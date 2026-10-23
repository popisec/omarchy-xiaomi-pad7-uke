# REVIEW-S1 — revisión adversarial de S1-VCI + docs/historia/revision/PIPELINE-PANEL-20261014/s1-vci.diff (14-oct-2026)

Veredicto: **OK-con-notas** (3 notas menores, 0 bloqueantes). El diff es aplicable,
fiel a L27 en lo que declara, disjunto de s2/s3/s4/s5a, y el criterio es medible.
Método: todo verificado por mí en copias (`/tmp/revs1`, ya borradas); árboles y
entregas intactos; tablet no tocada.

## 1. Premisa: CIERTA (verificado directo, más fuerte que la cita)

- `grep -c vci panel-xiaomi-o82-dualdsi.c`: **L16=0**, L29=27, **L33=0, L39=0**.
  Pérdida en ventana **L29→L33** (S1 la atribuye a `PREP-MINUCIAS-20261013.md:27-32`;
  yo la confirmé por conteo directo en los tres árboles).
- L27 contiene las dos mitades que S1 restaura: struct (`k52L27-tree/...o82-dualdsi.c:56-59`),
  voto en `power_on` (`:309-325`), disables (`:354-355`, `:438-439`, `:476-477`),
  `get_optional` + `L27-vci-absent` (`:721-730`). `l27-fidelidad-android.diff`
  (187 líneas, solo driver, sin DT) es la fuente del port — coherente con que el DT
  nunca lo tuvo.
- Faltan las DOS mitades en el vivo: driver 0 hits + `panel@0` con solo 3 supplies
  (`fase4-display.dts:362-364`). Solo-DT sería no-op (supply sin consumidor) y
  solo-driver sin DT degenera a `L27-vci-absent` = conducta actual. Correcto traer ambas.

## 2. Rail: CIERTO (con 1 corrección de cita, nota N1)

- `pmxr2230_l19: L19B`, init/min `0x27ac40`=2600000, max `0x3613c0`=3544000
  (`stock2-Cliffs7P-uke.dts:6956-6966`, símbolo `:20727-20728`). Aritmética comprobada.
- Voto vendor: `vci-supply = <0x150>` en `dt-fusionado-s238.dts:1280,1300`;
  `0x150` = `pmxr2230_l19/L19B` en el mismo árbol (`:7989-7998`);
  `vddio-supply = vddil8b-supply = <0x14f>` (mismo L8 físico, `:1299-1304`).
  Orden vendor (vddio+vci directos, luego entries vddil8b→vsp→vsn con 300 mA + 2 ms):
  `docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:380-394` (verificado; el binario lo confirma §4.2).
- El orden de s1 (vci antes de los 3 rails) es el del vendor. `O82_SUPPLY_ENABLE_LOAD_UA
  = 300000` (`o82-dualdsi.c:46` en L16) = `0x493e0` vendor. Sin `set_load` en vci =
  fiel al vendor (PROFUNDO:392).
- Curiosidad sin acción: en stock2 el padre `ldob19` trae `proxy-supply = <0x150>`,
  idéntico al phandle propio de L19B (auto-referencia del decompilado). Quirk del DT
  vendor que embarca y funciona en Android; no afecta al port.

## 3. Diff: OK (6 hunks, literales salvo lo declarado)

- `patch -p1 --dry-run` + aplicación real en copias: **OK, fuzz 0** en los 6 hunks;
  `diff` original↔parcheado muestra **cero líneas eliminadas** (puramente aditivo).
  Hunk DT: `fragment@10` tras `:566`; el `target-path` es idéntico al de `fragment@9`
  (`fase4-display.dts:561`).
- Literalidad vs L27: `set_voltage(2600000,3544000)`, `L27-vci-ok`, `L27-vci-absent`,
  `get_optional`, disables — texto idéntico (comparados línea a línea). Desviaciones:
  (a) probe reposicionado tras el bloque inherit — confirma­do que en L27 iba tras el
  `bulk_get` y antes del `gpiod_get` (`:714-732`); gets independientes + cleanup devm =
  funcionalmente idéntico, y evita partir el hunk 6 de s3. (b) blank extra en unprepare —
  cosmético. (c) Omisión del disable en el `err` de `prepare` (L27:438-439): existe,
  se omite como se declara; el motivo es real (el hunk de s3 sobre esa línea,
  `docs/historia/revision/PIPELINE-PANEL-20261014/s3-reset-tddi.diff:44-49`, comparte contexto `bulk_disable/return`).
  Efecto de (c): un `prepare` fallido deja +1 refcount en L19 hasta reboot; inofensivo
  para el diagnóstico (el criterio FALLA exige vci votado de todos modos) pero **debe
  volver en el pase de hardening**, como la propia S1 dice (§3).
