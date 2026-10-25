#!/usr/bin/env bash
for cmd in "$@"; do
    [[ -z "$cmd" ]] && continue
    if [[ "$cmd" == *"&&"* || "$cmd" == *";"* || "$cmd" == *"||"* ]]; then
        first_bin=$(echo "$cmd" | grep -Po '(?<=command -v\s)\S+' | head -1)
        if [[ -n "$first_bin" ]]; then
            command -v "$first_bin" >/dev/null 2>&1 || continue
        fi
    else
        first_bin="${cmd%% *}"
        command -v "$first_bin" >/dev/null 2>&1 || continue
    fi
    eval "$cmd" &
    exit 0
done

