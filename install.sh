#!/usr/bin/env bash
# Flash-Impulse installer
#
# User-friendly front-end over the lower-level `./setup` machinery inherited
# from illogical-impulse. Adds: interactive component selection, timestamped
# backups with rollback, migration handling for existing installs, keyring-based
# API-key storage and an environment doctor.
#
# Usage: ./install.sh [subcommand] [options]   (see ./install.sh help)
#
# shellcheck disable=SC1091  # sourced libs live in sdata/, not followed by shellcheck
# shellcheck disable=SC2059  # printf formats deliberately embed the STY_* color vars
# shellcheck disable=SC2012  # ls is only used on our own timestamp-named backup dirs

set -o pipefail

cd "$(dirname "$0")" || exit 1
REPO_ROOT="$(pwd)"
export REPO_ROOT

# shellcheck source=sdata/lib/environment-variables.sh
source ./sdata/lib/environment-variables.sh

FI_NAME="Flash-Impulse"
FI_CONF_DIR="${XDG_CONFIG_HOME}/flash-impulse"
FI_STATE_DIR="${XDG_STATE_HOME}/flash-impulse"
FI_BACKUP_ROOT="${FI_STATE_DIR}/backups"
FI_LOG_DIR="${XDG_DATA_HOME}/flash-impulse/logs"
FI_INSTALL_MANIFEST="${FI_CONF_DIR}/install.json"
FI_KEYRING_SERVICE="flash-impulse"

# Directories under $HOME that an install can touch and that are worth
# snapshotting for rollback. Kept deliberately explicit (no wildcards) so a
# rollback never restores something we did not put at risk.
FI_BACKUP_TARGETS=(
  ".config/hypr"
  ".config/quickshell"
  ".config/fish"
  ".config/foot"
  ".config/kitty"
  ".config/fontconfig"
  ".config/matugen"
  ".config/Kvantum"
  ".config/qt5ct"
  ".config/qt6ct"
  ".config/gtk-3.0"
  ".config/gtk-4.0"
)

log()  { printf "${STY_CYAN}[flash-impulse]${STY_RST} %b\n" "$1"; }
warn() { printf "${STY_YELLOW}[flash-impulse]${STY_RST} %b\n" "$1"; }
err()  { printf "${STY_RED}[flash-impulse]${STY_RST} %b\n" "$1" >&2; }
die()  { err "$1"; exit 1; }

confirm() {
  # confirm "question" -> 0/1. Honors --yes.
  [[ "$FI_ASSUME_YES" == true ]] && return 0
  local answer
  read -r -p "$(printf "%b" "$1 [y/N] ")" answer
  [[ "$answer" =~ ^[yY] ]]
}

require_not_root() {
  if [[ "$(id -u)" == 0 ]]; then
    die "Do not run as root. The installer calls sudo only where needed."
  fi
}

#####################################################################################
# Backups & rollback

fi_backup_create() {
  local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
  local dir="${FI_BACKUP_ROOT}/${stamp}"
  local manifest="${dir}/MANIFEST"
  local found=false

  mkdir -p "$dir"
  : > "$manifest"
  for rel in "${FI_BACKUP_TARGETS[@]}"; do
    local src="${HOME}/${rel}"
    [[ -e "$src" ]] || continue
    found=true
    mkdir -p "${dir}/$(dirname "$rel")"
    cp -a "$src" "${dir}/${rel}"
    printf "%s\n" "$rel" >> "$manifest"
  done

  if [[ "$found" == true ]]; then
    log "Backup created: ${STY_BOLD}${dir}${STY_RST}"
    printf "%s" "$stamp" > "${FI_STATE_DIR}/last-backup"
  else
    rmdir "$dir" 2> /dev/null
    log "Nothing to back up (fresh system)."
  fi
}

