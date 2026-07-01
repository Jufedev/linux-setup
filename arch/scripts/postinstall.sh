#!/usr/bin/env bash
# ============================================================================
# Arch Linux — Setup estilo macOS (KDE Plasma 6)
# Ejecutar como usuario normal después del primer boot
# Uso: bash postinstall.sh [--all | --repos | --hardware | --kde | --theme |
#          --macos-look | --fonts | --desktop | --terminal | --launcher |
#          --apps | --wallpapers | --keyboard | --login | --cachyos]
# Sin argumentos = menú interactivo
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
LOG_FILE="${LOG_DIR}/arch-macos-setup.log"

# Tracking de fallos: un paquete o módulo que falla NO debe abortar todo el setup
FAILED_PKGS=()
FAILED_MODULES=()

[[ ! -d "$KDE_CONFIGS_DIR" ]] && { warn "Directorio de configs no encontrado: $KDE_CONFIGS_DIR — continuando de todos modos"; }

# ── Sincronizar base de datos de pacman ───────────────────────────────────
info "Sincronizando base de datos de pacman..."
sudo pacman -Sy --noconfirm &>/dev/null
ok "Base de datos sincronizada"

# ── Resolver qdbus6 ──────────────────────────────────────────────────────────
# En Arch el binario Qt6 es qdbus6 (paquete qt6-tools, lo instala --kde); se
# contemplan los otros nombres por paridad con Fedora. Exportamos $QDBUS para
# que todos los módulos lo usen sin repetir esta lógica.
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
# setup de Fedora. El contrato del módulo está documentado en su header.
MACOS_PKG_INSTALL="pac_install"
# shellcheck source=../../shared/plasma6macos.sh
source "${SHARED_DIR}/plasma6macos.sh"

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
    echo "  • Cerrá y reabrí sesión para ver el tema, los paneles y las fuentes"
    echo "  • Si los paneles macOS quedaron raros, re-corré: bash postinstall.sh --macos-look"
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

# KDE Plasma 6 mínimo. Misma filosofía que el GNOME mínimo anterior: en vez del
# metapaquete plasma (~50 componentes), solo lo esencial para un desktop usable
# + los equivalentes KDE de las utilidades que ya instalábamos.
install_kde() {
    step "KDE Plasma 6 mínimo"

    # Core de Plasma + display manager. kdeplasma-addons trae widgets que usa el
    # layout del pack plasma6macos (ej. weather). qt6-tools trae qdbus6, que los
    # módulos de paneles necesitan para la Plasma Scripting API.
    pac_install \
        plasma-desktop \
        plasma-workspace \
        sddm \
        systemsettings \
        kscreen \
        plasma-nm \
        plasma-pa \
        powerdevil \
        xdg-desktop-portal-kde \
        kdeplasma-addons \
        qt6-tools

    # File manager + terminal
    pac_install dolphin konsole

    # Utilidades mínimas (equivalentes KDE del set GNOME que reemplazó este módulo)
    pac_install \
        xdg-user-dirs \
        ark \
        okular \
        gwenview \
        kcalc \
        partitionmanager \
        plasma-systemmonitor \
        kwallet-pam \
        kio-extras

    # Bluetooth (demonio + applet de Plasma)
    pac_install bluedevil bluez bluez-utils

    # Crear carpetas estándar (Documents, Downloads, Pictures, etc.)
    xdg-user-dirs-update

    sudo systemctl enable sddm
    sudo systemctl enable bluetooth
    ok "KDE Plasma mínimo instalado, SDDM y Bluetooth habilitados"
}

