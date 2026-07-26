pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Low-end hardware profile.
 *
 * The setting itself lives in the Hyprland config (custom/variables.lua), since
 * the expensive knobs — blur passes, shadows, animation durations — belong to the
 * compositor rather than the shell. This singleton just mirrors that state so the
 * settings and welcome apps can offer a switch, delegating every change to
 * performance-mode.sh, which stays the single source of truth.
 */
Singleton {
    id: root

    readonly property string scriptPath:
        `${Directories.config}/hypr/hyprland/scripts/performance-mode.sh`

    property bool enabled: false
    property bool busy: false

    Component.onCompleted: root.refresh()

    function refresh() {
        statusProc.running = true;
    }

    function setEnabled(value) {
        if (root.busy || value === root.enabled) return;
        root.busy = true;
        applyProc.command = [root.scriptPath, value ? "on" : "off"];
        applyProc.running = true;
    }

    Process {
        id: statusProc
        command: [root.scriptPath, "status"]
        running: false
        stdout: StdioCollector {
            id: statusOut
            onStreamFinished: {
                // "performance mode: on"
                root.enabled = statusOut.text.trim().endsWith("on");
            }
        }
    }

    Process {
        id: applyProc
        running: false
        onExited: (exitCode) => {
            root.busy = false;
            // Re-read rather than assuming, so a failed apply doesn't leave the
            // switch showing a state the system isn't in.
            root.refresh();
        }
    }
}
