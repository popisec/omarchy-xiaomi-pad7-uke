# PLAN DE TRABAJO — omarchy-uke (v4, 1-oct-2026) — OBJETIVO: GPU + PANTALLA

> ## ⚠️ CORRECCIÓN 1-oct-2026 (tarde, posterior a la ronda de crítica): EL FIX K24 CAMBIA DE NATURALEZA
>
> **El volcado del CM3 decodificaba `S2CR` al revés** (`a6xx_gmu.c:324` imprimía
> `type = s2cr & 0x3` y `cbndx = (s2cr >> 16) & 0xff`, cuando `arm-smmu.h:113-120` define
> `S2CR_TYPE = GENMASK(17,16)` y `S2CR_CBNDX = GENMASK(7,0)`). Con el decode correcto, lo que
> hay **medido** en la consola es:
>
> ```
> SME(1): SMR=0x80000005 (valid=1 id=0x0005) S2CR=0x00000001  →  type=TRANS  cbndx=1
> SME(2..5): SMR=0x00000000 (invalid)         S2CR=0x00020000  →  type=FAULT  cbndx=0
> ```
>
> **El SID 5 (el icache del CM3) está VÁLIDO y en TRANS por CB1.** Por tanto:
> - ❌ REFUTADO: «el SMR quedó inválido → el SID va a *unmatched* → bypass → fetch de física
>   0x4000 = basura». Salía de leer mal la fila `SME(2..5)`, cuyos SMR son inválidos.
> - ❌ REFUTADO: «hay que programar SMR/S2CR/CB antes del release» (el K19 tal como se diseñó).
>   El S2CR **ya está bien**.
> - ✅ **K24 = mapear el icache@0x4000 en la tabla de CB1** (el subcaso 2 de §P2.4, que el plan
>   ya tenía contemplado y que este dato por fin justifica).
>
> **Y el dump no podía responderlo**: el SMMU es un **MMU-500** (`palawan.dtsi:2536-2539`:
> `reg = <0x3da0000 0x40000>`, `compatible = … "qcom,smmu-500", "arm,mmu-500"`; el arranque
> imprime `SMMUv2 with: … 22 context banks`), así que `CBn = (numpage + n) << pgshift` con
> `numpage = 1<<(NUMPAGENDXB+1)` = **CB0 en 0x20000, stride 4 KB** (por el tamaño del recurso sin
> aviso de mismatch: `2*numpage<<pgshift == 0x40000` ⇒ pgshift=12, NUMPAGENDXB=4). Los dos bucles
> del dump leían `0x8000+i*0x1000` (que en SMMUv2 es la tabla de S1CD, no las CB — de ahí que no
> hubiera **ni una** línea `CB(`) y `(i<<16)` (stride de 64 KB, SMMUv3). **CB1 = 0x3dc1000: ninguno
> de los dos la leía.** Además el ioremap de 2 MB de K23 se salía del recurso (0x40000) hacia
> `gpu_qtb@0x3de8000`.
>
> **Consecuencia operativa**: el gate «no flashear K24 sin `CBpage`» (§R4) **no se puede evaluar con
> el K23 flasheado**: su volcado es ilegible por construcción. Por eso el siguiente artefacto es
> **K23b = el dump corregido** (geometría del ID1, decode bueno, ioremap ceñido al recurso, 8
> descriptores para que el del icache@0x4000 sea el índice 4, y `pr_flush` tras `S3-rst0`), y
> **K24 se espera a leer la tabla de CB1**. Un cambio por ciclo.
>
> Evidencia: `NOTAS-OMARCHY.md` (1-oct, «decode S2CR y geometría CB») y
> `build/gates/revision/V2-critica-k23b.md`.

> **Sustituye a `docs/historia/PLAN-SIGUIENTE-v3.md`** en todo (orden del dueño: «pantalla + GPU del todo; el
> resto después»). **v4 = v3 + la ronda independiente de crítica EJECUTADA** (4 subagentes
> solo-lectura, 37 hallazgos: 1 BLOQUEANTE, 11 ALTA, 17 MEDIA, 8 BAJA) + verificación
> independiente de la autocrítica C1-C14 de v3. Informe íntegro de los 4 críticos:
> `build/gates/revision/V1-critica-plan-v3.md`; el mapa hallazgo→resolución está en §7 de este
> fichero. Lo que cambia la ejecución está ya incorporado en §1-§6; lo marcado «[P0]» es tarea
> offline de la próxima sesión (0 tablet).
>
> **Restricciones**: esta planificación NO toca la tablet. Git: commits locales selectivos. Toda
> ejecución empieza releyendo `docs/historia/ESTADO-VIVO.md` y las últimas filas de
> `build/gates/PRE-REGISTRO-PANTALLA.md`.