# ── Panel layout (FALLBACK procedural) ─────────────────────────────
# Layout macOS básico (barra + dock) vía Plasma Scripting API. Es el FALLBACK:
# --all usa install_macos_look (layout fiel del video). Esto queda como --desktop
# para quien quiera el layout mínimo sin el pack. El JS borra los paneles y los
# reconstruye → idempotente pero DESTRUCTIVO para customizaciones manuales.
configure_desktop() {
    step "Panel layout — estilo macOS (barra superior + dock inferior)"

    local panel_js="${KDE_CONFIGS_DIR}/panel-layout.js"

    if [[ ! -f "$panel_js" ]]; then
        warn "panel-layout.js no encontrado en $panel_js — salteando layout de paneles"
        return 0
    fi

    if [[ -z "$QDBUS" ]]; then
        warn "QDBUS no encontrado — salteando layout (corré --desktop después de loguearte en Plasma)"
        return 0
    fi

    info "Aplicando layout de paneles vía Plasma Scripting API..."
    "$QDBUS" org.kde.plasmashell /PlasmaShell \
        org.kde.PlasmaShell.evaluateScript \
        "$(cat "$panel_js")" 2>&1 | tee -a "$LOG_FILE" \
        || warn "evaluateScript devolvió non-zero (normal si Plasma no está corriendo)"

    ok "Layout de paneles aplicado (barra superior + dock de iconos)"
}

