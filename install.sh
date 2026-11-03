#!/bin/bash

####################################################################################################
# PREFLIGHT ENVIRONMENT CHECKS
####################################################################################################

msg_ok()  { echo -e "\n\033[0;32m$*\033[0m"; }
msg_err() { echo -e "\n\033[0;31m$*\033[0m" >&2; }

# Stop immediately if UID is root
if [ "$EUID" -eq 0 ]; then
  msg_err "Don't run this script as root"
  exit 1
fi

# Kernel parameter setting
if [ -f /etc/kernel/cmdline ]; then
  CMDLINE_MODE=uki
  CMDLINE=/etc/kernel/cmdline
else
  CMDLINE_MODE=grub
  CMDLINE=/etc/default/grub
fi
cmdline_set_param() {
  local key="$1" val="$2"
  if [ "$CMDLINE_MODE" = uki ]; then
    if grep -qP "(^|\s)${key}=\S*" "$CMDLINE"; then
      sudo sed -i -E "s/(^|\s)${key}=[^ ]*/\1${key}=${val}/" "$CMDLINE"
    else
      sudo sed -i -E "s/\s*$/ ${key}=${val}/" "$CMDLINE"
    fi
  else
    if grep -qP "GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*(^|\s)${key}=\S*" "$CMDLINE"; then
      sudo sed -i -E "s/(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\b${key}=[^ \"]*/\1${key}=${val}/" "$CMDLINE"
    else
      sudo sed -i -E "s/(GRUB_CMDLINE_LINUX_DEFAULT=\")([^\"]*)\"/\1\2 ${key}=${val}\"/" "$CMDLINE"
    fi
  fi
}

# Bare kernel flag
cmdline_set_flag() {
  local flag="$1"
  if [ "$CMDLINE_MODE" = uki ]; then
    grep -qP "(^|\s)${flag}(\s|$)" "$CMDLINE" \
      || sudo sed -i -E "s/\s*$/ ${flag}/" "$CMDLINE"
  else
    grep -qP "GRUB_CMDLINE_LINUX_DEFAULT=\"([^\"]*\s)?${flag}(\s|\")" "$CMDLINE" \
      || sudo sed -i -E "s/(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"/\1 ${flag}\"/" "$CMDLINE"
  fi
}

# Append modules to mkinitcpio MODULES if absent
mkinitcpio_append_modules() {
  local m
  for m in "$@"; do
    grep -qE "^MODULES=\(([^)]*[[:space:]])?${m}([[:space:]][^)]*)?\)" /etc/mkinitcpio.conf \
      || sudo sed -i -E "s/^MODULES=\(([^)]*)\)/MODULES=(\1 ${m})/" /etc/mkinitcpio.conf
  done
}

# Echo 1 if the NVIDIA GPU needs the legacy 580xx driver, else 0
nvidia_is_legacy() {
  local gpu
  gpu=$(lspci -d 10de: | grep -iE 'vga|3d|display')
  if [ "$BLOAT" -eq 1 ] || [ -z "$gpu" ]; then   # --bloat / no GPU present: latest open driver
    echo 0
  elif grep -qPi 'RTX\s*[2-9][0-9]{3}|GTX\s*16[0-9]{2}|TITAN RTX|Tesla T4|Quadro T[0-9]{3,4}' <<< "$gpu"; then
    echo 0   # Turing+
  elif grep -qPi 'GTX\s*(9[0-9]{2}|10[0-9]{2})|GTX\s*750\s*Ti|Quadro [MP][0-9]{3,4}|TITAN\s*(X|Xp|V)\b|Tesla [MPV][0-9]+|GP100' <<< "$gpu"; then
    echo 1   # Maxwell/Pascal/Volta
  else
    echo "Warning: unrecognized GPU '$gpu' — assuming Turing+ (open driver)" >&2
    echo 0
  fi
}

