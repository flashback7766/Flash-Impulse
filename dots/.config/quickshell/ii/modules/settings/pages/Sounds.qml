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
        icon: "library_music"
        title: Translation.tr("Sound theme")

        ConfigTextField {
            buttonIcon: "graphic_eq"
            text: Translation.tr("XDG sound theme")
            placeholder: "freedesktop"
            value: Config.options.sounds.theme
            onEdited: newValue => Config.options.sounds.theme = newValue
            StyledToolTip {
                text: Translation.tr("A theme name under /usr/share/sounds. \"freedesktop\" is the one every install has.")
            }
        }
    }

    ContentSection {
        icon: "notification_sound"
        title: Translation.tr("Play a sound for")
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "battery_android_full"
                text: Translation.tr("Battery")
                checked: Config.options.sounds.battery
                onCheckedChanged: {
                    Config.options.sounds.battery = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "av_timer"
                text: Translation.tr("Pomodoro")
                checked: Config.options.sounds.pomodoro
                onCheckedChanged: {
                    Config.options.sounds.pomodoro = checked;
                }
            }
        }
    }
}
