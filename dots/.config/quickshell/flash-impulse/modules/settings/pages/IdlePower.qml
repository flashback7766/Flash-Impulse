import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Screen and sleep timing, split by power source — the same shape as Windows'
 * "Screen, sleep" panel: one column of timers for on battery, one for plugged
 * in, switched automatically by IdleManager the moment the cable changes.
 */
ContentPage {
    id: page
    forceWidth: true

    component ProfileSection: ColumnLayout {
        id: section
        required property var profile

        Layout.fillWidth: true
        spacing: 4

        ConfigSwitch {
            buttonIcon: "lock"
            text: Translation.tr("Lock after")
            checked: section.profile.lockEnable
            onCheckedChanged: section.profile.lockEnable = checked
        }
        ConfigSlider {
            enabled: section.profile.lockEnable
            buttonIcon: "timer"
            text: Translation.tr("Minutes")
            textWidth: 90
            showValue: true
            valueDecimals: 0
            from: 1
            to: 60
            stepSize: 1
            value: section.profile.lockMinutes
            onValueChanged: {
                section.profile.lockMinutes = Math.round(value);
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
        }

        ConfigSwitch {
            buttonIcon: "brightness_low"
            text: Translation.tr("Turn off screen after")
            checked: section.profile.screenOffEnable
            onCheckedChanged: section.profile.screenOffEnable = checked
        }
        ConfigSlider {
            enabled: section.profile.screenOffEnable
            buttonIcon: "timer"
            text: Translation.tr("Minutes")
            textWidth: 90
            showValue: true
            valueDecimals: 0
            from: 1
            to: 120
            stepSize: 1
            value: section.profile.screenOffMinutes
            onValueChanged: {
                section.profile.screenOffMinutes = Math.round(value);
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
        }

        ConfigSwitch {
            buttonIcon: "bedtime"
            text: Translation.tr("Sleep after")
            checked: section.profile.suspendEnable
            onCheckedChanged: section.profile.suspendEnable = checked
        }
        ConfigSlider {
            enabled: section.profile.suspendEnable
            buttonIcon: "timer"
            text: Translation.tr("Minutes")
            textWidth: 90
            showValue: true
            valueDecimals: 0
            from: 1
            to: 240
            stepSize: 1
            value: section.profile.suspendMinutes
            onValueChanged: {
                section.profile.suspendMinutes = Math.round(value);
            }
        }
    }

    ContentSection {
        icon: "power"
        title: Translation.tr("Plugged in")
        description: Battery.available ? Translation.tr("Used whenever the charger is connected") : Translation.tr("This machine has no battery, so this is the only profile there is")

        ProfileSection {
            profile: Config.options.idle.ac
        }
    }

    ContentSection {
        visible: Battery.available
        icon: "battery_android_full"
        title: Translation.tr("On battery")
        description: Translation.tr("Switches over the moment the charger is unplugged")

        ProfileSection {
            profile: Config.options.idle.battery
        }
    }

    ContentSection {
        icon: "info"
        title: Translation.tr("What locking always does")
        card: false

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("The screen locks before every sleep regardless of the timers above, whether idle time triggered it or the lid did — so turning off \"Lock\" here only means the screen stays unlocked while it's merely sitting idle, not while it's actually asleep.")
        }
    }
}
