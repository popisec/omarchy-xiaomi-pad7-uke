# REVIEW-S2 — Revisión adversarial de S2-G8 (14-oct-2026)

Revisor adversarial. Solo lectura; árbol `k52-L16-tree` intacto (verificación en
copia `/tmp/opencode/s2rev`). Todo lo afirmado aquí fue re-leído por el revisor.

## Veredicto: OK-con-notas

El fondo es sólido: la evidencia del pulso vendor está probada a nivel de
instrucción+reubicación (verificado de forma independiente, no citado de memoria),
el diff aplica limpio, no rompe símbolos, no colisiona con REFUTADO/LECCIONES ni con
otros diffs, y es una variable viva en el path del primer arranque. Las notas
obligan a 4 correcciones menores de citas y a re-anclar el plan de flash al vivo
actual (el §4 asume la escalera L33 del 13-oct; el vivo hoy es L45/display-off).

## 1. Evidencia re-verificada (a favor)

- **Pulso vendor = `__const_udelay(0x10C7)` — CONFIRMADO independiente.**
  `llvm-objdump --arch-name=aarch64 -d --disassemble-symbols=dsi_ctrl_hw_cmn_soft_reset
  ~/proyectos/ubuntu-uke/stock/modules/msm_drm.ko` (6105320 B, existe):
  `12d4ac: mov w0, #0x10c7` + `12d4b0: bl ...`; `llvm-readelf --relocs`:
  `000000000012d4b0 R_AARCH64_CALL26 ... __const_udelay + 0`. Offsets coinciden
  con S2 §2c. La secuencia RESET=1 → dsb → call → RESET=0 coincide con
  `build/vendor-re/decomp/dsi_ctrl_hw_cmn_soft_reset.c:12-25` (re-leído entero).
- **Equivalencia `__const_udelay(0x10C7)` ≡ `udelay(1)` — CONFIRMADA**, vía
  `include/asm-generic/delay.h: UDELAY_CONST_MULT = DIV_ROUND_UP(2^32, 1e6) = 4295
  = 0x10C7`, y `udelay(1)` constante → `__const_udelay(1*4295)` (NOTA A: la cita
  a `delay.c:76` apunta al sitio equivocado, el fondo es correcto).
- **`msleep` único en `dsi_host.c:1148` — CONFIRMADO** (`grep msleep` da solo esa
  línea; otros delays del fichero: `usleep_range` :1235, `udelay` :2387/:2389 en
  `msm_dsi_host_reset_phy`, función distinta no tocada).
- **Define sin otros usuarios — CONFIRMADO** (`grep -rn DSI_RESET_TOGGLE_DELAY_MS`
  en todo el árbol: solo def :36 + uso :1148). Eliminarlo no rompe nada.
- **`linux/delay.h` ya incluido (:8) — CONFIRMADO.** `udelay` disponible sin includes.
- **Orden `power_on`: timing → `sw_reset` → `ctrl_enable` — CONFIRMADO**
  (`:2464` + siguientes). 3 llamadores de `dsi_sw_reset`: power_on, `host_disable`
  (:2530), `dsi_err_worker` fifo_underflow (:1575). S2 los declara los tres.
- **`dsi_ctrl_enable` :919-921 escribe CLK_EN|carriles|ENABLE en un solo write —
  CONFIRMADO** (líneas exactas 919/921 re-leídas).
- **Vendor `ctrl_reset` restaura sin VID / `ctrl_en` solo BIT0 / VID al final —
  CONFIRMADO** (`dsi_ctrl_hw_cmn_ctrl_reset.c`, `dsi_ctrl_hw_cmn_ctrl_en.c`,
  `dsi_display_vid_engine_enable.c:25` re-leídos).
- **L36-early-return solo en `k52L33-tree`, vivo bloquea — CONFIRMADO**
  (L33 `dsi_wait4video_eng_busy` lleva el comentario L36 y no bloquea; vivo
  `:1455` `dsi_cmd_dma_tx` → `dsi_wait4video_eng_busy` → `:1233`
  `dsi_wait4video_done` 70 ms).
- **`o82_prepare` con DCS en prepare (:325+), `prepare_prev_first=true` (:726) —
  CONFIRMADO.**
- **REFUTADO/LECCIONES: cero colisiones — CONFIRMADO** (grep propio `sw_reset|
  soft_reset|ctrl_reset|CTRL_ENABLE|G8|RESET_TOGGLE|msleep.*20`: 0 hits
  relevantes; único hit `a8r8g8b8` en LECCIONES:291, pixel-format, irrelevante).
