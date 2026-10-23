# S1 — vci (P0): alimentación del panel, driver + DT (14-oct-2026)

## 1. Qué he leído (lista con fichero:línea de lo relevante)

Driver (vivo vs linaje con vci):
- `build/kernel-pokes/k52-L16-tree/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c:48-61` (struct, sin `vci`), `:84-88` (tabla de 3 supplies), `:291-323` (`o82_power_on`, sin voto vci), `:635-638` (probe, solo bulk), `:450-453` (unprepare). `grep -c vci` = **0**.
- `build/kernel-pokes/k52L27-tree/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c:56-59` (campo `vci`), `:309-326` (voto vci en power_on), `:354-355`/`438-439`/`476-477` (disables), `:721-732` (get_optional + `L27-vci-absent`). El soporte vci existió y se perdió entre L29→L33 (confirmado por `PREP-MINUCIAS-20261013.md:27-32`).

DT y rail:
- `build/gates/patches/k52L39-fuentes/fase4-display.dts:358-364` (`panel@0`: solo `vddil8b/vsp/vsn-supply`), `:108-110` (`&L8B`, mismo mecanismo de referencia externa), `:53-54` (`/dts-v1/; /plugin/;`), `:560-567` (fragment@9 + cierre; el siguiente libre es `fragment@10`).
- `build/evidencia/stock-dt/stock2-Cliffs7P-uke.dts:6956-6966` (`pmxr2230_l19: L19B`, min `0x27ac40`=2600000, max `0x3613c0`=3544000, init `0x27ac40`, phandle `0x150`), `:20727` (símbolo `L19B`).
- `docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:374-414` (§4: identidades vddio=L8/vci=L19, orden vddio+vci → vddil8b→vsp→vsn, loads 300 mA + 2 ms; §4.3 tabla: vci portado en L27 pero opcional).
- `docs/historia/revision/ROADMAP-PANTALLA-20261013.md:93` (FASE 3.2: añadir `vci-supply` al dtbo, L19 2,6 V).
- `build/gates/revision/PREP-MINUCIAS-20261013.md:18-140` (análisis previo §(a): driver vivo sin vci + DT sin `vci-supply` + hunks propuestos; mi diff los materializa y verifica).

Coordinación:
- `PIPELINE-PANEL-20261014/S3-RESET-TDDI.md:19-23` (medidas de hoy en vivo: L19 2600 mV `use 0/0`, `vci-supply` ausente en `panel@0`, vsp/vsn OFF), `:45-55` (hunks S3 y reparto: vci = S1), `:74-79` (qué no toca S3).
- `PIPELINE-PANEL-20261014/s3-reset-tddi.diff`, `docs/historia/revision/PIPELINE-PANEL-20261014/s2-g8.diff` (solo `dsi_host.c`), `docs/historia/revision/PIPELINE-PANEL-20261014/s5a-pps-dual-link.diff` (`@@ -29` includes, `@@ -360` prepare) — verificado §3 que mis líneas cambiadas no intersectan.
- `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md:12754,12774-12863` (s286 `33d153f2…` vigente en `dtbo_a`; no se toca desde aquí).
- `~/proyectos/ubuntu-permanente/docs/REFUTADO.md` + `LECCIONES.md`: `grep -i vci` = **0 coincidencias** (nada prohíbe esta línea).
- Tablet: **inaccesible por SSH en esta sesión** (2 timeouts a `192.168.42.129`, 14-oct ~09:1x). No re-medí nada en vivo; los datos vivos citados son los de S3 de hoy (atribuidos). Regla: solo lectura en cualquier caso; no se flashea ni se toca nada desde esta sección.

## 2. Estado real del asunto (evidencia)

**Corrección a la premisa del encargo:** «el driver ya soporta `vci-supply`» es falso para el árbol vivo (0 hits de `vci` en `k52-L16-tree/.../panel-xiaomi-o82-dualdsi.c`); era cierto para L27. **Faltan las dos mitades**: el driver no consume `vci` y el overlay no lo declara. Solo-DT sería un no-op silencioso; solo-driver no compila/vota nada sin el supply. El diff trae ambas mitades o nada.

