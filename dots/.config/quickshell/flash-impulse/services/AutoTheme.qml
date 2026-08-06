pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Follows the time of day: light while the sun is up, dark once it sets.
 *
 * Two ways to decide when that is — a schedule you type in, or real sunrise and
 * sunset. The second one needs coordinates, and rather than ask for them, it
 * takes them from the system timezone: a zone name is a city, and zone1970.tab
 * ships that city's latitude and longitude. No network, no API key, nothing to
 * configure — and it stays right when you travel and change the clock.
 *
 * Switching is edge-triggered, on purpose. It fires when the sun actually
 * crosses, not on every tick, so if you override the theme by hand at midnight
 * it stays overridden until sunrise instead of snapping back a minute later.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.appearance?.autoTheme
    readonly property bool enabled: (opts?.enable ?? false) && (Config?.ready ?? false)
    readonly property string mode: opts?.mode ?? "sun"

    // Coordinates in use, once resolved. Latitude north-positive, longitude
    // east-positive, as everything below assumes.
    property real latitude: NaN
    property real longitude: NaN
    property string locationName: ""
    readonly property bool hasLocation: !isNaN(root.latitude) && !isNaN(root.longitude)

    // Today's crossings, as Date objects. Null above the polar circles on the
    // days the sun does not bother to set, which is why the schedule is the
    // fallback rather than an error.
    property var sunriseTime: null
    property var sunsetTime: null
    readonly property bool usingSun: root.mode === "sun" && root.sunriseTime !== null && root.sunsetTime !== null

    readonly property string sunriseText: root.sunriseTime ? Qt.formatTime(root.sunriseTime, "hh:mm") : "--:--"
    readonly property string sunsetText: root.sunsetTime ? Qt.formatTime(root.sunsetTime, "hh:mm") : "--:--"

    property bool shouldBeDark: false
    property bool evaluated: false

    // ------------------------------------------------------------ location --
    function parseIso6709(s) {
        // "+4011+04430" or "+554521+0373704": degrees, minutes, optional seconds.
        const m = s.match(/^([+-])(\d{2})(\d{2})(\d{2})?([+-])(\d{3})(\d{2})(\d{2})?$/);
        if (!m)
            return null;
        const lat = (m[1] === "-" ? -1 : 1) * (Number(m[2]) + Number(m[3]) / 60 + Number(m[4] ?? 0) / 3600);
        const lon = (m[5] === "-" ? -1 : 1) * (Number(m[6]) + Number(m[7]) / 60 + Number(m[8] ?? 0) / 3600);
        return {
            lat: lat,
            lon: lon
        };
    }

    function resolveLocation() {
        const raw = (root.opts?.location ?? "").trim();
        const coords = raw.match(/^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$/);
        if (coords) {
            root.latitude = Number(coords[1]);
            root.longitude = Number(coords[2]);
            root.locationName = `${root.latitude.toFixed(2)}, ${root.longitude.toFixed(2)}`;
            root.recompute();
            return;
        }
        locationProc.zone = raw; // empty means "ask the system"
        locationProc.running = false;
        locationProc.running = true;
    }

    Process {
        id: locationProc
        property string zone: ""
        command: ["bash", "-c", `
            zone="$1"
            [ -z "$zone" ] && zone=$(readlink -f /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
            [ -z "$zone" ] && zone="$TZ"
            for f in /usr/share/zoneinfo/zone1970.tab /usr/share/zoneinfo/zone.tab; do
                [ -r "$f" ] || continue
                c=$(awk -F'\t' -v z="$zone" '/^#/ { next } $3 == z { print $2; exit }' "$f")
                [ -n "$c" ] && { printf '%s\t%s\n' "$zone" "$c"; exit 0; }
            done
            printf '%s\t\n' "$zone"
        `, "bash", locationProc.zone]
        stdout: StdioCollector {
            id: locationCollector
            onStreamFinished: {
                const parts = locationCollector.text.trim().split("\t");
                const zone = parts[0] ?? "";
                const parsed = parts.length > 1 ? root.parseIso6709(parts[1] ?? "") : null;
                if (parsed) {
                    root.latitude = parsed.lat;
                    root.longitude = parsed.lon;
                    root.locationName = zone;
                } else {
                    // Unknown zone: no coordinates, so the sun mode has nothing to
                    // work with and the schedule takes over.
                    root.latitude = NaN;
                    root.longitude = NaN;
                    root.locationName = zone;
                }
                root.recompute();
            }
        }
    }

    // ----------------------------------------------------------- sun times --
    // NOAA's sunrise equation, the same arrangement SunCalc uses. Accurate to
    // well under a minute, which is far more than a wallpaper needs.
    function sunTimes(date, lat, lon) {
        const rad = Math.PI / 180;
        const dayMs = 86400000;
        const J1970 = 2440588;
        const J2000 = 2451545;
        const J0 = 0.0009;

        const toDays = d => d.valueOf() / dayMs - 0.5 + J1970 - J2000;
        const fromJulian = j => new Date((j + 0.5 - J1970) * dayMs);

        const lw = rad * -lon;
        const phi = rad * lat;
        const d = toDays(date);

        const n = Math.round(d - J0 - lw / (2 * Math.PI));
        const ds = J0 + (0 + lw) / (2 * Math.PI) + n;

        const M = rad * (357.5291 + 0.98560028 * ds);
        const C = rad * (1.9148 * Math.sin(M) + 0.02 * Math.sin(2 * M) + 0.0003 * Math.sin(3 * M));
        const L = M + C + rad * 102.9372 + Math.PI;
        const dec = Math.asin(Math.sin(rad * 23.4397) * Math.sin(L));

        const jNoon = J2000 + ds + 0.0053 * Math.sin(M) - 0.0069 * Math.sin(2 * L);

        // -0.833°: the sun's disc is half a degree wide and the atmosphere bends
        // it up by another third, so it looks set slightly before it is.
        const h = -0.833 * rad;
        const cosOmega = (Math.sin(h) - Math.sin(phi) * Math.sin(dec)) / (Math.cos(phi) * Math.cos(dec));
        if (cosOmega > 1 || cosOmega < -1)
            return null; // Polar night or midnight sun — no crossing today.

        const omega = Math.acos(cosOmega);
        const jSet = J2000 + (J0 + (omega + lw) / (2 * Math.PI) + n) + 0.0053 * Math.sin(M) - 0.0069 * Math.sin(2 * L);
        const jRise = jNoon - (jSet - jNoon);

        return {
            rise: fromJulian(jRise),
            set: fromJulian(jSet)
        };
    }

    function minutesOf(date) {
        return date.getHours() * 60 + date.getMinutes();
    }

    function parseClock(s, fallback) {
        const m = (s ?? "").match(/^(\d{1,2}):(\d{2})$/);
        if (!m)
            return fallback;
        return Math.min(23, Number(m[1])) * 60 + Math.min(59, Number(m[2]));
    }

    // ------------------------------------------------------------ decision --
    property int clockMinute: DateTime.clock.minutes
    property int clockHour: DateTime.clock.hours
    onClockMinuteChanged: root.recompute()

    function recompute() {
        const now = DateTime.clock.date;

        if (root.mode === "sun" && root.hasLocation) {
            const t = root.sunTimes(now, root.latitude, root.longitude);
            root.sunriseTime = t?.rise ?? null;
            root.sunsetTime = t?.set ?? null;
        } else {
            root.sunriseTime = null;
            root.sunsetTime = null;
        }

        let lightAt, darkAt;
        if (root.usingSun) {
            lightAt = root.minutesOf(root.sunriseTime);
            darkAt = root.minutesOf(root.sunsetTime);
        } else {
            lightAt = root.parseClock(root.opts?.lightTime, 7 * 60);
            darkAt = root.parseClock(root.opts?.darkTime, 19 * 60);
        }

        const t = root.clockHour * 60 + root.clockMinute;
        // Light runs from lightAt up to darkAt, wrapping across midnight if the
        // two are the other way round.
        const light = lightAt <= darkAt ? (t >= lightAt && t < darkAt) : (t >= lightAt || t < darkAt);
        root.shouldBeDark = !light;
        root.evaluated = true;
    }

    function apply() {
        if (!root.enabled)
            return;
        if (Appearance.m3colors.darkmode === root.shouldBeDark)
            return;
        // Sunset and sunrise get the same treatment: this fires while you are
        // looking at something else, and a silent relayout storm is exactly the
        // kind of thing that reads as the machine hiccupping.
        ThemeTransition.requestMode(root.shouldBeDark ? "dark" : "light", -1, -1);
    }

    // The crossing itself. Anything the user did by hand before now is over.
    onShouldBeDarkChanged: {
        if (root.evaluated)
            root.apply();
    }

    // Turning it on, or changing how it decides, should snap the theme to match
    // right away rather than wait for the next sunset.
    onEnabledChanged: if (root.enabled) settleTimer.restart()
    onModeChanged: root.resolveLocation()

    Connections {
        target: root.opts ?? null
        enabled: root.opts !== undefined && root.opts !== null
        function onLocationChanged() {
            root.resolveLocation();
        }
        function onLightTimeChanged() {
            root.recompute();
            settleTimer.restart();
        }
        function onDarkTimeChanged() {
            root.recompute();
            settleTimer.restart();
        }
    }

    Timer {
        // The colours are read from a generated file, so at startup m3colors is
        // whatever the last run left behind; give it a moment to land before
        // deciding the theme is wrong and rewriting it.
        id: settleTimer
        interval: 1200
        onTriggered: root.apply()
    }

    function load() {
        root.resolveLocation();
        if (root.enabled)
            settleTimer.restart();
    }

    // A day rolls over: recompute so sunrise and sunset are today's, not
    // yesterday's. Cheap enough to just do hourly.
    Timer {
        running: root.enabled
        interval: 3600000
        repeat: true
        onTriggered: root.recompute()
    }

    IpcHandler {
        target: "autoTheme"

        function status(): string {
            return `${root.enabled ? "on" : "off"} mode=${root.mode} location=${root.locationName || "?"} ` + `lat=${root.latitude.toFixed(3)} lon=${root.longitude.toFixed(3)} ` + `sunrise=${root.sunriseText} sunset=${root.sunsetText} -> ${root.shouldBeDark ? "dark" : "light"}`;
        }

        function toggle(): void {
            Config.options.appearance.autoTheme.enable = !Config.options.appearance.autoTheme.enable;
        }
    }
}