- **AUDITORIA E8 (:39-40) y GAPLIST :71 — CONFIRMADO** (G8 abierto, mal
  clasificado como refutado). GAPLIST G8 🟢 abierto, pulso 1 µs vs 20 ms.
- **Diff aplica limpio — CONFIRMADO** (`patch --dry-run -p1`, exit 0, sin fuzz ni
  offset, sobre copia; contextos hunk-1 (:33-40) y hunk-2 (:1145-1151) verificados
  línea a línea contra el vivo).
- **Hunks disjuntos — CONFIRMADO**: s2 toca `dsi_host.c` @~33 y @1143-1166;
  `docs/historia/revision/PIPELINE-PANEL-20261014/s4-instrumentacion.diff` toca `dsi_host.c` @1206/1460/1570/1604/1633 (sin solape);
  s1 (dts), s3/s5a (panel driver), otros ficheros.

## 2. Discrepancias (fichero:línea, 4 menores + 2 de fondo)

- **NOTA A (cita desplazada).** S2 §1/§3: "`arch/arm64/lib/delay.c:76` define
  `udelay(n) → __const_udelay(n*0x10C7UL)". Falso el fichero: `:68-76` de ese
  fichero definen `__const_udelay`/`__udelay` (variante runtime). El macro
  `udelay(usec)` con la multiplicación por `UDELAY_CONST_MULT` (=0x10C7) está en
  `build/kernel-pokes/k52-L16-tree/include/asm-generic/delay.h:59-66`. El fondo
  (equivalencia) es correcto; corregir la cita en S2 §1 y en el comentario del diff.
- **NOTA B (líneas erróneas).** S2 §1: "`dsi_op_mode_config: :1221+1226
  VID_MODE_EN|ENABLE juntos`". En el vivo la función está en `:1158-1181` y el
  write único en `:1180`; las líneas 1221/1226 caen en `dsi_wait4video_eng_busy`/
  `dsi_tx_buf_alloc_6g`, fuera de la función. El hecho (VID|ENABLE en un write)
  es verdadero; los números son erróneos. Corregir a `:1158-1181` (write `:1180`).
  La cita `:1215-1234` (bloqueo VIDEO_DONE por DCS) es aproximada pero aceptable
  (`dsi_wait4video_done` empieza en `:1197`; el path por comando es `:1455`→`:1233`).
- **NOTA C (matiz "file-offset").** S2 §2c/§3: "file-offset `0x12d4ac/0x12d4b0`".
  Lo que muestra llvm-objdump en un ET_REL (`.ko` sin linkar) son direcciones
  relativas a la sección `.text`, no file-offsets crudos (falta `sh_offset`).
  Numéricamente verificado que coinciden con lo citado; renombrar a "offset en
  `.text`" o añadir el matiz.
- **NOTA D (ruta incompleta).** S2 §4 cita `HALLAZGO-MUERTE-DSI.md §8` sin ruta;
  el fichero vive en `build/evidencia/L40/HALLAZGO-MUERTE-DSI.md`. El baseline
  `out/diag-L33/VENTA-MUERTE-acm-207s.txt` sí existe donde se dice.
- **NOTA E (fondo: "restore no-op en primer arranque" condicionado).** S2 §2e fila 2
  afirma que en primer arranque CTRL parte de 0 y el restore es no-op. Eso vale si
  el reset deja CTRL=0, pero el propio proyecto documenta splash heredada del ABL
  (`P82-INHERIT`: el panel viene encendido del ABL; `o82_prepare` salta todo si
  `uke_panel_inherit()`). Si el ABL dejó `CTRLENABLE≠0`, el `dsi_sw_reset` del
  `power_on` sí ejecuta disable+restore reales con clocks forzados — el restore NO
  es no-op y el pulso toca estado heredado vivo. Esto no invalida el diff (lo hace,
  si acaso, más relevante), pero la clasificación "fila 2 no viva" y el "no-op"
  deben condicionarse a "salvo estado heredado del ABL". Riesgo no declarado.
- **NOTA F (fondo: plan de flash anclado a escalera caducada).** S2 §4: "Flash: boot
  del peldaño 4 + este diff" y juicio contra `diag-L33`. La escalera L33/s283 es del
  13-oct; el vivo es L45/display-off con KTZ/backlight verdes y `panel-defer`. Si el
  flash real sale de la base actual, el "peldaño 4" no existe y el baseline L33 puede
  no ser comparable (L45 trae `l44-ktz-driver`, `l45-panel-defer`, pokes K47…).
  Corrección necesaria antes de flashear: re-anclar el criterio al kernel que
  realmente se flashee, preferiblemente **control gemelo en la misma sesión**
  (boot con/sin diff, doctrina G4/G7, lo mejor del día según AUDITORIA §5.1), no
  comparación contra diag-L33. Sin esto, el criterio pierde su ancla.

## 3. Criterio pasa/falla

Direccional y prefijado ("`status=4` desaparece o `cmd#0` recibe ACK o el punto de
muerte se desplaza", FALLA = firma idéntica), con comando de juicio y baseline
nombrado. Aceptable, con dos endurecimientos propuestos: (i) con NOTA F, el baseline
debe ser el boot gemelo sin diff; (ii) "cualquier movimiento de firma" es amplio y
E4/E6 advierten contra leer ruido (conteos variables, ACM lossy, desplazamiento
temporal de ~20 ms declarado en el propio S2 §5) como señal: el PASA debe exigir
cambio en **secuencia o punto de parada**, no solo conteos ni un poke desplazado.
La doble captura + `dmesg -n 7` están exigidas. Bien.

