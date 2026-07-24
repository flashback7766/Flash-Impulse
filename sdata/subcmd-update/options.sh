# Handle args for subcmd: update
# shellcheck shell=bash
showhelp(){
printf "Syntax: %s update [OPTIONS]...

Thin update: pull the latest commit and re-deploy config files. Because file
deployment is idempotent, this is all a normal update needs — no bespoke sync
engine. Package updates are opt-in with --packages.

Options:
  -h, --help        Show this help message
  -p, --packages    Also (re)install/update dependencies (runs install step 1)
  -n, --dry-run     Walk the flow without changing anything
  -f, --force       Non-interactive (don't confirm each command)
      --skip-pull   Don't 'git pull'; just re-deploy what's already checked out
      --skip-backup Don't back up clashing files before deploying
" "$0"
}

# `man getopt` to see more
para=$(getopt -o hpnf -l help,packages,dry-run,force,skip-pull,skip-backup -n "$0" -- "$@")
[ $? != 0 ] && echo "$0: Error when getopt, please recheck parameters." && exit 1

CHECK_PACKAGES=false
UPDATE_SKIP_PULL=false

eval set -- "$para"
while true ; do
  case "$1" in
    -h|--help) showhelp; exit ;;
    -p|--packages) CHECK_PACKAGES=true; shift ;;
    -n|--dry-run) DRY_RUN=true; shift ;;
    -f|--force) ask=false; shift ;;
    --skip-pull) UPDATE_SKIP_PULL=true; shift ;;
    --skip-backup) SKIP_BACKUP=true; shift ;;
    --) shift; break ;;
    *) echo -e "$0: Wrong parameters."; exit 1 ;;
  esac
done
