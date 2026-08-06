# This is NOT a script for execution, but for loading functions, so NOT need execution permission or shebang.
XDG_BIN_HOME=${XDG_BIN_HOME:-$HOME/.local/bin}
XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}

STY_RED='\e[31m'
STY_GREEN='\e[32m'
STY_YELLOW='\e[33m'
STY_BLUE='\e[34m'
STY_PURPLE='\e[35m'
STY_CYAN='\e[36m'

STY_BOLD='\e[1m'
STY_FAINT='\e[2m'
STY_SLANT='\e[3m'
STY_UNDERLINE='\e[4m'
STY_BLINK='\e[5m'
STY_INVERT='\e[7m'
STY_RST='\e[00m'

# Used by install script
BACKUP_DIR="${BACKUP_DIR:-$HOME/flash-impulse-original-dots-backup}"
DOTS_CORE_CONFDIR="${XDG_CONFIG_HOME}/flash-impulse"
DOTS_CORE_CONFDIR_LEGACY="${XDG_CONFIG_HOME}/illogical-impulse"
INSTALLED_LISTFILE="${DOTS_CORE_CONFDIR}/installed_listfile"
FIRSTRUN_FILE="${DOTS_CORE_CONFDIR}/installed_true"

# The shell's config directory was named after upstream's project. Move an
# existing one across rather than starting empty beside it, or an upgrade
# silently resets every setting the user has ever changed — the shell would
# write defaults into the new path while the old one sat there looking current.
#
# Entry by entry, not a directory rename: the installer already keeps its own
# install.json in the new directory, so on any machine that has run the new
# installer the destination exists and a whole-directory move would refuse —
# which is the silent-reset case, arriving from the other side. Anything already
# present in the destination wins and the legacy copy is left alone, so this
# cannot overwrite a newer config and can be run any number of times.
function migrate_legacy_confdir() {
  [[ -d "${DOTS_CORE_CONFDIR_LEGACY}" ]] || return 0

  local entry name moved=0
  for entry in "${DOTS_CORE_CONFDIR_LEGACY}"/* "${DOTS_CORE_CONFDIR_LEGACY}"/.[!.]*; do
    [[ -e "$entry" ]] || continue          # unmatched glob
    name="$(basename -- "$entry")"
    [[ -e "${DOTS_CORE_CONFDIR}/${name}" ]] && continue
    if (( moved == 0 )); then
      printf "${STY_CYAN}Migrating shell config from %s to %s${STY_RST}\n" \
        "${DOTS_CORE_CONFDIR_LEGACY}" "${DOTS_CORE_CONFDIR}"
      ${DRY_RUN:+echo} mkdir -p "${DOTS_CORE_CONFDIR}"
    fi
    ${DRY_RUN:+echo} mv -- "$entry" "${DOTS_CORE_CONFDIR}/${name}"
    moved=$((moved + 1))
  done

  # Only when nothing is left behind — a leftover means something in the
  # destination shadowed it, and that is worth being able to look at.
  if (( moved > 0 )) && [[ -z "$(ls -A "${DOTS_CORE_CONFDIR_LEGACY}" 2> /dev/null)" ]]; then
    ${DRY_RUN:+echo} rmdir -- "${DOTS_CORE_CONFDIR_LEGACY}"
  fi
}
