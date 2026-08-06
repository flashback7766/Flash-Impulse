pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Makes changing the theme look deliberate instead of janky.
 *
 * Switching light/dark is not one operation, it is three, and only the first is
 * instant: a shell script runs matugen over the wallpaper (hundreds of
 * milliseconds of external process), it writes colors.json, and then
 * MaterialThemeLoader assigns some fifty properties onto Appearance.m3colors —
 * each of which invalidates every binding in the shell that reads it. So the UI
 * relayouts dozens of times in a row, after an unpredictable pause. That is the
 * stutter; no easing curve applied to it would help, because the frames simply
 * are not there to animate.
 *
 * So this does not animate the change. It hides it:
 *
 *   1. Freeze a copy of every screen, taken through the compositor rather than
 *      by shelling out to grim — no disk round-trip, no file to clean up.
 *   2. Show those frozen copies on top, so the desktop appears to stop.
 *   3. Run the switch underneath. All the relayout thrash happens behind an
 *      opaque image, where nobody can see it.
 *   4. Wait for the colours to actually land, then a beat longer for the
 *      bindings to settle.
 *   5. Only now animate: punch an expanding circular hole in the frozen copy so
 *      the finished new theme spreads out from wherever you clicked.
 *
 * The animation runs against a scene that has already finished changing, which
 * is the whole point — it is the one part of this that can be smooth, so it is
 * the only part allowed to be visible.
 */
Singleton {
    id: root

    // True only in the process that called ensureLoaded() — the shell. The
    // settings app has its own copy of every singleton, and two of these would
    // mean two overlays and two switches; it asks over IPC instead.
    property bool owns: false

    function ensureLoaded(): void {
        root.owns = true;
    }

    // 0 idle, 1 frozen (switch running), 2 revealing.
    property int phase: 0
    readonly property bool covering: root.phase === 1 || root.phase === 2
    property real reveal: 0

    // Where the new theme grows from, in the focused screen's pixels. Negative
    // means "no particular place" and the reveal starts from the centre.
    property real originX: -1
    property real originY: -1

    // What the theme was when we froze, so the wait below knows what "changed"
    // means rather than guessing on a timer.
    property bool wasDark: false
    property string pendingMode: ""

    readonly property bool enabled: Config.options?.appearance?.themeTransition ?? true

    function requestMode(mode: string, x: real, y: real): void {
        if (!root.owns) {
            Quickshell.execDetached(["qs", "-c", "flash-impulse", "ipc", "call", "theme", "switchTo", mode, Math.round(x).toString(), Math.round(y).toString()]);
            return;
        }
        root.begin(mode, x, y);
    }

    function begin(mode: string, x: real, y: real): void {
        // Already mid-transition: let the first one finish rather than stacking
        // two frozen copies and two scripts on top of each other.
        if (root.phase !== 0)
            return;

        const wantDark = mode === "dark";
        const alreadyThere = mode !== "auto" && wantDark === Appearance.m3colors.darkmode;

        if (!root.enabled || alreadyThere) {
            root.runSwitch(mode);
            return;
        }

        root.originX = x;
        root.originY = y;
        root.wasDark = Appearance.m3colors.darkmode;
        root.pendingMode = mode;
        root.reveal = 0;
        // Phase 1 mounts the overlays, which capture as they appear. The script
        // is started a frame later so the freeze is definitely up first — a
        // switch that lands before the cover does is the flicker this exists to
        // prevent.
        root.framesReady = 0;
        root.switchStarted = false;
        root.phase = 1;
        captureTimeout.restart();
        giveUpTimer.restart();
    }

    function runSwitch(mode: string): void {
        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${mode} --noswitch`]);
    }

    function finish(): void {
        root.phase = 0;
        root.framesReady = 0;
        root.switchStarted = false;
        captureTimeout.stop();
        root.reveal = 0;
        root.originX = -1;
        root.originY = -1;
        root.pendingMode = "";
        giveUpTimer.stop();
    }

    // Each overlay reports in once its frozen frame has actually arrived. The
    // capture is asynchronous, so a fixed delay here would be a guess — and a
    // guess that lost the race would start the switch before the screen was
    // covered, which is the exact flicker this is built to remove.
    property int framesReady: 0
    property bool switchStarted: false

    onFramesReadyChanged: root.maybeStartSwitch()

    function maybeStartSwitch(): void {
        if (root.phase !== 1 || root.switchStarted)
            return;
        if (root.framesReady < Quickshell.screens.length)
            return;
        root.switchStarted = true;
        root.runSwitch(root.pendingMode);
    }

    // A capture that never completes must not strand the desktop behind a blank
    // cover: go ahead uncovered rather than not at all.
    Timer {
        id: captureTimeout
        interval: 400
        onTriggered: {
            if (root.phase === 1 && !root.switchStarted) {
                console.warn("[ThemeTransition] Screen capture did not arrive; switching without the cover.");
                root.switchStarted = true;
                root.runSwitch(root.pendingMode);
            }
        }
    }

    // The colours have landed. Wait one more beat before animating: applyColors
    // sets its fifty properties in a loop, and starting the reveal in the middle
    // of that means animating across exactly the frames that are being dropped.
    Connections {
        target: Appearance.m3colors
        enabled: root.phase === 1
        function onDarkmodeChanged() {
            if (Appearance.m3colors.darkmode !== root.wasDark)
                settleTimer.restart();
        }
    }

    Timer {
        id: settleTimer
        interval: 90
        onTriggered: {
            if (root.phase !== 1)
                return;
            root.phase = 2;
            revealAnim.restart();
        }
    }

    NumberAnimation {
        id: revealAnim
        target: root
        property: "reveal"
        from: 0
        to: 1
        duration: Appearance.animationCurves.expressiveDefaultSpatialDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        onFinished: root.finish()
    }

    // If the switch fails — no matugen, a broken wallpaper path, a script that
    // exits non-zero — nothing ever changes the theme, and without this the
    // desktop would sit frozen behind a screenshot forever. Uncovering on a
    // wrong-looking screen beats not uncovering at all.
    Timer {
        id: giveUpTimer
        interval: 6000
        onTriggered: {
            if (root.phase === 1) {
                console.warn("[ThemeTransition] Theme did not change in time; uncovering.");
                root.finish();
            }
        }
    }

    IpcHandler {
        target: "theme"

        function toggleLightDark(): void {
            root.requestMode(Appearance.m3colors.darkmode ? "light" : "dark", -1, -1);
        }

        function switchTo(mode: string, x: string, y: string): string {
            root.begin(mode, parseFloat(x), parseFloat(y));
            return "ok";
        }
    }
}
