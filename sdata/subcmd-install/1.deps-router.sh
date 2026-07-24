# This script is meant to be sourced.
# It's not for directly running.
printf "${STY_CYAN}[$0]: 1. Install dependencies\n${STY_RST}"

function outdate_detect(){
  # Shallow clone prevent latest_commit_timestamp() from working.
  x git_auto_unshallow 2>&1>/dev/null

  local source_path="$1"
  local target_path="$2"
  local source_timestamp="$(latest_commit_timestamp $source_path 2>/dev/null)"
  local target_timestamp="$(latest_commit_timestamp $target_path 2>/dev/null)"
  local outdate_detect_mode="$(cat ${target_path}/outdate-detect-mode)"

  # outdate-detect-mode possible modes:
  # - WIP: Work in progress (should be taken as outdated)
  # - FORCE_OUTDATED: forcely taken as outdated
  # - FORCE_UPDATED: forcely taken as updated
  # - AUTO: Let the script decide automatically
  #
  # outdate status possible values:
  # - WIP,FORCE_OUTDATED,FORCE_UPDATED: Inherited directly from outdate-detect-mode
  # - EMPTY_SOURCE: source path has empty timestamp, maybe not tracked by git (should be taken as outdated)
  # - EMPTY_TARGET: target path has empty timestamp, maybe not tracked by git (should be taken as outdated)
  # - OUTDATED: target path is older than source path.
  # - UPDATED: target path is not older than source path.

  # Does target path have an outdate-detect-mode file which content is special?
  if [[ "${outdate_detect_mode}" =~ ^(WIP|FORCE_OUTDATED|FORCE_UPDATED)$ ]]; then
    echo "${outdate_detect_mode}"
  # Does source path has an empty timestamp?
  elif [ -z "$source_timestamp" ]; then
    echo "EMPTY_SOURCE"
  # Does target path has an empty timestamp?
  elif [ -z "$target_timestamp" ]; then
    echo "EMPTY_TARGET"
  # If target path is older than source path, it's outdated.
  elif [[ "$target_timestamp" -lt "$source_timestamp" ]]; then
    echo "OUTDATED"
  else
    echo "UPDATED"
  fi
}
#####################################################################################

if [[ "$INSTALL_VIA_NIX" == "true" ]]; then

  TARGET_ID=nix
  printf "${STY_YELLOW}"
  printf "===WARNING===\n"
  printf "./sdata/dist-${TARGET_ID}/install-deps.sh will be used.\n"
  printf "The process is still WIP.\n"
  printf "Proceed only at your own risk.\n"
  printf "\n"
  printf "${STY_RST}"
  pause
  source ./sdata/dist-${TARGET_ID}/install-deps.sh

elif [[ "$OS_GROUP_ID" =~ ^(arch|gentoo|fedora)$ ]]; then

  TARGET_ID=$OS_GROUP_ID
  # Non-Arch dep scripts are derived from dist-arch and only best-effort maintained.
  # If dist-arch has newer commits, warn that the derived script may lag behind.
  if ! [[ "${TARGET_ID}" = "arch" ]]; then
    tmp_update_status="$(outdate_detect sdata/dist-arch sdata/dist-${TARGET_ID})"
    if [[ "${tmp_update_status}" =~ ^(OUTDATED|EMPTY_TARGET|EMPTY_SOURCE|FORCE_OUTDATED|WIP)$ ]]; then
      printf "${STY_YELLOW}${STY_BOLD}=== NOTICE ===${STY_RST}\n"
      printf "${STY_YELLOW}"
      printf "Status code: ${tmp_update_status}\n"
      printf "./sdata/dist-${TARGET_ID}/ (best-effort, derived from dist-arch) may be behind\n"
      printf "./sdata/dist-arch/ and could install an incomplete set of dependencies.\n"
      printf "Arch/CachyOS is the primary tested target; other distros are best-effort.\n"
      printf "${STY_RST}\n"
      if ! [[ "$IGNORE_OUTDATE_CHECK" = "true" ]]; then
        if [ "$ask" = "false" ]; then
          printf "${STY_YELLOW}Proceeding anyway (non-interactive).${STY_RST}\n"
        else
          printf "${STY_YELLOW}Proceed?${STY_RST}\n"
          read -p "[Y/n]: " p
          case "$p" in
            [nN])echo "Aborting...";exit 1;;
            *)true;;
          esac
        fi
      fi
    fi
  fi
  printf "./sdata/dist-${TARGET_ID}/install-deps.sh will be used.\n"
  source ./sdata/dist-${TARGET_ID}/install-deps.sh
fi
