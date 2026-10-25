#!/usr/bin/env bash
set -euo pipefail

geometry=$(slurp 2>/dev/null) || exit 0
[[ -z "$geometry" ]] && exit 0

tmp_img=$(mktemp /tmp/snip_search_XXXXXX.png)
trap 'rm -f "$tmp_img"' EXIT

grim -g "$geometry" "$tmp_img" || exit 0

imageLink=$(curl -sF files[]=@"$tmp_img" 'https://uguu.se/upload' 2>/dev/null | jq -r '.files[0].url // empty' 2>/dev/null) || true
if [[ -n "$imageLink" && "$imageLink" != "null" ]]; then
    xdg-open "https://lens.google.com/uploadbyurl?url=${imageLink}"
fi

