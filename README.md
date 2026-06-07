# linux-setup — Setup estilo macOS

Automatiza la post-instalación de Arch Linux y (próximamente) Fedora con un look macOS completo: tema WhiteSur, fuentes Inter + JetBrains Mono, Kitty, Zsh + Starship, extensiones custom, wallpapers dinámicos y optimizaciones de performance via CachyOS.

## Stack

**Arch Linux + GNOME (mínimo)** · WhiteSur theme · Kitty + Zsh + Starship · Wallpapers dinámicos · CachyOS (kernel BORE + repos optimizados)

**Fedora 42 + KDE Plasma 6** — setup macOS con WhiteSur · Inter/JetBrains Mono · Konsole · KRunner · panel nativo flotante *(ver [fedora/README.md](fedora/README.md))*

## Estructura

```
linux-setup/
├── setup.sh                        # Dispatcher: detecta la distro y delega
├── shared/
│   ├── ssh-github.sh               # Genera llave SSH para push a GitHub (sin tokens)
│   └── starship/starship.toml      # Prompt minimalista compartido (Arch + Fedora)
├── arch/
│   ├── scripts/
│   │   ├── install.sh              # Instalación base (UEFI/GPT)
│   │   ├── postinstall.sh          # Setup visual macOS + apps + performance
│   │   ├── refresh.sh              # Refresca configs sin reinstalar
│   │   └── gdm-wallpaper-update.sh # Wallpaper dinámico del GDM por hora
│   └── configs/
│       ├── kitty/kitty.conf        # Terminal con Catppuccin Mocha
│       ├── ulauncher/macos-tahoe/  # Tema custom Ulauncher (Spotlight)
│       └── gnome/
│           ├── gnome-macos.dconf   # Configuración GNOME completa
│           ├── calendar-tweaks/    # Extensión custom: colapsa mensaje list del calendario
│           ├── dock-magnify/       # Extensión custom: fish-eye en el dock
│           ├── icons/              # Íconos custom (app grid 9 puntos)
│           └── panel-tweaks/       # Extensión custom: reorganiza el panel superior
├── fedora/
│   ├── scripts/postinstall.sh      # Setup macOS para Fedora 42 + KDE Plasma 6
│   └── configs/kde/                # Layouts de panel y perfil de Konsole
└── README.md
```

## Inicio rápido

El dispatcher `setup.sh` detecta tu distro automáticamente:

```bash
git clone https://github.com/Jufedev/linux-setup.git ~/linux-setup
cd ~/linux-setup
bash setup.sh --all
```

O ejecutá directamente el script de tu distro:

```bash
# Arch / CachyOS
bash arch/scripts/postinstall.sh --all

# Fedora 42 + KDE (Slice 2, próximamente)
bash fedora/scripts/postinstall.sh --all
```

---

## Arch Linux — Instalación completa

### Requisitos

- USB live de Arch Linux (bootear en modo **UEFI**, no Legacy)
- Conexión a internet (WiFi o Ethernet)
- Disco destino identificado (`lsblk` para verificar)

---

### Paso 1 — Instalación base (desde el USB live)

1. Bootear el USB en modo **UEFI** desde el BIOS
2. Conectar a internet:

```bash
# WiFi
iwctl
station wlan0 connect "TU_SSID"

# Ethernet: debería conectar automáticamente
```

3. Descargar y ejecutar:

```bash
curl -LO https://raw.githubusercontent.com/Jufedev/linux-setup/main/arch/scripts/install.sh
bash install.sh
```

El script se encarga de todo automáticamente:
- Verifica internet, sincroniza el reloj (NTP) y actualiza el keyring
- Te pide los datos de forma interactiva (disco, hostname, usuario, timezone)
- Muestra los discos disponibles y un resumen antes de confirmar
- Particiona (GPT), formatea, instala el sistema base y configura GRUB
- **Detecta tu CPU** e instala el microcode correcto (`amd-ucode`/`intel-ucode`) — esencial en baremetal, GRUB lo carga en el boot
- Instala `mesa` + `linux-headers` para tener gráficos y soporte de módulos desde el primer arranque

4. Al terminar:

```bash
umount -R /mnt
reboot
```

> La contraseña temporal es tu nombre de usuario. El sistema te pedirá cambiarla en el primer login.

---

### Paso 2 — Post-instalación (después del primer boot)

