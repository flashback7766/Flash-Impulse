# This script is meant to be sourced.
# It's not for directly running.

# Reuse an existing AUR helper if present; fall back to pacman otherwise.
detect_aur_helper || AUR_HELPER=""
remover=("$AUR_HELPER" -Rns)
[[ -z "$AUR_HELPER" ]] && remover=(sudo pacman -Rns)

# Both names: an install from before the rename still has the old metapackages,
# and an uninstall that leaves half of them behind is worse than one that tries
# to remove a package that is not there.
for i in {flash,illogical}-impulse-{quickshell-git,audio,backlight,basic,bibata-modern-classic-bin,fonts-themes,hyprland,kde,microtex-git,portal,python,screencapture,toolkit,widgets} plasma-browser-integration; do
  v "${remover[@]}" "$i"
done
