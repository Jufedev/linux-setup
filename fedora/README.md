# Fedora 42 KDE — macOS-style Setup

Automates a macOS-themed Fedora 42 KDE Plasma 6 desktop: WhiteSur theme stack
(Plasma + Kvantum + icons + cursors + GTK), Inter fonts, Cascadia Code, a top
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
| `--gpu` | Installs NVIDIA open kernel modules (`akmod-nvidia-open`) for Blackwell/RTX 50 cards; blacklists nouveau, enables KMS. No-op without an NVIDIA card. See [NVIDIA Dedicated GPU](#nvidia-dedicated-gpu-blackwell--rtx-50) |
| `--fonts` | Installs Inter, Cascadia Code Nerd Font, Apple Color Emoji, Windows-equivalent fonts; applies KDE font config |
| `--apps` | Installs flameshot, podman, distrobox, Chrome + Edge (Flatpak), enables firewalld |
| `--themes` | Clones + installs WhiteSur-kde (Plasma look-and-feel + Aurorae) |
| `--gtk` | Clones + installs WhiteSur-gtk-theme (GTK3/GTK4 + libadwaita link) |
| `--kvantum` | Installs Kvantum, sets WhiteSurDark widget style |
| `--icons` | Clones + installs WhiteSur icons and cursors |
| `--decorations` | Configures Aurorae window decorations, macOS left-side buttons |
| `--wallpapers` | Clones + installs WhiteSur wallpapers, sets default background |
| `--panel` | Applies macOS panel layout (top bar + bottom dock) via Plasma Scripting API; clock shows 24h + date |
| `--konsole` | Installs MacOS Konsole profile and color scheme, sets as default |
| `--keyboard` | Sets English intl (AltGr dead keys) keyboard layout (KDE session + system-wide via localectl) |

## NVIDIA Dedicated GPU (Blackwell / RTX 50)

The `--gpu` module installs the **open kernel modules** (`akmod-nvidia-open`) —
the only supported option for Blackwell cards (RTX 50 series, e.g. RTX 5060 Ti).
The legacy proprietary module no longer supports this architecture.

```bash
bash fedora/scripts/postinstall.sh --gpu
```

It installs `akmod-nvidia-open` + CUDA/VAAPI support, blacklists nouveau, sets
`nvidia-drm.modeset=1`, builds the akmod, and rebuilds the initramfs. Reboot and
verify with `nvidia-smi`. Without an NVIDIA card the module is a no-op (Mesa
already covers AMD/Intel on Fedora).

> **Test without the card.** To exercise the NVIDIA path in a VM that has no
> NVIDIA GPU, force the branch: `FORCE_GPU=nvidia bash fedora/scripts/postinstall.sh --gpu`.
> This validates package resolution and the akmod build; the module won't *load*
> without real hardware.

### BIOS — disable the integrated GPU first

On a Ryzen APU (e.g. 5700G) the iGPU stays active alongside the dedicated card.
For a clean single-GPU desktop, disable it in BIOS before installing the driver.

**GIGABYTE B550M AORUS Elite AX (rev 1.3):**

1. Enter BIOS with `DEL`; switch to Advanced mode with `F2`.
2. `Settings → IO Ports → Integrated Graphics` → **Disabled**.
3. `Settings → IO Ports → Initial Display Output` → **PCIe 1 Slot**.
4. Plug the monitor into the **graphics card**, not the motherboard.
5. Save & exit with `F10`.

> If "Integrated Graphics" is missing, update the BIOS — older versions did not
> expose the Cezanne iGPU toggle.

### Secure Boot

The akmod module is unsigned by default and will not load under Secure Boot.
Either disable Secure Boot in BIOS, or sign the module:

```bash
sudo kmodgenca -a
sudo mokutil --import /etc/pki/akmods/certs/public_key.der   # set a one-time password
# reboot → MOK Manager → Enroll MOK → enter the password
```

### Kernel 7.0 suspend caveat

Blackwell + nvidia-open has a known s2idle suspend/resume regression on Linux 7.0
(unfixed as of mid-2026). Fedora 42 (kernel 6.14) and 43 (6.17) are unaffected.
If you move to a 7.0 kernel and resume hangs, fall back to a 6.17/LTS kernel.

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
