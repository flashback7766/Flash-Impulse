import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls

/**
 * Material 3 filled text field.
 *
 * Drawn here rather than via Material.containerStyle: the Qt Material style
 * ships the spec's touch-target field — 56px tall, 4px top corners, a hairline
 * underline — which is a phone control. Next to cards rounded at 28 and buttons
 * that are full pills it reads as a leftover from another toolkit, and it makes
 * every settings row half again as tall as it needs to be.
 *
 * So: rounded on all four corners to match what surrounds it, sized to the text
 * it holds, and focus shown as a ring rather than an underline — an underline
 * under a rounded box lands nowhere near the corner it is supposed to follow.
 */
TextField {
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
    clip: true

    topInset: 0
    bottomInset: 0
    leftPadding: 14
    rightPadding: 14
    topPadding: 9
    bottomPadding: 9

    background: Rectangle {
        implicitHeight: 40
        implicitWidth: 120
        radius: root.fieldRadius
        color: root.enabled ? Appearance.colors.colSurfaceContainerHighest : Appearance.colors.colSurfaceContainer
        // Focus is the only state that gets a strong edge. A heavy outline on
        // every field turns a page of settings into a page of boxes.
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

    // A field bound to a long value opens scrolled to its end, because the
    // cursor lands there — so a row of commands shows you all the argument
    // tails and none of the program names. Snap back to the start whenever the
    // field is not being edited.
    Component.onCompleted: root.cursorPosition = 0
    onTextChanged: {
        if (!root.activeFocus)
            root.cursorPosition = 0;
    }
    onActiveFocusChanged: {
        if (!root.activeFocus)
            root.cursorPosition = 0;
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
    }
}