Rail (hechos, no inferencia): `pmxr2230_l19` = L19, 2,6 V init, rango 2,6–3,544 V, `proxy-consumer-enable` (stock2:6956-6966). Android lo vota en `pre_prepare` junto a vddio(L8) y **antes** de vddil8b→vsp→vsn (PROFUNDO §4.2). vddio es el mismo L8 físico que vddil8b (`vddio-supply` y `vddil8b-supply` = phandle `0x14f`, PROFUNDO:380-381) → ya cubierto por `o82_supplies[0]`; el único voto que falta es vci. En vivo L19 existe a 2,6 V pero con `use 0/0` y `panel@0` no lo referencia (S3:21-22): el TDDI arranca sin su rail analógico — candidato P0 directo al «el panel no escucha» (primer DCS `cmd#0 → FIFO → TIMEOUT`).

Resolución de `&L19B`: idéntico mecanismo que el `&L8B` que el overlay ya usa (fase4:12 «targets por `__symbols__` del vendor»; símbolo `L19B` en stock2:20727, misma tabla que `L8B`). Si el símbolo faltara en la base viva, el gate `fdtoverlay` lo caza antes de flashear (ver §4).

## 3. Cambio propuesto (diff exacto, con fichero:línea)

`docs/historia/revision/PIPELINE-PANEL-20261014/s1-vci.diff` (`patch -p1` desde la raíz del proyecto; rutas repo-relativas para ambos ficheros — la parte de driver indica el fichero del árbol `k52-L16-tree`). 6 hunks, 0 intersecciones con s2/s3/s4/s5a (verificado por aplicación real en /tmp en ambos órdenes, §6):

DT (fuente del overlay; el pipeline s28x genera el dtbo por text-patch sobre dtbo decompilado — `mkdtbo-s280.py:71,197-205` —, así que el integrador debe llevar este mismo `fragment@10` al script del s28x o recompilar desde fase4):
1. `fase4-display.dts` tras `:566` — `fragment@10 { target-path = ".../dsi@ae94000/panel@0"; __overlay__ { vci-supply = <&L19B>; }; }`.

Driver (restauración literal de L27, 5 hunks):
2. Struct (`:53-55`): campo `struct regulator *vci;` + comentario (literal L27:56-59).
3. `o82_power_on` (`:293-297`): bloque vci **antes** de los 3 rails — `set_voltage(2600000,3544000)` (fallo no fatal) + `enable` + 2 ms + poke `L27-vci-ok` (literal L27:309-326). Orden = vendor (vci junto a vddio/L8, antes de vsp/vsn). Sin `set_load`: el path vendor (`dsi_pwr_enable_regulator`) no lo pone (PROFUNDO:392).
4. `err` de power_on (`:317-322`): `if (ctx->vci) regulator_disable` (literal L27:354-355).
5. `o82_unprepare` (`:452-454`): mismo disable (literal L27:476-477; el blank se recoloca tras el bloque para no partir el hunk de unprepare de s3 — funcionalmente idéntico).
6. Probe (tras `:651-654`, bloque inherit): `devm_regulator_get_optional("vci")` + `L27-vci-absent` si `-ENODEV` (literal L27:721-732; **reposicionado** tras el bloque de reset — en L27 iba antes del `gpiod_get` — para no partir el hunk 4 de s3; gets independientes con cleanup devm = funcionalmente idéntico).

