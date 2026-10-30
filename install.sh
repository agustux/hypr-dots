#!/bin/bash

####################################################################################################
# PREFLIGHT ENVIRONMENT CHECKS
####################################################################################################

# Stop immediately if UID is root
if [ "$EUID" -eq 0 ]; then
  echo "Don't run this script as root" >&2
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

set_param() {
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

# Dotfiles update/installer function
DOTS="$HOME/.local/share/hypr-dots"
deploy_dotfiles() {
  mkdir -p "$HOME/.local/share" "$HOME/.config"
  if [ -d "$DOTS/.git" ]; then
    git -C "$DOTS" pull --ff-only || return 1
  else
    git clone https://github.com/agustux/hypr-dots.git "$DOTS" || return 1
  fi

  # Prune symlinks to files removed upstream
  find "$HOME/.config" -xtype l -lname "$DOTS/*" -delete
  (cd "$DOTS/.config" && find . -type f -print0) | while IFS= read -r -d '' f; do
    mkdir -p "$HOME/.config/$(dirname "$f")"
    ln -sf "$DOTS/.config/$f" "$HOME/.config/$f"
  done

  # Apply username fix to templates
  sed "s|@USER@|$USER|g" "$HOME/.config/gtk-3.0/bookmarks.tmpl" > "$HOME/.config/gtk-3.0/bookmarks"
  sed "s|@HOME@|$HOME|g" "$HOME/.config/hypr/hyprqt6engine.conf.tmpl" > "$HOME/.config/hypr/hyprqt6engine.conf"

  # Render Waybar configs, one per WM
  if [ -f "$HOME/.config/waybar/config.tmpl" ]; then
    for wm in hyprland sway; do
      sed "s|@WORKSPACES_MODULE@|$wm/workspaces|g" "$HOME/.config/waybar/config.tmpl" > "$HOME/.config/waybar/config.$wm"
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

# Intel iGPU/CPU presence detection (vendor ID 8086 = Intel)
IS_INTEL=0
for d in /sys/class/drm/card[0-9]*/device; do
  [[ $(<"$d/vendor") == 0x8086 ]] && IS_INTEL=1 && break
done
grep -qm1 GenuineIntel /proc/cpuinfo && IS_INTEL=1

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
UPDATE=0

for arg in "$@"; do
  case "$arg" in
    --bloat) BLOAT=1 ;;
    --foot) FOOT=1 ;;
    --gnome) GNOME=1 ;;
    --noswap) NOSWAP=1 ;;
    --nvidia) FORCE_NVIDIA=1 ;;
    --sway) SWAY=1 ;;
    --update) UPDATE=1 ;;
  esac
done

# Just update dots if --update used
if [ "$UPDATE" -eq 1 ]; then
  deploy_dotfiles || exit 1
  echo -e "\n\033[0;32mDotfiles updated, reboot to apply changes\033[0m"
  exit 0
fi

# Install GNOME if --bloat used
[ "$BLOAT" -eq 1 ] && GNOME=1

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

# Installing yay (AUR helper):
if ! command -v yay &> /dev/null; then
  cd "$HOME" || exit 1
  sudo pacman -Sy --needed --noconfirm git base-devel \
    && git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin \
    && makepkg -s --needed --noconfirm \
    && sudo pacman -U --needed --noconfirm yay-bin-*.pkg.tar.*
  cd "$HOME" && rm -rf yay-bin/
fi

# Removing actual bloat
BLOAT_PKGS=(polkit-kde-agent wofi kwallet dolphin uwsm kitty htop power-profiles-daemon)
TO_REMOVE=()
for pkg in "${BLOAT_PKGS[@]}"; do
  pacman -Qq "$pkg" &> /dev/null && TO_REMOVE+=("$pkg")
done
[ "${#TO_REMOVE[@]}" -gt 0 ] && sudo pacman -Rns --noconfirm "${TO_REMOVE[@]}"

# Basic WM Packages
if [ "$SWAY" -eq 1 ]; then
  yay -S --needed --noconfirm sway xdg-desktop-portal-gtk xdg-desktop-portal-wlr \
      hyprpolkitagent hyprlock swayidle swaybg grim slurp sway-contrib wl-clipboard dunst brightnessctl \
      jq wl-mirror
else
  yay -S --needed --noconfirm hyprland xdg-desktop-portal-gtk xdg-desktop-portal-hyprland \
      hyprpolkitagent hyprlock hypridle hyprpaper hyprshot hyprshutdown wl-clipboard dunst brightnessctl
fi

# Terminal
if [ "$FOOT" -eq 1 ]; then
  yay -S --needed --noconfirm foot
else
  yay -S --needed --noconfirm ghostty
fi

# Basic Hyprland Packages (AUR)
yay -S --needed --noconfirm hyprqt6engine

# Audio
yay -S --needed --noconfirm pipewire pipewire-pulse wireplumber

# Session / Auth
yay -S --needed --noconfirm gnome-keyring

# Theming / Qt
yay -S --needed --noconfirm qt6ct qt6-wayland adw-gtk-theme

