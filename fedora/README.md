# Fedora 42 KDE — macOS-style Setup

Automates a macOS-themed Fedora 42 KDE Plasma 6 desktop: WhiteSur theme stack
(Plasma + Kvantum + icons + cursors + GTK), Inter fonts, JetBrains Mono, a top
menu bar + bottom icon dock layout, and a matching Konsole profile. Run as a
normal user after first boot.

## Safety Net — Take a Snapshot First

Third-party install scripts touch `/usr/share` and system config. Take a
Btrfs snapshot before running the theming modules.

```bash
# Option A — snapper (if configured)
sudo snapper -c root create -d "pre-whitesur"

# Option B — raw btrfs snapshot
sudo btrfs subvolume snapshot / /.snapshots/pre-whitesur-$(date +%F)

# Option C — Timeshift (GUI or CLI)
sudo timeshift --create --comments "pre-whitesur"
```

> **Kernel fallback**: Fedora keeps the previous kernel in GRUB (`installonly_limit=3`
> in `/etc/dnf/dnf.conf`). If a Plasma update breaks the desktop, reboot and select
> the previous kernel entry from the GRUB menu.

## Prerequisites

| Requirement | Notes |
|---|---|
| Fedora 42 KDE Spin | KDE Plasma 6.4+. Other spins untested. |
| Normal user with sudo | Do **not** run as root. |
| Live Plasma session | Panel/wallpaper commands require a running Plasma session. Theming-only modules (fonts, GTK) work headless. |
| Internet connection | Clones WhiteSur repos from GitHub. ~200 MB total. |
| `git` installed | Pre-installed on Fedora 42. |

## Quick Start

```bash
# Recommended: take a Btrfs snapshot first (see Safety Net above)

# Run everything in order
bash fedora/scripts/postinstall.sh --all

# Or via the root dispatcher (auto-detects Fedora)
bash setup.sh --all
```

The script is safe to re-run. Each module is idempotent.

## Module Reference

| Flag | What it does |
|---|---|
| `--all` | Runs all modules in dependency order |
| `--repos` | Enables RPM Fusion free + nonfree, adds Flathub, upgrades system |
| `--fonts` | Installs Inter, JetBrains Mono, Noto Emoji; applies KDE font config |
| `--apps` | Installs flameshot, podman, distrobox, Chrome (Flatpak), enables firewalld |
| `--themes` | Clones + installs WhiteSur-kde (Plasma look-and-feel + Aurorae) |
| `--kvantum` | Installs Kvantum, sets WhiteSurDark widget style |
| `--icons` | Clones + installs WhiteSur icons and cursors |
| `--decorations` | Configures Aurorae window decorations, macOS left-side buttons |
| `--wallpapers` | Clones + installs WhiteSur wallpapers, sets default background |
| `--panel` | Applies macOS panel layout (top bar + bottom dock) via Plasma Scripting API |
| `--konsole` | Installs MacOS Konsole profile and color scheme, sets as default |

## Known Limitations

| Area | Limitation |
|---|---|
| SF Pro font | Apple's SF Pro is proprietary. **Inter** is used instead — visually close for UI text. |
| SDDM login screen | SDDM theming is intentionally skipped. SDDM is removed in Fedora 44+; login screen styling is not worth the maintenance cost. |
| Dock zoom effect | The Parabolic zoom widget (macOS-like magnification) requires an unmaintained community plugin. The native Icons-Only Task Manager dock is used instead — no zoom. |
| Panel layout script | `panel-layout.js` uses the Plasma 6 Desktop Scripting API. It clears and rebuilds all panels on each run — manual panel customizations are reset. Re-test after a major Plasma version upgrade. |
| Global menu (GTK apps) | The `org.kde.plasma.appmenu` widget works natively for KDE/Qt apps. GTK app menus require `appmenu-gtk3-module` (install via `dnf install appmenu-gtk3-module`). |
| Headless / CI runs | Modules 4–10 apply Plasma config and may print warnings when no graphical session is active. The script continues and returns the correct exit code. |

## Next Steps

After `--all` completes:

1. Log out and back in to apply font and theme changes fully.
2. If the panel layout looks off, re-run: `bash fedora/scripts/postinstall.sh --panel`
3. Open Konsole → Settings → Edit Current Profile → confirm **MacOS** is selected.
4. Check the summary output for any failed modules and re-run them individually.
