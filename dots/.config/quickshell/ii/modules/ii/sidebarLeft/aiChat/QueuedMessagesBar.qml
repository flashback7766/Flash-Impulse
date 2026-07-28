pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * What's waiting to be sent once the current answer finishes.
 *
 * Without it, a message typed mid-answer just vanishes from the input box with
 * nothing to show it was accepted — the queue has to be visible for queueing to
 * read as anything other than a dropped message.
 */
Item {
    id: root

    property var messages: Ai.queuedMessages ?? []
    readonly property int count: root.messages.length

    implicitHeight: root.count > 0 ? bar.implicitHeight : 0
    visible: implicitHeight > 0
    clip: true

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Rectangle {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        implicitHeight: barRow.implicitHeight + 12
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2

        RowLayout {
            id: barRow
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 4
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            spacing: 8

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
                text: "schedule_send"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                    text: root.count === 1 ? Translation.tr("Queued, sends when this answer finishes")
                        : Translation.tr("%1 queued, sent in order").arg(root.count)
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: (root.messages[0] ?? "").replace(/\s+/g, " ")
                }
            }

            AiMessageControlButton {
                Layout.alignment: Qt.AlignVCenter
                buttonIcon: "close"
                onClicked: Ai.clearQueue()
                StyledToolTip { text: Translation.tr("Discard queued messages") }
            }
        }
    }
}
