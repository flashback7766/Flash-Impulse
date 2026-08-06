# This script is meant to be sourced.
# It's not for directly running.

install-yay(){
  x sudo pacman -S --needed --noconfirm base-devel
  x git clone https://aur.archlinux.org/yay-bin.git /tmp/buildyay
  x cd /tmp/buildyay
  x makepkg -o
  x makepkg -se
  x makepkg -i --noconfirm
  x cd ${REPO_ROOT}
  rm -rf /tmp/buildyay
}

remove_deprecated_dependencies(){
  printf "${STY_CYAN}[$0]: Removing deprecated dependencies:${STY_RST}\n"
  local list=()
  list+=(illogical-impulse-{microtex,pymyc-aur,oneui4-icons-git})
  list+=(hyprland-qtutils)
  list+=({quickshell,hyprutils,hyprpicker,hyprlang,hypridle,hyprland-qt-support,hyprland-qtutils,hyprlock,xdg-desktop-portal-hyprland,hyprcursor,hyprwayland-scanner,hyprland}-git)
  list+=(matugen-bin)
  for i in ${list[@]};do try sudo pacman --noconfirm -Rdd $i;done
}
# NOTE: `implicitize_old_dependencies()` was for the old days when we just switch from dependencies.conf to local PKGBUILDs.
# However, let's just keep it as references for other distros writing their `sdata/dist-<OS_GROUP_ID>/install-deps.sh`, if they need it.
implicitize_old_dependencies(){
# Convert old dependencies to non explicit dependencies so that they can be orphaned if not in meta packages
  remove_bashcomments_emptylines ./sdata/dist-arch/previous_dependencies.conf ./cache/old_deps_stripped.conf
  readarray -t old_deps_list < ./cache/old_deps_stripped.conf
  pacman -Qeq > ./cache/pacman_explicit_packages
  readarray -t explicitly_installed < ./cache/pacman_explicit_packages

  echo "Attempting to set previously explicitly installed deps as implicit..."
  for i in "${explicitly_installed[@]}"; do for j in "${old_deps_list[@]}"; do
    [ "$i" = "$j" ] && "$AUR_HELPER" -D --asdeps "$i"
  done; done

  return 0
}

#####################################################################################
if ! command -v pacman >/dev/null 2>&1; then
  printf "${STY_RED}[$0]: pacman not found, it seems that the system is not ArchLinux or Arch-based distros. Aborting...${STY_RST}\n"
  exit 1
fi

# Keep makepkg from resetting sudo credentials
if [[ -z "${PACMAN_AUTH:-}" ]]; then
  export PACMAN_AUTH="sudo"
fi

showfun remove_deprecated_dependencies
v remove_deprecated_dependencies

# Issue #363
case $SKIP_SYSUPDATE in
  true) true;;
  *) v sudo pacman -Syu;;
esac

# Pick an AUR helper: reuse an existing yay or paru, otherwise install yay.
# (Only used to resolve deps; the metapackages themselves are built with makepkg.)
if ! detect_aur_helper; then
  echo -e "${STY_YELLOW}[$0]: No AUR helper (yay/paru) found, installing yay.${STY_RST}"
  showfun install-yay
  v install-yay
  detect_aur_helper
fi
echo -e "${STY_CYAN}[$0]: Using AUR helper: ${AUR_HELPER}${STY_RST}"

showfun implicitize_old_dependencies
v implicitize_old_dependencies

