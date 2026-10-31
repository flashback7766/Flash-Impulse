import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "deployed_code_update"
        title: Translation.tr("Package updates")
        description: Translation.tr("Arch-family only — the check shells out to the package manager")

        ConfigSwitch {
            buttonIcon: "sync"
            text: Translation.tr("Check for updates")
            checked: Config.options.updates.enableCheck
            onCheckedChanged: {
                Config.options.updates.enableCheck = checked;
            }
        }

        ConfigSpinBox {
            enabled: Config.options.updates.enableCheck
            icon: "av_timer"
            text: Translation.tr("Check interval (minutes)")
            value: Config.options.updates.checkInterval
            from: 5
            to: 1440
            stepSize: 5
            onValueChanged: {
                Config.options.updates.checkInterval = value;
            }
        }
    }

    ContentSection {
        id: otaSection
        icon: "cloud_download"
        title: Translation.tr("Dotfiles (Flash-Impulse) OTA")
        description: Translation.tr("Safely updates your system configurations from Git while keeping your local tweaks intact.")

        RippleButtonWithIcon {
            mainText: Translation.tr("Run OTA Update")
            materialIcon: "downloading"
            onClicked: {
                // Execute the update asynchronously
                // Running in a terminal allows the user to see the output and sudo prompts if needed
                CF.executeCommand("kitty --title 'OTA Update' --hold -e bash -c 'cd ~/Flash-Impulse && ./dots-manager.sh update; echo; echo \"Done! You can close this window.\"'");
            }
        }

        // What the manager actually did, its last runs and their exit codes.
        // The kitty window dies with the run; this tail is what stays. It
        // polls while the page lives, so a running update fills in as it
        // goes.
        FileView {
            id: otaLogView
            path: Qt.resolvedUrl((Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/flash-impulse/ota.log")
            onLoaded: otaSection.logTail = tailOf(otaLogView.text())
            onLoadFailed: error => {
                if (error === FileViewError.FileNotFound) otaSection.logTail = Translation.tr("No OTA runs yet — press the button above.");
            }
        }

        Timer {
            interval: 2000
            repeat: true
            running: true
            onTriggered: otaLogView.reload()
        }

        property string logTail: ""

        function tailOf(text, count = 14) {
            const lines = text.split("\n").filter(l => l.length > 0);
            return lines.slice(-count).join("\n");
        }

        TextArea {
            Layout.fillWidth: true
            implicitHeight: 150
            readOnly: true
            text: otaSection.logTail
            wrapMode: TextArea.WrapAnywhere
            color: Appearance.colors.colOnSurfaceVariant
            font.family: "monospace"
            font.pixelSize: Appearance.font.pixelSize.tiny
            background: Rectangle {
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
            }
        }
    }

    ContentSection {
        icon: "priority_high"
        title: Translation.tr("Nagging thresholds")
        description: Translation.tr("How many pending packages before the shell starts suggesting you update")

        ConfigSpinBox {
            enabled: Config.options.updates.enableCheck
            icon: "info"
            text: Translation.tr("Suggest after")
            value: Config.options.updates.adviseUpdateThreshold
            from: 1
            to: 2000
            stepSize: 5
            onValueChanged: {
                Config.options.updates.adviseUpdateThreshold = value;
            }
        }
        ConfigSpinBox {
            enabled: Config.options.updates.enableCheck
            icon: "warning"
            text: Translation.tr("Insist after")
            value: Config.options.updates.stronglyAdviseUpdateThreshold
            from: 1
            to: 5000
            stepSize: 10
            onValueChanged: {
                Config.options.updates.stronglyAdviseUpdateThreshold = value;
            }
        }
    }
}
