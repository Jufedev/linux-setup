#!/usr/bin/env bash
# ============================================================================
# Arch Linux — Setup estilo macOS (GNOME)
# Ejecutar como usuario normal después del primer boot
# Uso: bash postinstall.sh [--all | --repos | --hardware | --gnome | --theme | --fonts |
#          --desktop | --terminal | --launcher | --apps | --wallpapers | --keyboard | --login | --cachyos]
# Sin argumentos = menú interactivo
# ============================================================================
set -euo pipefail

# ── Colores ─────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${B}[INFO]${NC}  $1"; }
ok()    { echo -e "${G}[OK]${NC}    $1"; }
warn()  { echo -e "${Y}[WARN]${NC}  $1"; }
fail()  { echo -e "${R}[FAIL]${NC}  $1"; exit 1; }
step()  { echo -e "\n${C}━━━ $1 ━━━${NC}\n"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/../configs"
SHARED_DIR="${SCRIPT_DIR}/../../shared"

# Log persistente (sobrevive reinicios — /tmp se borra al rebootear)
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/arch-macos-setup.log"

# Tracking de fallos: un paquete o módulo que falla NO debe abortar todo el setup
FAILED_PKGS=()
FAILED_MODULES=()

# ── Pinned upstream refs (WhiteSur) ──────────────────────────────────────────
# Bump intencionalmente; clonar HEAD no es reproducible. Ver dependency audit.
readonly WHITESUR_GTK_REF="2025-07-24"
readonly WHITESUR_WALLPAPERS_REF="2023-06-11"

[[ ! -d "$CONFIGS_DIR" ]] && fail "Directorio de configs no encontrado: $CONFIGS_DIR"

# ── Sincronizar base de datos de pacman ───────────────────────────────────
info "Sincronizando base de datos de pacman..."
sudo pacman -Sy --noconfirm &>/dev/null
ok "Base de datos sincronizada"

# ── Helpers ────────────────────────────────────────────────────────────────
# Estrategia: intentar el batch (rápido, resuelve dependencias juntas). Si falla,
# reintentar paquete por paquete para que UN paquete roto no arrastre al resto.
# Los fallos se registran en FAILED_PKGS y el script CONTINÚA.
pac_install() {
    info "Instalando (pacman): $*"
    if sudo pacman -S --noconfirm --needed "$@" 2>&1 | tee -a "$LOG_FILE"; then
        return 0
    fi
    warn "Batch de pacman falló — reintentando uno por uno..."
    local pkg
    for pkg in "$@"; do
        if ! sudo pacman -S --noconfirm --needed "$pkg" 2>&1 | tee -a "$LOG_FILE"; then
            warn "Paquete falló (pacman): $pkg"
            FAILED_PKGS+=("$pkg")
        fi
    done
}

aur_install() {
    info "Instalando (AUR): $*"
    if yay -S --noconfirm --needed "$@" 2>&1 | tee -a "$LOG_FILE"; then
        return 0
    fi
    warn "Batch de AUR falló — reintentando uno por uno..."
    local pkg
    for pkg in "$@"; do
        if ! yay -S --noconfirm --needed "$pkg" 2>&1 | tee -a "$LOG_FILE"; then
            warn "Paquete falló (AUR): $pkg"
            FAILED_PKGS+=("$pkg")
        fi
    done
}

# Ejecuta un módulo sin que su fallo aborte el resto del setup.
# El 'if' suprime 'set -e' dentro del módulo y captura su estado final.
run_module() {
    local label="$1"; shift
    step "▶ $label"
    if "$@"; then
        ok "Módulo OK: $label"
    else
        warn "Módulo con errores: $label — continúo con el resto"
        FAILED_MODULES+=("$label")
    fi
}

print_summary() {
    echo ""
    echo -e "${G}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${G}║  Setup finalizado                                    ║${NC}"
    echo -e "${G}╚══════════════════════════════════════════════════════╝${NC}"

    if [[ ${#FAILED_MODULES[@]} -eq 0 && ${#FAILED_PKGS[@]} -eq 0 ]]; then
        ok "Todos los módulos y paquetes se instalaron sin errores"
    else
        [[ ${#FAILED_MODULES[@]} -gt 0 ]] && warn "Módulos con errores: ${FAILED_MODULES[*]}"
        [[ ${#FAILED_PKGS[@]} -gt 0 ]]    && warn "Paquetes que fallaron: ${FAILED_PKGS[*]}"
        echo "  Log completo: $LOG_FILE"
        echo "  Reintentá un módulo puntual con: bash postinstall.sh --<modulo>"
    fi

    echo ""
    echo -e "${G}Pasos finales:${NC}"
    echo "  • Reiniciá para bootear el kernel CachyOS (elegilo en GRUB si no es el default)"
    echo "  • Cerrá y reabrí sesión para ver el tema y las extensiones"
    echo "  • Parcheá el login estilo macOS con: bash postinstall.sh --login"
    echo ""

    # Código de salida no-cero si hubo fallos (útil para CI / scripts llamadores)
    if [[ ${#FAILED_MODULES[@]} -gt 0 || ${#FAILED_PKGS[@]} -gt 0 ]]; then
        return 1
    fi
}

ensure_yay() {
    if ! command -v yay &>/dev/null; then
        step "Instalando yay (AUR helper)"
        pac_install git base-devel go
        local tmpdir
        tmpdir=$(mktemp -d)
        git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
        (cd "$tmpdir/yay" && makepkg -si --noconfirm)
        rm -rf "$tmpdir"
        ok "yay instalado"
    else
        ok "yay ya está instalado"
    fi
}

# ============================================================================
# MÓDULOS
# ============================================================================

install_gnome() {
    step "GNOME Mínimo"

    # Shell y display manager
    pac_install \
        gnome-shell \
        gdm \
        gnome-control-center \
        gnome-tweaks \
        gnome-shell-extensions \
        gnome-keyring \
        gnome-menus

    # File manager
    pac_install nautilus

    # Utilidades mínimas
    pac_install \
        xdg-user-dirs \
        xdg-desktop-portal-gnome \
        file-roller \
        evince \
        eog \
        gnome-calculator \
        gnome-calendar \
        gnome-disk-utility \
        gnome-system-monitor \
        gvfs \
        gvfs-mtp

    # Bluetooth (demonio + bluetoothctl)
    pac_install bluez bluez-utils

    # Crear carpetas estándar (Documents, Downloads, Pictures, etc.)
    xdg-user-dirs-update

    sudo systemctl enable gdm
    sudo systemctl enable bluetooth
    ok "GNOME mínimo instalado, GDM y Bluetooth habilitados"

    # ── Remover bloat de dependencias ──
    info "Removiendo apps innecesarias (dependencias no deseadas)..."

    if pacman -Q gvfs-dnssd &>/dev/null; then
        sudo pacman -Rns --noconfirm gvfs-dnssd
    fi

    if pacman -Q avahi &>/dev/null; then
        sudo pacman -Rns --noconfirm avahi 2>/dev/null || {
            warn "avahi es dependencia requerida — ocultando apps del menú"
            mkdir -p "$HOME/.local/share/applications"
            for app in bssh bvnc avahi-discover; do
                printf '[Desktop Entry]\nNoDisplay=true\n' > "$HOME/.local/share/applications/${app}.desktop"
            done
        }
    fi

    if pacman -Q v4l-utils &>/dev/null; then
        sudo pacman -Rns --noconfirm v4l-utils 2>/dev/null || {
            warn "v4l-utils es dependencia requerida — ocultando apps del menú"
            mkdir -p "$HOME/.local/share/applications"
            for app in qv4l2 qvidcap; do
                printf '[Desktop Entry]\nNoDisplay=true\n' > "$HOME/.local/share/applications/${app}.desktop"
            done
        }
    fi

    ok "Bloat removido"

    # ── Paquetes opcionales (descomenta lo que necesites) ──
    # pac_install gnome-font-viewer      # Visor de fuentes
    # pac_install gnome-logs             # Visor de logs del sistema
    # pac_install gnome-characters       # Mapa de caracteres / emojis
    # pac_install baobab                 # Analizador de uso de disco
    # pac_install gnome-clocks           # Reloj mundial / alarmas / timer
    # pac_install gnome-weather          # Clima
    # pac_install gnome-text-editor      # Editor de texto simple
    # pac_install seahorse               # Gestor de contraseñas/llaves
    # pac_install simple-scan            # Escaneo de documentos
}

install_theme() {
    step "Tema WhiteSur (macOS)"

    # Remover versiones -git si existen (evita conflictos)
    local git_pkgs=""
    for pkg in whitesur-gtk-theme-git whitesur-icon-theme-git whitesur-cursor-theme-git; do
        pacman -Q "$pkg" &>/dev/null && git_pkgs+="$pkg "
    done
    if [[ -n "$git_pkgs" ]]; then
        warn "Removiendo versiones -git conflictivas: $git_pkgs"
        sudo pacman -Rns --noconfirm $git_pkgs
    fi

    pac_install sassc
    aur_install gtk-engine-murrine whitesur-gtk-theme whitesur-icon-theme whitesur-cursor-theme

    ok "Tema WhiteSur instalado"

    info "Aplicando tema WhiteSur Dark a apps libadwaita (GTK4)..."
    local whitesur_tmp
    whitesur_tmp=$(mktemp -d)
    git clone --depth=1 --branch "$WHITESUR_GTK_REF" https://github.com/vinceliuice/WhiteSur-gtk-theme.git "$whitesur_tmp"
    (cd "$whitesur_tmp" && ./install.sh -l -c Dark)
    rm -rf "$whitesur_tmp"
    ok "Override GTK4/libadwaita Dark aplicado (botones macOS en todas las ventanas)"

    info "Para parchear GDM: corré --login"
}

install_extensions() {
    step "Extensiones GNOME"

    aur_install \
        gnome-shell-extension-dash-to-dock \
        gnome-shell-extension-blur-my-shell \
        gnome-shell-extension-user-themes \
        gnome-shell-extension-appindicator \
        gnome-shell-extension-vitals \
        gnome-shell-extension-just-perfection-desktop \
        gnome-shell-extension-clipboard-indicator \
        gnome-shell-extension-hidetopbar-git

    ok "Extensiones instaladas"

    # Extensión custom: dock magnification (fish-eye macOS)
    info "Instalando extensión dock-magnify..."
    local ext_dir="$HOME/.local/share/gnome-shell/extensions/dock-magnify@archlinux-setup"
    mkdir -p "$ext_dir"
    cp "${CONFIGS_DIR}/gnome/dock-magnify/metadata.json" "$ext_dir/"
    cp "${CONFIGS_DIR}/gnome/dock-magnify/extension.js" "$ext_dir/"
    cp "${CONFIGS_DIR}/gnome/dock-magnify/stylesheet.css" "$ext_dir/"
    ok "Extensión dock-magnify instalada"

    # Extensión custom: ocultar notificaciones del calendario
    info "Instalando extensión calendar-tweaks..."
    ext_dir="$HOME/.local/share/gnome-shell/extensions/calendar-tweaks@archlinux-setup"
    mkdir -p "$ext_dir"
    cp "${CONFIGS_DIR}/gnome/calendar-tweaks/metadata.json"  "$ext_dir/"
    cp "${CONFIGS_DIR}/gnome/calendar-tweaks/extension.js"   "$ext_dir/"
    cp "${CONFIGS_DIR}/gnome/calendar-tweaks/stylesheet.css" "$ext_dir/"
    ok "Extensión calendar-tweaks instalada"

    # Extensión custom: reordenar panel (quick settings a la izquierda, Arch icon, fecha a la derecha)
    info "Instalando extensión panel-tweaks..."
    ext_dir="$HOME/.local/share/gnome-shell/extensions/panel-tweaks@archlinux-setup"
    mkdir -p "$ext_dir/icons"
    cp "${CONFIGS_DIR}/gnome/panel-tweaks/metadata.json"  "$ext_dir/"
    cp "${CONFIGS_DIR}/gnome/panel-tweaks/extension.js"   "$ext_dir/"
    cp "${CONFIGS_DIR}/gnome/panel-tweaks/stylesheet.css"  "$ext_dir/"
    cp "${CONFIGS_DIR}/gnome/panel-tweaks/icons/arch-symbolic.svg" "$ext_dir/icons/"
    ok "Extensión panel-tweaks instalada"

    warn "Actívalas en GNOME Extensions después de reiniciar la sesión"
}

install_fonts() {
    step "Fuentes del sistema"

    # Inter: UI general. Cascadia Code Nerd Font (CaskaydiaCove): terminal + glifos Nerd.
    # Apple Color Emoji: emojis estilo macOS/iOS (build para Linux, paquete AUR).
    aur_install ttf-inter ttf-apple-emoji
    pac_install ttf-cascadia-code-nerd

    # Equivalentes libres y métricamente compatibles de las fuentes de Windows
    # (Arial→Liberation Sans, Times→Liberation Serif, Courier→Liberation Mono,
    #  Calibri→Carlito, Cambria→Caladea) para que la web renderice como en Windows.
    pac_install ttf-liberation ttf-carlito ttf-caladea

    # Fallback de emojis a color: encadena Apple Color Emoji a sans/serif/mono.
    # Sin esto fontconfig no los muestra en navegadores/apps aunque la fuente esté.
    info "Instalando fallback de emojis (fontconfig)..."
    mkdir -p "$HOME/.config/fontconfig/conf.d"
    cp "${SHARED_DIR}/fontconfig/10-emoji-fallback.conf" \
        "$HOME/.config/fontconfig/conf.d/10-emoji-fallback.conf"
    fc-cache -f >/dev/null 2>&1 || true

    ok "Fuentes instaladas"
}

install_terminal() {
    step "Terminal (Kitty + Zsh + Starship)"

    pac_install kitty zsh starship
    aur_install zsh-autosuggestions zsh-syntax-highlighting

    # Copiar configs
    info "Copiando configuración de Kitty..."
    mkdir -p "$HOME/.config/kitty"
    cp "${CONFIGS_DIR}/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
    ok "kitty.conf copiado"

    info "Copiando configuración de Starship..."
    mkdir -p "$HOME/.config"
    cp "${SHARED_DIR}/starship/starship.toml" "$HOME/.config/starship.toml"
    ok "starship.toml copiado"

    # Configurar .zshrc
    if [[ -f "$HOME/.zshrc" ]]; then
        cp "$HOME/.zshrc" "$HOME/.zshrc.bak"
        warn ".zshrc existente respaldado en .zshrc.bak"
    fi
    info "Configurando .zshrc..."
    cat > "$HOME/.zshrc" <<'ZSHRC'
# ── Plugins ───────────────────────────────────────────────────────────────
[[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ── Starship prompt ───────────────────────────────────────────────────────
eval "$(starship init zsh)"

# ── Aliases ────────────────────────────────────────────────────────────────
alias ls='ls --color=auto'
alias ll='ls -la'
alias la='ls -A'
alias open='xdg-open'
alias cls='clear'
alias ..='cd ..'
alias ...='cd ../..'

# ── Path ───────────────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"
ZSHRC

    # Cambiar shell a zsh
    if [[ "$SHELL" != *"zsh"* ]]; then
        info "Cambiando shell a zsh..."
        chsh -s "$(which zsh)" 2>/dev/null || \
            warn "No se pudo cambiar el shell automáticamente. Ejecuta: chsh -s \$(which zsh)"
    fi

    ok "Terminal configurada"
}

install_launcher() {
    step "Launcher — Ulauncher (Spotlight equivalent)"

    aur_install ulauncher

    # Tema custom macOS Tahoe Dark
    local theme_dir="$HOME/.config/ulauncher/user-themes/macos-tahoe"
    mkdir -p "$theme_dir"
    cp "${CONFIGS_DIR}/ulauncher/macos-tahoe/manifest.json"       "$theme_dir/"
    cp "${CONFIGS_DIR}/ulauncher/macos-tahoe/theme.css"            "$theme_dir/"
    cp "${CONFIGS_DIR}/ulauncher/macos-tahoe/theme-gtk3.20.css"    "$theme_dir/"
    ok "Tema macOS Tahoe Dark instalado"

    # Configurar Ulauncher: tema custom, sin hotkey interno (GNOME keybinding lo maneja)
    mkdir -p "$HOME/.config/ulauncher"
    cat > "$HOME/.config/ulauncher/settings.json" <<'SETTINGS'
{
    "blacklisted-desktop-dirs": "/usr/share/locale:/usr/share/app-install:/usr/share/gnome:/usr/share/backgrounds:/usr/share/gnome-background-properties:/usr/share/nautilus",
    "clear-previous-query": true,
    "hotkey-show-app": null,
    "render-on-screen": "mouse-pointer-monitor",
    "show-indicator-icon": false,
    "show-recent-apps": "3",
    "terminal-command": "",
    "theme-name": "macos-tahoe"
}
SETTINGS
    ok "Ulauncher configurado (tema: macOS Tahoe Dark, hotkey: via GNOME Ctrl+Space)"

    # Override systemd service: forzar X11 backend para transparencia en Wayland
    local override_dir="$HOME/.config/systemd/user/ulauncher.service.d"
    mkdir -p "$override_dir"
    cat > "$override_dir/x11-backend.conf" <<'OVERRIDE'
[Service]
Environment=GDK_BACKEND=x11
OVERRIDE
    systemctl --user daemon-reload

    # Habilitar autostart
    systemctl --user enable ulauncher 2>/dev/null || true
    systemctl --user restart ulauncher 2>/dev/null || true

    ok "Ulauncher instalado y listo (X11 backend para transparencia)"
}

install_apps() {
    step "Apps, seguridad y entorno de desarrollo"

    # Apps
    pac_install flameshot
    aur_install google-chrome microsoft-edge-stable-bin

    # Firewall
    pac_install ufw
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw --force enable
    sudo systemctl enable ufw
    ok "Firewall (ufw) configurado — deny incoming, allow outgoing"

    # Containers para desarrollo
    pac_install podman distrobox
    ok "Distrobox + Podman instalados"

    ok "Apps, seguridad y entorno de desarrollo listos"
}

_install_app_grid_icon() {
    local icon_src="${CONFIGS_DIR}/gnome/icons/view-app-grid-symbolic.svg"
    [[ ! -f "$icon_src" ]] && return

    local found=false
    for theme_dir in /usr/share/icons/WhiteSur /usr/share/icons/WhiteSur-dark; do
        [[ ! -d "$theme_dir" ]] && continue

        while IFS= read -r existing; do
            sudo rm -f "$existing"
            sudo cp "$icon_src" "$existing"
            found=true
        done < <(find "$theme_dir" -name "view-app-grid*" \( -type f -o -type l \) 2>/dev/null)

        sudo gtk-update-icon-cache -f "$theme_dir" 2>/dev/null || true
    done

    if $found; then
        ok "Icono de app grid (9 puntos) instalado"
    else
        warn "Tema de iconos WhiteSur no encontrado en /usr/share/icons/"
    fi
}

_overview_patch_css() {
    local theme_css=""
    for dir in /usr/share/themes/WhiteSur-Dark "$HOME/.themes/WhiteSur-Dark" "$HOME/.local/share/themes/WhiteSur-Dark"; do
        if [[ -f "$dir/gnome-shell/gnome-shell.css" ]]; then
            theme_css="$dir/gnome-shell/gnome-shell.css"
            break
        fi
    done

    if [[ -z "$theme_css" ]]; then
        warn "WhiteSur-Dark gnome-shell.css no encontrado — overview sin parchear"
        return
    fi

    if grep -q 'archlinux-setup-overview-patch' "$theme_css" 2>/dev/null; then
        ok "Overview CSS ya parcheado"
        return
    fi

    info "Parcheando overview: $theme_css"
    local patch
    patch=$(cat <<'CSSPATCH'

/* archlinux-setup-overview-patch */
.workspace-thumbnails {
  width: 0 !important;
  height: 0 !important;
  margin: 0 !important;
  padding: 0 !important;
  opacity: 0 !important;
}
.workspace-background {
  background-color: transparent !important;
}
CSSPATCH
)
    if [[ "$theme_css" == /usr/share/* ]]; then
        printf '%s\n' "$patch" | sudo tee -a "$theme_css" > /dev/null
    else
        printf '%s\n' "$patch" >> "$theme_css"
    fi
    ok "Workspace thumbnails ocultos via CSS (compatible con Blur My Shell)"
}

apply_tweaks() {
    step "Configuración GNOME (dconf)"

    if ! command -v dconf &>/dev/null; then
        warn "dconf no disponible — ejecuta este paso después del primer login con GNOME"
        return
    fi

    info "Desactivando validación de versión de extensiones (necesario para extensiones custom)..."
    gsettings set org.gnome.shell disable-extension-version-validation true

    info "Cargando configuración GNOME desde gnome-macos.dconf..."
    dconf load / < "${CONFIGS_DIR}/gnome/gnome-macos.dconf"

    if command -v gnome-extensions &>/dev/null; then
        info "Activando extensiones..."
        local exts=(
            dash-to-dock@micxgx.gmail.com
            blur-my-shell@aunetx
            user-theme@gnome-shell-extensions.gcampax.github.com
            appindicatorsupport@rgcjonas.gmail.com
            Vitals@CoreCoding.com
            just-perfection-desktop@just-perfection
            clipboard-indicator@tudmotu.com
            hidetopbar@mathieu.bidon.ca
            dock-magnify@archlinux-setup
            calendar-tweaks@archlinux-setup
            panel-tweaks@archlinux-setup
        )
        for ext in "${exts[@]}"; do
            gnome-extensions enable "$ext" 2>/dev/null || true
        done
        ok "Extensiones activadas"
    fi

    _install_app_grid_icon
    _overview_patch_css

    ok "Configuración GNOME aplicada (tema, fuentes, extensiones)"
}

install_wallpapers() {
    step "Wallpapers dinámicos (cambian según la hora)"

    local tmpdir
    tmpdir=$(mktemp -d)

    info "Clonando WhiteSur-wallpapers..."
    git clone --depth=1 --branch "$WHITESUR_WALLPAPERS_REF" https://github.com/vinceliuice/WhiteSur-wallpapers.git "$tmpdir" \
        2>&1 | tee -a "$LOG_FILE"

    info "Instalando wallpapers dinámicos..."
    (cd "$tmpdir" && bash install-gnome-backgrounds.sh) 2>&1 | tee -a "$LOG_FILE"

    rm -rf "$tmpdir"

    # Activar el wallpaper dinámico WhiteSur (Big Sur) automáticamente
    local whitesur_xml="$HOME/.local/share/backgrounds/WhiteSur/WhiteSur-timed.xml"
    if [[ -f "$whitesur_xml" ]]; then
        gsettings set org.gnome.desktop.background picture-uri "file://${whitesur_xml}"
        gsettings set org.gnome.desktop.background picture-uri-dark "file://${whitesur_xml}"
        gsettings set org.gnome.desktop.background picture-options "zoom"
        ok "Wallpaper dinámico WhiteSur (Big Sur) activado — cambia automáticamente con la hora"
    else
        ok "Wallpapers instalados"
        warn "Seleccioná un wallpaper WhiteSur en Configuración → Fondo de pantalla"
    fi
}

_gdm_patch_css() {
    local gresource="/usr/share/gnome-shell/gnome-shell-theme.gresource"
    local workdir
    workdir=$(mktemp -d)

    # Extraer todos los recursos del gresource instalado
    while IFS= read -r resource; do
        local rel="${resource#/org/gnome/shell/theme/}"
        mkdir -p "$workdir/$(dirname "$rel")"
        gresource extract "$gresource" "$resource" > "$workdir/$rel" 2>/dev/null || true
    done < <(gresource list "$gresource")

    local css_patch
    css_patch=$(cat <<'CSSPATCH'

#panel {
  height: 0 !important;
  background-color: transparent !important;
}
.login-dialog-logo-bin {
  width: 0 !important;
  height: 0 !important;
  margin: 0 !important;
  opacity: 0 !important;
}
.user-icon,
.login-dialog .user-widget .user-icon,
.login-dialog .user-widget.vertical .user-icon {
  icon-size: 0 !important;
  width: 0 !important;
  height: 0 !important;
  margin: 0 !important;
  padding: 0 !important;
  opacity: 0 !important;
  background-color: transparent !important;
}
.user-icon StIcon,
.login-dialog .user-widget.vertical .user-icon StIcon {
  icon-size: 0 !important;
  padding: 0 !important;
  opacity: 0 !important;
}
.login-dialog-button.a11y-button,
.login-dialog-button.login-dialog-session-list-button,
.login-dialog-button.switch-user-button {
  width: 0 !important;
  height: 0 !important;
  margin: 0 !important;
  padding: 0 !important;
  opacity: 0 !important;
}
#lockDialogGroup {
  background-image: url("file:///usr/share/backgrounds/gdm-current.jpg") !important;
}
CSSPATCH
)
    while IFS= read -r css; do
        printf '%s\n' "$css_patch" >> "$css"
    done < <(find "$workdir" -name "*.css")

    # Reconstruir el gresource.xml a partir de los recursos extraídos
    local xml="$workdir/patch.gresource.xml"
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<gresources>'
        echo '  <gresource prefix="/org/gnome/shell/theme">'
        while IFS= read -r resource; do
            echo "    <file>${resource#/org/gnome/shell/theme/}</file>"
        done < <(gresource list "$gresource")
        echo '  </gresource>'
        echo '</gresources>'
    } > "$xml"

    # Recompilar y reemplazar
    (cd "$workdir" && sudo glib-compile-resources patch.gresource.xml \
        --sourcedir="$workdir" \
        --target="$gresource") 2>&1 | tee -a "$LOG_FILE"

    rm -rf "$workdir"
    ok "GDM parcheado (panel, logo, avatar, botones, fondo dinámico)"
}

_lock_screen_patch_css() {
    local theme_css=""
    for dir in /usr/share/themes/WhiteSur-Dark "$HOME/.themes/WhiteSur-Dark" "$HOME/.local/share/themes/WhiteSur-Dark"; do
        if [[ -f "$dir/gnome-shell/gnome-shell.css" ]]; then
            theme_css="$dir/gnome-shell/gnome-shell.css"
            break
        fi
    done

    if [[ -z "$theme_css" ]]; then
        warn "WhiteSur-Dark gnome-shell.css no encontrado — lock screen sin parchear"
        return
    fi

    if grep -q 'archlinux-setup-lock-patch' "$theme_css" 2>/dev/null; then
        ok "Lock screen CSS ya parcheado"
        return
    fi

    info "Parcheando lock screen: $theme_css"
    local patch
    patch=$(cat <<'CSSPATCH'

/* archlinux-setup-lock-patch */
.unlock-dialog .user-widget .user-icon,
.unlock-dialog .user-widget.vertical .user-icon {
  icon-size: 0 !important;
  width: 0 !important;
  height: 0 !important;
  margin: 0 !important;
  padding: 0 !important;
  opacity: 0 !important;
  background-color: transparent !important;
}
.unlock-dialog .user-widget.vertical .user-icon StIcon {
  icon-size: 0 !important;
  padding: 0 !important;
  opacity: 0 !important;
}
.unlock-dialog .cancel-button,
.unlock-dialog .switch-user-button,
.unlock-dialog .login-dialog-session-list-button {
  width: 0 !important;
  height: 0 !important;
  margin: 0 !important;
  padding: 0 !important;
  opacity: 0 !important;
}
CSSPATCH
)
    if [[ "$theme_css" == /usr/share/* ]]; then
        printf '%s\n' "$patch" | sudo tee -a "$theme_css" > /dev/null
    else
        printf '%s\n' "$patch" >> "$theme_css"
    fi
    ok "Lock screen CSS parcheado — consistente con GDM"
}

_gdm_generate_blur() {
    local dir="$1"

    if [[ -f "$dir/WhiteSur-light-blur.jpg" && -f "$dir/WhiteSur-blur.jpg" ]]; then
        return
    fi

    if ! command -v magick &>/dev/null && ! command -v convert &>/dev/null; then
        info "Instalando imagemagick para efecto blur..."
        sudo pacman -S --noconfirm imagemagick 2>&1 | tee -a "$LOG_FILE"
    fi

    local blur_cmd="magick"
    command -v magick &>/dev/null || blur_cmd="convert"

    # WhiteSur-light.jpg (day) and WhiteSur.jpg (night)
    local src dst
    src="$dir/WhiteSur-light.jpg"; dst="$dir/WhiteSur-light-blur.jpg"
    if [[ -f "$src" && ! -f "$dst" ]]; then
        info "Generando blur: WhiteSur-light-blur.jpg..."
        sudo "$blur_cmd" "$src" -blur 0x30 "$dst"
        ok "WhiteSur-light-blur.jpg"
    fi

    src="$dir/WhiteSur.jpg"; dst="$dir/WhiteSur-blur.jpg"
    if [[ -f "$src" && ! -f "$dst" ]]; then
        info "Generando blur: WhiteSur-blur.jpg..."
        sudo "$blur_cmd" "$src" -blur 0x30 "$dst"
        ok "WhiteSur-blur.jpg"
    fi
}

_gdm_ensure_wallpapers() {
    local sys_dir="/usr/share/backgrounds/WhiteSur"
    local user_dir="$HOME/.local/share/backgrounds/WhiteSur"

    if [[ ! -f "$sys_dir/WhiteSur-light.jpg" || ! -f "$sys_dir/WhiteSur.jpg" ]]; then
        if [[ -d "$user_dir" ]]; then
            info "Copiando wallpapers WhiteSur a ubicación del sistema..."
            sudo mkdir -p "$sys_dir"
            sudo cp "$user_dir"/*.jpg "$sys_dir/" 2>/dev/null || true
            [[ -f "$user_dir/WhiteSur-timed.xml" ]] && sudo cp "$user_dir/WhiteSur-timed.xml" "$sys_dir/"
            ok "Wallpapers copiados a $sys_dir"
        else
            warn "Wallpapers WhiteSur no encontrados — corré --wallpapers primero"
            return
        fi
    fi

    _gdm_generate_blur "$sys_dir"
}

_gdm_setup_dynamic_wallpaper() {
    info "Instalando servicio de wallpaper dinámico..."

    sudo install -m 755 "${SCRIPT_DIR}/gdm-wallpaper-update.sh" /usr/local/bin/gdm-wallpaper-update

    sudo tee /etc/systemd/system/gdm-wallpaper.service > /dev/null <<'UNIT'
[Unit]
Description=Update GDM wallpaper based on time of day

[Service]
Type=oneshot
ExecStart=/usr/local/bin/gdm-wallpaper-update
UNIT

    sudo tee /etc/systemd/system/gdm-wallpaper.timer > /dev/null <<'UNIT'
[Unit]
Description=Update GDM wallpaper hourly

[Timer]
OnBootSec=0
OnUnitActiveSec=1h

[Install]
WantedBy=timers.target
UNIT

    sudo systemctl daemon-reload
    sudo systemctl enable --now gdm-wallpaper.timer 2>&1 | tee -a "$LOG_FILE"
    sudo /usr/local/bin/gdm-wallpaper-update
    ok "Wallpaper dinámico configurado (actualiza al bootear y cada hora)"
}

apply_login() {
    step "Login — GDM estilo macOS con wallpaper dinámico"

    _gdm_ensure_wallpapers

    local tmpdir
    tmpdir=$(mktemp -d)

    info "Clonando WhiteSur-gtk-theme..."
    git clone --depth=1 --branch "$WHITESUR_GTK_REF" https://github.com/vinceliuice/WhiteSur-gtk-theme.git "$tmpdir" \
        2>&1 | tee -a "$LOG_FILE"

    info "Aplicando tema WhiteSur a GDM (requiere sudo)..."
    (cd "$tmpdir" && sudo ./tweaks.sh -g -nd -b default) 2>&1 | tee -a "$LOG_FILE"

    rm -rf "$tmpdir"

    _gdm_setup_dynamic_wallpaper

    info "Parcheando gresource (panel, logo, avatar, botones, fondo dinámico)..."
    _gdm_patch_css

    _lock_screen_patch_css

    ok "GDM configurado — login limpio con wallpaper dinámico"
    warn "Corré: sudo systemctl restart gdm"
}

# Driver NVIDIA con módulos abiertos. Blackwell (RTX serie 50, ej. 5060 Ti)
# REQUIERE nvidia-open-dkms; el módulo propietario clásico ya no la soporta.
# DKMS compila el módulo contra cada kernel instalado (stock + CachyOS).
configure_nvidia() {
    info "GPU NVIDIA detectada — instalando módulos abiertos (nvidia-open-dkms)"

    # Headers de cada kernel instalado: DKMS los necesita para compilar el módulo.
    local hdrs=() k
    for k in linux linux-lts linux-zen linux-hardened linux-cachyos linux-cachyos-bore; do
        pacman -Q "$k" &>/dev/null && hdrs+=("${k}-headers")
    done
    [[ ${#hdrs[@]} -eq 0 ]] && warn "No detecté headers de kernel — DKMS podría no compilar el módulo"

    # nvidia-open-dkms: módulos abiertos (obligatorio en Blackwell). nvidia-utils: userspace.
    local nvidia_pkgs=(nvidia-open-dkms nvidia-utils)
    # lib32 solo si multilib está habilitado (Steam/Wine). El setup no lo habilita por defecto.
    if pacman-conf --repo-list 2>/dev/null | grep -qx multilib; then
        nvidia_pkgs+=(lib32-nvidia-utils)
    fi
    pac_install "${hdrs[@]}" "${nvidia_pkgs[@]}"

    # Nouveau bloquea la init del módulo NVIDIA (pantalla negra) si llega a cargar.
    info "Blacklisting nouveau..."
    printf 'blacklist nouveau\noptions nouveau modeset=0\n' \
        | sudo tee /etc/modprobe.d/blacklist-nouveau.conf >/dev/null

    # Early KMS: módulos NVIDIA en el initramfs (requerido por la sesión Wayland de GNOME).
    if [[ -f /etc/mkinitcpio.conf ]] && ! grep -q 'nvidia_drm' /etc/mkinitcpio.conf; then
        info "Agregando módulos NVIDIA a mkinitcpio..."
        sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
        sudo sed -i 's/MODULES=( /MODULES=(/' /etc/mkinitcpio.conf
    fi

    # nvidia_drm.modeset=1 en la línea de comando del kernel (Wayland). Idempotente.
    if [[ -f /etc/default/grub ]] && ! grep -q 'nvidia_drm.modeset=1' /etc/default/grub; then
        info "Agregando nvidia_drm.modeset=1 a GRUB_CMDLINE_LINUX_DEFAULT..."
        sudo sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 nvidia_drm.modeset=1"/' /etc/default/grub
    fi

    # Regenerar initramfs con los módulos nuevos.
    if command -v mkinitcpio &>/dev/null; then
        info "Regenerando initramfs (mkinitcpio -P)..."
        sudo mkinitcpio -P 2>&1 | tee -a "$LOG_FILE" || warn "mkinitcpio -P falló"
    fi

    # Power management: evita corrupción de VRAM al suspender/hibernar.
    sudo systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service \
        2>&1 | tee -a "$LOG_FILE" || warn "No se pudieron habilitar los servicios nvidia-*"

    warn "Kernel 7.0 + Blackwell: regresión de suspend/resume (s2idle) sin fix a jun-2026."
    warn "  Si usás el kernel CachyOS (7.x) y se cuelga al resumir, probá un kernel 6.17/LTS."
    ok "NVIDIA configurada — reiniciá y verificá con: nvidia-smi"
}

install_hardware() {
    step "Hardware — microcode del CPU + drivers de GPU"

    # ── Microcode (crítico en baremetal — no aplica en VMs) ──
    local ucode=""
    if grep -q "AuthenticAMD" /proc/cpuinfo; then
        ucode="amd-ucode"
    elif grep -q "GenuineIntel" /proc/cpuinfo; then
        ucode="intel-ucode"
    fi
    if [[ -n "$ucode" ]]; then
        pac_install "$ucode"
    else
        warn "No se detectó vendor de CPU — sin microcode"
    fi

    command -v lspci &>/dev/null || pac_install pciutils

    # ── Drivers userspace de la iGPU (AMD/Intel) — Mesa. Inofensivo como fallback ──
    local igpu_pkgs=""
    if lspci 2>/dev/null | grep -E -qi 'amd|ati'; then
        igpu_pkgs="mesa vulkan-radeon libva-mesa-driver mesa-vdpau"
        info "iGPU AMD detectada — drivers RADV/VAAPI/VDPAU"
    elif lspci 2>/dev/null | grep -qi 'intel.*graphics\|intel.*display'; then
        igpu_pkgs="mesa vulkan-intel intel-media-driver"
        info "iGPU Intel detectada — drivers ANV/VAAPI"
    fi
    [[ -n "$igpu_pkgs" ]] && pac_install $igpu_pkgs

    # ── NVIDIA: bloque INDEPENDIENTE (no elif). Se atiende siempre que esté
    #    presente, sin importar la iGPU. Override para VM: FORCE_GPU=nvidia ──
    local has_nvidia="false"
    if [[ "${FORCE_GPU:-}" == "nvidia" ]]; then
        has_nvidia="true"
        warn "FORCE_GPU=nvidia — forzando branch NVIDIA (test/VM, sin placa real)"
    elif lspci 2>/dev/null | grep -qi 'nvidia'; then
        has_nvidia="true"
    fi
    [[ "$has_nvidia" == "true" ]] && configure_nvidia

    # ── Regenerar GRUB (microcode + nvidia_drm.modeset si se agregó) ──
    if command -v grub-mkconfig &>/dev/null; then
        info "Regenerando GRUB..."
        sudo grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tee -a "$LOG_FILE"
    fi

    ok "Hardware configurado (microcode + drivers de GPU)"
}

install_cachyos_repos() {
    step "CachyOS — Repos optimizados + kernel BORE/EEVDF"

    if grep -q "\[cachyos" /etc/pacman.conf; then
        ok "Repos de CachyOS ya están configurados en /etc/pacman.conf"
        return
    fi

    local tmpdir
    tmpdir=$(mktemp -d)

    info "Descargando script oficial de CachyOS..."
    curl -L "https://mirror.cachyos.org/cachyos-repo.tar.xz" -o "$tmpdir/cachyos-repo.tar.xz" \
        2>&1 | tee -a "$LOG_FILE"
    tar xf "$tmpdir/cachyos-repo.tar.xz" -C "$tmpdir"

    info "Configurando repos (auto-detecta x86-64-v3 o v4 según tu CPU)..."
    (cd "$tmpdir/cachyos-repo" && sudo ./cachyos-repo.sh)

    rm -rf "$tmpdir"

    info "Actualizando sistema con paquetes optimizados (puede tardar varios minutos)..."
    sudo pacman -Syu --noconfirm 2>&1 | tee -a "$LOG_FILE"

    info "Instalando kernel CachyOS (BORE/EEVDF scheduler)..."
    sudo pacman -S --noconfirm --needed linux-cachyos linux-cachyos-headers \
        2>&1 | tee -a "$LOG_FILE"

    if command -v grub-mkconfig &>/dev/null; then
        info "Regenerando configuración de GRUB..."
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi

    ok "Repos CachyOS activos — sistema actualizado con instrucciones optimizadas"
    ok "Kernel linux-cachyos instalado (BORE/EEVDF scheduler)"
    warn "IMPORTANTE: reinicia para bootear con el nuevo kernel"
}

# ============================================================================
# MENÚ PRINCIPAL
# ============================================================================

# Repos extra de paquetes. En Arch: habilita [multilib] (paquetes de 32 bits,
# ej. lib32-nvidia-utils para Steam/Wine). Análogo a --repos de Fedora (RPM Fusion).
setup_repos() {
    step "Repos — habilitar multilib (paquetes de 32 bits)"

    if grep -qE '^\[multilib\]' /etc/pacman.conf; then
        info "multilib ya está habilitado"
    else
        info "Habilitando [multilib] en /etc/pacman.conf..."
        sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
        sudo pacman -Sy 2>&1 | tee -a "$LOG_FILE" || warn "pacman -Sy falló tras habilitar multilib"
    fi

    ok "Repos configurados (multilib)"
}

# Layout de teclado system-wide: English intl (AltGr dead keys). Mismo concepto
# y resultado que --keyboard de Fedora (ambos usan localectl).
configure_keyboard() {
    step "Teclado — English intl (AltGr dead keys)"

    sudo localectl set-x11-keymap us "" altgr-intl 2>&1 | tee -a "$LOG_FILE" \
        || warn "localectl set-x11-keymap falló"

    ok "Teclado configurado (us, altgr-intl)"
}

# Layout de escritorio estilo macOS. En GNOME: extensiones + ajustes dconf.
# Mismo concepto que --desktop de Fedora (panel layout de KDE).
configure_desktop() {
    install_extensions
    apply_tweaks
}

run_all() {
    ensure_yay

    # CachyOS PRIMERO: agrega los repos optimizados (x86-64-v3/v4) antes de instalar
    # nada, así GNOME, mesa y el resto se bajan ya compilados para tu CPU.
    # El kernel BORE/EEVDF queda instalado y se activa al reiniciar.
    run_module "CachyOS (repos + kernel)"   install_cachyos_repos
    run_module "Repos (multilib)"           setup_repos
    run_module "Hardware (microcode + GPU)" install_hardware
    run_module "GNOME base"                 install_gnome
    run_module "Tema WhiteSur"              install_theme
    run_module "Fuentes"                    install_fonts
    run_module "Terminal"                   install_terminal
    run_module "Launcher (Ulauncher)"       install_launcher
    run_module "Apps + dev"                 install_apps
    run_module "Wallpapers"                 install_wallpapers
    run_module "Escritorio (extensiones + ajustes)" configure_desktop
    run_module "Teclado"                    configure_keyboard

    print_summary
}

show_menu() {
    ensure_yay

    while true; do
        echo -e "\n${C}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${C}║  Arch Linux — Setup estilo macOS                    ║${NC}"
        echo -e "${C}╚══════════════════════════════════════════════════════╝${NC}\n"
        echo "  1) Instalar todo — incluye CachyOS (recomendado)"
        echo "  2) Repos (multilib)"
        echo "  3) Hardware (microcode + GPU NVIDIA)"
        echo "  4) GNOME base"
        echo "  5) Tema WhiteSur"
        echo "  6) Fuentes"
        echo "  7) Escritorio (extensiones + ajustes)"
        echo "  8) Terminal (Kitty + Zsh + Starship)"
        echo "  9) Launcher (Ulauncher)"
        echo "  a) Apps"
        echo "  w) Wallpapers dinámicos (cambian por hora)"
        echo "  k) Teclado (us altgr-intl)"
        echo "  l) Login GDM estilo macOS"
        echo "  c) CachyOS repos + kernel BORE (ya incluido en 'todo')"
        echo "  0) Salir"
        echo ""
        read -rp "Selecciona una opción: " choice

        case $choice in
            1) run_all; break ;;
            2) setup_repos; break ;;
            3) install_hardware; break ;;
            4) install_gnome; break ;;
            5) install_theme; break ;;
            6) install_fonts; break ;;
            7) configure_desktop; break ;;
            8) install_terminal; break ;;
            9) install_launcher; break ;;
            a) install_apps; break ;;
            w) install_wallpapers; break ;;
            k) configure_keyboard; break ;;
            l) apply_login; break ;;
            c) install_cachyos_repos; break ;;
            0) exit 0 ;;
            *) warn "Opción inválida" ;;
        esac
    done
}

# ── CLI args ───────────────────────────────────────────────────────────────
case "${1:-}" in
    --all)        ensure_yay; run_all ;;
    --repos)      setup_repos ;;
    --hardware)   install_hardware ;;
    --gnome)      ensure_yay; install_gnome ;;
    --theme)      ensure_yay; install_theme ;;
    --fonts)      ensure_yay; install_fonts ;;
    --desktop)    ensure_yay; configure_desktop ;;
    --terminal)   ensure_yay; install_terminal ;;
    --launcher)   ensure_yay; install_launcher ;;
    --apps)       ensure_yay; install_apps ;;
    --wallpapers) install_wallpapers ;;
    --keyboard)   configure_keyboard ;;
    --login)      apply_login ;;
    --cachyos)    install_cachyos_repos ;;
    "")           show_menu ;;
    *)            echo "Uso: $0 [--all|--repos|--hardware|--gnome|--theme|--fonts|--desktop|--terminal|--launcher|--apps|--wallpapers|--keyboard|--login|--cachyos]"; exit 1 ;;
esac
