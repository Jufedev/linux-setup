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

## What is vendored here (full pack — WhiteSur was removed)

| File | Contents | Installed to |
|------|----------|--------------|
| `plasma6macos-icons.zip` | MacTahoe icon themes (light/dark) | `~/.local/share/icons/` |
| `plasma6macos-cursors.zip` | WhiteSur-cursors (referenced by the look-and-feel) | `~/.local/share/icons/` |
| `plasma6macos-gtk-theme.zip` | MacTahoe GTK3/GTK4 theme | `~/.local/share/themes/` |
| `plasma6macos-kvantum-config.zip` | MacSequoia Kvantum widget style | `~/.config/Kvantum/` |
| `plasma6macos-fonts.zip` | Pack fonts (Adwaita Sans/Mono) | `~/.local/share/fonts/` |
| `plasma6macos-plasmoids.zip` | Custom plasmoids (Tahoe Launcher, KdeControlStation, kMenu, weather, title-bar) | `~/.local/share/plasma/plasmoids/` |
| `plasma6macos-plasma-theme.zip` | MacSequoia desktop theme, Aurorae deco, color-schemes, look-and-feel, wallpapers | `~/.local/share/plasma/`, `~/.local/share/aurorae/`, `~/.local/share/color-schemes/` |
| `plasma6macos-kwin-effect.zip` | KWin kinetic effects + scripts + blur wallpaper plugin | `~/.local/share/kwin/`, `~/.local/share/plasma/wallpapers/` |
| `plasma6macos-sddm.zip` | Login theming for both Plasma Login Manager (`plasmalogin.conf`) and SDDM (`tahoe-sddm`) | `/var/lib/plasmalogin/`, `/usr/share/sddm/themes/` |

The panel layout (`../../configs/kde/plasma6macos/plasma-org.kde.plasma.desktop-appletsrc`)
is the pack's **KDE neon** variant — closest to upstream Plasma, since the pack ships no
Fedora variant. One change was applied: the apps-grid plasmoid `dev.xarbit.appgrid`
(not bundled in the pack) was swapped for `TahoeLauncher` (which is bundled).

The MacSequoia/MacTahoe themes are by vinceliuice, bundled inside the pack.

**Note on the widget style:** the look-and-feel sets `widgetStyle=Darkly`, but Darkly
is **not** shipped in the pack. The setup forces `widgetStyle=kvantum` (MacSequoia)
right after applying the look-and-feel, so widgets are styled without needing Darkly.

## NOT vendored (out of scope)

`gnome-config`, `plymouth`, `cava`, `fastfetch`, `zsh/starship` — GNOME-specific or
terminal eye-candy, intentionally left out (the repo already configures Konsole +
Starship). Each upstream plasmoid retains its own license where bundled (see individual
`LICENSE` files inside the archives).
