#!/usr/bin/env bash
# One-shot sensor discovery for the resources service.
#
# Prints `KEY=PATH` lines for whatever this machine actually exposes. The shell
# then polls those paths directly with FileView, so the hot path spawns no
# processes at all — important on a laptop, where a per-tick `grep -r`/`find`
# over sysfs costs more power than the readings are worth.
#
# Keys: CPU_TEMP, CPU_FREQ, GPU_BUSY, GPU_TEMP, GPU_TYPE,
#       BAT_POWER, BAT_CURRENT, BAT_VOLTAGE, BAT_STATUS, RAPL_ENERGY, RAPL_MAX

emit() { [ -r "$2" ] && printf '%s=%s\n' "$1" "$2"; }

hwmon_dir_for() {
    # First hwmon whose name matches $1
    local want="$1" name dir
    for name in /sys/class/hwmon/hwmon*/name; do
        [ -r "$name" ] || continue
        [ "$(cat "$name" 2> /dev/null)" = "$want" ] || continue
        dir="${name%/name}"
        printf '%s' "$dir"
        return 0
    done
    return 1
}

# --- CPU temperature: prefer a real package sensor, fall back to the ACPI zone.
# k10temp/zenpower expose Tctl as temp1; coretemp's package is temp1 too.
cpu_temp=""
for want in k10temp zenpower coretemp acpitz; do
    if dir="$(hwmon_dir_for "$want")" && [ -r "$dir/temp1_input" ]; then
        cpu_temp="$dir/temp1_input"
        break
    fi
done
[ -z "$cpu_temp" ] && cpu_temp=/sys/class/thermal/thermal_zone0/temp
emit CPU_TEMP "$cpu_temp"

emit CPU_FREQ /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq

# --- GPU: AMD (and any driver exposing gpu_busy_percent) via sysfs
for busy in /sys/class/drm/card*/device/gpu_busy_percent; do
    [ -r "$busy" ] || continue
    emit GPU_BUSY "$busy"
    printf 'GPU_TYPE=%s\n' "amd"
    # Matching hwmon node lives under the same device
    for t in "${busy%/gpu_busy_percent}"/hwmon/hwmon*/temp1_input; do
        [ -r "$t" ] && emit GPU_TEMP "$t" && break
    done
    break
done

# --- Power draw: battery is the honest system-wide figure while on DC
for bat in /sys/class/power_supply/BAT*; do
    [ -d "$bat" ] || continue
    emit BAT_STATUS "$bat/status"
    emit BAT_POWER "$bat/power_now"       # µW, present on most ThinkPads
    emit BAT_CURRENT "$bat/current_now"   # µA, fallback pair
    emit BAT_VOLTAGE "$bat/voltage_now"   # µV
    break
done

# --- RAPL: package energy counter, usable on AC. Often root-only since the
# platypus/PLATYPUS side-channel mitigations, hence the readability check.
for e in /sys/class/powercap/*/energy_uj; do
    [ -r "$e" ] || continue
    emit RAPL_ENERGY "$e"
    emit RAPL_MAX "${e%/energy_uj}/max_energy_range_uj"
    break
done
