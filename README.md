# My Hyprland Dotfiles
My minimalistic and lightweight Hyprland config for Arch with NVIDIA support(incl. 580 devices if needed), in Catppuccin Mocha.
Config is in hyprland.lua, includes runtime hardware detection (display outputs, GPU driver, undervolt support)
instead of hardcoded values, so the same dotfiles port across different machines.
Laptop battery life is priority, so power tooling (tlp, power-profiles-daemon, intel-undervolt) is included

### Requirements:
- Arch Linux
- Internet connection
- A supported (clean) Hyprland environment

This should preferably run after a clean arch install

### Quickstart:
```
curl -fsSL https://raw.githubusercontent.com/agustux/hypr-dots/main/install.sh | bash -s -- <flags here>
```
Flags:
- `--nvidia`  Install NVIDIA drivers/config
- `--gnome`   Install GNOME and switch the display manager from ly to GDM, still installs rest
- `--bloat`   Install Gus-curated extra tools and utilities, including the NVIDIA driver and GNOME stuff
- `--foot`    Install foot instead of Ghostty as the terminal
- `--noswap`  Skip creating the 4GB swapfile, for really storage constrained systems 
- `--update`  Only update dotfiles (for existing installs)
- `--sway`    Also install Sway and its packages (Hyprland stays installed)

The installer may modify your system configuration and will install
packages. Review install.sh before running it if you want to see exactly
what will be changed.

## Sway

Hyprland and Sway coexist. `--sway` only adds Sway's packages; both configs are always installed.
Pick the session at the display manager (ly's stock "Sway" entry works).

- Waybar configs are rendered at install: `config.hyprland` and `config.sway`. Each WM starts `waybar -c <file>`.
- `/usr/local/bin/sway` wraps `/usr/bin/sway`. It sets GPU, VA-API, cursor and Qt env before launch, as `hyprland.lua` does.
- `sway-outputs.sh` applies the same capped mode (max 1920 wide, native aspect ratio) and mirrors extra displays with `wl-mirror`.
- Portals: `~/.config/xdg-desktop-portal/sway-portals.conf` (gtk default, wlr for ScreenCast/Screenshot).
- Existing installs: re-run with `--update`. The old `~/.config/waybar/config` is no longer used and can be deleted.
- Sway keybinds are in `.config/sway/config`.
- Wallpaper: sway's `output * bg` (swaybg). Idle and suspend: swayidle (`~/.config/swayidle/config`). Lock screen: hyprlock, shared with Hyprland.
- Per-machine overrides (e.g. terminal) go in untracked `~/.config/sway/local.conf`, created by the installer.

## Keybinds

`Super` is the main modifier.

### Apps

| Keys | Action |
|---|---|
| `Super + Q` | Terminal (Ghostty, or foot if used `--foot`) |
| `Super + E` | Fil**e** manager (Nautilus) |
| `Super + B` | **B**rowser (**B**rave Origin) |
| `Super + R` | Launche**r** (**r**ofi) |
| `Super + W` | Toggle **W**aybar |
| `Super + Shift + Q` | Lock session |
| `Super + M` | Exit Hyprland |
| `Super + Shift + R` | Reload config (Sway only; Hyprland reloads on save) |

### Screenshots

| Keys | Action |
|---|---|
| `Print` | Region |
| `Alt + Print` | Window |
| `Super + Print` | Primary output |
| `Super + Shift + P` | Region |
| `Super + Alt + P` | Window |
| `Super + Ctrl + P` | Primary output |

### Windows

| Keys | Action |
|---|---|
| `Super + C` | **C**lose |
| `Super + P` | **P**seudotile |
| `Super + T` | **T**oggle split |
| `Super + V` | Toggle floating |
| `Super + F` | Toggle **f**ullscreen |
| `Super + H/J/K/L` | Focus left/down/up/right |
| `Super + Shift + H/J/K/L` | Swap window left/down/up/right |
| `Super + LMB drag` | Move |
| `Super + RMB drag` | Resize |
| `Super + Ctrl + R` | Resize mode: `H`/`L` shrink/grow width, `K`/`J` shrink/grow height, `Esc`/`Enter` exits |

### Workspaces

| Keys | Action |
|---|---|
| `Super + 1–0` | Switch to workspace 1–10 |
| `Super + Shift + 1–0` | Move window to workspace 1–10 |
| `Super + Scroll` | Cycle workspaces |
| 3-finger swipe | Switch workspace |
| `Super + S` | Toggle **s**cratchpad |
| `Super + Shift + S` | Move window to **s**cratchpad |

![Example of my rice](https://github.com/agustux/hypr-dots/blob/main/assets/2026-09-11-142304_hyprshot.png)
