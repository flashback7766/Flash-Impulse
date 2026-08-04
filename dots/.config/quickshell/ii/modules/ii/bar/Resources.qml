import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    property bool alwaysShowAllResources: false
    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    RowLayout {
        id: rowLayout

        spacing: 0
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        Resource {
            // "memory" is the chip glyph, which reads as CPU — RAM takes the
            // stacked-layers one instead.
            iconName: "planner_review"
            percentage: ResourceUsage.memoryUsedPercentage
            warningThreshold: Config.options.bar.resources.memoryWarningThreshold
        }

        Resource {
            iconName: "swap_horiz"
            percentage: ResourceUsage.swapUsedPercentage
            shown: (Config.options.bar.resources.alwaysShowSwap && percentage > 0) || 
                (MprisController.activePlayer?.trackTitle == null) ||
                root.alwaysShowAllResources
            Layout.leftMargin: shown ? 6 : 0
            warningThreshold: Config.options.bar.resources.swapWarningThreshold
        }

        Resource {
            iconName: "memory"
            percentage: ResourceUsage.cpuUsage
            // Optionally show the htop-style aggregate (sum over all threads,
            // e.g. 312 when 8 threads sit at ~39%) instead of the 0-100 average.
            displayText: Config.options.bar.resources.cpuPerCoreSum
                ? `${Math.round(ResourceUsage.cpuUsageSum * 100)}` : ""
            displayTextMax: Config.options.bar.resources.cpuPerCoreSum
                ? `${ResourceUsage.cpuCoreCount * 100}` : ""
            shown: Config.options.bar.resources.alwaysShowCpu ||
                !(MprisController.activePlayer?.trackTitle?.length > 0) ||
                root.alwaysShowAllResources
            Layout.leftMargin: shown ? 6 : 0
            warningThreshold: Config.options.bar.resources.cpuWarningThreshold
        }

        Resource {
            iconName: "developer_board"
            percentage: ResourceUsage.gpuUsageEffective / 100
            shown: Config.options.bar.resources.showGpu && ResourceUsage.gpuDetected && (
                Config.options.bar.resources.alwaysShowCpu ||
                !(MprisController.activePlayer?.trackTitle?.length > 0) ||
                root.alwaysShowAllResources)
            Layout.leftMargin: shown ? 6 : 0
            warningThreshold: Config.options.bar.resources.gpuWarningThreshold
        }

        Resource {
            // A memory chip, to sit next to the board glyph the GPU uses — the
            // pair reads as "the graphics card, and its memory".
            iconName: "memory_alt"
            percentage: ResourceUsage.vramUsedPercentage
            // On an APU vramTotal is a carve-out of system RAM, which is still
            // worth watching: it is the limit a model or a game actually hits.
            shown: Config.options.bar.resources.showVram && ResourceUsage.gpuDetected && ResourceUsage.vramTotal > 0 && (
                Config.options.bar.resources.alwaysShowCpu ||
                !(MprisController.activePlayer?.trackTitle?.length > 0) ||
                root.alwaysShowAllResources)
            Layout.leftMargin: shown ? 6 : 0
            warningThreshold: Config.options.bar.resources.vramWarningThreshold
        }

    }

    ResourcesPopup {
        hoverTarget: root
    }
}
