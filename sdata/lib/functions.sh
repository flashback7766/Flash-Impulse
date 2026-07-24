# Flash-Impulse engine — core functions.
# Sourced by ./setup and ./install.sh; not executed directly (no shebang needed).
# shellcheck shell=bash

# Global dry-run switch. When true, v() and x() print commands instead of running
# them, so the whole install flow can be walked without touching the system.
: "${DRY_RUN:=false}"

#####################################################################################
# Command execution primitives
#####################################################################################

# Run a command, ignoring failure.
function try { "$@" || true; }

# x: execute a command with a retry-on-failure loop. Use INSIDE functions that are
# themselves wrapped by v(). Honors DRY_RUN.
function x(){
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${STY_FAINT}[dry-run] $*${STY_RST}"
    return 0
  fi
  if "$@";then local cmdstatus=0;else local cmdstatus=1;fi # 0=normal; 1=failed; 2=failed but ignored
  while [ $cmdstatus == 1 ] ;do
    echo -e "${STY_RED}[$0]: Command \"${STY_GREEN}$*${STY_RED}\" has failed."
    echo -e "You may need to resolve the problem manually BEFORE repeating this command."
    echo -e "[Tip] If a certain package is failing to install, try installing it separately in another terminal.${STY_RST}"
    echo "  r = Repeat this command (DEFAULT)"
    echo "  e = Exit now"
    echo "  i = Ignore this error and continue (your setup might not work correctly)"
    local p; read -p " [R/e/i]: " p
    case $p in
      [iI]) echo -e "${STY_BLUE}Alright, ignore and continue...${STY_RST}";cmdstatus=2;;
      [eE]) echo -e "${STY_BLUE}Alright, will exit.${STY_RST}";break;;
      *) echo -e "${STY_BLUE}OK, repeating...${STY_RST}"
         if "$@";then cmdstatus=0;else cmdstatus=1;fi
         ;;
    esac
  done
  case $cmdstatus in
    0) echo -e "${STY_BLUE}[$0]: Command \"${STY_GREEN}$*${STY_BLUE}\" finished.${STY_RST}";;
    1) echo -e "${STY_RED}[$0]: Command \"${STY_GREEN}$*${STY_RED}\" has failed. Exiting...${STY_RST}";exit 1;;
    2) echo -e "${STY_RED}[$0]: Command \"${STY_GREEN}$*${STY_RED}\" has failed but ignored by user.${STY_RST}";;
  esac
}

# v: preview a command, ask before running it (unless $ask is false), then run via x().
# Honors DRY_RUN. When passed a defined function name, that function should use x()
# internally so per-command retry still works.
function v(){
  echo -e "####################################################"
  echo -e "${STY_BLUE}[$0]: Next command:${STY_RST}"
  echo -e "${STY_GREEN}$*${STY_RST}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${STY_FAINT}[dry-run] would run the above.${STY_RST}"
    return 0
  fi
  local execute=true
  if $ask;then
    while true;do
      echo -e "${STY_BLUE}Execute? ${STY_RST}"
      echo "  y = Yes"
      echo "  e = Exit now"
      echo "  s = Skip this command (NOT recommended - your setup might not work correctly)"
      echo "  yesforall = Yes and don't ask again; NOT recommended unless you really sure"
      local p; read -p "====> " p
      case $p in
        [yY]) echo -e "${STY_BLUE}OK, executing...${STY_RST}" ;break ;;
        [eE]) echo -e "${STY_BLUE}Exiting...${STY_RST}" ;exit ;break ;;
        [sS]) echo -e "${STY_BLUE}Alright, skipping this one...${STY_RST}" ;execute=false ;break ;;
        "yesforall") echo -e "${STY_BLUE}Alright, won't ask again. Executing...${STY_RST}"; ask=false ;break ;;
        *) echo -e "${STY_RED}Please enter [y/e/s/yesforall].${STY_RST}";;
      esac
    done
  fi
  if $execute;then x "$@";else
    echo -e "${STY_YELLOW}[$0]: Skipped \"$*\"${STY_RST}"
  fi
}

# Print the definition of a function (used to show the user what a step will do).
function showfun(){
  echo -e "${STY_BLUE}[$0]: The definition of function \"$1\" is as follows:${STY_RST}"
  printf "${STY_GREEN}"
  type -a "$1" 2>/dev/null || return 1
  printf "${STY_RST}"
}

# Pause for the user to read, unless running non-interactively.
function pause(){
  if [ ! "$ask" == "false" ] && [[ "$DRY_RUN" != true ]];then
    printf "${STY_FAINT}${STY_SLANT}"
    local p; read -p "(Ctrl-C to abort, Enter to proceed)" p
    printf "${STY_RST}"
  fi
}

function prevent_sudo_or_root(){
  case $(whoami) in
    root) echo -e "${STY_RED}[$0]: This script is NOT to be executed with sudo or as root. Aborting...${STY_RST}";exit 1;;
  esac
}

#####################################################################################
# Logging
#####################################################################################

function log_info()    { echo -e "${STY_BLUE}[INFO]${STY_RST} $1"; }
function log_success() { echo -e "${STY_GREEN}[SUCCESS]${STY_RST} $1"; }
function log_warning() { echo -e "${STY_YELLOW}[WARNING]${STY_RST} $1"; }
function log_error()   { echo -e "${STY_RED}[ERROR]${STY_RST} $1" >&2; }
function log_header()  { echo -e "\n${STY_PURPLE}=== $1 ===${STY_RST}"; }
function log_die()     { log_error "$1"; exit 1; }

#####################################################################################
# sudo session keepalive
#####################################################################################

declare -g SUDO_KEEPALIVE_PID=""

