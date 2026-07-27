#!/usr/bin/env bash
# install.sh — instala el gate de review en UN repo, por elección explícita.
#
# El enforcement es OPT-IN a propósito: no todo repo merece la ceremonia de
# review. Lo activás donde el costo de un bug supera el costo del proceso.
#
# Instala por SYMLINK, no por copia: así una corrección al hook se propaga sola
# a todos los repos donde esté activo, sin re-instalar uno por uno.
#
# Uso:
#   bash install.sh <repo> [<repo> ...]     # activar
#   bash install.sh --uninstall <repo>      # desactivar
#   bash install.sh --status <repo>         # ver si está activo
set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_SRC="$SRC_DIR/hooks"
HOOK_NAMES=(pre-commit pre-push)

usage() { echo "Uso: $0 [--uninstall|--status] <repo> [<repo> ...]" >&2; exit 2; }

resolve_repo() {
    cd "$1" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null
}

do_install() {
    local repo="$1" hooks_dir h target
    hooks_dir="$repo/.git/hooks"
    mkdir -p "$hooks_dir"
    for h in "${HOOK_NAMES[@]}"; do
        target="$hooks_dir/$h"
        # Se respalda TODO hook previo que no sea nuestro, sea archivo regular o
        # symlink. Antes el guard excluía los symlinks (`! -L`), así que un hook
        # de otro framework —husky, pre-commit, lefthook: todos instalan por
        # symlink— se pisaba SIN backup, y el uninstall no tenía qué restaurar.
        # Contradecía la garantía que este script documenta.
        if [[ -L "$target" ]]; then
            if [[ "$(readlink "$target")" != "$HOOKS_SRC/$h" ]]; then
                mv "$target" "$target.pre-review-gate.bak"
                echo "    hook previo (symlink ajeno) guardado como $h.pre-review-gate.bak"
            fi
        elif [[ -e "$target" ]]; then
            mv "$target" "$target.pre-review-gate.bak"
            echo "    hook previo guardado como $h.pre-review-gate.bak"
        fi
        ln -sfn "$HOOKS_SRC/$h" "$target"
        chmod +x "$HOOKS_SRC/$h"
    done
    echo "  ✓ gate ACTIVO en $repo"
    echo "    tope de intentos: $(git -C "$repo" config --get reviewGate.maxAttempts 2>/dev/null || echo '3 (default)')"
}

do_uninstall() {
    local repo="$1" hooks_dir h target
    hooks_dir="$repo/.git/hooks"
    for h in "${HOOK_NAMES[@]}"; do
        target="$hooks_dir/$h"

        # Solo se desinstala lo NUESTRO. Antes borraba cualquier symlink en esa
        # ruta sin mirar a dónde apuntaba: desinstalar el gate se llevaba puesto
        # el hook de otra herramienta, y sin backup que restaurar.
        if [[ -L "$target" && "$(readlink "$target")" != "$HOOKS_SRC/$h" ]]; then
            echo "    ⚠ $h es un symlink ajeno ($(readlink "$target")) — se deja intacto" >&2
            continue
        fi
        [[ -L "$target" ]] && rm -f "$target"

        # El restore no pisa lo que haya quedado en la ruta: si algo la ocupa,
        # el backup se conserva en disco en vez de destruir al ocupante.
        if [[ -e "$target.pre-review-gate.bak" ]]; then
            if [[ -e "$target" || -L "$target" ]]; then
                echo "    ⚠ $h ocupado por otro hook — el backup queda en $h.pre-review-gate.bak" >&2
            else
                mv "$target.pre-review-gate.bak" "$target" \
                    && echo "    hook previo restaurado: $h"
            fi
        fi
    done
    echo "  ✓ gate DESACTIVADO en $repo"
}

do_status() {
    local repo="$1" hooks_dir h active=0
    hooks_dir="$repo/.git/hooks"
    for h in "${HOOK_NAMES[@]}"; do
        if [[ -L "$hooks_dir/$h" ]] && [[ "$(readlink "$hooks_dir/$h")" == "$HOOKS_SRC/$h" ]]; then
            active=$((active + 1))
        fi
    done
    if [[ $active -eq ${#HOOK_NAMES[@]} ]]; then
        echo "  ✓ ACTIVO   $repo"
    elif [[ $active -gt 0 ]]; then
        echo "  ~ PARCIAL  $repo ($active/${#HOOK_NAMES[@]} hooks)"
    else
        echo "  ✗ inactivo $repo"
    fi
}

action="install"
case "${1:-}" in
    --uninstall) action="uninstall"; shift ;;
    --status)    action="status";    shift ;;
    --help|-h)   usage ;;
    "")          usage ;;
esac

[[ $# -ge 1 ]] || usage

rc=0
for arg in "$@"; do
    repo=$(resolve_repo "$arg") || { echo "  ✗ '$arg' no es un repositorio git" >&2; rc=1; continue; }
    case "$action" in
        install)   do_install   "$repo" ;;
        uninstall) do_uninstall "$repo" ;;
        status)    do_status    "$repo" ;;
    esac
done
exit $rc
