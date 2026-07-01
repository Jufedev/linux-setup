# linux-setup — Escritorio Linux con look macOS

Setup automatizado para dejar **Fedora 44 + KDE** o **Arch + KDE** con estética macOS completa: el pack **plasma6macos** (MacSequoia + iconos MacTahoe) sobre KDE Plasma 6, fuentes Cascadia Code + emojis Apple, terminal, prompt y apps equivalentes. El look es **el mismo en las dos distros** — el módulo que lo aplica vive en `shared/`. Un solo comando por distro.

```bash
git clone https://github.com/Jufedev/linux-setup.git ~/linux-setup
cd ~/linux-setup
bash setup.sh --all      # detecta tu distro y corre el setup que corresponde
```

---

## Stack

`setup.sh` detecta la distro y delega. Las dos rutas llegan al **mismo resultado visual** — mismo escritorio, mismo pack, mismo módulo compartido:

| Componente | Arch | Fedora |
|---|---|---|
| Paquetes | pacman + AUR (yay) | dnf + RPM Fusion + Flatpak |
| Escritorio | KDE Plasma 6 | KDE Plasma 6 |
| Login manager | SDDM (tema `tahoe-sddm`) | Plasma Login Manager (stock) |
| Terminal | Konsole | Konsole |
| Lanzador (Spotlight) | KRunner (nativo) | KRunner (nativo) |
| Dock | Panel flotante nativo | Panel flotante nativo |
| Tema macOS | plasma6macos: MacSequoia + iconos MacTahoe + Kvantum + Aurorae | *(igual — módulo compartido)* |
| Fuentes | Cascadia Code + Apple emoji + Inter | *(igual)* |
| Kernel / performance | CachyOS (BORE) *opcional* | stock |
| Instalación base | scripteada (`install.sh`) | manual (instalador gráfico) |

## Estructura

```
linux-setup/
├── setup.sh                # Dispatcher: detecta la distro y delega
├── shared/                 # Idéntico en ambas distros
│   ├── ssh-github.sh       # Llave SSH para push a GitHub (sin tokens)
│   ├── plasma6macos.sh     # Módulo del look macOS para KDE (lo usan ambas distros)
│   ├── vendor/plasma6macos/ # Pack plasma6macos vendorizado (zips + atribución)
│   ├── configs/kde/        # Layout de panel + perfil de Konsole
│   ├── starship/           # Prompt de terminal
│   └── fontconfig/         # Fallback de emojis a color
├── fedora/                 # Fedora 44 + KDE Plasma 6
│   └── scripts/postinstall.sh
└── arch/                   # Arch + KDE Plasma 6
    └── scripts/            # install.sh, postinstall.sh, refresh.sh
```

---

## Fedora 44 + KDE — proceso

> **Pasos simples.** Vos instalás Fedora a mano; el script hace todo el look macOS.

1. **Instalá Fedora 44 KDE** (USB con Rufus + instalador gráfico). Dejá Btrfs (default). *(Funciona también en 42/43.)*
2. **Tomá un snapshot** de seguridad antes de tocar nada:
   ```bash
   sudo btrfs subvolume snapshot / /.snapshots/pre-macos-$(date +%F)
   ```
