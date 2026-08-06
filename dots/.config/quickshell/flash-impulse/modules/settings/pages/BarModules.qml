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
    id: root
    forceWidth: true

    // The bar reads left → centre → right, so the switches do too. Anything
    // else and you are hunting for "the thing next to the clock" in a list
    // sorted by nothing.
    readonly property var modules: Config.options.bar.modules

    ContentSection {
        icon: "view_week"
        title: Translation.tr("What's on the bar")
        description: Translation.tr("In the order they appear, left to right. Turning one off frees the space rather than leaving a gap.")

        ContentSubsection {
            title: Translation.tr("Left")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "left_panel_open"
                    text: Translation.tr("Sidebar button")
                    checked: root.modules.leftSidebarButton
                    onCheckedChanged: {
                        root.modules.leftSidebarButton = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "select_window"
                    text: Translation.tr("Focused window")
                    checked: root.modules.activeWindow
                    onCheckedChanged: {
                        root.modules.activeWindow = checked;
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Centre")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "memory"
                    text: Translation.tr("Resources")
                    checked: root.modules.resources
                    onCheckedChanged: {
                        root.modules.resources = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "music_note"
                    text: Translation.tr("Media")
                    checked: root.modules.media
                    onCheckedChanged: {
                        root.modules.media = checked;
                    }
                }
            }
            ConfigSwitch {
                enabled: root.modules.media
                buttonIcon: "title"
                text: Translation.tr("Track title next to the media ring")
                checked: root.modules.mediaTitle
                onCheckedChanged: {
                    root.modules.mediaTitle = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "workspaces"
                text: Translation.tr("Workspaces")
                checked: root.modules.workspaces
                onCheckedChanged: {
                    root.modules.workspaces = checked;
                }
            }
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "schedule"
                    text: Translation.tr("Clock")
                    checked: root.modules.clock
                    onCheckedChanged: {
                        root.modules.clock = checked;
                    }
                }
                ConfigSwitch {
                    enabled: root.modules.clock
                    buttonIcon: "calendar_today"
                    text: Translation.tr("Date beside it")
                    checked: root.modules.clockDate
                    onCheckedChanged: {
                        root.modules.clockDate = checked;
                    }
                }
            }
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "widgets"
                    text: Translation.tr("Utility buttons")
                    checked: root.modules.utilButtons
                    onCheckedChanged: {
                        root.modules.utilButtons = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "battery_android_full"
                    text: Translation.tr("Battery")
                    checked: root.modules.battery
                    onCheckedChanged: {
                        root.modules.battery = checked;
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Right")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "shelf_auto_hide"
                    text: Translation.tr("System tray")
                    checked: root.modules.tray
                    onCheckedChanged: {
                        root.modules.tray = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "signal_cellular_alt"
                    text: Translation.tr("Status icons")
                    checked: root.modules.statusIcons
                    onCheckedChanged: {
                        root.modules.statusIcons = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Network, Bluetooth, keyboard layout, mute state and the notification count — the cluster that opens the right sidebar")
                    }
                }
            }
            ConfigSwitch {
                buttonIcon: "cloud"
                text: Translation.tr("Weather")
                checked: Config.options.bar.weather.enable
                onCheckedChanged: {
                    Config.options.bar.weather.enable = checked;
                }
            }
        }
    }

    ContentSection {
        icon: "width_wide"
        title: Translation.tr("Capsule width")
        description: Translation.tr("The two capsules either side of the workspaces are kept equal, so the workspaces land on the screen's centre line. Their width is measured from what is in them — these are the two things that cannot be measured.")

        ConfigSpinBox {
            icon: "compress"
            text: Translation.tr("Minimum width")
            value: Config.options.bar.centerModuleMinWidth
            from: 60
            to: 600
            stepSize: 10
            onValueChanged: {
                Config.options.bar.centerModuleMinWidth = value;
            }
        }
        ConfigSpinBox {
            enabled: root.modules.media && root.modules.mediaTitle
            icon: "title"
            text: Translation.tr("Room for the track title")
            value: Config.options.bar.mediaTitleWidth
            from: 60
            to: 600
            stepSize: 10
            onValueChanged: {
                Config.options.bar.mediaTitleWidth = value;
            }
            StyledToolTip {
                text: Translation.tr("The title elides, so it has no natural width to measure — this is how much room it gets before it starts shortening")
            }
        }
    }

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
