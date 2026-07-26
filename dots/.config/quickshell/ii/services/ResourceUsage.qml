pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Polled resource usage: RAM, swap, CPU (aggregate + per-core sum), CPU
 * temperature and frequency, GPU load/temperature, and system power draw.
 *
 * Everything on the polling path is a plain sysfs/procfs read through FileView —
 * no process is spawned per tick. Sensor paths are discovered once at startup by
 * services/resources/discover-sensors.sh, because their hwmon indices are not
 * stable across boots.
 */
Singleton {
    id: root

    // --- Memory / swap
    property real memoryTotal: 1
    property real memoryFree: 0
    property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal
    property real swapTotal: 1
    property real swapFree: 0
    property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
    property string memoryType: ""   // DDR4 / DDR5 / ... from SPD
    property int memorySpeedMts: 0   // rated MT/s, DDR5 only
    property string swapType: ""     // "zram" | "Partition" | "File"
    property real swapCompressionRatio: 0 // zram only: uncompressed / compressed
    property string zramStatPath: ""

    // --- CPU
    property real cpuUsage: 0            // 0..1, whole package
    property real cpuUsageSum: 0         // 0..coreCount, htop-style aggregate
    property int cpuCoreCount: 1         // logical cores
    property int cpuTemp: 0              // °C
    property real cpuFreqGhz: 0          // GHz (cpu0)
    property string cpuGovernor: ""      // scaling governor, e.g. "powersave"
    property var previousCpuStats
    property var previousCoreStats: []

    // --- GPU
    property string gpuType: "none"      // "amd" | "nvidia" | "none"
    property bool gpuDetected: false     // latches true once a GPU is seen
    property int gpuUsage: 0             // %, raw busy time
    property int gpuTemp: 0              // °C
    property real gpuFreqMhz: 0          // MHz, shader clock
    property real gpuMaxFreqMhz: 0       // MHz, top shader DPM state

    /**
     * Busy time alone overstates a downclocked GPU: the driver reports 100% while
     * idling at 200 MHz just as it does when saturated at 2200 MHz, even though
     * the actual work done differs ~11x. Weighting by the clock ratio gives a
     * figure proportional to real throughput, so the bar stops screaming at
     * light compositing work.
     */
    readonly property real gpuUsageEffective: (gpuMaxFreqMhz > 0 && gpuFreqMhz > 0)
        ? gpuUsage * (gpuFreqMhz / gpuMaxFreqMhz)
        : gpuUsage
    property real gpuPowerW: 0           // W, scope depends on gpuPowerLabel
    property real gpuVoltage: 0          // V, vddgfx rail
    property string gpuPowerLabel: ""    // sysfs label, e.g. "PPT" (whole SoC on an APU)

    // --- VRAM
    property real vramTotal: 0           // bytes
    property real vramUsed: 0
    property real vramFree: vramTotal - vramUsed
    property real vramUsedPercentage: vramTotal > 0 ? (vramUsed / vramTotal) : 0
    property string vramType: ""         // "System" for shared APU memory, else vendor
    property real vramFreqMhz: 0         // MHz, memory clock

    // --- Power
    property real systemPowerW: 0        // W, whole system while on battery
    property real cpuPowerW: 0           // W, from RAPL when the counter is readable

    property string maxAvailableMemoryString: kbToGbString(root.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(root.swapTotal)
    property string maxAvailableCpuString: "--"

    readonly property int historyLength: Config?.options.resources.historyLength ?? 60
    property list<real> cpuUsageHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    function updateMemoryUsageHistory() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage]
        if (memoryUsageHistory.length > historyLength) {
            memoryUsageHistory.shift()
        }
    }
    function updateSwapUsageHistory() {
        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage]
        if (swapUsageHistory.length > historyLength) {
            swapUsageHistory.shift()
        }
    }
    function updateCpuUsageHistory() {
        cpuUsageHistory = [...cpuUsageHistory, cpuUsage]
        if (cpuUsageHistory.length > historyLength) {
            cpuUsageHistory.shift()
        }
    }
    function updateHistories() {
        updateMemoryUsageHistory()
        updateSwapUsageHistory()
        updateCpuUsageHistory()
    }

    // --- Sensor paths, filled in once by the discovery script
    property var sensorPaths: ({})
    property bool sensorsReady: false

    Process {
        id: discoverSensorsProc
        command: [Quickshell.shellPath("services/resources/discover-sensors.sh")]
        running: true
        stdout: StdioCollector {
            id: discoverOut
            onStreamFinished: {
                const found = {};
                for (const line of discoverOut.text.trim().split("\n")) {
                    const eq = line.indexOf("=");
                    if (eq > 0) found[line.slice(0, eq)] = line.slice(eq + 1);
                }
                root.sensorPaths = found;
                if (found.GPU_TYPE) {
                    root.gpuType = found.GPU_TYPE;
                    root.gpuDetected = true;
                }
                root.memoryType = found.RAM_TYPE ?? "";
                root.memorySpeedMts = Number(found.RAM_SPEED ?? 0);
                root.vramType = found.VRAM_TYPE ?? "";
                root.gpuPowerLabel = found.GPU_POWER_LABEL ?? "";
                root.sensorsReady = true;
            }
        }
    }

    // Reading a counter needs a time base; energy_uj is monotonic microjoules.
    property var previousRapl

    function readSensors() {
        if (!root.sensorsReady) return;

        if (fileCpuTemp.path.length > 0) {
            const raw = parseInt(fileCpuTemp.text());
            if (!isNaN(raw)) root.cpuTemp = Math.round(raw / 1000);
        }
        if (fileCpuFreq.path.length > 0) {
            const khz = parseInt(fileCpuFreq.text());
            if (!isNaN(khz)) root.cpuFreqGhz = khz / 1000000;
        }
        if (fileGpuBusy.path.length > 0) {
            const busy = parseInt(fileGpuBusy.text());
            if (!isNaN(busy)) root.gpuUsage = busy;
        }
        if (fileGpuTemp.path.length > 0) {
            const raw = parseInt(fileGpuTemp.text());
            if (!isNaN(raw)) root.gpuTemp = Math.round(raw / 1000);
        }
        if (fileGpuFreq.path.length > 0) {
            const hz = parseInt(fileGpuFreq.text());
            if (!isNaN(hz)) root.gpuFreqMhz = hz / 1000000;
        }
        if (fileGpuPower.path.length > 0) {
            const uw = parseInt(fileGpuPower.text());
            if (!isNaN(uw)) root.gpuPowerW = uw / 1000000;
        }
        if (fileGpuSclk.path.length > 0 && root.gpuMaxFreqMhz === 0) {
            // Static for a given card, so parse it once.
            root.gpuMaxFreqMhz = root.parseDpmMax(fileGpuSclk.text());
        }
        if (fileGpuVolt.path.length > 0) {
            const mv = parseInt(fileGpuVolt.text());
            if (!isNaN(mv)) root.gpuVoltage = mv / 1000;
        }
        if (fileCpuGovernor.path.length > 0) root.cpuGovernor = fileCpuGovernor.text().trim();
        if (fileVramTotal.path.length > 0) {
            const total = parseInt(fileVramTotal.text());
            if (!isNaN(total)) root.vramTotal = total;
        }
        if (fileVramUsed.path.length > 0) {
            const used = parseInt(fileVramUsed.text());
            if (!isNaN(used)) root.vramUsed = used;
        }
        if (fileVramMclk.path.length > 0) {
            const mclk = fileVramMclk.text();
            root.vramFreqMhz = root.parseDpmClock(mclk);
            // On an APU the GPU's memory controller *is* the system memory
            // controller, so its top DPM state gives the real DRAM data rate —
            // which is what people mean by "DDR5-4800". The SPD only says what
            // the module is rated for, and platforms routinely run it slower.
            if (root.vramType === "System") {
                const maxMclk = root.parseDpmMax(mclk);
                if (maxMclk > 0) root.memorySpeedMts = maxMclk * 2;
            }
        }
        root.systemPowerW = root.readPower();
        root.cpuPowerW = root.readCpuPower();
        root.updateSwapType();
        root.updateZramRatio();
    }

    /**
     * pp_dpm_* lists every DPM state, marking the active one with an asterisk:
     *   0: 1000Mhz
     *   1: 2400Mhz *
     */
    function parseDpmClock(text) {
        if (!text) return 0;
        const match = text.match(/^\s*\d+:\s*(\d+)\s*Mhz\s*\*/mi);
        return match ? Number(match[1]) : 0;
    }

    /** Highest clock the DPM table offers, i.e. the full-speed state. */
    function parseDpmMax(text) {
        if (!text) return 0;
        let max = 0;
        const regex = /^\s*\d+:\s*(\d+)\s*Mhz/gmi;
        let match;
        while ((match = regex.exec(text)) !== null) {
            max = Math.max(max, Number(match[1]));
        }
        return max;
    }

    function updateSwapType() {
        // /proc/swaps: Filename, Type, Size, Used, Priority
        const lines = fileSwaps.text().trim().split("\n");
        if (lines.length < 2) {
            root.swapType = "";
            root.zramStatPath = "";
            return;
        }
        const fields = lines[1].trim().split(/\s+/);
        if (fields.length < 2) return;
        const zram = fields[0].match(/\/dev\/(zram\d+)/);
        if (zram) {
            root.swapType = "zram";
            root.zramStatPath = `/sys/block/${zram[1]}/mm_stat`;
        } else {
            root.swapType = fields[1] === "file" ? "File" : "Partition";
            root.zramStatPath = "";
        }
    }

    /**
     * zram's mm_stat: orig_data_size compr_data_size mem_used_total ...
     * The ratio is what actually justifies zram over a swap partition.
     */
    function updateZramRatio() {
        if (root.zramStatPath.length === 0) {
            root.swapCompressionRatio = 0;
            return;
        }
        const parts = fileZramStat.text().trim().split(/\s+/);
        const orig = Number(parts[0]);
        const compressed = Number(parts[1]);
        root.swapCompressionRatio = (compressed > 0 && orig > 0) ? orig / compressed : 0;
    }

    function readPower() {
        // Battery: the honest whole-system figure, but only while on DC.
        if (fileBatStatus.path.length > 0 && fileBatStatus.text().trim() === "Discharging") {
            if (fileBatPower.path.length > 0) {
                const uw = parseInt(fileBatPower.text());
                if (!isNaN(uw) && uw > 0) return uw / 1000000;
            }
            // Some batteries only report current + voltage.
            if (fileBatCurrent.path.length > 0 && fileBatVoltage.path.length > 0) {
                const ua = parseInt(fileBatCurrent.text());
                const uv = parseInt(fileBatVoltage.text());
                if (!isNaN(ua) && !isNaN(uv) && ua > 0 && uv > 0)
                    return (ua / 1000000) * (uv / 1000000);
            }
        }
        return 0;
    }

    /**
     * CPU package power from the RAPL energy counter. Needs a delta over real
     * time — sampling it twice back-to-back (as a naive script would) always
     * reads ~0, because the counter only ticks every few milliseconds.
     *
     * Note this is frequently root-only: the file was locked down after the
     * PLATYPUS side-channel work, so on most systems this quietly stays at 0.
     */
    function readCpuPower() {
        if (fileRaplEnergy.path.length > 0) {
            const uj = parseInt(fileRaplEnergy.text());
            const now = Date.now();
            if (!isNaN(uj)) {
                const prev = root.previousRapl;
                root.previousRapl = { uj: uj, t: now };
                if (prev && now > prev.t) {
                    let deltaUj = uj - prev.uj;
                    if (deltaUj < 0) { // counter wrapped
                        const max = parseInt(fileRaplMax.text());
                        if (!isNaN(max)) deltaUj += max; else return root.cpuPowerW;
                    }
                    return deltaUj / (now - prev.t) / 1000;
                }
            }
        }
        return root.cpuPowerW;
    }

    Timer {
        interval: 1
        running: true
        repeat: true
        onTriggered: {
            // Reload files
            fileMeminfo.reload()
            fileStat.reload()
            root.reloadSensorFiles()

            // Parse memory and swap usage
            const textMeminfo = fileMeminfo.text()
            memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
            memoryFree = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
            swapTotal = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 1)
            swapFree = Number(textMeminfo.match(/SwapFree: *(\d+)/)?.[1] ?? 0)

            // Parse CPU usage
            const textStat = fileStat.text()
            const cpuLine = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
            if (cpuLine) {
                const stats = cpuLine.slice(1).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                const idle = stats[3]

                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total
                    const idleDiff = idle - previousCpuStats.idle
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
                }

                previousCpuStats = { total, idle }
            }

            root.updatePerCoreUsage(textStat)
            root.readSensors()
            root.updateHistories()
            interval = Config.options?.resources?.updateInterval ?? 3000
        }
    }

    /**
     * Sum of every logical core's utilisation (0..coreCount), the number htop
     * shows. Uses all /proc/stat fields — dropping iowait/irq/softirq (as a
     * four-field parse does) inflates the result whenever the machine is
     * waiting on I/O.
     */
    function updatePerCoreUsage(textStat) {
        const coreRegex = /^cpu(\d+)((?:\s+\d+)+)/gm;
        const newStats = [];
        let match;
        let sum = 0;
        let index = 0;
        while ((match = coreRegex.exec(textStat)) !== null) {
            const fields = match[2].trim().split(/\s+/).map(Number);
            const total = fields.reduce((a, b) => a + b, 0);
            const idle = (fields[3] ?? 0) + (fields[4] ?? 0); // idle + iowait
            const prev = root.previousCoreStats[index];
            if (prev) {
                const totalDiff = total - prev.total;
                const idleDiff = idle - prev.idle;
                if (totalDiff > 0) sum += 1 - idleDiff / totalDiff;
            }
            newStats.push({ total, idle });
            index++;
        }
        if (index > 0) {
            root.cpuCoreCount = index;
            root.cpuUsageSum = sum;
        }
        root.previousCoreStats = newStats;
    }

    function reloadSensorFiles() {
        if (!root.sensorsReady) return;
        if (fileCpuTemp.path.length > 0) fileCpuTemp.reload();
        if (fileCpuFreq.path.length > 0) fileCpuFreq.reload();
        if (fileGpuBusy.path.length > 0) fileGpuBusy.reload();
        if (fileGpuTemp.path.length > 0) fileGpuTemp.reload();
        if (fileGpuFreq.path.length > 0) fileGpuFreq.reload();
        if (fileGpuPower.path.length > 0) fileGpuPower.reload();
        if (fileGpuVolt.path.length > 0) fileGpuVolt.reload();
        if (fileGpuSclk.path.length > 0 && root.gpuMaxFreqMhz === 0) fileGpuSclk.reload();
        if (fileCpuGovernor.path.length > 0) fileCpuGovernor.reload();
        if (fileZramStat.path.length > 0) fileZramStat.reload();
        if (fileVramTotal.path.length > 0) fileVramTotal.reload();
        if (fileVramUsed.path.length > 0) fileVramUsed.reload();
        if (fileVramMclk.path.length > 0) fileVramMclk.reload();
        fileSwaps.reload();
        if (fileBatStatus.path.length > 0) fileBatStatus.reload();
        if (fileBatPower.path.length > 0) fileBatPower.reload();
        if (fileBatCurrent.path.length > 0) fileBatCurrent.reload();
        if (fileBatVoltage.path.length > 0) fileBatVoltage.reload();
        if (fileRaplEnergy.path.length > 0) fileRaplEnergy.reload();
    }

    FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat; path: "/proc/stat" }
    FileView { id: fileSwaps; path: "/proc/swaps" }

    // Discovered sensors. An empty path simply means this machine lacks it.
    FileView { id: fileCpuTemp;    path: root.sensorPaths.CPU_TEMP ?? "" }
    FileView { id: fileCpuFreq;    path: root.sensorPaths.CPU_FREQ ?? "" }
    FileView { id: fileGpuBusy;    path: root.sensorPaths.GPU_BUSY ?? "" }
    FileView { id: fileGpuTemp;    path: root.sensorPaths.GPU_TEMP ?? "" }
    FileView { id: fileGpuFreq;    path: root.sensorPaths.GPU_FREQ ?? "" }
    FileView { id: fileGpuPower;   path: root.sensorPaths.GPU_POWER ?? "" }
    FileView { id: fileGpuVolt;    path: root.sensorPaths.GPU_VOLT ?? "" }
    FileView { id: fileGpuSclk;    path: root.sensorPaths.GPU_SCLK ?? "" }
    FileView { id: fileCpuGovernor; path: root.sensorPaths.CPU_GOVERNOR ?? "" }
    FileView { id: fileZramStat;   path: root.zramStatPath }
    FileView { id: fileVramTotal;  path: root.sensorPaths.VRAM_TOTAL ?? "" }
    FileView { id: fileVramUsed;   path: root.sensorPaths.VRAM_USED ?? "" }
    FileView { id: fileVramMclk;   path: root.sensorPaths.VRAM_MCLK ?? "" }
    FileView { id: fileBatStatus;  path: root.sensorPaths.BAT_STATUS ?? "" }
    FileView { id: fileBatPower;   path: root.sensorPaths.BAT_POWER ?? "" }
    FileView { id: fileBatCurrent; path: root.sensorPaths.BAT_CURRENT ?? "" }
    FileView { id: fileBatVoltage; path: root.sensorPaths.BAT_VOLTAGE ?? "" }
    FileView { id: fileRaplEnergy; path: root.sensorPaths.RAPL_ENERGY ?? "" }
    FileView { id: fileRaplMax;    path: root.sensorPaths.RAPL_MAX ?? "" }

    Process {
        id: findCpuMaxFreqProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"
            }
        }
    }

    /**
     * NVIDIA has no sysfs equivalent of gpu_busy_percent, so it needs nvidia-smi.
     * Only runs when no sysfs GPU was discovered, and at a slower cadence, since
     * the process spawn is expensive (~100-300ms). Untested — no NVIDIA hardware
     * on the development machine.
     */
    Timer {
        running: root.sensorsReady && !root.gpuDetected
        interval: 5000
        repeat: true
        triggeredOnStart: true
        onTriggered: nvidiaProc.running = true
    }

    Process {
        id: nvidiaProc
        command: ["bash", "-c",
            "command -v nvidia-smi >/dev/null || exit 1; "
            + "nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits | head -1"]
        running: false
        stdout: StdioCollector {
            id: nvidiaOut
            onStreamFinished: {
                const parts = nvidiaOut.text.trim().split(",");
                if (parts.length < 2) return;
                const usage = parseInt(parts[0]);
                const temp = parseInt(parts[1]);
                if (isNaN(usage)) return;
                root.gpuType = "nvidia";
                root.gpuDetected = true;
                root.gpuUsage = usage;
                if (!isNaN(temp)) root.gpuTemp = temp;
            }
        }
    }
}