# Shallow-clone <url> into a temp dir, run <cmd...> in it, always clean up (stdin passes through)
run_in_fresh_clone() {
  local url="$1"; shift
  (
    dir=$(mktemp -d) || exit 1
    trap 'rm -rf "$dir"' EXIT
    git clone --depth 1 "$url" "$dir" && cd "$dir" && "$@"
  )
}

# Bootstrap yay-bin; build dir removed only on success
ensure_yay() {
  command -v yay &> /dev/null && return 0
  local dir
  sudo pacman -S --needed --noconfirm git base-devel || return 1
  dir=$(mktemp -d) || return 1
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$dir" \
    && (cd "$dir" && makepkg -si --needed --noconfirm) \
    && rm -rf "$dir" \
    && return 0
  echo "yay bootstrap failed; build dir kept at $dir" >&2
  return 1
}

# render_tmpl <src> <VAR> <value> <dst>: replace @VAR@ in src, write dst
render_tmpl() {
  sed "s|@$2@|$3|g" "$1" > "$4"
}

# write_if_missing <path>: write stdin to path only if it doesn't exist
write_if_missing() {
  [ -f "$1" ] || cat > "$1"
}

# grub_set_default <KEY> <value>: set (or uncomment, or append) KEY=value in /etc/default/grub
grub_set_default() {
  local key="$1" val="$2" f=/etc/default/grub
  if grep -qE "^#?${key}=" "$f"; then
    sudo sed -i -E "s|^#?${key}=.*|${key}=${val}|" "$f"
  else
    echo "${key}=${val}" | sudo tee -a "$f" > /dev/null
  fi
}

# Dotfiles update/installer function
DOTS_DIR="$HOME/.local/share/hypr-dots"
deploy_dotfiles() {
  mkdir -p "$HOME/.local/share" "$HOME/.config"
  if [ -d "$DOTS_DIR/.git" ]; then
    git -C "$DOTS_DIR" pull --ff-only --recurse-submodules || return 1
    git -C "$DOTS_DIR" submodule update --init --recursive || return 1
  else
    git clone --recurse-submodules https://github.com/agustux/hypr-dots.git "$DOTS_DIR" || return 1
  fi
  git -C "$DOTS_DIR" submodule update --init --remote || return 1

  # Prune symlinks to files removed upstream
  find "$HOME/.config" -xtype l -lname "$DOTS_DIR/*" -delete
  (cd "$DOTS_DIR/.config" && find . -type f -not -path '*/.git' -not -path '*/.git/*' -print0) \
    | while IFS= read -r -d '' f; do
    mkdir -p "$HOME/.config/$(dirname "$f")"
    ln -sf "$DOTS_DIR/.config/$f" "$HOME/.config/$f"
  done

  # Apply username fix to templates
  render_tmpl "$HOME/.config/gtk-3.0/bookmarks.tmpl" USER "$USER" "$HOME/.config/gtk-3.0/bookmarks"
  render_tmpl "$HOME/.config/hypr/hyprqt6engine.conf.tmpl" HOME "$HOME" "$HOME/.config/hypr/hyprqt6engine.conf"

  # Render Waybar configs, one per WM
  if [ -f "$HOME/.config/waybar/config.tmpl" ]; then
    for wm in hyprland sway; do
      render_tmpl "$HOME/.config/waybar/config.tmpl" WORKSPACES_MODULE "$wm/workspaces" "$HOME/.config/waybar/config.$wm"
    done
  fi

  # Sway: shadow /usr/bin/sway so the stock ly entry picks up env + iGPU detection
  if [ "$SWAY" -eq 1 ]; then
    sudo install -Dm755 "$HOME/.config/sway/sway-session" /usr/local/bin/sway
  fi
}

# Intel undervolt support detection (i3/i5/i7/i9, 4th-10th gen)
CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo)
NUM=$(echo "$CPU_MODEL" | grep -oP 'i[3579]-\K[0-9]{4,5}')
if [[ "$NUM" =~ ^1[0-4] ]]; then GEN="${NUM:0:2}"; else GEN="${NUM:0:1}"; fi
UNDERVOLT_SUPPORTED=0
[[ "$GEN" =~ ^([4-9]|10)$ ]] && UNDERVOLT_SUPPORTED=1

