#!/usr/bin/env bash
# ============================================================================
# Fedora 44 + KDE Plasma 6 — Setup estilo macOS
# Ejecutar como usuario normal después del primer boot
# Uso: bash postinstall.sh [--all | --repos | --hardware | --fonts | --theme |
#          --macos-look | --desktop | --terminal | --launcher | --apps |
#          --wallpapers | --keyboard | --login | --debloat | --verify-gpu]
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
SHARED_DIR="${SCRIPT_DIR}/../../shared"
KDE_CONFIGS_DIR="${SHARED_DIR}/configs/kde"
VENDOR_DIR="${SHARED_DIR}/vendor/plasma6macos"

# Log persistente (sobrevive reinicios — /tmp se borra al rebootear)
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/fedora-macos-setup.log"

# Tracking de fallos: un paquete o módulo que falla NO debe abortar todo el setup
FAILED_PKGS=()
FAILED_MODULES=()

[[ ! -d "$KDE_CONFIGS_DIR" ]] && { warn "Directorio de configs no encontrado: $KDE_CONFIGS_DIR — continuando de todos modos"; }

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

# ── Módulo compartido plasma6macos ───────────────────────────────────────────
# Las funciones del look macOS (install_macos_*, apply_macos_layout, install_theme,
# etc.) son distro-agnósticas y viven en shared/plasma6macos.sh — las comparte el
# setup de Arch. El contrato del módulo está documentado en su header.
MACOS_PKG_INSTALL="dnf_install"
# shellcheck source=../../shared/plasma6macos.sh
source "${SHARED_DIR}/plasma6macos.sh"

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

# Predicados puros del flavor de kmod (0 = presente). Existen para que tanto el
# reporte (verify_nvidia_open_kmod) como el VEREDICTO (verify_gpu_integrity)
# consulten la misma fuente: antes el veredicto ignoraba el flavor por completo.
nvidia_proprietary_kmod_present() {
    rpm -q akmod-nvidia &>/dev/null || rpm -q kmod-nvidia &>/dev/null
}

nvidia_open_kmod_present() {
    rpm -q akmod-nvidia-open &>/dev/null || rpm -q kmod-nvidia-open &>/dev/null
}

# Marca que el veredicto de flavor YA se imprimió en esta corrida. configure_hardware
# lo emite antes del gate (lo necesita para explicar un aborto) y verify_gpu_integrity
# lo emitiría otra vez al final de la MISMA corrida: sin este flag, `--hardware` imprime
# el bloque dos veces y empuja el tag duplicado a FAILED_PKGS.
NVIDIA_FLAVOR_REPORTED=0

verify_nvidia_open_kmod() {
    NVIDIA_FLAVOR_REPORTED=1
    # La señal de peligro es la PRESENCIA del propietario, no la ausencia del open:
    # cuando RPM Fusion tiene el open desincronizado (open más viejo que el userspace),
    # dnf instala el open PERO arrastra akmod-nvidia (propietario) como dependencia
    # para igualar nvidia-kmod=<userspace>. Quedan los dos, y el propietario es el que
    # matchea el userspace → es el que cargaría → pantalla negra en Blackwell.
    local has_open="false" has_prop="false"
    nvidia_open_kmod_present        && has_open="true"
    nvidia_proprietary_kmod_present && has_prop="true"

    if [[ "$has_prop" == "true" ]]; then
        warn "⚠ El módulo NVIDIA PROPIETARIO (akmod/kmod-nvidia) quedó instalado."
        if [[ "$has_open" == "true" ]]; then
            warn "  Está JUNTO al abierto: RPM Fusion tiene el open desincronizado y dnf"
            warn "  arrastró el propietario para igualar la versión del userspace."
        fi
        warn "  En placas Blackwell (RTX 50) el propietario NO soporta el hardware → PANTALLA NEGRA."
        warn "  Comprobá con: rpm -q akmod-nvidia akmod-nvidia-open xorg-x11-drv-nvidia"
        warn "  Acción: quitá el propietario (sudo dnf remove akmod-nvidia kmod-nvidia) e instalá"
        warn "  el par coherente del repo release:"
        warn "    sudo dnf install akmod-nvidia-open xorg-x11-drv-nvidia-cuda \\"
        warn "        --disablerepo=rpmfusion-nonfree-updates --exclude=akmod-nvidia,kmod-nvidia"
        FAILED_PKGS+=("nvidia-proprietary-kmod-present")
    elif [[ "$has_open" == "true" ]]; then
        ok "Solo el módulo NVIDIA ABIERTO instalado — correcto para Blackwell/RTX 50"
    else
        warn "No se detectó ningún kmod NVIDIA instalado — revisá la salida de dnf más arriba."
        FAILED_PKGS+=("nvidia-kmod-missing")
    fi
}

