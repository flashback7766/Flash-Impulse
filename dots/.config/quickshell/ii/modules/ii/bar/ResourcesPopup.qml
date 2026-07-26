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
    // VRAM counters come from sysfs in bytes rather than /proc's kB
    function formatBytes(bytes) {
        return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB";
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
                StyledPopupValueRow {
                    visible: ResourceUsage.memoryType.length > 0
                    icon: "label"
                    label: Translation.tr("Type:")
                    value: ResourceUsage.memoryType
                }
                StyledPopupValueRow {
                    visible: ResourceUsage.memorySpeedMts > 0
                    icon: "speed"
                    label: Translation.tr("Speed:")
                    value: `${ResourceUsage.memorySpeedMts} MT/s`
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
                StyledPopupValueRow {
                    visible: ResourceUsage.swapType.length > 0
                    icon: "label"
                    label: Translation.tr("Type:")
                    value: ResourceUsage.swapType
                }
                StyledPopupValueRow {
                    visible: ResourceUsage.swapCompressionRatio > 0
                    icon: "compress"
                    label: Translation.tr("Ratio:")
                    value: `${ResourceUsage.swapCompressionRatio.toFixed(1)}x`
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
                StyledPopupValueRow {
                    // RAPL is root-only on most systems, so this often stays hidden
                    visible: ResourceUsage.cpuPowerW > 0
                    icon: "bolt"
                    label: Translation.tr("Power:")
                    value: `${ResourceUsage.cpuPowerW.toFixed(1)} W`
                }
                StyledPopupValueRow {
                    visible: ResourceUsage.systemPowerW > 0
                    icon: "battery_charging_full"
                    label: Translation.tr("System:")
                    value: `${ResourceUsage.systemPowerW.toFixed(1)} W`
                }
                StyledPopupValueRow {
                    visible: ResourceUsage.cpuGovernor.length > 0
                    icon: "tune"
                    label: Translation.tr("Mode:")
                    value: ResourceUsage.cpuGovernor
                }
            }
        }

        Column {
            visible: ResourceUsage.gpuDetected
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow {
                icon: "developer_board"
                label: ResourceUsage.gpuType === "nvidia" ? "GPU (NVIDIA)"
                    : ResourceUsage.gpuType === "amd" ? "GPU (AMD)" : "GPU"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
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
                    visible: ResourceUsage.gpuFreqMhz > 0
                    icon: "speed"
                    label: Translation.tr("Freq:")
                    value: `${Math.round(ResourceUsage.gpuFreqMhz)} MHz`
                }
                StyledPopupValueRow {
                    visible: ResourceUsage.gpuPowerW > 0
                    icon: "bolt"
                    // An APU reports PPT — the whole SoC package, CPU included —
                    // so say so instead of passing it off as GPU-only draw.
                    label: ResourceUsage.gpuPowerLabel === "PPT"
                        ? Translation.tr("SoC:") : Translation.tr("Power:")
                    value: `${ResourceUsage.gpuPowerW.toFixed(1)} W`
                }
                StyledPopupValueRow {
                    visible: ResourceUsage.gpuVoltage > 0
                    icon: "e911_emergency"
                    label: Translation.tr("Volt:")
                    value: `${ResourceUsage.gpuVoltage.toFixed(2)} V`
                }
            }
        }

        Column {
            visible: ResourceUsage.vramTotal > 0
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow {
                icon: "sd_card"
                label: "VRAM"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "clock_loader_60"
                    label: Translation.tr("Used:")
                    value: root.formatBytes(ResourceUsage.vramUsed)
                }
                StyledPopupValueRow {
                    icon: "check_circle"
                    label: Translation.tr("Free:")
                    value: root.formatBytes(ResourceUsage.vramFree)
                }
                StyledPopupValueRow {
                    icon: "empty_dashboard"
                    label: Translation.tr("Total:")
                    value: root.formatBytes(ResourceUsage.vramTotal)
                }
                StyledPopupValueRow {
                    visible: ResourceUsage.vramType.length > 0
                    icon: "label"
                    label: Translation.tr("Type:")
                    value: ResourceUsage.vramType
                }
                StyledPopupValueRow {
                    visible: ResourceUsage.vramFreqMhz > 0
                    icon: "speed"
                    label: Translation.tr("Freq:")
                    value: `${Math.round(ResourceUsage.vramFreqMhz)} MHz`
                }
            }
        }
    }
}
