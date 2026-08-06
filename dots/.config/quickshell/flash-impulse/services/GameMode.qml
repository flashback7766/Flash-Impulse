pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Game mode: strips the compositor down while a game is running, and puts it
 * back afterwards.
 *
 * Two things can turn it on — the quick toggle in the right sidebar, and Feral
 * GameMode noticing a game start — and they are deliberately one state rather
 * than two. Two independent switches onto the same compositor settings means
 * whichever turns off last wins, so quitting a game after having toggled it by
 * hand would silently undo the manual choice.
 *
 * The interesting problem here is not turning things off, it is turning them
 * back on again afterwards *reliably*. The compositor tweaks are set with
 * `hyprctl keyword`, which lives only in the running Hyprland — a reboot, or a
 * `hyprctl reload`, restores them for free. Performance mode does not work that
 * way: it writes `performanceMode = true` into custom/variables.lua on purpose,
 * so it survives a restart. Which means a machine that reboots, crashes or
 * loses power with a game running would come back permanently in the low-end
 * profile, with nothing on screen explaining why the desktop looks cheap.
 *
 * So the auto-enable records what it is about to overwrite, in a file outside
 * the config it is overwriting. On startup that file is reconciled against
 * whether a game is *actually* running now, and a stale one is undone. The
 * state file is the thing that makes this safe to leave running unattended.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.gameMode ?? null

    // A game registered with Feral GameMode. Independent of the manual toggle.
    property bool gamemodedActive: false
    // The quick toggle in the sidebar.
    property bool manualEnabled: false

    readonly property bool active: root.manualEnabled || (root.gamemodedActive && (root.opts?.followGamemoded ?? true))

    // Set while startup reconciliation is still deciding, so the normal
    // active-changed path doesn't fire against a half-known world.
    property bool reconciling: true

    readonly property string restorePath: FileUtils.trimFileProtocol(`${Directories.state}/user/gamemode-restore.json`)

    // Called from shell.qml to construct this singleton at startup, which is
    // what runs the reconciliation below. Waiting for a toggle to be looked at
    // would mean a stale low-end profile sits there until someone opens the
    // sidebar — exactly the case this is meant to clean up.
    function ensureLoaded(): void {}

    // ---------------------------------------------------------------- apply --
    function compositorOn(): void {
        const o = root.opts;
        const kw = [];
        if (o?.disableAnimations ?? true) kw.push("keyword animations:enabled 0");
        if (o?.disableShadows ?? true) kw.push("keyword decoration:shadow:enabled 0");
        if (o?.disableBlur ?? true) kw.push("keyword decoration:blur:enabled 0");
        if (o?.noGaps ?? true) kw.push("keyword general:gaps_in 0", "keyword general:gaps_out 0", "keyword general:border_size 1");
        if (o?.squareCorners ?? true) kw.push("keyword decoration:rounding 0");
        if (o?.allowTearing ?? true) kw.push("keyword general:allow_tearing 1");
        if (kw.length === 0) return;
        Quickshell.execDetached(["hyprctl", "--batch", kw.join("; ")]);
    }

    function compositorOff(): void {
        // Everything above was a live keyword override, and a reload is what
        // drops all of them at once — including any this build didn't set,
        // which matters if the option list changes between sessions.
        Quickshell.execDetached(["hyprctl", "reload"]);
    }

    // ------------------------------------------------------------ transition --
    function enter(): void {
        root.compositorOn();
        if (!(root.opts?.performanceMode ?? true))
            return;
        // Record before changing, and only if there is nothing recorded yet —
        // entering twice (toggle on, then a game starts) must not overwrite the
        // original value with the one we ourselves just set.
        if (!restoreFile.hasRecord)
            restoreFile.record(PerformanceMode.enabled);
        PerformanceMode.setEnabled(true);
    }

    function leave(): void {
        root.compositorOff();
        if (!restoreFile.hasRecord)
            return;
        const previous = restoreFile.previousPerformanceMode;
        restoreFile.clear();
        PerformanceMode.setEnabled(previous);
    }

    onActiveChanged: {
        if (root.reconciling)
            return;
        if (root.active)
            root.enter();
        else
            root.leave();
    }

    // ------------------------------------------------------------- discovery --
    // Whether a game is running *right now*, asked once at startup. The monitor
    // below only reports changes, so without this a shell restarted while a
    // game is already running would believe nothing was going on.
    Process {
        id: initialQuery
        running: true
        command: ["bash", "-c", "busctl --user get-property com.feralinteractive.GameMode /com/feralinteractive/GameMode com.feralinteractive.GameMode ClientCount 2>/dev/null | awk '{print $2}'"]
        stdout: StdioCollector {
            id: initialOut
            onStreamFinished: {
                root.gamemodedActive = parseInt(initialOut.text.trim(), 10) > 0;
                root.reconcile();
            }
        }
        onExited: exitCode => {
            // gamemoded not running at all: no games, by definition.
            if (exitCode !== 0) {
                root.gamemodedActive = false;
                root.reconcile();
            }
        }
    }

    Process {
        id: monitor
        running: (root.opts?.followGamemoded ?? true)
        command: ["gdbus", "monitor", "--session", "--dest", "com.feralinteractive.GameMode"]
        stdout: SplitParser {
            onRead: line => {
                // "…PropertiesChanged ('com.feralinteractive.GameMode', {'ClientCount': <1>}, @as [])"
                const m = line.match(/'ClientCount':\s*<(\d+)>/);
                if (m) {
                    root.gamemodedActive = parseInt(m[1], 10) > 0;
                    return;
                }
                // The daemon exiting is not a PropertiesChanged — it just stops
                // owning the name, and any game it was tracking is gone with it.
                if (line.includes("does not have an owner") || line.includes("is not owned"))
                    root.gamemodedActive = false;
            }
        }
    }

    // ----------------------------------------------------------- reconciling --
    function reconcile(): void {
        if (!restoreFile.loaded)
            return; // Called again from onLoaded.
        // And wait for the real performance-mode state. Its `enabled` defaults
        // to false, so acting before the first status read means restoring
        // "false" onto a value that is already believed to be false — which
        // setEnabled() correctly treats as a no-op, leaving the low-end profile
        // on with the record cleared and nothing left to notice it.
        if (!PerformanceMode.loaded)
            return; // Called again from the Connections below.
        root.reconciling = false;

        if (root.active) {
            // A game is already running (shell restarted under it). Make sure
            // the settings match, and record the pre-game value if we hadn't.
            root.enter();
            return;
        }

        // Nothing running. A leftover record means the session ended while a
        // game was — reboot, crash, power loss — so undo what was never undone.
        if (restoreFile.hasRecord) {
            const previous = restoreFile.previousPerformanceMode;
            restoreFile.clear();
            console.log(`[GameMode] Stale game-mode state found; restoring performance mode to ${previous}.`);
            PerformanceMode.setEnabled(previous);
        }
    }

    Connections {
        target: PerformanceMode
        function onLoadedChanged() {
            if (PerformanceMode.loaded)
                root.reconcile();
        }
    }

    FileView {
        id: restoreFile
        path: Qt.resolvedUrl(root.restorePath)
        // Read synchronously: reconcile() runs once at startup and has to make a
        // decision, not schedule one.
        blockLoading: true
        preload: true
        atomicWrites: true
        // The file legitimately doesn't exist most of the time.
        printErrors: false

        property bool hasRecord: false
        property bool previousPerformanceMode: false
        property bool loaded: false

        function parse(): void {
            restoreFile.hasRecord = false;
            try {
                const text = restoreFile.text();
                if (text.trim().length > 0) {
                    const data = JSON.parse(text);
                    restoreFile.previousPerformanceMode = data.previousPerformanceMode === true;
                    restoreFile.hasRecord = true;
                }
            } catch (e) {
                console.warn("[GameMode] Unreadable restore state; ignoring it.");
            }
            restoreFile.loaded = true;
            root.reconcile();
        }

        function record(previous: bool): void {
            restoreFile.previousPerformanceMode = previous;
            restoreFile.hasRecord = true;
            restoreFile.setText(JSON.stringify({
                previousPerformanceMode: previous
            }));
        }

        function clear(): void {
            restoreFile.hasRecord = false;
            // Emptied rather than deleted: an empty file parses as "no record"
            // just the same, and FileView has no delete.
            restoreFile.setText("");
        }

        onLoaded: restoreFile.parse()
        onLoadFailed: {
            // No file is the normal case — nothing was interrupted.
            restoreFile.loaded = true;
            root.reconcile();
        }
    }
}
