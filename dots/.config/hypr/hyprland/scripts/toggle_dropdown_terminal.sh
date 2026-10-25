#!/usr/bin/env bash
# Robust Quake Dropdown Terminal Toggle for Hyprland

CLASS="dropdown-terminal"

# Check if client exists in Hyprland
client_address=$(hyprctl clients -j 2>/dev/null | jq -r --arg c "$CLASS" '.[] | select(.class == $c) | .address' | head -1)

# Check if special:dropdown is currently visible on the focused monitor
special_on_focused=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .specialWorkspace.name')

if [[ -z "$client_address" ]]; then
    # Spawn completely detached from terminal and any file descriptors
    setsid kitty --class "$CLASS" </dev/null &>/dev/null &
    
    # Wait for the client to register
    for i in {1..30}; do
        sleep 0.03
        client_address=$(hyprctl clients -j 2>/dev/null | jq -r --arg c "$CLASS" '.[] | select(.class == $c) | .address' | head -1)
        if [[ -n "$client_address" ]]; then
            break
        fi
    done
    
    # Check if special:dropdown is visible now (window rules usually map it to special:dropdown)
    special_on_focused=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .specialWorkspace.name')
    if [[ "$special_on_focused" != "special:dropdown" ]]; then
        hyprctl dispatch 'hl.dsp.workspace.toggle_special("dropdown")' >/dev/null 2>&1
    fi
    hyprctl dispatch 'hl.dsp.focus({ window = "class:dropdown-terminal" })' >/dev/null 2>&1 || true
else
    # Client exists: cleanly toggle
    hyprctl dispatch 'hl.dsp.workspace.toggle_special("dropdown")' >/dev/null 2>&1
    if [[ "$special_on_focused" != "special:dropdown" ]]; then
        hyprctl dispatch 'hl.dsp.focus({ window = "class:dropdown-terminal" })' >/dev/null 2>&1 || true
    fi
fi
