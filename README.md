# linux-setup — Escritorio Linux con look macOS

Setup automatizado para dejar **Fedora 44 + KDE** o **Arch + GNOME** con estética macOS completa: tema WhiteSur, fuentes Cascadia Code + emojis Apple, terminal, prompt y apps equivalentes. Un solo comando por distro.

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
├── fedora/                 # Fedora 44 + KDE Plasma 6
│   ├── scripts/postinstall.sh
│   └── configs/kde/        # Layout de panel + perfil de Konsole
└── arch/                   # Arch + GNOME
    ├── scripts/            # install.sh, postinstall.sh, refresh.sh, gdm-wallpaper
    └── configs/            # kitty, ulauncher, gnome (+ extensiones custom)
```

---

## Fedora 44 + KDE — proceso

> **Pasos simples.** Vos instalás Fedora a mano; el script hace todo el look macOS.

1. **Instalá Fedora 44 KDE** (USB con Rufus + instalador gráfico). Dejá Btrfs (default). *(Funciona también en 42/43.)*
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

> Módulos sueltos (`--theme`, `--fonts`, `--desktop`, etc.), tabla completa de flags y limitaciones conocidas en **[fedora/README.md](fedora/README.md)**.

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

Instala en orden: CachyOS → repos → hardware → GNOME → tema → fuentes → terminal → launcher → apps → wallpapers → escritorio → teclado. **Resiliente:** si un paquete falla, lo reintenta solo, lo registra y sigue; al final te muestra un resumen. Log en `~/.local/state/arch-macos-setup.log`.

Sin argumentos abre un **menú interactivo**, o usá flags directos:

> **Flags unificados.** Los flags son **idénticos en Arch y Fedora** y hacen lo mismo en ambas, salvo `--gnome` y `--cachyos` (exclusivos de Arch — Fedora ya trae KDE y no usa CachyOS) y `--debloat` (exclusivo de Fedora — Arch ya es mínimo por construcción).

| Flag | Qué instala |
|------|-------------|
| `--all` | Todo en orden (recomendado para instalación limpia) |
| `--repos` | Habilita `multilib` (paquetes de 32 bits, ej. `lib32-nvidia-utils`) |
| `--hardware` | Microcode + drivers de GPU; NVIDIA con módulos abiertos `nvidia-open-dkms` (Blackwell/RTX 50) |
| `--gnome` | GNOME mínimo + GDM *(Arch-only)* |
| `--theme` | Stack visual WhiteSur (GTK + iconos + cursores) |
| `--fonts` | Cascadia Code + Apple emoji + Inter + fuentes Windows libres |
| `--desktop` | Layout estilo macOS: extensiones GNOME + ajustes dconf |
| `--terminal` | Kitty + Zsh + Starship |
| `--launcher` | Ulauncher + tema macOS |
| `--apps` | Flameshot, Chrome, Edge, Podman + Distrobox, firewall *(deny incoming)* |
| `--wallpapers` | Wallpapers dinámicos por hora *(ya en `--all`)* |
| `--keyboard` | Layout `us altgr-intl` (system-wide) |
| `--login` | Login GDM estilo macOS *(ver Extras)* |
| `--cachyos` | Repos + kernel optimizados *(Arch-only, ya en `--all`)* |
| `--debloat` | Quita apps preinstaladas de la KDE Spin (juegos, PIM, Firefox, LibreOffice…) *(Fedora-only, opt-in, NO va en `--all`)* |

### Extras de Arch (opcionales)

- **Login macOS (GDM)** — `bash arch/scripts/postinstall.sh --login`. Aplica WhiteSur al login con wallpaper por hora. Va aparte porque requiere sudo + reiniciar GDM.
- **Performance (CachyOS)** — ya viene en `--all`: agrega repos compilados para tu CPU (uplift real ~5–20%) + kernel BORE/EEVDF. Reiniciá y elegí `linux-cachyos` en GRUB.
- **Monitor sin EDID** (resolución cae a `640x480`) — algunos monitores viejos o por adaptador no entregan EDID. Forzá el modo por parámetro de kernel en GRUB (`GRUB_CMDLINE_LINUX_DEFAULT="… video=DP-1:1440x900@60"`, luego `sudo grub-mkconfig -o /boot/grub/grub.cfg`). No va en los scripts porque el conector y la resolución cambian por máquina.

---

## GPU NVIDIA dedicada (Blackwell / RTX 50)

Las placas Blackwell (serie RTX 50, ej. **5060 Ti**) **requieren los módulos
abiertos** de NVIDIA; el propietario clásico ya no las soporta.

| Distro | Cómo se instala |
|---|---|
| Arch | `--hardware` → `nvidia-open-dkms` + `nvidia-utils` + headers, blacklist de nouveau, `nvidia_drm.modeset=1`, early KMS en mkinitcpio |
| Fedora | `--hardware` → `akmod-nvidia-open` + CUDA/VAAPI, blacklist de nouveau, `nvidia-drm.modeset=1` |

Reiniciá y verificá con `nvidia-smi`. Sin placa NVIDIA el módulo es no-op (Mesa ya cubre AMD/Intel).

### Antes que nada: deshabilitá la iGPU en BIOS

En una APU Ryzen (ej. 5700G) el gráfico integrado sigue activo junto a la placa.
Para un desktop de una sola GPU, deshabilitalo en BIOS.

**GIGABYTE B550M AORUS Elite AX (rev 1.3):**

1. Entrá al BIOS con `DEL`; pasá a modo Advanced con `F2`.
2. `Settings → IO Ports → Integrated Graphics` → **Disabled**.
3. `Settings → IO Ports → Initial Display Output` → **PCIe 1 Slot**.
4. Enchufá el monitor a la **placa de video**, no a la board.
5. Guardá y salí con `F10`.

> Si no aparece "Integrated Graphics", actualizá el BIOS — las versiones viejas
> no exponían el toggle del iGPU de Cezanne.

> **Probar sin la placa.** Para ejercitar el branch NVIDIA en una VM sin GPU:
> `FORCE_GPU=nvidia bash <distro>/scripts/postinstall.sh --hardware` (mismo flag en ambas).
> Valida que los paquetes resuelvan y que DKMS/akmod compile; el módulo no *carga* sin hardware real.

Detalle de Secure Boot, firma de módulos y el caveat de suspend en kernel 7.0 en
**[fedora/README.md](fedora/README.md)**.

## Core (Arch + Fedora)

Herramientas base, **iguales en las dos distros**: Distrobox se instala con `--apps` (Arch y Fedora) y el script de SSH vive en `shared/`. No dependen del escritorio.

### Entornos de desarrollo con Distrobox

Tu sistema queda limpio como capa visual; todo el trabajo pesado vive en contenedores aislados que se sienten nativos (acceden a tu display, red, `$HOME`, clipboard) pero podés romper y recrear sin tocar el host.

```bash
distrobox create --name dev --image archlinux:latest   # o fedora:latest, ubuntu, etc.
distrobox enter dev
# adentro instalás lo que quieras sin miedo
```

**Imagen reproducible (concepto AMI local).** En vez de instalar a mano cada vez, definís un `Containerfile` con tu stack y construís la imagen una sola vez:

```dockerfile
FROM archlinux:latest
RUN pacman -Syu --noconfirm && pacman -S --noconfirm \
    go python nodejs rust terraform aws-cli-v2 git vim