3. **Cloná y corré el setup:** *(la KDE Spin no trae `git` de fábrica)*
   ```bash
   sudo dnf install -y git
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

Instala en orden: CachyOS → repos → hardware → KDE → fuentes → terminal → launcher → apps → look macOS → login → teclado. **Resiliente:** si un paquete falla, lo reintenta solo, lo registra y sigue; al final te muestra un resumen. Log en `~/.local/state/arch-macos-setup.log`.

Sin argumentos abre un **menú interactivo**, o usá flags directos:

> **Flags unificados.** Los flags son **idénticos en Arch y Fedora** y hacen lo mismo en ambas, salvo `--kde` y `--cachyos` (exclusivos de Arch — Fedora ya trae KDE en la spin y no usa CachyOS) y `--debloat` (exclusivo de Fedora — Arch ya es mínimo por construcción).

| Flag | Qué instala |
|------|-------------|
| `--all` | Todo en orden (recomendado para instalación limpia) |
| `--repos` | Habilita `multilib` (paquetes de 32 bits, ej. `lib32-nvidia-utils`) |
| `--hardware` | Microcode + drivers de GPU; NVIDIA con módulos abiertos `nvidia-open-dkms` (Blackwell/RTX 50) |
| `--kde` | KDE Plasma 6 mínimo + SDDM *(Arch-only)* |
| `--theme` / `--macos-look` | El pack **plasma6macos** completo: MacSequoia + iconos MacTahoe + Kvantum + plasmoides + layout + wallpaper |
| `--fonts` | Cascadia Code + Apple emoji + Inter + fuentes Windows libres; config de fuentes KDE |
| `--desktop` | **Fallback**: layout mínimo de paneles (barra + dock) vía Plasma Scripting API |
| `--terminal` | Konsole (perfil MacOS) + Zsh + Starship |
| `--launcher` | No-op: KRunner es nativo de KDE (Meta o Alt+Space) |
| `--apps` | Flameshot, GNOME Calendar *(calendario del dock)*, Chrome, Edge, Podman + Distrobox, firewall *(deny incoming)* |
| `--wallpapers` | Wallpaper MacSequoia del pack *(ya en `--all`)* |
| `--keyboard` | Layout `us altgr-intl` (sesión KDE + system-wide) |
| `--login` | Login SDDM estilo macOS: tema `tahoe-sddm` del pack *(aditivo y reversible)* |
| `--cachyos` | Repos + kernel optimizados *(Arch-only, ya en `--all`)* |
| `--debloat` | Quita apps preinstaladas de la KDE Spin (juegos, PIM, Firefox, LibreOffice…) *(Fedora-only, opt-in, NO va en `--all`)* |

### Extras de Arch (opcionales)

- **Login macOS (SDDM)** — `bash arch/scripts/postinstall.sh --login` (ya incluido en `--all`). Instala el tema `tahoe-sddm` del pack y lo activa con un drop-in en `/etc/sddm.conf.d/95-macos-login.conf`. Para revertir: borrá ese archivo.
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

## El look macOS (Arch + Fedora)

KDE no usa "extensiones" al estilo GNOME: el look del video se arma con el pack **plasma6macos** (vendorizado en `shared/vendor/plasma6macos/`, aplicado por el módulo compartido `shared/plasma6macos.sh` — **el mismo en las dos distros**), que aplica:

- **Barra superior** con menú  (kMenu), Global Menu, Control Center estilo iOS, clima y reloj
- **Dock inferior flotante** con **botón de apps (Tahoe Launcher)** + Icons-Only Task Manager
- **Tema MacSequoia** (Plasma + Aurorae con botones a la izquierda) + efectos KWin (blur/kinetic)
- **Login** estilo macOS (aditivo y reversible)

Detalle completo y cómo revertir: **[fedora/README.md → The macOS look](fedora/README.md#the-macos-look-plasma6macos)**. El `panel-layout.js` queda como fallback mínimo vía `--desktop`.

El módulo `--keyboard` configura el layout **English intl (AltGr dead keys)** tanto en la sesión KDE como a nivel sistema (login manager + fallback via `localectl`).

---

## Qué se instala (y qué NO)

### Arch — KDE Plasma 6 mínimo

En vez del metapaquete `plasma` (~50 componentes), solo lo esencial.

**Sí:** plasma-desktop, plasma-workspace, sddm, systemsettings, kscreen, plasma-nm, plasma-pa, powerdevil, xdg-desktop-portal-kde, kdeplasma-addons, konsole, dolphin, ark, okular, gwenview, kcalc, partitionmanager, plasma-systemmonitor, kwallet-pam, kio-extras, bluedevil + bluez *(servicio `bluetooth` activado)*.

**NO:** el metapaquete `plasma` completo, la suite PIM (Kontact/KMail/KOrganizer), Discover, Spectacle (usamos Flameshot), juegos KDE, ni apps redundantes con el stack del setup.

### Fedora — KDE Spin

**Sí:** RPM Fusion + Flathub, fuentes (Cascadia/Apple emoji/Inter/Windows libres), pack **plasma6macos** completo (MacSequoia + iconos MacTahoe + GTK + Kvantum + Aurorae + plasmoides + KWin + wallpaper + login), flameshot, podman, distrobox, Chrome + Edge (Flatpak), firewalld.

**NO:** tema de la pantalla de login (Fedora 44 reemplazó SDDM por el Plasma Login Manager; no vale la pena mantenerlo), zoom parabólico del dock *(widget sin mantener en Plasma 6)*. KDE ya trae Konsole, Dolphin, KRunner, etc. de fábrica.

---

## Equivalencias macOS → Linux (KDE)

Ambas distros usan KDE Plasma 6, así que las equivalencias son las mismas; solo
cambia de dónde vienen los navegadores (AUR en Arch, Flatpak en Fedora).

| macOS | Arch + Fedora (KDE) |
|---|---|
| Finder | Dolphin |
| iTerm2 | Konsole |
| Spotlight | KRunner *(nativo)* |
| Screenshot | Flameshot |
| Preview | Okular + Gwenview |
| Archive Utility | Ark |
| Disk Utility | KDE Partition Manager |
| Activity Monitor | System Monitor (Plasma) |
| Calculator | KCalc |
| Calendar | GNOME Calendar *(icono del dock con la fecha del día)* |
| iStatMenus | Widgets de System Monitor |
| Safari / Chrome | Google Chrome *(AUR / Flatpak)* |
| Edge | Microsoft Edge *(AUR / Flatpak)* |
| Docker Desktop | Podman + Distrobox |