- Combinación: **s1+s3 idéntico en ambos órdenes** (s3-tras-s1 aplica con offsets
  4–28 líneas, fuzz 0 — desplazamientos esperados, deterministas); **s1+s5a idéntico
  en ambos órdenes** (offsets ≤53, fuzz 0); s2/s4 tocan solo `dsi_host.c` (disjuntos
  por fichero). Ojo integrador: s1 usa rutas proyecto-relativas y s3 rutas
  árbol-relativas; no se aplican con el mismo `-p1` desde la misma raíz sin adaptar.
- Alcance correcto: el poke extra `K47-pan-pwron` de L27 NO se porta (no es vci).

## 4. DT e integración: CORRECTA (con 1 aviso, nota N2)

- `fase4-display.dts` existe; `fragment@9` es el último (`:558-566`); `fragment@10`
  libre; `/dts-v1/; /plugin/` en `:53-54`. El parcheado compila (`dtc -@`, solo los
  warnings preexistentes) y `__fixups__` gana
  `L19B = "/fragment@10/__overlay__:vci-supply:0"` — **idéntico mecanismo que el
  `&L8B` existente**. La resolución final contra `__symbols__` de la base viva la
  cubre el gate `fdtoverlay` declarado en S1 §4.
- La nota de integración es correcta: `mkdtbo-s280.py` no compila fase4 — descompila
  (`:71`), empalma texto (`:197-205`, G4) y recompila con `dtc -@`, con gate
  `fdtoverlay` (G5). El `fragment@10` hay que llevarlo al script del s28x.

## 5. Criterio: MEDIBLE Y PREFIJADO ✓

PASA = `L27-vci-ok` + `vci(L19,2.6V) ENABLED` + `use 1` en `pmxr2230_l19` + firma de
muerte distinta de L33; FALLA = muerte idéntica con vci votado (refuta «sin vci el
TDDI no escucha», sin reintentos — techo 3 ciclos). Guardas correctas: `L27-vci-absent`
= build incompleto (no refutación); `enable FALLO` = parar la línea. Comandos concretos
(`dmesg -n 7`, doble captura, `regulator_summary`). Nada que objetar.

## 6. Pregunta clave (¿falta algo del vendor?): NO nada imprescindible

vddio queda cubierto por identidad física (mismo rail L8, mismo phandle `0x14f`;
`supplies[0]` lo vota a 1,9 V vía `fragment@3`). vsp/vsn `boot-on` se re-votan sin
glitch (PROFUNDO §4.3). pinctrl/reset son S3, bien excluido. Único micro-interrogante:
el vendor no documenta delay post-vci (los 2 ms son elección de L27 que s1 hereda);
en la dirección inofensiva (un sleep no rompe secuencia). Hipótesis marcada como tal:
si vci votado + muerte idéntica, el siguiente candidato es reset/TDDI (S3), no más rails.

## Notas (menores, corregir al integrar)

- **N1 (cita)**: S1 §2 y el comentario del diff yuxtaponen «`vci-supply=0x150`» con
  «`stock2…:6956`», pero **`stock2` tiene 0 hits de `vci`**. La evidencia directa del
  `0x150` es `dt-fusionado-s238.dts:1280,1300` (+ identidad `:7989-7998`); stock2 solo
  aporta nodo/tensión/símbolo de L19. Corregir la cita al integrar (el hecho es cierto,
  la atribución no). Igual el «PROFUNDO:380-381»: la fila vci está en `:382`.
- **N2 (integración)**: el script s280 declara filosofía «sin fragmentos nuevos, sin
  phandles nuevos» (`mkdtbo-s280.py:85-86`); `fragment@10` + label externo `L19B`
  rompe ese patrón en la vía de empalme de texto — el integrador debe verificar que el
  fixup sobrevive al splice y que `fdtoverlay` resuelve `L19B` contra la base **viva**
  (yo solo lo verifiqué contra stock2/s238, no contra el dtb base del s286). El gate
  lo caza antes de flashear; clasificar un fallo aquí como «build incompleto», no como
  refutación de vci.
- **N3 (atribución)**: las medidas en vivo (L19 `use 0/0`, `vci-supply` ausente) son de
  S3 de hoy (`docs/historia/revision/PIPELINE-PANEL-20261014/S3-RESET-TDDI.md:19-23`, verificado que existen); S1 lo atribuye
  correctamente y declara su propio SSH fallido. Sin objeción; re-medir en el ciclo
  como S1 §6 pide.