# GPU/CPU vendor detection (DRM vendor IDs: 8086 = Intel, 1002 = AMD)
IS_INTEL=0
IS_AMD=0
for d in /sys/class/drm/card[0-9]/device; do
  [ -r "$d/vendor" ] || continue
  case $(<"$d/vendor") in
    0x8086) IS_INTEL=1 ;;
    0x1002) IS_AMD=1 ;;
  esac
done
IS_INTEL_CPU=0
IS_AMD_CPU=0
grep -qm1 GenuineIntel /proc/cpuinfo && { IS_INTEL=1; IS_INTEL_CPU=1; }
grep -qm1 AuthenticAMD /proc/cpuinfo && IS_AMD_CPU=1

# Chrultrabook detection (Chrome EC survives full UEFI firmware flash)
IS_CHROMEBOOK=0
[ -e /dev/cros_ec ] && IS_CHROMEBOOK=1
compgen -G '/sys/bus/acpi/devices/GOOG*' >/dev/null && IS_CHROMEBOOK=1

# T2 Mac detection (106b:1801 = Apple T2 Bridge Controller)
IS_T2=0
grep -qis 'v0000106Bd00001801' /sys/bus/pci/devices/*/modalias && IS_T2=1

# Broadcom wifi detection (vendor ID 14e4 = Broadcom); skipped on T2 (handled manually)
NEEDS_BROADCOM_WL=0
[ "$IS_T2" -eq 0 ] && grep -qis 'v000014E4d.*bc02sc80' /sys/bus/pci/devices/*/modalias && NEEDS_BROADCOM_WL=1

# Disable undervolting on T2 Macs
[ "$IS_T2" -eq 1 ] && UNDERVOLT_SUPPORTED=0

# Parse flags (for non-interactive runs)
BLOAT=0
FOOT=0
GNOME=0
NOSWAP=0
FORCE_NVIDIA=0
SWAY=0
HYPR=1
UPDATE=0
for arg in "$@"; do
  case "$arg" in
    --bloat) BLOAT=1 ;;
    --foot) FOOT=1 ;;
    --gnome) GNOME=1 ;;
    --noswap) NOSWAP=1 ;;
    --nvidia) FORCE_NVIDIA=1 ;;
    --sway) SWAY=1; HYPR=0 ;;
    --update) UPDATE=1 ;;
    *) msg_err "Unknown flag: $arg\nValid: --bloat --foot --gnome --noswap --nvidia --sway --update"; exit 1 ;;
  esac
done

# Just update dots if --update used
if [ "$UPDATE" -eq 1 ]; then
  deploy_dotfiles || exit 1
  msg_ok "Dotfiles updated, reboot to apply changes"
  exit 0
fi

# Install GNOME, Sway and Hyprland if --bloat used
[ "$BLOAT" -eq 1 ] && { GNOME=1; SWAY=1; HYPR=1; }

# NVIDIA presence detection (vendor ID 10de = NVIDIA) with --nvidia override
NVIDIA=0
if [ "$FORCE_NVIDIA" -eq 1 ] || [ "$BLOAT" -eq 1 ]; then
  NVIDIA=1
else
  grep -qis 'v000010DEd.*bc03' /sys/bus/pci/devices/*/modalias && NVIDIA=1
fi

# Kernel header detection (matches every installed kernel via its pkgbase: linux, linux-lts, linux-zen)
declare -A seen; KERNEL_HEADERS=()
for f in /usr/lib/modules/*/pkgbase; do
  [ -r "$f" ] && read -r p <"$f" && [ -z "${seen[$p]}" ] && seen[$p]=1 && KERNEL_HEADERS+=("$p-headers")
done
[ "${#KERNEL_HEADERS[@]}" -eq 0 ] && KERNEL_HEADERS=(linux-headers)

####################################################################################################
# PACKAGE INSTALLS
####################################################################################################

