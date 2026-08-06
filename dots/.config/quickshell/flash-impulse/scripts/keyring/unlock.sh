#!/usr/bin/env bash
# Based on https://unix.stackexchange.com/a/602935

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Skip if already unlocked
if "${SCRIPT_DIR}/is_unlocked.sh"; then
    exit 1
fi

# Prompt for password if not provided
if [[ -z "${UNLOCK_PASSWORD}" ]]; then
    echo -n 'Login password: ' >&2
    read -s UNLOCK_PASSWORD || return
fi

# Hand the password to the daemon that is already running, over its control
# socket. This used to killall gnome-keyring-daemon and start a replacement
# with --login, which was worse than doing nothing: every app holding a Secret
# Service connection — gh, Electron's safeStorage, the shell's own key store —
# lost it, and collections that were open before the unlock came back locked,
# so the next thing wanting a secret popped a password dialog. Worse, --login
# against an existing login keyring whose password does not match moves it
# aside as login.keyring.backup-<date> and creates an empty one in its place.
#
# --start is a no-op when a daemon is already up; it is here so this still
# works if one somehow is not.
gnome-keyring-daemon --start --components=secrets >/dev/null 2>&1
printf '%s' "${UNLOCK_PASSWORD}" | gnome-keyring-daemon --unlock >/dev/null 2>&1
unset UNLOCK_PASSWORD
echo '' >&2
