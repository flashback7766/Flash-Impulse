pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A genuine multiple-choice question the model asked instead of guessing,
 * via the ask_user_question tool. Answering it resumes the turn — there's
 * nothing to approve or reject here, just an option to pick.
 */
Item {
    id: root

    property var messageData: null
    readonly property string question: messageData?.askQuestion ?? ""
    readonly property var options: messageData?.askOptions ?? []
    readonly property bool pending: messageData?.askPending ?? false
    readonly property string answer: messageData?.askAnswer ?? ""

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
        border.color: Appearance.m3colors.m3tertiary

        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        ColumnLayout {
            id: cardColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.pending ? Appearance.m3colors.m3tertiary : Appearance.colors.colSubtext
                    text: root.pending ? "live_help" : "check_circle"
                }

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                    wrapMode: Text.Wrap
                    text: root.question
                }
            }

            // Still waiting: one button per option, wrapped to fit the sidebar.
            FlowButtonGroup {
                Layout.fillWidth: true
                Layout.leftMargin: 26
                visible: root.pending
                spacing: 6

                Repeater {
                    model: root.options

                    delegate: RippleButton {
                        id: optionButton
                        required property string modelData
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: Ai.answerQuestion(root.messageData, optionButton.modelData)
                        contentItem: StyledText {
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.m3colors.m3onSecondaryContainer
                            text: optionButton.modelData
                        }
                    }
                }
            }

            // Answered: the options collapse to a single line, like a command
            // block folding once it's done — the decision is made, not a
            // standing invitation to change your mind.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 26
                visible: !root.pending && root.answer.length > 0
                spacing: 6

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("You chose:")
                }
                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                    wrapMode: Text.Wrap
                    text: root.answer
                }
            }
        }
    }
}
