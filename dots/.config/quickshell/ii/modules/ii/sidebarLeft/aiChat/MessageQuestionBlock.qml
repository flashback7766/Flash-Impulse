pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Questions the model asked instead of guessing.
 *
 * One to four of them, each taking one answer or several, each option able to
 * carry a line explaining what picking it means — the shape Claude Code's
 * AskUserQuestion uses. Both sides feed this same block, so a question from the
 * CLI and a question from Gemini are the same thing on screen.
 *
 * A single one-answer question submits the moment it's clicked; anything more
 * waits for the button, because answering the first of three questions is not
 * the same as being finished.
 */
Item {
    id: root

    property var messageData: null
    readonly property var questions: messageData?.askQuestions ?? []
    readonly property bool pending: messageData?.askPending ?? false
    readonly property var answers: messageData?.askAnswers ?? ({})
    readonly property bool complete: {
        for (let i = 0; i < root.questions.length; i++) {
            if ((root.answers[i] ?? []).length === 0) return false;
        }
        return root.questions.length > 0;
    }
    readonly property bool needsConfirm: root.questions.length > 1
        || (root.questions[0]?.multiSelect === true)

    function chosen(questionIndex, label) {
        return (root.answers[questionIndex] ?? []).indexOf(label) !== -1;
    }

    Layout.fillWidth: true
    implicitHeight: card.implicitHeight

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: cardColumn.implicitHeight + 16
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
            spacing: 10

            Repeater {
                model: root.questions

                delegate: ColumnLayout {
                    id: questionEntry
                    required property var modelData
                    required property int index
                    readonly property var options: questionEntry.modelData.options ?? []
                    readonly property bool multi: questionEntry.modelData.multiSelect === true

                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignTop
                            iconSize: Appearance.font.pixelSize.larger
                            color: root.pending ? Appearance.m3colors.m3tertiary : Appearance.colors.colSubtext
                            text: root.pending ? "live_help" : "check_circle"
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            // The short label, when the model gave one: says what
                            // the question is about before you've read it.
                            StyledText {
                                Layout.fillWidth: true
                                visible: (questionEntry.modelData.header ?? "").length > 0
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: Appearance.m3colors.m3tertiary
                                text: (questionEntry.modelData.header ?? "").toUpperCase()
                            }

                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer2
                                wrapMode: Text.Wrap
                                text: questionEntry.modelData.question ?? ""
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: questionEntry.multi && root.pending
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Pick any that apply")
                            }
                        }
                    }

                    // Full-width rows rather than chips: an option can carry a
                    // line of explanation, and that doesn't fit in a pill.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 26
                        visible: root.pending
                        spacing: 4

                        Repeater {
                            model: questionEntry.options

                            delegate: RippleButton {
                                id: optionButton
                                required property var modelData
                                readonly property bool picked: root.chosen(questionEntry.index, optionButton.modelData.label)

                                Layout.fillWidth: true
                                implicitHeight: optionRow.implicitHeight + 12
                                buttonRadius: Appearance.rounding.small
                                colBackground: optionButton.picked
                                    ? Appearance.colors.colSecondaryContainer
                                    : Appearance.colors.colLayer1
                                colBackgroundHover: optionButton.picked
                                    ? Appearance.colors.colSecondaryContainerHover
                                    : Appearance.colors.colLayer1Hover
                                onClicked: Ai.toggleAskOption(root.messageData, questionEntry.index,
                                    optionButton.modelData.label)

                                contentItem: RowLayout {
                                    id: optionRow
                                    spacing: 8

                                    // A tick box when several answers are allowed,
                                    // a dot when only one is: the control says
                                    // which kind of question this is before you
                                    // click and find out.
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.leftMargin: 8
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: optionButton.picked
                                            ? Appearance.m3colors.m3onSecondaryContainer
                                            : Appearance.colors.colSubtext
                                        text: questionEntry.multi
                                            ? (optionButton.picked ? "check_box" : "check_box_outline_blank")
                                            : (optionButton.picked ? "radio_button_checked" : "radio_button_unchecked")
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.rightMargin: 8
                                        spacing: 1

                                        StyledText {
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignLeft
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: optionButton.picked ? Font.DemiBold : Font.Normal
                                            color: optionButton.picked
                                                ? Appearance.m3colors.m3onSecondaryContainer
                                                : Appearance.colors.colOnLayer1
                                            wrapMode: Text.Wrap
                                            text: optionButton.modelData.label ?? ""
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: (optionButton.modelData.description ?? "").length > 0
                                            horizontalAlignment: Text.AlignLeft
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                            wrapMode: Text.Wrap
                                            text: optionButton.modelData.description ?? ""
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Answered: collapses to what was picked, the way a command
                    // block folds once it's done. The decision is made, not a
                    // standing invitation to change your mind.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 26
                        visible: !root.pending
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
                            text: (root.answers[questionEntry.index] ?? []).join(", ")
                        }
                    }
                }
            }

            RippleButton {
                Layout.fillWidth: true
                Layout.leftMargin: 26
                visible: root.pending && root.needsConfirm
                enabled: root.complete
                opacity: enabled ? 1 : 0.5
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.m3colors.m3tertiaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                onClicked: Ai.submitAskAnswers(root.messageData)

                contentItem: StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onTertiaryContainer
                    text: root.complete
                        ? Translation.tr("Send")
                        : Translation.tr("Pick an answer for each")
                }
            }
        }
    }
}
