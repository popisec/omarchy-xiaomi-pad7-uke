# CRÍTICA-L50 — Revisión adversarial del instrumento de subdivisión (14-oct-2026)

> Subagente crítico. Solo lectura (árbol intacto; diff verificado sobre el árbol vivo
> con `patch -p1 --dry-run`; nada en la tablet). Base: `L50-INSTRUMENT.md`,
> `l50-instrument.diff`, `docs/historia/revision/PIPELINE-PANEL-20261014/L50-SMMU.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/L50-DCS-VENDOR.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/L49-PREP.md` (§5),
> `l49-capture.diff`, `out/CAPTURA-MUERTE-netconsole.log`, `docs/historia/ESTADO-VIVO.md`, ledger #624.

## 1. Diff: VERIFICADO, 0-funcional, sin bloqueantes

- `patch -p1 --dry-run` OK en ambos ficheros (medido). Solo añade `uke_poke`+`pr_err`;
  ninguna lógica tocada. `uke-poke.h` incluido en `dsi_host.c:7` y `dsi_manager.c:7` (medido).
- 12 tags `uke_poke("K50-*")` únicos (medido `grep -c` = 12); `K50-` total = 18
  (6 tags ×2 poke+pr_err + 6 tags ×1 solo-poke; aritmética del §4 **correcta**);
  `pr_err("K50-` ×6 (medido). Todos los pokes emiten línea por netconsole
  (el `uke_poke` lleva su propio `pr_err("UKE-POKE")` + los 6 explícitos son nivel 3).
- Formatos aarch64 correctos: `dma_base` es `uint64_t` → `%llx` con cast (medido
  `dsi_host.c:1447-1456`); commit recibe `u32` → `%08x`/`%u` (medido `dsi.h:54`,
  `dsi_manager.c:543`); `id` es `int` → `%d` (medido `dsi.h:47`); `bool`→`%d` OK.
- Posiciones: las que dice la tabla §2 (manager brackets, prepare clk-rate/en/ctrl-ok,
  dma-base tras `dma_base_get` OK, vid-ok tras wait, trig-done tras trigger, commit
  entrada con id/base/len). Orden commit(0)→commit(1) confirmado en `dsi_manager.c:543-556`.
- Verificado además: el early-return L36 de `wait4video` **NO está** en el árbol vivo
  (función completa, `dsi_host.c:1222-1242`) ⇒ la fila R2 del §3 es viva, no muerta.

## 2. Huecos de la tabla §3 (no bloquean el build; el prep los añade)

- **Sin fila**: última = `prep0/1-before` ⇒ wedge en `pm_runtime_get_sync` (resume
  GDSC, clase F2, posibilidad real). Es el hueco más serio: un veredicto "resume",
  ni A ni B, sin casilla.
- **Sin fila**: última = `prep0/1-after` (wedge en retorno/entry de `cmd_tx`,
  o `dma_base_get` fallido —ese deja el `pr_err` preexistente "failed to get iova",
  visible pero sin casilla) y última = `K47-host-xfer` aún (wedge en `mutex_lock`
  o entrada del manager).
- **Sobreinterpreta (menor)**: `clk-en` sin `ctrl-ok` incluye también
  `set_tx_power_mode` + `dsi_read`, no solo el write de `REG_DSI_CTRL`.
- `clk-rate` sin `id` (1ª=DSI_0) es válido pero frágil ante pérdida de cola (ver §4):
  documentar, no cambiar.

## 3. Gates de build: VERIFICADOS en el diff; `repack-k52L50.py` no existe aún

- `K50-`==18 y 6 formatos ×1: medidos en el diff (18/6). `UKE-POKE`==115 se mantiene
  (cero literales "UKE-POKE" añadidos; aplica F-INT-5). L49×5 y resto de gates, intactos.
- Ojo para el prep: `S4-DIAG` sale 9× en la fuente (con comentarios); el gate debe
  contar en el binario como hizo L49, no en fuente. Spec (OUT/cmdline 580 B/FBDEV=n/
  sha pre-registrado ANTES) coherente con `repack-k52L49.py` (G2 580 B medido).
- El `.py` hay que clonarlo; esta crítica no lo escribe (fuera de alcance).

## 4. Riesgo de canal (el importante): ACEPTABLE con regla ±1, sin Gate B

- Por qué llegó la última línea en #624: tras `K47-host-xfer` hay holgura
  (manager+prepare+MMIOs, ms) >> hrtimer NTB 300 µs; la cola flusheó (104 UKE-POKE
  en `out/CAPTURA-MUERTE-netconsole.log`, última `K47-host-xfer` a 1389.103838).
- Qué cambia con L50: ráfaga de ~18 líneas en <1 ms junto al wedge; si el wedge cae
  <300 µs tras el último poke, **la última línea observada puede ir 1 (raro: 2) pokes
  por detrás del punto real**. Efecto: error de atribución de ±1 slot
  (p.ej. wedge en `commit(1)` leído como `commit(0)` — mismo barrio, veredicto cercano;
  el par delicado es `vid-ok`/`commit` = R2 vs inter-trigger).
- Por qué no es grave: el dato F0 (`dma_base`) sale TEMPRANO (antes de wait+trigger),
  casi seguro ya flusheado aunque se pierda la cola. El objetivo primario está a salvo.
- Mitigación (sin código): (a) regla de lectura **"±1 poke"** en el runbook; (b) no
  añadir más densidad —este diff es el techo; (c) `dmesg -w` en paralelo como 2º canal
  en tiempo real (independiente del NTB); (d) NO activar el Gate B sync-flush este
  ciclo (riesgo de atribución fina, no de pérdida total).

## 5. Runbook: completo salvo 3 retoques menores

- OK: MAC fresca, `printk 7`, probe `<3>` ×3, `:#0` (coincide con ledger #624;
  `docs/historia/revision/PIPELINE-PANEL-20261014/L50-PREP.md` §5 decía `:0` — vale `:#0`), ACM lector único, `dmesg -w`, recogida,
  rollback L49 `ccfdea9d…`/L48 `0b1d22c4…` (shas coinciden con `docs/historia/revision/PIPELINE-PANEL-20261014/L49-PREP.md`),
  fila pre-registrada. "No depender del dumper" ya consta ✓.
- Añadir: (a) lección pkill de hoy (NOTAS:4289: matar ACM por PID explícito, nunca
  por patrón); (b) matiz fidelidad #624: probes llegaron 2× — aceptar 2/3 con MAC
  estable en vez de exigir 3/3 ciego; (c) ramas FALLA sin definir: última=K47 aún
  (wedge en entry/mutex → re-subdividir, no fix) y canal mudo (→ Gate B, no L51).
- Criterio PASA claro (nueva última K50 + `dma_base` → A/B → L51=fix). FALLA = lo de
  arriba; añadirlo es tarea del prep, 5 líneas.

## Veredicto: **PASA construir L50**

El diff es correcto y 0-funcional, los gates cuadran al `grep`, y el riesgo de canal
es aceptable con la regla ±1. **Nada que corregir en el diff ni en el runbook base.**
El prep debe, antes del flash: (1) clonar `repack-k52L50.py` con el G3 especificado
(contar S4-DIAG en binario); (2) añadir 3 filas a la tabla §3 (`prep-before`→resume,
`prep-after`/`iova-fail`, `K47`→entry/mutex) + matizar la de `clk-en`;
(3) regla ±1 + pkill-por-PID + ramas FALLA en el runbook. Presupuesto: 1 escritura.
