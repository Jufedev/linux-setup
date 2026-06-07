#!/usr/bin/env bash
# ============================================================================
# Fedora 42 + KDE Plasma 6 — Setup estilo macOS
# Ejecutar como usuario normal después del primer boot
# Uso: bash postinstall.sh [--all | --repos | --fonts | --apps | --themes |
#          --kvantum | --icons | --decorations | --wallpapers | --panel | --konsole]
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
    step "Fonts — Inter + JetBrains Mono + Noto Emoji"

    # NOTA: los nombres de paquete rsms-inter-fonts y jetbrains-mono-fonts-all
    # son los esperados para Fedora 42. Verificar con `dnf search inter fonts`
    # y `dnf search jetbrains` en la primera ejecución real si algo falla.
    dnf_install \
        rsms-inter-fonts \
        jetbrains-mono-fonts-all \
        google-noto-emoji-fonts

    # Aplicar fuentes en KDE via kwriteconfig6 (solo si está disponible)
    if command -v kwriteconfig6 &>/dev/null; then
        info "Configuring KDE fonts via kwriteconfig6..."
        # Fuente general: Inter 10pt
        kwriteconfig6 --file kdeglobals --group General \
            --key font "Inter,10,-1,5,50,0,0,0,0,0"
        # Fuente monospace: JetBrainsMono Nerd Font 10pt
        # NOTA: requiere instalar la variante Nerd Font por separado si el paquete
        # jetbrains-mono-fonts-all no la incluye. Ajustar el nombre de la fuente
        # si fc-list no muestra "JetBrainsMono Nerd Font".
        kwriteconfig6 --file kdeglobals --group General \
            --key fixed "JetBrains Mono,10,-1,5,50,0,0,0,0,0"
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

# ── Módulo 4: WhiteSur themes (STUB — Slice 3) ──────────────────────────────
install_whitesur_themes() {
    info "TODO: Slice 3 — WhiteSur Plasma/GTK/Kvantum themes"
    return 0
}

# ── Módulo 5: Kvantum (STUB — Slice 3) ──────────────────────────────────────
apply_kvantum() {
    info "TODO: Slice 3 — Kvantum WhiteSur widget style"
    return 0
}

# ── Módulo 6: Icons + cursors (STUB — Slice 3) ──────────────────────────────
install_icons_cursors() {
    info "TODO: Slice 3 — WhiteSur icons and cursors"
    return 0
}

# ── Módulo 7: Window decorations (STUB — Slice 3) ───────────────────────────
apply_window_decorations() {
    info "TODO: Slice 3 — Aurorae WhiteSur window decorations + macOS button layout"
    return 0
}

# ── Módulo 8: Wallpapers (STUB — Slice 3) ───────────────────────────────────
install_wallpapers() {
    info "TODO: Slice 3 — WhiteSur wallpapers"
    return 0
}

# ── Módulo 9: Panel layout (STUB — Slice 4) ─────────────────────────────────
apply_panel_layout() {
    info "TODO: Slice 4 — macOS-style panel layout via Plasma Scripting API"
    return 0
}

# ── Módulo 10: Konsole profile (STUB — Slice 4) ─────────────────────────────
install_konsole_profile() {
    info "TODO: Slice 4 — Konsole color scheme and profile"
    return 0
}

# ── run_all ──────────────────────────────────────────────────────────────────
run_all() {
    run_module "Repos (RPM Fusion + Flathub)" setup_repos
    run_module "Fonts"                         install_fonts
    run_module "Apps + dev + firewall"         install_apps
    run_module "WhiteSur themes"               install_whitesur_themes
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
    --kvantum)     run_module "Kvantum"                       apply_kvantum;        print_summary ;;
    --icons)       run_module "Icons + cursors"               install_icons_cursors; print_summary ;;
    --decorations) run_module "Window decorations"            apply_window_decorations; print_summary ;;
    --wallpapers)  run_module "Wallpapers"                    install_wallpapers;   print_summary ;;
    --panel)       run_module "Panel layout"                  apply_panel_layout;   print_summary ;;
    --konsole)     run_module "Konsole profile"               install_konsole_profile; print_summary ;;
    *)
        echo "Usage: $0 [--all | --repos | --fonts | --apps | --themes | --kvantum | --icons | --decorations | --wallpapers | --panel | --konsole]"
        exit 0
        ;;
esac