# Installing yay (AUR helper)
ensure_yay || exit 1

# Removing actual bloat
REMOVE_PKGS=(polkit-kde-agent wofi kwallet dolphin uwsm kitty htop power-profiles-daemon)
TO_REMOVE=()
for pkg in "${REMOVE_PKGS[@]}"; do
  pacman -Qq "$pkg" &> /dev/null && TO_REMOVE+=("$pkg")
done
[ "${#TO_REMOVE[@]}" -gt 0 ] && sudo pacman -Rns --noconfirm "${TO_REMOVE[@]}"

# Package sets
PKGS_WM_COMMON=(xdg-desktop-portal-gtk hyprpolkitagent hyprlock grim slurp wl-clipboard dunst brightnessctl jq)

PKGS_SWAY=(sway xdg-desktop-portal-wlr swayidle swaybg sway-contrib wl-mirror)
PKGS_HYPR=(hyprland xdg-desktop-portal-hyprland hypridle hyprpaper hyprshutdown libnotify)
PKGS_GNOME=(gdm gnome-shell gnome-control-center gnome-session gnome-backgrounds xdg-desktop-portal-gnome dconf)
PKGS_NVIM=(neovim ripgrep fd tree-sitter-cli lua-language-server bash-language-server pyright clang markdown-oxide)

PKGS_AUDIO=(pipewire pipewire-alsa pipewire-jack pipewire-pulse gst-plugin-pipewire libpulse wireplumber sof-firmware alsa-firmware)
PKGS_SESSION=(gnome-keyring ly seatd bluez bluez-utils)
PKGS_THEME=(hyprqt6engine qt6ct qt6-wayland adw-gtk-theme ttf-dejavu ttf-jetbrains-mono-nerd
  ttf-nerd-fonts-symbols-mono ttf-nerd-fonts-symbols noto-fonts-emoji waybar rofi rofi-bluetooth-git)
PKGS_GUI=(networkmanager-dmenu tlp pavucontrol nm-connection-editor blueman baobab gnome-disk-utility
  nautilus loupe decibels snapshot vlc vlc-plugins-all gnome-calculator gnome-clocks papers brave-origin-bin)
PKGS_CLI=(curl less man-db ufw rsync powertop nvtop zip unzip cpupower fastfetch bash-completion tar-scripts
  exfatprogs libcamera gst-plugin-libcamera pipewire-libcamera libcamera-tools libcamera-ipa xorg-xhost alsa-utils)

PKGS_INTEL=(intel-gpu-tools vulkan-intel lib32-vulkan-intel intel-media-driver libva-intel-driver)
PKGS_AMD=(vulkan-radeon lib32-vulkan-radeon)
PKGS_UCODE_INTEL=(intel-ucode)
PKGS_UCODE_AMD=(amd-ucode)
PKGS_UNDERVOLT=(intel-undervolt)
PKGS_T2=(t2fanrd)
PKGS_BROADCOM=(broadcom-wl-dkms)
PKGS_NVIDIA=(nvidia-utils lib32-nvidia-utils nvidia-open-dkms)
PKGS_NVIDIA_LEGACY=(nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-580xx-dkms)

PKGS_BLOAT=(proton-vpn-gtk-app obs-studio windscribe-v2-bin localsend-bin ventoy-bin yt-dlp
  android-udev android-tools gvfs-mtp libmtp scrcpy gnirehtet-bin opencode
  mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader libdrm lib32-libdrm lib32-glibc
  lib32-gcc-libs lib32-libglvnd lib32-wayland lib32-libx11 lib32-libxcb lib32-libpulse
  lib32-libpipewire lib32-alsa-lib lib32-alsa-plugins)

# Assemble install list
# Assemble install list
PKGS=(
    "${KERNEL_HEADERS[@]}"
    "${PKGS_WM_COMMON[@]}"
    "${PKGS_NVIM[@]}"
    "${PKGS_AUDIO[@]}"
    "${PKGS_SESSION[@]}"
    "${PKGS_THEME[@]}"
    "${PKGS_GUI[@]}"
    "${PKGS_CLI[@]}"
)

