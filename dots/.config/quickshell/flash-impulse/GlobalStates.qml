import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property bool barOpen: true
    property bool crosshairOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    // Held across reloads. As a plain property it reset to false whenever the
    // config reloaded, which released the session lock — so editing any QML file
    // while the screen was locked unlocked the machine.
    property alias screenLocked: lockState.screenLocked
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    // Where on the focused screen the session menu should appear to come from,
    // in that screen's pixels. Set by whatever opened it when there is a real
    // thing on screen it should grow out of — the power button in the right
    // sidebar — and left negative for a keybind or an IPC call, which have no
    // position and get the centre instead.
    property real sessionOriginX: -1
    property real sessionOriginY: -1

    function openSessionFrom(x: real, y: real): void {
        root.sessionOriginX = x;
        root.sessionOriginY = y;
        root.sessionOpen = true;
    }
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false

    // Mirrors of the Ai service's busy state, written by Ai itself. The bar
    // button and the sidebar wrapper used to bind straight to Ai.*, which
    // constructed the singleton — ollama probe, MCP subprocesses, chat-store
    // index and all — at every shell startup before anyone opened the chat.
    // Defaults are Ai's own initial values, so the two agree before Ai exists.
    property bool aiGenerating: false
    property bool aiConversationIdle: true
    property int aiQueuedMessages: 0
    property int aiPendingFilePathLength: 0

    PersistentProperties {
        id: lockState
        reloadableId: "globalLockState"
        property bool screenLocked: false
    }

    onSidebarRightOpenChanged: {
        if (GlobalStates.sidebarRightOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"

        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }
}