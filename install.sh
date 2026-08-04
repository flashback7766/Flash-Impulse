#!/usr/bin/env bash
# Flash-Impulse installer.
#
# A front-end over the lower-level `./setup` engine inherited from
# illogical-impulse. Two faces, one binary:
#
#   * Run it bare on a terminal and you get a full-screen TUI — arrow keys,
#     checkboxes, a review screen before anything is touched.
#   * Give it a subcommand or a flag, or run it with stdout redirected, and it
#     behaves like any other CLI: subcommands, --help per command, --json where
#     output is worth parsing, and exit codes that mean something.
#
# The TUI covers *choosing*, never *executing*. Package installs stream pacman
# output and can stop on a sudo password prompt, and there is no honest way to
# render that inside a managed screen — so once the choices are made the TUI
# tears down and execution happens on the normal scrolling terminal.
#
# shellcheck disable=SC1091  # sourced libs live in sdata/, not followed by shellcheck
# shellcheck disable=SC2059  # printf formats deliberately embed colour vars
# shellcheck disable=SC2012  # ls is only used on our own timestamp-named backup dirs

set -o pipefail

cd "$(dirname "$0")" || exit 1
REPO_ROOT="$(pwd)"
export REPO_ROOT

# shellcheck source=sdata/lib/environment-variables.sh
source ./sdata/lib/environment-variables.sh
# shellcheck source=sdata/lib/tui.sh
source ./sdata/lib/tui.sh

FI_NAME="Flash-Impulse"
FI_VERSION="1.0"
FI_CONF_DIR="${XDG_CONFIG_HOME}/flash-impulse"
FI_STATE_DIR="${XDG_STATE_HOME}/flash-impulse"
FI_BACKUP_ROOT="${FI_STATE_DIR}/backups"
FI_LOG_DIR="${XDG_DATA_HOME}/flash-impulse/logs"
FI_INSTALL_MANIFEST="${FI_CONF_DIR}/install.json"
FI_KEYRING_SERVICE="flash-impulse"
FI_PROVIDERS=(gemini openai anthropic)

# Exit codes, so callers can branch on *why* it stopped rather than parsing text.
readonly EX_OK=0 EX_FAIL=1 EX_USAGE=2 EX_CANCELLED=3 EX_MISSING_DEP=4

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

# The installable units, in engine order. Each row is:
#   key | SKIP_ variable | label | one-line description
FI_COMPONENTS=(
  "deps|SKIP_ALLDEPS|System packages & dependencies|Everything Hyprland and the shell need to run"
  "setups|SKIP_ALLSETUPS|Permissions & services|Group membership, systemd user units"
  "files|SKIP_ALLFILES|Config files|Hyprland and Quickshell — the desktop itself"
  "fish|SKIP_FISH|Fish shell config|Prompt, aliases, the Hyprland autostart on tty1"
  "fontconfig|SKIP_FONTCONFIG|Fontconfig|Font fallback and rendering rules"
  "misc|SKIP_MISCCONF|Misc app configs|Terminal, Qt and GTK theming"
)

# Runtime flags
FI_ASSUME_YES=false
FI_DRY_RUN=false
FI_JSON=false
FI_QUIET=false
FI_COLOR=auto

#####################################################################################
# Output

