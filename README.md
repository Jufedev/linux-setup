# Arch Linux — Setup estilo macOS (mínimo)

Instalación automatizada de Arch Linux con GNOME mínimo, sin bloatware, configurado para verse como macOS. Incluye optimizaciones de performance opcionales via CachyOS.

## Stack

**Arch Linux + GNOME (mínimo)** · WhiteSur theme · Kitty + Zsh + Starship · Wallpapers dinámicos · CachyOS (opcional)

## Estructura

```
archlinux-setup/
├── scripts/
│   ├── install.sh                  # Instalación base (UEFI/GPT)
│   ├── postinstall.sh              # Setup visual macOS + apps + performance
│   ├── refresh.sh                  # Refresca configs sin reinstalar
│   └── gdm-wallpaper-update.sh    # Wallpaper dinámico del GDM por hora
├── configs/
│   ├── kitty/kitty.conf            # Terminal con Catppuccin Mocha
│   ├── starship/starship.toml      # Prompt minimalista con iconos
│   ├── ulauncher/macos-tahoe/      # Tema custom Ulauncher (Spotlight)
│   └── gnome/
│       ├── gnome-macos.dconf       # Configuración GNOME completa
│       ├── calendar-tweaks/        # Extensión custom: colapsa mensaje list del calendario
│       ├── dock-magnify/           # Extensión custom: fish-eye en el dock
│       ├── icons/                  # Íconos custom (app grid 9 puntos)
│       └── panel-tweaks/           # Extensión custom: reorganiza el panel superior
└── README.md
```

## Requisitos

- USB live de Arch Linux (bootear en modo **UEFI**, no Legacy)
- Conexión a internet (WiFi o Ethernet)
- Disco destino identificado (`lsblk` para verificar)

---

## Paso 1 — Instalación base (desde el USB live)

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
curl -LO https://raw.githubusercontent.com/Jufedev/archlinux-setup/main/scripts/install.sh
bash install.sh
```

El script se encarga de todo automáticamente:
- Verifica internet, sincroniza el reloj (NTP) y actualiza el keyring
- Te pide los datos de forma interactiva (disco, hostname, usuario, timezone)
- Muestra los discos disponibles y un resumen antes de confirmar
- Particiona (GPT), formatea, instala el sistema base y configura GRUB

4. Al terminar:

```bash
umount -R /mnt
reboot
```

> La contraseña temporal es tu nombre de usuario. El sistema te pedirá cambiarla en el primer login.

---

## Paso 2 — Post-instalación (después del primer boot)

Clonar el repo (si no lo tenés) y ejecutar:

```bash
git clone https://github.com/Jufedev/archlinux-setup.git ~/archlinux-setup
cd ~/archlinux-setup
bash scripts/postinstall.sh --all
```

Esto instala todo de una vez: GNOME, tema, extensiones, fuentes, terminal, Ulauncher, apps y configuración visual.

Para elegir módulos individuales, ejecutar sin argumentos para el menú interactivo:

```bash
bash scripts/postinstall.sh
```

O usar flags directamente:

| Flag | Qué instala |
|------|-------------|
| `--all` | Todo en orden (recomendado para instalación limpia) |
| `--gnome` | GNOME mínimo + GDM |
| `--theme` | Tema WhiteSur (GTK + iconos + cursores + libadwaita) |
| `--extensions` | Extensiones GNOME + extensiones custom (calendar-tweaks, dock-magnify, panel-tweaks) |
| `--fonts` | Inter + JetBrainsMono Nerd Font |
| `--terminal` | Kitty + Zsh + Starship + plugins |
| `--spotlight` | Ulauncher + tema macOS Tahoe Dark |
| `--apps` | Flameshot, Chrome, Edge, ufw, Podman + Distrobox |
| `--tweaks` | Aplica toda la configuración visual desde `gnome-macos.dconf` |
| `--wallpapers` | Wallpapers dinámicos que cambian según la hora (incluido en `--all`) |
| `--gdm` | Login GDM estilo macOS — solo el ⚙ de apagado visible *(ver Paso 3)* |
| `--cachyos` | Repos optimizados + kernel BORE/EEVDF *(ver Paso 4)* |

> `--tweaks` aplica la configuración de GNOME (tema, fuentes, extensiones, touchpad, layout). Ejecutarlo siempre como último paso, o después de instalar módulos individuales.
>
> `--gdm` requiere sudo y reiniciar GDM. Ejecutarlo por separado después del `--all`.

---

## Paso 3 — Login GDM estilo macOS (opcional)

Aplica el tema WhiteSur al login screen con una configuración minimalista: solo el nombre de usuario y el campo de contraseña sobre el wallpaper dinámico Ventura (cambia según la hora).

```bash
bash scripts/postinstall.sh --gdm
```

**Qué hace internamente:**
1. Copia wallpapers Ventura a `/usr/share/backgrounds/` (si no están)
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

## Paso 4 — Performance con CachyOS (opcional)

Este paso agrega los repositorios de CachyOS a tu instalación de Arch base, sin reemplazarla. Obtenés paquetes del sistema compilados con instrucciones optimizadas para tu CPU y un kernel con mejor responsividad de desktop.

```bash
bash scripts/postinstall.sh --cachyos
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

## Paso 5 — Ajustes manuales

1. **Seleccionar wallpaper dinámico** → Configuración → Fondo → elegir un wallpaper WhiteSur (cambia solo por hora)
2. **GDM** → correr `bash scripts/postinstall.sh --gdm` (requiere sudo)

---

## Qué se instala (y qué NO)

### GNOME mínimo (en vez del metapaquete `gnome` con ~40 apps)

**Sí se instala:**
gnome-shell, gdm, gnome-control-center, gnome-tweaks, gnome-shell-extensions,
gnome-keyring, nautilus, xdg-user-dirs, xdg-desktop-portal-gnome, file-roller,
evince, eog, gnome-calculator, gnome-calendar, gnome-disk-utility,
gnome-system-monitor, gvfs, gvfs-mtp

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

Las extensiones custom están incluidas en el repo (`configs/gnome/`) y se instalan automáticamente con `--extensions`. No requieren ningún paso extra.

### Equivalencias macOS → Linux

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

