import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A labelled single-line config value.
 *
 * MaterialTextArea with a placeholder was doing this job, which meant the label
 * vanished the moment the field had a value — exactly when you most need to know
 * what you are looking at.
 */
RowLayout {
    id: root

    // StyledToolTip looks for `hovered` on its parent; a bare RowLayout has no
    // such property, so the tooltip's visible-condition sees `undefined`,
    // treats that as "no hover tracking needed" and shows permanently.
    property alias hovered: rootHoverHandler.hovered
    HoverHandler {
        id: rootHoverHandler
    }
    property string text: ""
    property string buttonIcon: ""
    property string placeholder: ""
    property string value: ""
    property real fieldWidth: 260
    signal edited(string newValue)

    Layout.fillWidth: true
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    spacing: 10

    OptionalMaterialSymbol {
        icon: root.buttonIcon
        opacity: root.enabled ? 1 : 0.4
    }
    StyledText {
        Layout.fillWidth: true
        text: root.text
        wrapMode: Text.Wrap
        color: Appearance.colors.colOnSecondaryContainer
        opacity: root.enabled ? 1 : 0.4
    }
    MaterialTextField {
        Layout.preferredWidth: root.fieldWidth
        placeholderText: root.placeholder
        text: root.value
        // On editingFinished, not textChanged: writing on every keystroke means
        // a half-typed path or command gets saved and acted on.
        onEditingFinished: root.edited(text)
    }
}
