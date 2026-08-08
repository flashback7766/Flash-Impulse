#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source $(eval echo ${FLASH_IMPULSE_VENV:-$ILLOGICAL_IMPULSE_VIRTUAL_ENV})/bin/activate
python3 "$SCRIPT_DIR/web_search.py" "$@"
deactivate