[ "$SWAY" -eq 1 ] && PKGS+=("${PKGS_SWAY[@]}")
[ "$HYPR" -eq 1 ] && PKGS+=("${PKGS_HYPR[@]}")
[ "$FOOT" -eq 1 ] && PKGS+=(foot) || PKGS+=(ghostty)
[ "$GNOME" -eq 1 ] && PKGS+=("${PKGS_GNOME[@]}")
[ "$NEEDS_BROADCOM_WL" -eq 1 ] && PKGS+=("${PKGS_BROADCOM[@]}")
[ "$IS_T2" -eq 1 ] && PKGS+=("${PKGS_T2[@]}")

if [ "$IS_INTEL" -eq 1 ] || [ "$BLOAT" -eq 1 ]; then
  PKGS+=("${PKGS_INTEL[@]}")
  [ "$UNDERVOLT_SUPPORTED" -eq 1 ] && PKGS+=("${PKGS_UNDERVOLT[@]}")
fi

if [ "$IS_AMD" -eq 1 ] || [ "$BLOAT" -eq 1 ]; then
  PKGS+=("${PKGS_AMD[@]}")
fi

if [ "$IS_INTEL_CPU" -eq 1 ] || [ "$BLOAT" -eq 1 ]; then PKGS+=("${PKGS_UCODE_INTEL[@]}"); fi
if [ "$IS_AMD_CPU" -eq 1 ] || [ "$BLOAT" -eq 1 ]; then PKGS+=("${PKGS_UCODE_AMD[@]}"); fi

[ "$BLOAT" -eq 1 ] && PKGS+=("${PKGS_BLOAT[@]}")
if [ "$NVIDIA" -eq 1 ]; then
  if [ "$(nvidia_is_legacy)" -eq 1 ]; then
    PKGS+=("${PKGS_NVIDIA_LEGACY[@]}")
  else
    PKGS+=("${PKGS_NVIDIA[@]}")
  fi
fi

yay -S --needed --noconfirm --sudoloop "${PKGS[@]}" || exit 1

####################################################################################################
# SYSTEM CONFIGURATION
####################################################################################################

# Adding Swapfile
if [ "$NOSWAP" -eq 0 ] && [ ! -f /swapfile ]; then
  sudo dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
fi

# UFW rules and fix for localsend
if [ "$BLOAT" -eq 1 ]; then
  sudo ufw allow 53317/tcp
  sudo ufw allow 53317/udp
fi
sudo systemctl enable --now ufw.service
sudo ufw --force enable

# Bluetooth service (same as archinstall)
sudo systemctl enable bluetooth.service

# PipeWire user units (same symlinks as archinstall)
mkdir -p "$HOME/.config/systemd/user/default.target.wants"
ln -sf /usr/lib/systemd/user/pipewire-pulse.service "$HOME/.config/systemd/user/default.target.wants/pipewire-pulse.service"
ln -sf /usr/lib/systemd/user/pipewire-pulse.socket "$HOME/.config/systemd/user/default.target.wants/pipewire-pulse.socket"

# Seat access (seatd, same as archinstall)
sudo systemctl enable seatd.service
sudo usermod -aG seat "$USER"

# Chrultrabook Fixes (if chromebook)
if [ "$IS_CHROMEBOOK" -eq 1 ]; then
  printf '1\nsst\n' | run_in_fresh_clone https://github.com/WeirdTreeThing/chromebook-linux-audio ./setup-audio
  echo n | run_in_fresh_clone https://github.com/WeirdTreeThing/cros-keyboard-map ./install.sh
fi

# NVIDIA configuration for hyprland
if [ "$NVIDIA" -eq 1 ]; then
  sudo systemctl enable nvidia-resume
  sudo systemctl enable nvidia-suspend
  sudo systemctl enable nvidia-hibernate

  cmdline_set_param iommu pt
  cmdline_set_param nvidia.NVreg_PreserveVideoMemoryAllocations 1
  cmdline_set_param nvidia_drm.modeset 1