function sudo_init_keepalive(){
  [[ "$DRY_RUN" == true ]] && return 0
  command -v sudo >/dev/null 2>&1 || return 0
  if [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
    return 0
  fi
  echo -e "${STY_CYAN}[$0]: Requesting sudo privileges for installation...${STY_RST}"
  if ! sudo true; then
    echo -e "${STY_RED}[$0]: Failed to obtain sudo privileges. Aborting...${STY_RST}"
    exit 1
  fi
  # Refresh the sudo timestamp every 60s so long installs don't re-prompt.
  (
    while true; do
      sleep 60
      sudo true 2>/dev/null || exit 0
    done
  ) &
  SUDO_KEEPALIVE_PID=$!
  echo -e "${STY_GREEN}[$0]: Sudo session initialized (PID: $SUDO_KEEPALIVE_PID)${STY_RST}"
}

function sudo_stop_keepalive(){
  if [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=""
  fi
}

#####################################################################################
# git helpers (used by the update flow and outdate detection)
#####################################################################################

function git_auto_unshallow(){
  if [[ -f "$(git rev-parse --git-dir)/shallow" ]]; then
    echo "Shallow clone detected. Unshallowing..."
    git fetch --unshallow
  fi
}

function latest_commit_timestamp(){
  local target_path="$1"
  local result
  result=$(git log -1 --format="%ct" -- "$target_path" 2>/dev/null)
  if [[ -z "$result" ]]; then
    echo "[latest_commit_timestamp] The timestamp of \"$target_path\" is empty. Aborting..." >&2
    return 1
  fi
  echo "$result"
}

function auto_update_git_submodule(){
  if git submodule status --recursive | grep -E '^[+-U]';then
    # `git pull --recurse-submodules` can't substitute this: it won't init a submodule when needed.
    x git submodule update --init --recursive
  fi
}

#####################################################################################
# Misc helpers
#####################################################################################

function remove_bashcomments_emptylines(){
  mkdir -p "$(dirname "$2")"
  sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$1" > "$2"
}

function dedup_and_sort_listfile(){
  if ! test -f "$1"; then
    echo "File not found: $1" >&2; return 2
  fi
  local temp; temp="$(mktemp)"
  sort -u -- "$1" > "$temp"
  mv -f -- "$temp" "$2"
}

# Back up only the target dirs/files that clash with what we're about to install,
# skipping anything in the ignored_list. Uses rsync include/exclude rules.
function backup_clashing_targets(){
  local source_dir="$1"
  local target_dir="$2"
  local backup_dir="$3"
  local -a ignored_list=("${@:4}")

  local clash_list=()
  local source_list target_list
  mapfile -t source_list < <(ls -A "$source_dir")
  mapfile -t target_list < <(ls -A "$target_dir")
  local -A target_map
  for i in "${target_list[@]}"; do
    target_map["$i"]=1
  done
  for i in "${source_list[@]}"; do
    if [[ -n "${target_map[$i]}" ]]; then
      clash_list+=("$i")
    fi
  done
  local -A delk
  for del in "${ignored_list[@]}" ; do delk[$del]=1 ; done
  for k in "${!clash_list[@]}" ; do
    [ "${delk[${clash_list[$k]}]-}" ] && unset 'clash_list[k]'
  done
  clash_list=("${clash_list[@]}")

  local args_includes=()
  for i in "${clash_list[@]}"; do
    if [[ -d "$target_dir/$i" ]]; then
      args_includes+=(--include="/$i/")
      args_includes+=(--include="/$i/**")
    else
      args_includes+=(--include="/$i")
    fi
  done
  args_includes+=(--exclude='*')

  x mkdir -p "$backup_dir"
  x rsync -av --progress "${args_includes[@]}" "$target_dir/" "$backup_dir/"
}

#####################################################################################
# Package helpers (generic; distro dep scripts live in sdata/dist-*/)
#####################################################################################

# Install packages providing the given commands, using the native package manager.
function install_cmds(){
  local pkgs=()
  local cmd
  case $OS_GROUP_ID in
    "arch")
      for cmd in "$@";do
        case $cmd in
          ip) pkgs+=(iproute2);;
          *)  pkgs+=("$cmd") ;;
        esac
      done
      v sudo pacman -Syu
      v sudo pacman -S --noconfirm --needed "${pkgs[@]}"
      ;;
    "debian")
      for cmd in "$@";do
        case $cmd in
          ip) pkgs+=(iproute2);;
          *)  pkgs+=("$cmd") ;;
        esac
      done
      v sudo apt update -y
      v sudo apt install -y "${pkgs[@]}"
      ;;
    "fedora")
      for cmd in "$@";do
        case $cmd in
          ip) pkgs+=(iproute);;
          *)  pkgs+=("$cmd") ;;
        esac
      done
      v sudo dnf install -y "${pkgs[@]}"
      ;;
    "suse")
      for cmd in "$@";do
        case $cmd in
          ip) pkgs+=(iproute2);;
          *)  pkgs+=("$cmd") ;;
        esac
      done
      v sudo zypper refresh
      v sudo zypper -n install "${pkgs[@]}"
      ;;
    *)
      printf "WARNING\n"
      printf "No method found to install package providing the commands:\n"
      printf "  %s\n" "$*"
      printf "Please install by yourself.\n"
      ;;
  esac
}

# Ensure the given commands exist, installing whatever is missing.
function ensure_cmds(){
  local not_found_cmds=()
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1;then
      not_found_cmds+=("$cmd")
    fi
  done
  if [[ ${#not_found_cmds[@]} -gt 0 ]]; then
    echo -e "${STY_YELLOW}[$0]: Not found: ${not_found_cmds[*]}.${STY_RST}"
    install_cmds "${not_found_cmds[@]}"
  fi
}