# ── Integridad del driver NVIDIA (gate anti-pantalla-negra) ──────────────────
# verify_nvidia_open_kmod mira el FLAVOR del rpm, pero no responde la otra
# pregunta que importa antes de reiniciar: ¿existe el módulo para los kernels
# que la máquina puede bootear?
#
# Por qué es crítico: en un desktop de una sola GPU la iGPU queda deshabilitada
# en BIOS (ver README). Si el initramfs sale con nouveau bloqueado y SIN módulo
# NVIDIA construido, el próximo boot se queda sin driver de video y no hay
# segunda salida para depurar. El build tiene que verificarse ANTES de tocar
# nada que apague nouveau.

# Lista los kernels que PODRÍAN bootear, no solo el que corre ahora. `--repos`
# ejecuta `dnf upgrade --refresh`, que puede instalar un kernel nuevo, y en
# `--all` eso pasa JUSTO ANTES de este módulo: mirar solo `uname -r` dejaría
# pasar un build que falló precisamente para el kernel que va a bootear.
list_bootable_kernels() {
    local d
    if rpm -q kernel-core &>/dev/null; then
        rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n'
        return 0
    fi
    for d in /usr/lib/modules/*/; do
        [[ -d "$d" ]] && basename "$d"
    done
    return 0
}

# Emite por stdout los kernels que NO tienen el módulo nvidia construido.
nvidia_kernels_missing_module() {
    local k
    while read -r k; do
        [[ -n "$k" ]] || continue
        modinfo -k "$k" nvidia &>/dev/null || printf '%s\n' "$k"
    done < <(list_bootable_kernels)
    return 0
}

# Gate: el módulo tiene que existir para TODOS los kernels booteables.
# FAIL-CLOSED: si no se puede enumerar ni un kernel, la lista de "faltantes" sale
# vacía y una comparación ingenua daría OK sin haber verificado NADA. Un falso OK
# acá apaga nouveau sin red, así que la ausencia de datos se trata como fallo.
#
# Alcance honesto: `modinfo` prueba que el archivo del módulo existe y parsea
# para ese kernel — NO que vaya a insertarse (Secure Boot o símbolos sin
# resolver pueden rechazarlo igual). Por eso el aviso de Secure Boot va aparte.
#
# Fuente ÚNICA del diagnóstico: emite el warn que corresponda y devuelve 0 solo
# si el módulo existe para todos los kernels booteables. La consultan el gate
# (configure_hardware), la auditoría (verify_gpu_integrity) y el predicado mudo
# de abajo: antes esta misma lógica estaba escrita tres veces y podían discrepar.
report_nvidia_module_built() {
    local kernels missing
    kernels=$(list_bootable_kernels)
    if [[ -z "$kernels" ]]; then
        warn "✗ No se pudo enumerar ningún kernel instalado — no se puede verificar el módulo."
        return 1
    fi
    missing=$(nvidia_kernels_missing_module)
    if [[ -n "$missing" ]]; then
        warn "✗ Falta el módulo nvidia para: $(echo "$missing" | tr '\n' ' ')"
        return 1
    fi
    return 0
}

# Predicado mudo, para los sitios que solo necesitan el booleano sin imprimir.
verify_nvidia_module_built() {
    report_nvidia_module_built &>/dev/null
}

# Deja la máquina booteable con nouveau (degradado pero CON imagen) en vez de
# sin driver. Es el rollback que se ejecuta solo si el módulo no está.
# Reporta el resultado REAL: un rollback a medias es más peligroso que ninguno,
# porque el usuario reiniciaría creyendo que está a salvo.
#
# ALCANCE: revierte para TODOS los kernels, no solo el que falló. Tiene que ser
# así porque `grubby --update-kernel=ALL` puso nvidia-drm.modeset=1 en todos:
# revertir uno solo dejaría el resto con KMS de NVIDIA y sin blacklist, que es
# el estado incoherente que causa pantalla negra. La contrapartida es real y se
# anuncia abajo: si la máquina YA venía funcionando con NVIDIA y falla el build
# de un kernel nuevo, este rollback también desconfigura el kernel que andaba.
rollback_nouveau_blacklist() {
    local rc=0
    warn "Revirtiendo los cambios que dejarían la máquina sin driver de video..."
    warn "  ALCANCE: se revierte en TODOS los kernels instalados, no solo el que falló."
    warn "  Si esta máquina ya arrancaba con NVIDIA, ese kernel también vuelve a nouveau:"
    warn "  el próximo boot tendrá imagen, pero SIN driver NVIDIA hasta re-correr --hardware."

    sudo rm -f /etc/modprobe.d/blacklist-nouveau.conf \
        || { warn "No se pudo borrar blacklist-nouveau.conf"; rc=1; }

    if command -v grubby &>/dev/null; then
        sudo grubby --update-kernel=ALL --remove-args="nvidia-drm.modeset=1" 2>&1 | tee -a "$LOG_FILE" \
            || { warn "grubby falló al quitar nvidia-drm.modeset"; rc=1; }
    fi

    # --regenerate-all: grubby de arriba toca TODOS los kernels, así que el
    # rollback tiene que alcanzar todos los initramfs, no solo el que corre.
    sudo dracut --force --regenerate-all 2>&1 | tee -a "$LOG_FILE" \
        || { warn "dracut --force --regenerate-all falló durante el rollback"; rc=1; }

    if [[ $rc -eq 0 ]]; then
        ok "nouveau reactivado — el próximo boot arranca con imagen (sin driver NVIDIA)"
    else
        warn "⚠ EL ROLLBACK FALLÓ — NO REINICIES todavía."
        warn "  El initramfs puede seguir sin nouveau: reiniciar así te deja sin video."
        warn "  Corregilo a mano y verificá que termine bien:"
        warn "    sudo rm -f /etc/modprobe.d/blacklist-nouveau.conf && sudo dracut --force --regenerate-all"
        FAILED_PKGS+=("nouveau-rollback-failed")
    fi
    return $rc
}

# Verificación de integridad post-instalación (y post-reboot). Es el módulo que
# faltaba: comprueba estado REAL, no qué dijo dnf. Ejecutable suelto con
# --verify-gpu para auditar la máquina en cualquier momento.
#
# NO imprime su propio banner: la invocan run_module (que ya emite "▶ label") y
# configure_hardware al final del módulo. Un step() acá duplicaba el encabezado
# en --verify-gpu y metía un tercer banner anidado a mitad de --hardware.
verify_gpu_integrity() {
    local problems=0

    # Guard de pciutils, igual que configure_hardware: --verify-gpu es ejecutable
    # suelto y puede correr en una máquina donde lspci no está instalado.
    # FAIL-CLOSED: sin lspci NO se puede afirmar que no hay GPU. Antes esta rama
    # se comía el "command not found" y devolvía 0 con "nada que verificar" — la
    # auditoría daba OK sin haber mirado nada, justo el fallo silencioso que este
    # módulo existe para evitar.
    if ! command -v lspci &>/dev/null; then
        warn "✗ lspci no está instalado (paquete pciutils) — no se puede verificar la GPU."
        warn "  Instalalo con: sudo dnf install pciutils"
        FAILED_PKGS+=("pciutils-missing")
        return 1
    fi

    if ! lspci 2>/dev/null | grep -qi 'nvidia'; then
        info "No hay GPU NVIDIA en el bus — nada que verificar"
        return 0
    fi

    # 1. Flavor correcto (abierto, nunca el propietario en Blackwell).
    #    verify_nvidia_open_kmod REPORTA pero siempre retorna 0, así que el
    #    veredicto consulta los predicados directo: si no, esta auditoría podría
    #    decir "OK" justo sobre el peligro que le da sentido a todo el módulo.
    #    Solo se reporta si nadie lo hizo ya en esta corrida (ver NVIDIA_FLAVOR_REPORTED):
    #    en --verify-gpu suelto imprime; dentro de --hardware ya lo emitió el gate.
    [[ "$NVIDIA_FLAVOR_REPORTED" == "1" ]] || verify_nvidia_open_kmod
    if nvidia_proprietary_kmod_present; then
        problems=$((problems + 1))
    elif ! nvidia_open_kmod_present; then
        problems=$((problems + 1))
    fi

    # 2. El módulo existe para TODOS los kernels booteables (no solo el corriente).
    #    Sin lista de kernels no hay verificación posible → se cuenta como problema.
    #    Mismo diagnóstico que consulta el gate (report_nvidia_module_built).
    if report_nvidia_module_built; then
        ok "Módulo nvidia construido para todos los kernels instalados"
    else
        problems=$((problems + 1))
    fi

    # 3. ¿Está cargado? (solo tiene sentido después de reiniciar)
    local nvidia_loaded="false"
    if lsmod | grep -q '^nvidia'; then
        nvidia_loaded="true"
        ok "Módulo nvidia CARGADO en el kernel"
    else
        warn "Módulo nvidia no cargado (normal si todavía no reiniciaste)"
    fi

    # 4. nouveau ocupando la placa. Pre-reboot SIEMPRE está cargado (es el que
    #    maneja tu pantalla ahora mismo): solo es un problema real si convive
    #    con el módulo NVIDIA ya cargado. Sin esta distinción, toda primera
    #    corrida exitosa daba un falso positivo.
    if lsmod | grep -q '^nouveau'; then
        if [[ "$nvidia_loaded" == "true" ]]; then
            warn "nouveau cargado JUNTO al módulo NVIDIA — conflicto real"
            problems=$((problems + 1))
        else
            info "nouveau todavía cargado (normal si no reiniciaste; se libera en el próximo boot)"
        fi
    fi

    # 5. El userspace responde (la prueba de fuego).
    #    `timeout`: contra un driver a medio cargar nvidia-smi puede colgarse en
    #    el ioctl y nunca devolver — justo el estado que esta herramienta existe
    #    para diagnosticar. Colgar la auditoría sería el peor resultado posible.
    if command -v nvidia-smi &>/dev/null; then
        local smi_rc=0
        timeout 15 nvidia-smi &>/dev/null || smi_rc=$?
        if [[ $smi_rc -eq 0 ]]; then
            ok "nvidia-smi responde — driver operativo"
        elif [[ $smi_rc -eq 124 ]]; then
            warn "✗ nvidia-smi se colgó (timeout 15s) — driver en mal estado, no solo ausente"
            problems=$((problems + 1))
        else
            warn "nvidia-smi existe pero falla (normal si todavía no reiniciaste)"
        fi
    else
        warn "nvidia-smi no está instalado — falta xorg-x11-drv-nvidia-cuda"
        problems=$((problems + 1))
    fi

    # 6. Coherencia peligrosa: nouveau bloqueado y sin módulo NVIDIA = sin video.
    if [[ -f /etc/modprobe.d/blacklist-nouveau.conf ]] && ! verify_nvidia_module_built; then
        warn "⚠ PELIGRO: nouveau está bloqueado y el módulo NVIDIA no existe."
        warn "  Reiniciar así te deja SIN driver de video y sin iGPU de respaldo."
        warn "  Rollback: sudo rm /etc/modprobe.d/blacklist-nouveau.conf && sudo dracut --force --regenerate-all"
        FAILED_PKGS+=("nvidia-unsafe-to-reboot")
        problems=$((problems + 1))
    fi

    if [[ $problems -eq 0 ]]; then
        ok "Integridad del driver NVIDIA: OK"
        return 0
    fi
    warn "Integridad del driver NVIDIA: $problems problema(s) — ver detalle arriba"
    return 1
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

# ── Repos ─────────────────────────────────────────────────────────
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

# ── Fuentes ────────────────────────────────────────────────────────
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

# ── Apps ───────────────────────────────────────────────────────────
install_apps() {
    step "Apps + dev tools + firewall"

    # Herramientas de captura de pantalla y contenedores + GNOME Calendar
    # (el calendario macOS-style del dock; su icono muestra la fecha del día).
    # lm_sensors expone la temperatura del CPU a KSystemStats → necesario para que
    # el sensor de temp de CPU aparezca en el Control Center (Flex Hub) y monitores.
    dnf_install \
        flameshot \
        podman \
        distrobox \
        gnome-calendar \
        lm_sensors

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

# ── Panel layout (FALLBACK procedural) ─────────────────────────────
# Layout macOS básico (barra + dock) vía Plasma Scripting API. Es el FALLBACK:
# --all usa install_macos_look (layout fiel del video). Esto queda como --desktop
# para quien quiera el layout mínimo sin el pack. El JS borra los paneles y los
# reconstruye → idempotente pero DESTRUCTIVO para customizaciones manuales.
configure_desktop() {
    step "Panel layout — macOS-style (top bar + bottom dock)"

    local panel_js="${KDE_CONFIGS_DIR}/panel-layout.js"

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

# ── Konsole profile ───────────────────────────────────────────────
# Copia el perfil y el esquema de color MacOS a ~/.local/share/konsole/
# y configura Konsole para usarlo como perfil por defecto.
install_terminal() {
    step "Konsole — MacOS profile + color scheme"

    local konsole_src="${KDE_CONFIGS_DIR}/konsole"
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

# ── Keyboard layout ──────────────────────────────────────────────
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

# ── GPU / NVIDIA ───────────────────────────────────────────────────
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
    # kernel instalado vía akmods + kernel-devel. El --exclude hornea la política
    # Blackwell: el kmod propietario (akmod/kmod-nvidia) no debe instalarse NUNCA.
    # Si RPM Fusion tiene el open desincronizado del userspace, dnf falla acá
    # RUIDOSAMENTE en vez de arrastrar el propietario (pantalla negra silenciosa).
    # No se usa dnf_install a propósito: su reintento paquete-por-paquete perdería
    # el --exclude y este install debe ser todo-o-nada.
    info "Installing (dnf): akmod-nvidia-open xorg-x11-drv-nvidia-cuda (sin kmod propietario)"
    if ! sudo dnf install -y --exclude=akmod-nvidia,kmod-nvidia \
            akmod-nvidia-open xorg-x11-drv-nvidia-cuda 2>&1 | tee -a "$LOG_FILE"; then
        warn "Instalación del driver falló — probable desync open/userspace en RPM Fusion."
        warn "Salida rápida (par coherente del repo release, sin fijar versiones):"
        warn "  sudo dnf install akmod-nvidia-open xorg-x11-drv-nvidia-cuda \\"
        warn "      --disablerepo=rpmfusion-nonfree-updates --exclude=akmod-nvidia,kmod-nvidia"
        warn "Un 'dnf upgrade' posterior te sube al par sincronizado cuando RPM Fusion lo arregle."
        warn "O esperá la resincronización y re-corré: bash postinstall.sh --hardware"
        FAILED_PKGS+=("akmod-nvidia-open")
    fi

    # Safeguard: confirmar que dnf no arrastró el módulo propietario en su lugar.
    verify_nvidia_open_kmod

    # ORDEN CRÍTICO: construir y VERIFICAR el módulo ANTES de apagar nouveau.
    # (Antes el blacklist se escribía primero y `akmods --force` solo advertía al
    # fallar: un build roto se horneaba igual en el initramfs y el siguiente boot
    # quedaba sin driver de video — sin iGPU de respaldo, sin forma de depurar.)
    info "Construyendo el módulo akmod (puede tardar unos minutos)..."
    sudo akmods --force 2>&1 | tee -a "$LOG_FILE" || warn "akmods --force devolvió error"

    # Secure Boot: un módulo sin firmar no carga. Se avisa ANTES del gate porque
    # explica por qué el módulo puede estar construido y aun así no funcionar.
    if command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
        warn "Secure Boot ACTIVO — el módulo NVIDIA no cargará sin firma."
        warn "  Opción A (simple): deshabilitá Secure Boot en BIOS."
        warn "  Opción B: firmá el módulo (kmodgenca -a && mokutil --import). Ver README."
    fi

    # ── GATE anti-pantalla-negra ──────────────────────────────────────────────
    # Si el módulo no quedó construido —o quedó el FLAVOR equivocado— NO se toca
    # nouveau y se aborta. Además se revierte cualquier blacklist que hubiera
    # dejado una corrida anterior, para que la máquina quede booteable con nouveau
    # en vez de sin driver.
    #
    # Por qué el flavor se verifica ACÁ y no solo en verify_gpu_integrity: esa
    # auditoría corre DESPUÉS del blacklist y del dracut, o sea después del punto
    # sin retorno. Y `modinfo` no alcanza como gate porque el módulo abierto y el
    # propietario se llaman IGUAL (`nvidia`): con el propietario instalado el
    # chequeo de existencia pasa limpio, y es justo el que deja pantalla negra en
    # Blackwell. Gate y auditoría consultan los mismos predicados a propósito.
    local gate_failed="false"

    if nvidia_proprietary_kmod_present; then
        warn "✗ El módulo NVIDIA PROPIETARIO (akmod/kmod-nvidia) está instalado."
        warn "  En placas Blackwell (RTX 50) NO soporta el hardware: bloquear nouveau"
        warn "  ahora deja PANTALLA NEGRA en el próximo boot. Ver el detalle más arriba."
        FAILED_PKGS+=("nvidia-gate-wrong-flavor")
        gate_failed="true"
    elif ! nvidia_open_kmod_present; then
        warn "✗ No hay ningún kmod NVIDIA instalado — no hay driver que reemplace a nouveau."
        FAILED_PKGS+=("nvidia-gate-no-kmod")
        gate_failed="true"
    fi

    if ! report_nvidia_module_built; then
        FAILED_PKGS+=("nvidia-module-build-failed")
        gate_failed="true"
    fi

    if [[ "$gate_failed" == "true" ]]; then
        warn "  NO se va a bloquear nouveau: reiniciar así te dejaría sin driver de video."
        if [[ -f /etc/modprobe.d/blacklist-nouveau.conf ]]; then
            rollback_nouveau_blacklist || warn "  El rollback no terminó limpio (ver arriba)."
        fi
        warn "  Revisá el log del build: $LOG_FILE  (y /var/cache/akmods/)"
        warn "  Causa típica: falta kernel-devel de ESE kernel, o RPM Fusion todavía no"
        warn "  lo soporta. Instalá los headers o re-corré --hardware tras un 'dnf upgrade'."
        return 1
    fi
    ok "Módulo nvidia ABIERTO construido y verificado para todos los kernels instalados"

    # A partir de acá el módulo EXISTE — recién ahora es seguro apagar nouveau.
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

    # Regenerar el initramfs para que tome el blacklist de nouveau. Si esto falla
    # el blacklist YA está escrito en disco: el initramfs viejo puede no coincidir
    # con la config, así que es un fallo que tiene que propagar, no un aviso.
    #
    # --regenerate-all (no solo --force): sin él dracut toca ÚNICAMENTE el kernel
    # que corre ahora, mientras `grubby --update-kernel=ALL` de arriba puso
    # nvidia-drm.modeset=1 en TODOS. Un kernel instalado por `dnf upgrade` —que
    # además pasa a ser el default de GRUB— conservaría su initramfs sin el
    # blacklist: nouveau carga temprano con nvidia-drm tomando KMS = pantalla negra.
    local dracut_rc=0
    sudo dracut --force --regenerate-all 2>&1 | tee -a "$LOG_FILE" || dracut_rc=1
    if [[ $dracut_rc -ne 0 ]]; then
        warn "dracut --force --regenerate-all falló tras escribir el blacklist de nouveau."
        rollback_nouveau_blacklist || warn "  El rollback tampoco terminó limpio."
        FAILED_PKGS+=("dracut-failed")
        return 1
    fi

    # Veredicto final: un solo mensaje coherente. Antes se imprimía "NO reinicies"
    # y "reiniciá" seguidos, y el non-zero se tragaba, así que run_module/
    # print_summary reportaban éxito aunque la integridad fallara.
    if verify_gpu_integrity; then
        ok "GPU NVIDIA configurada — reiniciá y verificá con: bash postinstall.sh --verify-gpu"
        return 0
    fi

    warn "GPU NVIDIA configurada CON OBSERVACIONES — revisalas ANTES de reiniciar."
    warn "  Re-auditá cuando las resuelvas: bash postinstall.sh --verify-gpu"
    return 1
}

# ── plasma6macos: el "look del video" ────────────────────────────────────────
# Los módulos que aplican el pack plasma6macos (install_macos_*, apply_macos_layout,
# set_macos_wallpaper, install_macos_look, install_theme) viven en el módulo
# compartido shared/plasma6macos.sh — se sourcea al inicio del script.

# Lanzador tipo Spotlight. KDE ya trae KRunner nativo — no hay nada que instalar.
# El flag existe por paridad con Arch, donde --launcher es el mismo no-op.
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
    --verify-gpu) run_module "Verificación de integridad (GPU)" verify_gpu_integrity; print_summary ;;
    *)
        echo "Usage: $0 [--all | --repos | --hardware | --fonts | --theme | --macos-look | --desktop | --terminal | --launcher | --apps | --wallpapers | --keyboard | --login | --debloat | --verify-gpu]"
        exit 0
        ;;
esac