Clonar el repo (si no lo tenés) y ejecutar:

```bash
git clone https://github.com/Jufedev/linux-setup.git ~/linux-setup
cd ~/linux-setup
bash arch/scripts/postinstall.sh --all
```

Esto instala todo de una vez, **en este orden**: CachyOS (repos + kernel) → hardware (microcode + drivers de GPU) → GNOME → tema → extensiones → fuentes → terminal → Ulauncher → apps → wallpapers → ajustes visuales.

CachyOS va primero a propósito: así GNOME, mesa y el resto se bajan ya compilados para tu CPU desde los repos optimizados.

> **Resiliencia:** si un paquete falla, el setup ya **no se aborta** — reintenta ese paquete solo, lo registra y sigue con el resto. Al final te muestra un resumen de qué falló. El log queda en `~/.local/state/arch-macos-setup.log` (persiste entre reinicios).

Para elegir módulos individuales, ejecutar sin argumentos para el menú interactivo:

```bash
bash arch/scripts/postinstall.sh
```

O usar flags directamente:

| Flag | Qué instala |
|------|-------------|
| `--all` | Todo en orden (recomendado para instalación limpia) |
| `--gnome` | GNOME mínimo + GDM |
| `--theme` | Tema WhiteSur (GTK + iconos + cursores + libadwaita) |
| `--extensions` | Extensiones GNOME + extensiones custom (calendar-tweaks, dock-magnify, panel-tweaks) |
| `--fonts` | Inter + JetBrainsMono Nerd Font + Noto Color Emoji |
| `--terminal` | Kitty + Zsh + Starship + plugins |
| `--spotlight` | Ulauncher + tema macOS Tahoe Dark |
| `--apps` | Flameshot, Chrome, Edge, ufw, Podman + Distrobox |
| `--tweaks` | Aplica toda la configuración visual desde `gnome-macos.dconf` |
| `--wallpapers` | Wallpapers dinámicos que cambian según la hora (incluido en `--all`) |
| `--gdm` | Login GDM estilo macOS — solo el ⚙ de apagado visible *(ver Paso 3)* |
| `--cachyos` | Repos optimizados + kernel BORE/EEVDF — **ya incluido en `--all`** *(ver Paso 4)* |
| `--hardware` | Microcode del CPU + drivers de GPU auto-detectados — **ya incluido en `--all`** |

> `--tweaks` aplica la configuración de GNOME (tema, fuentes, extensiones, touchpad, layout). Ejecutarlo siempre como último paso, o después de instalar módulos individuales.
>
> `--gdm` requiere sudo y reiniciar GDM. Ejecutarlo por separado después del `--all`.

---

### Paso 3 — Login GDM estilo macOS (opcional)

Aplica el tema WhiteSur al login screen con una configuración minimalista: solo el nombre de usuario y el campo de contraseña sobre el wallpaper dinámico WhiteSur (Big Sur), que cambia según la hora.

```bash
bash arch/scripts/postinstall.sh --gdm
```

**Qué hace internamente:**
1. Copia wallpapers WhiteSur a `/usr/share/backgrounds/` (si no están)
2. Genera versiones con blur de los wallpapers via ImageMagick (efecto difuminado estilo macOS)
3. Clona WhiteSur-gtk-theme y aplica el tema a GDM
4. Instala un servicio systemd que actualiza el wallpaper según la hora (light 7AM–7PM, dark el resto)
5. Parchea el CSS del gresource: oculta panel superior, logo Arch, avatar, botones de accesibilidad/sesión
6. Parchea el tema WhiteSur del lock screen para que sea consistente con el login

```bash
# Para aplicar los cambios sin reiniciar
sudo systemctl restart gdm
```

> Este módulo **no está incluido en `--all`** porque requiere sudo y reiniciar GDM. Ejecutarlo una vez después del setup principal.

---

### Paso 4 — Performance con CachyOS (incluido en `--all`)

CachyOS ahora es el **primer módulo** de `--all`: se configura antes que nada para que GNOME, mesa y el resto de los paquetes se instalen ya compilados con instrucciones optimizadas para tu CPU. Agrega los repos a tu Arch base sin reemplazarla, más un kernel con mejor responsividad de desktop.

Para correrlo de forma aislada (por ejemplo, en un sistema ya instalado):

```bash
bash arch/scripts/postinstall.sh --cachyos
```

