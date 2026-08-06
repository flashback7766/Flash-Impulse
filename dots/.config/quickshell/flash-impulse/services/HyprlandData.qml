pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})

    // A monitor that comes out of the lock screen (or, rarely, a monitor
    // reload) can get stuck reporting an activeWorkspace.id near INT32_MAX
    // instead of a real one — the comment further down already knew about
    // this for the workspace *list*, but nothing recovered a monitor that
    // actually landed on one. Every widget that does arithmetic on the raw
    // id (workspace grouping, "group * shownCount + index") multiplies that
    // huge number out across a whole row of pills, which is what turns the
    // bar into a wall of overlapping digits until something switches that
    // monitor to a real workspace by hand.
    readonly property int workspaceIdSaneMax: 100
    property var phantomRecoveryCooldown: ({}) // monitor name -> Date.now() of last attempt

    function recoverPhantomWorkspaces() {
        const now = Date.now();
        const toRecover = [];
        for (const m of root.monitors) {
            const id = m?.activeWorkspace?.id;
            if (id === undefined || id === null || id <= root.workspaceIdSaneMax) continue;
            const last = root.phantomRecoveryCooldown[m.name] ?? 0;
            if (now - last < 3000) continue; // already tried this monitor moments ago
            root.phantomRecoveryCooldown[m.name] = now;
            toRecover.push(m.name);
        }
        if (toRecover.length === 0) return;

        // Pick a workspace nobody is sitting on. Moving a monitor onto one that
        // already lives on another output makes Hyprland *swap* the two, which
        // during a two-monitor recovery hands the phantom straight back to the
        // display just fixed — and even with one phantom, aiming blindly at
        // workspace 1 shoves whichever monitor legitimately had it. So skip
        // every id currently claimed by a healthy monitor, and hand out the
        // lowest free ones.
        const taken = new Set(root.monitors
            .map(m => m?.activeWorkspace?.id)
            .filter(id => id >= 1 && id <= root.workspaceIdSaneMax));
        const targets = [];
        let candidate = 1;
        for (const name of toRecover) {
            while (taken.has(candidate)) candidate++;
            taken.add(candidate);
            targets.push({ name: name, workspace: candidate });
        }
        for (const t of targets)
            console.warn(`[HyprlandData] Monitor "${t.name}" is on a phantom workspace — recovering to workspace ${t.workspace}.`);

        // All of them in one script rather than one exec() per monitor:
        // recoverProc is a single Process, and exec()ing it again while it is
        // still running restarts it instead of queueing, which would drop
        // every monitor but the last.
        //
        // Two dispatches per monitor, because hl.dsp.focus({ workspace,
        // monitor }) as a single call moves focus to `monitor` and silently
        // ignores `workspace` — established by trying it, it is not written
        // down anywhere. The legacy `focusmonitor <name>` form isn't valid
        // syntax at all under this Lua-configured Hyprland: it errors out, so
        // with `&&` the workspace switch chained after it never ran.
        const steps = targets.map(t =>
            `hyprctl dispatch "hl.dsp.focus({ monitor = '${t.name}' })" && hyprctl dispatch "hl.dsp.focus({ workspace = ${t.workspace} })"`
        );

        // Recovery has to focus each monitor it fixes, so hand focus back to
        // wherever it was — otherwise a phantom on the display you *aren't*
        // using yanks your keyboard onto the one you are not looking at.
        const focused = root.monitors.find(m => m.focused);
        const returnable = focused && !toRecover.includes(focused.name);
        if (returnable)
            steps.push(`hyprctl dispatch "hl.dsp.focus({ monitor = '${focused.name}' })"`);

        recoverProc.exec(["bash", "-c", steps.join(" ; ")]);
    }

    Process {
        id: recoverProc
    }

    // The recovery above rides on updateMonitors(), which normally only runs
    // off Hyprland's own event stream (onRawEvent). Right after an unlock the
    // compositor may sit on a phantom workspace for a while before anything
    // else happens to trigger an event, so this is the backstop that notices
    // regardless. Monitor polling is cheap — a couple of monitors' worth of
    // JSON — so 4s is frequent enough to matter without being wasteful.
    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: root.updateMonitors()
    }

    // Convenient stuff

    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const address = `0x${toplevel.HyprlandToplevel?.address}`;
            var win = HyprlandData.windowByAddress[address];
            return win?.workspace?.id === workspace;
        })
    }

    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }

    function clientForToplevel(toplevel) {
        if (!toplevel || !toplevel.HyprlandToplevel) {
            return null;
        }
        const address = `0x${toplevel?.HyprlandToplevel?.address}`;
        return root.windowByAddress[address];
    }

    // Internals

    function updateWindowList() {
        getClients.running = true;
    }

    function updateLayers() {
        getLayers.running = true;
    }

    function updateMonitors() {
        getMonitors.running = true;
    }

    function updateWorkspaces() {
        getWorkspaces.running = true;
        getActiveWorkspace.running = true;
    }

    function updateAll() {
        updateWindowList();
        updateMonitors();
        updateLayers();
        updateWorkspaces();
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    Component.onCompleted: {
        updateAll();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            // console.log("Hyprland raw event:", event.name);
            if (["openlayer", "closelayer", "screencast"].includes(event.name)) return;
            updateAll()
        }
    }

    Process {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            id: clientsCollector
            onStreamFinished: {
                root.windowList = JSON.parse(clientsCollector.text)
                let tempWinByAddress = {};
                for (var i = 0; i < root.windowList.length; ++i) {
                    var win = root.windowList[i];
                    tempWinByAddress[win.address] = win;
                }
                root.windowByAddress = tempWinByAddress;
                root.addresses = root.windowList.map(win => win.address);
            }
        }
    }

    Process {
        id: getMonitors
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                root.monitors = JSON.parse(monitorsCollector.text);
                root.recoverPhantomWorkspaces();
            }
        }
    }

    Process {
        id: getLayers
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            id: layersCollector
            onStreamFinished: {
                root.layers = JSON.parse(layersCollector.text);
            }
        }
    }

    Process {
        id: getWorkspaces
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            id: workspacesCollector
            onStreamFinished: {
                var rawWorkspaces = JSON.parse(workspacesCollector.text);
                // Filter out invalid workspace ids (e.g. lock-screen temp workspace 2147483647 - N)
                root.workspaces = rawWorkspaces.filter(ws => ws.id >= 1 && ws.id <= 100);
                let tempWorkspaceById = {};
                for (var i = 0; i < root.workspaces.length; ++i) {
                    var ws = root.workspaces[i];
                    tempWorkspaceById[ws.id] = ws;
                }
                root.workspaceById = tempWorkspaceById;
                root.workspaceIds = root.workspaces.map(ws => ws.id);
            }
        }
    }

    Process {
        id: getActiveWorkspace
        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector {
            id: activeWorkspaceCollector
            onStreamFinished: {
                root.activeWorkspace = JSON.parse(activeWorkspaceCollector.text);
            }
        }
    }
}
