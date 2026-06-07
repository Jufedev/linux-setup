#!/usr/bin/env bash
# ============================================================================
# GitHub SSH — genera una llave ed25519 para autenticar git push sin tokens
# ----------------------------------------------------------------------------
# distrobox monta $HOME dentro de cada contenedor, así que ~/.ssh (la llave y
# el config) queda disponible automáticamente en todas tus "VMs". No hay que
# copiar nada: generás una vez en el host y funciona en todos lados.
#
# Por defecto la llave se protege con una passphrase ALEATORIA robusta que el
# script genera y muestra al final junto con la pública, para que la guardes en
# tu gestor de contraseñas. Como la llave tiene passphrase, dentro de distrobox
# usás ssh-agent (ver README, sección Distrobox).
#
# Uso: bash shared/ssh-github.sh [opciones]
#   --email <correo>     Comentario de la llave (default: usuario@hostname)
#   --no-passphrase      Genera la llave SIN passphrase (frictionless, menos seguro)
#   --switch-remote      Cambia el origin de este repo de HTTPS a SSH sin preguntar
#   --no-switch-remote   No toca el remote
# ============================================================================
set -euo pipefail

# ── Colores ─────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${B}[INFO]${NC}  $1"; }
ok()    { echo -e "${G}[OK]${NC}    $1"; }
warn()  { echo -e "${Y}[WARN]${NC}  $1"; }
fail()  { echo -e "${R}[FAIL]${NC}  $1"; exit 1; }
step()  { echo -e "\n${C}━━━ $1 ━━━${NC}\n"; }

# ── Defaults / args ─────────────────────────────────────────────────────────
KEY="$HOME/.ssh/github_ed25519"
SSH_CONFIG="$HOME/.ssh/config"
EMAIL=""
PASSPHRASE_MODE="generate"   # generate | none
SWITCH_REMOTE="ask"          # ask | yes | no

while [[ $# -gt 0 ]]; do
    case "$1" in
        --email)            EMAIL="${2:-}"; shift 2 ;;
        --no-passphrase)    PASSPHRASE_MODE="none"; shift ;;
        --switch-remote)    SWITCH_REMOTE="yes"; shift ;;
        --no-switch-remote) SWITCH_REMOTE="no"; shift ;;
        *) fail "Opción desconocida: $1" ;;
    esac
done

command -v ssh-keygen &>/dev/null || fail "ssh-keygen no encontrado — instalá 'openssh': sudo pacman -S openssh"

# Passphrase aleatoria robusta (openssl si está; si no, /dev/urandom)
gen_passphrase() {
    if command -v openssl &>/dev/null; then
        openssl rand -base64 24
    else
        LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32; echo
    fi
}

COMMENT="${EMAIL:-$(whoami)@$(hostnamectl --static 2>/dev/null || hostname)}"

# ── 1. Generar la llave ─────────────────────────────────────────────────────
step "1/4 — Llave SSH ed25519"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

PASSPHRASE=""
if [[ -f "$KEY" ]]; then
    warn "Ya existe $KEY — la reutilizo (no la sobreescribo)"
    warn "Su passphrase es la que guardaste al crearla (el script no la puede mostrar)"
else
    info "Generando llave para: $COMMENT"
    if [[ "$PASSPHRASE_MODE" == "none" ]]; then
        ssh-keygen -t ed25519 -C "$COMMENT" -f "$KEY" -N "" >/dev/null
        warn "Llave SIN passphrase (cómodo, pero menos seguro)."
    else
        PASSPHRASE="$(gen_passphrase)"
        ssh-keygen -t ed25519 -C "$COMMENT" -f "$KEY" -N "$PASSPHRASE" >/dev/null
        ok "Llave creada con passphrase aleatoria robusta"
    fi
    chmod 600 "$KEY"
    chmod 644 "$KEY.pub"
    ok "Llave creada: $KEY"
fi

# ── 2. Configurar ~/.ssh/config ─────────────────────────────────────────────
step "2/4 — ~/.ssh/config"

touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

if grep -qE '^\s*Host\s+github\.com\b' "$SSH_CONFIG"; then
    ok "Ya hay un bloque para github.com — no lo toco"
else
    cat >> "$SSH_CONFIG" <<EOF

Host github.com
    HostName github.com
    User git
    IdentityFile ${KEY}
    IdentitiesOnly yes
    AddKeysToAgent yes
EOF
    ok "Bloque github.com agregado a $SSH_CONFIG"
fi

# ── 3. ssh-agent + salida (pública + passphrase) ────────────────────────────
step "3/4 — Clave pública + passphrase"

# Aseguramos un ssh-agent corriendo. Con 'AddKeysToAgent yes' en el config, el
# primer push/verify carga la llave y te pide la passphrase una sola vez.
if [[ -z "${SSH_AUTH_SOCK:-}" ]] || ! ssh-add -l &>/dev/null; then
    eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
fi

PUB="$(cat "$KEY.pub")"

echo ""
echo -e "${C}════════════════════════════════════════════════════════════${NC}"
echo -e "${Y}  GUARDÁ ESTO EN TU GESTOR DE CONTRASEÑAS${NC}"
echo -e "${C}════════════════════════════════════════════════════════════${NC}"
if [[ -n "$PASSPHRASE" ]]; then
    echo -e "${Y}PASSPHRASE:${NC}"
    echo "  $PASSPHRASE"
    echo ""
fi
echo -e "${C}CLAVE PÚBLICA:${NC}"
echo "  $PUB"
echo -e "${C}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${Y}Pegá la CLAVE PÚBLICA en GitHub → https://github.com/settings/ssh/new${NC}"
echo "  Title: lo que quieras (ej: $(hostnamectl --static 2>/dev/null || hostname))"
echo "  Key type: Authentication Key"
echo ""
read -rp "Presioná ENTER cuando la hayas agregado en GitHub para verificar... " _

# ── 4. Remote del repo + verificación ───────────────────────────────────────
step "4/4 — Remote SSH + verificación"

# Cambiar el origin de HTTPS a SSH si corresponde
if git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --is-inside-work-tree &>/dev/null; then
    REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    CUR_URL="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || echo "")"

    if [[ "$CUR_URL" == https://github.com/* ]]; then
        SSH_URL="git@github.com:${CUR_URL#https://github.com/}"
        [[ "$SSH_URL" != *.git ]] && SSH_URL="${SSH_URL}.git"

        do_switch=false
        case "$SWITCH_REMOTE" in
            yes) do_switch=true ;;
            no)  info "Remote sin cambios (HTTPS): $CUR_URL" ;;
            ask)
                read -rp "¿Cambiar el origin a SSH? ($SSH_URL) (s/N): " ans
                [[ "$ans" == "s" || "$ans" == "S" ]] && do_switch=true
                ;;
        esac

        if $do_switch; then
            git -C "$REPO_DIR" remote set-url origin "$SSH_URL"
            ok "origin → $SSH_URL"
        fi
    elif [[ -n "$CUR_URL" ]]; then
        info "origin ya no es HTTPS: $CUR_URL"
    fi
fi

# Verificar autenticación (ssh -T devuelve 1 aunque sea exitoso)
info "Probando autenticación con GitHub..."
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    ok "¡Autenticación SSH con GitHub funcionando!"
else
    warn "GitHub respondió, pero no confirmó autenticación."
    warn "Si recién agregaste la clave, esperá unos segundos y probá: ssh -T git@github.com"
fi

echo ""
ok "Listo — ya podés hacer push por SSH, sin tokens."
info "distrobox: la llave en ~/.ssh ya está adentro de tus contenedores."
info "Como tiene passphrase, dentro del contenedor cargala una vez con ssh-agent:"
info "  eval \"\$(ssh-agent -s)\" && ssh-add ~/.ssh/github_ed25519   (ver README → Distrobox)"
