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
        icon: "lock"
        title: Translation.tr("Behaviour")

        ConfigSwitch {
            buttonIcon: "water_drop"
            text: Translation.tr('Use Hyprlock (instead of Quickshell)')
            checked: Config.options.lock.useHyprlock
            onCheckedChanged: {
                Config.options.lock.useHyprlock = checked;
            }
            StyledToolTip {
                text: Translation.tr("If you want to somehow use fingerprint unlock...")
            }
        }

        ConfigSwitch {
            buttonIcon: "account_circle"
            text: Translation.tr('Launch on startup')
            checked: Config.options.lock.launchOnStartup
            onCheckedChanged: {
                Config.options.lock.launchOnStartup = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Security")

            ConfigSwitch {
                buttonIcon: "settings_power"
                text: Translation.tr('Require password to power off/restart')
                checked: Config.options.lock.security.requirePasswordToPower
                onCheckedChanged: {
                    Config.options.lock.security.requirePasswordToPower = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Remember that on most devices one can always hold the power button to force shutdown\nThis only makes it a tiny bit harder for accidents to happen")
                }
            }

            ConfigSwitch {
                buttonIcon: "key_vertical"
                text: Translation.tr('Also unlock keyring')
                checked: Config.options.lock.security.unlockKeyring
                onCheckedChanged: {
                    Config.options.lock.security.unlockKeyring = checked;
                }
                StyledToolTip {
                    text: Translation.tr("This is usually safe and needed for your browser and AI sidebar anyway\nMostly useful for those who use lock on startup instead of a display manager that does it (GDM, SDDM, etc.)")
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Style: general")

            ConfigSwitch {
                buttonIcon: "center_focus_weak"
                text: Translation.tr('Center clock')
                checked: Config.options.lock.centerClock
                onCheckedChanged: {
                    Config.options.lock.centerClock = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "info"
                text: Translation.tr('Show "Locked" text')
                checked: Config.options.lock.showLockedText
                onCheckedChanged: {
                    Config.options.lock.showLockedText = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "shapes"
                text: Translation.tr('Use varying shapes for password characters')
                checked: Config.options.lock.materialShapeChars
                onCheckedChanged: {
                    Config.options.lock.materialShapeChars = checked;
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Style: Blurred")

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr('Enable blur')
                checked: Config.options.lock.blur.enable
                onCheckedChanged: {
                    Config.options.lock.blur.enable = checked;
                }
            }

            ConfigSpinBox {
                enabled: Config.options.lock.blur.enable
                icon: "blur_circular"
                text: Translation.tr("Blur radius")
                value: Config.options.lock.blur.radius
                from: 1
                to: 300
                stepSize: 5
                onValueChanged: {
                    Config.options.lock.blur.radius = value;
                }
                StyledToolTip {
                    text: Translation.tr("Cost scales with the radius. Large values on an integrated GPU will make the lock screen fade in visibly late.")
                }
            }

            ConfigSpinBox {
                icon: "loupe"
                text: Translation.tr("Extra wallpaper zoom (%)")
                value: Config.options.lock.blur.extraZoom * 100
                from: 1
                to: 150
                stepSize: 2
                onValueChanged: {
                    Config.options.lock.blur.extraZoom = value / 100;
                }
            }
        }
    }
}
