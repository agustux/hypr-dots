#!/bin/bash

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

# Intel undervolt support detection (i3/i5/i7/i9, 4th-10th gen)
CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo)
NUM=$(echo "$CPU_MODEL" | grep -oP 'i[3579]-\K[0-9]{4,5}')
if [[ "$NUM" =~ ^1[0-4] ]]; then GEN="${NUM:0:2}"; else GEN="${NUM:0:1}"; fi
UNDERVOLT_SUPPORTED=0
[[ "$GEN" =~ ^([4-9]|10)$ ]] && UNDERVOLT_SUPPORTED=1

# Intel iGPU/CPU presence detection (vendor ID 8086 = Intel)
IS_INTEL=0
lspci -d 8086: | grep -qi 'vga\|3d\|display' && IS_INTEL=1
grep -qi 'GenuineIntel' /proc/cpuinfo && IS_INTEL=1

# Chrultrabook detection (Chrome EC survives full UEFI firmware flash)
modprobe cros_ec_lpcs 2>/dev/null
IS_CHROMEBOOK=0
[ -e /dev/cros_ec ] && IS_CHROMEBOOK=1
[ -d /sys/bus/platform/devices/GOOG*/ ] 2>/dev/null && IS_CHROMEBOOK=1

# Broadcom wifi detection (vendor ID 14e4 = Broadcom)
NEEDS_BROADCOM_WL=0
lspci -d 14e4: | grep -qi network && NEEDS_BROADCOM_WL=1

# Parse flags (for non-interactive runs)
FORCE_NVIDIA=0
BLOAT=0
GNOME=0
FOOT=0
NOSWAP=0
for arg in "$@"; do
  case "$arg" in
    --noswap) NOSWAP=1 ;;
    --foot) FOOT=1 ;;
    --nvidia) FORCE_NVIDIA=1 ;;
    --bloat) BLOAT=1 ;;
    --gnome) GNOME=1 ;;
  esac
done
[ "$BLOAT" -eq 1 ] && GNOME=1

# NVIDIA presence detection (vendor ID 10de = NVIDIA), with --nvidia override
# and an interactive fallback prompt if no GPU is detected and no flag was passed
NVIDIA=0
if [ "$FORCE_NVIDIA" -eq 1 ] || [ "$BLOAT" -eq 1 ]; then
  NVIDIA=1
else
  lspci -d 10de: | grep -qi 'vga\|3d\|display' && NVIDIA=1
  if [ "$NVIDIA" -eq 0 ]; then
    read -rp "No NVIDIA GPU detected. Install NVIDIA drivers/config anyway? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] && NVIDIA=1
  fi
fi

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

# Basic Hyprland Packages
yay -S --needed --noconfirm hyprland xdg-desktop-portal-gtk xdg-desktop-portal-hyprland \
    hyprpolkitagent hyprlock hypridle hyprpaper hyprshot hyprshutdown wl-clipboard dunst brightnessctl

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
yay -S --needed --noconfirm bash-completion tar-scripts exfat-utils libcamera gst-plugin-libcamera \
    pipewire-libcamera libcamera-tools libcamera-ipa xorg-xhost sof-firmware

# Neovim Packages
yay -S --needed --noconfirm neovim ripgrep fd tree-sitter-cli lua-language-server \
    bash-language-server pyright clang markdown-oxide

# GNOME
if [ "$GNOME" -eq 1 ]; then
  yay -S --needed --noconfirm gdm gnome-shell gnome-control-center gnome-session \
      xdg-desktop-portal-gnome dconf
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

# Configuring TLP:
sudo systemctl enable tlp.service
sudo systemctl mask systemd-rfkill.service systemd-rfkill.socket
sudo mkdir -p /etc/tlp.d
sudo tee /etc/tlp.d/00-custom.conf > /dev/null <<EOF
# CPU
CPU_SCALING_GOVERNOR_ON_BAT=powersave
CPU_BOOST_ON_BAT=0
NMI_WATCHDOG=0

# PCIe / Runtime PM
PCIE_ASPM_ON_BAT=powersave
RUNTIME_PM_ON_BAT=auto

# USB
USB_AUTOSUSPEND=1

# WiFi
WIFI_PWR_ON_BAT=on
USB_EXCLUDE_BTUSB=1
EOF

