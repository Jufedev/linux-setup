# linux-setup — Escritorio Linux con look macOS

Setup automatizado para dejar **Fedora 42 + KDE** o **Arch + GNOME** con estética macOS completa: tema WhiteSur, fuentes Cascadia Code + emojis Apple, terminal, prompt y apps equivalentes. Un solo comando por distro.

```bash
git clone https://github.com/Jufedev/linux-setup.git ~/linux-setup
cd ~/linux-setup
bash setup.sh --all      # detecta tu distro y corre el setup que corresponde
```

---

## Stack

`setup.sh` detecta la distro y delega. Las dos rutas buscan el **mismo resultado visual** con las herramientas nativas de cada SO:

| Componente | Arch | Fedora |
|---|---|---|
| Paquetes | pacman + AUR (yay) | dnf + RPM Fusion + Flatpak |
| Escritorio | GNOME | KDE Plasma 6 |
| Login manager | GDM | SDDM (stock) |
| Terminal | Kitty | Konsole |
| Lanzador (Spotlight) | Ulauncher | KRunner (nativo) |
| Dock | Dash-to-Dock | Panel flotante nativo |
| Tema macOS | WhiteSur (GTK + Shell) | WhiteSur (Plasma + Kvantum + Aurorae) |
| Fuentes | Cascadia Code + Apple emoji + Inter | *(igual)* |
| Kernel / performance | CachyOS (BORE) *opcional* | stock |
| Instalación base | scripteada (`install.sh`) | manual (instalador gráfico) |

## Estructura

```
linux-setup/
├── setup.sh                # Dispatcher: detecta la distro y delega
├── shared/                 # Idéntico en ambas distros
│   ├── ssh-github.sh       # Llave SSH para push a GitHub (sin tokens)
│   ├── starship/           # Prompt de terminal
│   └── fontconfig/         # Fallback de emojis a color
├── fedora/                 # Fedora 42 + KDE Plasma 6
│   ├── scripts/postinstall.sh
│   └── configs/kde/        # Layout de panel + perfil de Konsole
└── arch/                   # Arch + GNOME
    ├── scripts/            # install.sh, postinstall.sh, refresh.sh, gdm-wallpaper
    └── configs/            # kitty, ulauncher, gnome (+ extensiones custom)
```

---

## Fedora 42 + KDE — proceso

> **Pasos simples.** Vos instalás Fedora a mano; el script hace todo el look macOS.

1. **Instalá Fedora 42 KDE Spin** (USB con Rufus + instalador gráfico). Dejá Btrfs (default).
2. **Tomá un snapshot** de seguridad antes de tocar nada:
   ```bash
   sudo btrfs subvolume snapshot / /.snapshots/pre-whitesur-$(date +%F)
   ```
3. **Cloná y corré el setup:**
   ```bash
   git clone https://github.com/Jufedev/linux-setup.git ~/linux-setup
   cd ~/linux-setup
   bash fedora/scripts/postinstall.sh --all
   ```
4. **Cerrá y reabrí sesión** para ver el tema y el panel.

Si algo sale mal, reiniciá y elegí el kernel anterior en GRUB (Fedora guarda los últimos 3).

> Módulos sueltos (`--themes`, `--fonts`, `--panel`, etc.), tabla completa de flags y limitaciones conocidas en **[fedora/README.md](fedora/README.md)**.

---

## Arch Linux — proceso

### 1. Instalación base (desde el USB live)

Bootear el USB en modo **UEFI**, conectar a internet, y correr el instalador:

```bash
# WiFi (si hace falta): iwctl → station wlan0 connect "TU_SSID"
curl -LO https://raw.githubusercontent.com/Jufedev/linux-setup/main/arch/scripts/install.sh
bash install.sh
```

El script te pide los datos (disco, usuario, timezone), particiona en GPT, instala la base, detecta el microcode de tu CPU y configura GRUB. Al terminar:

```bash
umount -R /mnt && reboot
```

> La contraseña temporal es tu nombre de usuario; te la cambia en el primer login.

### 2. Post-instalación (primer boot)

```bash
git clone https://github.com/Jufedev/linux-setup.git ~/linux-setup
cd ~/linux-setup
bash arch/scripts/postinstall.sh --all
```

Instala en orden: CachyOS → hardware → GNOME → tema → extensiones → fuentes → terminal → Ulauncher → apps → wallpapers → ajustes. **Resiliente:** si un paquete falla, lo reintenta solo, lo registra y sigue; al final te muestra un resumen. Log en `~/.local/state/arch-macos-setup.log`.

Sin argumentos abre un **menú interactivo**, o usá flags directos:

| Flag | Qué instala |
|------|-------------|
| `--all` | Todo en orden (recomendado para instalación limpia) |
| `--gnome` | GNOME mínimo + GDM |
| `--theme` | Tema WhiteSur (GTK + iconos + cursores) |
| `--extensions` | Extensiones GNOME + custom |
| `--fonts` | Cascadia Code + Apple emoji + Inter + fuentes Windows libres |
| `--terminal` | Kitty + Zsh + Starship |
| `--spotlight` | Ulauncher + tema macOS |
| `--apps` | Flameshot, Chrome, Edge, ufw, Podman + Distrobox |
| `--tweaks` | Aplica la config visual de GNOME (correr último) |
| `--wallpapers` | Wallpapers dinámicos por hora *(ya en `--all`)* |
| `--gdm` | Login estilo macOS *(ver Extras)* |
| `--cachyos` | Repos + kernel optimizados *(ya en `--all`)* |
| `--hardware` | Microcode + drivers de GPU *(ya en `--all`)* |

