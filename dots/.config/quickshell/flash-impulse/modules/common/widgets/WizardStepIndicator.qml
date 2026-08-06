import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * Material 3 progress indicator for a linear flow.
 *
 * Segments rather than a bar: a bar tells you how far along you are, segments
 * also tell you how many steps are left — which is the question people actually
 * have when a first-run wizard opens.
 */
RowLayout {
    id: root
    required property int count
    required property int currentIndex
    property real segmentHeight: 4

    spacing: 6

    Repeater {
        model: root.count

        delegate: Rectangle {
            required property int index

            Layout.fillWidth: true
            implicitHeight: root.segmentHeight
            radius: Appearance.rounding.full
            color: index <= root.currentIndex ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.75)

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
