#!/usr/bin/env bash
# dots-manager — bring the Flash-Impulse dotfiles from Git onto the live
# config. The settings page's OTA button runs this.
#
# What an update is, deliberately: pull the repo fast-forward, lay the
# updated configs over ~/.config, reload Hyprland. Packages, services and
# migrations are the installer's job — an OTA that reruns the whole engine
# behind the owner's back is how a theme update once took the desktop down.
#
# Local tweaks stay intact the way the repo's own convention keeps them:
# live edits are committed back, so a clean repo means live matches it. A
# dirty repo stops the update rather than being stashed behind your back.

set -euo pipefail

REPO="${FLASH_IMPULSE_REPO:-$HOME/Flash-Impulse}"
LIVE_CONFIG="${FLASH_IMPULSE_LIVE_CONFIG:-$HOME/.config}"

die() { echo "dots-manager: $*" >&2; exit 1; }

repo_status() {
    cd "$REPO"
    git fetch origin --quiet
    local behind
    behind=$(git rev-list --count HEAD..origin/main)
    local dirty
    dirty=$(git status --porcelain | wc -l)
    printf 'repo      %s (%s)\n' "$(git rev-parse --short HEAD)" "$(git branch --show-current)"
    printf 'origin    %s — %s\n' "$(git rev-parse --short origin/main)" \
        "$([ "$behind" -eq 0 ] && echo 'up to date' || echo "$behind commit(s) waiting")"
    printf 'worktree  %s\n' "$([ "$dirty" -eq 0 ] && echo clean || echo "$dirty uncommitted change(s)")"
}

cmd_update() {
    cd "$REPO"
    git fetch origin --quiet

    # Every run lands in the state log; the settings page shows its tail.
    # The log is a convenience — past a couple of screens of history only
    # the tail is kept.
    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/flash-impulse"
    local log="$state_dir/ota.log"
    mkdir -p "$state_dir"
    if [ -f "$log" ] && [ "$(wc -c < "$log")" -gt 131072 ]; then
        tail -c 65536 "$log" > "$log.tail" && mv "$log.tail" "$log"
    fi
    exec > >(tee -a "$log") 2>&1
    echo "=== OTA run: $(date '+%Y-%m-%d %H:%M:%S') ==="
    trap 'echo "=== finished (code $?) ==="' EXIT

    local behind
    behind=$(git rev-list --count HEAD..origin/main)
    if [ "$behind" -eq 0 ]; then
        echo "Already up to date ($(git rev-parse --short HEAD))."
        return 0
    fi
    echo "Update available: $behind commit(s) behind origin/main."

    local dirty
    dirty=$(git status --porcelain | wc -l)
    if [ "$dirty" -ne 0 ]; then
        echo "Uncommitted changes in $REPO — they would mix into the pull:" >&2
        git status --short >&2
        die "commit or stash them first; the update does not move them behind your back"
    fi

    git pull --ff-only --quiet origin main
    echo "Updated to $(git rev-parse --short HEAD):"
    git log --oneline HEAD@"{1}"..HEAD | sed 's/^/  /'

    # Overlay, never --delete: the live config may hold files this repo does
    # not own, and an OTA must not evict them. Compared by checksum, not by
    # mtime — a commit that touches no configs (a script, a doc) must not
    # rewrite the live tree and wake every watcher in the shell for nothing.
    local changed
    changed=$(rsync -a --checksum --itemize-changes \
        "$REPO/dots/.config/" "$LIVE_CONFIG/" | grep -c '^>f' || true)

    if [ "$changed" -eq 0 ]; then
        echo "Configs already match — nothing to lay down, nothing to reload."
        return 0
    fi
    echo "Laid $changed file(s) onto $LIVE_CONFIG."

    hyprctl reload >/dev/null 2>&1 || echo "(hyprctl reload failed — is Hyprland running?)"
    # The shell picks QML changes up on its own; a reload nudge costs nothing.
    qs -c flash-impulse ipc call >/dev/null 2>&1 || true
    echo "Hyprland reloaded; the shell hot-reloads its QML."
    echo "If an update ever ships package or migration steps, run: ./install.sh install"
}

cmd_status() { repo_status; }

case "${1:-help}" in
    update) cmd_update ;;
    status) repo_status ;;
    help|*) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; echo; echo "usage: dots-manager.sh {update|status}" ;;
esac