fi

# T2 Mac
if [ "$IS_T2" -eq 1 ]; then
  cmdline_set_param intel_iommu on
  cmdline_set_param iommu pt
  cmdline_set_param pm_async off

  echo t2bce_vhci | sudo tee /etc/modules-load.d/t2.conf > /dev/null

  # Early-load modules (reverse order: each is prepended)
  for m in t2bce_vhci t2bce_core t2bce_dma; do
    grep -qE "^MODULES=\(.*\b$m\b" /etc/mkinitcpio.conf \
      || sudo sed -i -E "s/^MODULES=\(/MODULES=($m /" /etc/mkinitcpio.conf
  done

  # Audio
  run_in_fresh_clone https://github.com/kekrby/t2-better-audio.git ./install.sh

  # Fan: daemon generates /etc/t2fand.conf on first start
  sudo systemctl enable --now t2fanrd
  sleep 2
  sudo sed -i -E 's/^speed_curve\s*=.*/speed_curve=logarithmic/' /etc/t2fand.conf
  sudo systemctl restart t2fanrd
fi

# GNOME
if [ "$GNOME" -eq 1 ]; then
  sudo systemctl disable ly@tty1.service 2>/dev/null
  sudo systemctl enable gdm.service

  dbus-run-session -- bash -c '
    dconf write /org/gnome/desktop/search-providers/disabled "['"'"'org.gnome.clocks.desktop'"'"']"
    gsettings set org.gnome.desktop.interface show-battery-percentage true
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "nothing"
    gsettings set org.gnome.settings-daemon.plugins.power power-button-action "interactive"
    gsettings set org.gnome.desktop.peripherals.touchpad disable-while-typing false
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
    gsettings set org.gnome.desktop.interface accent-color "blue"
  '
fi
[ "$GNOME" -eq 0 ] && sudo systemctl enable ly@tty1.service

####################################################################################################
# DOTFILES & FINALIZE
####################################################################################################

# More Hyprland stuff
mkdir -p $HOME/Documents
mkdir -p $HOME/Music
mkdir -p $HOME/Pictures
mkdir -p $HOME/Videos
mkdir -p $HOME/Downloads
mkdir -p $HOME/Pictures/Screenshots

# Installing dotfiles
deploy_dotfiles || exit 1

# Untracked per-machine overrides (never overwritten by updates)
LOCAL_LUA="$HOME/.config/hypr/local.lua"
if [ "$FOOT" -eq 1 ]; then
  # foot has no --gtk-single-instance flag
  write_if_missing "$LOCAL_LUA" << 'EOF'
-- Local overrides (untracked). Keys: terminal, terminal_flags
return {
  terminal = "foot",
  terminal_flags = "",
}
EOF
else
  write_if_missing "$LOCAL_LUA" << 'EOF'
-- Local overrides (untracked). Keys: terminal, terminal_flags
return {}
EOF
fi

# Sway per-machine overrides (untracked)
LOCAL_SWAY="$HOME/.config/sway/local.conf"
if [ "$FOOT" -eq 1 ]; then
  write_if_missing "$LOCAL_SWAY" <<< 'set $terminal foot'
else
  write_if_missing "$LOCAL_SWAY" < /dev/null
fi

# Quieting kernel messages on the console
cmdline_set_param loglevel 3

# Quiet boot + Plymouth splash
cmdline_set_flag quiet
cmdline_set_flag splash

# Setting VT color scheme
cmdline_set_param vt.default_red "30,243,166,249,137,245,148,205,88,243,166,249,137,245,148,166"
cmdline_set_param vt.default_grn "30,139,227,226,180,194,226,214,91,139,227,226,180,194,226,173"
cmdline_set_param vt.default_blu "46,168,161,175,250,231,213,244,112,168,161,175,250,231,213,200"

