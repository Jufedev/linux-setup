# Fedora 44 KDE — macOS-style Setup

Automates a macOS-themed Fedora 44 KDE Plasma 6 desktop: WhiteSur theme stack
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
| Fedora 44 KDE | KDE Plasma 6.x. Works on 42/43 too (scripts use `rpm -E %fedora`). |
| Normal user with sudo | Do **not** run as root. |
| Live Plasma session | Panel/wallpaper commands and Flatpak operations (`--repos`/`--apps`, which need a polkit agent) require a running session. Theming-only modules (fonts, GTK) work headless. |
| Internet connection | Clones WhiteSur repos from GitHub. ~200 MB total. |
| `git` installed | **Not preinstalled on the KDE Spin** — `sudo dnf install -y git` (you need it to clone this repo anyway). The theming/wallpaper modules also auto-install it if missing. |

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

> **Unified flags.** The flag set is **identical to the Arch setup** and each flag
> does the same thing on both. `--launcher` is a no-op on Fedora (KRunner is native),
> kept for parity. `--macos-look` is Fedora-only (the plasma6macos pack is KDE-specific).
> Arch's `--gnome` and `--cachyos`
> have no Fedora equivalent (KDE ships with the spin; CachyOS is Arch-only).
> `--debloat` is Fedora-only (Arch is minimal by construction, so it has nothing
> to strip).

