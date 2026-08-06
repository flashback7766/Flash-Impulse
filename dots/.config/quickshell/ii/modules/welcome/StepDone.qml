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
        icon: "check_circle"
        title: Translation.tr("That's it")
        description: Translation.tr("Everything you just picked, plus every other option there is, lives in Settings — Super+I.")

        Flow {
            Layout.fillWidth: true
            spacing: 8

            RippleButtonWithIcon {
                materialIcon: "settings"
                mainText: Translation.tr("Open Settings")
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                onClicked: Quickshell.execDetached(["qs", "-p", `${Directories.config}/quickshell/ii/settings.qml`])
            }
            RippleButtonWithIcon {
                materialIcon: "keyboard_alt"
                mainText: Translation.tr("Keybinds")
                onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "cheatsheet", "toggle"])
            }
        }
    }

    ContentSection {
        icon: "menu_book"
        title: Translation.tr("If something goes wrong")

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnLayer1
            text: Translation.tr("Colors not updating? Open the right sidebar with Super+N and hit \"Reload Hyprland & Quickshell\" in the top-right corner.")
        }

        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 8

            RippleButtonWithIcon {
                materialIcon: "auto_stories"
                mainText: Translation.tr("Documentation")
                onClicked: Qt.openUrlExternally("https://github.com/flashback7766/Flash-Impulse#readme")
            }
            RippleButtonWithIcon {
                materialIcon: "adjust"
                materialIconFill: false
                mainText: Translation.tr("Report an issue")
                onClicked: Qt.openUrlExternally("https://github.com/flashback7766/Flash-Impulse/issues")
            }
            RippleButtonWithIcon {
                nerdIcon: "󰊤"
                mainText: "GitHub"
                onClicked: Qt.openUrlExternally("https://github.com/flashback7766/Flash-Impulse")
            }
        }
    }
}