Verificación del diff (comandos + salida, todo en /tmp, árbol intacto):
- `patch -p1 --dry-run` y aplicación real sobre copias prístinas: OK; resultado byte-idéntico a la referencia generada por reemplazo exacto (cada ancla `count==1`).
- s3→s1 y s1→s3 (hunks de driver con rutas de árbol): ambos OK, mismo fichero final byte-idéntico. s5a→s1 y s1→s5a: ambos OK, idéntico resultado. s2/s4 tocan solo `dsi_host.c`: disjuntos por fichero.
- Deliberadamente **omitido**: disable de vci en el `err` de `prepare` (L27:438-439). Su única ubicación posible parte en dos el hunk de s3 sobre la línea gpio en un orden de aplicación; además solo corre si el init ya falló (criterio fallado de todos modos) y el rail queda con refcount del núcleo hasta reboot. Se recupera en el pase de hardening, no en este ciclo.

## 4. Criterio pasa/falla prefijado (comando + salida esperada)

Flash con display habilitado (quitar `:d` de la cmdline; requiere FASE 1 del ROADMAP — sin bind no hay prepare). Gates previos obligatorios: `fdtoverlay -i <base.dtb> -o <merged> <overlay.dtbo>` en verde (regla AGENTS nº1), `dmesg -n 7` antes del disparo (los `UKE-P82` son KERN_INFO), doble captura consola ACM + `dmesg -w` por SSH, presupuesto slots/batería del ledger.

- **PASA** si en `dmesg`: `L27-vci-ok` + `UKE-P82: power_on: vci(L19,2.6V) ENABLED`, y `regulator_summary` muestra `pmxr2230_l19` con `use 1` (voto tomado), **y** la firma de muerte se mueve respecto a L33 (p. ej. `cmd#0` con respuesta, o timeout distinto al `video-done` de HALLAZGO-L33). Sin DT nuevo, `L27-vci-absent` + 3 rails = comportamiento actual (build incompleto, no refutación).
- **FALLA** (refuta «sin vci el TDDI no escucha») si: con `L27-vci-ok` + L19 votado, la muerte es idéntica a L33 (`video-done timeout` en `cmd#0` tras reset completo). Anotar «vci refutado como causa del silencio» y NO reintentar (techo 3 ciclos por hipótesis).
- Señal que **para** la línea: `vci: enable FALLO %d` en el primer prepare (rail reclamado por otro consumidor o rango rechazado) → no insistir, diagnosticar `regulator_summary` en frío.

## 5. Riesgos y refutaciones que aplican (REFUTADO/LECCIONES)

- Nada en REFUTADO.md/LECCIONES.md menciona vci (grep vacío §1): vía libre, sin rondas previas que repetir.
- Riesgo bajo por diseño: `get_optional` + `NULL` = comportamiento actual si el DT no llega; con DT, un voto enable más en el orden vendor. El `set_voltage` no fatal absorbe discrepancias de rango del DT vivo.
- LECCIONES regla 5: `sync` antes de resets; ≤2 escrituras/día; registrar slots y mV en la fila del ledger. Regla 9: no dejar scripts que alteren estado (este cambio es solo build + flash, sin runtime).
- Un cambio por ciclo: este diff es **alternativa** a s3 para el ciclo de mañana (vci P0 primero, por orden del BRIEF), no acumulable salvo decisión explícita del dueño.

## 6. Qué NO hacer / lo que queda fuera

- **NO** tocar reset/gpios/doble-reset (S3), host DSI/G8/pulsos (S2), PPS-DSC (S5), ni `CLOCK_NON_CONTINUOUS`, backlight, `ktz_bl_*`, pinctrl/TE/ESD-flags (S6 o ya verdes).
- **NO** poner `enable-load` a vci ni `regulator-boot-on`: el vendor no lo hace en ese path (PROFUNDO §4.2); inventarlo sería una segunda variable.
- **NO** el disable de vci en el `err` de `prepare` (omitido deliberadamente, ver §3).
- **NO** flashear ni tocar la tablet desde esta sección; **NO** usar `fastboot boot` como vehículo (usa el dtbo del slot = s286 sin vci; LECCIONES regla 7).
- SSH propio fallido (2 timeouts): reintentar la medida `regulator_summary` + `panel@0` en el ciclo de mañana con RNDIS vivo antes de flashear (re-medir L19 `use` tras el ciclo = parte del criterio §4).