## 4. Riesgos no declarados por el autor (además de NOTA E)

1. **Herencia ABL + `udelay` en `power_on`**: con `msleep(20)` el `power_on` dormía
   20 ms con el thread planificable; con `udelay(1)` hace busy-wait atómico de 1 µs
   y llega ~20 ms antes al `ctrl_enable`/PHY. Si el panel/TDDI necesita esos 20 ms
   (rails asentándose, reset-GPIO aún propagándose), el fallo podría *empeorar* por
   timing, no por el pulso — indistinguible en la firma salvo que se mida. El autor
   declara el desplazamiento pero no este sentido del riesgo (asume que antes = igual
   o mejor). Mitigación: ninguna barata en un-cambio-por-ciclo; se anota para no
   mal-atribuir un empeoramiento.
2. **Apilado futuro con s4**: los hunks de `docs/historia/revision/PIPELINE-PANEL-20261014/s4-instrumentacion.diff` (@1206+) están
   calculados sobre base sin s2; si s2 entra, s4 se desplaza +16 líneas. Solo aviso
   de mantenimiento (un-cambio-por-ciclo impide el apilado de todos modos).
3. **Citas secundarias no re-verificadas por este revisor**: las líneas de
   `docs/historia/revision/ANDROID-DSI-ENABLE-COMPARISON-20261013.md` (:79-80, :182-195, :46-53) y
   `SECUENCIA-ENCENDIDO-ANDROID-O82-20261012.md` (:20-40) se toman de S2; la
   verificación propia se hizo contra las fuentes primarias (decomp + disasm +
   árbol vivo), que las respaldan en lo estructural. No se detectó contradicción.

## 5. Pregunta clave

**¿Es UNA variable y es la diferencia viva del primer arranque? Sí**, con notas.
Un solo sitio de código (`dsi_sw_reset`, un hunk funcional + retirada de un define
muerto), en el path `power_on` (timing → sw_reset → ctrl_enable) que corre en cada
arranque con display. Los 3 llamadores afectados están declarados y el vendor usa el
pulso de 1 µs en los 3 paths equivalentes; en el primer arranque el efecto medido
será atribuible al `power_on` (los otros dos paths — `host_disable`, `err_worker` —
no corren en el arranque limpio). Condición: aplicar NOTA F (control gemelo) para
que la atribución sea real y no comparativa contra L33.

## 6. Correcciones necesarias (antes o junto al flash, sin re-trabajo grande)

1. S2 §1 + comentario del diff: cita `delay.c:76` → `include/asm-generic/delay.h:59-66`
   (macro `udelay`, `UDELAY_CONST_MULT`=0x10C7).
2. S2 §1: `:1221+1226` → `:1158-1181` (write `:1180`).
3. S2 §2c/§3: "file-offset" → "offset en `.text`".
4. S2 §4: ruta completa de `HALLAZGO-MUERTE-DSI.md` (`build/evidencia/L40/`).
5. S2 §2e fila 2 + §6: condicionar el "no-op en primer arranque" al estado heredado
   del ABL (NOTA E).
6. S2 §4: re-anclar flash y baseline al vivo (control gemelo con/sin diff en la misma
   sesión; NOTA F) y endurecer PASA a secuencia/punto-de-parada.
