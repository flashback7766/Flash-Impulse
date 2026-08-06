import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * "Keep these display settings?" — on every connected screen, not just the
 * one the settings app happens to be on, because the whole point of asking is
 * that the change just applied might have made a different screen the one
 * you can actually see right now.
 */
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: confirmWindow
            required property var modelData
            screen: modelData
            visible: DisplayManager.confirmPending

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:displayConfirm"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: DisplayManager.confirmPending ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"

            // Anchored to all four edges rather than just the bottom: the card is
            // positioned by an anchor *inside* this surface instead, because a
            // window anchored to a single layer-shell edge has no guaranteed
            // centering behaviour on the other axis across compositors — SessionScreen
            // uses the same full-surface-plus-inner-anchor shape for the same reason.
            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }
            implicitWidth: modelData.width
            implicitHeight: modelData.height

            // Keys is an Item-attached property — PanelWindow itself isn't an
            // Item, only what it contains is, so the handler and the focus both
            // have to live on a child.
            Item {
                anchors.fill: parent
                focus: confirmWindow.visible

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_N)
                        DisplayManager.revertNow();
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Y)
                        DisplayManager.confirmKeep();
                }
            }

            Rectangle {
                id: card
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: 48
                }
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                implicitWidth: contentRow.implicitWidth + 40
                implicitHeight: contentRow.implicitHeight + 28

                RowLayout {
                    id: contentRow
                    anchors.centerIn: parent
                    spacing: 20

                    ColumnLayout {
                        spacing: 2
                        StyledText {
                            text: Translation.tr("Keep these display settings?")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: Translation.tr("Reverting in %1s").arg(DisplayManager.confirmSecondsLeft)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    RippleButtonWithIcon {
                        materialIcon: "close"
                        mainText: Translation.tr("Revert")
                        buttonRadius: Appearance.rounding.full
                        onClicked: DisplayManager.revertNow()
                    }
                    RippleButtonWithIcon {
                        materialIcon: "check"
                        mainText: Translation.tr("Keep changes")
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        contentColor: Appearance.colors.colOnPrimary
                        onClicked: DisplayManager.confirmKeep()
                    }
                }
            }
        }
    }
}
