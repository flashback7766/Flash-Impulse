import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Editor for a config value that is a list of objects.
 *
 * A few settings are genuinely structured — MCP server definitions, extra model
 * endpoints, quick-toggle layout — and inventing a bespoke form for each would
 * be a lot of surface for something edited once. This gives them a validated
 * JSON field instead, which is still strictly better than the old answer of
 * "open config.json in a text editor": it validates before it writes, so a
 * misplaced comma is caught here rather than silently resetting the value on
 * next load.
 */
ColumnLayout {
    id: root
    property string title: ""
    property string tooltip: ""
    property var value: []
    property int minimumLines: 6
    signal edited(var newValue)

    // Only re-serialise from the config when the user is not mid-edit, or
    // every keystroke would be stomped by the value it is trying to change.
    readonly property string serialized: JSON.stringify(root.value ?? [], null, 2)
    property bool dirty: false
    property string errorText: ""

    Layout.fillWidth: true
    spacing: 6

    function reset(): void {
        editor.text = root.serialized;
        root.dirty = false;
        root.errorText = "";
    }

    function apply(): void {
        try {
            const parsed = JSON.parse(editor.text);
            if (!Array.isArray(parsed)) {
                root.errorText = Translation.tr("Expected a list, e.g. [ … ]");
                return;
            }
            root.errorText = "";
            root.dirty = false;
            root.edited(parsed);
        } catch (e) {
            root.errorText = e.message;
        }
    }

    onSerializedChanged: {
        if (!root.dirty)
            root.reset();
    }
    Component.onCompleted: root.reset()

    ContentSubsection {
        visible: root.title.length > 0
        title: root.title
        tooltip: root.tooltip
    }

    MaterialTextArea {
        id: editor
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.preferredHeight: Math.max(root.minimumLines, Math.min(24, editor.lineCount + 1)) * (font.pixelSize + 6) + 24
        wrapMode: TextEdit.Wrap
        font.family: Appearance.font.family.monospace
        onTextChanged: {
            if (text !== root.serialized)
                root.dirty = true;
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            visible: root.errorText.length > 0 || root.dirty
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.errorText.length > 0 ? Appearance.colors.colError : Appearance.colors.colSubtext
            text: root.errorText.length > 0 ? root.errorText : Translation.tr("Unsaved changes")
        }
        Item {
            Layout.fillWidth: true
            visible: !(root.errorText.length > 0 || root.dirty)
        }
        RippleButtonWithIcon {
            visible: root.dirty
            buttonRadius: Appearance.rounding.small
            materialIcon: "undo"
            mainText: Translation.tr("Revert")
            onClicked: root.reset()
        }
        RippleButtonWithIcon {
            enabled: root.dirty
            buttonRadius: Appearance.rounding.small
            materialIcon: "save"
            mainText: Translation.tr("Apply")
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive
            onClicked: root.apply()
        }
    }
}
