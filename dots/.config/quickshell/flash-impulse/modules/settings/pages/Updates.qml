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