**Qué hace internamente:**
1. Descarga el script oficial de CachyOS y auto-detecta la ISA de tu CPU (x86-64-v3 o x86-64-v4)
2. Agrega los repos de CachyOS a `/etc/pacman.conf` e importa las GPG keys
3. Actualiza todos los paquetes del sistema a las versiones optimizadas (`pacman -Syu`)
4. Instala el kernel `linux-cachyos` con scheduler BORE/EEVDF
5. Regenera la configuración de GRUB

**Por qué vale la pena:**
- Los paquetes compilados con x86-64-v3 (AVX2/FMA) dan un uplift real de 5–20% dependiendo del workload
- El scheduler BORE/EEVDF mejora la responsividad de desktop — se nota día a día
- Tu CPU Ryzen 7 5700G (Zen 3) soporta x86-64-v3 de forma nativa

> Reiniciá después de este paso para bootear con el nuevo kernel. En GRUB vas a ver tanto `linux` (Arch stock) como `linux-cachyos` como opciones.

---

### Paso 5 — Entornos de desarrollo con Distrobox (opcional)

Distrobox crea contenedores que se sienten nativos (acceden a tu display, red, home, clipboard) pero están completamente aislados del sistema base. Tu Arch con GNOME + WhiteSur queda limpio como capa visual, todo el trabajo pesado vive dentro de contenedores.

```
┌─────────────────────────────────────────────────┐
│  Arch Linux (host)                              │
│  Solo GNOME + WhiteSur + Kitty + Ulauncher      │
│  Nada de herramientas de desarrollo             │
│                                                 │
│  ┌──────────────┐  ┌──────────────────────────┐ │
│  │ dev          │  │ dev-experimental         │ │
│  │              │  │                          │ │
│  │ Go, Python   │  │ Mismo stack pero para    │ │
│  │ Terraform    │  │ probar cosas riesgosas   │ │
│  │ Node, Bun    │  │                          │ │
│  │ AWS CLI      │  │ Si explota, lo borras    │ │
│  │ Claude Code  │  │ y creas otro             │ │
│  └──────────────┘  └──────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

> Podman y Distrobox se instalan automáticamente con `--apps`. Este paso explica cómo usarlos.

### Uso básico

```bash
# Crear un contenedor basado en Arch
distrobox create --name dev --image archlinux:latest

# Entrar
distrobox enter dev

# Adentro instalas lo que quieras sin miedo
sudo pacman -S go python terraform nodejs rust aws-cli-v2
```

### Destruir y recrear

Todo lo que instales dentro del contenedor muere con él:

```bash
distrobox stop dev
distrobox rm dev
distrobox create --name dev --image archlinux:latest
```

### Imagen base personalizada (concepto AMI local)

En vez de instalar manualmente cada vez, definís una imagen con todo tu stack. Crear un `Containerfile`:

```dockerfile
FROM archlinux:latest

RUN pacman -Syu --noconfirm

RUN pacman -S --noconfirm \
    go python python-pip nodejs npm rust \
    terraform aws-cli-v2 git vim

# Bun
RUN curl -fsSL https://bun.sh/install | bash

# Claude Code
RUN npm install -g @anthropic-ai/claude-code
```

Construir y crear contenedores a partir de la imagen:

```bash
# Construir
podman build -t dev-env .

# Contenedor estable para trabajo diario
distrobox create --name dev --image localhost/dev-env

# Contenedor experimental para probar cosas
distrobox create --name dev-experimental --image localhost/dev-env
```

### Integración con el host

| Acción | Comando |
|---|---|
| Exportar binario al host | `distrobox-export --bin /usr/bin/go --export-path ~/.local/bin` |
| Exportar app al menú GNOME | `distrobox-export --app code` |
| Home separado por contenedor | `distrobox create --name dev --image localhost/dev-env --home ~/distrobox-homes/dev` |

Por defecto Distrobox comparte tu `$HOME` con el contenedor — tus archivos, configs de git, SSH keys, todo disponible sin copiar nada.

### SSH con passphrase dentro de los contenedores

La llave generada en el [Paso 6](#paso-6--ssh-para-github-sin-tokens) tiene passphrase. El archivo (`~/.ssh/github_ed25519`) se comparte automáticamente vía `$HOME`, pero el `ssh-agent` del host **no** entra al contenedor. Para no tipear la passphrase en cada `git push`, levantá un agente dentro del contenedor y cargá la llave una vez por sesión:

```bash
distrobox enter dev

