#!/usr/bin/env bash
# One-shot sensor discovery for the resources service.
#
# Prints `KEY=PATH` lines for whatever this machine actually exposes. The shell
# then polls those paths directly with FileView, so the hot path spawns no
# processes at all — important on a laptop, where a per-tick `grep -r`/`find`
# over sysfs costs more power than the readings are worth.
#
# Path keys:  CPU_TEMP, CPU_FREQ, GPU_BUSY, GPU_TEMP, GPU_FREQ, GPU_POWER,
#             VRAM_TOTAL, VRAM_USED, VRAM_MCLK, BAT_POWER, BAT_CURRENT,
#             BAT_VOLTAGE, BAT_STATUS, RAPL_ENERGY, RAPL_MAX
# Value keys: GPU_TYPE, GPU_POWER_LABEL, RAM_TYPE, VRAM_TYPE

emit() { [ -r "$2" ] && printf '%s=%s\n' "$1" "$2"; }
emit_val() { [ -n "$2" ] && printf '%s=%s\n' "$1" "$2"; }

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

# --- RAM type, straight from the SPD EEPROM's DRAM device type byte. The
# spd5118 (DDR5) driver exposes it unprivileged; ee1004 (DDR4) usually does too.
# Falls back to inferring from which SPD driver is bound at all.
ram_type=""
for eeprom in /sys/bus/i2c/drivers/spd5118/*/eeprom /sys/bus/i2c/drivers/ee1004/*/eeprom; do
    [ -r "$eeprom" ] || continue
    case "$(od -An -tx1 -j2 -N1 "$eeprom" 2> /dev/null | tr -d ' ')" in
        08) ram_type="DDR2" ;;
        0b) ram_type="DDR3" ;;
        0c) ram_type="DDR4" ;;
        0e) ram_type="LPDDR3" ;;
        0f) ram_type="LPDDR4" ;;
        10) ram_type="LPDDR4X" ;;
        12) ram_type="DDR5" ;;
        13) ram_type="LPDDR5" ;;
    esac
    [ -n "$ram_type" ] && break
done
if [ -z "$ram_type" ]; then
    [ -d /sys/bus/i2c/drivers/spd5118 ] && ram_type="DDR5"
    [ -d /sys/bus/i2c/drivers/ee1004 ] && ram_type="DDR4"
fi
emit_val RAM_TYPE "$ram_type"

# Rated transfer rate, decoded from the DDR5 SPD's tCKAVGmin (bytes 20-21,
# little-endian picoseconds): MT/s = 2 / tCK. DDR4 encodes this differently, so
# only DDR5-class modules are decoded rather than guessing.
case "$ram_type" in
    DDR5 | LPDDR5)
        for eeprom in /sys/bus/i2c/drivers/spd5118/*/eeprom; do
            [ -r "$eeprom" ] || continue
            read -r lsb msb <<< "$(od -An -tu1 -j20 -N2 "$eeprom" 2> /dev/null)"
            tck=$((msb * 256 + lsb))
            if [ "$tck" -gt 0 ]; then
                mts=$((2 * 1000000 / tck))
                emit_val RAM_SPEED $(((mts + 50) / 100 * 100)) # snap to the nearest JEDEC step
            fi
            break
        done
        ;;
esac

emit CPU_GOVERNOR /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# --- GPU: AMD (and any driver exposing gpu_busy_percent) via sysfs
for busy in /sys/class/drm/card*/device/gpu_busy_percent; do
    [ -r "$busy" ] || continue
    dev="${busy%/gpu_busy_percent}"
    emit GPU_BUSY "$busy"
    printf 'GPU_TYPE=%s\n' "amd"
    # Matching hwmon node lives under the same device
    for h in "$dev"/hwmon/hwmon*; do
        [ -d "$h" ] || continue
        emit GPU_TEMP "$h/temp1_input"
        emit GPU_FREQ "$h/freq1_input"
        emit GPU_POWER "$h/power1_input"
        emit GPU_VOLT "$h/in0_input"
        # On an APU this is "PPT" — the whole SoC package, CPU included — so
        # pass the label through rather than mislabelling it as GPU-only.
        [ -r "$h/power1_label" ] && emit_val GPU_POWER_LABEL "$(cat "$h/power1_label")"
        break
    done
    emit VRAM_TOTAL "$dev/mem_info_vram_total"
    emit VRAM_USED "$dev/mem_info_vram_used"
    emit VRAM_MCLK "$dev/pp_dpm_mclk"
    # A discrete card names its memory vendor; an APU carves VRAM out of system RAM.
    if [ -r "$dev/mem_info_vram_vendor" ]; then
        emit_val VRAM_TYPE "$(cat "$dev/mem_info_vram_vendor")"
    else
        emit_val VRAM_TYPE "System"
    fi
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
