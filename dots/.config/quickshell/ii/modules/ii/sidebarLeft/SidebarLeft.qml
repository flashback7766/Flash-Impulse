import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property bool detach: false
    property bool pin: false
    property Component contentComponent: SidebarLeftContent {}
    property Item sidebarContent

    function toggleDetach() {
        root.detach = !root.detach;
    }

    Process { // Dodge cursor away, pin, move cursor back
        id: pinWithFunnyHyprlandWorkaroundProc
        property var hook: null
        property int cursorX;
        property int cursorY;
        function doIt() {
            command = ["hyprctl", "cursorpos"]
            hook = (output) => {
                cursorX = parseInt(output.split(",")[0]);
                cursorY = parseInt(output.split(",")[1]);
                doIt2();
            }
            running = true;
        }
        function doIt2(output) {
            command = ["bash", "-c", "hyprctl dispatch 'hl.dsp.cursor.move({x=9999,y=9999})'"];
            hook = () => {
                doIt3();
            }
            running = true;
        }
        function doIt3(output) {
            root.pin = !root.pin;
            command = ["bash", "-c", `sleep 0.01; hyprctl dispatch 'hl.dsp.cursor.move({x=${cursorX},y=${cursorY}})'`];
            hook = null
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                pinWithFunnyHyprlandWorkaroundProc.hook(text);
            }
        }
    }

    function togglePin() {
        if (!root.pin) pinWithFunnyHyprlandWorkaroundProc.doIt()
        else root.pin = !root.pin;
    }

    Component.onCompleted: {
        root.sidebarContent = contentComponent.createObject(null, {
            "scopeRoot": root,
        });
        sidebarLoader.item.contentParent.children = [root.sidebarContent];
    }

    onDetachChanged: {
        if (root.detach) {
            GlobalFocusGrab.removeDismissable(sidebarLoader.item) // Remove sidebar from the focus grab system
            sidebarContent.parent = null; // Detach content from sidebar
            sidebarLoader.active = false; // Unload sidebar
            detachedSidebarLoader.active = true; // Load detached window
            detachedSidebarLoader.item.contentParent.children = [sidebarContent];
        } else {
            sidebarContent.parent = null; // Detach content from window
            detachedSidebarLoader.active = false; // Unload detached window
            sidebarLoader.active = true; // Load sidebar
            sidebarLoader.item.contentParent.children = [sidebarContent];
        }
    }

    Loader {
        id: sidebarLoader
        active: true
        
        sourceComponent: PanelWindow { // Window
            id: panelWindow

            // The window can't animate its own appearance, so it stays mapped
            // while the panel inside slides and fades, and unmaps once that has
            // finished. Before this the sidebar simply blinked into existence.
            property real reveal: GlobalStates.sidebarLeftOpen ? 1 : 0
            Behavior on reveal {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            visible: panelWindow.reveal > 0.001
            
            property bool extend: false

            // Draggable width, remembered per mode. Zero in the store means the
            // theme default, so a fresh install and a reset both land there
            // without a second "has the user chosen" flag.
            readonly property real minSidebarWidth: 360
            readonly property real maxSidebarWidth: Math.min((panelWindow.screen?.width ?? 1920) * 0.9, 1400)
            readonly property real defaultSidebarWidth: panelWindow.extend
                ? Appearance.sizes.sidebarWidthExtended : Appearance.sizes.sidebarWidth
            property real sidebarWidth: {
                const stored = panelWindow.extend
                    ? (Persistent.states?.sidebar?.left?.widthExtended ?? 0)
                    : (Persistent.states?.sidebar?.left?.width ?? 0);
                const wanted = stored > 0 ? stored : panelWindow.defaultSidebarWidth;
                return Math.max(panelWindow.minSidebarWidth,
                    Math.min(wanted, panelWindow.maxSidebarWidth));
            }

            function setSidebarWidth(value) {
                const clamped = Math.max(panelWindow.minSidebarWidth,
                    Math.min(value, panelWindow.maxSidebarWidth));
                if (!Persistent.states?.sidebar?.left) return;
                if (panelWindow.extend) Persistent.states.sidebar.left.widthExtended = clamped;
                else Persistent.states.sidebar.left.width = clamped;
            }

            function resetSidebarWidth() {
                if (!Persistent.states?.sidebar?.left) return;
                if (panelWindow.extend) Persistent.states.sidebar.left.widthExtended = 0;
                else Persistent.states.sidebar.left.width = 0;
            }

            property var contentParent: sidebarLeftBackground

            function hide() {
                GlobalStates.sidebarLeftOpen = false
            }

            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.pin ? sidebarWidth : 0
            // Sized for the widest the sidebar may ever be dragged to; the visible
            // panel inside is what actually changes width.
            implicitWidth: panelWindow.maxSidebarWidth + Appearance.sizes.elevationMargin
            WlrLayershell.namespace: "quickshell:sidebarLeft"
            // Hyprland 0.49: OnDemand is Exclusive, Exclusive just breaks click-outside-to-close
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors {
                top: true
                left: true
                bottom: true
            }

            // The panel plus its resize handle: input outside this falls through
            // to whatever is behind, which is what makes click-outside-to-close
            // work at all.
            mask: Region {
                item: sidebarLeftBackground
                Region { item: resizeHandle }
            }

            onVisibleChanged: {
                if (visible) {
                    GlobalFocusGrab.addDismissable(panelWindow);
                } else {
                    GlobalFocusGrab.removeDismissable(panelWindow);
                }
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    panelWindow.hide();
                }
            }

            // Content
            //
            // anchors.fill only mirrors the target's layout geometry (x/y/width/
            // height) — it does not follow opacity or a transform, since those are
            // purely visual. Without matching them here, the panel fades and slides
            // away on close while the shadow stays put at full strength until the
            // window itself finally unmaps, reading as a shadow left hanging in
            // place for the whole close animation.
            Translate {
                id: sidebarRevealTranslate
                x: (panelWindow.reveal - 1) * 36
            }
            StyledRectangularShadow {
                target: sidebarLeftBackground
                radius: sidebarLeftBackground.radius
                opacity: panelWindow.reveal
                transform: sidebarRevealTranslate
            }
            Rectangle {
                id: sidebarLeftBackground
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: Appearance.sizes.hyprlandGapsOut
                anchors.leftMargin: Appearance.sizes.hyprlandGapsOut
                width: panelWindow.sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                height: parent.height - Appearance.sizes.hyprlandGapsOut * 2
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

                // A short slide from the edge it lives on, not a full-width one:
                // travelling the whole width reads as slow however fast it is.
                opacity: panelWindow.reveal
                transform: sidebarRevealTranslate

                Behavior on width {
                    // Off while dragging: an eased width lags the pointer, and a
                    // handle that doesn't sit under your finger feels broken.
                    enabled: !resizeHandle.pressed
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }


                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide();
                    }
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_O) {
                            panelWindow.extend = !panelWindow.extend;
                        } else if (event.key === Qt.Key_D) {
                            root.toggleDetach();
                        } else if (event.key === Qt.Key_P) {
                            root.togglePin();
                        }
                        event.accepted = true;
                    }
                }
            }

            MouseArea { // Drag the right edge to resize
                id: resizeHandle
                // A sibling of the panel, not a child: the sidebar's content is
                // installed with `contentParent.children = [...]`, which replaces
                // the whole array and takes anything else in there with it.
                anchors.right: sidebarLeftBackground.right
                anchors.top: sidebarLeftBackground.top
                anchors.bottom: sidebarLeftBackground.bottom
                anchors.topMargin: 16
                anchors.bottomMargin: 16
                width: 14
                z: 9999
                visible: GlobalStates.sidebarLeftOpen
                hoverEnabled: true
                cursorShape: Qt.SizeHorCursor
                acceptedButtons: Qt.LeftButton

                property real pressAnchorX: 0
                property real startWidth: 0

                onPressed: mouse => {
                    // Measured against the panel's own left edge, which is anchored
                    // and therefore still. The handle rides the right edge, so its
                    // own coordinates would chase the drag; and the window isn't an
                    // Item, so it can't be mapped to at all.
                    resizeHandle.pressAnchorX = resizeHandle.mapToItem(sidebarLeftBackground, mouse.x, 0).x;
                    resizeHandle.startWidth = panelWindow.sidebarWidth;
                }
                onPositionChanged: mouse => {
                    if (!resizeHandle.pressed) return;
                    const nowX = resizeHandle.mapToItem(sidebarLeftBackground, mouse.x, 0).x;
                    panelWindow.setSidebarWidth(resizeHandle.startWidth + (nowX - resizeHandle.pressAnchorX));
                }
                onDoubleClicked: panelWindow.resetSidebarWidth()

                // Always drawn, faintly. A handle you can only find by guessing
                // where to put the pointer is one most people never find.
                Rectangle {
                    anchors.centerIn: parent
                    width: 3
                    height: resizeHandle.containsMouse || resizeHandle.pressed ? 36 : 22
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colOnLayer0
                    opacity: resizeHandle.pressed ? 0.55 : (resizeHandle.containsMouse ? 0.4 : 0.16)
                    Behavior on height {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: resizeHandle.containsMouse && !resizeHandle.pressed
                    text: Translation.tr("Drag to resize · double-click to reset")
                }
            }

        }
    }

    Loader {
        id: detachedSidebarLoader
        active: false

        sourceComponent: FloatingWindow {
            id: detachedSidebarRoot
            property var contentParent: detachedSidebarBackground
            color: "transparent"

            visible: GlobalStates.sidebarLeftOpen
            onVisibleChanged: {
                if (!visible) GlobalStates.sidebarLeftOpen = false;
            }
            
            Rectangle {
                id: detachedSidebarBackground
                anchors.fill: parent
                color: Appearance.colors.colLayer0

                Keys.onPressed: (event) => {
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_D) {
                            root.toggleDetach();
                        }
                        event.accepted = true;
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen
        }

        function close(): void {
            GlobalStates.sidebarLeftOpen = false
        }

        function open(): void {
            GlobalStates.sidebarLeftOpen = true
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftOpen"
        description: "Opens left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftOpenAi"
        description: "Toggles left sidebar (Copilot key)"

        onPressed: {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftClose"
        description: "Closes left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = false;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggleDetach"
        description: "Detach left sidebar into a window/Attach it back"

        onPressed: {
            root.detach = !root.detach;
        }
    }

}
