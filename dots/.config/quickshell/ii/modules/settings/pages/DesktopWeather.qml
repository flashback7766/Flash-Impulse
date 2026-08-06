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
        icon: "weather_mix"
        title: Translation.tr("Weather widget")

        ConfigRow {
            Layout.fillWidth: true

            ConfigSwitch {
                Layout.fillWidth: false
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: Config.options.background.widgets.weather.enable
                onCheckedChanged: {
                    Config.options.background.widgets.weather.enable = checked;
                }
            }
            Item {
                Layout.fillWidth: true
            }
            ConfigSelectionArray {
                Layout.fillWidth: false
                currentValue: Config.options.background.widgets.weather.placementStrategy
                onSelected: newValue => {
                    Config.options.background.widgets.weather.placementStrategy = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Draggable"),
                        icon: "drag_pan",
                        value: "free"
                    },
                    {
                        displayName: Translation.tr("Least busy"),
                        icon: "category",
                        value: "leastBusy"
                    },
                    {
                        displayName: Translation.tr("Most busy"),
                        icon: "shapes",
                        value: "mostBusy"
                    },
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Position")
            tooltip: Translation.tr("A fraction of the screen, 0 to 1. Normally set by dragging the widget; here for when you want the two screens to match exactly.")

            ConfigRow {
                uniform: true
                ConfigSlider {
                    enabled: Config.options.background.widgets.weather.placementStrategy === "free"
                    buttonIcon: "swap_horiz"
                    text: Translation.tr("Horizontal")
                    textWidth: 90
                    showValue: true
                    from: 0
                    to: 1
                    value: Config.options.background.widgets.weather.x
                    onValueChanged: {
                        Config.options.background.widgets.weather.x = value;
                    }
                }
                ConfigSlider {
                    enabled: Config.options.background.widgets.weather.placementStrategy === "free"
                    buttonIcon: "swap_vert"
                    text: Translation.tr("Vertical")
                    textWidth: 90
                    showValue: true
                    from: 0
                    to: 1
                    value: Config.options.background.widgets.weather.y
                    onValueChanged: {
                        Config.options.background.widgets.weather.y = value;
                    }
                }
            }
        }
    }
}
