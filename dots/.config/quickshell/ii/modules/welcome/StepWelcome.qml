import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "waving_hand"
        title: Translation.tr("Welcome to Flash-Impulse")
        description: Translation.tr("A few questions, then you're on the desktop. Nothing here is permanent — all of it lives in Settings, under Super+I.")

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: "bolt"
                iconSize: 44
                fill: 1
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colOnLayer1
                    text: Translation.tr("A Hyprland desktop built on Quickshell, with an AI sidebar that can actually run things — behind a whitelist, a blacklist and a model judge.")
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Move with the buttons below, or Alt+← and Alt+→. The counter in the corner tells you how much is left.")
                }
            }
        }
    }

    ContentSection {
        icon: "keyboard"
        title: Translation.tr("Three keys worth remembering now")
        card: true

        Repeater {
            model: [
                { keys: ["Super", "/"], what: Translation.tr("Every keybind there is") },
                { keys: ["Super", "A"], what: Translation.tr("The AI sidebar") },
                { keys: ["Super", "I"], what: Translation.tr("These settings, in full") }
            ]

            delegate: RowLayout {
                required property var modelData

                Layout.fillWidth: true
                Layout.leftMargin: 8
                spacing: 12

                RowLayout {
                    Layout.preferredWidth: 130
                    spacing: 4

                    KeyboardKey {
                        key: Config.options.cheatsheet.superKey ?? "󰖳"
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: "+"
                    }
                    KeyboardKey {
                        key: modelData.keys[1]
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: modelData.what
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }
}