fi_backup_list() {
  if [[ ! -d "$FI_BACKUP_ROOT" ]] || [[ -z "$(ls -A "$FI_BACKUP_ROOT" 2> /dev/null)" ]]; then
    log "No backups yet. They are created automatically by \"install\"."
    return 0
  fi
  log "Available backups (newest last), under ${FI_BACKUP_ROOT}:"
  local b
  for b in "$FI_BACKUP_ROOT"/*/; do
    b="$(basename "$b")"
    printf "  %s  (%s items)\n" "$b" "$(wc -l < "${FI_BACKUP_ROOT}/${b}/MANIFEST" 2> /dev/null || echo "?")"
  done
}

fi_rollback() {
  local stamp="$1"
  if [[ -z "$stamp" ]]; then
    stamp="$(ls -1 "$FI_BACKUP_ROOT" 2> /dev/null | sort | tail -n1)"
    [[ -n "$stamp" ]] || die "No backups found under ${FI_BACKUP_ROOT}."
  fi
  local dir="${FI_BACKUP_ROOT}/${stamp}"
  local manifest="${dir}/MANIFEST"
  [[ -f "$manifest" ]] || die "Backup \"${stamp}\" not found or has no manifest."

  warn "About to restore the following paths from backup ${STY_BOLD}${stamp}${STY_RST}:"
  sed 's/^/    ~\//' "$manifest"
  warn "Current contents of those paths will be replaced."
  confirm "Proceed with rollback?" || die "Rollback cancelled."

  local rel
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    rm -rf "${HOME:?}/${rel}"
    mkdir -p "$(dirname "${HOME}/${rel}")"
    cp -a "${dir}/${rel}" "${HOME}/${rel}"
    log "Restored ~/${rel}"
  done < "$manifest"
  log "Rollback complete. Restart Hyprland (or reboot) to apply."
}

#####################################################################################
# Secrets (libsecret / Secret Service)

fi_require_secret_tool() {
  command -v secret-tool > /dev/null 2>&1 && return 0
  err "secret-tool (libsecret) is not installed."
  err "  Arch/CachyOS:  sudo pacman -S libsecret"
  err "  Fedora:        sudo dnf install libsecret"
  return 1
}

fi_secret_set() {
  local provider="$1"
  [[ "$provider" =~ ^(gemini|openai|anthropic)$ ]] \
    || die "Unknown provider \"$provider\". Use: gemini | openai | anthropic"
  fi_require_secret_tool || exit 1
  log "Enter the ${provider} API key (input hidden), then press Enter:"
  local key
  read -r -s key
  [[ -n "$key" ]] || die "Empty key, nothing stored."
  printf "%s" "$key" | secret-tool store --label="${FI_NAME} ${provider} API key" \
    service "$FI_KEYRING_SERVICE" provider "$provider" \
    || die "secret-tool failed (is a Secret Service daemon like gnome-keyring running?)"
  log "Stored ${provider} key in the system keyring."
}

fi_secret_get() {
  fi_require_secret_tool || exit 1
  secret-tool lookup service "$FI_KEYRING_SERVICE" provider "$1"
}

fi_secret_clear() {
  fi_require_secret_tool || exit 1
  secret-tool clear service "$FI_KEYRING_SERVICE" provider "$1" \
    && log "Cleared $1 key."
}

#####################################################################################
# Doctor

fi_doctor() {
  log "${STY_BOLD}${FI_NAME} environment check${STY_RST}"
  source ./sdata/lib/dist-determine.sh
  printf "  distro:         %s (group: %s)\n" "${OS_DISTRO_ID:-?}" "${OS_GROUP_ID:-?}"

  local tool
  for tool in git rsync curl hyprctl qs secret-tool; do
    if command -v "$tool" > /dev/null 2>&1; then
      printf "  %-14s ${STY_GREEN}ok${STY_RST}\n" "$tool:"
    else
      printf "  %-14s ${STY_RED}missing${STY_RST}\n" "$tool:"
    fi
  done

  if command -v claude > /dev/null 2>&1; then
    printf "  %-14s ${STY_GREEN}ok${STY_RST} (%s)\n" "claude:" "$(claude --version 2> /dev/null | head -n1)"
  else
    printf "  %-14s ${STY_YELLOW}missing${STY_RST} — needed for the Claude Code AI backend\n" "claude:"
    printf "                 install: ${STY_UNDERLINE}https://claude.com/claude-code${STY_RST}\n"
  fi

  local p
  for p in gemini openai anthropic; do
    if command -v secret-tool > /dev/null 2>&1 && [[ -n "$(fi_secret_get "$p" 2> /dev/null)" ]]; then
      printf "  %-14s ${STY_GREEN}key stored${STY_RST}\n" "$p:"
    else
      printf "  %-14s ${STY_FAINT}no key${STY_RST} (set with: ./install.sh secrets set %s)\n" "$p:" "$p"
    fi
  done

  if [[ -f "${FIRSTRUN_FILE}" ]]; then
    printf "  install state: existing install detected (%s)\n" "${FIRSTRUN_FILE}"
  else
    printf "  install state: fresh (no previous install marker)\n"
  fi
}

#####################################################################################
# Install wizard

fi_choose_components() {
  # Populates FI_SETUP_FLAGS array. Interactive unless --yes.
  FI_SETUP_FLAGS=()
  if [[ "$FI_ASSUME_YES" == true ]]; then
    log "Non-interactive mode: full installation."
    return 0
  fi

  printf "\n${STY_BOLD}Select what to install.${STY_RST} Answer y/n (Enter = yes):\n\n"
  local deps setups files fish fontconfig misc
  read -r -p "  1) System packages & dependencies?        [Y/n] " deps
  read -r -p "  2) Permissions/services setup?            [Y/n] " setups
  read -r -p "  3) Config files (Hyprland + Quickshell)?  [Y/n] " files
  read -r -p "  4) Fish shell config?                     [Y/n] " fish
  read -r -p "  5) Fontconfig?                            [Y/n] " fontconfig
  read -r -p "  6) Misc app configs (terminal, qt, gtk)?  [Y/n] " misc

  [[ "$deps"       =~ ^[nN] ]] && FI_SETUP_FLAGS+=(--skip-alldeps)
  [[ "$setups"     =~ ^[nN] ]] && FI_SETUP_FLAGS+=(--skip-allsetups)
  [[ "$files"      =~ ^[nN] ]] && FI_SETUP_FLAGS+=(--skip-allfiles)
  [[ "$fish"       =~ ^[nN] ]] && FI_SETUP_FLAGS+=(--skip-fish)
  [[ "$fontconfig" =~ ^[nN] ]] && FI_SETUP_FLAGS+=(--skip-fontconfig)
  [[ "$misc"       =~ ^[nN] ]] && FI_SETUP_FLAGS+=(--skip-miscconf)
  return 0
}

fi_migration_prompt() {
  # Existing end-4/ii or Flash-Impulse install? Decide what to do with custom/*.
  local hypr_custom="${XDG_CONFIG_HOME}/hypr/custom"
  [[ -d "$hypr_custom" || -f "$FIRSTRUN_FILE" ]] || return 0

  printf "\n"
  warn "An existing illogical-impulse/${FI_NAME} install was detected."
  printf "  m) ${STY_BOLD}Migrate${STY_RST} — keep your personal ~/.config/hypr/custom/* tweaks (recommended)\n"
  printf "  c) ${STY_BOLD}Clean${STY_RST}   — move the old custom configs aside and start from the fork defaults\n"
  if [[ "$FI_ASSUME_YES" == true ]]; then
    log "Non-interactive mode: migrating (keeping custom configs)."
    return 0
  fi
  local answer
  read -r -p "Migrate or clean? [M/c] " answer
  if [[ "$answer" =~ ^[cC] ]]; then
    local aside="${hypr_custom}.pre-flash-impulse"
    if [[ -d "$hypr_custom" ]]; then
      rm -rf "$aside"
      mv "$hypr_custom" "$aside"
      log "Moved old custom configs to ${aside}"
    fi
  else
    log "Keeping existing custom configs (the deploy step never overwrites them)."
  fi
}

fi_write_install_manifest() {
  mkdir -p "$FI_CONF_DIR" "$FI_LOG_DIR"
  {
    printf '{\n'
    printf '  "installer": "flash-impulse",\n'
    printf '  "date": "%s",\n' "$(date -Iseconds)"
    printf '  "setup_flags": "%s",\n' "${FI_SETUP_FLAGS[*]}"
    printf '  "backup": "%s"\n' "$(cat "${FI_STATE_DIR}/last-backup" 2> /dev/null)"
    printf '}\n'
  } > "$FI_INSTALL_MANIFEST"
}

fi_install() {
  require_not_root
  printf "${STY_BOLD}${STY_CYAN}\n%s installer\n${STY_RST}" "$FI_NAME"
  printf "${STY_FAINT}Fork of end-4/dots-hyprland + better-ii-ai. GPL-3.0.\n${STY_RST}\n"

  fi_choose_components
  fi_migration_prompt

  if [[ "$FI_DRY_RUN" == true ]]; then
    log "[dry-run] Would create backup of: ${FI_BACKUP_TARGETS[*]}"
    log "[dry-run] Would run: ./setup install ${FI_SETUP_FLAGS[*]} $*"
    return 0
  fi

  mkdir -p "$FI_STATE_DIR"
  fi_backup_create

  log "Handing over to the setup engine..."
  local extra_flags=()
  [[ "$FI_ASSUME_YES" == true ]] && extra_flags+=(--force)
  # Our own backup already ran; skip the legacy single-dir backup.
  bash ./setup install --skip-backup "${extra_flags[@]}" "${FI_SETUP_FLAGS[@]}" "$@" \
    || die "Setup engine failed. Your pre-install backup is intact — see: ./install.sh backups"

  fi_write_install_manifest

  printf "\n"
  log "${STY_BOLD}Done.${STY_RST}"
  log "Next steps:"
  log "  • AI keys (optional):   ./install.sh secrets set gemini"
  log "  • Claude Code backend:  install \"claude\" CLI and log in — see ./install.sh doctor"
  log "  • If anything broke:    ./install.sh rollback"
}

#####################################################################################
# CLI

showhelp() {
  printf "%b" "${STY_BOLD}${FI_NAME} installer${STY_RST}

Syntax: ./install.sh [subcommand] [options]

Subcommands:
  install         Interactive installation (default when no subcommand given)
  rollback [ID]   Restore configs from a backup (latest if ID omitted)
  backups         List available backups
  secrets set <gemini|openai|anthropic>    Store an API key in the system keyring
  secrets get <provider>                   Print a stored key
  secrets clear <provider>                 Remove a stored key
  doctor          Check distro, dependencies, claude CLI and stored keys
  help            This message

Options for install:
  -y, --yes       Non-interactive: full install, migrate existing configs
      --dry-run   Print what would happen without changing anything
  Anything else is passed through to the underlying \"./setup install\".

Power users can still call ./setup directly for fine-grained control.
"
}

FI_ASSUME_YES=false
FI_DRY_RUN=false
FI_SETUP_FLAGS=()

main() {
  local subcmd="${1:-install}"
  case "$subcmd" in
    install | "") shift $(($# > 0 ? 1 : 0)) ;;
    rollback) shift; fi_rollback "${1:-}"; exit ;;
    backups) fi_backup_list; exit ;;
    secrets)
      shift
      case "${1:-}" in
        set)   fi_secret_set "${2:-}"; exit ;;
        get)   fi_secret_get "${2:-}"; exit ;;
        clear) fi_secret_clear "${2:-}"; exit ;;
        *) die "Usage: ./install.sh secrets <set|get|clear> <provider>" ;;
      esac ;;
    doctor) fi_doctor; exit ;;
    help | -h | --help) showhelp; exit ;;
    -*) : ;; # options without subcommand -> treat as install
    *) die "Unknown subcommand \"$subcmd\". See: ./install.sh help" ;;
  esac

  # Parse install options; unknown ones are passed to ./setup install.
  local passthrough=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y | --yes) FI_ASSUME_YES=true ;;
      --dry-run) FI_DRY_RUN=true ;;
      *) passthrough+=("$1") ;;
    esac
    shift
  done
  fi_install "${passthrough[@]}"
}

main "$@"
