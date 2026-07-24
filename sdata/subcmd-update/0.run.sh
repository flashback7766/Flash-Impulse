# Thin update: pull latest, then re-deploy config files (optionally deps).
# Sourced by ./setup; the engine (engine_* functions) is already loaded.
# shellcheck shell=bash

printf "${STY_CYAN}[$0]: Flash-Impulse update${STY_RST}\n"
printf "${STY_FAINT}Pulls the latest commit and re-deploys config files. "
printf "File deployment is idempotent, so this is all a normal update needs.${STY_RST}\n"
pause

# 1. Pull latest (fast-forward only — never rewrite local history silently).
if [[ "${UPDATE_SKIP_PULL}" != true ]]; then
  if [[ -n "$(git status --porcelain -- . ':(exclude)dots/.config/hypr/custom' 2>/dev/null)" ]]; then
    printf "${STY_YELLOW}[$0]: You have local changes. 'git pull --ff-only' may fail; "
    printf "stash or commit them first if so.${STY_RST}\n"
  fi
  v git pull --ff-only
fi

# 2. Optionally refresh dependencies.
if [[ "${CHECK_PACKAGES}" == true ]]; then
  engine_print_distro
  engine_begin_privileged
  engine_install_deps
fi

# 3. Re-deploy config files (handles its own backup + firstrun + hyprctl reload).
engine_deploy_files

printf "${STY_CYAN}[$0]: Update finished.${STY_RST}\n"
