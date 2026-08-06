#!/usr/bin/env bash
# Toggle the Flash-Impulse low-end profile.
#
# Keeps the layout, shapes and colours identical; trades effect quality for
# frame time. Persists by setting `performanceMode` in custom/variables.lua
# (which overrides the shipped default) and applies the expensive bits live so
# there's no need to log out.
#
# Usage: performance-mode.sh [on|off|toggle|status]

set -o pipefail

CUSTOM_VARS="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/custom/variables.lua"
SHELL_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/flash-impulse/config.json"

current_state() {
    [[ -f "$CUSTOM_VARS" ]] && grep -qE '^\s*performanceMode\s*=\s*true' "$CUSTOM_VARS" && echo on || echo off
}

persist() {
    local want="$1"
    mkdir -p "$(dirname "$CUSTOM_VARS")"
    touch "$CUSTOM_VARS"
    if grep -qE '^\s*performanceMode\s*=' "$CUSTOM_VARS"; then
        sed -i -E "s/^\s*performanceMode\s*=.*/performanceMode = ${want}/" "$CUSTOM_VARS"
    else
        printf '\n-- Low-end hardware profile (see hyprland/variables.lua)\nperformanceMode = %s\n' "$want" >> "$CUSTOM_VARS"
    fi
}

apply_live() {
    # Mirrors the values in hyprland/general.lua so the running session matches
    # what a reload would produce.
    if [[ "$1" == true ]]; then
        hyprctl --batch "keyword decoration:blur:size 4 ; \
            keyword decoration:blur:passes 1 ; \
            keyword decoration:shadow:enabled false ; \
            keyword decoration:shadow:render_power 2" > /dev/null
    else
        hyprctl --batch "keyword decoration:blur:size 10 ; \
            keyword decoration:blur:passes 3 ; \
            keyword decoration:shadow:enabled true ; \
            keyword decoration:shadow:render_power 10" > /dev/null
    fi
    # Animation speeds come from the Lua profile; a reload re-evaluates it.
    hyprctl reload > /dev/null 2>&1

    # Shell side: stretch the polling interval and drop the wallpaper parallax.
    if [[ -f "$SHELL_CONFIG" ]] && command -v jq > /dev/null 2>&1; then
        local interval
        [[ "$1" == true ]] && interval=6000 || interval=3000
        jq --argjson i "$interval" '.resources.updateInterval = $i' "$SHELL_CONFIG" > "$SHELL_CONFIG.tmp" \
            && mv "$SHELL_CONFIG.tmp" "$SHELL_CONFIG"
    fi
}

case "${1:-toggle}" in
    on) want=true ;;
    off) want=false ;;
    toggle) [[ "$(current_state)" == on ]] && want=false || want=true ;;
    status) echo "performance mode: $(current_state)"; exit 0 ;;
    *) echo "Usage: $0 [on|off|toggle|status]" >&2; exit 1 ;;
esac

persist "$want"
apply_live "$want"
[[ "$want" == true ]] && state=on || state=off
echo "performance mode: $state"
command -v notify-send > /dev/null 2>&1 &&
    notify-send -a "Flash-Impulse" "Performance mode $state" \
        "$([[ $want == true ]] && echo 'Cheaper blur, no shadows, snappier animations.' || echo 'Full effects restored.')"
