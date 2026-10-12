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
bash -c "$(curl -fsSL https://raw.githubusercontent.com/agustux/hypr-dots/main/install.sh)"
```
Flags:
- `--nvidia`  Install NVIDIA drivers/config
- `--gnome`   Install GNOME and switch the display manager from ly to GDM, still installs rest
- `--bloat`   Install Gus-curated extra tools and utilities, including the NVIDIA driver and GNOME stuff
- `--foot`    Install foot instead of Ghostty as the terminal

The installer may modify your system configuration and will install
packages. Review install.sh before running it if you want to see exactly
what will be changed.

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

### Screenshots

| Keys | Action |
|---|---|
| `Print` | Region |
| `Alt + Print` | Window |
| `Super + Print` | Primary output |

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
