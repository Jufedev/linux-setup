#!/usr/bin/env bash
# review-cycle.sh — desbloqueo GUARDADO del ciclo de review de gentle-ai.
#
# EL PROBLEMA QUE RESUELVE
# Una lineage `escalated` es terminal: bloquea todo commit en el repo y el
# contrato prohíbe reabrirla. Eso es correcto — impide que el autor levante su
# propio rechazo. Pero deja a un agente desatendido parado hasta que aparezca un
# humano, aunque ya haya arreglado los hallazgos.
#
# LA REGLA QUE LO HACE SEGURO
# Archivar una lineage escalada se permite SOLO si el contenido cambió. El
# recibo trae `final_candidate_tree`, que es un hash de árbol de git: se compara
# contra el árbol actual del index. Si son iguales, el código NO se tocó desde el
# rechazo y volver a revisar sería tirar los dados de nuevo sobre lo mismo.
# Si difieren, es un cambio de scope legítimo y merece lineage nueva.
#
#   contenido igual    → RECHAZA  (sería lavar el veredicto)
#   contenido distinto → archiva  (arreglaste y volvés a someterte a review)
#
# CORTACIRCUITO
# Máximo N intentos por cambio lógico (mismo `base_tree`). Superado el tope, se
# detiene y espera a un humano: si tres rondas no convergieron, el problema no
# se arregla con una cuarta. Configurable con `git config reviewGate.maxAttempts`.
#
# TRAZA
# Cada archivado se registra en .git/gentle-ai/archived/AUDIT.log con los hashes,
# el número de intento y el tope vigente. Nada se borra: el recibo del rechazo se
# conserva completo. La traza es lo que hace auditable una corrida desatendida.
#
# Uso:
#   bash review-cycle.sh status  [repo]
#   bash review-cycle.sh unblock [repo]
set -uo pipefail

