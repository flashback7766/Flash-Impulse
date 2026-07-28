pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * What to ask, on an empty chat.
 *
 * A blank box with a list of keyboard shortcuts tells you how to operate the
 * thing but not what it's for. These are the questions this assistant is
 * unusually good at — it can read the machine it runs on — so they double as a
 * statement of what makes it different from a browser tab.
 */
ColumnLayout {
    id: root

    signal picked(string prompt)

    spacing: 6

    readonly property var suggestions: [
        {
            icon: "monitor",
            label: Translation.tr("Set up my second monitor"),
            prompt: Translation.tr("Look at my monitor setup and help me configure the second display properly.")
        },
        {
            icon: "battery_alert",
            label: Translation.tr("What's draining my battery?"),
            prompt: Translation.tr("Check what's using the most power on this laptop right now and tell me what to do about it.")
        },
        {
            icon: "storage",
            label: Translation.tr("What's eating my disk space?"),
            prompt: Translation.tr("Find what's taking up the most disk space on this machine and summarise it.")
        },
        {
            icon: "volume_off",
            label: Translation.tr("My audio stopped working"),
            prompt: Translation.tr("My sound stopped working. Check the audio stack and help me fix it.")
        }
    ]

    Repeater {
        model: root.suggestions

        delegate: Rectangle {
            id: card
            required property var modelData
            required property int index

            Layout.fillWidth: true
            implicitHeight: 42
            radius: Appearance.rounding.small
            color: cardArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            // Staggered so the set assembles rather than appearing all at once.
            opacity: 0
            Component.onCompleted: cardReveal.start()
            SequentialAnimation {
                id: cardReveal
                PauseAnimation { duration: card.index * 45 }
                NumberAnimation {
                    target: card
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 240
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea {
                id: cardArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(card.modelData.prompt)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 10

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colPrimary
                    text: card.modelData.icon
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                    text: card.modelData.label
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                    opacity: cardArea.containsMouse ? 1 : 0
                    text: "arrow_forward"
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }
}
