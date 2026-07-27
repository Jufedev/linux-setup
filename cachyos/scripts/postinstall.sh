#!/usr/bin/env bash
# ============================================================================
# CachyOS + KDE — Post-instalación
# Ejecutar como usuario normal después del primer boot
# Uso: bash postinstall.sh [--all | --apps | --firewall]
# Sin argumentos = menú interactivo
#
# Este script es DELIBERADAMENTE chico. CachyOS ya trae de fábrica casi todo lo
# que los setups de Arch y Fedora de este repo tenían que construir a mano
# (driver NVIDIA vía chwd, blacklist de nouveau vía nvidia-utils, KDE, fuentes,
# paru, ufw). Acá solo queda lo que la distro NO hace. Ver README.md → "Lo que
# este setup NO hace".
# ============================================================================
set -euo pipefail

# ── Colores ─────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${B}[INFO]${NC}  $1"; }
ok()    { echo -e "${G}[OK]${NC}    $1"; }
warn()  { echo -e "${Y}[WARN]${NC}  $1"; }
step()  { echo -e "\n${C}━━━ $1 ━━━${NC}\n"; }

# paru y pacman rechazan correr como root, y los archivos que crea el script
# quedarían de root. Va PRIMERO, antes de tocar el disco: si la guarda va después
# del mkdir del log, con `sudo --preserve-env=HOME` ya se creó un directorio de
# root en el $HOME del usuario antes de abortar.
if [[ $EUID -eq 0 ]]; then
    echo -e "${R}[ERROR]${NC} No corras este script como root ni con sudo."
    echo "        Corrélo como tu usuario normal; pide sudo cuando lo necesita."
    exit 1
fi

# Log persistente (sobrevive reinicios — /tmp se borra al rebootear)
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/cachyos-setup.log"

# Tracking de fallos: un paquete o módulo que falla NO debe abortar todo el setup
FAILED_PKGS=()
FAILED_MODULES=()

# ── Helpers ────────────────────────────────────────────────────────────────
# Actualiza el sistema UNA vez por ejecución, y solo cuando algo va a instalar de
# verdad (el menú y los errores de uso no deben pedir sudo).
#
# Se usa -Syu y NO -Sy a propósito: sincronizar la base de datos sin actualizar el
# sistema y después instalar paquetes nuevos contra un índice más nuevo es un
# "partial upgrade", que Arch documenta como NO soportado y puede romper librerías
# compartidas. El script de arch/ podía usar -Sy porque su módulo --cachyos hacía
# el -Syu; acá ese módulo no existe, así que el upgrade tiene que pasar por acá.
_PACMAN_SYNCED=0
pacman_sync() {
    if [[ $_PACMAN_SYNCED -eq 1 ]]; then
        return 0
    fi
    info "Actualizando el sistema (pacman -Syu) — puede tardar unos minutos..."
    if sudo pacman -Syu --noconfirm 2>&1 | tee -a "$LOG_FILE" >/dev/null; then
        ok "Sistema actualizado"
        _PACMAN_SYNCED=1
        return 0
    fi
    warn "pacman -Syu falló (log: $LOG_FILE)"
    return 1
}

# Estrategia: intentar el batch (rápido, resuelve dependencias juntas). Si falla,
# reintentar paquete por paquete para que UN paquete roto no arrastre al resto.
# Retorna no-cero si algún paquete quedó sin instalar: sin eso, el módulo que la
# llama informa "OK" aunque falte algo que declaró imprescindible.
pac_install() {
    # Instalar sobre un sistema a medio actualizar es el escenario de partial
    # upgrade — se prefiere no instalar nada antes que dejar el sistema mezclado.
    if ! pacman_sync; then
        warn "No se instala nada sobre un sistema a medio actualizar — omitidos: $*"
        FAILED_PKGS+=("$@")
        return 1
    fi

    info "Instalando (pacman): $*"
    if sudo pacman -S --noconfirm --needed "$@" 2>&1 | tee -a "$LOG_FILE"; then
        return 0
    fi
    warn "Batch de pacman falló — reintentando uno por uno..."
    local pkg failed=0
    for pkg in "$@"; do
        if ! sudo pacman -S --noconfirm --needed "$pkg" 2>&1 | tee -a "$LOG_FILE"; then
            warn "Paquete falló (pacman): $pkg"
            FAILED_PKGS+=("$pkg")
            failed=1
        fi
    done
    return $failed
}

