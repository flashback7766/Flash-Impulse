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
        icon: "swipe_vertical"
        title: Translation.tr("Scrolling")
        description: Translation.tr("How shell surfaces respond to a wheel or a two-finger swipe")

        ConfigSwitch {
            buttonIcon: "touch_app"
            text: Translation.tr("Faster touchpad scrolling")
            checked: Config.options.interactions.scrolling.fasterTouchpadScroll
            onCheckedChanged: {
                Config.options.interactions.scrolling.fasterTouchpadScroll = checked;
            }
        }

        ConfigSpinBox {
            icon: "mouse"
            text: Translation.tr("Mouse detection threshold")
            value: Config.options.interactions.scrolling.mouseScrollDeltaThreshold
            from: 1
            to: 400
            stepSize: 10
            onValueChanged: {
                Config.options.interactions.scrolling.mouseScrollDeltaThreshold = value;
            }
            StyledToolTip {
                text: Translation.tr("A scroll event larger than this is treated as a wheel rather than a touchpad. Wheels send big discrete steps; touchpads send many small ones.")
            }
        }
        ConfigSpinBox {
            icon: "mouse"
            text: Translation.tr("Mouse scroll factor")
            value: Config.options.interactions.scrolling.mouseScrollFactor
            from: 10
            to: 1000
            stepSize: 10
            onValueChanged: {
                Config.options.interactions.scrolling.mouseScrollFactor = value;
            }
        }
        ConfigSpinBox {
            icon: "touchpad_mouse"
            text: Translation.tr("Touchpad scroll factor")
            value: Config.options.interactions.scrolling.touchpadScrollFactor
            from: 10
            to: 1000
            stepSize: 10
            onValueChanged: {
                Config.options.interactions.scrolling.touchpadScrollFactor = value;
            }
        }
    }

    ContentSection {
        icon: "build"
        title: Translation.tr("Workarounds")

        ConfigSwitch {
            buttonIcon: "border_right"
            text: Translation.tr("Dead pixel workaround")
            checked: Config.options.interactions.deadPixelWorkaround.enable
            onCheckedChanged: {
                Config.options.interactions.deadPixelWorkaround.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Hyprland leaves the rightmost column of pixels non-interactive. Enable if clicks on the far right edge do nothing.")
            }
        }
    }
}