# Colour is on when we are talking to a terminal, off when redirected, and always
# whatever --color/--no-color said if the user was explicit.
FI_STY_SAVED=false
ui_init_color() {
  # The engine's STY_* codes get blanked alongside ours, so a redirected run is
  # plain all the way down rather than plain only in this file's own output.
  if [[ "$FI_STY_SAVED" != true ]]; then
    FI_STY_SAVED=true
    STY_RED_DEF="$STY_RED" STY_GREEN_DEF="$STY_GREEN" STY_YELLOW_DEF="$STY_YELLOW"
    STY_BLUE_DEF="$STY_BLUE" STY_PURPLE_DEF="$STY_PURPLE" STY_CYAN_DEF="$STY_CYAN"
    STY_BOLD_DEF="$STY_BOLD" STY_FAINT_DEF="$STY_FAINT" STY_SLANT_DEF="$STY_SLANT"
    STY_UNDERLINE_DEF="$STY_UNDERLINE" STY_INVERT_DEF="$STY_INVERT" STY_RST_DEF="$STY_RST"
  fi

  local want=false
  case "$FI_COLOR" in
    always) want=true ;;
    never)  want=false ;;
    auto)   [[ -t 1 ]] && want=true ;;
  esac

  if [[ "$want" == true ]]; then
    tui_use_color
    STY_RED="$STY_RED_DEF" STY_GREEN="$STY_GREEN_DEF" STY_YELLOW="$STY_YELLOW_DEF"
    STY_BLUE="$STY_BLUE_DEF" STY_PURPLE="$STY_PURPLE_DEF" STY_CYAN="$STY_CYAN_DEF"
    STY_BOLD="$STY_BOLD_DEF" STY_FAINT="$STY_FAINT_DEF" STY_SLANT="$STY_SLANT_DEF"
    STY_UNDERLINE="$STY_UNDERLINE_DEF" STY_INVERT="$STY_INVERT_DEF" STY_RST="$STY_RST_DEF"
  else
    tui_no_color
    STY_RED="" STY_GREEN="" STY_YELLOW="" STY_BLUE="" STY_PURPLE="" STY_CYAN=""
    STY_BOLD="" STY_FAINT="" STY_SLANT="" STY_UNDERLINE="" STY_INVERT="" STY_RST=""
  fi
}

ui_say()   { [[ "$FI_QUIET" == true ]] || printf '%b\n' "$1"; }
ui_title() { [[ "$FI_QUIET" == true ]] || printf '\n%b%b%b\n' "$TUI_BOLD" "$1" "$TUI_RST"; }
ui_step()  { [[ "$FI_QUIET" == true ]] || printf '  %b▸%b %b\n' "$TUI_ACCENT" "$TUI_RST" "$1"; }
ui_ok()    { [[ "$FI_QUIET" == true ]] || printf '  %b✓%b %b\n' "$TUI_OK" "$TUI_RST" "$1"; }
ui_warn()  { printf '  %b!%b %b\n' "$TUI_WARN" "$TUI_RST" "$1" >&2; }
ui_err()   { printf '  %b✗%b %b\n' "$TUI_ERR" "$TUI_RST" "$1" >&2; }
die()      { ui_err "$1"; exit "${2:-$EX_FAIL}"; }

# JSON string escaping, enough for the paths and identifiers we emit.
json_str() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

confirm() {
  # confirm "question" -> 0/1. --yes answers everything affirmatively.
  [[ "$FI_ASSUME_YES" == true ]] && return 0
  [[ -t 0 ]] || return 1   # no terminal to ask on: refuse rather than assume
  local answer
  read -r -p "$(printf '  %b?%b %b [y/N] ' "$TUI_ACCENT" "$TUI_RST" "$1")" answer
  [[ "$answer" =~ ^[yY] ]]
}

require_not_root() {
  [[ "$(id -u)" == 0 ]] \
    && die "Do not run as root. The installer calls sudo only where it needs to."
  return 0
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
  local rel
  for rel in "${FI_BACKUP_TARGETS[@]}"; do
    local src="${HOME}/${rel}"
    [[ -e "$src" ]] || continue
    found=true
    mkdir -p "${dir}/$(dirname "$rel")"
    cp -a "$src" "${dir}/${rel}"
    printf '%s\n' "$rel" >> "$manifest"
  done

  if [[ "$found" == true ]]; then
    ui_ok "Backup created: ${TUI_BOLD}${dir}${TUI_RST}"
    printf '%s' "$stamp" > "${FI_STATE_DIR}/last-backup"
  else
    rmdir "$dir" 2>/dev/null
    ui_ok "Nothing to back up (fresh system)."
  fi
}