CMD="${1:-status}"
REPO="${2:-$PWD}"
REPO=$(cd "$REPO" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || {
    echo "✗ '$2' no es un repositorio git" >&2; exit 2; }

GA_DIR="$REPO/.git/gentle-ai"
TX_DIR="$GA_DIR/review-transactions/v2"
ARCHIVE_DIR="$GA_DIR/archived"
AUDIT_LOG="$ARCHIVE_DIR/AUDIT.log"

max_attempts() {
    local n
    n=$(git -C "$REPO" config --get reviewGate.maxAttempts 2>/dev/null) || n=""
    [[ "$n" =~ ^[0-9]+$ ]] && { echo "$n"; return; }
    echo 3
}

# Lee un campo del recibo de una lineage.
#
# FALLA CERRADO: devuelve 0 solo si el campo se leyó de verdad. Antes colapsaba
# "no se pudo leer" (recibo ausente, JSON corrupto, campo faltante) y "campo
# vacío" en el mismo string vacío, y eso rompía la garantía central de este
# script: en do_unblock, un `cand` vacío nunca puede igualar un hash de árbol,
# así que la rama que RECHAZA por contenido-igual quedaba inalcanzable y una
# lineage con recibo ilegible se archivaba sin comparar nada. El check
# anti-lavado fallaba ABIERTO, que es exactamente lo que promete impedir.
receipt_field() {
    local dir="$1" field="$2" out
    [[ -f "$dir/review-receipt.json" ]] || return 1
    # El path y el campo van por argv, no interpolados en el fuente de python:
    # así una comilla en la ruta no puede romper (ni inyectar en) el programa.
    out=$(python3 -c "
import json,sys
try:
    value = json.load(open(sys.argv[1])).get(sys.argv[2])
except Exception:
    sys.exit(1)
if value is None:
    sys.exit(1)
print(value)
" "$dir/review-receipt.json" "$field" 2>/dev/null) || return 1
    printf '%s\n' "$out"
}

# Lineages en estado terminal-escalado.
escalated_lineages() {
    [[ -d "$TX_DIR" ]] || return 0
    local d
    for d in "$TX_DIR"/*/; do
        [[ -d "$d" ]] || continue
        [[ "$(receipt_field "${d%/}" terminal_state)" == "escalated" ]] && printf '%s\n' "${d%/}"
    done
    return 0
}

# Árbol actual del index. Vacío si no se puede calcular.
current_tree() {
    git -C "$REPO" write-tree 2>/dev/null || echo ""
}

# Intentos ya archivados para el mismo cambio lógico (mismo base_tree).
attempts_for_base() {
    local base="$1" n rc
    # Sin base no hay forma de contar los intentos de ESTE cambio: `grep -c
    # "base="` matchearía TODAS las líneas del log. Se reporta el tope para que
    # el cortacircuito CORTE, en vez de devolver un conteo falso.
    [[ -n "$base" ]] || { max_attempts; return; }
    [[ -f "$AUDIT_LOG" ]] || { echo 0; return; }

    # OJO con `grep -c ... || echo 0`: con CERO matches grep imprime "0" Y sale
    # con código 1, así que el fallback agregaba un SEGUNDO "0" y la función
    # devolvía "0\n0". Eso reventaba `[[ $tries -ge $tope ]]` y `$((tries + 1))`
    # con error aritmético: el cortacircuito nunca cortaba y la línea del
    # AUDIT.log nunca se escribía, aunque do_unblock reportara éxito. Sin esa
    # línea el conteo de ese base se quedaba en cero para siempre.
    # Códigos de grep: 0 = hubo matches, 1 = cero matches ("$n" ya vale 0),
    # >1 = error real de lectura.
    n=$(grep -c -- "base=$base" "$AUDIT_LOG" 2>/dev/null); rc=$?
    if (( rc > 1 )) || [[ ! "$n" =~ ^[0-9]+$ ]]; then
        # Log ilegible: se reporta el tope para que el cortacircuito corte.
        # Contar de menos sería habilitar intentos infinitos sin traza.
        max_attempts
        return
    fi
    printf '%s\n' "$n"
}

print_status() {
    echo "repo:        $REPO"
    echo "tope de intentos: $(max_attempts)  (git config reviewGate.maxAttempts)"
    local tree; tree=$(current_tree)
    echo "árbol index: ${tree:-<no calculable>}"

    local found=0 d
    while read -r d; do
        [[ -n "$d" ]] || continue
        found=1
        local lin cand base readable=1
        lin=$(basename "$d")
        cand=$(receipt_field "$d" final_candidate_tree) || { cand=""; readable=0; }
        base=$(receipt_field "$d" base_tree)            || { base=""; readable=0; }
        echo ""
        echo "  lineage ESCALADA: $lin"
        echo "    árbol rechazado: ${cand:-<ilegible>}"
        echo "    base:            ${base:-<ilegible>}"
        echo "    intentos previos para este base: $(attempts_for_base "$base") / $(max_attempts)"
        if [[ $readable -eq 0 ]]; then
            echo "    → unblock NO permitido: el recibo no se pudo leer (ausente o corrupto)"
        elif [[ -z "$tree" ]]; then
            echo "    → unblock NO permitido: no se puede calcular el árbol del index"
        elif [[ "$tree" == "$cand" ]]; then
            echo "    → unblock NO permitido: el contenido NO cambió desde el rechazo"
        elif [[ $(attempts_for_base "$base") -ge $(max_attempts) ]]; then
            echo "    → unblock NO permitido: cortacircuito, tope de intentos alcanzado"
        else
            echo "    → unblock PERMITIDO: el contenido cambió desde el rechazo"
        fi
    done < <(escalated_lineages)

    [[ $found -eq 0 ]] && echo "" && echo "  sin lineages escaladas — nada que desbloquear"
    return 0
}

do_unblock() {
    local tree; tree=$(current_tree)
    if [[ -z "$tree" ]]; then
        echo "✗ No se pudo calcular el árbol del index (¿conflictos sin resolver?)." >&2
        echo "  Sin árbol no hay comparación posible → no se archiva nada." >&2
        return 1
    fi

    local any=0 archived=0 d
    while read -r d; do
        [[ -n "$d" ]] || continue
        any=1
        local lin cand base tries tope
        lin=$(basename "$d")

        # Un recibo ilegible NO habilita el archivado: sin `final_candidate_tree`
        # no hay con qué comparar, y seguir sería archivar a ciegas.
        if ! cand=$(receipt_field "$d" final_candidate_tree) || [[ -z "$cand" ]]; then
            echo "✗ $lin: RECHAZADO — no se pudo leer 'final_candidate_tree' del recibo." >&2
            echo "    Sin el árbol rechazado no hay comparación posible → necesita un humano." >&2
            continue
        fi
        if ! base=$(receipt_field "$d" base_tree) || [[ -z "$base" ]]; then
            echo "✗ $lin: RECHAZADO — no se pudo leer 'base_tree' del recibo." >&2
            echo "    Sin base no se pueden contar los intentos → el cortacircuito quedaría ciego." >&2
            continue
        fi

        tries=$(attempts_for_base "$base")
        tope=$(max_attempts)

        if [[ "$tree" == "$cand" ]]; then
            echo "✗ $lin: RECHAZADO — el contenido no cambió desde el rechazo." >&2
            echo "    árbol rechazado y árbol actual son el mismo: $tree" >&2
            echo "    Arreglá los hallazgos primero. Volver a revisar lo mismo es lavar el veredicto." >&2
            continue
        fi

        if [[ $tries -ge $tope ]]; then
            echo "✗ $lin: RECHAZADO — cortacircuito ($tries/$tope intentos para este cambio)." >&2
            echo "    Tres rondas sin converger no se arreglan con una cuarta. Necesita un humano." >&2
            continue
        fi

        mkdir -p "$ARCHIVE_DIR"
        local stamp dest
        stamp=$(date +%Y%m%dT%H%M%S)
        dest="$ARCHIVE_DIR/${lin}-escalated-${stamp}"
        if ! mv "$d" "$dest"; then
            echo "✗ $lin: falló el archivado a $dest" >&2
            continue
        fi
        printf '%s lineage=%s base=%s rejected_tree=%s new_tree=%s attempt=%d/%d dest=%s\n' \
            "$(date -Is)" "$lin" "$base" "$cand" "$tree" "$((tries + 1))" "$tope" "$(basename "$dest")" \
            >> "$AUDIT_LOG"
        echo "✓ $lin archivada (intento $((tries + 1))/$tope) — el recibo del rechazo se conserva en:"
        echo "    $dest"
        archived=$((archived + 1))
    done < <(escalated_lineages)

    if [[ $any -eq 0 ]]; then
        echo "Sin lineages escaladas — nada que desbloquear."
        return 0
    fi
    [[ $archived -gt 0 ]] || return 1
    echo ""
    echo "Ahora sí podés abrir lineage nueva: gentle-ai review start --cwd $REPO"
    return 0
}

case "$CMD" in
    status)  print_status ;;
    unblock) do_unblock ;;
    *)
        echo "Uso: $0 [status|unblock] [repo]" >&2
        exit 2
        ;;
esac