# Rice
yay -S --needed --noconfirm ttf-dejavu ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols-mono \
    ttf-nerd-fonts-symbols noto-fonts-emoji waybar rofi

# Rice (AUR)
yay -S --needed --noconfirm rofi-bluetooth-git

# Network / Bluetooth / Power Utils
yay -S --needed --noconfirm networkmanager-dmenu tlp pavucontrol \
    nm-connection-editor blueman

# GUI Utilities
yay -S --needed --noconfirm baobab gnome-disk-utility nautilus loupe decibels snapshot vlc \
    vlc-plugins-all gnome-calculator gnome-clocks papers

# GUI Utilities (AUR)
yay -S --needed --noconfirm brave-origin-bin

# CLI Utilities
yay -S --needed --noconfirm curl less man-db ufw rsync powertop nvtop zip unzip \
    cpupower fastfetch

# Support Libraries
yay -S --needed --noconfirm "${KERNEL_HEADERS[@]}" bash-completion tar-scripts exfatprogs exfat-utils \
    libcamera gst-plugin-libcamera pipewire-libcamera libcamera-tools libcamera-ipa xorg-xhost sof-firmware

# Neovim Packages
yay -S --needed --noconfirm neovim ripgrep fd tree-sitter-cli lua-language-server \
    bash-language-server pyright clang markdown-oxide

# GNOME
if [ "$GNOME" -eq 1 ]; then
  yay -S --needed --noconfirm gdm gnome-shell gnome-control-center gnome-session \
      gnome-backgrounds xdg-desktop-portal-gnome dconf
fi

# Broadcom Wifi MacBook Fixes
if [ "$NEEDS_BROADCOM_WL" -eq 1 ]; then
  sudo pacman -S --needed --noconfirm broadcom-wl-dkms
fi

# Intel-related
if [ "$IS_INTEL" -eq 1 ] || [ "$BLOAT" -eq 1 ]; then
  yay -S --needed --noconfirm intel-gpu-tools vulkan-intel lib32-vulkan-intel \
      intel-media-driver libva-intel-driver
  if [ "$UNDERVOLT_SUPPORTED" -eq 1 ]; then
    yay -S --needed --noconfirm intel-undervolt
  fi
fi

# T2 Mac
if [ "$IS_T2" -eq 1 ]; then
  yay -S --needed --noconfirm t2fanrd
fi

# Full Gus Packages
if [ "$BLOAT" -eq 1 ]; then
    # Misc.
    yay -S --needed --noconfirm proton-vpn-gtk-app obs-studio windscribe-v2-bin localsend-bin ventoy-bin yt-dlp \
         android-udev android-tools gvfs-mtp libmtp scrcpy gnirehtet-bin opencode
    # Other graphics stuff
    yay -S --needed --noconfirm mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader \
        libdrm lib32-libdrm lib32-glibc \
        lib32-gcc-libs lib32-libglvnd lib32-wayland lib32-libx11 lib32-libxcb lib32-libpulse \
        lib32-libpipewire lib32-alsa-lib lib32-alsa-plugins
fi

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

# Chrultrabook Fixes (if chromebook)
if [ "$IS_CHROMEBOOK" -eq 1 ]; then
  yay -S --needed --noconfirm alsa-utils
  TMP_DIR=$(mktemp -d)
  git clone --depth 1 https://github.com/WeirdTreeThing/chromebook-linux-audio "$TMP_DIR/audio" \
      && (cd "$TMP_DIR/audio" && printf '1\nsst\n' | ./setup-audio)
  git clone --depth 1 https://github.com/WeirdTreeThing/cros-keyboard-map "$TMP_DIR/kbd" \
      && (cd "$TMP_DIR/kbd" && echo "n" | ./install.sh)
  rm -rf "$TMP_DIR"
fi

# NVIDIA stuff for hyprland
if [ "$NVIDIA" -eq 1 ]; then
  GPU_NAME=$(lspci -d 10de: | grep -iE 'vga|3d|display')
  NVIDIA_LEGACY=0
  if [ "$BLOAT" -eq 1 ]; then
      NVIDIA_LEGACY=0   # --bloat: skip detection, always latest open driver
  elif [ -z "$GPU_NAME" ]; then
      NVIDIA_LEGACY=0   # No NVIDIA GPU present (user override): open driver
  elif echo "$GPU_NAME" | grep -qPi 'RTX\s*[2-9][0-9]{3}|GTX\s*16[0-9]{2}|TITAN RTX|Tesla T4|Quadro T[0-9]{3,4}'; then
      NVIDIA_LEGACY=0   # Turing+
  elif echo "$GPU_NAME" | grep -qPi 'GTX\s*(9[0-9]{2}|10[0-9]{2})|GTX\s*750\s*Ti|Quadro [MP][0-9]{3,4}|TITAN\s*(X|Xp|V)\b|Tesla [MPV][0-9]+|GP100'; then
      NVIDIA_LEGACY=1   # Maxwell/Pascal/Volta
  else
      echo "Warning: unrecognized GPU '$GPU_NAME' — assuming Turing+ (open driver)" >&2
  fi

  if [ "$NVIDIA_LEGACY" -eq 1 ]; then
      yay -S --needed --noconfirm nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-580xx-dkms
  else
      yay -S --needed --noconfirm nvidia-utils lib32-nvidia-utils nvidia-open-dkms
  fi

  sudo systemctl enable nvidia-resume
  sudo systemctl enable nvidia-suspend
  sudo systemctl enable nvidia-hibernate

  set_param iommu pt
  set_param nvidia.NVreg_PreserveVideoMemoryAllocations 1
  set_param nvidia_drm.modeset 1