# Una sola vez por sesión del contenedor:
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/github_ed25519   # te pide la passphrase (la que guardaste en tu gestor)
```

A partir de ahí, todos los `git push` de esa sesión usan el agente sin volver a pedirla. Si querés que se levante solo, agregá esas dos líneas al `~/.bashrc`/`~/.zshrc` de tu imagen base (`Containerfile`).

### Actualizar la imagen base

1. Editar el `Containerfile`
2. Reconstruir: `podman build -t dev-env .`
3. Recrear contenedores: `distrobox stop dev && distrobox rm dev && distrobox create --name dev --image localhost/dev-env`

### Referencia rápida

| Acción | Comando |
|---|---|
| Crear contenedor | `distrobox create --name dev --image archlinux:latest` |
| Entrar | `distrobox enter dev` |
| Salir | `exit` |
| Listar | `distrobox list` |
| Parar | `distrobox stop dev` |
| Eliminar | `distrobox rm dev` |
| Construir imagen | `podman build -t dev-env .` |
| Crear desde imagen | `distrobox create --name dev --image localhost/dev-env` |

---

### Paso 6 — SSH para GitHub (sin tokens)

Autenticá `git push` con una llave SSH `ed25519` en vez de andar manejando tokens. Como Distrobox comparte tu `$HOME`, la llave en `~/.ssh` queda disponible dentro de **todos** tus contenedores sin copiar nada.

```bash
bash shared/ssh-github.sh
```

Qué hace:
1. Genera `~/.ssh/github_ed25519` con una **passphrase aleatoria robusta** (no sobreescribe si ya existe)
2. Agrega un bloque `Host github.com` a `~/.ssh/config` apuntando a esa llave
3. Imprime en consola la **clave pública** y la **passphrase** para que las guardes en tu gestor de contraseñas
4. Te abre el flujo para pegar la pública en GitHub → `https://github.com/settings/ssh/new`
5. Ofrece cambiar el `origin` de este repo de HTTPS a SSH y verifica la conexión

Opciones:

| Flag | Efecto |
|------|--------|
| `--email <correo>` | Comentario de la llave (default: `usuario@hostname`) |
| `--no-passphrase` | Genera la llave **sin** passphrase (frictionless, menos seguro) |
| `--switch-remote` / `--no-switch-remote` | Cambia (o no) el remote a SSH sin preguntar |

