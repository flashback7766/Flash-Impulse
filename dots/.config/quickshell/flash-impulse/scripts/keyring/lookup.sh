#!/usr/bin/env bash
# Reads the shell's keyring blob and prints it.
#
# The entry used to be stored under application=illogical-impulse. Renaming the
# attribute outright would have orphaned every key already in someone's keyring
# — secret-tool matches on attributes, so the old entry simply stops being
# found. So: look under the new name first, fall back to the old one, and let
# the next write land under the new name. Nothing is deleted; the stale entry is
# harmless and losing an API key is not.
data=$(secret-tool lookup 'application' 'flash-impulse' 2> /dev/null)
if [[ -z "$data" ]]; then
    data=$(secret-tool lookup 'application' 'illogical-impulse' 2> /dev/null)
fi
[[ -n "$data" ]] || exit 1
printf '%s' "$data"
