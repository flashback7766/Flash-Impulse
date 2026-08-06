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
        icon: "speed"
        title: Translation.tr("Performance mode")
        description: Translation.tr("Worth turning on for older integrated graphics")

        ConfigSwitch {
            buttonIcon: "speed"
            text: Translation.tr("Enable performance mode")
            enabled: !PerformanceMode.busy
            checked: PerformanceMode.enabled
            onCheckedChanged: PerformanceMode.setEnabled(checked)
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("Blur costs roughly passes × radius × area, so this drops it from 3 passes at radius 10 to 1 at 4 — still frosted, around an order of magnitude less fill rate. It also drops window shadows and shortens every animation. Layout, rounding, spacing and colors are untouched.")
        }
    }

    ContentSection {
        icon: "memory"
        title: Translation.tr("Polling")
        description: Translation.tr("The bar reads CPU, GPU and memory straight from sysfs — no process is spawned on this path")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Resource polling interval (ms)")
            value: Config.options.resources.updateInterval
            from: 100
            to: 10000
            stepSize: 100
            onValueChanged: {
                Config.options.resources.updateInterval = value;
            }
        }
    }
}
