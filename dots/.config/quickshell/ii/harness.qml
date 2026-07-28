// Offscreen render harness for the chat block widgets.
//
// Run with:  qs -p ~/.config/quickshell/ii/harness.qml
//
// It instantiates the blocks against fixture data and grabs the scene graph to a
// PNG, so a widget can be checked visually without the sidebar being on screen —
// which matters because restarting the shell to look at it kills the lock screen
// when the session happens to be locked.
//
// Drive widgets with fixture data only. Anything that reaches into the Ai
// singleton for real — sendUserMessage, queueUserMessage — runs against the live
// API and writes a chat file into the user's history.
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.aiChat
import QtQuick
import QtQuick.Layouts
import Quickshell

ShellRoot {
    id: root

    property string outPath: Quickshell.env("HARNESS_OUT") || "/tmp/harness.png"

    FloatingWindow {
        id: win
        implicitWidth: 480
        implicitHeight: 900
        color: Appearance.colors.colLayer0Base

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            StyledText {
                text: "Table"
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            MessageTableBlock {
                Layout.fillWidth: true
                header: ["Вариант", "Задержка", "Память", "Стоит брать"]
                aligns: ["left", "right", "center", "left"]
                rows: [
                    ["**Ollama** локально", "~40 мс", "8 ГБ", "да, если есть GPU"],
                    ["Gemini Flash-Lite", "~180 мс", "—", "по умолчанию"],
                    ["Claude Opus", "~600 мс", "—", "для сложного кода"]
                ]
            }

            StyledText {
                text: "Quote"
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            MessageQuoteBlock {
                Layout.fillWidth: true
                segmentContent: "Замер на холодном старте. Прогретая модель отвечает вдвое быстрее."
            }

            StyledText {
                text: "Code block with a file name"
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            MessageCodeBlock {
                Layout.fillWidth: true
                segmentLang: "lua"
                segmentFilename: "~/.config/hypr/monitors.lua"
                segmentContent: 'hl.monitor({ output = "eDP-1", mode = "1920x1200@60", position = "0x0", scale = 1 })\nhl.monitor({ output = "DP-1", mode = "1920x1080@144", position = "1920x0", scale = 1 })\n'
            }

            StyledText {
                text: "Queued messages bar (one, then several)"
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            QueuedMessagesBar {
                Layout.fillWidth: true
                messages: ["а теперь то же самое, но для второго монитора"]
            }

            QueuedMessagesBar {
                Layout.fillWidth: true
                messages: ["первое", "второе", "третье"]
            }

            StyledText {
                text: "Command block: awaiting approval"
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            MessageCommandBlock {
                Layout.fillWidth: true
                messageData: QtObject {
                    property string commandState: "pending"
                    property string commandText: 'hyprctl keyword monitor "DP-1, 1920x1080@144, 1920x0, 1"'
                    property string commandOutput: ""
                    property int commandExitCode: 0
                    property string commandVerdict: "Judge: Modifies desktop window manager configuration."
                    property bool commandAutoApproved: false
                    property bool functionPending: true
                }
            }

            StyledText {
                text: "Command block: failed"
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            MessageCommandBlock {
                Layout.fillWidth: true
                messageData: QtObject {
                    property string commandState: "failed"
                    property string commandText: "hyprctl monitors all"
                    property string commandOutput: "Invalid command\nusage: hyprctl monitors [all]"
                    property int commandExitCode: 2
                    property string commandVerdict: ""
                    property bool commandAutoApproved: false
                    property bool functionPending: false
                }
            }

            Item { Layout.fillHeight: true }
        }

        Timer {
            // Long enough for fonts, the syntax highlighter and the layout passes.
            interval: 2500
            running: true
            onTriggered: {
                column.grabToImage(result => {
                    result.saveToFile(root.outPath);
                    Qt.callLater(Qt.quit);
                });
            }
        }
    }
}
