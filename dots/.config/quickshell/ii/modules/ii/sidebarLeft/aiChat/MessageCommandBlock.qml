pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import org.kde.syntaxhighlighting

/**
 * A shell command the model wants to run.
 *
 * The approval bar sits outside the collapsible output on purpose: the output
 * region hides itself once a command finishes, and the buttons used to live
 * inside it — so the moment the assistant's turn ended, the block collapsed and
 * took the only way to approve anything with it.
 *
 * Everything shown here comes from AiMessageData's command fields rather than
 * from the rendered markdown, so "did it succeed" no longer depends on whether
 * the command's own output happened to contain a check mark.
 */
Item {
    id: root

    property var messageData: null

    // Not `state`: that's Item's own, and binding it would swap the item's states.
    readonly property string commandState: messageData?.commandState ?? ""
    readonly property bool pending: root.commandState === "pending"
    readonly property bool running: root.commandState === "running"
    readonly property bool failed: root.commandState === "failed"
    readonly property bool rejected: root.commandState === "rejected"
    readonly property string output: messageData?.commandOutput ?? ""
    readonly property string verdict: messageData?.commandVerdict ?? ""

    // Output opens while there's something to watch and stays open when it went
    // wrong; a command that succeeded is noise you can ask for.
    property bool outputExpanded: false
    property bool userToggled: false
    onCommandStateChanged: {
        if (root.userToggled) return;
        root.outputExpanded = (root.commandState === "running" || root.commandState === "failed");
    }

    readonly property color accent: root.failed ? Appearance.colors.colError
        : root.pending ? Appearance.m3colors.m3tertiary
        : root.running ? Appearance.colors.colPrimary
        : Appearance.colors.colSubtext

    Layout.fillWidth: true
    implicitHeight: card.implicitHeight

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: cardColumn.implicitHeight
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        border.width: root.pending ? 1 : 0
        border.color: root.accent

        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        ColumnLayout {
            id: cardColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 0

            RowLayout { // Status line
                Layout.fillWidth: true
                Layout.margins: 8
                Layout.bottomMargin: 0
                spacing: 6

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.accent
                    text: root.failed ? "error"
                        : root.rejected ? "block"
                        : root.pending ? "gavel"
                        : root.running ? "terminal"
                        : "check_circle"

                    SequentialAnimation on opacity {
                        running: root.running
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { from: 1; to: 0.4; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.4; to: 1; duration: 700; easing.type: Easing.InOutSine }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: root.accent
                    elide: Text.ElideRight
                    text: root.pending ? Translation.tr("Wants to run a command")
                        : root.running ? Translation.tr("Running…")
                        : root.rejected ? Translation.tr("Rejected")
                        : root.failed ? Translation.tr("Failed · exit %1").arg(root.messageData?.commandExitCode ?? 1)
                        : Translation.tr("Done")
                }

                AiMessageControlButton {
                    buttonIcon: "content_copy"
                    onClicked: Quickshell.clipboardText = root.messageData?.commandText ?? ""
                    StyledToolTip { text: Translation.tr("Copy command") }
                }

                AiMessageControlButton {
                    visible: root.output.length > 0
                    activated: root.outputExpanded
                    buttonIcon: root.outputExpanded ? "keyboard_arrow_up" : "keyboard_arrow_down"
                    onClicked: {
                        root.userToggled = true;
                        root.outputExpanded = !root.outputExpanded;
                    }
                    StyledToolTip {
                        text: root.outputExpanded ? Translation.tr("Hide output") : Translation.tr("Show output")
                    }
                }
            }

            Rectangle { // The command itself — never elided while it needs approval
                Layout.fillWidth: true
                Layout.margins: 8
                Layout.topMargin: 6
                implicitHeight: commandTextItem.implicitHeight + 12
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colLayer1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 6

                    StyledText {
                        Layout.alignment: Qt.AlignTop
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.accent
                        text: "$"
                    }

                    StyledText {
                        id: commandTextItem
                        Layout.fillWidth: true
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                        wrapMode: Text.Wrap
                        // Truncating what you're about to approve would be a lie, so
                        // long commands wrap; only a finished one gets shortened.
                        elide: root.pending ? Text.ElideNone : Text.ElideRight
                        maximumLineCount: root.pending ? 12 : 2
                        text: root.messageData?.commandText ?? ""
                    }
                }
            }

            RowLayout { // Safety verdict
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.bottomMargin: 8
                spacing: 6
                visible: root.verdict.length > 0 && (root.pending || root.messageData?.commandAutoApproved)

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    iconSize: Appearance.font.pixelSize.small
                    color: root.pending ? Appearance.m3colors.m3tertiary : Appearance.colors.colSubtext
                    text: root.pending ? "warning" : "shield"
                }

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                    text: root.verdict
                }
            }

            RowLayout { // Approval — outside the collapsible output, always reachable
                Layout.fillWidth: true
                Layout.margins: 8
                Layout.topMargin: 0
                spacing: 6
                visible: root.messageData?.functionPending ?? false

                Item { Layout.fillWidth: true }

                RippleButton {
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    onClicked: Ai.rejectCommand(root.messageData)
                    contentItem: RowLayout {
                        spacing: 4
                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer2
                            text: "close"
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                            text: Translation.tr("Reject")
                        }
                    }
                }

                RippleButton {
                    toggled: true
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    onClicked: Ai.approveCommand(root.messageData)
                    contentItem: RowLayout {
                        spacing: 4
                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnPrimary
                            text: "play_arrow"
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnPrimary
                            text: Translation.tr("Run")
                        }
                    }
                }
            }

            Item { // Output
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.bottomMargin: root.outputExpanded && root.output.length > 0 ? 8 : 0
                clip: true
                implicitHeight: root.outputExpanded && root.output.length > 0 ? outputBackground.implicitHeight : 0

                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Rectangle {
                    id: outputBackground
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    implicitHeight: outputText.implicitHeight + 12
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colLayer1

                    StyledText {
                        id: outputText
                        anchors.fill: parent
                        anchors.margins: 6
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
                        text: root.output
                    }
                }
            }
        }
    }
}
