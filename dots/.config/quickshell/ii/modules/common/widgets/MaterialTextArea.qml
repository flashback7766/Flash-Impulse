import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls

/**
 * Material 3 filled text area.
 *
 * Same reasoning as MaterialTextField: the stock container is a 56px-tall box
 * with 4px top corners and an underline, which does not belong next to cards
 * rounded at 28. This one is rounded all round, grows with its content, and
 * shows focus as a ring.
 */
TextArea {
    id: root
    property real fieldRadius: Appearance.rounding.small

    Material.theme: Material.System
    Material.accent: Appearance.m3colors.m3primary
    Material.primary: Appearance.m3colors.m3primary
    Material.foreground: Appearance.m3colors.m3onSurface
    renderType: Text.QtRendering

    color: Appearance.colors.colOnLayer1
    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
    // The Material style animates the placeholder up into a floating label when
    // the field is focused or filled. That needs headroom above the text, which
    // a field sized to its content does not have — the label ends up clipped
    // against whatever is above it. Draw it ourselves and let it simply
    // disappear on the first keystroke, which is what a placeholder is for.
    placeholderTextColor: "transparent"

    StyledText {
        anchors {
            left: parent.left
            right: parent.right
            leftMargin: root.leftPadding
            rightMargin: root.rightPadding
            top: parent.top
            topMargin: root.topPadding
        }
        visible: root.text.length === 0
        text: root.placeholderText
        elide: Text.ElideRight
        font: root.font
        color: Appearance.colors.colSubtext
    }

    topInset: 0
    bottomInset: 0
    leftPadding: 14
    rightPadding: 14
    topPadding: 9
    bottomPadding: 9

    background: Rectangle {
        implicitHeight: 40
        radius: root.fieldRadius
        color: root.enabled ? Appearance.colors.colSurfaceContainerHighest : Appearance.colors.colSurfaceContainer
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Appearance.colors.colPrimary : (root.hovered ? Appearance.colors.colOutline : Appearance.colors.colOutlineVariant)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    font {
        family: Appearance.font.family.main
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    wrapMode: TextEdit.Wrap
}
