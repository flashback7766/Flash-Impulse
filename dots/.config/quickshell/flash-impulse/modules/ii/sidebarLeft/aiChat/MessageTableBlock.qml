pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * A markdown table.
 *
 * Qt's markdown renderer does draw tables, but as a bare grid — no header
 * weight, no row banding, and no way to reach a column that falls off the edge
 * of a narrow sidebar. Since a table is usually the answer to "compare these",
 * it gets its own widget: emphasised header, banded rows, and horizontal
 * scrolling once the columns can't fit.
 */
Item {
    id: root

    // Named to match the other block delegates; AiMessage.saveMessage() walks these.
    property string segmentContent: ""
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: false
    property var messageData: null

    property var header: []
    property var aligns: []
    property var rows: []

    readonly property int columnCount: root.header.length
    // Flattened for a single Repeater: the header is row 0, body rows follow.
    readonly property var cells: {
        const out = [];
        for (let c = 0; c < root.columnCount; c++) {
            out.push({ text: root.header[c] ?? "", row: 0, col: c });
        }
        for (let r = 0; r < root.rows.length; r++) {
            for (let c = 0; c < root.columnCount; c++) {
                out.push({ text: root.rows[r][c] ?? "", row: r + 1, col: c });
            }
        }
        return out;
    }

    Layout.fillWidth: true
    implicitHeight: frame.implicitHeight

    Rectangle {
        id: frame
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: flick.implicitHeight
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer1
        clip: true

        Flickable {
            id: flick
            anchors.fill: parent
            implicitHeight: grid.implicitHeight
            contentWidth: Math.max(grid.implicitWidth, width)
            contentHeight: grid.implicitHeight
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ScrollBar.horizontal: ScrollBar {
                policy: ScrollBar.AsNeeded
                opacity: flick.contentWidth > flick.width ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                contentItem: Rectangle {
                    implicitHeight: 5
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2Active
                }
            }

            GridLayout {
                id: grid
                width: flick.contentWidth
                columns: Math.max(1, root.columnCount)
                rowSpacing: 0
                columnSpacing: 0

                Repeater {
                    model: ScriptModel { values: root.cells }

                    delegate: Rectangle {
                        id: cell
                        required property var modelData

                        readonly property bool isHeader: cell.modelData.row === 0
                        readonly property string align: root.aligns[cell.modelData.col] ?? "left"

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // Wide enough to be readable, capped so one verbose column
                        // can't push everything else off the edge.
                        Layout.minimumWidth: Math.min(90, cellText.implicitWidth + 20)
                        Layout.maximumWidth: 320
                        implicitWidth: Math.min(320, cellText.implicitWidth + 20)
                        implicitHeight: cellText.implicitHeight + 14

                        color: cell.isHeader ? Appearance.colors.colLayer2
                            : (cell.modelData.row % 2 === 0) ? Appearance.colors.colLayer2Hover
                            : "transparent"

                        StyledText {
                            id: cellText
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            anchors.topMargin: 7
                            anchors.bottomMargin: 7
                            font.family: Appearance.font.family.reading
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: cell.isHeader ? Font.DemiBold : Font.Normal
                            color: cell.isHeader ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnLayer1
                            wrapMode: Text.Wrap
                            textFormat: root.renderMarkdown ? Text.MarkdownText : Text.PlainText
                            horizontalAlignment: cell.align === "right" ? Text.AlignRight
                                : cell.align === "center" ? Text.AlignHCenter
                                : Text.AlignLeft
                            text: cell.modelData.text
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                    }
                }
            }
        }
    }
}
