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
        icon: "shelf_auto_hide"
        title: Translation.tr("Tray")

        ConfigSwitch {
            buttonIcon: "keep"
            text: Translation.tr('Make icons pinned by default')
            checked: Config.options.tray.invertPinnedItems
            onCheckedChanged: {
                Config.options.tray.invertPinnedItems = checked;
            }
        }
        
        ConfigSwitch {
            buttonIcon: "colors"
            text: Translation.tr('Tint icons')
            checked: Config.options.tray.monochromeIcons
            onCheckedChanged: {
                Config.options.tray.monochromeIcons = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "visibility_off"
            text: Translation.tr("Hide passive items")
            checked: Config.options.tray.filterPassive
            onCheckedChanged: {
                Config.options.tray.filterPassive = checked;
            }
            StyledToolTip {
                text: Translation.tr("An item that reports itself as passive has nothing to say right now — most apps use this to mean \"idle\"")
            }
        }
        ConfigSwitch {
            buttonIcon: "label"
            text: Translation.tr("Show item IDs in tooltips")
            checked: Config.options.tray.showItemId
            onCheckedChanged: {
                Config.options.tray.showItemId = checked;
            }
            StyledToolTip {
                text: Translation.tr("Turn this on to find out what to type in the pinned list below")
            }
        }

        ConfigStringList {
            title: Config.options.tray.invertPinnedItems ? Translation.tr("Never pin these") : Translation.tr("Always pin these")
            tooltip: Translation.tr("Tray item IDs. The switch above decides whether this list is the pinned set or the exception to it.")
            placeholder: Translation.tr("Fcitx")
            values: Config.options.tray.pinnedItems
            onEdited: newValues => Config.options.tray.pinnedItems = newValues
        }
    }

    ContentSection {
        icon: "memory"
        title: Translation.tr("Resource chips")
        description: Translation.tr("Read straight from sysfs — no process is spawned on the polling path")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "memory_alt"
                text: Translation.tr("Always show swap")
                checked: Config.options.bar.resources.alwaysShowSwap
                onCheckedChanged: {
                    Config.options.bar.resources.alwaysShowSwap = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "developer_board"
                text: Translation.tr("Always show CPU")
                checked: Config.options.bar.resources.alwaysShowCpu
                onCheckedChanged: {
                    Config.options.bar.resources.alwaysShowCpu = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "monitor"
                text: Translation.tr("Show GPU")
                checked: Config.options.bar.resources.showGpu
                onCheckedChanged: {
                    Config.options.bar.resources.showGpu = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Only appears when a GPU sensor is actually found")
                }
            }
            ConfigSwitch {
                buttonIcon: "sd_card"
                text: Translation.tr("Show VRAM")
                checked: Config.options.bar.resources.showVram
                onCheckedChanged: {
                    Config.options.bar.resources.showVram = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Only when the driver reports a VRAM size")
                }
            }
        }
        ConfigSwitch {
            buttonIcon: "stacked_bar_chart"
            text: Translation.tr("htop-style CPU total")
            checked: Config.options.bar.resources.cpuPerCoreSum
            onCheckedChanged: {
                Config.options.bar.resources.cpuPerCoreSum = checked;
            }
            StyledToolTip {
                text: Translation.tr("Sums per-core load instead of averaging it, so one saturated core on a 16-thread machine reads as busy rather than as 6%")
            }
        }

        ContentSubsection {
            title: Translation.tr("Warn above (%)")
            tooltip: Translation.tr("The chip turns to the error color past this point")

            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "memory"
                    text: Translation.tr("Memory")
                    value: Config.options.bar.resources.memoryWarningThreshold
                    from: 1
                    to: 100
                    stepSize: 1
                    onValueChanged: {
                        Config.options.bar.resources.memoryWarningThreshold = value;
                    }
                }
                ConfigSpinBox {
                    icon: "swap_horiz"
                    text: Translation.tr("Swap")
                    value: Config.options.bar.resources.swapWarningThreshold
                    from: 1
                    to: 100
                    stepSize: 1
                    onValueChanged: {
                        Config.options.bar.resources.swapWarningThreshold = value;
                    }
                }
            }
            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "developer_board"
                    text: Translation.tr("CPU")
                    value: Config.options.bar.resources.cpuWarningThreshold
                    from: 1
                    to: 100
                    stepSize: 1
                    onValueChanged: {
                        Config.options.bar.resources.cpuWarningThreshold = value;
                    }
                }
                ConfigSpinBox {
                    icon: "monitor"
                    text: Translation.tr("GPU")
                    value: Config.options.bar.resources.gpuWarningThreshold
                    from: 1
                    to: 100
                    stepSize: 1
                    onValueChanged: {
                        Config.options.bar.resources.gpuWarningThreshold = value;
                    }
                }
            }
            ConfigSpinBox {
                icon: "sd_card"
                text: Translation.tr("VRAM")
                value: Config.options.bar.resources.vramWarningThreshold
                from: 1
                to: 100
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.resources.vramWarningThreshold = value;
                }
            }
        }
    }

    ContentSection {
        icon: "widgets"
        title: Translation.tr("Utility buttons")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "content_cut"
                text: Translation.tr("Screen snip")
                checked: Config.options.bar.utilButtons.showScreenSnip
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showScreenSnip = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "colorize"
                text: Translation.tr("Color picker")
                checked: Config.options.bar.utilButtons.showColorPicker
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showColorPicker = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "mic"
                text: Translation.tr("Mic toggle")
                checked: Config.options.bar.utilButtons.showMicToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showMicToggle = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "dark_mode"
                text: Translation.tr("Dark/Light toggle")
                checked: Config.options.bar.utilButtons.showDarkModeToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showDarkModeToggle = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "speed"
                text: Translation.tr("Performance Profile toggle")
                checked: Config.options.bar.utilButtons.showPerformanceProfileToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showPerformanceProfileToggle = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "videocam"
                text: Translation.tr("Record")
                checked: Config.options.bar.utilButtons.showScreenRecord
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showScreenRecord = checked;
                }
            }
        }
    }

    ContentSection {
        icon: "cloud"
        title: Translation.tr("Weather")
        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable")
            checked: Config.options.bar.weather.enable
            onCheckedChanged: {
                Config.options.bar.weather.enable = checked;
            }
        }
    }

    ContentSection {
        icon: "notifications"
        title: Translation.tr("Notification indicator")

        ConfigSwitch {
            buttonIcon: "counter_1"
            text: Translation.tr("Show unread count")
            checked: Config.options.bar.indicators.notifications.showUnreadCount
            onCheckedChanged: {
                Config.options.bar.indicators.notifications.showUnreadCount = checked;
            }
        }
    }

    ContentSection {
        icon: "tooltip"
        title: Translation.tr("Tooltips")
        ConfigSwitch {
            buttonIcon: "ads_click"
            text: Translation.tr("Click to show")
            checked: Config.options.bar.tooltips.clickToShow
            onCheckedChanged: {
                Config.options.bar.tooltips.clickToShow = checked;
            }
        }
    }
}
