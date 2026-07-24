# This script is meant to be sourced.
# It's not for directly running.

# Reuse an existing AUR helper if present; fall back to pacman otherwise.
detect_aur_helper || AUR_HELPER=""
remover=("$AUR_HELPER" -Rns)
[[ -z "$AUR_HELPER" ]] && remover=(sudo pacman -Rns)

for i in illogical-impulse-{quickshell-git,audio,backlight,basic,bibata-modern-classic-bin,fonts-themes,hyprland,kde,microtex-git,portal,python,screencapture,toolkit,widgets} plasma-browser-integration; do
  v "${remover[@]}" "$i"
done