if [ "$UNDERVOLT_SUPPORTED" -eq 1 ]; then
  sudo systemctl enable intel-undervolt
  sudo tee /etc/intel-undervolt.conf > /dev/null <<EOF
enable yes

undervolt 0 'CPU' -150
undervolt 1 'GPU' -80
undervolt 2 'CPU Cache' -120
undervolt 3 'System Agent' -100
undervolt 4 'Analog I/O' -100

interval 5000

daemon undervolt:once
daemon power
daemon tjoffset
EOF
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
      NVIDIA_LEGACY=0   # --bloat: skip detection, always open driver
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
      yay -S --needed --noconfirm nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils linux-headers
  else
      yay -S --needed --noconfirm nvidia-utils lib32-nvidia-utils nvidia-open-dkms linux-headers
  fi

  sudo systemctl enable nvidia-resume
  sudo systemctl enable nvidia-suspend
  sudo systemctl enable nvidia-hibernate

  set_param iommu pt
  set_param nvidia.NVreg_PreserveVideoMemoryAllocations 1
  set_param nvidia_drm.modeset 1
  [ "$CMDLINE_MODE" = uki ] && sudo mkinitcpio -P

  sudo tee /etc/modprobe.d/nvidia-pm.conf > /dev/null << 'EOF'
options nvidia NVreg_DynamicPowerManagement=0x02
options nvidia NVreg_EnableGpuFirmware=0
EOF
  sudo tee /etc/udev/rules.d/80-nvidia-pm.rules > /dev/null << 'EOF'
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{remove}="1"
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{remove}="1"
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="on"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="on"
EOF
fi
# End NVIDIA stuff for hyprland

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

cd $HOME && git clone https://github.com/agustux/hypr-dots.git
mkdir -p $HOME/.config
cp -r $HOME/hypr-dots/.config/. $HOME/.config/

# Rewriting hardcoded home path in GTK bookmarks
for d in gtk-3.0 gtk-4.0; do
  sed "s|@USER@|$USER|g" "$HOME/.config/$d/bookmarks.tmpl" > "$HOME/.config/$d/bookmarks"
  rm "$HOME/.config/$d/bookmarks.tmpl"
done

# Swapping terminal to foot (foot has no --gtk-single-instance flag)
if [ "$FOOT" -eq 1 ]; then
  sed -i -e 's|^local var_terminal = .*|local var_terminal = "foot"|' \
         -e 's|^local var_terminal_flags = .*|local var_terminal_flags = ""|' \
         "$HOME/.config/hypr/hyprland.lua"
fi

# Rewriting hardcoded home path for QT
sed "s|@HOME@|$HOME|g" ~/.config/hypr/hyprqt6engine.conf.tmpl > ~/.config/hypr/hyprqt6engine.conf

# Quieting kernel messages on the console
set_param loglevel 3

# Setting VT color scheme
set_param vt.default_red "30,243,166,249,137,245,148,205,88,243,166,249,137,245,148,166"
set_param vt.default_grn "30,139,227,226,180,194,226,214,91,139,227,226,180,194,226,173"
set_param vt.default_blu "46,168,161,175,250,231,213,244,112,168,161,175,250,231,213,200"
[ "$CMDLINE_MODE" = uki ] && sudo mkinitcpio -P

# Copying GRUB config
sudo mkdir -p /boot/grub/themes/catppuccin-mocha
sudo cp -r $HOME/.config/grub/. /boot/grub/themes/catppuccin-mocha/
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


# Linking .config's ly config to /etc
sudo ln -sf "$HOME/.config/ly/config.ini" /etc/ly/config.ini
sudo mkdir -p /etc/systemd/system/ly@tty1.service.d
sudo tee /etc/systemd/system/ly@tty1.service.d/override.conf > /dev/null << 'EOF'
[Service]
ExecStartPre=/usr/bin/printf '%%b' '\e]P01e1e2e\e]P7cdd6f4\ec'
EOF

# Getting the hyprland configs set up
echo '[ -f ~/.config/bash/bashrc ] && . ~/.config/bash/bashrc' > ~/.bashrc

# Purging any orphaned packages
orphans=$(yay -Qtdq 2>/dev/null)
[ -n "$orphans" ] && yay -Rns --noconfirm $orphans
yay -Scc --noconfirm

echo  -e "\nEverything seems to have been applied successfully, reboot for the changes to take effect"