# Installing system configs from dotfiles
sudo install -Dm644 "$HOME/.config/tlp/00-custom.conf" /etc/tlp.d/00-custom.conf
sudo systemctl mask systemd-rfkill.service systemd-rfkill.socket
sudo systemctl enable tlp.service

# Install undervolt config
if [ "$UNDERVOLT_SUPPORTED" -eq 1 ]; then
  sudo install -Dm644 "$HOME/.config/intel-undervolt/intel-undervolt.conf" /etc/intel-undervolt.conf
  sudo systemctl enable intel-undervolt
fi

# Install NVIDIA confs
if [ "$NVIDIA" -eq 1 ]; then
  sudo install -Dm644 "$HOME/.config/nvidia/nvidia-pm.conf" /etc/modprobe.d/nvidia-pm.conf
  sudo install -Dm644 "$HOME/.config/nvidia/80-nvidia-pm.rules" /etc/udev/rules.d/80-nvidia-pm.rules
fi

# Plymouth
PLYMOUTH_THEME=arch-mac-style-catppuccin-mocha
sudo unzip -oq "$HOME/.config/plymouth/$PLYMOUTH_THEME.zip" -d /usr/share/plymouth/themes
sudo plymouth-set-default-theme "$PLYMOUTH_THEME"   # initramfs rebuilt at end of script

# Hook right after udev (or systemd)
sudo sed -i -E '/^HOOKS=/{/\bplymouth\b/!s/\b(udev|systemd)\b/& plymouth/}' /etc/mkinitcpio.conf

# Early KMS modules (all GPU vendors under --bloat)
# Early KMS modules (all GPU vendors under --bloat)
KMS_MODULES=()
if [ "$IS_AMD" -eq 1 ] || [ "$BLOAT" -eq 1 ]; then KMS_MODULES+=(amdgpu); fi
if [ "$IS_INTEL" -eq 1 ] || [ "$BLOAT" -eq 1 ]; then KMS_MODULES+=(i915); fi
if [ "$NVIDIA" -eq 1 ]; then KMS_MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm); fi
mkinitcpio_append_modules "${KMS_MODULES[@]}"

# Ly config installation
sudo install -d /etc/ly
sudo ln -sf "$HOME/.config/ly/config.ini" /etc/ly/config.ini
sudo install -Dm644 "$HOME/.config/ly/ly-override.conf" /etc/systemd/system/ly@tty1.service.d/override.conf

# Copying GRUB config/theme
sudo mkdir -p /boot/grub/themes/catppuccin-mocha
sudo cp -rL $HOME/.config/grub/. /boot/grub/themes/catppuccin-mocha/
[ "$CMDLINE_MODE" = uki ] && sudo chmod -x /etc/grub.d/10_linux
grub_set_default GRUB_TERMINAL_OUTPUT gfxterm
grub_set_default GRUB_THEME '"/boot/grub/themes/catppuccin-mocha/theme.txt"'
sudo sed -i 's|^GRUB_TERMINAL_INPUT=console|#GRUB_TERMINAL_INPUT=console|' /etc/default/grub
grub_set_default GRUB_TIMEOUT 15
# Drop GRUB's per-firmware-entry (EFI BootNext) menu entries; keep "UEFI Firmware Settings"
grep -q '^NoExtract.*_efi_bootnext' /etc/pacman.conf || \
  sudo sed -i '/^\[options\]/a NoExtract = etc/grub.d/*_efi_bootnext' /etc/pacman.conf
sudo rm -f /etc/grub.d/*_efi_bootnext
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Getting the bashrc set up
echo '[ -f ~/.config/bash/bashrc ] && . ~/.config/bash/bashrc' > ~/.bashrc

# Making the initramfs to apply our configs
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Purging any orphaned packages
orphans=$(yay -Qtdq 2>/dev/null)
[ -n "$orphans" ] && yay -Rns --noconfirm $orphans
yay -Scc --noconfirm

msg_ok "Everything seems to have been applied successfully, reboot for the changes to take effect"

