import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A hairline with a label, marking a point where something about the
 * conversation changed — the model was swapped, the context was compacted.
 *
 * Without it, an answer from a different model just appears in the same column
 * as the last one and the change reads as inconsistency rather than as
 * something the user did.
 */
Item {
    id: root

    property string text: ""
    property string icon: ""

    implicitHeight: dividerRow.implicitHeight + 12

    RowLayout {
        id: dividerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Appearance.colors.colOutlineVariant
        }

        MaterialSymbol {
            visible: root.icon.length > 0
            iconSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: root.icon
        }

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            text: root.text
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Appearance.colors.colOutlineVariant
        }
    }
}