fi
# End NVIDIA stuff for hyprland

# T2 Mac
if [ "$IS_T2" -eq 1 ]; then
  set_param intel_iommu on
  set_param iommu pt
  set_param pm_async off

  echo t2bce_vhci | sudo tee /etc/modules-load.d/t2.conf > /dev/null

  # Early-load modules (reverse order: each is prepended)
  for m in t2bce_vhci t2bce_core t2bce_dma; do
    grep -qE "^MODULES=\(.*\b$m\b" /etc/mkinitcpio.conf \
      || sudo sed -i -E "s/^MODULES=\(/MODULES=($m /" /etc/mkinitcpio.conf
  done

  # Audio
  T2_AUDIO=$(mktemp -d)
  git clone --depth 1 https://github.com/kekrby/t2-better-audio.git "$T2_AUDIO" \
    && (cd "$T2_AUDIO" && ./install.sh)
  rm -rf "$T2_AUDIO"

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
if [ ! -f "$LOCAL_LUA" ]; then
  if [ "$FOOT" -eq 1 ]; then
    # foot has no --gtk-single-instance flag
    cat > "$LOCAL_LUA" << 'EOF'
-- Local overrides (untracked). Keys: terminal, terminal_flags
return {
  terminal = "foot",
  terminal_flags = "",
}
EOF
  else
    printf -- '-- Local overrides (untracked). Keys: terminal, terminal_flags\nreturn {}\n' > "$LOCAL_LUA"
  fi
fi

# Sway per-machine overrides (untracked)
LOCAL_SWAY="$HOME/.config/sway/local.conf"
if [ ! -f "$LOCAL_SWAY" ]; then
  if [ "$FOOT" -eq 1 ]; then
    echo 'set $terminal foot' > "$LOCAL_SWAY"
  else
    : > "$LOCAL_SWAY"
  fi
fi

# Quieting kernel messages on the console
set_param loglevel 3

# Setting VT color scheme
set_param vt.default_red "30,243,166,249,137,245,148,205,88,243,166,249,137,245,148,166"
set_param vt.default_grn "30,139,227,226,180,194,226,214,91,139,227,226,180,194,226,173"
set_param vt.default_blu "46,168,161,175,250,231,213,244,112,168,161,175,250,231,213,200"

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

# Ly config installation
sudo ln -sf "$HOME/.config/ly/config.ini" /etc/ly/config.ini
sudo install -Dm644 "$HOME/.config/ly/ly-override.conf" /etc/systemd/system/ly@tty1.service.d/override.conf

# Copying GRUB config/theme
sudo mkdir -p /boot/grub/themes/catppuccin-mocha
sudo cp -rL $HOME/.config/grub/. /boot/grub/themes/catppuccin-mocha/
[ "$CMDLINE_MODE" = uki ] && sudo chmod -x /etc/grub.d/10_linux
sudo sed -i 's|^#GRUB_TERMINAL_OUTPUT=.*|GRUB_TERMINAL_OUTPUT=gfxterm|' /etc/default/grub
sudo sed -i 's|^#\?GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/catppuccin-mocha/theme.txt"|' /etc/default/grub
sudo sed -i 's|^GRUB_TERMINAL_INPUT=console|#GRUB_TERMINAL_INPUT=console|' /etc/default/grub
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=15/' /etc/default/grub
# Drop GRUB's per-firmware-entry (EFI BootNext) menu entries; keep "UEFI Firmware Settings"
grep -q '^NoExtract.*_efi_bootnext' /etc/pacman.conf || \
  sudo sed -i '/^\[options\]/a NoExtract = etc/grub.d/*_efi_bootnext' /etc/pacman.conf
sudo rm -f /etc/grub.d/*_efi_bootnext
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Getting the bashrc set up
echo '[ -f ~/.config/bash/bashrc ] && . ~/.config/bash/bashrc' > ~/.bashrc

# Making the initramfs to apply our configs
if [ "$CMDLINE_MODE" = "uki" ]; then
    sudo mkinitcpio -P
elif [ "$CMDLINE_MODE" = "grub" ]; then
    sudo grub-mkconfig -o /boot/grub/grub.cfg
fi

# Purging any orphaned packages
orphans=$(yay -Qtdq 2>/dev/null)
[ -n "$orphans" ] && yay -Rns --noconfirm $orphans
yay -Scc --noconfirm

echo -e "\n\033[0;32mEverything seems to have been applied successfully, reboot for the changes to take effect\033[0m"

