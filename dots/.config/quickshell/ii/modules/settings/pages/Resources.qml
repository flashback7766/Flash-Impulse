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
        icon: "av_timer"
        title: Translation.tr("Polling")
        description: Translation.tr("Lower is more responsive and costs more CPU. The bar reads sysfs directly, so this is the only cost.")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (ms)")
            value: Config.options.resources.updateInterval
            from: 100
            to: 10000
            stepSize: 100
            onValueChanged: {
                Config.options.resources.updateInterval = value;
            }
        }

        ConfigSpinBox {
            icon: "timeline"
            text: Translation.tr("Graph history (samples)")
            value: Config.options.resources.historyLength
            from: 10
            to: 600
            stepSize: 10
            onValueChanged: {
                Config.options.resources.historyLength = value;
            }
            StyledToolTip {
                text: Translation.tr("How many past readings the resource graphs keep. Multiply by the interval above for the span they cover.")
            }
        }
    }
}