## §1 Estado de partida (1-oct; sin cambios de aparato desde ESTADO-VIVO 03:00)

| Dato | Valor | Fuente |
|---|---|---|
| Tablet | **ZOMBI** (ping 2/2; puertos 22 y 5555 cerrados) | medido 1-oct; ESTADO-VIVO |
| Slot activo | **a** (experimental desde F9, #P45) | ESTADO-VIVO; #P45 |
| `boot_a` | **K23** `8e7ed4f9…` (96 MiB), cmdline dsid (**con** `video=DSI-1:d`) | §1 de v3; sha verificado en disco |
| ⚠️ Fichero del K23 | vive como `build/bootimg/boot-ukek18d.img` (nombre de K18d pre-registrado en #P47 con OTRO sha `99d49b06…`); `repack-k18.py:38` pisa ese nombre. **[P0] renombrar a `boot-ukek23.img` + sha propio; prohibido re-ejecutar `repack-k18.py` sin destino distinto** | crítico operativo O2 |
| `dtbo_a` | **s263** `fe06fccc…` (GPU+GMU al SID 5) | #P48; sha verificado |
| Slot b (rollback, INTACTO) | boot **K13-dsid** `e0ee47dc…` + dtbo **s260** `6fbb5173…` — shas en `SHA-BUENOS.txt:48-49`, copias en `backup-par-bueno/` verificadas por el crítico operativo | verificado hoy |
| Vigía fastboot | PAUSADO y sin proceso vivo (`/tmp/uke-fastboot-watch.pause`) | medido 1-oct |
| Consola | Lector único vivo (PID ~8778, loop `timeout 2 cat` sobre **ACM0 hardcodeado**; log `/var/tmp/uke-sesion-console.log` 2,1 MB). **[P0] sustituir por el patrón SIN timeout de #P40 (el actual pierde la ventana 3,95-4,18 s) y verificar re-enumeración de nodo** | crítico operativo O6 |
| Semáforo hermano | libre (ledger #449 = última fila, sin filas posteriores) | verificado por crítico |
| **Presupuesto de escrituras de HOY** | **AGOTADO DE SOBRA: ≥5 documentadas en 1-oct** (ledger #447-#449: s263→dtbo_a, K20d→boot_a ×2, K22, K23; v3 decía «2» — error corregido por M1). **Cualquier escritura más = re-negociación EXPLÍCITA del presupuesto del día por el dueño, anotada en la fila** | ledger hermano #447-#449 |

**Qué contiene K23** (cadena acumulada, ídem v3): k16-split + k17-migas (P82, S0, S4) + K18-kgsl-keep
+ K19-dump (SME/CBpage/tablas) + K20-gmu-shared + K22-fw-en-initramfs (`lib/firmware/qcom/`) +
K23-ioremap-2MB. **Marco honesto**: K23 es **instrumentación** (fix del dump, no del CM3); el fix
esperado es **K24**. Medido en K22: fw cargan a 4,07 s y la escalera corre en el arranque hasta S2.

## §2 Criterios de «hecho» (v4)

| Objetivo | Hecho = | Cambio v4 |
|---|---|---|
| GPU (OBJ 5 / F1a) | `eglinfo -B` = `freedreno` + **GLES 3.2** sobre `renderD128` **+ 1 repetición tras power-cycle en frío** | M9: persistencia simétrica con pantalla |
| Pantalla (OBJ 6 / F1b) | `card0` + conector o82 con `modes` 3200×2136 + **FOTO** + persistencia (cold boot + 2ª FOTO) | ídem v3 |
| **FOTO operacionalizada** | el dueño fotografía el panel → copiar a `build/logs/evidencia/P5x-foto-{1,2}.jpg` + sha256 anotado en la fila `#P5x`; **sin fichero la fila no cierra** | M6 (nuevo) |
| **Cierre de ESTA sesión** | «OBJ 5 y/o OBJ 6 cerrados por sus propias filas» + evidencia; el intermedio realista («pantalla pinta / GPU rota» o viceversa) se documenta como tal. **«Hyprland+quickshell en panel» NO es criterio de hoy** (F6 sin instalar; pertenece a F6) | M5 |
| Honestidad | Nada se declara hecho sin evidencia en fichero + relectura sha256 + repetibilidad tras frío. **Un éxito de P2-ctrl (modetest) es diagnóstico y NO cierra OBJ 6** | D9 |

## §3 Fases

### P0 — Despertar y veredicto del CM3 (0 escrituras) ~30-60 min

0. **[P0, offline] Pre-registro de la predicción** (M8): fila `#P50` en `PRE-REGISTRO-PANTALLA.md`
   ANTES del power-cycle (0 escrituras): «predicción: **B, C o F** (nada en K23 arregla el CM3);
   D refutaría el fix del ioremap; E = muerte pre-S2 no modelada (discriminador: última miga
   visible); A exige revisión doble». La predicción queda comprometida antes de medir.
1. **Antes del power-cycle** (PC, [P0] donde se indica):
   - Consola: comprobar nodo real (`ls /dev/ttyACM*` — re-enumeración = loop ciego; relanzar matando
     el `cat` huérfano) y **sustituir el loop `timeout 2 cat` por `cat` sin timeout con guard
     `[ -e ]`** (patrón #P40 que capturó la ventana 4,20 s — O6). Snapshot del log vivo a
     `build/logs/antes-despertar.log`.
   - Vigía: confirmar pausa; fastboot-poll en la ventana de arranque (`while :; do fastboot devices;
     sleep 5; done`) **+ poll SSH** (`until build/gates/uke-ssh.sh 'echo ok'; do sleep 3; done` — O6).
2. **Power-cycle** (dueño: power ~12 s + toque). Desenlaces:
   - (i) arranca K23 (slot a) → paso 3.
   - (ii) cae a fastboot → `fastboot getvar all` + `battery-voltage`; **gate de mV: prohibido
     reintentar slots sin mV leído** (O8); si mV < 3700: camino de carga de §5 antes de reintentar.
     Después `set_active a` + `reboot`, o `set_active b` (par estable) según la consola.
   - (iii) ni consola ni USB → batería/teclas; no insistir (watchdog sin arreglar).
3. **En cuanto responda SSH: capturar primero, fsck después** (el zombi llega a ~280-400 s):
   ```sh
   # CMD1: copia íntegra del anillo dmesg DENTRO de la tablet + volcado al PC (grep en local):
   build/gates/uke-ssh.sh 'dmesg -n 7; dmesg > /dev/shm/dm.txt; cat /dev/shm/dm.txt' \
     | tee build/logs/despertar-s3s4-full.log
   # CMD2: estado drm/kgsl (después de asegurar CMD1):
   build/gates/uke-ssh.sh 'cat /sys/bus/platform/devices/3d00000.qcom,kgsl-3d0/power/runtime_status; ls /sys/class/drm/; cat /sys/class/drm/card0-DSI-1/status' \
     | tee build/logs/despertar-drm.txt
   # El grep de migas se corre EN EL PC sobre despertar-s3s4-full.log, con la lista EXTENDIDA (K2):
   grep -aE "UKE-K1[789]|K19-dump|K21 completo|CBpage|SME\(|S[0-9]-|S4-poll|H[89]-|H5-|H10-|P3-|CM3DBG|cfg_probe|Loaded GMU|UKE-P82|sCR0"
   ```
   Si la sesión SSH no llega: consola ACM (nueva captura sin timeout) + `antes-despertar.log`.
   **Rama C declarada (D7)**: el cuelgue puede ocurrir dentro de `msm_open` del fbdev a ~4,2 s sin
   llegar a SSH; que S0-S3 alcancen la consola es NO VERIFICADO — la mitigación (loglevel bajo,
   ftrace) se prepara offline si el árbol cae ahí.
4. **Árbol de decisión — AHORA 6 ramas** (K1 añade F; K2/K6 matizan A/B/C; código:
   `a6xx_gmu.c:408-421`; el dump corre entre S2 y S3):

   | # | Patrón en `dmesg` | Lectura | Siguiente |
   |---|---|---|---|
   | A | `K19-dumpOK` + `S3-rst0` + `S4-pollOK` + `H8-cm3`/`H9-hfiq` **+ `H10-hfi` sin `FAIL`** | CM3 arrancó y el HFI respondió: GPU viva punta a punta (sin `H10-hfi` OK no se cree la rama A — K2) | P2-ctrl (sonda de panel) y P1 |
   | B | `K19-dumpOK` + `S3-rst0` + `S4-pollFAIL` (~100 ms) | release volvió; CM3 no arrancó; **fallo limpio**: GPU ausente (`runtime_status` esperado: `suspended`; `active` ⇒ contradicción, releer — K6); el sistema sigue | leer `CBpage` → K24; panel: **P2-ctrl**, y P2-skip como artefacto (K5) |
   | C | `K19-dumpOK` + **sin** `S3-rst0` | la escritura del release no retorna (stall K20-style) | leer `CBpage` → K24; panel: P2-ctrl (con skip si el boot no llega) |
   | **F** | `K19-dumpOK` + `S3-rst0` + **ni `S4-poll*`** | **el primer readl del poll wedgea** (firma exacta de #P47, U2 §4); máquina probablemente muerta (hung_task 20 s → panic) | `CBpage` ya impreso → K24; recuperación §5, rollback a b |
   | D | `K19-dump` sin `dumpOK`, o WARN/machine-check | el dump volvió a fallar | K23b (fix), **techo 1 fix** (M7); alternativa ftrace |
   | E | ni `K19-dump`, o el boot no llega | muerte pre-S2 no modelada | consola + WARN; rollback a b si toca; techo 3 ciclos/hipótesis |

   **Esperado: B, C o F** (nada en K22/K23 arregla el fetch del CM3 — §1). Si sale A, revisar dos
   veces antes de creerlo. Notas de lectura del dump (K3): el dump solo decide «tabla
   inválida/blocked» — si `L[0]` es un table descriptor, el destino de 0x4000 vive un nivel más
   abajo (no leído) → ir directo al fix K21-style; `CBpage(i)` NO es el banco `i` (usar `cfg_probe`:
   pgshift/NUMPAGENDXB/numpage, ahora en el grep).
5. **e2fsck** ANTES de cualquier ciclo nuevo — **con el flujo PROBADO, no el §A.2 de P7** (O1:
   P7 §A.2.4/§A.2.5 fueron refutados en vivo por el ledger #446: journald resurrecta y sshd muere
   en kex con `/` en ro): flujo `docs/historia/RUNBOOK-SIGUIENTE.md` Paso 4 / ESTADO-VIVO (parar los 3 sockets de
   journald + UNA sesión SSH persistente abierta ANTES del remount ro + auto-reboot integrado).
   Empezar por el inventario `-fn` (0 riesgo; esta congelación terminó en unmount limpio). Mount ro
   SIEMPRE con `norecovery` (O5). Sin SSH: §A.3 exige shell vivo (ttyGS0) — sin shell real, la única
   vía es flash con e2fsck en initramfs (1 escritura → exención) o quedarse en `-fn`. El fs real es
   105,8 GiB (no 8): el fsck puede exceder la ventana zombi — si el zombi llega durante el fsck:
   esperar/reconectar (A.2.6.1), NO rebotar (O7). Nota para el operador: la precondición P7 A.2.1.1
   («slot b estable») NO aplica hoy — se corre sobre slot a; B intacto es la red (O9).

### P1 — GPU de punta a punta (0 flashes; rama A, o tras K24) — cierra OBJ 5

1. **Staging de userspace** [P0 si se quiere adelantar]: `build/pkg/` NO tiene mesa; obtener
   `mesa libdrm mesa-utils` (aarch64) por el canal USB documentado (A1-auditoría-instalador §4 /
   v2 P3.5) y verificar sha al copiarlos (R7).
2. `eglinfo -B` con doble captura viva y **una sola apertura desprendida** (G1 §5c). Criterio:
   `freedreno` + GLES 3.2. En rama A: recordar K5 — cada `open()` re-corre la escalera solo si el
   GPU quedó en NULL; en A está vivo, sin re-corrida.
3. Si el render falla pero S4 llegó: escalera `Z2`/zap + `measure-cm3.sh` (sin más flashes).
4. Registrar (PRE-REGISTRO + ledger + OBJETIVOS fila 5).

### P2 — Pantalla (orden v4; presupuesto en §4)

**Orden de los tests (cambio BLOQUEANTE D1 + M2 + K5):**

1. **P2-ctrl (NUEVO — sonda de panel 0 escrituras, SIEMPRE primero; aplica en ramas A, B y C)**
   El boot actual (K23-dsid) es estable por SSH y ya lleva las migas UKE-P82: el panel se ejercita
   bajo captura sin flashear nada. Escalera de agresividad creciente, cada peldaño con `dmesg -w`
   al PC y una sola apertura desprendida (G1 §5c):
   - (a) Lectura: `ls /sys/class/drm/`, `status`/`modes` del o82, `regulator_summary` (D5).
   - (b) **Conector Writeback**: commit atómico con FB_ID → ejercita DPU+DMA+scanout hacia memoria
     SIN panel; si wedgea el asesino es DPU/DMA, si no es panel-side (D6).
   - (c) Backlight-only si el panel probeó (D6).
   - (d) `modetest -M msm -c` (una apertura) → (e) `modetest -s <conn>@<crtc>:<mode>`.
   OJO (corrección de v3): el veto «modetest abre → CM3» contradecía #P43 (con el fw sqe oculto el
   resultado fue EL MISMO: el asesino de modetest NO es la carga del GPU). Precaución que sí vale:
   peldaños cortos, captura armada antes, techo de intentos por peldaño, y NO abrir card0 si el
   boot anterior murió en rama C/F con la máquina inestable. **P2-ctrl es diagnóstico: no cierra
   OBJ 6** (D9).
2. **P2-skip** — [P0 offline ya]: parche `msm.uke_skip_load_gpu=1` (~5 líneas en `msm_drv.c:198-207`,
   diseño U2 §4) **+ miga temprana `UKE-K24: skip_load_gpu=1` antes de cualquier `load_gpu` como
   gate** (D8: hoy ni el parche ni el gate existen — grep vacío verificado) + **quitar
   `hung_task_panic=1` de la cmdline** (D2: cada muerte de panel con el flag heredado = pánico +
   reboot sucio + dmesg perdido; K20 midió el mismo stall como local y la máquina VIVE).
   Param **por cmdline** (en rama C el primer open cuelga en el boot: no hay «flip en caliente»).
   Es el artefacto preferente de panel en ramas **B/C/F** (K5: en B cada `open()` de card0
   re-corre la escalera GMU entera — el re-lanzamiento del CM3 N veces no está medido; el skip lo
   elimina) y el aislador del segundo-asesino.
3. **P2-plain** (repack sin `video=DSI-1:d`, mismo kernel): **SOLO rama A** (M2: bajo B la premisa
   «GPU falla limpio ⇒ modeset corre» NO está medida — G1 §5b: sin GPU no hay card0 porque el open
   dispara `load_gpu`; #P48 midió «GPU ausente → sin card0». Si algún día se quiere plain bajo B:
   pre-registrar primero la predicción «bajo B existirá card0»). **Antes de volarlo**: añadir
   offline las migas que faltan (D3) — encoder enable, config DSC, dsi host enable, frame-done/
   vblank, + `drm_client_setup`/fbdev + salida de `get_modes` — porque la zona tras «prepare:
   COMPLETO» no tiene NINGUNA miga hoy y es el sospechoso (d) entero; y no prometer «punto exacto»
   hasta medir que las migas son visibles en esa ventana (D4: K17-plain jamás voló; la visibilidad
   de P82 en muerte real es NO VERIFICADA).
   Desenlaces: (a) fbcon pinta → FOTO + persistencia → P3. (b) vive sin pintar → P2-ctrl ya habrá
   dicho por qué. (c) muere → última miga UKE-P82 (en su caso) = punto aproximado.
4. **K24** (fix del mapeo del CM3) — **REDISEÑADO el 1-oct tras la corrección del decode (ver banner)**.
   El S2CR del SID 5 ya está en TRANS por CB1, así que **el subcaso 1 (programar SMR/S2CR/CB) queda
   REFUTADO** y el fix es el subcaso 2. Queda así, con gates:
   - **Gate 0 (K4, ya medido en parte)**: `sCR0` con CLIENTPD=0 (medido `0x002f0406` → bit0=0 ✓) y
     `S2CR(1) = type TRANS (0) cbndx 1` (medido ✓). Los dos gates que el plan pedía para el subcaso 1
     **ya no aplican**: no hay que programar nada del S2CR.
   - **Gate 1 (el nuevo, y es el que hay que medir)**: la tabla de **CB1** (`0x3dc1000`) — con el
     volcado corregido de K23b, `CBpage(1) off=0x21000: SCTLR=… TTBR0=…` más los 8 descriptores.
     - Si el descriptor que cubre `0x4000` (índice **4** con granularidad de 4 KB) es un bloque/
       puntero a tabla **válido** → el mapeo ya existe y K24 no es aquí: el problema es otro
       (subcaso 3) y hay que buscar quién más toca la CB1 o si el CM3 arranca con el TCM en otra
       dirección.
     - Si es 0x0 / no válido → **K24 = insertar la entrada** que mapee iova `0x4000` → phys del TCM
       (K21-style), en la página de la tabla que corresponda, **respetando el nivel y la
       granularidad que se lean** en `fmt`. Esto se hace desde el mismo sitio que el volcado
       (antes de `S3-rst0`), nunca en runtime.
   - **Subcaso 3 (ambos válidos → otra causa)**: ¿el TCM está en el rango que el dominio de la GPU
     traduce? (`uke_gmu_shared` mapea 0x0..0x80000000, así que 0x4000 entra, pero el TCM **físico**
     puede estar fuera del `iommu_map` que el driver hizo del `gmu_pdc`.) ojo a esto antes de tocar la
     tabla: si el PA es correcto pero el TCM no está mapeado en el dominio, el fix es un
     `iommu_map` del TCM, no una entrada de tabla.
   Mantener `video=DSI-1:d` en K24 (la GPU se prueba por `renderD128`; el panel va en P2-*).
5. **Sospechosos del panel actualizados** (D5): power_on vsp/vsn (**enable de los
   reg-fixed-voltage GPIO 74/75 — NO vía gpio-shared-proxy: 1 ref activa desde s238**), rst
   GPIO2/tlmm (probe histórico OK en el linaje s260), cmd[N] DSI host, **DSC/dual-DSI merge +
   relojes/GDSC/interconnect** (nuevos), tras prepare (scanout/DPU). Tocar rails ⇒ **GO explícito
   del dueño**.

**Presupuesto (reformulado — O4/M1)**: **0 escrituras hasta exención explícita del dueño anotada
en la fila** (el día ya superó el techo ×2 con ≥5); concedida la exención, máx 2 escrituras; el
rollback cuenta como escritura salvo que sea restauración del par de rollback.
**Regla de PARADA dura (M7/O4)**: la sesión TERMINA si (a) 2º zombi del día sin fsck verde, o
(b) 2 ciclos consecutivos sin migas nuevas, o (c) K23b+K24 sin `S3-rst0`. Al parar: estado seguro
(boot_a verificado o `set_active b`), vigía en estado documentado, ESTADO-VIVO + ledger + commit.
El techo de 3 ciclos por hipótesis (regla #11 del hermano) aplica a TODAS las hipótesis de P2.

### P3 — Persistencia y cierre

1. Artefacto final (kernel K2x + s263) verificado por relectura en slot A; cold boot + 2ª FOTO +
   `eglinfo` post-frío (M9).
2. `ESTADO-VIVO` + `NOTAS` + `OBJETIVOS` (filas 5/6 + «Orden de prioridad» — M4) + fila `#P5x` +
   ledger hermano + commit.

## §4 Reglas operativas del ciclo (obligatorias; cambios v4 en **negrita**)

- **Presupuesto/ciclo**: batería ≥3750 mV + cargador de pared; portátil enchufado. **0 escrituras
  hasta exención explícita del dueño EN LA FILA (hoy: día ya agotado con ≥5)**; concedida, ≤2.
  `getvar all` antes/después. Batería si NO hay fastboot: `prepara/bateria.sh` (exit 3 si ADSP
  caído → fallback `/sys/class/power_supply/*/voltage_now` — O8) o `getvar battery-voltage`.
- **Pre-registro**: fila en `PRE-REGISTRO-PANTALLA.md` + `FLASH-LEDGER` del hermano con sha256 del
  artefacto ANTES de flashear; relectura **al tamaño exacto** (`dd bs=1M count=96 | sha256sum`;
  anula el pad de 96 MiB). **Mismatch → NO reboot: re-dd; 2º mismatch → `set_active b` +
  diagnóstico del canal de escritura** (O10).
- **Slots**: todo a **A**; **B = rollback** (K13-dsid+s260), no se toca. `set_active a|b` como
  reset de contadores. **Prohibido reintentar slots en fastboot sin mV leído** (O8).
- **Escritura a boot_a**: TEMPRANO en la ventana; `dd` + `sync` + `drop_caches` + relectura sha +
  **reinicio limpio = `sync && systemctl reboot` + CONFIRMAR por consola/ping que cayó y volvió
  antes de dar el ciclo por lanzado** (O3: #P49 midió «Rebooting.» a 385 s → congelación a 387 s);
  power-cycle como plan B. Si el zombi corta a mitad → power-cycle y rehacer desde
  **`boot-ukek23.img`** (renombrado — O2).
- **Consola**: lector único, **patrón sin timeout de #P40** + nodo verificado; doble captura
  (ACM + `ssh dmesg`); el veredicto sale de `dmesg` completo volcado a fichero (§P0.3), no de la
  consola.
- **Vigía**: hoy pausado → recuperación manual (§5). **Decisión del dueño hoy (M10): re-armarlo
  con pausa tras leer el desenlace de P0, o declarar «tras P0 la tablet no se deja desatendida»**.
  Si se re-arma: ARMAR CON PAUSA antes del flash, `rm -f` solo tras leer el desenlace.
- **Fastboot**: por teclas físicas; en fastboot no carga bajo umbral.
- **e2fsck antes de cada ciclo con reboots sucios** (flujo RUNBOOK Paso 4, NO P7 §A.2 — O1);
  zombi ⇒ capturar primero; no confiar en `systemctl reboot` sin confirmación.
- **SMMU**: nunca instrumentación en runtime; nunca volcar rangos MMIO.
- **Semáforo hermano** antes de cada flash (hoy: libre).
- **Arranques experimentales**: power-cycle en frío mejor que `fastboot reboot` (#P17).
- **Techo 3 ciclos/hipótesis** (regla #11 del hermano): explícito ahora también para P2 y K24.

## §5 Red de recuperación (comandos literales)

- Tablet en fastboot con A agotado: `fastboot set_active a && fastboot reboot` — o
  `fastboot set_active b` para el par bueno.
- Rollback: `fastboot set_active b` + (solo si B se hubiera pisado, que no es el caso)
  `fastboot flash boot_b build/backup-par-bueno/boot-ukek13-dsid.img`.
- **Fastboot + batería <3700 mV (nuevo — O8)**: `set_active b` → arrancar Arch (par estable) con
  **cargador de pared** → `prepara/uke-adsp-load.sh` → `prepara/bateria.sh --umbral 3700` →
  fastboot por teclas con batería. Nada de reintentos en fastboot drenando.
- Vigía (si se re-arma): `setsid nohup bash build/gates/uke-fastboot-watch-k16.sh >/dev/null 2>&1 &`
  — NO dejarlo armado sin pausa durante una observación.
- Consola: reutilizar/relanzar el lector (matar también el `cat` huérfano; REGLA-UN-SOLO-LECTOR).

## §6 Riesgos vivos (top)

| # | Riesgo | Evidencia | Mitigación |
|---|---|---|---|
| R1 | K23 = primer arranque con dump completo: desenlace inédito | #P48/#P49; `a6xx_gmu.c:408-421` | árbol §P0.4 ahora con 6 ramas (F incluida); predicción pre-registrada; captura íntegra de dmesg |
| R2 | Zombi (~280-400 s) enmascara el veredicto | 3 zombis anoche (#P49) | CMD1 = dmesg→`/dev/shm`→PC antes de nada; fsck; escribir temprano |
| R3 | fs sin journal se re-ensucia con cada wedge | #P49 | e2fsck (flujo probado) antes de cada ciclo; **quitar `hung_task_panic` en P2-skip** (D2 reduce reboots sucios) |
| R4 | Dump K23 ilegible → K24 a ciegas | K19/K22 | no flashear K24 sin `CBpage`; rama D = K23b con techo 1; ftrace como alternativa |
| R5 | Panel nunca ejercitado end-to-end (0 migas P82 visibles NO VERIFICADAS) | D3/D4 | **P2-ctrl primero** (0 escrituras); migas DPU nuevas offline; P2-plain solo tras eso |
| R6 | Segundo asesino en el camino del panel | #P40; U2 §1 | el test de panel (P2-ctrl/P2-skip) decide; no dar el modeset por hecho tras el fix GPU |
| R7 | `mesa`/`eglinfo` ausentes y sin .pkg staged | verificado 1-oct | staging por USB antes de P1 |
| R8 | Sin vigía vivo + A agotable → fastboot sin rescate | medido 1-oct | decisión del dueño (re-armar o no desatender); camino de carga §5 |
| **R9** | **En rama B cada `open()` re-libera el CM3 (escalera entera otra vez): N intentos no medidos** | K5: `msm_drv.c:198-207` | P2-skip como artefacto de B; contar solo la última `UKE-P82`, no la última miga absoluta |
| **R10** | **Rama C puede quedarse sin dmesg ni consola (cuelgue dentro de `msm_open` del fbdev a ~4,2 s)** | D7: fw a 4,07 s vs ventana consola perdida 3,95-4,18 s | loglevel bajo offline; ftrace (R4); poll SSH agresivo; declarar la incertidumbre en el árbol |

## §7 Crítica independiente (EJECUTADA 1-oct por la tarde) — mapa de incorporación

**4 subagentes solo-lectura** (kernel/GPU-SMMU, pantalla/DSI, operativo, método) — **37 hallazgos:
1 BLOQUEANTE, 11 ALTA, 17 MEDIA, 8 BAJA**. Informe íntegro (textos literales con evidencia
`fichero:línea`): `build/gates/revision/V1-critica-plan-v3.md`. La autocrítica C1-C14 de v3 fue
verificada independientemente: C1/C5/C8/C12 comprobadas contra código/proceso/disco — **reales y
bien resueltas** («nada de vaporware»: dump colocado entre S2 y S3, poll de 100 ms reales, grep
matchea el texto real de las migas).

| Hallazgo (sev) | Resumen | Incorporado en |
|---|---|---|
| D1 (BLOQUEANTE) | Falta P2-ctrl (sonda 0-flash); el veto a modetest contradecía #P43 | §P2.1 nuevo; corrección del matiz CM3 |
| K1 (ALTA) | Falta rama F (S3-rst0 + sin S4-poll* = firma #P47) | árbol §P0.4 = 6 ramas |
| K2 (ALTA) | Grep pierde H10-hfiFAIL/H5-fwstartFAIL → rama A falsable | grep extendido §P0.3; rama A exige H10-hfi OK |
| O1 (ALTA) | Plan citaba P7 §A.2, refutado en vivo (ledger #446) | §P0.5 = flujo RUNBOOK Paso 4 + `-fn` primero + `norecovery` |
| O2 (ALTA) | K23 vive como `boot-ukek18d.img` (nombre pisado por repack) | §1 [P0] renombrar a `boot-ukek23.img`; §4 rehacer |
| O3 (ALTA) | «Reinicio limpio» indefinido (contraejemplo #P49) | §4: sync+systemctl reboot+confirmar caída/vuelta |
| O4+M1+M7 (ALTA) | Presupuesto incoherente y real ≥5 escrituras (no 2); sin parada dura | §1/§4 reformulados; regla de PARADA dura |
| M2 (ALTA) | P2-plain bajo rama B con premisa no medida (G1 §5b: sin GPU no hay card0) | §P2.3: plain SOLO rama A; B → P2-skip |
| MEDIA | K3 (dump no distingue tabla/CB; CBpage≠banco), K4 (gate sCR0/S2CR-type), K5 (open re-corre escalera en B), K6 (runtime_status), D2 (quitar hung_task_panic), D3 (migas DPU nuevas), D4 (visibilidad P82 NO VERIFICADA), D5 (sospechosos: DSC/clk/GDSC; vsp/vsn sin proxy), D6 (Writeback/backlight 0-flash), D7 (rama C sin dmesg), O5 (§A.3 requiere shell; norecovery), O6 (poll SSH + dmesg a /dev/shm + lector sin timeout), O7 (fsck 105,8 GiB > ventana), O8 (fastboot+batería baja), M3 (árboles obsoletos en ESTADO-VIVO/RUNBOOK), M4 (OBJETIVOS prioridad), M5 (cierre parcial), M6 (FOTO operacionalizada), M8 (predicción pre-registrada) | integradas en §2/§3/§4/§5/§6 y §8; M3 aplicada ya en esta pasada |
| BAJA | K7 (otros streams candidatos), K8 (dump improbable que mate), D8 (gate del skip), D9 (ctrl no cierra), O9 (P7 A.2.1.1), O10 (tamaño exacto+mismatch), M9 (GPU persistencia), M10 (vigía: decisión) | integradas como notas en §2-§5 |

## §8 Gaps documentales (ampliado por la crítica)

1. **[P0]** `REGLAS.md` canónico con las reglas pagadas (v3 §8.1; `RUNBOOK-SIGUIENTE:29` cita 15
   reglas inexistentes).
2. **[P0]** `README.md` §Reglas: par viejo `s244-bounce`+`s229` → apuntar a ESTADO-VIVO (v3 §8.2).
3. **[P0]** `OBJETIVOS.md`: filas 1/6 refrescar **y reescribir la sección «Orden de prioridad»**
   (M4: K16 como #1 ya está ejecutado y refutado; WiFi #3 por delante del panel contradice al dueño).
4. **[HECHO en esta pasada]** ESTADO-VIVO y RUNBOOK-SIGUIENTE: árboles de 3 ramas marcados como
   históricos; el árbol vigente es §P0.4 de v4 (M3).
5. **[P0]** Renombrar `build/bootimg/boot-ukek18d.img` → `boot-ukek23.img` + nota en `repack-k18.py`
   (O2).
6. **[P0]** Migas DPU nuevas + parche skip + quitar `hung_task_panic` en las variantes P2 (D2/D3/D8)
   — todo offline, 0 tablet.