fi_backups_list() {
  local -a stamps=()
  if [[ -d "$FI_BACKUP_ROOT" ]]; then
    local b
    for b in "$FI_BACKUP_ROOT"/*/; do
      [[ -d "$b" ]] || continue
      stamps+=("$(basename "$b")")
    done
  fi

  if [[ "$FI_JSON" == true ]]; then
    printf '{"root":%s,"backups":[' "$(json_str "$FI_BACKUP_ROOT")"
    local i first=true
    for i in "${stamps[@]}"; do
      [[ "$first" == true ]] || printf ','
      first=false
      printf '{"id":%s,"items":%s}' \
        "$(json_str "$i")" \
        "$(wc -l < "${FI_BACKUP_ROOT}/${i}/MANIFEST" 2>/dev/null || echo 0)"
    done
    printf ']}\n'
    return 0
  fi

  if (( ${#stamps[@]} == 0 )); then
    ui_say "No backups yet. One is taken automatically at the start of every install."
    return 0
  fi
  ui_title "Backups in ${FI_BACKUP_ROOT}"
  local i
  for i in "${stamps[@]}"; do
    printf '  %s  %b(%s paths)%b\n' \
      "$i" "$TUI_DIM" "$(wc -l < "${FI_BACKUP_ROOT}/${i}/MANIFEST" 2>/dev/null || echo '?')" "$TUI_RST"
  done
}

fi_rollback() {
  local stamp="${1:-}"
  if [[ -z "$stamp" ]]; then
    stamp="$(ls -1 "$FI_BACKUP_ROOT" 2>/dev/null | sort | tail -n1)"
    [[ -n "$stamp" ]] || die "No backups found under ${FI_BACKUP_ROOT}."
  fi
  local dir="${FI_BACKUP_ROOT}/${stamp}"
  local manifest="${dir}/MANIFEST"
  [[ -f "$manifest" ]] || die "Backup \"${stamp}\" not found, or it has no manifest."

  ui_title "Rollback to ${stamp}"
  ui_say "  These paths will be replaced by their backed-up contents:"
  sed "s|^|    ~/|" "$manifest"
  confirm "Proceed with rollback?" || exit "$EX_CANCELLED"

  local rel
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    rm -rf "${HOME:?}/${rel}"
    mkdir -p "$(dirname "${HOME}/${rel}")"
    cp -a "${dir}/${rel}" "${HOME}/${rel}"
    ui_ok "Restored ~/${rel}"
  done < "$manifest"
  ui_say ""
  ui_ok "Rollback complete. Restart Hyprland (or reboot) to apply."
}

#####################################################################################
# Secrets (libsecret / Secret Service)

fi_require_secret_tool() {
  command -v secret-tool > /dev/null 2>&1 && return 0
  ui_err "secret-tool (libsecret) is not installed."
  ui_say "      Arch/CachyOS:  sudo pacman -S libsecret"
  ui_say "      Fedora:        sudo dnf install libsecret"
  return 1
}

fi_valid_provider() {
  local p
  for p in "${FI_PROVIDERS[@]}"; do [[ "$p" == "$1" ]] && return 0; done
  return 1
}

fi_secret_set() {
  local provider="${1:-}"
  fi_valid_provider "$provider" \
    || die "Unknown provider \"${provider}\". Use one of: ${FI_PROVIDERS[*]}" "$EX_USAGE"
  fi_require_secret_tool || exit "$EX_MISSING_DEP"
  ui_say "  Paste the ${provider} API key (input is hidden), then press Enter:"
  local key
  read -r -s key
  [[ -n "$key" ]] || die "Empty key, nothing stored." "$EX_USAGE"
  printf '%s' "$key" | secret-tool store --label="${FI_NAME} ${provider} API key" \
    service "$FI_KEYRING_SERVICE" provider "$provider" \
    || die "secret-tool failed. Is a Secret Service daemon (gnome-keyring) running?"
  ui_ok "Stored the ${provider} key in the system keyring."
}

fi_secret_get() {
  fi_valid_provider "${1:-}" \
    || die "Unknown provider \"${1:-}\". Use one of: ${FI_PROVIDERS[*]}" "$EX_USAGE"
  fi_require_secret_tool || exit "$EX_MISSING_DEP"
  secret-tool lookup service "$FI_KEYRING_SERVICE" provider "$1"
}

fi_secret_clear() {
  fi_valid_provider "${1:-}" \
    || die "Unknown provider \"${1:-}\". Use one of: ${FI_PROVIDERS[*]}" "$EX_USAGE"
  fi_require_secret_tool || exit "$EX_MISSING_DEP"
  secret-tool clear service "$FI_KEYRING_SERVICE" provider "$1" && ui_ok "Cleared the $1 key."
}

fi_secret_has() {
  command -v secret-tool > /dev/null 2>&1 || return 1
  [[ -n "$(secret-tool lookup service "$FI_KEYRING_SERVICE" provider "$1" 2>/dev/null)" ]]
}

fi_secrets_list() {
  local p
  if [[ "$FI_JSON" == true ]]; then
    printf '{'
    local first=true
    for p in "${FI_PROVIDERS[@]}"; do
      [[ "$first" == true ]] || printf ','
      first=false
      if fi_secret_has "$p"; then printf '%s:true' "$(json_str "$p")"
      else printf '%s:false' "$(json_str "$p")"; fi
    done
    printf '}\n'
    return 0
  fi
  ui_title "Stored API keys"
  for p in "${FI_PROVIDERS[@]}"; do
    if fi_secret_has "$p"; then
      printf '  %b✓%b %-10s stored\n' "$TUI_OK" "$TUI_RST" "$p"
    else
      printf '  %b·%b %-10s %bnot set%b\n' "$TUI_DIM" "$TUI_RST" "$p" "$TUI_DIM" "$TUI_RST"
    fi
  done
}

#####################################################################################
# Doctor

fi_doctor() {
  source ./sdata/lib/dist-determine.sh
  # /etc/os-release is free-form enough that values arrive with stray
  # whitespace — this machine ships `ID=arch  `, which then shows up quoted in
  # --json output and misaligns the plain one.
  OS_DISTRO_ID="$(printf '%s' "${OS_DISTRO_ID:-}" | tr -d '[:space:]')"
  OS_GROUP_ID="$(printf '%s' "${OS_GROUP_ID:-}" | tr -d '[:space:]')"

  local -a tools=(git rsync curl hyprctl qs secret-tool claude)
  local -a missing=()
  local t p

  if [[ "$FI_JSON" == true ]]; then
    printf '{"distro":%s,"group":%s,"tools":{' \
      "$(json_str "${OS_DISTRO_ID:-unknown}")" "$(json_str "${OS_GROUP_ID:-unknown}")"
    local first=true
    for t in "${tools[@]}"; do
      [[ "$first" == true ]] || printf ','
      first=false
      if command -v "$t" > /dev/null 2>&1; then printf '%s:true' "$(json_str "$t")"
      else printf '%s:false' "$(json_str "$t")"; fi
    done
    printf '},"keys":{'
    first=true
    for p in "${FI_PROVIDERS[@]}"; do
      [[ "$first" == true ]] || printf ','
      first=false
      if fi_secret_has "$p"; then printf '%s:true' "$(json_str "$p")"
      else printf '%s:false' "$(json_str "$p")"; fi
    done
    printf '},"installed":%s}\n' "$([[ -f "$FIRSTRUN_FILE" ]] && echo true || echo false)"
    return 0
  fi

  ui_title "Environment"
  printf '  %-14s %s %b(%s)%b\n' "distro" "${OS_DISTRO_ID:-unknown}" \
    "$TUI_DIM" "group: ${OS_GROUP_ID:-unknown}" "$TUI_RST"

  ui_title "Tools"
  for t in "${tools[@]}"; do
    if command -v "$t" > /dev/null 2>&1; then
      printf '  %b✓%b %-14s\n' "$TUI_OK" "$TUI_RST" "$t"
    elif [[ "$t" == claude ]]; then
      printf '  %b·%b %-14s %boptional — the Claude Code AI backend needs it%b\n' \
        "$TUI_DIM" "$TUI_RST" "$t" "$TUI_DIM" "$TUI_RST"
    else
      printf '  %b✗%b %-14s %bmissing%b\n' "$TUI_ERR" "$TUI_RST" "$t" "$TUI_ERR" "$TUI_RST"
      missing+=("$t")
    fi
  done

  ui_title "API keys"
  for p in "${FI_PROVIDERS[@]}"; do
    if fi_secret_has "$p"; then
      printf '  %b✓%b %-14s stored\n' "$TUI_OK" "$TUI_RST" "$p"
    else
      printf '  %b·%b %-14s %bnot set — ./install.sh secrets set %s%b\n' \
        "$TUI_DIM" "$TUI_RST" "$p" "$TUI_DIM" "$p" "$TUI_RST"
    fi
  done

  ui_title "Install state"
  if [[ -f "$FIRSTRUN_FILE" ]]; then
    printf '  previously installed %b(%s)%b\n' "$TUI_DIM" "$FIRSTRUN_FILE" "$TUI_RST"
  else
    printf '  fresh — no previous install marker\n'
  fi

  ui_say ""
  if (( ${#missing[@]} > 0 )); then
    ui_warn "Missing required tools: ${missing[*]}"
    return "$EX_MISSING_DEP"
  fi
  ui_ok "Everything required is present."
}

#####################################################################################
# Component selection

# Reads FI_COMPONENTS, writes:
#   FI_SELECTED      — keys the user kept, for the manifest and the review screen
#   SKIP_<X>=true    — exported for the engine, for the ones they dropped
fi_apply_selection() {
  # fi_apply_selection <state...>  where state[i] is on/off for FI_COMPONENTS[i]
  local -a states=("$@")
  FI_SELECTED=()
  local i row key skipvar
  for (( i = 0; i < ${#FI_COMPONENTS[@]}; i++ )); do
    row="${FI_COMPONENTS[$i]}"
    key="${row%%|*}"
    skipvar="$(cut -d'|' -f2 <<< "$row")"
    if [[ "${states[$i]}" == "on" ]]; then
      FI_SELECTED+=("$key")
    else
      export "${skipvar}=true"
    fi
  done
}

fi_select_all() {
  local -a states=()
  local i
  for (( i = 0; i < ${#FI_COMPONENTS[@]}; i++ )); do states+=("on"); done
  fi_apply_selection "${states[@]}"
}

#####################################################################################
# TUI flow

# Returns 0 to go ahead, EX_CANCELLED if the user backed out. On success
# FI_SELECTED and the SKIP_* exports are set, and FI_MIGRATE holds keep/clean.
fi_wizard() {
  tui_enter || return 1

  local -a states=()
  local i row
  TUI_CL_LABEL=() TUI_CL_DESC=() TUI_CL_STATE=()
  for (( i = 0; i < ${#FI_COMPONENTS[@]}; i++ )); do
    row="${FI_COMPONENTS[$i]}"
    TUI_CL_LABEL+=("$(cut -d'|' -f3 <<< "$row")")
    TUI_CL_DESC+=("$(cut -d'|' -f4 <<< "$row")")
    TUI_CL_STATE+=("on")
  done

  if ! tui_checklist "What should be installed?"; then
    tui_leave; return "$EX_CANCELLED"
  fi
  states=("${TUI_CL_STATE[@]}")

  # Migration only matters when there is something to migrate.
  FI_MIGRATE="keep"
  local hypr_custom="${XDG_CONFIG_HOME}/hypr/custom"
  if [[ -d "$hypr_custom" || -f "$FIRSTRUN_FILE" ]]; then
    TUI_RD_LABEL=("Keep my tweaks" "Start clean")
    TUI_RD_DESC=(
      "Leave ~/.config/hypr/custom/* alone — the deploy step never overwrites it"
      "Move the old custom configs aside and use this fork's defaults"
    )
    TUI_RD_CHOICE=0
    if ! tui_radio "An existing install was found. What about your custom configs?"; then
      tui_leave; return "$EX_CANCELLED"
    fi
    [[ "$TUI_RD_CHOICE" == 1 ]] && FI_MIGRATE="clean"
  fi

  # Review before anything is touched.
  TUI_PAGE_LINE=()
  local any=false
  for (( i = 0; i < ${#FI_COMPONENTS[@]}; i++ )); do
    if [[ "${states[$i]}" == "on" ]]; then
      TUI_PAGE_LINE+=("${TUI_OK}✓${TUI_RST} $(cut -d'|' -f3 <<< "${FI_COMPONENTS[$i]}")")
      any=true
    else
      TUI_PAGE_LINE+=("${TUI_DIM}· $(cut -d'|' -f3 <<< "${FI_COMPONENTS[$i]}") — skipped${TUI_RST}")
    fi
  done
  TUI_PAGE_LINE+=("")
  if [[ "$FI_MIGRATE" == "clean" ]]; then
    TUI_PAGE_LINE+=("${TUI_WARN}Existing custom configs will be moved aside.${TUI_RST}")
  else
    TUI_PAGE_LINE+=("${TUI_DIM}Existing custom configs are kept as they are.${TUI_RST}")
  fi
  TUI_PAGE_LINE+=("${TUI_DIM}A timestamped backup is taken before anything changes.${TUI_RST}")
  [[ "$FI_DRY_RUN" == true ]] \
    && TUI_PAGE_LINE+=("${TUI_WARN}Dry run — nothing will actually be written.${TUI_RST}")

  if [[ "$any" != true ]]; then
    TUI_PAGE_LINE+=("" "${TUI_WARN}Nothing is selected; this would do nothing.${TUI_RST}")
  fi

  if ! tui_review "Review" "Start the install?"; then
    tui_leave; return "$EX_CANCELLED"
  fi

  tui_leave
  fi_apply_selection "${states[@]}"
  return 0
}

#####################################################################################
# Install

fi_do_migration() {
  local hypr_custom="${XDG_CONFIG_HOME}/hypr/custom"
  [[ -d "$hypr_custom" ]] || return 0
  if [[ "${FI_MIGRATE:-keep}" == "clean" ]]; then
    local aside="${hypr_custom}.pre-flash-impulse"
    rm -rf "$aside"
    mv "$hypr_custom" "$aside"
    ui_ok "Moved old custom configs to ${aside}"
  else
    ui_ok "Keeping existing custom configs."
  fi
}

fi_write_install_manifest() {
  mkdir -p "$FI_CONF_DIR" "$FI_LOG_DIR"
  {
    printf '{\n'
    printf '  "installer": "flash-impulse",\n'
    printf '  "version": %s,\n' "$(json_str "$FI_VERSION")"
    printf '  "date": %s,\n' "$(json_str "$(date -Iseconds)")"
    printf '  "components": %s,\n' "$(json_str "${FI_SELECTED[*]}")"
    printf '  "migration": %s,\n' "$(json_str "${FI_MIGRATE:-keep}")"
    printf '  "backup": %s\n' "$(json_str "$(cat "${FI_STATE_DIR}/last-backup" 2>/dev/null)")"
    printf '}\n'
  } > "$FI_INSTALL_MANIFEST"
}

fi_install() {
  require_not_root

  # The greeting step is the engine's own interactive intro; this file provides
  # the UX, so it is always suppressed.
  export SKIP_ALLGREETING=true

  local interactive=false
  [[ "$FI_ASSUME_YES" != true ]] && tui_available && interactive=true

  if [[ "$interactive" == true ]]; then
    fi_wizard
    local rc=$?
    if (( rc == EX_CANCELLED )); then
      ui_say "Cancelled — nothing was changed."
      exit "$EX_CANCELLED"
    elif (( rc != 0 )); then
      # No usable terminal after all; fall through to the non-interactive path.
      interactive=false
    fi
  fi

  if [[ "$interactive" != true ]]; then
    fi_select_all
    FI_MIGRATE="keep"
    ui_say "Non-interactive: installing everything, keeping existing custom configs."
  fi

  printf '\n%b%s%b %b· installing%b\n\n' \
    "$TUI_ACCENT$TUI_BOLD" "$FI_NAME" "$TUI_RST" "$TUI_DIM" "$TUI_RST"

  # Non-interactive engine runs shouldn't pause for confirmation per command.
  [[ "$FI_ASSUME_YES" == true ]] && export ask=false

  # Load the engine as a library (two layers: this file is UX, the engine is logic).
  # shellcheck source=sdata/lib/engine.sh
  source ./sdata/lib/engine.sh
  # engine.sh re-sources environment-variables.sh, which assigns the STY_*
  # codes unconditionally and so undoes the --no-color/redirect decision. Put
  # it back, or a piped install writes escape codes into the log.
  ui_init_color

  if [[ "$FI_DRY_RUN" == true ]]; then
    ui_step "Dry run — walking the engine flow without changing anything"
    export DRY_RUN=true ask=false
    engine_run_install
    ui_say ""
    ui_ok "Dry run finished. Would have backed up: ${FI_BACKUP_TARGETS[*]}"
    return 0
  fi

  mkdir -p "$FI_STATE_DIR"
  ui_step "Backing up existing configs"
  fi_backup_create
  fi_do_migration

  # Our own timestamped backup already ran; the engine should not take a second.
  export SKIP_BACKUP=true
  ui_step "Running the install engine"
  ui_say ""
  # The step scripts are written for `set -e`; give them that without imposing
  # it on this file's own error handling.
  if ! ( set -e; engine_run_install ); then
    ui_say ""
    ui_err "The install engine failed."
    ui_say "      Your pre-install backup is intact:  ./install.sh backups"
    ui_say "      Restore it with:                    ./install.sh rollback"
    exit "$EX_FAIL"
  fi

  fi_write_install_manifest

  ui_say ""
  ui_ok "${TUI_BOLD}Done.${TUI_RST}"
  ui_title "Next"
  ui_say "  • Store an AI key      ./install.sh secrets set gemini"
  ui_say "  • Claude Code backend  install the \"claude\" CLI, then ./install.sh doctor"
  ui_say "  • Something broke      ./install.sh rollback"
  ui_say ""
}

#####################################################################################
# Help

help_main() {
  printf '%b' "${TUI_ACCENT}${TUI_BOLD}${FI_NAME}${TUI_RST} installer ${TUI_DIM}v${FI_VERSION}${TUI_RST}

${TUI_BOLD}USAGE${TUI_RST}
  ./install.sh [<command>] [<options>]

  With no command it installs; on a terminal that means the full-screen
  wizard, elsewhere a plain non-interactive run.

${TUI_BOLD}COMMANDS${TUI_RST}
  install              Install the desktop (default)
  doctor               Check distro, tools, keys and install state
  backups              List the backups taken before each install
  rollback [<id>]      Restore configs from a backup, newest if no id
  secrets <sub>        Manage API keys in the system keyring
  version              Print the version
  help [<command>]     Help for a command

${TUI_BOLD}OPTIONS${TUI_RST}
  -y, --yes            Answer yes to everything; skips the wizard
      --dry-run        Walk the whole flow without changing anything
      --json           Machine-readable output (doctor, backups, secrets list)
  -q, --quiet          Only warnings and errors
      --color <when>   always | never | auto (default: auto)
      --no-color       Same as --color never
  -h, --help           This message
  -V, --version        Print the version

${TUI_BOLD}EXIT CODES${TUI_RST}
  0 ok · 1 failed · 2 bad usage · 3 cancelled · 4 missing dependency

${TUI_DIM}For per-step flags and fontset choices, ./setup takes the engine directly.${TUI_RST}
"
}

help_install() {
  printf '%b' "${TUI_BOLD}install${TUI_RST} — install the desktop

  ./install.sh install [-y] [--dry-run]

  On a terminal, opens a wizard: pick components with the arrow keys and
  space, choose what happens to an existing install, then review before
  anything is written. Execution itself always happens on the normal
  terminal, because package managers need to show their output and may ask
  for a sudo password.

  A timestamped backup of every config directory the install can touch is
  taken first; ./install.sh rollback puts it back.

  -y, --yes     No wizard: install everything, keep existing custom configs.
      --dry-run Walk the engine without writing anything.
"
}

help_secrets() {
  printf '%b' "${TUI_BOLD}secrets${TUI_RST} — API keys in the system keyring

  ./install.sh secrets list
  ./install.sh secrets set <provider>
  ./install.sh secrets get <provider>
  ./install.sh secrets clear <provider>

  Providers: ${FI_PROVIDERS[*]}

  Keys are stored through libsecret, so they live in the login keyring
  rather than in a dotfile. \"get\" prints the raw key on stdout so it can
  be piped; everything else is for humans.
"
}

help_rollback() {
  printf '%b' "${TUI_BOLD}rollback${TUI_RST} — restore configs from a backup

  ./install.sh rollback [<id>]

  With no id, the newest backup is used. Ids come from ./install.sh backups.
  Only the paths recorded in that backup's MANIFEST are touched.
"
}

help_for() {
  case "${1:-}" in
    install)  help_install ;;
    secrets)  help_secrets ;;
    rollback) help_rollback ;;
    doctor)   printf '%b' "${TUI_BOLD}doctor${TUI_RST} — environment check\n\n  ./install.sh doctor [--json]\n\n  Exits 4 if a required tool is missing.\n" ;;
    backups)  printf '%b' "${TUI_BOLD}backups${TUI_RST} — list backups\n\n  ./install.sh backups [--json]\n" ;;
    ""|help)  help_main ;;
    *)        die "No help for \"$1\". Try: ./install.sh help" "$EX_USAGE" ;;
  esac
}

#####################################################################################
# CLI

main() {
  # Settle colour before parsing, or an error *about* the arguments prints raw
  # escape codes into a pipe. Re-run after parsing, once --color is known.
  ui_init_color

  # Global options are accepted anywhere on the line, so `install --json` and
  # `--json install` both work. Non-option words collect as the command and its
  # arguments.
  local -a args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)          FI_ASSUME_YES=true ;;
      --dry-run)         FI_DRY_RUN=true ;;
      --json)            FI_JSON=true ;;
      -q|--quiet)        FI_QUIET=true ;;
      --no-color)        FI_COLOR=never ;;
      --color)
        shift
        case "${1:-}" in
          always|never|auto) FI_COLOR="$1" ;;
          *) die "--color takes always, never or auto." "$EX_USAGE" ;;
        esac ;;
      --color=*)
        FI_COLOR="${1#*=}"
        [[ "$FI_COLOR" =~ ^(always|never|auto)$ ]] \
          || die "--color takes always, never or auto." "$EX_USAGE" ;;
      # Flags, not pseudo-commands: `install --help` has to mean "help for
      # install", which it cannot if --help is shoved into the argument list
      # and then trips the "takes no arguments" check.
      -h|--help)         FI_WANT_HELP=true ;;
      -V|--version)      FI_WANT_VERSION=true ;;
      --)                shift; while [[ $# -gt 0 ]]; do args+=("$1"); shift; done; break ;;
      -*)                die "Unknown option \"$1\". See ./install.sh help." "$EX_USAGE" ;;
      *)                 args+=("$1") ;;
    esac
    shift
  done

  ui_init_color

  [[ "${FI_WANT_VERSION:-false}" == true ]] && { printf '%s %s\n' "$FI_NAME" "$FI_VERSION"; return 0; }
  [[ "${FI_WANT_HELP:-false}" == true ]] && { help_for "${args[0]:-}"; return 0; }

  local cmd="${args[0]:-install}"
  case "$cmd" in
    help)     help_for "${args[1]:-}" ;;
    version)  printf '%s %s\n' "$FI_NAME" "$FI_VERSION" ;;
    install)
      # `install --help` and friends land here as __help already, so anything
      # left over is a stray word.
      (( ${#args[@]} > 1 )) && die "\"install\" takes no arguments. See: ./install.sh help install" "$EX_USAGE"
      fi_install ;;
    doctor)   fi_doctor ;;
    backups)  fi_backups_list ;;
    rollback) fi_rollback "${args[1]:-}" ;;
    secrets)
      case "${args[1]:-}" in
        list)  fi_secrets_list ;;
        set)   fi_secret_set "${args[2]:-}" ;;
        get)   fi_secret_get "${args[2]:-}" ;;
        clear) fi_secret_clear "${args[2]:-}" ;;
        "")    help_secrets; exit "$EX_USAGE" ;;
        *)     die "Unknown \"secrets\" subcommand \"${args[1]}\". See: ./install.sh help secrets" "$EX_USAGE" ;;
      esac ;;
    *) die "Unknown command \"$cmd\". See: ./install.sh help" "$EX_USAGE" ;;
  esac
}

main "$@"