> Por defecto la llave lleva una passphrase aleatoria que el script genera y muestra **una sola vez** — guardala en tu gestor antes de cerrar la terminal. Gracias a `AddKeysToAgent yes` en `~/.ssh/config`, el primer `git push` te la pide una vez y el `ssh-agent` la recuerda. Para usarla dentro de Distrobox, ver la nota de ssh-agent en el [Paso 5](#paso-5--entornos-de-desarrollo-con-distrobox-opcional).

---

### Paso 7 — Ajustes manuales

1. **Seleccionar wallpaper dinámico** → Configuración → Fondo → elegir un wallpaper WhiteSur (cambia solo por hora)
2. **GDM** → correr `bash arch/scripts/postinstall.sh --gdm` (requiere sudo)

### Monitor sin EDID (resoluciones faltantes)

Algunos monitores viejos o conectados por adaptador (p. ej. DP→VGA/DVI) **no entregan EDID**,
así que el kernel no conoce sus modos y cae a `640x480`. GNOME entonces no ofrece la resolución
nativa del panel.

Diagnóstico — un EDID de `0 bytes` confirma el caso:

```bash
for c in /sys/class/drm/card*-*/; do
  printf '%s: %s bytes\n' "$(basename "$c")" "$(wc -c < "$c/edid")"
done
```

Solución — forzar el modo por parámetro de kernel en GRUB. Sintaxis: `video=<CONECTOR>:<ANCHO>x<ALTO>@<HZ>`
(el nombre del conector sale del comando de arriba, p. ej. `DP-1`, `HDMI-A-1`):

```bash
# Editar la línea GRUB_CMDLINE_LINUX_DEFAULT en /etc/default/grub y agregar el parámetro.
# Ejemplo real (BenQ T71W por DP-1, panel nativo 1440x900@60):
#   GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet video=DP-1:1440x900@60"
sudo grub-mkconfig -o /boot/grub/grub.cfg
# Reiniciar. Al volver, GNOME ya ofrece la resolución en Configuración → Pantallas.
```

> Es específico de tu hardware, por eso NO va en los scripts: el conector y la resolución
> cambian por máquina. Si el modo no levanta, probá agregar `e` para forzar el encendido
> del conector: `video=DP-1:1440x900@60e`.

---

## Fedora 42 + KDE Plasma 6 — macOS setup (próximamente)

Fedora + KDE Plasma 6 macOS setup — coming in `fedora/` (see [fedora/README.md](fedora/README.md)).

> T1.8 (manual): rename the GitHub repository from `archlinux-setup` to `linux-setup` via
> GitHub Settings → General → Repository Name. GitHub auto-redirects the old URL — all existing
> clones and remotes keep working.

---

## Qué se instala (y qué NO) — Arch

### GNOME mínimo (en vez del metapaquete `gnome` con ~40 apps)

**Sí se instala:**
gnome-shell, gdm, gnome-control-center, gnome-tweaks, gnome-shell-extensions,
gnome-keyring, gnome-menus, nautilus, xdg-user-dirs, xdg-desktop-portal-gnome,
file-roller, evince, eog, gnome-calculator, gnome-calendar, gnome-disk-utility,
gnome-system-monitor, gvfs, gvfs-mtp, bluez, bluez-utils (servicio `bluetooth` habilitado)

**NO se instala:**
gnome-terminal (usamos Kitty), GNOME Maps, Weather, Music, Photos, Contacts,
Cheese, Totem, Epiphany, GNOME Boxes, Connections, Characters, Logs, Tour,
Console, ni ningún juego

### Extensiones GNOME

| Extensión | Función |
|-----------|---------|
| AppIndicator | Soporte para iconos en bandeja del sistema |
| Blur My Shell | Blur en el dock y panel |
| **calendar-tweaks** *(custom)* | **Colapsa el message list del calendario para un panel más limpio** |
| Clipboard Indicator | Historial del portapapeles |
| Dash to Dock | Dock estilo macOS siempre visible |
| **dock-magnify** *(custom)* | **Fish-eye en el dock al pasar el cursor** |
| HideTopBar | Oculta la barra superior automáticamente |
| Just Perfection | Ajustes finos de la interfaz |
| **panel-tweaks** *(custom)* | **Reorganiza el panel: quick settings izquierda con ícono Arch, Vitals+clipboard centro, fecha derecha** |
| User Themes | Temas de shell custom |
| Vitals | Monitor de recursos en la barra (equivalente a iStatMenus) |

Las extensiones custom están incluidas en el repo (`arch/configs/gnome/`) y se instalan automáticamente con `--extensions`. No requieren ningún paso extra.

### Equivalencias macOS → Linux (Arch)

| macOS | Linux | Paquete |
|---|---|---|
| Finder | Nautilus | `nautilus` |
| iTerm2 | Kitty | `kitty` |
| Spotlight | Ulauncher | `ulauncher` |
| Screenshot | Flameshot | `flameshot` |
| Preview | Evince + Eye of GNOME | `evince` `eog` |
| Archive Utility | File Roller | `file-roller` |
| Disk Utility | GNOME Disks | `gnome-disk-utility` |
| Activity Monitor | System Monitor | `gnome-system-monitor` |
| Calculator | GNOME Calculator | `gnome-calculator` |
| Calendar | GNOME Calendar | `gnome-calendar` |
| iStatMenus | Vitals | `gnome-shell-extension-vitals` |
| Safari / Chrome | Google Chrome | `google-chrome` (AUR) |
| — | Microsoft Edge | `microsoft-edge-stable-bin` (AUR) |
| — | ufw (firewall) | `ufw` |
| Docker Desktop | Podman + Distrobox | `podman` `distrobox` |

### Paquetes opcionales (descomenta en el script)

```
gnome-font-viewer    — visor de fuentes
gnome-logs           — visor de logs del sistema
gnome-characters     — mapa de caracteres / emojis
baobab               — analizador de uso de disco
gnome-clocks         — reloj mundial / alarmas
gnome-weather        — clima
gnome-text-editor    — editor de texto simple
seahorse             — gestor de contraseñas/llaves
simple-scan          — escaneo de documentos
```
