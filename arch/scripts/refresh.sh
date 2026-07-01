#!/usr/bin/env bash
# ============================================================================
# Arch Linux — Refresh de configuraciones (KDE Plasma 6)
# Aplica cambios de configs sin reinstalar. Ideal para prueba y error.
# Uso: bash arch/scripts/refresh.sh [--all | --configs | --wallpapers]
# Sin argumentos = --all
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../../shared"
KDE_CONFIGS_DIR="${SHARED_DIR}/configs/kde"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${B}[INFO]${NC}  $1"; }
ok()    { echo -e "${G}[OK]${NC}    $1"; }
warn()  { echo -e "${Y}[WARN]${NC}  $1"; }

[[ ! -d "$KDE_CONFIGS_DIR" ]] && { echo -e "${R}[FAIL]${NC}  Configs no encontradas: $KDE_CONFIGS_DIR"; exit 1; }

# ── Konsole + Starship ────────────────────────────────────────────────────
refresh_configs() {
    info "Copiando perfil MacOS de Konsole..."
    local konsole_src="${KDE_CONFIGS_DIR}/konsole"
    local konsole_dest="${HOME}/.local/share/konsole"
    mkdir -p "$konsole_dest"
    cp "${konsole_src}/MacOS.profile"     "${konsole_dest}/MacOS.profile"
    cp "${konsole_src}/MacOS.colorscheme" "${konsole_dest}/MacOS.colorscheme"
    ok "Perfil Konsole (MacOS)"

    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file konsolerc --group "Desktop Entry" \
            --key DefaultProfile MacOS.profile
        ok "Perfil por defecto de Konsole: MacOS.profile"
    fi

    cp "${SHARED_DIR}/starship/starship.toml" "$HOME/.config/starship.toml"
    ok "starship.toml"
}

# ── Wallpaper ─────────────────────────────────────────────────────────────
refresh_wallpaper() {
    local wp="${HOME}/.local/share/wallpapers/MacSequoia-Light"
    if [[ ! -d "$wp" ]]; then
        warn "Wallpaper MacSequoia no instalado — corré: bash arch/scripts/postinstall.sh --macos-look"
        return
    fi
    if command -v plasma-apply-wallpaperimage &>/dev/null; then
        plasma-apply-wallpaperimage "$wp" 2>/dev/null \
            || warn "wallpaper apply non-zero (normal sin sesión gráfica)"
        ok "Wallpaper MacSequoia aplicado"
    else
        warn "plasma-apply-wallpaperimage no disponible — seteá el wallpaper a mano"
    fi
}

# ── Todo ──────────────────────────────────────────────────────────────────
refresh_all() {
    refresh_configs
    refresh_wallpaper
    echo ""
    ok "Refresh completo — Konsole, Starship y wallpaper actualizados"
    info "Para re-aplicar el look completo corré: bash arch/scripts/postinstall.sh --macos-look"
}

# ── CLI ───────────────────────────────────────────────────────────────────
case "${1:-}" in
    --configs)    refresh_configs ;;
    --wallpapers) refresh_wallpaper ;;
    --all|"")     refresh_all ;;
    *) echo "Uso: $0 [--all | --configs | --wallpapers]"; exit 1 ;;
esac
