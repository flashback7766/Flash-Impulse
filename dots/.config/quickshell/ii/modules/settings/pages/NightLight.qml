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
        icon: "nightlight"
        title: Translation.tr("Night light")
        description: Translation.tr("Warms the display after dark. Separate from the light/dark theme — this one changes the panel, not the palette.")

        ConfigSwitch {
            buttonIcon: "schedule"
            text: Translation.tr("Turn on automatically")
            checked: Config.options.light.night.automatic
            onCheckedChanged: {
                Config.options.light.night.automatic = checked;
            }
        }

        ConfigRow {
            enabled: Config.options.light.night.automatic

            ConfigTextField {
                buttonIcon: "bedtime"
                text: Translation.tr("From")
                placeholder: "19:00"
                fieldWidth: 90
                value: Config.options.light.night.from
                onEdited: newValue => Config.options.light.night.from = newValue
            }
            ConfigTextField {
                buttonIcon: "wb_sunny"
                text: Translation.tr("To")
                placeholder: "06:30"
                fieldWidth: 90
                value: Config.options.light.night.to
                onEdited: newValue => Config.options.light.night.to = newValue
            }
        }

        ConfigSpinBox {
            icon: "thermostat"
            text: Translation.tr("Color temperature (K)")
            value: Config.options.light.night.colorTemperature
            from: 1000
            to: 6500
            stepSize: 100
            onValueChanged: {
                Config.options.light.night.colorTemperature = value;
            }
            StyledToolTip {
                text: Translation.tr("Lower is warmer. 6500K is neutral daylight; 4000K is noticeably amber.")
            }
        }
    }

    ContentSection {
        icon: "flashlight_off"
        title: Translation.tr("Anti-flashbang")

        ConfigSwitch {
            buttonIcon: "brightness_low"
            text: Translation.tr("Dim bright content in the dark")
            checked: Config.options.light.antiFlashbang.enable
            onCheckedChanged: {
                Config.options.light.antiFlashbang.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Softens the moment a white page opens on a dark screen")
            }
        }
    }
}
