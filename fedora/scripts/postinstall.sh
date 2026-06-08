#!/usr/bin/env bash
# ============================================================================
# Fedora 42 + KDE Plasma 6 — Setup estilo macOS
# Ejecutar como usuario normal después del primer boot
# Uso: bash postinstall.sh [--all | --repos | --fonts | --apps | --themes |
#          --gtk | --kvantum | --icons | --decorations | --wallpapers | --panel | --konsole]
# Sin argumentos = muestra el uso
# ============================================================================
set -euo pipefail

# ── Colores ─────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${B}[INFO]${NC}  $1"; }
ok()    { echo -e "${G}[OK]${NC}    $1"; }
warn()  { echo -e "${Y}[WARN]${NC}  $1"; }
error() { echo -e "${R}[ERROR]${NC} $1" >&2; }
step()  { echo -e "\n${C}━━━ $1 ━━━${NC}\n"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/../configs"
SHARED_DIR="${SCRIPT_DIR}/../../shared"

# Log persistente (sobrevive reinicios — /tmp se borra al rebootear)
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/fedora-macos-setup.log"

# Tracking de fallos: un paquete o módulo que falla NO debe abortar todo el setup
FAILED_PKGS=()
FAILED_MODULES=()

[[ ! -d "$CONFIGS_DIR" ]] && { warn "Directorio de configs no encontrado: $CONFIGS_DIR — continuando de todos modos"; }

# ── Resolver qdbus6 ──────────────────────────────────────────────────────────
# Fedora 42 puede tenerlo como qdbus6, qdbus-qt6 o qdbus según el build.
# Exportamos $QDBUS para que todos los módulos lo usen sin repetir esta lógica.
QDBUS=""
for _qd in qdbus6 qdbus-qt6 qdbus; do
    if command -v "$_qd" &>/dev/null; then
        QDBUS="$_qd"
        break
    fi
done
export QDBUS

# ── Pinned upstream refs (WhiteSur) ──────────────────────────────────────────
# Bump intencionalmente; clonar HEAD no es reproducible. Ver dependency audit.
readonly WHITESUR_GTK_REF="2025-07-24"
readonly WHITESUR_KDE_REF="2024-11-18"
readonly WHITESUR_ICON_REF="2025-12-27"
readonly WHITESUR_WALLPAPERS_REF="2023-06-11"
readonly WHITESUR_CURSORS_SHA="e190baf618ed95ee217d2fd45589bd309b37672b"

# ── Helpers ────────────────────────────────────────────────────────────────
# Estrategia: intentar el batch (rápido, resuelve dependencias juntas). Si falla,
# reintentar paquete por paquete para que UN paquete roto no arrastre al resto.
# Los fallos se registran en FAILED_PKGS y el script CONTINÚA.
dnf_install() {
    info "Installing (dnf): $*"
    if sudo dnf install -y "$@" 2>&1 | tee -a "$LOG_FILE"; then
        return 0
    fi
    warn "dnf batch failed — retrying one by one..."
    local pkg
    for pkg in "$@"; do
        if ! sudo dnf install -y "$pkg" 2>&1 | tee -a "$LOG_FILE"; then
            warn "Package failed (dnf): $pkg"
            FAILED_PKGS+=("$pkg")
        fi
    done
}

# Habilita un repositorio COPR. Idempotente: si ya está habilitado, no falla.
copr_enable() {
    local repo="$1"
    info "Enabling COPR: $repo"
    if sudo dnf copr enable -y "$repo" 2>&1 | tee -a "$LOG_FILE"; then
        ok "COPR enabled: $repo"
    else
        warn "COPR enable failed: $repo"
        FAILED_PKGS+=("copr:$repo")
    fi
}

# Instala apps de Flathub. Mismo patrón batch→individual que dnf_install.
flatpak_install() {
    info "Installing (flatpak): $*"
    if flatpak install -y flathub "$@" 2>&1 | tee -a "$LOG_FILE"; then
        return 0
    fi
    warn "flatpak batch failed — retrying one by one..."
    local app
    for app in "$@"; do
        if ! flatpak install -y flathub "$app" 2>&1 | tee -a "$LOG_FILE"; then
            warn "Flatpak failed: $app"
            FAILED_PKGS+=("flatpak:$app")
        fi
    done
}

# Ejecuta un módulo sin que su fallo aborte el resto del setup.
# El 'if' suprime 'set -e' dentro del módulo y captura su estado final.
run_module() {
    local label="$1"; shift
    step "▶ $label"
    if "$@"; then
        ok "Module OK: $label"
    else
        warn "Module had errors: $label — continuing with the rest"
        FAILED_MODULES+=("$label")
    fi
}

print_summary() {
    echo ""
    echo -e "${G}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${G}║  Setup complete                                      ║${NC}"
    echo -e "${G}╚══════════════════════════════════════════════════════╝${NC}"

    if [[ ${#FAILED_MODULES[@]} -eq 0 && ${#FAILED_PKGS[@]} -eq 0 ]]; then
        ok "All modules and packages installed without errors"
    else
        [[ ${#FAILED_MODULES[@]} -gt 0 ]] && warn "Modules with errors: ${FAILED_MODULES[*]}"
        [[ ${#FAILED_PKGS[@]} -gt 0 ]]    && warn "Packages that failed: ${FAILED_PKGS[*]}"
        echo "  Full log: $LOG_FILE"
        echo "  Retry a single module with: bash postinstall.sh --<module>"
    fi

    echo ""
    echo -e "${G}Next steps:${NC}"
    echo "  • Log out and back in to see the full theme and font changes"
    echo "  • If panel layout looks off, re-run: bash postinstall.sh --panel"
    echo ""

    # Salir con código de error si hubo fallos (útil para CI / scripts llamadores)
    if [[ ${#FAILED_MODULES[@]} -gt 0 || ${#FAILED_PKGS[@]} -gt 0 ]]; then
        return 1
    fi
}

# ============================================================================
# MÓDULOS
# ============================================================================

# ── Módulo 1: Repos ─────────────────────────────────────────────────────────
setup_repos() {
    step "Repos — RPM Fusion + Flathub"

    local fedora_ver
    fedora_ver="$(rpm -E %fedora)"

    # RPM Fusion free + nonfree (idempotente: dnf install en un RPM ya instalado = no-op)
    info "Enabling RPM Fusion free + nonfree for Fedora ${fedora_ver}..."
    sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm" \
        2>&1 | tee -a "$LOG_FILE" || warn "RPM Fusion install returned non-zero (may already be enabled)"

    # Flathub (--if-not-exists es idempotente)
    info "Adding Flathub remote..."
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo \
        2>&1 | tee -a "$LOG_FILE" || warn "Flathub remote add returned non-zero (may already exist)"

    # Actualización del sistema tras nuevos repos
    info "Running dnf upgrade --refresh..."
    sudo dnf upgrade --refresh -y 2>&1 | tee -a "$LOG_FILE"

    ok "Repos configured (RPM Fusion + Flathub)"
}

# ── Módulo 2: Fuentes ────────────────────────────────────────────────────────
install_fonts() {
    step "Fonts — Inter + Cascadia Code Nerd Font + Apple Emoji + Windows-equivalent"

    # Inter (UI general) viene directamente de los repos de Fedora.
    # Liberation/Carlito/Caladea: equivalentes libres y métricamente compatibles de
    # las fuentes de Windows (Arial/Times/Courier/Calibri/Cambria) para la web.
    dnf_install \
        rsms-inter-fonts \
        liberation-sans-fonts \
        liberation-serif-fonts \
        liberation-mono-fonts \
        google-carlito-fonts \
        google-crosextra-caladea-fonts

    # Instalar la variante Nerd Font de Cascadia Code (CaskaydiaCove) desde el
    # release oficial de nerd-fonts — trae los glifos de iconos que necesita Starship.
    local nerd_font_dir="${HOME}/.local/share/fonts/CascadiaCodeNerd"
    if fc-list | grep -qi 'CaskaydiaCove Nerd'; then
        info "CaskaydiaCove Nerd Font already installed — skipping download"
    else
        info "Downloading CaskaydiaCove (Cascadia Code) Nerd Font from nerd-fonts releases..."
        local nf_tmp
        nf_tmp="$(mktemp -d)"
        # shellcheck disable=SC2064
        trap "rm -rf '$nf_tmp'" RETURN
        local nf_archive="${nf_tmp}/CascadiaCode.tar.xz"

        if curl -fsSL \
            "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.tar.xz" \
            -o "$nf_archive" 2>&1 | tee -a "$LOG_FILE"; then
            mkdir -p "$nerd_font_dir"
            tar -xf "$nf_archive" --wildcards '*.ttf' -C "$nerd_font_dir" \
                2>&1 | tee -a "$LOG_FILE" \
                || warn "tar extraction returned non-zero — some font files may be missing"
            info "CaskaydiaCove Nerd Font extracted to $nerd_font_dir"
        else
            warn "CaskaydiaCove Nerd Font download failed — Starship/powerline glyphs may not render"
            FAILED_PKGS+=("nerd-fonts:CascadiaCode")
        fi
    fi

    # Apple Color Emoji (estilo macOS/iOS) — no hay paquete en Fedora; se baja el
    # build para Linux desde samuelngs/apple-emoji-ttf. Reemplaza a Noto (estilo Google).
    local apple_emoji_dir="${HOME}/.local/share/fonts/AppleColorEmoji"
    if fc-list | grep -qi 'Apple Color Emoji'; then
        info "Apple Color Emoji already installed — skipping download"
    else
        info "Downloading Apple Color Emoji (Linux build)..."
        mkdir -p "$apple_emoji_dir"
        if curl -fsSL \
            "https://github.com/samuelngs/apple-emoji-ttf/releases/latest/download/AppleColorEmoji-Linux.ttf" \
            -o "${apple_emoji_dir}/AppleColorEmoji.ttf" 2>&1 | tee -a "$LOG_FILE"; then
            info "Apple Color Emoji installed to $apple_emoji_dir"
        else
            warn "Apple Color Emoji download failed — emoji may not render"
            FAILED_PKGS+=("apple-color-emoji")
        fi
    fi

    # Fallback de emojis a color: encadena Apple Color Emoji a sans/serif/mono.
    # Sin esto fontconfig no los muestra en navegadores/apps aunque la fuente esté.
    info "Installing emoji fallback config (fontconfig)..."
    mkdir -p "${HOME}/.config/fontconfig/conf.d"
    cp "${SHARED_DIR}/fontconfig/10-emoji-fallback.conf" \
        "${HOME}/.config/fontconfig/conf.d/10-emoji-fallback.conf" \
        2>&1 | tee -a "$LOG_FILE" || warn "emoji fallback config copy failed"

    # Regenerar caché de fuentes para que las apps vean las nuevas fuentes
    fc-cache -f 2>&1 | tee -a "$LOG_FILE" || warn "fc-cache returned non-zero"

    # Aplicar fuentes en KDE via kwriteconfig6 (solo si está disponible)
    if command -v kwriteconfig6 &>/dev/null; then
        info "Configuring KDE fonts via kwriteconfig6..."
        # Fuente general: Inter 10pt
        kwriteconfig6 --file kdeglobals --group General \
            --key font "Inter,10,-1,5,50,0,0,0,0,0"
        # Fuente monospace: CaskaydiaCove Nerd Font 10pt (con glifos de iconos)
        kwriteconfig6 --file kdeglobals --group General \
            --key fixed "CaskaydiaCove Nerd Font,10,-1,5,50,0,0,0,0,0"
        ok "KDE font config written — re-login to apply fonts fully"
    else
        warn "kwriteconfig6 not found — skipping KDE font config (run after KDE is installed)"
    fi

    ok "Fonts installed"
}

# ── Módulo 3: Apps ───────────────────────────────────────────────────────────
install_apps() {
    step "Apps + dev tools + firewall"

    # Herramientas de captura de pantalla y contenedores
    dnf_install \
        flameshot \
        podman \
        distrobox

    ok "flameshot + podman + distrobox installed"

    # Firewall (firewalld viene con Fedora KDE spin pero puede estar desactivado)
    if command -v firewall-cmd &>/dev/null; then
        info "Enabling firewalld..."
        sudo systemctl enable --now firewalld 2>&1 | tee -a "$LOG_FILE" \
            || warn "firewalld enable returned non-zero (may already be running)"
        ok "firewalld enabled"
    else
        dnf_install firewalld
        sudo systemctl enable --now firewalld 2>&1 | tee -a "$LOG_FILE" || true
        ok "firewalld installed and enabled"
    fi

    # Apps de Flatpak (navegadores — Flatpak es la forma recomendada en Fedora inmutable/atómica)
    info "Installing browser Flatpaks..."
    flatpak_install com.google.Chrome

    ok "Apps, dev tools, and firewall configured"
}

# ── Módulo 4: WhiteSur themes ────────────────────────────────────────────────
# Clona el repo WhiteSur-kde a un directorio temporal, ejecuta su install.sh y
# aplica el look-and-feel global de Plasma. Re-ejecutar es idempotente (install.sh
# sobreescribe los archivos existentes).
install_whitesur_themes() {
    step "WhiteSur KDE — Plasma look-and-feel + Aurorae"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    # Limpiar el directorio temporal al salir (éxito o error)
    trap 'rm -rf "$tmp_dir"' RETURN

    info "Cloning WhiteSur-kde..."
    git clone --depth=1 --branch "$WHITESUR_KDE_REF" https://github.com/vinceliuice/WhiteSur-kde.git \
        "$tmp_dir/WhiteSur-kde" 2>&1 | tee -a "$LOG_FILE"

    info "Running WhiteSur-kde install.sh..."
    bash "$tmp_dir/WhiteSur-kde/install.sh" 2>&1 | tee -a "$LOG_FILE"

    # Aplicar el look-and-feel global (Plasma style + color scheme + window deco en un paso).
    # El || true evita que falle si la sesión gráfica no está disponible (ej. CI, headless).
    info "Applying WhiteSur look-and-feel..."
    plasma-apply-lookandfeel -a com.github.vinceliuice.WhiteSur 2>&1 | tee -a "$LOG_FILE" \
        || warn "plasma-apply-lookandfeel returned non-zero (normal si no hay sesión gráfica activa)"

    ok "WhiteSur KDE theme installed"
}

# ── Módulo 4b: WhiteSur GTK theme ────────────────────────────────────────────
# WhiteSur-kde NO instala el tema GTK — ese está en un repo separado.
# Este módulo clona WhiteSur-gtk-theme y lo instala con el enlace libadwaita (-l)
# para que las apps GTK4 también hereden el look WhiteSur.
install_whitesur_gtk() {
    step "WhiteSur GTK — GTK3/GTK4 theme + libadwaita link"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' RETURN

    info "Cloning WhiteSur-gtk-theme..."
    git clone --depth=1 --branch "$WHITESUR_GTK_REF" https://github.com/vinceliuice/WhiteSur-gtk-theme.git \
        "$tmp_dir/WhiteSur-gtk-theme" 2>&1 | tee -a "$LOG_FILE" \
        || { warn "WhiteSur-gtk-theme clone failed — skipping GTK theme install"; return 0; }

    info "Running WhiteSur-gtk-theme install.sh -l (libadwaita link)..."
    bash "$tmp_dir/WhiteSur-gtk-theme/install.sh" -l 2>&1 | tee -a "$LOG_FILE" \
        || warn "WhiteSur-gtk-theme install.sh returned non-zero (partial install may still work)"

    # Registrar el tema GTK en KDE para que Dolphin y apps GTK lo usen
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file kdeglobals --group General --key GtkTheme WhiteSur-Dark
        info "KDE GTK theme set to WhiteSur-Dark"
    fi

    ok "WhiteSur GTK theme installed"
}

# ── Módulo 5: Kvantum ────────────────────────────────────────────────────────
# Kvantum aplica el estilo de widgets Qt (el puente entre GTK-look y Qt apps).
# Se instala vía dnf si no está presente, luego se configura el tema WhiteSurDark.
apply_kvantum() {
    step "Kvantum — WhiteSurDark widget style"

    # Instalar kvantum si no está disponible
    if ! command -v kvantummanager &>/dev/null; then
        info "kvantum not found — installing via dnf..."
        dnf_install kvantum
    fi

    # Configurar el tema de Kvantum (creado por el install.sh de WhiteSur-kde)
    kvantummanager --set WhiteSurDark 2>&1 | tee -a "$LOG_FILE" \
        || warn "kvantummanager --set returned non-zero (normal fuera de sesión gráfica)"

    # Registrar kvantum como el estilo de widgets en KDE
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle kvantum
        info "KDE widget style set to kvantum"
    fi

    # Pedir a KWin que relea su config sin cerrar la sesión
    [[ -n "$QDBUS" ]] && "$QDBUS" org.kde.KWin /KWin reconfigure 2>/dev/null \
        || warn "KWin reconfigure skipped (QDBUS not available or headless)"

    ok "Kvantum configured (WhiteSurDark)"
}

# ── Módulo 6: Icons + cursors ────────────────────────────────────────────────
# Instala WhiteSur-icon-theme y WhiteSur-cursors desde sus repos upstream.
install_icons_cursors() {
    step "Icons + cursors — WhiteSur"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' RETURN

    # Icons
    info "Cloning WhiteSur-icon-theme..."
    git clone --depth=1 --branch "$WHITESUR_ICON_REF" https://github.com/vinceliuice/WhiteSur-icon-theme.git \
        "$tmp_dir/WhiteSur-icon-theme" 2>&1 | tee -a "$LOG_FILE"

    info "Installing WhiteSur icon theme..."
    bash "$tmp_dir/WhiteSur-icon-theme/install.sh" -a 2>&1 | tee -a "$LOG_FILE" \
        || warn "icon theme install returned non-zero"

    # Cursors
    info "Cloning WhiteSur-cursors..."
    git clone --filter=blob:none https://github.com/vinceliuice/WhiteSur-cursors.git \
        "$tmp_dir/WhiteSur-cursors" 2>&1 | tee -a "$LOG_FILE" \
        && git -C "$tmp_dir/WhiteSur-cursors" checkout "$WHITESUR_CURSORS_SHA" 2>&1 | tee -a "$LOG_FILE"

    info "Installing WhiteSur cursors..."
    bash "$tmp_dir/WhiteSur-cursors/install.sh" 2>&1 | tee -a "$LOG_FILE" \
        || warn "cursor theme install returned non-zero"

    # Aplicar en KDE (cambio permanente vía kwriteconfig6)
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file kdeglobals --group Icons --key Theme WhiteSur
        kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme WhiteSur-cursors
        info "KDE icon + cursor theme configured"
    fi

    # Aplicar cursor en sesión activa (|| true — puede fallar en headless)
    plasma-apply-cursortheme WhiteSur-cursors 2>&1 | tee -a "$LOG_FILE" \
        || warn "plasma-apply-cursortheme returned non-zero (normal fuera de sesión gráfica)"

    ok "Icons and cursors installed (WhiteSur)"
}

# ── Módulo 7: Window decorations ─────────────────────────────────────────────
# Aurorae WhiteSur + botones en la izquierda (estilo macOS: cerrar/min/max).
# El tema Aurorae se instala con WhiteSur-kde (módulo 4).
apply_window_decorations() {
    step "Window decorations — Aurorae WhiteSur + macOS button layout"

    if command -v kwriteconfig6 &>/dev/null; then
        # Seleccionar el backend Aurorae para las decoraciones de ventana
        kwriteconfig6 --file kwinrc \
            --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae

        # Tema específico dentro de Aurorae
        kwriteconfig6 --file kwinrc \
            --group org.kde.kdecoration2 --key theme __aurorae__svg__WhiteSur

        # Layout de botones estilo macOS: cierre/minimizar/maximizar a la IZQUIERDA
        # Códigos: X=close, I=minimize, A=maximize, M=menu, S=on-all-desktops
        kwriteconfig6 --file kwinrc \
            --group org.kde.kdecoration2 --key ButtonsOnLeft "XIA"
        kwriteconfig6 --file kwinrc \
            --group org.kde.kdecoration2 --key ButtonsOnRight ""

        info "Aurorae WhiteSur decoration and macOS button layout configured"
    else
        warn "kwriteconfig6 not found — skipping window decoration config"
    fi

    # Recargar KWin para aplicar sin cerrar sesión
    [[ -n "$QDBUS" ]] && "$QDBUS" org.kde.KWin /KWin reconfigure 2>/dev/null \
        || warn "KWin reconfigure skipped (QDBUS not available or headless)"

    ok "Window decorations applied (Aurorae WhiteSur, macOS left buttons)"
}

# ── Módulo 8: Wallpapers ─────────────────────────────────────────────────────
# Instala la colección WhiteSur-wallpapers y establece uno como fondo de Plasma.
install_wallpapers() {
    step "Wallpapers — WhiteSur"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' RETURN

    info "Cloning WhiteSur-wallpapers..."
    git clone --depth=1 --branch "$WHITESUR_WALLPAPERS_REF" https://github.com/vinceliuice/WhiteSur-wallpapers.git \
        "$tmp_dir/WhiteSur-wallpapers" 2>&1 | tee -a "$LOG_FILE"

    # El repo usa install-wallpapers.sh o install.sh según la versión del upstream
    local install_script
    if [[ -f "$tmp_dir/WhiteSur-wallpapers/install-wallpapers.sh" ]]; then
        install_script="install-wallpapers.sh"
    else
        install_script="install.sh"
    fi

    info "Installing WhiteSur wallpapers..."
    bash "$tmp_dir/WhiteSur-wallpapers/$install_script" 2>&1 | tee -a "$LOG_FILE" \
        || warn "wallpaper install returned non-zero"

    # Establecer un wallpaper por defecto en Plasma (|| true — requiere sesión gráfica activa)
    # El install.sh copia los wallpapers a ~/Pictures/WhiteSur o /usr/share/wallpapers/WhiteSur
    local wallpaper_path
    wallpaper_path="${HOME}/Pictures/WhiteSur/WhiteSur-light-nord.jpg"
    if [[ ! -f "$wallpaper_path" ]]; then
        # Fallback a la ubicación del sistema
        wallpaper_path="/usr/share/wallpapers/WhiteSur/contents/images/5120x2880.jpg"
    fi

    if [[ -f "$wallpaper_path" ]]; then
        plasma-apply-wallpaperimage "$wallpaper_path" 2>&1 | tee -a "$LOG_FILE" \
            || warn "plasma-apply-wallpaperimage returned non-zero (normal fuera de sesión gráfica)"
        info "Wallpaper set: $wallpaper_path"
    else
        warn "Default wallpaper path not found — set manually from System Settings"
    fi

    ok "WhiteSur wallpapers installed"
}

# ── Módulo 9: Panel layout ───────────────────────────────────────────────────
# Aplica el layout macOS (barra superior + dock inferior) vía Plasma Scripting API.
# El JS borra los paneles existentes y los reconstruye → idempotente pero DESTRUCTIVO
# para customizaciones manuales (se documenta en panel-layout.js y en el README).
apply_panel_layout() {
    step "Panel layout — macOS-style (top bar + bottom dock)"

    local panel_js="${CONFIGS_DIR}/kde/panel-layout.js"

    if [[ ! -f "$panel_js" ]]; then
        warn "panel-layout.js not found at $panel_js — skipping panel layout"
        return 0
    fi

    if [[ -z "$QDBUS" ]]; then
        warn "QDBUS not found — skipping panel layout (run --panel after login)"
        return 0
    fi

    info "Applying panel layout via Plasma Scripting API..."
    "$QDBUS" org.kde.plasma.shell /PlasmaShell \
        org.kde.PlasmaShell.evaluateScript \
        "$(cat "$panel_js")" 2>&1 | tee -a "$LOG_FILE" \
        || warn "evaluateScript returned non-zero (normal si Plasma no está corriendo)"

    ok "Panel layout applied (top menu bar + bottom icon dock)"
}

# ── Módulo 10: Konsole profile ───────────────────────────────────────────────
# Copia el perfil y el esquema de color MacOS a ~/.local/share/konsole/
# y configura Konsole para usarlo como perfil por defecto.
install_konsole_profile() {
    step "Konsole — MacOS profile + color scheme"

    local konsole_src="${CONFIGS_DIR}/kde/konsole"
    local konsole_dest="${HOME}/.local/share/konsole"

    mkdir -p "$konsole_dest"

    if [[ -f "${konsole_src}/MacOS.profile" ]]; then
        cp "${konsole_src}/MacOS.profile" "${konsole_dest}/MacOS.profile"
        info "Copied MacOS.profile → $konsole_dest/"
    else
        warn "MacOS.profile not found at $konsole_src — skipping"
        return 0
    fi

    if [[ -f "${konsole_src}/MacOS.colorscheme" ]]; then
        cp "${konsole_src}/MacOS.colorscheme" "${konsole_dest}/MacOS.colorscheme"
        info "Copied MacOS.colorscheme → $konsole_dest/"
    else
        warn "MacOS.colorscheme not found at $konsole_src — color scheme may be missing"
    fi

    # Establecer el perfil por defecto en konsolerc
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file konsolerc --group "Desktop Entry" \
            --key DefaultProfile MacOS.profile
        info "Konsole default profile set to MacOS.profile"
    else
        warn "kwriteconfig6 not found — set default profile manually in Konsole settings"
    fi

    ok "Konsole profile installed (MacOS)"
}

# ── run_all ──────────────────────────────────────────────────────────────────
run_all() {
    run_module "Repos (RPM Fusion + Flathub)" setup_repos
    run_module "Fonts"                         install_fonts
    run_module "Apps + dev + firewall"         install_apps
    run_module "WhiteSur themes"               install_whitesur_themes
    run_module "WhiteSur GTK theme"            install_whitesur_gtk
    run_module "Kvantum"                       apply_kvantum
    run_module "Icons + cursors"               install_icons_cursors
    run_module "Window decorations"            apply_window_decorations
    run_module "Wallpapers"                    install_wallpapers
    run_module "Panel layout"                  apply_panel_layout
    run_module "Konsole profile"               install_konsole_profile

    print_summary
}

# ── CLI args ─────────────────────────────────────────────────────────────────
case "${1:-}" in
    --all)         run_all ;;
    --repos)       run_module "Repos (RPM Fusion + Flathub)" setup_repos;         print_summary ;;
    --fonts)       run_module "Fonts"                         install_fonts;        print_summary ;;
    --apps)        run_module "Apps + dev + firewall"         install_apps;         print_summary ;;
    --themes)      run_module "WhiteSur themes"               install_whitesur_themes; print_summary ;;
    --gtk)         run_module "WhiteSur GTK theme"            install_whitesur_gtk; print_summary ;;
    --kvantum)     run_module "Kvantum"                       apply_kvantum;        print_summary ;;
    --icons)       run_module "Icons + cursors"               install_icons_cursors; print_summary ;;
    --decorations) run_module "Window decorations"            apply_window_decorations; print_summary ;;
    --wallpapers)  run_module "Wallpapers"                    install_wallpapers;   print_summary ;;
    --panel)       run_module "Panel layout"                  apply_panel_layout;   print_summary ;;
    --konsole)     run_module "Konsole profile"               install_konsole_profile; print_summary ;;
    *)
        echo "Usage: $0 [--all | --repos | --fonts | --apps | --themes | --gtk | --kvantum | --icons | --decorations | --wallpapers | --panel | --konsole]"
        exit 0
        ;;
esac