# CachyOS trae paru de fábrica, así que NO se bootstrapea ningún helper de AUR.
# Si no está, se registra el fallo y se sigue: es un paquete opcional, no vale
# compilar un helper por él. La alternativa manual va en el resumen final.
#
# ES INTERACTIVO A PROPÓSITO — sin --noconfirm y sin pipe a tee:
#   • Un PKGBUILD de AUR es código de la comunidad que se EJECUTA al compilar. El
#     prompt de paru es el único punto donde se puede mirar qué hace antes de que
#     corra. Es un paquete, una vez, con el usuario sentado adelante.
#   • Sin pipe porque paru necesita una TTY real para mostrar el PKGBUILD y
#     preguntar. Se registra el resultado en el log, no la salida completa.
aur_install() {
    if ! command -v paru &>/dev/null; then
        warn "paru no encontrado — se saltean los paquetes de AUR: $*"
        FAILED_PKGS+=("$@")
        return 1
    fi
    info "Instalando (AUR, paru): $* — te va a mostrar el PKGBUILD y preguntar"
    local pkg failed=0
    for pkg in "$@"; do
        if paru -S --needed "$pkg"; then
            echo "[OK] AUR: $pkg" >> "$LOG_FILE"
        else
            warn "Paquete falló (AUR): $pkg"
            echo "[FAIL] AUR: $pkg" >> "$LOG_FILE"
            FAILED_PKGS+=("$pkg")
            failed=1
        fi
    done
    return $failed
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

# ============================================================================
# MÓDULOS
# ============================================================================

# Lo único que CachyOS no trae y este equipo necesita.
#   podman + distrobox: el pipeline de shorts-generate corre dentro del
#     distrobox 'shorts'. Sin esto no hay proyecto.
#   microsoft-edge-stable-bin: navegador principal del usuario. Es el ÚNICO
#     paquete de AUR de todo el setup. Firefox ya lo instala CachyOS.
install_apps() {
    step "Apps — contenedores + navegador"

    # El estado de cada instalación se propaga al retorno del módulo. Si no,
    # run_module informa "Módulo OK: Apps" aunque podman —que este mismo comentario
    # declara imprescindible— no se haya instalado.
    local failed=0

    if pac_install podman distrobox; then
        ok "Podman + Distrobox instalados"
    else
        failed=1
    fi

    aur_install microsoft-edge-stable-bin || failed=1

    return $failed
}

# CachyOS instala ufw (subgrupo "firewall" del instalador) pero NO lo configura
# ni lo activa: queda inerte. Acá se lo endurece de verdad.
# Guardas explícitas a propósito: una feature de seguridad NO debe fallar en
# silencio (set -e está suprimido dentro de run_module).
configure_firewall() {
    step "Firewall — ufw (deny incoming, allow outgoing)"

    command -v ufw &>/dev/null || pac_install ufw

    if ! command -v ufw &>/dev/null; then
        warn "ufw no se instaló — el firewall NO quedó configurado"
        return 1
    fi

    # Cada comando que falla marca el módulo como fallido. Antes solo warneaban y
    # el módulo seguía hacia el 'ok' final: se podía anunciar "deny incoming" sin
    # que esa política se hubiera aplicado nunca.
    local failed=0
    sudo ufw default deny incoming  2>&1 | tee -a "$LOG_FILE" || { warn "ufw: falló 'default deny incoming'";  failed=1; }
    sudo ufw default allow outgoing 2>&1 | tee -a "$LOG_FILE" || { warn "ufw: falló 'default allow outgoing'"; failed=1; }
    # 'ufw --force enable' ya lo activa en boot (no hace falta systemctl enable).
    sudo ufw --force enable         2>&1 | tee -a "$LOG_FILE" || { warn "ufw: falló al habilitar";             failed=1; }

    # Verificación del ESTADO REAL, no del bit de encendido. 'status verbose'
    # imprime la línea "Default: deny (incoming), allow (outgoing), ...".
    # Chequear solo "Status: active" dejaba pasar el caso peligroso: ufw activo
    # con la política de entrada equivocada, anunciado como si estuviera bien.
    local ufw_status
    ufw_status="$(sudo ufw status verbose 2>/dev/null || true)"

    grep -qi '^Status: active' <<<"$ufw_status" \
        || { warn "Firewall (ufw) NO está activo — revisá: sudo ufw status verbose"; failed=1; }
    grep -qi '^Default:.*deny (incoming)' <<<"$ufw_status" \
        || { warn "Firewall (ufw): la política de ENTRADA no quedó en 'deny' — revisá: sudo ufw status verbose"; failed=1; }
    grep -qi '^Default:.*allow (outgoing)' <<<"$ufw_status" \
        || { warn "Firewall (ufw): la política de SALIDA no quedó en 'allow' — revisá: sudo ufw status verbose"; failed=1; }

    if [[ $failed -ne 0 ]]; then
        return 1
    fi

    ok "Firewall (ufw) ACTIVO y verificado — deny incoming, allow outgoing"
}

# ============================================================================
# MENÚ PRINCIPAL
# ============================================================================

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
        echo "  Paquete de AUR a mano:           paru -S <paquete>"
    fi

    echo ""
    echo -e "${G}Pasos finales:${NC}"
    echo "  • Verificá el driver antes de confiar:  nvidia-smi"
    echo "  • Verificá los snapshots:               snapper -c root list"
    echo "  • Distrobox del pipeline (con GPU):     distrobox create --nvidia ..."
    echo "    Ver README.md → '2. Después del primer boot' y '4. El distrobox del pipeline'"
    echo ""

    # Código de salida no-cero si hubo fallos (útil para scripts llamadores)
    if [[ ${#FAILED_MODULES[@]} -gt 0 || ${#FAILED_PKGS[@]} -gt 0 ]]; then
        return 1
    fi
}

run_all() {
    run_module "Apps (contenedores + navegador)" install_apps
    run_module "Firewall (ufw)"                  configure_firewall
    print_summary
}

show_menu() {
    echo ""
    echo -e "${C}CachyOS + KDE — post-instalación${NC}"
    echo ""
    echo "  1) Todo (--all)"
    echo "  2) Apps: podman + distrobox + Edge (--apps)"
    echo "  3) Firewall: endurecer ufw (--firewall)"
    echo "  0) Salir"
    echo ""
    read -rp "Opción: " opt
    case "$opt" in
        1) run_all ;;
        2) run_module "Apps (contenedores + navegador)" install_apps; print_summary ;;
        3) run_module "Firewall (ufw)"                  configure_firewall; print_summary ;;
        0) exit 0 ;;
        *) warn "Opción inválida"; exit 1 ;;
    esac
}

case "${1:-}" in
    --all)      run_all ;;
    --apps)     run_module "Apps (contenedores + navegador)" install_apps; print_summary ;;
    --firewall) run_module "Firewall (ufw)"                  configure_firewall; print_summary ;;
    "")         show_menu ;;
    *)
        echo "Uso: bash postinstall.sh [--all | --apps | --firewall]"
        exit 1
        ;;
esac
