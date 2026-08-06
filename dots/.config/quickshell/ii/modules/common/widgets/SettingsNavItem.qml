import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * One destination in the settings navigation drawer.
 *
 * Material 3 navigation drawer item: full-pill container, 56 high, active
 * state carried by a secondary-container fill rather than by an accent bar.
 * Collapses to an icon-only rail when the window is too narrow for labels.
 */
RippleButton {
    id: root
    required property string itemIcon
    required property string itemLabel
    property string itemDescription: ""
    property bool collapsed: false

    Layout.fillWidth: true
    implicitHeight: 52
    buttonRadius: Appearance.rounding.full

    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive

    readonly property color colContent: root.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1

    contentItem: Item {
        implicitHeight: 52

        MaterialSymbol {
            id: navIcon
            anchors {
                left: parent.left
                leftMargin: root.collapsed ? 0 : 16
                verticalCenter: parent.verticalCenter
            }
            // Centred when there is no label to sit beside.
            width: root.collapsed ? parent.width : implicitWidth
            horizontalAlignment: Text.AlignHCenter
            iconSize: 22
            fill: root.toggled ? 1 : 0
            text: root.itemIcon
            color: root.colContent

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            anchors {
                left: navIcon.right
                leftMargin: 14
                right: parent.right
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            visible: !root.collapsed
            opacity: root.collapsed ? 0 : 1
            text: root.itemLabel
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: root.toggled ? Font.DemiBold : Font.Normal
            color: root.colContent

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    StyledToolTip {
        // Only useful in the rail, where the label is gone.
        extraVisibleCondition: root.collapsed
        text: root.itemLabel
    }
}
