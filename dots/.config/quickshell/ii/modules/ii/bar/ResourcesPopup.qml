import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    // Helper function to format KB to GB
    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    Row {
        anchors.centerIn: parent
        spacing: 12

        Column {
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow {
                icon: "memory"
                label: "RAM"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "clock_loader_60"
                    label: Translation.tr("Used:")
                    value: root.formatKB(ResourceUsage.memoryUsed)
                }
                StyledPopupValueRow {
                    icon: "check_circle"
                    label: Translation.tr("Free:")
                    value: root.formatKB(ResourceUsage.memoryFree)
                }
                StyledPopupValueRow {
                    icon: "empty_dashboard"
                    label: Translation.tr("Total:")
                    value: root.formatKB(ResourceUsage.memoryTotal)
                }
            }
        }

        Column {
            visible: ResourceUsage.swapTotal > 0
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow {
                icon: "swap_horiz"
                label: "Swap"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "clock_loader_60"
                    label: Translation.tr("Used:")
                    value: root.formatKB(ResourceUsage.swapUsed)
                }
                StyledPopupValueRow {
                    icon: "check_circle"
                    label: Translation.tr("Free:")
                    value: root.formatKB(ResourceUsage.swapFree)
                }
                StyledPopupValueRow {
                    icon: "empty_dashboard"
                    label: Translation.tr("Total:")
                    value: root.formatKB(ResourceUsage.swapTotal)
                }
            }
        }

        Column {
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow {
                icon: "memory"
                label: "CPU"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "bolt"
                    label: Translation.tr("Load:")
                    value: `${Math.round(ResourceUsage.cpuUsageSum * 100)}% (${ResourceUsage.cpuCoreCount} threads)`
                }
                StyledPopupValueRow {
                    visible: ResourceUsage.cpuTemp > 0
                    icon: "thermometer"
                    label: Translation.tr("Temp:")
                    value: `${ResourceUsage.cpuTemp}°C`
                }
                StyledPopupValueRow {
                    visible: ResourceUsage.cpuFreqGhz > 0
                    icon: "speed"
                    label: Translation.tr("Freq:")
                    value: `${ResourceUsage.cpuFreqGhz.toFixed(2)} GHz`
                }
            }
        }

        Column {
            // Also carries the system-wide power draw, so it stays useful on a
            // machine that reports no GPU load sensor.
            visible: ResourceUsage.gpuDetected || ResourceUsage.systemPowerW > 0
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow {
                icon: "developer_board"
                label: ResourceUsage.gpuType === "nvidia" ? "GPU (NVIDIA)"
                    : ResourceUsage.gpuType === "amd" ? "GPU (AMD)"
                    : ResourceUsage.gpuDetected ? "GPU" : Translation.tr("System")
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    visible: ResourceUsage.gpuDetected
                    icon: "bolt"
                    label: Translation.tr("Load:")
                    value: `${ResourceUsage.gpuUsage}%`
                }
                StyledPopupValueRow {
                    visible: ResourceUsage.gpuTemp > 0
                    icon: "thermometer"
                    label: Translation.tr("Temp:")
                    value: `${ResourceUsage.gpuTemp}°C`
                }
                StyledPopupValueRow {
                    visible: ResourceUsage.systemPowerW > 0
                    icon: "battery_charging_full"
                    label: Translation.tr("Power:")
                    value: `${ResourceUsage.systemPowerW.toFixed(1)} W`
                }
            }
        }
    }
}
