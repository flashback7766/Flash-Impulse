import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

GroupButton {
    id: button
    property string buttonIcon
    property bool activated: false
    toggled: activated
    
    Layout.fillWidth: false
    Layout.fillHeight: false
    
    // 28, not 32: these set the height of the action strip under every message
    // and of every code and command header, so four pixels here are four pixels
    // on each of them.
    implicitWidth: 28
    implicitHeight: 28
    baseWidth: 28
    baseHeight: 28
    
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundActive: Appearance.colors.colSecondaryContainerActive

    contentItem: MaterialSymbol {
        horizontalAlignment: Text.AlignHCenter
        iconSize: Appearance.font.pixelSize.larger
        text: buttonIcon
        color: button.activated ? Appearance.m3colors.m3onPrimary :
            button.enabled ? Appearance.m3colors.m3onSurface :
            Appearance.colors.colOnLayer1Inactive

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
}
