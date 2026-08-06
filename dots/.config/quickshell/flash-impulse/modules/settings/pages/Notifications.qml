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
        icon: "notifications_active"
        title: Translation.tr("Popups")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Timeout duration (if not defined by notification) (ms)")
            value: Config.options.notifications.timeout
            from: 1000
            to: 60000
            stepSize: 1000
            onValueChanged: {
                Config.options.notifications.timeout = value;
            }
        }

        ConfigSwitch {
            buttonIcon: "monitor"
            text: Translation.tr("Force specific monitor")
            checked: Config.options.notifications.monitor.enable
            onCheckedChanged: {
                Config.options.notifications.monitor.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("If you have multiple monitors and want notifications to only show on one of them, enable this and enter the monitor name below (e.g., eDP-1)")
            }
        }

        ConfigRow {
            enabled: Config.options.notifications.monitor.enable
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Monitor name to show notifications on (e.g., eDP-1)")
                text: Config.options.notifications.monitor.name
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.notifications.monitor.name = text;
                }
            }
        }
    }
}
