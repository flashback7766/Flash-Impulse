import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * Editor for a config value that is a list of strings.
 *
 * These used to be reachable only by hand-editing config.json — keyword lists,
 * pinned tray items, excluded sites. Chips rather than one comma-separated
 * field: a comma-separated field silently makes " foo" a different entry from
 * "foo", and gives no way to see how many entries you actually have.
 */
ColumnLayout {
    id: root
    property string title: ""
    property string tooltip: ""
    property string placeholder: Translation.tr("Add an entry…")
    property var values: []
    signal edited(var newValues)

    Layout.fillWidth: true
    spacing: 6

    function addValue(v: string): void {
        const t = v.trim();
        if (t.length === 0)
            return;
        const list = (root.values ?? []).slice();
        if (list.includes(t))
            return;
        list.push(t);
        root.edited(list);
    }

    function removeAt(i: int): void {
        const list = (root.values ?? []).slice();
        list.splice(i, 1);
        root.edited(list);
    }

    ContentSubsection {
        visible: root.title.length > 0
        title: root.title
        tooltip: root.tooltip
    }

    Flow {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        spacing: 6
        visible: (root.values?.length ?? 0) > 0

        Repeater {
            model: root.values ?? []

            delegate: Rectangle {
                id: chip
                required property int index
                required property string modelData

                implicitWidth: chipRow.implicitWidth + 20
                implicitHeight: 32
                radius: Appearance.rounding.full
                color: Appearance.colors.colSecondaryContainer

                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 6

                    StyledText {
                        text: chip.modelData
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    RippleButton {
                        implicitWidth: 20
                        implicitHeight: 20
                        buttonRadius: Appearance.rounding.full
                        onClicked: root.removeAt(chip.index)
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 14
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }
    }

    StyledText {
        Layout.leftMargin: 8
        visible: (root.values?.length ?? 0) === 0
        text: Translation.tr("Empty")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 8

        MaterialTextField {
            id: newEntryField
            Layout.fillWidth: true
            placeholderText: root.placeholder
            onAccepted: {
                root.addValue(text);
                text = "";
            }
        }
        RippleButtonWithIcon {
            materialIcon: "add"
            mainText: Translation.tr("Add")
            buttonRadius: Appearance.rounding.small
            onClicked: {
                root.addValue(newEntryField.text);
                newEntryField.text = "";
            }
        }
    }
}
