import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * Capsule that appears behind a loose bar item only while the bar itself is
 * transparent. Items living outside a BarGroup — the window title, the tray, the
 * sidebar buttons — would otherwise be bare text and icons sitting directly on
 * the wallpaper, which is where a transparent bar usually falls apart.
 *
 * Costs nothing when the bar has its own background: the Loader stays inactive.
 * The instance is responsible for its own anchors.
 */
Loader {
    id: root
    property color color: Appearance.colors.colLayer0
    property real radius: Appearance.rounding.full

    active: !(Config.options?.bar.showBackground ?? true)
    z: -1 // Behind whatever it is backing

    sourceComponent: Item {
        StyledRectangularShadow {
            target: backdrop
        }
        Rectangle {
            id: backdrop
            anchors.fill: parent
            color: root.color
            radius: root.radius
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
    }
}
