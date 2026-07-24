# Flash-Impulse engine — library entry point.
#
# Sourcing this file loads the whole install engine as a set of functions, so both
# the ./setup CLI (power users) and ./install.sh (friendly front-end) drive the exact
# same code path. It must be sourced, not executed.
#
# Consumers set these before calling the engine (all optional, default = do it):
#   ask                 true/false — per-command confirmation (default true)
#   DRY_RUN             true/false — print commands instead of running them
#   SKIP_ALLGREETING    skip the greeting step
#   SKIP_ALLDEPS        skip dependency installation
#   SKIP_ALLSETUPS      skip permissions/services setup
#   SKIP_ALLFILES       skip config file deployment
#   SKIP_{FISH,FONTCONFIG,MISCCONF,QUICKSHELL,HYPRLAND,HYPRLAND_ENTRY,PLASMAINTG,BACKUP,SYSUPDATE}
#   FONTSET_DIR_NAME    named fontset under dots-extra/fontsets
# shellcheck shell=bash

_FI_ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${REPO_ROOT:=$(cd "${_FI_ENGINE_DIR}/../.." && pwd)}"
export REPO_ROOT

# `ask` defaults to interactive; a consumer can override before or after sourcing.
: "${ask:=true}"

# Order matters: env vars/colors first, then core functions, then package + distro libs.
# shellcheck source=environment-variables.sh
source "${REPO_ROOT}/sdata/lib/environment-variables.sh"
# shellcheck source=functions.sh
source "${REPO_ROOT}/sdata/lib/functions.sh"
# shellcheck source=package-installers.sh
source "${REPO_ROOT}/sdata/lib/package-installers.sh"
# shellcheck source=dist-determine.sh
source "${REPO_ROOT}/sdata/lib/dist-determine.sh"

#####################################################################################
# Install steps. Each wraps a step script — kept as separate files for readability,
# but exposed here as callable functions so the engine is a proper library.
#####################################################################################

engine_greeting()       { source "${REPO_ROOT}/sdata/subcmd-install/0.greeting.sh"; }
engine_install_deps()   { source "${REPO_ROOT}/sdata/subcmd-install/1.deps-router.sh"; }
engine_setup_services() { source "${REPO_ROOT}/sdata/subcmd-install/2.setups.sh"; }
engine_deploy_files()   { source "${REPO_ROOT}/sdata/subcmd-install/3.files.sh"; }

# Print the distro-detection banner(s) determined by dist-determine.sh.
engine_print_distro() {
  local f
  for f in "${print_os_group_id_functions[@]}"; do "$f"; done
}

# Start a sudo keepalive and make sure it's torn down on exit.
engine_begin_privileged() {
  sudo_init_keepalive
  trap sudo_stop_keepalive EXIT INT TERM
}

#####################################################################################
# Full install orchestration. Honors the SKIP_ALL* flags and DRY_RUN.
#####################################################################################

engine_run_install() {
  engine_print_distro
  pause
  engine_begin_privileged
  [[ "${SKIP_ALLGREETING}" != true ]] && engine_greeting
  [[ "${SKIP_ALLDEPS}"     != true ]] && engine_install_deps
  [[ "${SKIP_ALLSETUPS}"   != true ]] && engine_setup_services
  [[ "${SKIP_ALLFILES}"    != true ]] && engine_deploy_files
  return 0
}