# https://github.com/end-4/dots-hyprland/issues/581
# yay -Bi is kinda hit or miss, instead cd into the relevant directory and manually source and install deps
install-local-pkgbuild() {
  local location=$1
  local installflags=$2

  x pushd $location

  source ./PKGBUILD
  x "$AUR_HELPER" -S --sudoloop $installflags --asdeps "${depends[@]}"
  # man makepkg:
  # -A, --ignorearch: Ignore a missing or incomplete arch field in the build script.
  # -s, --syncdeps: Install missing dependencies using pacman. When build-time or run-time dependencies are not found, pacman will try to resolve them.
  # -f, --force: build a package even if it already exists in the PKGDEST
  #
  # Build first, install second, rather than `makepkg -i` doing both.
  #
  # The metapackages were renamed illogical-impulse-* -> flash-impulse-*, and
  # each new one carries `replaces`. That alone does not help here: pacman only
  # acts on `replaces` during a sync from a repository. Installed from a local
  # file it is an ordinary name conflict, which `--noconfirm` answers "no" to,
  # failing the whole transaction.
  #
  # So the predecessor is removed explicitly — but only after the replacement
  # has been built. Three of these packages own real files, `quickshell` among
  # them, and that is the binary the desktop is running on: remove it before the
  # build and a build that fails leaves the machine with no shell at all.
  # -C, --cleanbuild: wipe $srcdir before building. Needed because these
  # directories were renamed: a working copy left over from a build under the
  # old name records the old absolute path in its git alternates, and makepkg
  # then fails with "does not appear to be a git repository" pointing at a
  # directory that no longer exists. The download cache lives outside $srcdir
  # and is kept, so the cost is a fresh checkout, not a fresh clone.
  x makepkg -ACfs --noconfirm
  remove_renamed_predecessor "$pkgname"
  # --packagelist rather than a *.pkg.tar.zst glob: a directory that has been
  # built in before can hold artifacts from an older pkgver, and installing
  # those alongside the new one is how you end up downgrading something by
  # accident. This asks makepkg which files this build actually produced.
  local built=()
  readarray -t built < <(makepkg --packagelist)
  x sudo pacman -U --noconfirm --needed "${built[@]}"
  x popd
}

# -Rdd: skip the dependency check. Removing a metapackage would otherwise make
# pacman consider cascading into the very packages the replacement is about to
# claim, and anything left orphaned for the second in between is adopted again
# by the install that follows immediately.
remove_renamed_predecessor(){
  local new=$1
  local old="${new/#flash-impulse-/illogical-impulse-}"
  [[ "$old" != "$new" ]] || return 0
  pacman -Qq "$old" &> /dev/null || return 0
  printf "${STY_CYAN}[$0]: Replacing $old with $new${STY_RST}\n"
  try sudo pacman -Rdd --noconfirm "$old"
}

# Install core dependencies from the meta-packages
metapkgs=(./sdata/dist-arch/flash-impulse-{audio,backlight,basic,fonts-themes,kde,portal,python,screencapture,toolkit,widgets})
metapkgs+=(./sdata/dist-arch/flash-impulse-hyprland)
metapkgs+=(./sdata/dist-arch/flash-impulse-microtex-git)
metapkgs+=(./sdata/dist-arch/flash-impulse-quickshell-git)
metapkgs+=(./sdata/dist-arch/flash-impulse-bibata-modern-classic-bin)

for i in "${metapkgs[@]}"; do
  metainstallflags="--needed"
  $ask && showfun install-local-pkgbuild || metainstallflags="$metainstallflags --noconfirm"
  v install-local-pkgbuild "$i" "$metainstallflags"
done

## Optional dependencies
if pacman -Qs ^plasma-browser-integration$ ;then SKIP_PLASMAINTG=true;fi
case $SKIP_PLASMAINTG in
  true) true;;
  *)
    if $ask;then
      echo -e "${STY_YELLOW}[$0]: NOTE: The size of \"plasma-browser-integration\" is ~600 KiB, but if you don't yet have KDE on your system it'll pull an extra ~600MiB of packages.${STY_RST}"
      echo -e "${STY_YELLOW}It is needed if you want playtime of media in Firefox to be shown on the music controls widget.${STY_RST}"
      echo -e "${STY_YELLOW}Install it? [y/N]${STY_RST}"
      read -p "====> " p
    else
      p=y
    fi
    case $p in
      y) x sudo pacman -S --needed --noconfirm plasma-browser-integration ;;
      *) echo "Ok, won't install"
    esac
    ;;
esac
