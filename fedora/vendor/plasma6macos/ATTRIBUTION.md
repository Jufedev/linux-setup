# plasma6macos — vendored assets

These assets are **not authored by this project**. They are vendored (committed
in-tree) on purpose: the upstream is published only on the KDE Store / OpenDesktop
with **no versioned releases**, so pinning to an immutable ref is impossible. Vendoring
guarantees the macOS look survives even if the upstream listing disappears or changes.

## Upstream

- **Project:** "Transform KDE Plasma 6 Look Like macOS" (plasma6macos)
- **Author:** Lsteam
- **Source:** https://www.opendesktop.org/p/2304796/ (mirror: https://store.kde.org/p/2200488/)
- **Vendored on:** 2026-06-29

## What is vendored here (desktop + login scope only)

| File | Contents | Installed to |
|------|----------|--------------|
| `plasma6macos-plasmoids.zip` | Custom plasmoids (Tahoe Launcher, KdeControlStation, kMenu, weather, title-bar) | `~/.local/share/plasma/plasmoids/` |
| `plasma6macos-plasma-theme.zip` | MacSequoia desktop theme, Aurorae deco, color-schemes, look-and-feel, wallpapers | `~/.local/share/plasma/`, `~/.local/share/aurorae/`, `~/.local/share/color-schemes/` |
| `plasma6macos-kwin-effect.zip` | KWin kinetic effects + scripts + blur wallpaper plugin | `~/.local/share/kwin/`, `~/.local/share/plasma/wallpapers/` |
| `plasma6macos-sddm.zip` | Login theming for both Plasma Login Manager (`plasmalogin.conf`) and SDDM (`tahoe-sddm`) | `/var/lib/plasmalogin/`, `/usr/share/sddm/themes/` |

The panel layout (`../../configs/kde/plasma6macos/plasma-org.kde.plasma.desktop-appletsrc`)
is the pack's **KDE neon** variant — closest to upstream Plasma, since the pack ships no
Fedora variant. One change was applied: the apps-grid plasmoid `dev.xarbit.appgrid`
(not bundled in the pack) was swapped for `TahoeLauncher` (which is bundled).

The MacSequoia theme is by vinceliuice (same author as WhiteSur), bundled inside the pack.

## NOT vendored (out of scope)

Icons, GTK theme, Kvantum, fonts, cursors, plymouth, cava, fastfetch, zsh/starship —
these are either provided by the existing WhiteSur modules or intentionally left out.
Each upstream plasmoid retains its own license where bundled (see individual `LICENSE`
files inside the archives).
