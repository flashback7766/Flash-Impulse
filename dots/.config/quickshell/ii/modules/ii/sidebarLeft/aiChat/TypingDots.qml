import qs.modules.common
import QtQuick

/**
 * Three dots pulsing in sequence, for the gap between sending and the first
 * token. A spinner says "busy"; dots say "it's about to start talking", which
 * is the more useful thing to know while an answer is being composed.
 */
Item {
    id: root

    property color color: Appearance.colors.colPrimary
    property real dotSize: 6
    property int cycle: 1100

    implicitWidth: dotRow.implicitWidth
    // Roughly a line of text, so the answer doesn't jump when the dots give way
    // to the first paragraph.
    implicitHeight: Math.max(dotRow.implicitHeight, 20)

    Row {
        id: dotRow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.dotSize * 0.8

        Repeater {
            model: 3

            Rectangle {
                id: dot
                required property int index

                width: root.dotSize
                height: root.dotSize
                radius: root.dotSize / 2
                color: root.color
                opacity: 0.3

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: root.visible

                    PauseAnimation { duration: dot.index * (root.cycle / 6) }
                    NumberAnimation { to: 1; duration: root.cycle / 3; easing.type: Easing.OutQuad }
                    NumberAnimation { to: 0.3; duration: root.cycle / 3; easing.type: Easing.InQuad }
                    PauseAnimation { duration: root.cycle / 3 - dot.index * (root.cycle / 6) }
                }
            }
        }
    }
}