# ── Terminal ──────────────────────────────────────────────────────
# Konsole con el perfil MacOS compartido (mismo look que Fedora) + Zsh + Starship.
install_terminal() {
    step "Terminal (Konsole + Zsh + Starship)"

    pac_install konsole zsh starship zsh-autosuggestions zsh-syntax-highlighting

    # Perfil y esquema de color MacOS → ~/.local/share/konsole/
    local konsole_src="${KDE_CONFIGS_DIR}/konsole"
    local konsole_dest="${HOME}/.local/share/konsole"
    mkdir -p "$konsole_dest"

    if [[ -f "${konsole_src}/MacOS.profile" ]]; then
        cp "${konsole_src}/MacOS.profile" "${konsole_dest}/MacOS.profile"
        info "MacOS.profile copiado → $konsole_dest/"
    else
        warn "MacOS.profile no encontrado en $konsole_src — salteando perfil"
    fi

    if [[ -f "${konsole_src}/MacOS.colorscheme" ]]; then
        cp "${konsole_src}/MacOS.colorscheme" "${konsole_dest}/MacOS.colorscheme"
        info "MacOS.colorscheme copiado → $konsole_dest/"
    fi

    # Establecer el perfil por defecto en konsolerc
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file konsolerc --group "Desktop Entry" \
            --key DefaultProfile MacOS.profile
        info "Perfil por defecto de Konsole: MacOS.profile"
    else
        warn "kwriteconfig6 no encontrado — seleccioná el perfil MacOS a mano en Konsole"
    fi

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

# Lanzador tipo Spotlight. KDE ya trae KRunner nativo — no hay nada que instalar.
# El flag existe por paridad entre distros (antes en GNOME instalaba Ulauncher).
install_launcher() {
    step "Launcher — KRunner (nativo)"
    ok "KRunner ya viene con KDE Plasma — nada que instalar (Meta o Alt+Space)"
}

install_fonts() {
    step "Fuentes del sistema"

    # Inter: UI general (repo oficial). Cascadia Code Nerd Font (CaskaydiaCove):
    # terminal + glifos Nerd. Apple Color Emoji: emojis estilo macOS/iOS (build
    # para Linux, paquete AUR).
    pac_install inter-font ttf-cascadia-code-nerd
    aur_install ttf-apple-emoji

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

    # Aplicar fuentes en KDE via kwriteconfig6 (solo si está disponible)
    if command -v kwriteconfig6 &>/dev/null; then
        info "Configurando fuentes de KDE via kwriteconfig6..."
        # Fuente general: Inter 10pt
        kwriteconfig6 --file kdeglobals --group General \
            --key font "Inter,10,-1,5,50,0,0,0,0,0"
        # Fuente monospace: CaskaydiaCove Nerd Font 10pt (con glifos de iconos)
        kwriteconfig6 --file kdeglobals --group General \
            --key fixed "CaskaydiaCove Nerd Font,10,-1,5,50,0,0,0,0,0"
        ok "Config de fuentes KDE escrita — re-login para aplicarla del todo"
    else
        warn "kwriteconfig6 no encontrado — corré --fonts de nuevo con KDE instalado"
    fi

    ok "Fuentes instaladas"
}

install_apps() {
    step "Apps, seguridad y entorno de desarrollo"

    # Apps. gnome-calendar es el calendario macOS-style del dock (el layout del
    # pack lo fija como launcher y su icono muestra la fecha del día) — igual que
    # en Fedora.
    pac_install flameshot gnome-calendar
    aur_install google-chrome microsoft-edge-stable-bin

    # Firewall — deny incoming, allow outgoing. Guardas explícitas: una feature de
    # seguridad NO debe fallar en silencio (set -e está suprimido bajo run_module).
    pac_install ufw
    if command -v ufw &>/dev/null; then
        sudo ufw default deny incoming  2>&1 | tee -a "$LOG_FILE" || warn "ufw: falló 'default deny incoming'"
        sudo ufw default allow outgoing 2>&1 | tee -a "$LOG_FILE" || warn "ufw: falló 'default allow outgoing'"
        # 'ufw --force enable' ya activa el servicio en boot (no hace falta systemctl enable).
        sudo ufw --force enable         2>&1 | tee -a "$LOG_FILE" || warn "ufw: falló al habilitar"
        # Verificación real del estado (no asumir éxito).
        if sudo ufw status 2>/dev/null | grep -qi '^Status: active'; then
            ok "Firewall (ufw) ACTIVO — deny incoming, allow outgoing"
        else
            warn "Firewall (ufw) instalado pero NO activo — revisá: sudo ufw status"
        fi
    else
        warn "ufw no se instaló — el firewall NO quedó configurado"
    fi

    # Containers para desarrollo
    pac_install podman distrobox
    ok "Distrobox + Podman instalados"

    ok "Apps, seguridad y entorno de desarrollo listos"
}

# Login estilo macOS (del pack plasma6macos). ADITIVO Y REVERSIBLE a propósito:
# un greeter roto te deja afuera, así que NO tocamos autologin ni el manager —
# solo instalamos el tema tahoe-sddm y lo seleccionamos con un drop-in en
# /etc/sddm.conf.d/. Para revertir: borrá 95-macos-login.conf.
apply_login() {
    step "Login — look macOS (tahoe-sddm, aditivo)"

    if ! command -v sddm &>/dev/null && [[ ! -d /usr/share/sddm/themes ]]; then
        warn "SDDM no está instalado — corré primero: bash postinstall.sh --kde"
        return 0
    fi

    _extract_vendor plasma6macos-sddm.zip || return 0
    local src="$_VENDOR_TMP"
    trap 'rm -rf "${src:-}" 2>/dev/null || true' RETURN

    info "Instalando tema tahoe-sddm..."
    [[ -d "$src/tahoe-sddm"      ]] && sudo cp -rf "$src/tahoe-sddm"      /usr/share/sddm/themes/ 2>&1 | tee -a "$LOG_FILE"
    [[ -d "$src/tahoe-sddm-dark" ]] && sudo cp -rf "$src/tahoe-sddm-dark" /usr/share/sddm/themes/ 2>&1 | tee -a "$LOG_FILE"
    sudo install -d /etc/sddm.conf.d
    printf '[Theme]\nCurrent=tahoe-sddm\n' | sudo tee /etc/sddm.conf.d/95-macos-login.conf >/dev/null \
        && ok "Login (SDDM) — tema tahoe-sddm aplicado" \
        || warn "no se pudo escribir la config de SDDM"
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

    # Early KMS: módulos NVIDIA en el initramfs (requerido por la sesión Wayland de KDE).
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

# Layout de teclado: English intl (AltGr dead keys). Sesión KDE (kxkbrc) +
# system-wide (localectl). Mismo concepto y resultado que --keyboard de Fedora.
configure_keyboard() {
    step "Teclado — English intl (AltGr dead keys)"

    # Sesión KDE (kxkbrc)
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file kxkbrc --group Layout --key Use true
        kwriteconfig6 --file kxkbrc --group Layout --key LayoutList us
        kwriteconfig6 --file kxkbrc --group Layout --key VariantList altgr-intl
    else
        warn "kwriteconfig6 no encontrado — salteando config de teclado de KDE"
    fi

    # System-wide (login manager + fallback)
    sudo localectl set-x11-keymap us "" altgr-intl 2>&1 | tee -a "$LOG_FILE" \
        || warn "localectl set-x11-keymap falló"

    ok "Teclado configurado (us, altgr-intl)"
}

run_all() {
    ensure_yay

    # CachyOS PRIMERO: agrega los repos optimizados (x86-64-v3/v4) antes de instalar
    # nada, así KDE, mesa y el resto se bajan ya compilados para tu CPU.
    # El kernel BORE/EEVDF queda instalado y se activa al reiniciar.
    run_module "CachyOS (repos + kernel)"   install_cachyos_repos
    run_module "Repos (multilib)"           setup_repos
    run_module "Hardware (microcode + GPU)" install_hardware
    run_module "KDE Plasma base"            install_kde
    run_module "Fuentes"                    install_fonts
    run_module "Terminal (Konsole)"         install_terminal
    run_module "Launcher (KRunner nativo)"  install_launcher
    run_module "Apps + dev"                 install_apps
    install_macos_look  # pack plasma6macos COMPLETO: MacSequoia + iconos + gtk + kvantum + plasmoides + layout
    run_module "Login (look macOS)"         apply_login
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
        echo "  4) KDE Plasma base"
        echo "  5) Tema macOS (pack plasma6macos)"
        echo "  6) Fuentes"
        echo "  7) Escritorio (layout de paneles fallback)"
        echo "  8) Terminal (Konsole + Zsh + Starship)"
        echo "  9) Launcher (KRunner nativo)"
        echo "  a) Apps"
        echo "  w) Wallpaper (MacSequoia)"
        echo "  k) Teclado (us altgr-intl)"
        echo "  l) Login SDDM estilo macOS"
        echo "  c) CachyOS repos + kernel BORE (ya incluido en 'todo')"
        echo "  0) Salir"
        echo ""
        read -rp "Selecciona una opción: " choice

        case $choice in
            1) run_all; break ;;
            2) setup_repos; break ;;
            3) install_hardware; break ;;
            4) install_kde; break ;;
            5) install_macos_look; break ;;
            6) install_fonts; break ;;
            7) configure_desktop; break ;;
            8) install_terminal; break ;;
            9) install_launcher; break ;;
            a) install_apps; break ;;
            w) set_macos_wallpaper; break ;;
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
    --all)        run_all ;;
    --repos)      run_module "Repos (multilib)"           setup_repos;        print_summary ;;
    --hardware)   run_module "Hardware (microcode + GPU)" install_hardware;   print_summary ;;
    --kde)        run_module "KDE Plasma base"            install_kde;        print_summary ;;
    --theme)      install_theme;                                              print_summary ;;
    --macos-look) install_macos_look;                                         print_summary ;;
    --fonts)      ensure_yay; run_module "Fuentes"        install_fonts;      print_summary ;;
    --desktop)    run_module "Escritorio (panel-layout.js fallback)" configure_desktop; print_summary ;;
    --terminal)   run_module "Terminal (Konsole)"         install_terminal;   print_summary ;;
    --launcher)   run_module "Launcher (KRunner nativo)"  install_launcher;   print_summary ;;
    --apps)       ensure_yay; run_module "Apps + dev"     install_apps;       print_summary ;;
    --wallpapers) run_module "Wallpaper (MacSequoia)"     set_macos_wallpaper; print_summary ;;
    --keyboard)   run_module "Teclado"                    configure_keyboard; print_summary ;;
    --login)      run_module "Login (look macOS)"         apply_login;        print_summary ;;
    --cachyos)    run_module "CachyOS (repos + kernel)"   install_cachyos_repos; print_summary ;;
    "")           show_menu ;;
    *)            echo "Uso: $0 [--all|--repos|--hardware|--kde|--theme|--macos-look|--fonts|--desktop|--terminal|--launcher|--apps|--wallpapers|--keyboard|--login|--cachyos]"; exit 1 ;;
esac
