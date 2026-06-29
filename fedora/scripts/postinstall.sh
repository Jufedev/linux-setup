#!/usr/bin/env bash
# ============================================================================
# Fedora 44 + KDE Plasma 6 — Setup estilo macOS
# Ejecutar como usuario normal después del primer boot
# Uso: bash postinstall.sh [--all | --repos | --hardware | --fonts | --theme |
#          --macos-look | --desktop | --terminal | --launcher | --apps |
#          --wallpapers | --keyboard | --login | --debloat]
# Sin argumentos = muestra el uso
# ============================================================================
set -euo pipefail

# ── Colores ─────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${B}[INFO]${NC}  $1"; }
ok()    { echo -e "${G}[OK]${NC}    $1"; }
warn()  { echo -e "${Y}[WARN]${NC}  $1"; }
step()  { echo -e "\n${C}━━━ $1 ━━━${NC}\n"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/../configs"
SHARED_DIR="${SCRIPT_DIR}/../../shared"
VENDOR_DIR="${SCRIPT_DIR}/../vendor/plasma6macos"

# Log persistente (sobrevive reinicios — /tmp se borra al rebootear)
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/fedora-macos-setup.log"

# Tracking de fallos: un paquete o módulo que falla NO debe abortar todo el setup
FAILED_PKGS=()
FAILED_MODULES=()

[[ ! -d "$CONFIGS_DIR" ]] && { warn "Directorio de configs no encontrado: $CONFIGS_DIR — continuando de todos modos"; }

# ── Resolver qdbus6 ──────────────────────────────────────────────────────────
# Fedora puede tenerlo como qdbus6, qdbus-qt6 o qdbus según el build.
# Exportamos $QDBUS para que todos los módulos lo usen sin repetir esta lógica.
QDBUS=""
for _qd in qdbus6 qdbus-qt6 qdbus; do
    if command -v "$_qd" &>/dev/null; then
        QDBUS="$_qd"
        break
    fi
done
export QDBUS

# ── plasma6macos pack (vendorizado) ──────────────────────────────────────────
# El look del video ES el pack plasma6macos COMPLETO (autor: Lsteam). NO tiene
# versionado en la KDE Store → vive vendorizado en fedora/vendor/plasma6macos/
# (ver su ATTRIBUTION.md). El tema es MacSequoia + iconos MacTahoe (vinceliuice).
# Reemplazó por completo al stack WhiteSur. MacSequoia-Light es el default.
readonly MACOS_LNF="com.github.vinceliuice.MacSequoia-Light"

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

# Quita paquetes (debloat). Filtra a los que están instalados para ser idempotente
# (re-ejecutar no falla con "no packages marked for removal"), luego los saca en una
# sola transacción; si el batch falla, reintenta de a uno. dnf arrastra solo las
# dependencias que quedan huérfanas (clean_requirements_on_remove), no toca lo que
# siga siendo requerido por otro paquete.
dnf_remove() {
    local present=() pkg
    for pkg in "$@"; do
        rpm -q "$pkg" &>/dev/null && present+=("$pkg")
    done
    if [[ ${#present[@]} -eq 0 ]]; then
        info "Nada para quitar — los paquetes ya no están instalados"
        return 0
    fi
    info "Removing (dnf): ${present[*]}"
    if sudo dnf remove -y "${present[@]}" 2>&1 | tee -a "$LOG_FILE"; then
        return 0
    fi
    warn "dnf remove batch failed — retrying one by one..."
    for pkg in "${present[@]}"; do
        if ! sudo dnf remove -y "$pkg" 2>&1 | tee -a "$LOG_FILE"; then
            warn "Package failed to remove (dnf): $pkg"
            FAILED_PKGS+=("remove:$pkg")
        fi
    done
}

# Safeguard Blackwell: tras instalar el driver, confirma que quedó el módulo
# ABIERTO (akmod/kmod-nvidia-open) y no el PROPIETARIO (akmod/kmod-nvidia).
# En placas Blackwell (RTX 50) el propietario NO soporta el hardware → pantalla
# negra silenciosa. Si RPM Fusion tiene el open desincronizado del userspace,
# dnf puede arrastrar el propietario para satisfacer xorg-x11-drv-nvidia. Esto
# convierte ese fallo silencioso en una advertencia visible (y en el resumen).
verify_nvidia_open_kmod() {
    # La señal de peligro es la PRESENCIA del propietario, no la ausencia del open:
    # cuando RPM Fusion tiene el open desincronizado (open más viejo que el userspace),
    # dnf instala el open PERO arrastra akmod-nvidia (propietario) como dependencia
    # para igualar nvidia-kmod=<userspace>. Quedan los dos, y el propietario es el que
    # matchea el userspace → es el que cargaría → pantalla negra en Blackwell.
    local has_open="false" has_prop="false"
    { rpm -q akmod-nvidia-open || rpm -q kmod-nvidia-open; } &>/dev/null && has_open="true"
    { rpm -q akmod-nvidia      || rpm -q kmod-nvidia;       } &>/dev/null && has_prop="true"

    if [[ "$has_prop" == "true" ]]; then
        warn "⚠ El módulo NVIDIA PROPIETARIO (akmod/kmod-nvidia) quedó instalado."
        if [[ "$has_open" == "true" ]]; then
            warn "  Está JUNTO al abierto: RPM Fusion tiene el open desincronizado y dnf"
            warn "  arrastró el propietario para igualar la versión del userspace."
        fi
        warn "  En placas Blackwell (RTX 50) el propietario NO soporta el hardware → PANTALLA NEGRA."
        warn "  Comprobá con: rpm -q akmod-nvidia akmod-nvidia-open xorg-x11-drv-nvidia"
        warn "  Acción: esperá a que RPM Fusion sincronice el open con el userspace y reinstalá,"
        warn "  o excluí el propietario (dnf ... --exclude=akmod-nvidia,kmod-nvidia) asumiendo el fallo."
        FAILED_PKGS+=("nvidia-proprietary-kmod-present")
    elif [[ "$has_open" == "true" ]]; then
        ok "Solo el módulo NVIDIA ABIERTO instalado — correcto para Blackwell/RTX 50"
    else
        warn "No se detectó ningún kmod NVIDIA instalado — revisá la salida de dnf más arriba."
        FAILED_PKGS+=("nvidia-kmod-missing")
    fi
}

# Instala apps de Flathub. Mismo patrón batch→individual que dnf_install.
# NOTA: las operaciones flatpak a nivel sistema (remote-add e install) requieren
# un agente polkit. Corré los scripts desde la sesión de escritorio Plasma ya
# instalada (no por SSH/headless): es el flujo soportado y polkit pide la
# autorización. Sin sesión gráfica fallan con "not allowed for user".
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

# Asegura que el remote 'flathub' exista (idempotente con --if-not-exists).
# setup_repos (--repos) lo agrega, pero --apps puede ejecutarse standalone, así que
# install_apps también lo invoca para no fallar al instalar los navegadores.
ensure_flathub_remote() {
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo \
        2>&1 | tee -a "$LOG_FILE" || warn "Flathub remote add returned non-zero (may already exist)"
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
    echo "  • Log out and back in to see the full theme, panels and font changes"
    echo "  • If the macOS panels/dock look off, re-run: bash postinstall.sh --macos-look"
    echo "  • Minimal panel fallback (no pack): bash postinstall.sh --desktop"
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
    ensure_flathub_remote

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

    # Herramientas de captura de pantalla y contenedores + GNOME Calendar
    # (el calendario macOS-style del dock; su icono muestra la fecha del día).
    dnf_install \
        flameshot \
        podman \
        distrobox \
        gnome-calendar

    ok "flameshot + podman + distrobox + gnome-calendar installed"

    # Firewall — firewalld viene con el KDE spin. Su zona por defecto en Fedora
    # (FedoraWorkstation) deja ABIERTOS los puertos 1025-65535 entrantes; la
    # cambiamos a 'public' para igualar la postura de Arch (deny incoming).
    command -v firewall-cmd &>/dev/null || dnf_install firewalld
    if command -v firewall-cmd &>/dev/null; then
        info "Enabling firewalld..."
        sudo systemctl enable --now firewalld 2>&1 | tee -a "$LOG_FILE" \
            || warn "firewalld enable returned non-zero (may already be running)"

        info "Setting default zone to 'public' (deny incoming except ssh/dhcpv6/mdns)..."
        sudo firewall-cmd --set-default-zone=public 2>&1 | tee -a "$LOG_FILE" \
            || warn "could not set default zone to public"

        # Verificación real del estado vía exit code ('--state' devuelve 0 solo si corre).
        if sudo firewall-cmd --state &>/dev/null; then
            ok "Firewall (firewalld) ACTIVO — zona '$(sudo firewall-cmd --get-default-zone 2>/dev/null)'"
        else
            warn "firewalld instalado pero NO running — revisá: sudo firewall-cmd --state"
        fi
    else
        warn "firewalld no se instaló — el firewall NO quedó configurado"
    fi

    # Apps de Flatpak (navegadores — Flatpak es la forma recomendada en Fedora inmutable/atómica).
    # --apps puede correrse sin --repos, así que garantizamos el remote flathub antes de instalar.
    info "Installing browser Flatpaks..."
    ensure_flathub_remote
    flatpak_install com.google.Chrome com.microsoft.Edge

    ok "Apps, dev tools, and firewall configured"
}

# ── plasma6macos assets — iconos + cursores ──────────────────────────────────
# Iconos MacTahoe (lo que el look-and-feel MacSequoia referencia) + cursores
# WhiteSur-cursors (idem). Van a ~/.local/share/icons/. La SELECCIÓN del tema la
# hace apply_macos_config vía el look-and-feel.
install_macos_icons_cursors() {
    step "plasma6macos — iconos (MacTahoe) + cursores (WhiteSur)"
    local dest="${HOME}/.local/share/icons"
    mkdir -p "$dest"
    if _extract_vendor plasma6macos-icons.zip; then
        cp -rf "$_VENDOR_TMP"/. "$dest/"; rm -rf "$_VENDOR_TMP"
        info "Iconos MacTahoe instalados"
    fi
    if _extract_vendor plasma6macos-cursors.zip; then
        cp -rf "$_VENDOR_TMP"/. "$dest/"; rm -rf "$_VENDOR_TMP"
        info "Cursores WhiteSur instalados"
    fi
    command -v gtk-update-icon-cache &>/dev/null \
        && gtk-update-icon-cache -q "$dest/MacTahoe-light" 2>/dev/null || true
    ok "Iconos + cursores instalados"
}

# ── plasma6macos assets — fuentes ────────────────────────────────────────────
# Fuentes del pack (Adwaita Sans/Mono). Van a ~/.local/share/fonts/ + fc-cache.
install_macos_fonts() {
    step "plasma6macos — fuentes del pack"
    _extract_vendor plasma6macos-fonts.zip || return 0
    local src="$_VENDOR_TMP"
    trap 'rm -rf "${src:-}" 2>/dev/null || true' RETURN
    local dest="${HOME}/.local/share/fonts"
    mkdir -p "$dest"
    cp -rf "$src"/. "$dest/"
    command -v fc-cache &>/dev/null && fc-cache -f "$dest" >>"$LOG_FILE" 2>&1 || true
    ok "Fuentes del pack instaladas"
}

# ── plasma6macos assets — tema GTK ───────────────────────────────────────────
# Tema GTK MacTahoe (apps GTK3/GTK4). Va a ~/.local/share/themes/. La selección
# (GtkTheme) la hace apply_macos_config.
install_macos_gtk() {
    step "plasma6macos — tema GTK (MacTahoe)"
    _extract_vendor plasma6macos-gtk-theme.zip || return 0
    local src="$_VENDOR_TMP"
    trap 'rm -rf "${src:-}" 2>/dev/null || true' RETURN
    local dest="${HOME}/.local/share/themes"
    mkdir -p "$dest"
    cp -rf "$src"/. "$dest/"
    ok "Tema GTK MacTahoe instalado"
}

# ── plasma6macos assets — Kvantum ────────────────────────────────────────────
# Estilo de widgets Qt: Kvantum + tema MacSequoia. El pack pone widgetStyle=Darkly
# en su look-and-feel, pero Darkly NO se distribuye en el pack; usamos Kvantum
# MacSequoia (que sí viene y da los menús translúcidos del video). apply_macos_config
# fuerza widgetStyle=kvantum DESPUÉS de aplicar el look-and-feel.
install_macos_kvantum() {
    step "plasma6macos — Kvantum (MacSequoia widget style)"
    command -v kvantummanager &>/dev/null || dnf_install kvantum
    _extract_vendor plasma6macos-kvantum-config.zip || return 0
    local src="$_VENDOR_TMP"
    trap 'rm -rf "${src:-}" 2>/dev/null || true' RETURN
    local dest="${HOME}/.config/Kvantum"
    mkdir -p "$dest"
    cp -rf "$src"/. "$dest/"
    ok "Kvantum MacSequoia instalado"
}

# ── Módulo 9: Panel layout (FALLBACK procedural) ─────────────────────────────
# Layout macOS básico (barra + dock) vía Plasma Scripting API. Es el FALLBACK:
# --all usa install_macos_look (layout fiel del video). Esto queda como --desktop
# para quien quiera el layout mínimo sin el pack. El JS borra los paneles y los
# reconstruye → idempotente pero DESTRUCTIVO para customizaciones manuales.
configure_desktop() {
    step "Panel layout — macOS-style (top bar + bottom dock)"

    local panel_js="${CONFIGS_DIR}/kde/panel-layout.js"

    if [[ ! -f "$panel_js" ]]; then
        warn "panel-layout.js not found at $panel_js — skipping panel layout"
        return 0
    fi

    if [[ -z "$QDBUS" ]]; then
        warn "QDBUS not found — skipping panel layout (run --desktop after login)"
        return 0
    fi

    info "Applying panel layout via Plasma Scripting API..."
    "$QDBUS" org.kde.plasmashell /PlasmaShell \
        org.kde.PlasmaShell.evaluateScript \
        "$(cat "$panel_js")" 2>&1 | tee -a "$LOG_FILE" \
        || warn "evaluateScript returned non-zero (normal si Plasma no está corriendo)"

    ok "Panel layout applied (top menu bar + bottom icon dock)"
}

# ── Módulo 10: Konsole profile ───────────────────────────────────────────────
# Copia el perfil y el esquema de color MacOS a ~/.local/share/konsole/
# y configura Konsole para usarlo como perfil por defecto.
install_terminal() {
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

# ── Módulo 11: Keyboard layout ──────────────────────────────────────────────
configure_keyboard() {
    step "Keyboard layout — English intl (AltGr dead keys)"

    # Sesión KDE (kxkbrc)
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file kxkbrc --group Layout --key Use true
        kwriteconfig6 --file kxkbrc --group Layout --key LayoutList us
        kwriteconfig6 --file kxkbrc --group Layout --key VariantList altgr-intl
    else
        warn "kwriteconfig6 not found — skipping KDE keyboard config"
    fi

    # System-wide (login manager + fallback)
    sudo localectl set-x11-keymap us "" altgr-intl 2>&1 | tee -a "$LOG_FILE" \
        || warn "localectl set-x11-keymap failed"

    ok "Keyboard layout set (us, altgr-intl)"
}

# ── Módulo 13: GPU / NVIDIA ───────────────────────────────────────────────────
# Driver NVIDIA para placas dedicadas. Blackwell (RTX serie 50, ej. 5060 Ti)
# REQUIERE los módulos abiertos (akmod-nvidia-open); el módulo propietario clásico
# ya no soporta esta arquitectura. Detección por lspci; para testear en VM sin la
# placa real, forzá el branch con: FORCE_GPU=nvidia bash postinstall.sh --hardware
configure_hardware() {
    step "Hardware — microcode del CPU + driver de GPU"

    # Microcode: en Fedora el de AMD viene en linux-firmware; el de Intel en microcode_ctl.
    if grep -q "GenuineIntel" /proc/cpuinfo; then
        dnf_install microcode_ctl
    else
        info "Microcode AMD incluido en linux-firmware (nada que instalar)"
    fi

    command -v lspci &>/dev/null || dnf_install pciutils

    local has_nvidia="false"
    if [[ "${FORCE_GPU:-}" == "nvidia" ]]; then
        has_nvidia="true"
        warn "FORCE_GPU=nvidia — forzando el branch NVIDIA (modo test/VM, sin placa real)"
    elif lspci 2>/dev/null | grep -qi 'nvidia'; then
        has_nvidia="true"
    fi

    # AMD/Intel ya quedan cubiertos por Mesa de fábrica en Fedora — no hay nada que instalar.
    if [[ "$has_nvidia" != "true" ]]; then
        info "No se detectó GPU NVIDIA — Mesa ya cubre AMD/Intel en Fedora"
        ok "GPU configurada (sin NVIDIA)"
        return 0
    fi

    info "GPU NVIDIA detectada — instalando módulos abiertos (akmod-nvidia-open)"

    # akmod-nvidia-open vive en RPM Fusion nonfree (lo habilita setup_repos).
    # Validamos por si este módulo se corre suelto antes de --repos.
    if ! dnf repolist 2>/dev/null | grep -qi 'rpmfusion-nonfree'; then
        warn "RPM Fusion nonfree no parece habilitado — corré primero: bash postinstall.sh --repos"
    fi

    # Driver abierto + soporte CUDA/VAAPI. akmod construye el módulo contra cada
    # kernel instalado vía akmods + kernel-devel. NO usar akmod-nvidia (cerrado).
    dnf_install akmod-nvidia-open xorg-x11-drv-nvidia-cuda

    # Safeguard: confirmar que dnf no arrastró el módulo propietario en su lugar.
    verify_nvidia_open_kmod

    # Nouveau bloquea la init del módulo NVIDIA (pantalla negra) si llega a cargar.
    info "Blacklisting nouveau..."
    printf 'blacklist nouveau\noptions nouveau modeset=0\n' \
        | sudo tee /etc/modprobe.d/blacklist-nouveau.conf >/dev/null

    # KMS: nvidia-drm.modeset=1 es necesario para la sesión Wayland de KDE.
    # grubby --args es idempotente (no duplica el arg si ya está).
    if command -v grubby &>/dev/null; then
        info "Habilitando nvidia-drm.modeset=1 vía grubby..."
        sudo grubby --update-kernel=ALL --args="nvidia-drm.modeset=1" 2>&1 | tee -a "$LOG_FILE" \
            || warn "grubby falló al setear nvidia-drm.modeset"
    fi

    # Forzar el build del akmod ahora (en vez de esperar al próximo boot) y
    # regenerar el initramfs para que tome el blacklist de nouveau.
    info "Construyendo el módulo akmod (puede tardar unos minutos)..."
    sudo akmods --force 2>&1 | tee -a "$LOG_FILE" || warn "akmods --force devolvió error (puede completarse en el boot)"
    sudo dracut --force 2>&1 | tee -a "$LOG_FILE" || warn "dracut --force falló"

    # Secure Boot: un módulo sin firmar no carga. Avisamos, no lo resolvemos solos
    # (firmar requiere enrolar una MOK con reboot interactivo).
    if command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
        warn "Secure Boot ACTIVO — el módulo NVIDIA no cargará sin firma."
        warn "  Opción A (simple): deshabilitá Secure Boot en BIOS."
        warn "  Opción B: firmá el módulo (kmodgenca -a && mokutil --import). Ver README."
    fi

    ok "GPU NVIDIA configurada — reiniciá y verificá con: nvidia-smi"
}

# ── plasma6macos: el "look del video" ────────────────────────────────────────
# Estos módulos aplican el pack plasma6macos (MacSequoia + plasmoides custom +
# layout exacto + efectos KWin + login). Corren DESPUÉS de WhiteSur: WhiteSur
# aporta GTK/Kvantum/iconos/cursores (también macOS), y MacSequoia pisa el estilo
# Plasma + Aurorae + el layout de paneles para quedar idéntico al video.

# Extrae un zip vendorizado del pack a un tmp dir. Deja la ruta en $_VENDOR_TMP.
# Devuelve 1 (sin abortar) si el asset no está o falla la extracción.
_VENDOR_TMP=""
_extract_vendor() {
    local zip_name="$1"
    local zip_path="${VENDOR_DIR}/${zip_name}"
    _VENDOR_TMP=""
    if [[ ! -f "$zip_path" ]]; then
        warn "Asset vendorizado no encontrado: $zip_path — salteando"
        return 1
    fi
    command -v unzip &>/dev/null || dnf_install unzip
    _VENDOR_TMP="$(mktemp -d)"
    if ! unzip -q -o "$zip_path" -d "$_VENDOR_TMP" >>"$LOG_FILE" 2>&1; then
        warn "Falló la extracción de $zip_name"
        rm -rf "$_VENDOR_TMP"; _VENDOR_TMP=""
        return 1
    fi
    return 0
}

# Plasmoides custom: Tahoe Launcher (botón de apps), KdeControlStation, kMenu (),
# weather y title-bar. Se copian a ~/.local/share/plasma/plasmoids/ (idempotente).
install_macos_plasmoids() {
    step "plasma6macos — plasmoides (Launchpad, Control Center, , weather)"
    _extract_vendor plasma6macos-plasmoids.zip || return 0
    local src="$_VENDOR_TMP"
    trap 'rm -rf "${src:-}" 2>/dev/null || true' RETURN

    local dest="${HOME}/.local/share/plasma/plasmoids"
    mkdir -p "$dest"
    if [[ -d "$src/plasmoids" ]]; then
        cp -rf "$src/plasmoids/." "$dest/"
        ok "Plasmoides instalados en $dest"
    else
        warn "El archivo no contiene plasmoids/ — nada que copiar"
    fi
}

# Tema MacSequoia: desktoptheme (estilo Plasma) + Aurorae (deco) + color-schemes +
# look-and-feel + wallpapers. Va a ~/.local/share/ (idempotente).
install_macos_plasma_theme() {
    step "plasma6macos — tema MacSequoia (Plasma + Aurorae + color schemes)"
    _extract_vendor plasma6macos-plasma-theme.zip || return 0
    local src="$_VENDOR_TMP"
    trap 'rm -rf "${src:-}" 2>/dev/null || true' RETURN

    local share="${HOME}/.local/share"
    mkdir -p "$share/plasma/desktoptheme" "$share/plasma/look-and-feel" \
             "$share/aurorae/themes" "$share/color-schemes" "$share/wallpapers"
    [[ -d "$src/plasma/desktoptheme"  ]] && cp -rf "$src/plasma/desktoptheme/."  "$share/plasma/desktoptheme/"
    [[ -d "$src/plasma/look-and-feel" ]] && cp -rf "$src/plasma/look-and-feel/." "$share/plasma/look-and-feel/"
    [[ -d "$src/aurorae/themes"       ]] && cp -rf "$src/aurorae/themes/."       "$share/aurorae/themes/"
    [[ -d "$src/color-schemes"        ]] && cp -rf "$src/color-schemes/."        "$share/color-schemes/"
    [[ -d "$src/wallpapers"           ]] && cp -rf "$src/wallpapers/."           "$share/wallpapers/"
    ok "Tema MacSequoia instalado"
}

# Efectos KWin (blur, kinetic), scripts y tabbox + el plugin de wallpaper con blur.
# Quedan disponibles; se activan al recargar KWin / volver a entrar.
install_macos_kwin_effects() {
    step "plasma6macos — efectos KWin (blur, kinetic) + tabbox"
    _extract_vendor plasma6macos-kwin-effect.zip || return 0
    local src="$_VENDOR_TMP"
    trap 'rm -rf "${src:-}" 2>/dev/null || true' RETURN

    local share="${HOME}/.local/share"
    mkdir -p "$share/kwin/effects" "$share/kwin/scripts" "$share/kwin/tabbox" "$share/plasma/wallpapers"
    [[ -d "$src/kwin/effects" ]] && cp -rf "$src/kwin/effects/." "$share/kwin/effects/"
    [[ -d "$src/kwin/scripts" ]] && cp -rf "$src/kwin/scripts/." "$share/kwin/scripts/"
    [[ -d "$src/kwin/tabbox"  ]] && cp -rf "$src/kwin/tabbox/."  "$share/kwin/tabbox/"
    [[ -d "$src/wallpapers"   ]] && cp -rf "$src/wallpapers/."   "$share/plasma/wallpapers/"
    [[ -n "$QDBUS" ]] && "$QDBUS" org.kde.KWin /KWin reconfigure 2>/dev/null || true
    ok "Efectos KWin instalados (se aplican al recargar KWin / re-login)"
}

# Aplica el layout EXACTO del pack (su appletsrc, variante neon = la más cercana a
# upstream, con dev.xarbit.appgrid → TahoeLauncher) + el look-and-feel MacSequoia.
# Reemplaza al panel-layout.js procedural (que queda como fallback vía --desktop).
# Hace backup del layout actual una sola vez antes de pisarlo.
apply_macos_layout() {
    step "plasma6macos — layout de paneles (barra + dock) + look MacSequoia"

    local appletsrc="${CONFIGS_DIR}/kde/plasma6macos/plasma-org.kde.plasma.desktop-appletsrc"
    if [[ ! -f "$appletsrc" ]]; then
        warn "Layout no encontrado: $appletsrc — salteando"
        return 0
    fi

    local target="${HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc"
    mkdir -p "${HOME}/.config"
    if [[ -f "$target" && ! -f "${target}.pre-macos.bak" ]]; then
        cp "$target" "${target}.pre-macos.bak"
        info "Backup del layout previo → ${target}.pre-macos.bak"
    fi
    cp "$appletsrc" "$target"
    info "Layout plasma6macos aplicado"

    # Look-and-feel MacSequoia (estilo Plasma + esquema de color + iconos MacTahoe +
    # Aurorae + cursor en un paso).
    if command -v plasma-apply-lookandfeel &>/dev/null; then
        plasma-apply-lookandfeel -a "$MACOS_LNF" 2>&1 | tee -a "$LOG_FILE" \
            || warn "plasma-apply-lookandfeel devolvió non-zero (normal sin sesión gráfica)"
    fi

    # Overrides DESPUÉS del look-and-feel (el LnF setea widgetStyle=Darkly, que no
    # distribuimos): forzamos Kvantum MacSequoia + tema GTK MacTahoe.
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file kdeglobals --group KDE     --key widgetStyle kvantum
        kwriteconfig6 --file kdeglobals --group General --key GtkTheme MacTahoe-Light

        # macOS: ocultar la barra de título de las ventanas maximizadas (los botones
        # y el nombre ya viven en la barra superior fija vía application-title-bar).
        # BorderlessMaximizedWindows es nativo de KWin; el script 'truely-maximized'
        # (del pack) hace lo mismo de forma más completa — lo activamos también.
        kwriteconfig6 --file kwinrc --group Windows --key BorderlessMaximizedWindows true
        kwriteconfig6 --file kwinrc --group Plugins --key truely-maximizedEnabled true
    fi
    command -v kvantummanager &>/dev/null \
        && kvantummanager --set MacSequoia 2>&1 | tee -a "$LOG_FILE" || true

    # Wallpaper MacSequoia (instalado por install_macos_plasma_theme).
    if command -v plasma-apply-wallpaperimage &>/dev/null; then
        plasma-apply-wallpaperimage "${HOME}/.local/share/wallpapers/MacSequoia-Light" 2>&1 \
            | tee -a "$LOG_FILE" || warn "wallpaper apply non-zero (normal sin sesión gráfica)"
    fi
    [[ -n "$QDBUS" ]] && "$QDBUS" org.kde.KWin /KWin reconfigure 2>/dev/null || true

    # Recargar plasmashell para tomar el nuevo appletsrc. Solo con sesión gráfica;
    # headless avisa que hay que volver a entrar.
    if [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] && command -v kquitapp6 &>/dev/null; then
        info "Reiniciando plasmashell para cargar el layout..."
        kquitapp6 plasmashell 2>/dev/null || true
        sleep 1
        if command -v kstart &>/dev/null; then
            (kstart plasmashell >/dev/null 2>&1 &)
        else
            (setsid plasmashell >/dev/null 2>&1 &)
        fi

        # Esperar a que plasmashell vuelva y ajustar la geometría de los paneles
        # (dock flotante/centrado + barra superior más fina) vía scripting API —
        # esas props no se setean confiablemente desde el appletsrc estático.
        local geo="${CONFIGS_DIR}/kde/plasma6macos/panel-geometry.js"
        if [[ -n "$QDBUS" && -f "$geo" ]]; then
            local _i
            for _i in $(seq 1 20); do
                "$QDBUS" org.kde.plasmashell /PlasmaShell \
                    org.kde.PlasmaShell.evaluateScript "0" &>/dev/null && break
                sleep 1
            done
            "$QDBUS" org.kde.plasmashell /PlasmaShell \
                org.kde.PlasmaShell.evaluateScript "$(cat "$geo")" 2>&1 \
                | tee -a "$LOG_FILE" || warn "no se pudo ajustar la geometría de los paneles"
        fi
        ok "Layout aplicado — plasmashell reiniciado"
    else
        warn "Sin sesión gráfica — cerrá sesión y volvé a entrar (después: bash postinstall.sh --macos-look para la geometría)"
    fi
}

# Aplica el wallpaper MacSequoia (lo instala install_macos_plasma_theme). Existe
# como módulo suelto por paridad con Arch (--wallpapers).
set_macos_wallpaper() {
    step "Wallpaper — MacSequoia"
    local wp="${HOME}/.local/share/wallpapers/MacSequoia-Light"
    [[ -d "$wp" ]] || install_macos_plasma_theme
    if command -v plasma-apply-wallpaperimage &>/dev/null; then
        plasma-apply-wallpaperimage "$wp" 2>&1 | tee -a "$LOG_FILE" \
            || warn "wallpaper apply non-zero (normal sin sesión gráfica)"
        ok "Wallpaper MacSequoia aplicado"
    else
        warn "plasma-apply-wallpaperimage no disponible — seteá el wallpaper a mano"
    fi
}

# Umbrella del look macOS del video (pack plasma6macos COMPLETO). Primero los
# assets (iconos/fuentes/gtk/kvantum/plasmoides/tema/kwin), después la config
# (apply_macos_layout: look-and-feel + overrides + wallpaper + layout). Cada
# sub-paso corre aislado vía run_module para que un fallo no tumbe al resto.
install_macos_look() {
    run_module "Iconos + cursores (MacTahoe)" install_macos_icons_cursors
    run_module "Fuentes del pack"             install_macos_fonts
    run_module "Tema GTK (MacTahoe)"          install_macos_gtk
    run_module "Kvantum (MacSequoia)"         install_macos_kvantum
    run_module "Plasmoides"                   install_macos_plasmoids
    run_module "Tema MacSequoia (Plasma)"     install_macos_plasma_theme
    run_module "Efectos KWin"                 install_macos_kwin_effects
    run_module "Layout + look (config)"       apply_macos_layout
}

# El "tema" en Fedora ES el pack plasma6macos completo (MacSequoia). Reemplazó al
# stack WhiteSur. --theme y --macos-look hacen lo mismo (alias por paridad con Arch).
install_theme() {
    install_macos_look
}

# Lanzador tipo Spotlight. KDE ya trae KRunner nativo — no hay nada que instalar.
# Existe por paridad con Arch (--launcher = Ulauncher).
install_launcher() {
    step "Launcher — KRunner (nativo)"
    ok "KRunner ya viene con KDE Plasma — nada que instalar (Meta o Alt+Space)"
}

# Login estilo macOS (del pack plasma6macos). ADITIVO Y REVERSIBLE a propósito:
# un greeter roto te deja afuera, así que NO tocamos el manager ni autologin —
# solo seteamos el wallpaper del greeter (drop-in) o, en spins con SDDM, el tema.
#
# Fedora 44 KDE: Plasma Login Manager (plasmalogin) → drop-in en
#   /etc/plasmalogin.conf.d/ + wallpaper en /var/lib/plasmalogin/wallpapers/.
# Otras spins: SDDM → tema tahoe-sddm en /usr/share/sddm/themes/.
# Para revertir: borrá el drop-in 95-macos-login.conf (y, en SDDM, Current=).
apply_login() {
    step "Login — look macOS (plasma6macos, aditivo)"
    _extract_vendor plasma6macos-sddm.zip || return 0
    local src="$_VENDOR_TMP"
    trap 'rm -rf "${src:-}" 2>/dev/null || true' RETURN

    local bg="$src/tahoe-sddm/background.jpg"

    if [[ -d /etc/plasmalogin.conf.d ]] || command -v plasma-login-manager &>/dev/null \
       || systemctl list-unit-files 2>/dev/null | grep -qi 'plasma-login-manager'; then
        info "Plasma Login Manager detectado — seteando wallpaper del greeter"
        # Instalar el wallpaper que referencia el conf del pack.
        if [[ -f "$bg" ]]; then
            sudo install -Dm644 "$bg" /var/lib/plasmalogin/wallpapers/Plasma-Tahoe 2>&1 | tee -a "$LOG_FILE" \
                || warn "no se pudo instalar el wallpaper del greeter"
        fi
        # Drop-in SOLO con el wallpaper (sin [Autologin], sin tocar el manager).
        sudo install -d /etc/plasmalogin.conf.d
        printf '[Greeter][Wallpaper][org.kde.image][General]\nImage=file:///var/lib/plasmalogin/wallpapers/Plasma-Tahoe\n' \
            | sudo tee /etc/plasmalogin.conf.d/95-macos-login.conf >/dev/null \
            && ok "Login (Plasma Login Manager) — wallpaper macOS aplicado" \
            || warn "no se pudo escribir el drop-in del greeter"

    elif command -v sddm &>/dev/null || [[ -d /usr/share/sddm/themes ]]; then
        info "SDDM detectado — instalando tema tahoe-sddm"
        [[ -d "$src/tahoe-sddm"      ]] && sudo cp -rf "$src/tahoe-sddm"      /usr/share/sddm/themes/ 2>&1 | tee -a "$LOG_FILE"
        [[ -d "$src/tahoe-sddm-dark" ]] && sudo cp -rf "$src/tahoe-sddm-dark" /usr/share/sddm/themes/ 2>&1 | tee -a "$LOG_FILE"
        sudo install -d /etc/sddm.conf.d
        printf '[Theme]\nCurrent=tahoe-sddm\n' | sudo tee /etc/sddm.conf.d/95-macos-login.conf >/dev/null \
            && ok "Login (SDDM) — tema tahoe-sddm aplicado" \
            || warn "no se pudo escribir la config de SDDM"
    else
        warn "No se detectó un login manager soportado — login sin cambios"
    fi
}

# ── Módulo: Debloat (Fedora-only, OPT-IN) ────────────────────────────────────
# Quita apps preinstaladas de la KDE Spin que no encajan en un desktop estilo
# macOS minimal. NO corre en --all (es destructivo: saca Firefox, LibreOffice y
# la suite PIM). dnf arrastra solo las dependencias que quedan huérfanas.
# Lista validada en una VM Fedora KDE 44: no toca Plasma core (plasma-desktop,
# kwin, plasma-login-manager) ni el stack del setup (dolphin, konsole, okular,
# gwenview, ark, kcalc, discover, kde-connect, kwallet). ~200 paquetes, ~1 GiB.
debloat_system() {
    step "Debloat — quitar apps preinstaladas de la KDE Spin"

    dnf_remove \
        kpat kmines kmahjongg \
        kontact kmail korganizer kaddressbook akregator \
        akonadi-import-wizard grantlee-editor pim-data-exporter pim-sieve-editor \
        dragon elisa-player kamoso neochat krfb krdc \
        plasma-welcome mediawriter qrca kmouth skanpage \
        gnome-abrt setroubleshoot spectacle firefox \
        kolourpaint kcharselect khelpcenter \
        libreoffice-core

    ok "Debloat completo — apps innecesarias removidas"
}

# ── run_all ──────────────────────────────────────────────────────────────────
run_all() {
    run_module "Repos (RPM Fusion + Flathub)" setup_repos
    run_module "Hardware (microcode + GPU)"   configure_hardware
    run_module "Fonts (Cascadia + emoji)"     install_fonts
    run_module "Terminal (Konsole)"           install_terminal
    run_module "Launcher (KRunner native)"    install_launcher
    run_module "Apps + dev + firewall"        install_apps
    install_macos_look  # pack plasma6macos COMPLETO: MacSequoia + iconos + gtk + kvantum + plasmoides + layout
    run_module "Login (look macOS)"           apply_login
    run_module "Keyboard"                     configure_keyboard

    print_summary
}

# ── CLI args ─────────────────────────────────────────────────────────────────
case "${1:-}" in
    --all)        run_all ;;
    --repos)      run_module "Repos (RPM Fusion + Flathub)" setup_repos;       print_summary ;;
    --hardware)   run_module "Hardware (microcode + GPU)"   configure_hardware; print_summary ;;
    --fonts)      run_module "Fonts"                        install_fonts;      print_summary ;;
    --theme)      install_theme;                                                print_summary ;;
    --macos-look) install_macos_look;                                           print_summary ;;
    --desktop)    run_module "Desktop (panel-layout.js fallback)" configure_desktop; print_summary ;;
    --terminal)   run_module "Terminal (Konsole)"           install_terminal;   print_summary ;;
    --launcher)   run_module "Launcher (KRunner native)"    install_launcher;   print_summary ;;
    --apps)       run_module "Apps + dev + firewall"        install_apps;       print_summary ;;
    --wallpapers) run_module "Wallpaper (MacSequoia)"       set_macos_wallpaper; print_summary ;;
    --keyboard)   run_module "Keyboard"                     configure_keyboard; print_summary ;;
    --login)      run_module "Login (look macOS)"           apply_login;        print_summary ;;
    --debloat)    run_module "Debloat (Fedora-only)"        debloat_system;     print_summary ;;
    *)
        echo "Usage: $0 [--all | --repos | --hardware | --fonts | --theme | --macos-look | --desktop | --terminal | --launcher | --apps | --wallpapers | --keyboard | --login | --debloat]"
        exit 0
        ;;
esac
