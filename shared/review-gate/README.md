# review-gate

Enforcement **opt-in** del ciclo de review de `gentle-ai`, más un desbloqueo
guardado para que un agente desatendido pueda iterar sin poder saltearse nada.

## El problema

El gate de review no tiene dientes por sí solo. `gentle-ai review validate` solo
corre si alguien elige invocarlo — no hay nada en git que lo exija. Un agente que
omite el paso, o una persona apurada, commitea igual y nadie se entera.

Al mismo tiempo, cuando una review **sí** bloquea, el estado `escalated` es
terminal por diseño: impide que el autor levante su propio rechazo. Correcto
para una sesión con humano presente; paralizante para una corrida desatendida.

Las dos mitades de este directorio atacan una cosa cada una.

## Activar el gate (por repo, a mano)

```bash
bash shared/review-gate/install.sh ~/projects/mi-repo      # activar
bash shared/review-gate/install.sh --status  ~/projects/*  # ver dónde está activo
bash shared/review-gate/install.sh --uninstall ~/projects/mi-repo
```

Instala `pre-commit` y `pre-push` por **symlink**, así una corrección al hook se
propaga sola a todos los repos activos. Un hook previo que hubiera se guarda como
`<hook>.pre-review-gate.bak` y se restaura al desinstalar.

Los hooks **fallan cerrado**: sin `gentle-ai` en PATH, sin recibo, o con un recibo
que no cubre este contenido exacto, el commit no entra.

> **No hay variable de entorno para saltearlos, a propósito.** El único bypass es
> `git commit --no-verify` / `git push --no-verify`: nativo de git, explícito, y un
> acto humano deliberado. Un agente no debe usarlo nunca.

Es opt-in porque no todo repo merece la ceremonia. Activalo donde el costo de un
bug supere el costo del proceso.

## Desbloquear después de un rechazo

```bash
bash shared/review-gate/review-cycle.sh status  <repo>   # ¿se puede? ¿por qué no?
bash shared/review-gate/review-cycle.sh unblock <repo>   # archiva, si corresponde
```

`unblock` archiva una lineage escalada **solo si el contenido cambió**. El recibo
trae `final_candidate_tree`, que es un hash de árbol de git; se compara contra el
árbol actual del index:

| Situación | Resultado |
|---|---|
| Árbol actual **igual** al rechazado | **RECHAZA** — sería lavar el veredicto |
| Árbol actual **distinto** | Archiva → podés abrir lineage nueva |
| Tope de intentos alcanzado | **RECHAZA** — cortacircuito, necesita un humano |

Con eso, *"arreglé y me vuelvo a someter a review"* está permitido y *"vuelvo a
tirar los dados sobre el mismo código"* es imposible.

**Cortacircuito**: máximo 3 intentos por cambio lógico (mismo `base_tree`).
Ajustable con `git config reviewGate.maxAttempts <n>`. Si tres rondas no
convergieron, una cuarta tampoco: se detiene y espera.

**Traza**: cada archivado se registra en `.git/gentle-ai/archived/AUDIT.log` con
los hashes, el intento y el tope vigente. **Nada se borra** — el recibo completo
del rechazo se conserva. Esa traza es lo que hace auditable una corrida
desatendida: a la mañana siguiente ves cuántas veces te rebotaron y por qué.

## El ciclo completo, desatendido

```
implementar → review start → lentes → finalize
   ├── recibo OK    → commit (el hook valida) → push
   └── escalated    → arreglar los hallazgos
                    → review-cycle.sh unblock   (exige contenido distinto)
                    → review start ...          (lineage nueva)
                    → tope de intentos → PARA y espera a un humano
```
