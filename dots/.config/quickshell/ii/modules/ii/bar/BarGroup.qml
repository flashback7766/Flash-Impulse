import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool vertical: false
    property real padding: 5
    // A capsule needs its content kept clear of the rounded caps
    readonly property real sidePadding: (standalone && !vertical) ? padding + 5 : padding
    // What the contents want, readable even when a caller overrides implicitWidth
    // to line this group up with another one.
    readonly property real contentWidth: gridLayout.implicitWidth + sidePadding * 2
    implicitWidth: vertical ? Appearance.sizes.baseVerticalBarWidth : contentWidth
    implicitHeight: vertical ? (gridLayout.implicitHeight + padding * 2) : Appearance.sizes.baseBarHeight
    default property alias items: gridLayout.children

    // With the bar's own background hidden, a group is the only surface standing
    // against the wallpaper, so it has to carry the elevation it used to borrow
    // from the bar: the opaque-over-wallpaper fill, an outline and a shadow.
    readonly property bool standalone: !(Config.options?.bar.showBackground ?? true) && !(Config.options?.bar.borderless ?? false)

    Loader {
        active: root.standalone
        anchors.fill: background
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this instead
            target: background
        }
    }

    Rectangle {
        id: background
        anchors {
            fill: parent
            topMargin: root.vertical ? 0 : 4
            bottomMargin: root.vertical ? 0 : 4
            leftMargin: root.vertical ? 4 : 0
            rightMargin: root.vertical ? 4 : 0
        }
        color: Config.options?.bar.borderless ? "transparent" : (root.standalone ? Appearance.colors.colLayer0 : Appearance.colors.colLayer1)
        radius: root.standalone ? Appearance.rounding.full : Appearance.rounding.small
        border.width: root.standalone ? 1 : 0
        border.color: Appearance.colors.colLayer0Border
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors {
            verticalCenter: root.vertical ? undefined : parent.verticalCenter
            horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            left: root.vertical ? undefined : parent.left
            right: root.vertical ? undefined : parent.right
            top: root.vertical ? parent.top : undefined
            bottom: root.vertical ? parent.bottom : undefined
            margins: root.padding
            leftMargin: root.sidePadding
            rightMargin: root.sidePadding
        }
        columnSpacing: 4
        rowSpacing: 12
    }
}