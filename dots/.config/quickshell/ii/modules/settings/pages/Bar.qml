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
        icon: "spoke"
        title: Translation.tr("Placement")

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Bar position")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: newValue => {
                        Config.options.bar.bottom = (newValue & 1) !== 0;
                        Config.options.bar.vertical = (newValue & 2) !== 0;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Top"),
                            icon: "arrow_upward",
                            value: 0 // bottom: false, vertical: false
                        },
                        {
                            displayName: Translation.tr("Left"),
                            icon: "arrow_back",
                            value: 2 // bottom: false, vertical: true
                        },
                        {
                            displayName: Translation.tr("Bottom"),
                            icon: "arrow_downward",
                            value: 1 // bottom: true, vertical: false
                        },
                        {
                            displayName: Translation.tr("Right"),
                            icon: "arrow_forward",
                            value: 3 // bottom: true, vertical: true
                        }
                    ]
                }
            }
            ContentSubsection {
                title: Translation.tr("Automatically hide")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: Config.options.bar.autoHide.enable
                    onSelected: newValue => {
                        Config.options.bar.autoHide.enable = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: false
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: true
                        }
                    ]
                }
            }
        }

        ConfigRow {
            
            ContentSubsection {
                title: Translation.tr("Corner style")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.bar.cornerStyle
                    onSelected: newValue => {
                        Config.options.bar.cornerStyle = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("Hug"),
                            icon: "line_curve",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Float"),
                            icon: "page_header",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Rect"),
                            icon: "toolbar",
                            value: 2
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Group style")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: Config.options.bar.borderless
                    onSelected: newValue => {
                        Config.options.bar.borderless = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("Pills"),
                            icon: "location_chip",
                            value: false
                        },
                        {
                            displayName: Translation.tr("Line-separated"),
                            icon: "split_scene",
                            value: true
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Background")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: Config.options.bar.showBackground
                    onSelected: newValue => {
                        Config.options.bar.showBackground = newValue; // Update local copy
                    }
                    options: [
                        {
                            // Groups grow their own outlined capsule to stay readable
                            displayName: Translation.tr("Transparent"),
                            icon: "blur_on",
                            value: false
                        },
                        {
                            displayName: Translation.tr("Solid"),
                            icon: "toolbar",
                            value: true
                        }
                    ]
                }
            }
        }

        ConfigSwitch {
            enabled: Config.options.bar.cornerStyle === 1
            buttonIcon: "ev_shadow"
            text: Translation.tr("Shadow behind the floating bar")
            checked: Config.options.bar.floatStyleShadow
            onCheckedChanged: {
                Config.options.bar.floatStyleShadow = checked;
            }
            StyledToolTip {
                text: Translation.tr("Only applies to the Float corner style")
            }
        }
    }

    ContentSection {
        icon: "shelf_auto_hide"
        title: Translation.tr("Auto-hide")
        description: Translation.tr("How the hidden bar comes back")

        ConfigSwitch {
            enabled: Config.options.bar.autoHide.enable
            buttonIcon: "width_normal"
            text: Translation.tr("Push windows aside instead of overlapping")
            checked: Config.options.bar.autoHide.pushWindows
            onCheckedChanged: {
                Config.options.bar.autoHide.pushWindows = checked;
            }
        }
        ConfigSpinBox {
            enabled: Config.options.bar.autoHide.enable
            icon: "border_top"
            text: Translation.tr("Hover region width (px)")
            value: Config.options.bar.autoHide.hoverRegionWidth
            from: 1
            to: 40
            stepSize: 1
            onValueChanged: {
                Config.options.bar.autoHide.hoverRegionWidth = value;
            }
            StyledToolTip {
                text: Translation.tr("How deep into the screen edge the pointer has to reach before the bar comes back")
            }
        }
        ConfigSwitch {
            enabled: Config.options.bar.autoHide.enable
            buttonIcon: "keyboard_command_key"
            text: Translation.tr("Show while the Super key is held")
            checked: Config.options.bar.autoHide.showWhenPressingSuper.enable
            onCheckedChanged: {
                Config.options.bar.autoHide.showWhenPressingSuper.enable = checked;
            }
        }
        ConfigSpinBox {
            enabled: Config.options.bar.autoHide.enable && Config.options.bar.autoHide.showWhenPressingSuper.enable
            icon: "av_timer"
            text: Translation.tr("Hold delay (ms)")
            value: Config.options.bar.autoHide.showWhenPressingSuper.delay
            from: 0
            to: 1000
            stepSize: 10
            onValueChanged: {
                Config.options.bar.autoHide.showWhenPressingSuper.delay = value;
            }
            StyledToolTip {
                text: Translation.tr("Keeps a Super-based keybind from flashing the bar on the way past")
            }
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("Contents & screens")

        ConfigSwitch {
            buttonIcon: "expand_content"
            text: Translation.tr("Verbose")
            checked: Config.options.bar.verbose
            onCheckedChanged: {
                Config.options.bar.verbose = checked;
            }
            StyledToolTip {
                text: Translation.tr("Shows the full resource chips and the media title. Off gives a much narrower bar.")
            }
        }

        ConfigTextField {
            buttonIcon: "star"
            text: Translation.tr("Top-left icon")
            placeholder: "spark"
            value: Config.options.bar.topLeftIcon
            onEdited: newValue => Config.options.bar.topLeftIcon = newValue
            StyledToolTip {
                text: Translation.tr("\"distro\" for your distro's logo, or the name of any icon in ~/.config/quickshell/ii/assets/icons")
            }
        }

        ConfigStringList {
            title: Translation.tr("Show the bar only on these screens")
            tooltip: Translation.tr("Monitor names as reported by 'hyprctl monitors', e.g. eDP-1. Leave empty for every screen.")
            placeholder: Translation.tr("eDP-1")
            values: Config.options.bar.screenList
            onEdited: newValues => Config.options.bar.screenList = newValues
        }
    }
}
