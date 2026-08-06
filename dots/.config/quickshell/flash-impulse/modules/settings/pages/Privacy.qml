import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "rule"
        title: Translation.tr("Policies")

        ConfigRow {

            // AI policy
            ColumnLayout {
                ContentSubsectionLabel {
                    text: Translation.tr("AI")
                }

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

        }
    }

    ContentSection {
        icon: "work_alert"
        title: Translation.tr("Work safety")

        ConfigSwitch {
            buttonIcon: "assignment"
            text: Translation.tr("Hide clipboard images copied from sussy sources")
            checked: Config.options.workSafety.enable.clipboard
            onCheckedChanged: {
                Config.options.workSafety.enable.clipboard = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "wallpaper"
            text: Translation.tr("Hide sussy/anime wallpapers")
            checked: Config.options.workSafety.enable.wallpaper
            onCheckedChanged: {
                Config.options.workSafety.enable.wallpaper = checked;
            }
        }
    }

    ContentSection {
        icon: "wifi_find"
        title: Translation.tr("What counts as being in public")
        description: Translation.tr("Work safety only kicks in on a network whose name matches one of these")

        ConfigStringList {
            title: Translation.tr("Network name keywords")
            placeholder: "eduroam"
            values: Config.options.workSafety.triggerCondition.networkNameKeywords
            onEdited: newValues => Config.options.workSafety.triggerCondition.networkNameKeywords = newValues
        }
    }

    ContentSection {
        icon: "filter_alt"
        title: Translation.tr("What gets hidden")
        description: Translation.tr("Substring matches, case-insensitive, against the file name or the link")

        ConfigStringList {
            title: Translation.tr("File name keywords")
            values: Config.options.workSafety.triggerCondition.fileKeywords
            onEdited: newValues => Config.options.workSafety.triggerCondition.fileKeywords = newValues
        }

        ConfigStringList {
            title: Translation.tr("Link keywords")
            values: Config.options.workSafety.triggerCondition.linkKeywords
            onEdited: newValues => Config.options.workSafety.triggerCondition.linkKeywords = newValues
        }
    }
}
