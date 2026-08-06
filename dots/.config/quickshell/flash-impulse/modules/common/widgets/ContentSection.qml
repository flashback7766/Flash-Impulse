import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A titled group of settings, drawn as a Material 3 card.
 *
 * The label sits outside the card rather than inside it: M3 treats a group
 * heading as page structure, not card content, and keeping it out means two
 * adjacent cards read as two groups even when the reader skips the words.
 */
ColumnLayout {
    id: root
    property string title
    property string icon: ""
    property string description: ""
    property real cardPadding: 16
    // Off for sections whose only child already draws its own surface (a
    // preview, an image grid) — nesting a card in a card just adds a rim.
    property bool card: true
    default property alias contentData: sectionContent.data

    Layout.fillWidth: true
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        spacing: 8

        // Aligned to the centre of the *title line*, not to the top of the row
        // and not to the centre of the whole block. Top-aligning puts a 22px
        // glyph against a smaller cap height, so it reads as floating above the
        // words; centring the row drops it between the two lines when there is
        // a description. Matching the first line's box is what actually looks
        // level.
        Item {
            Layout.alignment: Qt.AlignTop
            implicitWidth: root.icon.length > 0 ? sectionIcon.implicitWidth : 0
            implicitHeight: sectionTitle.implicitHeight
            visible: root.icon.length > 0

            MaterialSymbol {
                id: sectionIcon
                anchors.centerIn: parent
                text: root.icon
                iconSize: Appearance.font.pixelSize.huge
                fill: 1
                color: Appearance.colors.colPrimary
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                id: sectionTitle
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.description.length > 0
                text: root.description
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        radius: Appearance.rounding.large
        color: root.card ? Appearance.colors.colSurfaceContainerHigh : "transparent"
        implicitHeight: sectionContent.implicitHeight + (root.card ? root.cardPadding * 2 : 0)

        ColumnLayout {
            id: sectionContent
            anchors {
                fill: parent
                margins: root.card ? root.cardPadding : 0
            }
            spacing: 6
        }
    }
}