| Flag | What it does |
|---|---|
| `--all` | Runs all modules in dependency order |
| `--repos` | Enables RPM Fusion free + nonfree, adds Flathub, upgrades system |
| `--hardware` | Microcode + NVIDIA open kernel modules (`akmod-nvidia-open`) for Blackwell/RTX 50; blacklists nouveau, enables KMS. No-op without an NVIDIA card. See [NVIDIA Dedicated GPU](#nvidia-dedicated-gpu-blackwell--rtx-50) |
| `--fonts` | Installs Inter, Cascadia Code Nerd Font, Apple Color Emoji, Windows-equivalent fonts; applies KDE font config |
| `--theme` | Full WhiteSur visual stack: Plasma look-and-feel + Aurorae + GTK + Kvantum + icons + cursors (base layer) |
| `--macos-look` | **The "video" look.** Applies the vendored [plasma6macos pack](../vendor/plasma6macos/ATTRIBUTION.md): MacSequoia Plasma theme + custom plasmoids (Tahoe Launcher / apps button, Control Center,  menu, weather) + KWin blur/kinetic effects + the exact panel layout. Runs in `--all` after `--theme` and overrides the Plasma style. See [The macOS look (plasma6macos)](#the-macos-look-plasma6macos) |
| `--desktop` | **Fallback** minimal panel layout (top bar + bottom dock) via Plasma Scripting API; clock shows 24h + date. `--all` uses `--macos-look` instead |
| `--terminal` | Installs MacOS Konsole profile and color scheme, sets as default |
| `--launcher` | KRunner is native to KDE — no-op (Meta or Alt+Space) |
| `--apps` | Installs flameshot, podman, distrobox, Chrome + Edge (Flatpak); enables firewalld and sets the default zone to `public` (deny incoming) |
| `--wallpapers` | Clones + installs WhiteSur wallpapers, sets default background |
| `--keyboard` | Sets English intl (AltGr dead keys) keyboard layout (KDE session + system-wide via localectl) |
| `--login` | macOS login look (from the pack). **Additive + reversible:** sets the greeter wallpaper via a drop-in (Plasma Login Manager on Fedora 44) or installs the `tahoe-sddm` theme (SDDM spins). Never touches autologin or the manager itself |
| `--debloat` | **Fedora-only, opt-in (NOT in `--all`).** Removes preinstalled KDE Spin apps that don't fit a minimal macOS-style desktop. See [Debloat](#debloat-fedora-only) |

## Debloat (Fedora-only)

The Fedora KDE Spin ships a full app catalog. `--debloat` strips the apps that
don't fit a minimal, macOS-style desktop. It is **opt-in** and deliberately **not
part of `--all`** — it removes real productivity apps, so you choose when to run it.

```bash
bash fedora/scripts/postinstall.sh --debloat
```

Removes (~200 packages, ~1 GiB freed; `dnf` also drops the now-orphaned
dependencies):

| Group | Packages |
|---|---|
| KDE games | `kpat`, `kmines`, `kmahjongg` |
| KDE PIM suite | `kontact`, `kmail`, `korganizer`, `kaddressbook`, `akregator`, `akonadi-import-wizard`, `grantlee-editor`, `pim-data-exporter`, `pim-sieve-editor` |
| Media / comms | `dragon`, `elisa-player`, `kamoso`, `neochat`, `krfb`, `krdc` |
| Office / browser | `libreoffice-core` (full suite), `firefox` *(the setup installs Chrome + Edge)* |
| Redundant / one-offs | `spectacle` *(Flameshot is installed)*, `kolourpaint`, `kcharselect`, `khelpcenter`, `plasma-welcome`, `mediawriter`, `qrca`, `kmouth`, `skanpage` |
| Fedora cruft on KDE | `gnome-abrt`, `setroubleshoot` |

**Kept** (Plasma core + the setup's own stack): `plasma-desktop`, `plasma-workspace`,
`kwin`, `plasma-login-manager`, `dolphin`, `konsole`, `okular`, `gwenview`, `ark`,
`kcalc`, `plasma-discover`, `plasma-systemsettings`, `kde-connect`, `kwallet`,
`filelight`, `kde-partitionmanager`, `kleopatra`.

> Validated on a real Fedora KDE 44 VM: after `--debloat` the system still boots to
> the graphical login and Plasma is intact. The module is idempotent (re-running it
> is a no-op once the packages are gone) and reversible — reinstall anything with
> `sudo dnf install <package>`. One side effect: removing Firefox also drops
> `plasma-browser-integration`, so the kept Chrome/Edge lose panel media controls.

## NVIDIA Dedicated GPU (Blackwell / RTX 50)

The `--hardware` module installs the **open kernel modules** (`akmod-nvidia-open`) —
the only supported option for Blackwell cards (RTX 50 series, e.g. RTX 5060 Ti).
The legacy proprietary module no longer supports this architecture.

```bash
bash fedora/scripts/postinstall.sh --hardware
```

It installs `akmod-nvidia-open` + CUDA/VAAPI support, blacklists nouveau, sets
`nvidia-drm.modeset=1`, builds the akmod, and rebuilds the initramfs. Reboot and
verify with `nvidia-smi`. Without an NVIDIA card the module is a no-op (Mesa
already covers AMD/Intel on Fedora).

> **Open-module safeguard.** When RPM Fusion's `akmod-nvidia-open` lags behind the
> NVIDIA userspace (`xorg-x11-drv-nvidia`), `dnf` installs the open module **but
> also pulls the proprietary `akmod-nvidia`** to satisfy the userspace's
> `nvidia-kmod=<version>` dependency — and the proprietary one is the version that
> matches userspace, so it's the one that would load. On Blackwell (RTX 50) that
> means a **silent black screen**. After the install `--hardware` checks the
> installed kmod flavor and, if the proprietary module is present, prints a loud
> warning and flags it in the summary (`nvidia-proprietary-kmod-present`). Recheck
> with `rpm -q akmod-nvidia akmod-nvidia-open xorg-x11-drv-nvidia`; wait for RPM
> Fusion to resync the open module and reinstall, or exclude the proprietary one
> (`--exclude=akmod-nvidia,kmod-nvidia`, accepting that the install then fails until
> the open module catches up).

> **Test without the card.** To exercise the NVIDIA path in a VM that has no
> NVIDIA GPU, force the branch: `FORCE_GPU=nvidia bash fedora/scripts/postinstall.sh --hardware`.
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

NVIDIA Blackwell + nvidia-open has a known s2idle suspend/resume regression on
**Linux kernel 7.0** (unfixed as of mid-2026; reproduced on 7.0.4 and 7.0.9,
affects RTX 40 and 50 series). The trigger is the **kernel version, not the
Fedora release**:

- Fedora 44 ships **kernel 6.19** (safe) but pulls 7.0 via updates — a fully
  updated F44 likely runs 7.0.x. The `--repos` module runs `dnf upgrade`, so a
  fresh setup may land on 7.0.
- Fedora 42 (6.14) and 43 (6.17) are unaffected.

On a **desktop** the impact is low (you rarely suspend). If resume hangs, boot a
6.x kernel from the GRUB menu (Fedora keeps the last 3) or pin one until the
driver fix lands.

## The macOS look (plasma6macos)

The full desktop look from the reference tutorial is the **plasma6macos** pack
(author: Lsteam — KDE Store). WhiteSur alone doesn't match it because the pack's
Plasma theme is actually **MacSequoia** (vinceliuice) plus a set of custom plasmoids
that WhiteSur doesn't ship.

`--macos-look` (and `--all`) applies the desktop + login parts of that pack, vendored
in [`fedora/vendor/plasma6macos/`](../vendor/plasma6macos/ATTRIBUTION.md):

| Piece | What it adds |
|---|---|
| Plasmoids | **Tahoe Launcher** (the apps/Launchpad button), **KdeControlStation** (iOS-style Control Center), **kMenu** (the  menu), weather, window title-bar |
| MacSequoia theme | Plasma desktop theme + Aurorae window decoration + color schemes + look-and-feel (`MacSequoia-Light` by default) |
| KWin effects | Blur + kinetic open/close/maximize animations |
| Panel layout | The pack's exact `appletsrc` (top menu bar + floating dock). `dev.xarbit.appgrid` is swapped for the bundled `TahoeLauncher` |
| Login | Greeter wallpaper (Plasma Login Manager) or `tahoe-sddm` theme (SDDM) — additive and reversible |

**Why vendored:** the pack has no versioned releases on the KDE Store, so it can't be
pinned to a git ref like the WhiteSur repos. Committing it in-tree means the look
survives even if the upstream listing disappears. WhiteSur is kept as the base for
GTK/Kvantum/icons/cursors; MacSequoia overrides the Plasma style and panel layout on top.

**To revert** the panel layout: `cp ~/.config/plasma-org.kde.plasma.desktop-appletsrc.pre-macos.bak ~/.config/plasma-org.kde.plasma.desktop-appletsrc` and re-login. **To revert** the login: delete `/etc/plasmalogin.conf.d/95-macos-login.conf` (or `/etc/sddm.conf.d/95-macos-login.conf`).

## Known Limitations

| Area | Limitation |
|---|---|
| SF Pro font | Apple's SF Pro is proprietary. **Inter** is used instead — visually close for UI text. |
| Login screen | `--login` styles the greeter additively (wallpaper drop-in on Fedora 44's Plasma Login Manager; full `tahoe-sddm` theme on SDDM spins). The full QML greeter theme only applies where SDDM is the manager — on Fedora 44 only the wallpaper changes. |
| Pack versioning | plasma6macos has no upstream releases, so it's **vendored** (committed) instead of pinned to a ref. Bumping it means re-downloading the zips from the KDE Store and replacing `fedora/vendor/plasma6macos/`. |
| Panel layout | `--all`/`--macos-look` drops the pack's `appletsrc` and restarts plasmashell (a backup is saved to `*.pre-macos.bak`). `--desktop` is a minimal procedural fallback (`panel-layout.js`) that rebuilds panels on each run — manual panel customizations are reset. Re-test after a major Plasma version upgrade. |
| Global menu (GTK apps) | The `org.kde.plasma.appmenu` widget works natively for KDE/Qt apps. GTK app menus require `appmenu-gtk3-module` (install via `dnf install appmenu-gtk3-module`). |
| Firewall (deny incoming) | `--apps` sets firewalld's default zone to `public` (deny incoming except ssh/dhcpv6/mdns), matching the Arch setup. Fedora's stock `FedoraWorkstation` zone leaves ports 1025-65535 open — that is overridden. **KDE Connect / LAN file sharing need their ports opened manually** (e.g. `sudo firewall-cmd --permanent --add-service=kdeconnect && sudo firewall-cmd --reload`). |
| Headless / CI runs | Modules 4–10 apply Plasma config and may print warnings when no graphical session is active. The script continues and returns the correct exit code. |
| Flatpak needs a desktop session | `--repos` and `--apps` run **system-level** Flatpak ops (add the Flathub remote, install Chrome/Edge) that require a **polkit agent**. From a Plasma session they prompt for authorization and succeed; over SSH/headless they fail with `not allowed for user`. The intended flow is: install Fedora to disk → boot the desktop → `git clone` → run the scripts from Konsole. |

## Next Steps

After `--all` completes:

1. Log out and back in to apply font, theme and panel changes fully.
2. If the macOS panels/dock look off, re-run: `bash fedora/scripts/postinstall.sh --macos-look`
3. Open Konsole → Settings → Edit Current Profile → confirm **MacOS** is selected.
4. Check the summary output for any failed modules and re-run them individually.