### Extras de Arch (opcionales)

- **Login macOS (GDM)** — `bash arch/scripts/postinstall.sh --gdm`. Aplica WhiteSur al login con wallpaper por hora. Va aparte porque requiere sudo + reiniciar GDM.
- **Performance (CachyOS)** — ya viene en `--all`: agrega repos compilados para tu CPU (uplift real ~5–20%) + kernel BORE/EEVDF. Reiniciá y elegí `linux-cachyos` en GRUB.
- **Dev con Distrobox** — Podman + Distrobox se instalan con `--apps`. Tu Arch queda limpio como capa visual y todo el trabajo vive en contenedores aislados que comparten tu `$HOME`:
  ```bash
  distrobox create --name dev --image archlinux:latest
  distrobox enter dev
  ```
  Para un stack reproducible, definí un `Containerfile` (`FROM archlinux:latest` + tus paquetes), `podman build -t dev-env .` y creá contenedores desde esa imagen. Exportar al host: `distrobox-export --bin <ruta>` / `--app <nombre>`.
- **SSH para GitHub sin tokens** — `bash shared/ssh-github.sh` genera una llave `ed25519` con passphrase, la agrega a `~/.ssh/config` e imprime la pública + passphrase una sola vez (guardalas en tu gestor). Dentro de Distrobox, levantá un `ssh-agent` por sesión: `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/github_ed25519`.
- **Monitor sin EDID** (resolución cae a `640x480`) — algunos monitores viejos o por adaptador no entregan EDID. Forzá el modo por parámetro de kernel en GRUB (`GRUB_CMDLINE_LINUX_DEFAULT="… video=DP-1:1440x900@60"`, luego `sudo grub-mkconfig -o /boot/grub/grub.cfg`). No va en los scripts porque el conector y la resolución cambian por máquina.

---

## Extensiones y personalizaciones (Arch + Fedora)

### Arch — extensiones GNOME

| Extensión | Función |
|-----------|---------|
| Dash to Dock | Dock estilo macOS siempre visible |
| Blur My Shell | Blur en dock y panel |
| AppIndicator | Iconos en bandeja del sistema |
| Vitals | Monitor de recursos en la barra (≈ iStatMenus) |
| Clipboard Indicator | Historial del portapapeles |
| HideTopBar · Just Perfection · User Themes | Ajustes finos de la interfaz |
| **calendar-tweaks** *(custom)* | Colapsa el message list del calendario |
| **dock-magnify** *(custom)* | Fish-eye en el dock al pasar el cursor |
| **panel-tweaks** *(custom)* | Reorganiza el panel superior (ícono Arch, Vitals+clipboard, fecha) |

Las custom están en el repo (`arch/configs/gnome/`) y se instalan solas con `--extensions`.

### Fedora — KDE Plasma

KDE no usa "extensiones": el look se arma con un **layout de panel** (`fedora/configs/kde/panel-layout.js`) que crea:

- **Barra superior** con Global Menu (el menú de la app activa, estilo macOS)
- **Dock inferior flotante** (Icons-Only Task Manager)
- **Decoraciones Aurorae** con botones a la izquierda (cerrar/minimizar/maximizar)

---

## Qué se instala (y qué NO)

### Arch — GNOME mínimo

En vez del metapaquete `gnome` (~40 apps), solo lo esencial.

**Sí:** gnome-shell, gdm, control-center, tweaks, nautilus, file-roller, evince, eog, calculator, calendar, disk-utility, system-monitor, gvfs, bluez *(servicio `bluetooth` activado)*.

**NO:** gnome-terminal (usamos Kitty), Maps, Weather, Music, Photos, Contacts, Cheese, Totem, Epiphany, Boxes, Characters, Logs, Tour, Console, ni juegos.

### Fedora — KDE Spin

**Sí:** RPM Fusion + Flathub, fuentes (Cascadia/Apple emoji/Inter/Windows libres), stack WhiteSur completo (Plasma + Kvantum + Aurorae + GTK + iconos + cursores + wallpapers), flameshot, podman, distrobox, Chrome (Flatpak), firewalld.

**NO:** tema de SDDM (deprecado en Fedora 44+), zoom parabólico del dock *(widget sin mantener en Plasma 6)*. KDE ya trae Konsole, Dolphin, KRunner, etc. de fábrica.

---

## Equivalencias macOS → Arch → Fedora

| macOS | Arch (GNOME) | Fedora (KDE) |
|---|---|---|
| Finder | Nautilus | Dolphin |
| iTerm2 | Kitty | Konsole |
| Spotlight | Ulauncher | KRunner *(nativo)* |
| Screenshot | Flameshot | Flameshot |
| Preview | Evince + Eye of GNOME | Okular + Gwenview |
| Archive Utility | File Roller | Ark |
| Disk Utility | GNOME Disks | KDE Partition Manager |
| Activity Monitor | System Monitor | System Monitor (Plasma) |
| Calculator | GNOME Calculator | KCalc |
| Calendar | GNOME Calendar | KOrganizer |
| iStatMenus | Vitals *(extensión)* | System Monitor widgets |
| Safari / Chrome | Google Chrome *(AUR)* | Chrome *(Flatpak)* |
| Edge | microsoft-edge-stable-bin *(AUR)* | Edge *(Flatpak, manual)* |
| Docker Desktop | Podman + Distrobox | Podman + Distrobox |
