import QtQuick
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.modules.common as C

NestableObject {
    id: root

    required property HyprlandMonitor monitor
    readonly property var liveMonitorData: HyprlandData.monitors.find(m => m.id === monitor.id)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel
    // A monitor coming out of the lock screen can briefly report a phantom
    // workspace id near INT32_MAX (HyprlandData.recoverPhantomWorkspaces()
    // switches it back within a few seconds). Every consumer below does
    // arithmetic on this id to lay out a row of pills — group * shownCount +
    // index — so left unguarded, that one huge number turns into a whole row
    // of overlapping huge numbers instead of just looking briefly wrong.
    readonly property int rawActiveWorkspace: monitor?.activeWorkspace?.id ?? 1
    readonly property int activeWorkspace: (rawActiveWorkspace >= 1 && rawActiveWorkspace <= 100) ? rawActiveWorkspace : 1
    readonly property bool currentWorkspaceNotFake: activeWindow?.activated ?? false // Active empty workspace = fake. At least, that's how I like to call it.
    readonly property int fakeWorkspace: currentWorkspaceNotFake ? -9999 : activeWorkspace
    readonly property int shownCount: C.Config.options.bar.workspaces.shown
    readonly property int group: Math.floor((activeWorkspace - 1) / shownCount)
    readonly property var specialWorkspace: liveMonitorData?.specialWorkspace
    readonly property string specialWorkspaceName: specialWorkspace?.name.replace("special:", "") ?? "special"
    readonly property bool specialWorkspaceActive: specialWorkspaceName !== ""

    property list<bool> occupied: []
    property list<var> biggestWindow: occupied.map((_, index) => {
        const wsId = getWorkspaceIdAt(index);
        var biggestWindow = HyprlandData.biggestWindowForWorkspace(wsId);
        return biggestWindow;
    })

    function getWorkspaceId(group, index) {
        return group * root.shownCount + index + 1;
    }
    function getWorkspaceIdAt(index) {
        return root.getWorkspaceId(root.group, index);
    }

    // Function to update workspaceOccupied
    function updateWorkspaceOccupied() {
        root.occupied = Array.from({
            length: root.shownCount
        }, (_, i) => {
            const thisWorkspaceId = getWorkspaceId(root.group, i);
            return Hyprland.workspaces.values.some(ws => ws.id === thisWorkspaceId);
        });
    }

    // Occupied workspace updates
    Component.onCompleted: updateWorkspaceOccupied()
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            root.updateWorkspaceOccupied();
        }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            root.updateWorkspaceOccupied();
        }
    }
    onGroupChanged: {
        updateWorkspaceOccupied();
    }
}
