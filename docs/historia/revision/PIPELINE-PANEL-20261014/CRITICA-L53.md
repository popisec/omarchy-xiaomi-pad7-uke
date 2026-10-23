# CRÍTICA L53 — instrumento KTZ (estado ABL vs nuestro) — 14-oct-2026

> Adversarial, solo lectura, con evidencia fichero:línea. Diff: `l53-ktz-dump.diff`.
> Contexto: `docs/historia/revision/PIPELINE-PANEL-20261014/L53-PREP.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/VERIF-HERMANO-PANTALLA.md`, `VERIF-K52B2-PANTALLA.md`, `NOTAS-OMARCHY.md:4687-4697`.

## 1. Diff: aplica y es correcto

- `r[17]`, bucle `i<=0x10` = 17 lecturas, índices `r[0..16]` ✓. Formato con **17 `%02x`** (contado:
  `grep -o '%02x' l53-ktz-dump.diff | wc -l` = 17) para 18 args (`tag` + 17) = `%s` + 17 ✓, sin
  warning de `-Wformat` (`%02x` ↔ `unsigned int` es exacto).
- El literal del `pr_err` va en **una sola línea** (solo se parten los args): el patrón de string
  roto que rompió L51/L52 **no se repite** ✓. Helper `static` definido antes de sus dos usuarios
  (`update_status` :405, `probe` :510) ✓. `pr_err` declarado vía `gpio/consumer.h:197`
  → `kernel.h` → `printk.h:553` ✓ (precedente: `qcom-wled.c`, `apple_bl.c` en el mismo dir).
- `probe-entry` tras `devm_regmap_init_i2c` (`ktz8866.c:529-533`), antes de `ktz8866_init` (:568) ✓.
  Matiz: entre medias corren `regulator_get_optional` + `gpiod_get_optional` (:538-551), pero con el
  DT uke (sin supplies ni `enable-gpios`, ver L45) son no-ops: **cero writes I2C al KTZ antes** ✓.
- `post-init` tras `ktz8866_init` (void: todos sus writes hechos) ✓; `post-first-update` tras el
  primer `backlight_update_status` (:572-573) ✓. `update-in` a la entrada (un `in` sin `out` =
  brillo rechazado >4095: informativo, no bug); `update-out` solo en el path de éxito ✓.
- **Flujo inalterado**: ningún retorno consumido, ningún write añadido ✓.

## 2. `regmap_read`: seguro

- `ktz8866_regmap_config` (:103-107): sin caché, sin `readable_reg` ⇒ todo read va al bus;
  `max_register=0x15` (`REG_MAX`, :64) ⇒ `0x00..0x10` en rango ✓. El chip ACK-ea reads (medido por
  python `I2C_SLAVE_FORCE`, `NOTAS:4693-4697`, L43) ✓. 17 reads ≈ sub-ms a 400 kHz; el quirk
  L43-icc era voto ICC/registro del bus, no volumen de lecturas ✓. El path ya duerme (writes I2C):
  sin problema atómico nuevo ✓. Si `0x0F` (FLAG) fuese clear-on-read, el log de `probe-entry`
  preserva el valor ABL y el driver nunca lo lee: sin cambio de conducta ✓.
- `0xdead` con `%02x` imprime `dead` (1 token, distinguible de valores válidos de 1 byte — bien
  para cazar fallos). El gate cuenta literales (`repack-k52L53.py:395-407`), no anchos: no rompe
  nada. Solo si un gate futuro regexea `[0-9a-f]{2}` habría que pasar a `0xDD`. No bloquea.
- Rango `0x00..0x10` omite `0x11..0x15` (DIMMING/RAMP), pero el vendor no los escribe con el DT
  uke (cabecera :478-482); los regs de decisión (`0x02/0x03/0x04/0x05/0x08/0x09-0x0E/0x0F/0x10`)
  están todos ✓. No ampliar este ciclo.

## 3. `ignore_loglevel`: justificado, solo este ciclo

- `pr_err` = nivel 3, invisible cuando userspace baja `console_loglevel` a 1 (precedente #624);
  los dumps del probe son a ~4,17 s ⇒ sin el token, ACM/netconsole los pierden (el ring buffer
  los guarda igual: `dmesg` por SSH los tendría de todos modos; el token asegura los canales
  live ante reset-cut, regla de doble captura) ✓. Coste: boot completo verboso en ACM 115200 —
  aceptable con lector único abierto (ya obligatorio) y netconsole UDP como primario ✓.
- **Revertir a 608 B tras el ciclo** (quitar el token); sin efecto en rendimiento más allá de I/O
  de consola ✓. `608+15+1=624` ✓ (`repack-k52L53.py:207-208` lo gatea).

## 4. Criterio y valor: los 5 dumps bastan, sin añadir nada

- `probe-entry` = receta ABL (p.ej. `0x08=0x7F` + `0x09-0x0E/0x10` ≠ nuestros) y difiere de
  `post-init`/`post-first-update` ⇒ el diff son los writes que faltan (fix = re-init del ABL-diff).
- `probe-entry` = defaults/reset ⇒ handover resetea el chip o el ABL no usó el KTZ ⇒ branch B
  (DCS 0x51 interno, `VERIF-K52B2-PANTALLA.md` §5) ✓. Decisión binaria limpia: suficiente.
- Dump extra en el prepare del panel (~47-55 s): **innecesario** — `update-in/out` enganchan
  TODA llamada a `update_status` (suspend/resume `BL_CORE_SUSPENDRESUME`, systemd-backlight,
  sddm), así que cualquier reescritura tardía ya queda capturada ✓. No tocar (un cambio por ciclo).
- Observación no bloqueante: los tags no llevan `dev_name`; el DT stock trae 2 KTZ pero el dtbo
  actual solo habilita uno (un solo `probe sucess end` en L44): si algún día se habilita el 2º bus,
  los tags duplican. No es este ciclo.

## 5. Gates del repack L53 (`repack-k52L53.py`, medidos en el script)

- `UKE-K53` ×1 en binario (:402; fuente ×2 comentario+código) ✓; tags únicos
  `update-out`/`probe-entry (estado ABL)`/`post-first-update` ×1 (:404-406; `update-in`/`post-init`
  colisionan tree-wide ⇒ solo-fuente, documentado en :396-401) ✓; `ignore_loglevel` + 624 B
  (:207-217, sin `uke_write_mask`) ✓; `FIX-A1b`×6 + `FIX-A1:`×0 (:387-390), `POKE`=121 (:236),
  `K50-`×18 (:376), `S4-DIAG`×4 (:344) ✓. Resto intacto.

## VEREDICTO: **PASA compilar + flashear L53**

Sin correcciones bloqueantes. Dos notas para el runbook (no para el diff): revertir
`ignore_loglevel` (608 B) en L54; si algún gate futuro parsea campos, preferir `0xDD` sobre `0xdead`.
