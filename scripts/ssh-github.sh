#!/usr/bin/env bash
# ============================================================================
# GitHub SSH — genera una llave ed25519 para autenticar git push sin tokens
# ----------------------------------------------------------------------------
# distrobox monta $HOME dentro de cada contenedor, así que ~/.ssh (la llave y
# el config) queda disponible automáticamente en todas tus "VMs". No hay que
# copiar nada: generás una vez en el host y funciona en todos lados.
#
# Uso: bash scripts/ssh-github.sh [opciones]
#   --email <correo>     Comentario de la llave (default: usuario@hostname)
#   --passphrase         Pide passphrase (más seguro; requiere ssh-agent en
#                        cada distrobox). Default: sin passphrase (frictionless)
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
USE_PASSPHRASE=false
SWITCH_REMOTE="ask"   # ask | yes | no

while [[ $# -gt 0 ]]; do
    case "$1" in
        --email)            EMAIL="${2:-}"; shift 2 ;;
        --passphrase)       USE_PASSPHRASE=true; shift ;;
        --switch-remote)    SWITCH_REMOTE="yes"; shift ;;
        --no-switch-remote) SWITCH_REMOTE="no"; shift ;;
        *) fail "Opción desconocida: $1" ;;
    esac
done

command -v ssh-keygen &>/dev/null || fail "ssh-keygen no encontrado — instalá 'openssh': sudo pacman -S openssh"

COMMENT="${EMAIL:-$(whoami)@$(hostnamectl --static 2>/dev/null || hostname)}"

# ── 1. Generar la llave ─────────────────────────────────────────────────────
step "1/4 — Llave SSH ed25519"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ -f "$KEY" ]]; then
    warn "Ya existe $KEY — la reutilizo (no la sobreescribo)"
else
    info "Generando llave para: $COMMENT"
    if $USE_PASSPHRASE; then
        ssh-keygen -t ed25519 -C "$COMMENT" -f "$KEY"
    else
        ssh-keygen -t ed25519 -C "$COMMENT" -f "$KEY" -N ""
        warn "Llave SIN passphrase (cómodo para compartir con distrobox)."
        warn "Si querés agregarle una después: ssh-keygen -p -f $KEY"
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

# ── 3. Agente + clave pública ───────────────────────────────────────────────
step "3/4 — ssh-agent + clave pública"

if [[ -z "${SSH_AUTH_SOCK:-}" ]] || ! ssh-add -l &>/dev/null; then
    eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
fi
ssh-add "$KEY" 2>/dev/null && ok "Llave cargada en ssh-agent" || warn "No se pudo cargar en ssh-agent (no es crítico)"

PUB="$(cat "$KEY.pub")"

# Copiar al portapapeles si hay herramienta disponible
if command -v wl-copy &>/dev/null; then
    printf '%s' "$PUB" | wl-copy && ok "Clave pública copiada al portapapeles (wl-copy)"
elif command -v xclip &>/dev/null; then
    printf '%s' "$PUB" | xclip -selection clipboard && ok "Clave pública copiada al portapapeles (xclip)"
else
    warn "No hay wl-copy/xclip — copiá la clave a mano"
fi

echo ""
echo -e "${C}Tu clave pública:${NC}"
echo "$PUB"
echo ""
echo -e "${Y}Pegala en GitHub → https://github.com/settings/ssh/new${NC}"
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
info "distrobox: la llave en ~/.ssh ya está disponible dentro de tus contenedores."
