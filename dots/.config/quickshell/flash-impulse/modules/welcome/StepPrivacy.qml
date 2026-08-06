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
        icon: "neurology"
        title: Translation.tr("AI")
        description: Translation.tr("\"Local only\" keeps the sidebar available but refuses any provider that would send your text off this machine.")

        ConfigSelectionArray {
            currentValue: Config.options.policies.ai
            onSelected: newValue => {
                Config.options.policies.ai = newValue;
            }
            options: [
                {
                    displayName: Translation.tr("No"),
                    icon: "close",
                    value: 0
                },
                {
                    displayName: Translation.tr("Yes"),
                    icon: "check",
                    value: 1
                },
                {
                    displayName: Translation.tr("Local only"),
                    icon: "sync_saved_locally",
                    value: 2
                }
            ]
        }
    }

    ContentSection {
        icon: "work_alert"
        title: Translation.tr("Work safety")
        description: Translation.tr("Kicks in on a network whose name looks public — eduroam, guest, cafe and so on")

        ConfigSwitch {
            buttonIcon: "assignment"
            text: Translation.tr("Hide clipboard images from sussy sources")
            checked: Config.options.workSafety.enable.clipboard
            onCheckedChanged: {
                Config.options.workSafety.enable.clipboard = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "wallpaper"
            text: Translation.tr("Hide sussy wallpapers")
            checked: Config.options.workSafety.enable.wallpaper
            onCheckedChanged: {
                Config.options.workSafety.enable.wallpaper = checked;
            }
        }
    }
}
