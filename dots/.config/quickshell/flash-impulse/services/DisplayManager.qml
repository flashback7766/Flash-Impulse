pragma Singleton

import qs.services
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Writes ~/.config/hypr/monitors.lua and applies it, with the safety net
 * Windows and KDE both put behind their own display-settings page: apply,
 * then ask "keep these settings?" with a countdown, and revert automatically
 * if nobody answers. A monitor change is the one settings category where
 * "it looked right in the editor" isn't good enough — the position, mode or
 * transform that seemed fine can leave the real screen unreadable or the
 * pointer walking off the edge of it, with no way back in.
 *
 * The whole flow runs *here*, in the shell process, and the settings app only
 * asks for it over IPC. That is not an arbitrary split: the settings app is a
 * separate process with its own copy of this singleton, so a countdown started
 * there would tick in an object the shell's confirmation overlay cannot see,
 * and would die with the window — which is precisely the moment you need it,
 * since a bad mode is a good way to lose the window you were clicking in.
 */
Singleton {
    id: root

    readonly property string monitorsLuaPath: FileUtils.trimFileProtocol(`${Directories.home}/.config/hypr/monitors.lua`)
    readonly property int confirmSeconds: 15

    property string previousConf: ""
    property bool confirmPending: false
    property int confirmSecondsLeft: 0

    // Called from shell.qml purely to construct this singleton, which is what
    // registers the IPC handler below. Lazy construction would mean the target
    // only exists once something happened to read a property here.
    function ensureLoaded(): void {}

    // One line per known output, keyed by name — existing entries for a
    // monitor that's unplugged right now are carried through untouched, so
    // reconnecting a laptop to yesterday's dock still finds its layout.
    /**
     * The file as an ordered list of entries, keeping everything.
     *
     * This used to return only the lines carrying `output = "..."`, and the file
     * was rebuilt from those alone — so every comment, blank line and any other
     * hl.* call the user had put in monitors.lua was silently deleted the first
     * time they touched a display setting. Nothing warned, because from the
     * page's side the write looked entirely successful.
     *
     * Entries are one of:
     *   monitor  — an hl.monitor line, keyed by its output name
     *   primary  — the hl.workspace_rule that marks the default screen
     *   other    — anything else, passed through untouched
     */
    function parseConfig(text) {
        const entries = [];
        for (const line of text.split("\n")) {
            const mo = line.match(/output\s*=\s*"([^"]+)"/);
            if (mo && line.includes("hl.monitor")) {
                entries.push({ kind: "monitor", key: mo[1], text: line });
                continue;
            }
            if (line.includes("hl.workspace_rule") && /default\s*=\s*true/.test(line)) {
                entries.push({ kind: "primary", text: line });
                continue;
            }
            entries.push({ kind: "other", text: line });
        }
        return entries;
    }

    /**
     * Hyprland has no "primary monitor" — hl.monitor rejects the field outright,
     * and `Hyprland --verify-config` treats an unknown field as a hard parse
     * error that takes the whole config down, not just the line. What the
     * setting actually means here is which screen workspace 1 lands on, and that
     * is a workspace rule.
     */
    function buildPrimaryLine(output) {
        return `hl.workspace_rule({ workspace = "1", monitor = "${output}", default = true })`;
    }

    function primaryFrom(text) {
        for (const entry of root.parseConfig(text)) {
            if (entry.kind !== "primary")
                continue;
            const m = entry.text.match(/monitor\s*=\s*"([^"]+)"/);
            if (m)
                return m[1];
        }
        return "";
    }

    // Every field name and value here was checked against
    // `Hyprland --verify-config`, which rejects an unknown field outright —
    // there is no silent-ignore path, so a typo would break the user's whole
    // Hyprland config, not just the monitor line.
    function buildLine(m) {
        let fields = `output = "${m.output}"`;
        if (m.disabled) {
            fields += `, disabled = true`;
            return `hl.monitor({ ${fields} })`;
        }
        fields += `, mode = "${m.modeStr}", position = "${m.x}x${m.y}"`;
        // "auto" is a real value for scale, distinct from any number — it lets
        // Hyprland pick a sensible fractional scale from the panel's DPI.
        fields += `, scale = ${m.scaleAuto ? '"auto"' : m.scale.toFixed(2)}`;
        if (m.transform) fields += `, transform = ${m.transform}`;
        if (m.vrr !== 0) fields += `, vrr = ${m.vrr}`;
        if (m.bitdepth !== 8) fields += `, bitdepth = ${m.bitdepth}`;
        if (m.cm && m.cm !== "auto") fields += `, cm = "${m.cm}"`;
        if (m.mirror) fields += `, mirror = "${m.mirror}"`;
        return `hl.monitor({ ${fields} })`;
    }

    // `edited` is an array of the buildLine() inputs above, one per monitor the
    // Displays page was showing (connected monitors only — parseOutputLines is
    // what preserves the rest).
    function applyMonitors(edited, primary) {
        // A blocking read, and an abort if it comes back empty while the file
        // is non-empty on disk. The first version read through an async
        // FileView that had not finished loading yet, got "" for the existing
        // config, and wrote a file containing only the monitors currently
        // plugged in — silently deleting the entry for a display that happened
        // to be unplugged at the time. Losing someone's dock layout because a
        // read had not landed yet is not an acceptable failure mode.
        const existing = monitorsFile.text();
        if (existing.length === 0 && !monitorsFile.loaded) {
            console.warn("[DisplayManager] Could not read monitors.lua; refusing to write over it.");
            return;
        }

        const entries = root.parseConfig(existing);

        // Rewrite the monitors that were edited, in place, and append the ones
        // the file has never seen.
        for (const m of edited) {
            const at = entries.findIndex(e => e.kind === "monitor" && e.key === m.output);
            if (at >= 0)
                entries[at].text = root.buildLine(m);
            else
                entries.push({ kind: "monitor", key: m.output, text: root.buildLine(m) });
        }

        // primary is undefined when the caller does not manage it — an older
        // settings build, or an IPC call from a script — and then the existing
        // rule is left exactly as it is rather than being dropped.
        if (primary !== undefined) {
            const at = entries.findIndex(e => e.kind === "primary");
            if (primary && primary.length > 0) {
                const line = root.buildPrimaryLine(primary);
                if (at >= 0)
                    entries[at].text = line;
                else
                    entries.push({ kind: "primary", text: line });
            } else if (at >= 0) {
                entries.splice(at, 1);
            }
        }

        root.previousConf = existing;
        root.reloadWhenSaved = true;
        root.confirmAfterReload = true;
        // Joined without adding a trailing newline: splitting on "\n" already
        // produced a final empty entry for it, and adding another grew the file
        // by one blank line on every single apply.
        monitorsFile.setText(entries.map(e => e.text).join("\n"));
    }

    // setText() writes asynchronously, so telling Hyprland to reload on the very
    // next line is a race it can lose — it re-reads the file, finds the old
    // content still there, and the change appears not to have happened. Caught
    // on the revert path, where the file was correct on disk but the display
    // stayed 10-bit until something else triggered a second reload.
    property bool reloadWhenSaved: false
    property bool confirmAfterReload: false

    function startConfirm() {
        root.confirmSecondsLeft = root.confirmSeconds;
        root.confirmPending = true;
        confirmTimer.restart();
    }

    function confirmKeep() {
        confirmTimer.stop();
        root.confirmPending = false;
    }

    function revertNow() {
        confirmTimer.stop();
        root.confirmPending = false;
        if (root.previousConf.length === 0)
            return;
        root.reloadWhenSaved = true;
        root.confirmAfterReload = false;
        monitorsFile.setText(root.previousConf);
    }

    Timer {
        id: confirmTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.confirmSecondsLeft -= 1;
            if (root.confirmSecondsLeft <= 0)
                root.revertNow();
        }
    }

    FileView {
        id: monitorsFile
        path: Qt.resolvedUrl(root.monitorsLuaPath)
        // Synchronous reads. Everything this service does with the file is
        // read-modify-write, and a read that has not landed yet reads as an
        // empty file, which is indistinguishable from "no monitors configured".
        blockLoading: true
        preload: true
        // Write to a temp file and rename, so Hyprland can never catch this
        // mid-write and parse half a config.
        atomicWrites: true

        onSaved: {
            if (!root.reloadWhenSaved)
                return;
            root.reloadWhenSaved = false;
            Quickshell.execDetached(["hyprctl", "reload"]);
            if (root.confirmAfterReload) {
                root.confirmAfterReload = false;
                root.startConfirm();
            }
        }
        onSaveFailed: err => {
            root.reloadWhenSaved = false;
            root.confirmAfterReload = false;
            console.warn(`[DisplayManager] Could not write monitors.lua (${err}); nothing applied.`);
        }
    }

    // The settings app talks to this rather than doing the work itself; see the
    // note at the top for why the countdown has to live in the shell.
    IpcHandler {
        target: "display"

        // Base64, not raw JSON. Quickshell's `ipc call` CLI reads a bracketed
        // argument as a list literal: `[{"a":1}]` arrives as `{"a":1}` with the
        // outer brackets eaten, and `[1,2]` arrives as two separate arguments.
        // Base64's alphabet has no brackets or commas, so it survives intact.
        function apply(specBase64: string): string {
            try {
                const spec = JSON.parse(Qt.atob(specBase64));
                // Two accepted shapes. A bare array is monitors only and leaves
                // any existing primary rule alone — that is what a script or an
                // older settings build sends, and it must not silently drop a
                // setting it does not know about. An object also carries the
                // primary, where "" means "no default screen".
                if (Array.isArray(spec)) {
                    root.applyMonitors(spec, undefined);
                    return "ok";
                }
                if (spec && Array.isArray(spec.monitors)) {
                    root.applyMonitors(spec.monitors, spec.primary ?? "");
                    return "ok";
                }
                return "expected a JSON array, or an object with a monitors array";
            } catch (e) {
                return `bad spec: ${e.message}`;
            }
        }

        // What the config currently marks as the default screen, so the settings
        // page can seed its control without parsing monitors.lua itself.
        function primary(): string {
            return root.primaryFrom(monitorsFile.text());
        }

        function keep(): string {
            root.confirmKeep();
            return "ok";
        }

        function revert(): string {
            root.revertNow();
            return "ok";
        }
    }
}
