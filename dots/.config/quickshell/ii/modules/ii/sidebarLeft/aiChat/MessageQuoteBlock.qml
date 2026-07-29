import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * A blockquote, with the accent bar that Qt's markdown renderer doesn't draw.
 * Shares the muted service-block background used by reasoning and tool output —
 * only the accent tells them apart.
 */
Item {
    id: root

    // Named to match the other block delegates; AiMessage.saveMessage() walks these.
    property string segmentContent: ""
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: false
    property var messageData: null
    // Lets AiMessage.saveMessage() put the "> " markers back when re-serialising.
    readonly property bool isQuoteBlock: true

    Layout.fillWidth: true
    implicitHeight: background.implicitHeight

    Rectangle {
        id: background
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: quoteText.implicitHeight + 12
        color: Appearance.colors.colLayer2
        radius: Appearance.rounding.small

        Rectangle { // Accent bar
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
                topMargin: 4
                bottomMargin: 4
            }
            width: 3
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimary
        }

        TextArea {
            id: quoteText
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 12
                rightMargin: 8
                topMargin: 6
            }
            padding: 0
            readOnly: !root.editing
            selectByMouse: root.enableMouseSelection || root.editing
            renderType: Text.NativeRendering
            font.family: Appearance.font.family.reading
            font.hintingPreference: Font.PreferNoHinting
            font.pixelSize: Appearance.font.pixelSize.small
            font.italic: true
            color: Appearance.colors.colOnLayer1
            selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
            selectionColor: Appearance.colors.colSecondaryContainer
            wrapMode: TextEdit.Wrap
            textFormat: root.renderMarkdown ? TextEdit.MarkdownText : TextEdit.PlainText
            text: root.segmentContent
            background: null

            onTextChanged: if (root.editing) root.segmentContent = text
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }
}
