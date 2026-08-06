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
 * whether a game is *actually* running now, and a stale one is undone.
 *
 * ## One owner
 *
 * Singletons are per-process, and the settings app is its own process. Left
 * ungated, opening Settings would start a second gdbus monitor, a second
 * reconciliation, and a second opinion about whether game mode is on — two
 * processes applying and undoing the same global settings. Only the shell calls
 * ensureLoaded(), so only the shell watches and acts; everyone else reads the
 * state out of the same file and asks over IPC to change it.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.gameMode ?? null

    // True only in the process that called ensureLoaded() — the shell.
    property bool owns: false

    // A game registered with Feral GameMode. Independent of the manual toggle.
    property bool gamemodedActive: false
    // The quick toggle in the sidebar and in settings.
    property bool manualEnabled: false
    // What the owner last wrote to the state file. The only thing a process
    // that isn't the owner has any business believing.
    property bool publishedActive: false
    property bool publishedGamemoded: false

    // Whether a game is running, answered correctly in any process: the owner
    // knows first-hand, everyone else reads what it published. Without this the
    // settings app would always claim no game was running, since only the owner
    // watches gamemoded.
    readonly property bool gameRunning: root.owns ? root.gamemodedActive : root.publishedGamemoded

    readonly property bool active: root.owns ? (root.manualEnabled || (root.gamemodedActive && (root.opts?.followGamemoded ?? true))) : root.publishedActive

    // Set while startup reconciliation is still deciding, so the normal
    // active-changed path doesn't fire against a half-known world.
    property bool reconciling: true

    readonly property string statePath: FileUtils.trimFileProtocol(`${Directories.state}/user/gamemode-state.json`)

    // Called from shell.qml. Constructing the singleton is what starts the
    // watching, and claiming ownership is what makes it the one that acts.
    function ensureLoaded(): void {
        root.owns = true;
    }

    // Anything that isn't the owner asks it to flip the switch.
    function requestManual(value: bool): void {
        if (root.owns) {
            root.manualEnabled = value;
            return;
        }
        Quickshell.execDetached(["qs", "-c", "flash-impulse", "ipc", "call", "gamemode", value ? "on" : "off"]);
    }

    // ---------------------------------------------------------------- apply --
    function compositorOn(): void {
        const o = root.opts;
        const kw = [];
        if (o?.disableAnimations ?? true)
            kw.push("keyword animations:enabled 0");
        if (o?.disableShadows ?? true)
            kw.push("keyword decoration:shadow:enabled 0");
        if (o?.disableBlur ?? true)
            kw.push("keyword decoration:blur:enabled 0");
        if (o?.noGaps ?? true)
            kw.push("keyword general:gaps_in 0", "keyword general:gaps_out 0", "keyword general:border_size 1");
        if (o?.squareCorners ?? true)
            kw.push("keyword decoration:rounding 0");
        if (o?.allowTearing ?? true)
            kw.push("keyword general:allow_tearing 1");
        if (kw.length === 0)
            return;
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
        if (!(root.opts?.performanceMode ?? true)) {
            stateFile.publish();
            return;
        }
        // Record before changing, and only if there is nothing recorded yet —
        // entering twice (toggle on, then a game starts) must not overwrite the
        // original value with the one we ourselves just set.
        if (!stateFile.hasRecord)
            stateFile.previousPerformanceMode = PerformanceMode.enabled;
        stateFile.hasRecord = true;
        stateFile.publish();
        PerformanceMode.setEnabled(true);
    }

    function leave(): void {
        root.compositorOff();
        if (!stateFile.hasRecord) {
            stateFile.publish();
            return;
        }
        const previous = stateFile.previousPerformanceMode;
        stateFile.hasRecord = false;
        stateFile.publish();
        PerformanceMode.setEnabled(previous);
    }

    onGamemodedActiveChanged: {
        // `active` may not change at all here — a game starting while the manual
        // toggle is already on leaves it true — but the settings app still needs
        // to know a game is running, so publish regardless.
        if (root.owns && !root.reconciling)
            stateFile.publish();
    }

    onActiveChanged: {
        if (!root.owns || root.reconciling)
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
        running: root.owns
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
        running: root.owns && (root.opts?.followGamemoded ?? true)
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
        if (!root.owns || !stateFile.ready)
            return; // Called again once the pieces are in place.
        // Wait for the real performance-mode state. Its `enabled` defaults to
        // false, so acting before the first status read means restoring "false"
        // onto a value that is already believed to be false — which setEnabled()
        // correctly treats as a no-op, leaving the low-end profile on with the
        // record cleared and nothing left to notice it.
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
        if (stateFile.hasRecord) {
            const previous = stateFile.previousPerformanceMode;
            stateFile.hasRecord = false;
            console.log(`[GameMode] Stale game-mode state found; restoring performance mode to ${previous}.`);
            PerformanceMode.setEnabled(previous);
        }
        stateFile.publish();
    }

    Connections {
        target: PerformanceMode
        function onLoadedChanged() {
            if (PerformanceMode.loaded)
                root.reconcile();
        }
    }

    FileView {
        id: stateFile
        path: Qt.resolvedUrl(root.statePath)
        // Read synchronously: reconcile() runs once at startup and has to make a
        // decision, not schedule one.
        blockLoading: true
        preload: true
        atomicWrites: true
        // Non-owners follow along by watching this rather than by guessing.
        watchChanges: true
        // The file legitimately doesn't exist most of the time.
        printErrors: false

        property bool hasRecord: false
        property bool previousPerformanceMode: false
        property bool ready: false

        function parse(): void {
            try {
                const text = stateFile.text();
                if (text.trim().length > 0) {
                    const data = JSON.parse(text);
                    root.publishedActive = data.active === true;
                    root.publishedGamemoded = data.gameRunning === true;
                    // A non-owner must not adopt the owner's manual flag as its
                    // own — `active` above is what it reads, and manualEnabled
                    // staying false keeps requestManual() going over IPC.
                    if (root.owns)
                        root.manualEnabled = data.manualEnabled === true;
                    stateFile.hasRecord = data.restore !== undefined && data.restore !== null;
                    stateFile.previousPerformanceMode = stateFile.hasRecord && data.restore.previousPerformanceMode === true;
                } else {
                    root.publishedActive = false;
                    root.publishedGamemoded = false;
                    stateFile.hasRecord = false;
                }
            } catch (e) {
                console.warn("[GameMode] Unreadable state file; ignoring it.");
                stateFile.hasRecord = false;
            }
            stateFile.ready = true;
            root.reconcile();
        }

        // Only the owner writes. Publishing `active` is what lets the settings
        // app show the right thing without running a second copy of all this.
        function publish(): void {
            if (!root.owns)
                return;
            const data = {
                active: root.active,
                manualEnabled: root.manualEnabled,
                gameRunning: root.gamemodedActive
            };
            if (stateFile.hasRecord)
                data.restore = {
                    previousPerformanceMode: stateFile.previousPerformanceMode
                };
            stateFile.setText(JSON.stringify(data));
        }

        onLoaded: stateFile.parse()
        onFileChanged: stateFile.reload()
        onLoadFailed: {
            // No file is the normal case — nothing was interrupted.
            root.publishedActive = false;
            stateFile.hasRecord = false;
            stateFile.ready = true;
            root.reconcile();
        }
    }

    IpcHandler {
        target: "gamemode"

        function on(): string {
            root.manualEnabled = true;
            return "ok";
        }

        function off(): string {
            root.manualEnabled = false;
            return "ok";
        }

        function toggle(): string {
            root.manualEnabled = !root.manualEnabled;
            return root.manualEnabled ? "on" : "off";
        }

        function status(): string {
            return root.active ? "on" : "off";
        }
    }
}