```

```bash
podman build -t dev-env .
distrobox create --name dev --image localhost/dev-env
```

**Integración con el host:**

| Acción | Comando |
|---|---|
| Crear · entrar · salir | `distrobox create --name dev --image <img>` · `distrobox enter dev` · `exit` |
| Listar · parar · borrar | `distrobox list` · `distrobox stop dev` · `distrobox rm dev` |
| Exportar binario al host | `distrobox-export --bin /usr/bin/go --export-path ~/.local/bin` |
| Exportar app al menú | `distrobox-export --app code` |

Por defecto comparte tu `$HOME` — git, configs y llaves SSH disponibles sin copiar nada.

### SSH para GitHub (sin tokens)

```bash
bash shared/ssh-github.sh
```

Genera una llave `ed25519` con **passphrase aleatoria**, agrega un bloque `Host github.com` a `~/.ssh/config`, e imprime la pública + la passphrase **una sola vez** (guardalas en tu gestor). Después ofrece pasar el `origin` de este repo de HTTPS a SSH.

> **Dentro de Distrobox** el `ssh-agent` del host no entra, así que levantá uno por sesión y cargá la llave una vez:
> ```bash
> eval "$(ssh-agent -s)" && ssh-add ~/.ssh/github_ed25519
> ```
> Como `$HOME` se comparte, la llave en `~/.ssh` ya queda disponible en todos tus contenedores.

| Flag | Efecto |
|------|--------|
| `--email <correo>` | Comentario de la llave (default: `usuario@hostname`) |
| `--no-passphrase` | Llave sin passphrase (menos seguro) |
| `--switch-remote` / `--no-switch-remote` | Cambia (o no) el remote a SSH sin preguntar |

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

Las custom están en el repo (`arch/configs/gnome/`) y se instalan solas con `--desktop`.

### Fedora — KDE Plasma

KDE no usa "extensiones": el look se arma con un **layout de panel** (`fedora/configs/kde/panel-layout.js`) que crea:

- **Barra superior** con Global Menu (el menú de la app activa, estilo macOS)
- **Dock inferior flotante** (Icons-Only Task Manager)
- **Decoraciones Aurorae** con botones a la izquierda (cerrar/minimizar/maximizar)
- **Reloj en 24h con fecha** (configurado en el mismo script del panel)

El módulo `--keyboard` configura el layout **English intl (AltGr dead keys)** tanto en la sesión KDE como a nivel sistema (SDDM + fallback via `localectl`).

---

## Qué se instala (y qué NO)

### Arch — GNOME mínimo

En vez del metapaquete `gnome` (~40 apps), solo lo esencial.

**Sí:** gnome-shell, gdm, control-center, tweaks, nautilus, file-roller, evince, eog, calculator, calendar, disk-utility, system-monitor, gvfs, bluez *(servicio `bluetooth` activado)*.

**NO:** gnome-terminal (usamos Kitty), Maps, Weather, Music, Photos, Contacts, Cheese, Totem, Epiphany, Boxes, Characters, Logs, Tour, Console, ni juegos.

### Fedora — KDE Spin

**Sí:** RPM Fusion + Flathub, fuentes (Cascadia/Apple emoji/Inter/Windows libres), stack WhiteSur completo (Plasma + Kvantum + Aurorae + GTK + iconos + cursores + wallpapers), flameshot, podman, distrobox, Chrome + Edge (Flatpak), firewalld.

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
| Edge | microsoft-edge-stable-bin *(AUR)* | Edge *(Flatpak)* |
| Docker Desktop | Podman + Distrobox | Podman + Distrobox |
