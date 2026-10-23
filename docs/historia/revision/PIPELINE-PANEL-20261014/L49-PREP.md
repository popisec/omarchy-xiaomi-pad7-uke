# L49-PREP — Captura del punto exacto del commit + candidatos a fix (14-oct-2026, noche)

> Subagente preparador del ciclo L49. Solo lectura en tablet y árbol
> (`build/kernel-pokes/k52-L16-tree` NO tocado; diff generado sobre copia en
> `/tmp` y verificado con `patch -p1 --dry-run` contra el árbol vivo).
> Base leída: `docs/historia/revision/PIPELINE-PANEL-20261014/BRIEF.md`, `H2-CRASH-CAPTURADO-20261014.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/CRITICA-L47.md`,
> `docs/historia/revision/PIPELINE-PANEL-20261014/L48-PREP.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/CRITICA-L48.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/REVISION-BOOTS-20261014.md`,
> `docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-CADENA-20261014.md`, `REVISION-CADENA-20261013.md` (cadena §4),
> `docs/historia/revision/PIPELINE-PANEL-20261014/REVISION-CADENA-20261014.md`, NOTAS-OMARCHY.md (entradas 14-oct, incl.
> 15:xx), docs/historia/ESTADO-VIVO.md (14-oct 15:xx), ledger #620/#621/#622 (+#622-bis),
> `drivers/soc/qcom/uke-panic-fb.c`, `include/linux/uke-poke.h`,
> `build/gates/dump-log.sh`, código del commit citado abajo, y del proyecto
> hermano `REFUTADO.md` (R-10/R-46) + `LECCIONES.md` (R6, `panic=10`).
> Estado medido hoy 15:4x por SSH (solo lectura): tablet **viva, uptime
> 39 min, L48 + `sddm disabled/inactive` = display-ON ESTABLE**, dumper v3
> activo (`/mnt/logfs/uke-c85330ed-*.txt.gz`, 48 ficheros), pintor activo
> (`uke-ojos: autodiag 0xe3940000..0xe5353000 => no es System RAM (reservada:
> OK)`, `/proc/iomem: e3940000-e643ffff : reserved`, doble `memmap=` en
> cmdline). `/sys/fs/pstore` vacío, `/proc/mtd` sin dispositivos.

## 0. Punto de partida (lo que cambió hoy a las 15:xx)

- La muerte display-ON la causaba `sddm`→Hyprland: tras el bind (47 s) el
  primer commit (modeset) mata el SoC; con `sddm` deshabilitado el display-ON
  es **estable minutos** (PASA, ledger #622-bis).
- `modetest -M msm -c` vive; `modetest -M msm -s 36@85:#0` **muere en <1 s**:
  más rápido que el dumper (2 s) y que el ACM (pierde el stream post-login).
  El punto exacto dentro del commit está sin capturar.
- Los pokes del commit **ya viajan en la imagen L48 puesta**: `K47-atom-tail`
  (`msm_atomic.c:216`), `K47-kms-en-commit` (`dpu_kms.c:443`),
  `K47-crtc-en` (`dpu_crtc.c:1273`), `K47-enc-en` (`dpu_encoder.c:1343`),
  `K47-brg-pre-en` (`dsi_manager.c:282`), `K47-mgr-phy-en`
  (`dsi_manager.c:140`), `K47-phy-en` (`dsi_phy.c:742`),
  `K47-pll-prep` (`dsi_phy_7nm.c:494`), `K47-7nm-en` (`dsi_phy_7nm.c:961`),
  `K47-host-pwr` (`dsi_host.c:2508`), `K47-host-en` (`dsi_host.c:2454`),
  `K47-pan-pwr`/`K47-pwr-OK`/`K47-pan-prep`/`K47-pre-rst`/`K47-pre-rstOK`/
  `K47-pre-init` (`panel-xiaomi-o82-dualdsi.c:297/337/352/376/378/381`),
  `K47-pan-dcs` (`:468`), `K47-host-xfer` (`dsi_host.c:1791`),
  `K47-vid-en` (`dpu_encoder_phys_vid.c:449`), `K47-enc-mset`
  (`dpu_encoder.c:1157`), `K47-mgr-mset` (`dsi_manager.c:392`)
  (verificado por grep en el árbol hoy).

## 1. Captura del punto exacto: opciones evaluadas con evidencia

### 1a. Canal del pintado (`uke_poke` → pantalla) — ELEGIDO como primario

Mecanismo verificado en el árbol (`uke-panic-fb.c:240-264`):

- `uke_poke(tag)` hace **dos cosas inseparables**: `pr_err("UKE-POKE: %s")`
  (sale por dmesg/ACM) **y pinta el tag de forma SÍNCRONA** en la fila 0-40
  del framebuffer del ABL (`uke_fill(0,40)+uke_text`, sin locks, sin timer,
  sin workqueue). Falla cerrado si la región no está reservada.
- La región **SÍ está reservada en L48**: autodiag del boot vivo dice
  `reservada: OK`, `/proc/iomem` la marca `reserved`, cmdline trae
  `memmap=0x1A12800$0xE3940000` + `memmap=0x2B00000$0xE3940000` ⇒
  `uke_safe=true` ⇒ **cada poke del commit se está pintando HOY**.
- El comentario de `dump-log.sh` («el painter solo muestra una VENTANA de
  ~0.5 s») habla del **repintado del LOG** (tick 2 s + kmsg_dumper: últimas
  ~110 líneas), NO de la fila del poke: la fila 0-40 muestra **siempre el
  último tag**, sin ventana. Localizada la confusión; no aplica a `uke_poke`.
- Ante un **hang** (nuestra firma: silencio, sin panic), el kmsg_dumper NO
  corre ⇒ la fila del poke **sobrevive congelada** en la pantalla que sigue
  escaneando el splash. Lectura = **fotografía de la pantalla** antes del
  reset (el reset hace que el ABL repinte el splash y la borre).
- Matiz R6 del proyecto hermano (`LECCIONES.md:196-201`): si la muerte fuera
  un **panic** y no un hang, el dumper hace `uke_fill(0,40)` + cabecera roja
  y **borra la fila del poke** — pero imprime `LAST-POKE: <tag>` en su
  propia cabecera (`uke-panic-fb.c:499-504`). En ambas ramas el punto queda
  legible en foto. `panic=10` va en cmdline (reboot a los 10 s):
  **fotografiar rápido**.
- Coste: **0 escrituras**. Los pokes ya están en L48; el test (`modetest -s`)
  tampoco escribe. Resolución: sub-segundo (el pintado es síncrono en el
  camino que muere). Es el canal ideal para esta muerte.

### 1b. Ralentizar el commit (`msleep` entre pasos) — RECHAZADO como primer paso

- Perturba el timing (E6): L48 demostró sensibilidad real (migas inertes
  movieron la muerte 50 s → 5-11 min; `docs/historia/revision/PIPELINE-PANEL-20261014/REVISION-CADENA-20261014.md:88-89`).
  Unos `msleep(100)` en el enable-path cambian GDSC/clock/PLL-sequencing y
  pueden mover o enmascarar el punto que se quiere medir.
- Coste: 1 ciclo de diagnóstico con variable perturbadora, contra 0 de (a).
- Queda como **fallback documentado** solo si la foto es ilegible (p.ej.
  pantalla en negro tras reprogramar el encoder): `msleep(200)` tras cada
  `L49-*-ok` del diff adjunto, en ciclo aparte. No se propone diff.

### 1c. Otros canales — evaluados

- **pstore/mtdoops**: NO disponible. `/sys/fs/pstore` vacío y `/proc/mtd`
  sin dispositivos en el boot vivo (medido hoy); R-46 del hermano ya falsó
  «el kmsg queda en la partición oops» (registros de junio, el ABL dejó de
  escribirlos). Un hang además no genera oops/panic que persistir
  (`hung_task_panic=0` y el detector no corre wedged). Secundario barato
  tras el reboot (`ls /sys/fs/pstore`, 0 coste) pero sin esperar nada.
- **ACM**: pierde el stream post-login (ledger #622-bis) por causa raíz
  desconocida; a 115200 + spam del Oops de 8.3 s el lector no da abasto
  (`docs/historia/revision/PIPELINE-PANEL-20261014/REVISION-BOOTS-20261014.md:217-220`). Arreglarlo (baud, lector dedicado,
  `loglevel`) es otro ciclo y **sigue sin dar resolución sub-segundo**.
  Se mantiene armado (lector único) pero no se depende de él.
- **Dumper 2 s**: se mantiene; caza muertes lentas, no la de <1 s.

**Decisión**: captura = **(a) foto de la fila del poke + `pr_err` del dumper
como respaldo**, coste 0. L49 (1 escritura) = instrumentación de
subdivisión (§4) o fix directo si la foto ya nombra el sub-punto (§2).

## 2. Candidatos a FIX rankeados (hipótesis hasta la foto; mecanismos verificados)

Camino del commit verificado (orden): `atom-tail` → `kms-en-commit`
(resume DPU+MDSS) → `crtc-en` (get_sync) → `enc-en` (`resource_control`
KICKOFF: votos icc/clk) → `brg-pre-en` → `power_on`: `mgr-phy-en`
(reset-PHY MMIO + `enable_phy` → `phy-en`: resume+reguladores →
`pll-prep` (bias+start+lock con timeout) → `7nm-en` (lanes)) →
`host-pwr`: vregs (`vdda` 1.2 V, `dsi_cfg.c:193-197`) → get_sync +
`link_clk_set_rate_6g` (`dsi_host.c:383`: `dev_pm_opp_set_rate` + `clk_set_rate`
a SRCs con padre=PLL por `palawan.dtsi:3493-3494/3590-3591`) +
`link_clk_enable_6g` (esc→byte→pixel→byte_intf) → pinctrl default →
`timing_setup` + `sw_reset` + `ctrl_enable` → `host-en` →
panel `power_on` (vci L19 2.6 V + rails + 2 ms) → reset GPIOs → DCS init →
`vid-en` (primer scanout/DMA) → `enc-mset`/`mgr-mset`.

| # | Punto (foto que lo señala) | Mecanismo | Fix quirúrgico | Fuerza |
|---|---|---|---|---|
| F1 | `L49-host-vreg-ok` SÍ + `L49-host-clk-ok` AUSENTE | `set_rate`/`enable` de link-clocks contra SRCs con padre=PLL: camino **virgen en este boot**; el vendor fija rates en probe y jamás en commit (`docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-CADENA-20261014.md:60-62,80-85`). Un glitch aquí cuelga el árbol display sin traza | Pre-fijar rates / separar set_rate del enable / no retocar el SRC si PLL aún no engancha (diff tras la foto) | Hipótesis más fuerte para muerte silenciosa en `host_power_on` |
| F2 | muerte en `atom-tail`/`kms-en-commit`/`crtc-en`/`enc-en` (temprano) | Resume GDSC (`af09000`)/MMCX + clocks tras **minutos** apagado (bind lo probó tras segundos; `K48-*-susp` medidos). El vendor **nunca apaga** (rehúsa suspend con splash, `ANDROID-CADENA §2.1`) | H-A revive: `pm_runtime_forbid/disable` en DPU+MDSS (diseño en `ANDROID-CADENA §5 H-A`) | Media; es el único candidato si la foto es temprana |
| F3 | `K47-mgr-phy-en` SÍ + `L49-phy-ok` AUSENTE (sin `pll-prep`) | Reset-PHY MMIO / PLL que no engancha. Los polls llevan timeout (`dsi_phy_7nm.c:386,999`) ⇒ el fallo normal es **gracioso** (`PLL lock failed` + `-ETIMEDOUT`), NO silencio | Fidelidad vendor (lanes a LP11 antes de rails, H1–H8 de `ENABLE-COMPARISON`) | Débil como asesino silencioso; fuerte como fallo gracioso |
| F4 | `pan-prep`/`pre-rst`/`pan-dcs` | Rails/reset/DCS del panel: reguladores+GPIOs con errores graciosos (`o82_power_on` retorna, no cuelga) | Despierta el backlog S1-vci/S3-reset/S2-pulso | No explica el silencio; solo si la foto cae aquí |
| F5 | `vid-en`/`enc-mset`/`mgr-mset` (tardío) | Primer scanout/DMA por VBIF→SMMU: camino virgen; fault SMMU normalmente loguea | VBIF/SMMU (heritage `uke_keep_boot`, memtypes) | Media-baja; solo si la foto cae aquí |

Lo que NO se sostiene (dicho en voz alta): sin la foto, F1–F5 son
mecanismos plausibles, no diagnóstico. El orden DSI del vendor (LP11 →
rails/reset → LINK → DCS → vídeo al final) vs el nuestro es backlog real
pero **ningún desorden de DCS explica un SoC muerto en <1 s sin una línea**;
el wedge silencioso apunta a clocks/power (F1/F2), no al panel.

## 3. Diffs propuestos

- **`l49-capture.diff`** (adjunto, 5 pokes `L49-*` inertes —`pr_err`+pintado
  lock-free, falsados como asesinos en X9 s166/s167— en `dsi_manager.c`
  (2) y `dsi_host.c` (3); `patch -p1 --dry-run` **OK contra el árbol vivo**
  verificado hoy): subdivide el intervalo más ancho y más sospechoso
  (`mgr-phy-en` → `pwron-ok`): `L49-phy-ok` (PHY reset+PLL listos),
  `L49-host-vreg-ok` (vregs), `L49-host-clk-ok` (link-clks),
  `L49-host-ctrl-ok` (timing+reset+ctrl), `L49-pwron-ok` (power_on completo).
  Tabla de lectura en §5.
- Sin diff de fix hoy: el fix depende del sub-punto (§2); escribirlo antes
  de la foto violaría «evidencia o no es nada» (BRIEF regla 3).

## 4. Plan recomendado (máxima información por escritura)

- **Fase 0 — esta noche, 0 escrituras** (tablet viva y estable AHORA):
  runbook §5 con `modetest -s` + foto. Si la foto nombra el sub-punto,
  L49 = fix directo de §2 (se salta el flash de instrumentación).
- **L49 — 1 escritura** (`boot_a`; `dtbo_a` s287 se queda):
  defecto = L48 + `l49-capture.diff` (solo instrumento, variable única
  nula) + runbook §5. Contenido alternativo si la Fase 0 ya señaló fuera
  del intervalo phy/host-power: 2-3 pokes análogos en ese intervalo.
- Rollback prefijado: L48 `0b1d22c4…` (display-ON estable sin sddm) o L45
  `83647c45…` (2ª escritura solo si el slot lo exige).

## 5. Criterio prefijado + runbook

### 5.1. Fase 0 (0 escrituras, dueño + SSH)

1. SSH vivo; `systemctl is-active sddm` = `inactive` (no tocar si cambió).
2. Foto basal de la pantalla (referencia del splash + fila de poke actual).
3. Cámara grabando la pantalla (o foto en ráfaga); por SSH, **un solo
   intento**: `modetest -M msm -s 36@85:0` (connector 36, CRTC 85, modo #0
   3200x2136@120 de la lista — CRITICA-L47 §3.2; prohibido inventar modo).
4. Al cortarse la conexión: **foto inmediata** de la pantalla congelada
   (antes de 10 s por `panic=10` si fuera panic; en hang no hay prisa pero
   no resetear antes de fotografiar).
5. Reset físico; al volver (sddm off → estable): copiar dumper v3 del boot
   (`/mnt/logfs/uke-<bootid>-*.txt.gz`), `grep UKE-POKE`, `ls /sys/fs/pstore`.

Lectura de la foto (último tag visible = «murió EN o DESPUÉS», E6 bien
aplicado):

| Tag congelado | Significa | Siguiente |
|---|---|---|
| `K47-atom-tail`/`kms-en-commit`/`crtc-en`/`enc-en` | Muere en resume/votos | F2 → L49/L50 = forbid-suspend (H-A) |
| `K47-brg-pre-en` | Entrada de power_on | F2/F1 |
| `K47-mgr-phy-en` (sin `L49-phy-ok`) | Reset-PHY/PLL | F3 |
| `L49-phy-ok` sin `vreg-ok` | vregs DSI | F1-variante |
| `L49-host-vreg-ok` sin `clk-ok` | **Link-clocks/PLL** | **F1** |
| `L49-host-clk-ok` sin `ctrl-ok` | pinctrl/timing/reset | F1-variante |
| `L49-host-ctrl-ok`/`pwron-ok`/`host-en` | IRQ/host-enable | menor |
| `pan-pwr`→`pre-init` | Power/reset panel | F4 (backlog S1/S3) |
| `pan-dcs`/`host-xfer` | DCS | F4 (backlog S4) |
| `vid-en`/`enc-mset`/`mgr-mset` | Scanout | F5 (VBIF/SMMU) |
| Sin tag nuevo (fila vieja) | Muere antes del primer poke o pantalla reprogramada | Fallback §1b + dumper |

### 5.2. L49 (1 escritura)

- Pre-vuelo: `getvar all` (retries a/b, `unbootable`, mV ≥3700 salvo
  exención del dueño en fila), semáforo inter-proyecto (ESTADO-ACTUAL.md +
  ledger hermano), ACM lector único + dumper v3 armados, pausa del vigía
  en el flash, fila ledger **pre-registrada con sha256 ANTES de flashear**,
  readback al tamaño exacto tras flashear.
- Build L49 = L48 + `l49-capture.diff`; gates: 5 literales `L49-*-ok` ×1
  en `strings` del Image (+ los 11+1 de L48, CRITICA-L48 §2.3); cmdline
  display-ON 566 B; `FBDEV=n` se mantiene.
- Observación: sddm **deshabilitado** (el display-ON es estable); ≥6 min o
  hasta.reset; **sin modetest en este ciclo** salvo PASA (aplica la rama
  PASA-MODESET de CRITICA-L48 §4.1 si sddm/userspace modesetea solo).
- Ramas: **PASA-SPLIT** (foto/run muestra sub-punto + sistema recuperable →
  L50 = fix de §2) / **PASA-MODESET** (luz/modeset userspace OK) /
  **FALLA-TEMPRANA** (<20 s: otra vía, comparar control) /
  **FOTO-ILEGIBLE** (→ fallback §1b).

## 6. Riesgos y refutaciones que aplican

- **Slots/batería**: H2+L47 quemaron `a` hasta `unbootable` dos veces; hoy
  van #620/#621/#622 + restores (gate ≤2/día eximido de facto por el dueño
  — debe constar en la fila, CRITICA-L47 §3.3). L49+rollback = 2 escrituras
  = tope; cualquier imprevisto mueve el resto a mañana. Fastboot no carga
  (R-44): **cargador de pared** + mV inicial/final en fila.
- **El test mata el SoC a propósito**: un solo `modetest -s` por boot
  estable; si cuelga, reset físico y parar (sin segundo intento el mismo
  día). R-42: sin recuperación automática, vigía físico obligatorio.
- **E6**: los 5 pokes son inertes (X9 s166/s167); aun así, si L49 moviese la
  muerte sin foto legible, se declara E6 y no se apila más instrumento.
- **REFUTADO/LECCIONES**: R-10 (pstore vacío — confirmado hoy),
  R-46 (mtdoops con registros de junio — confirmado hoy: sin backend),
  R6-pintor (borrado de la fila en panic — cubierto: LAST-POKE sobrevive),
  `panic=10` (foto rápida), R-12 (`fastboot boot` usa dtbo del slot ⇒
  flashear `boot_a` de verdad), regla 4 (doble captura), regla 5
  (`sync` antes de reset).

## 7. Presupuesto

- Fase 0: **0 escrituras** (modetest no escribe). L49: **1 escritura**
  (`boot_a`); rollback = 2ª solo si procede. Total ciclo ≤2 = tope diario.
- Qué NO hacer: fix funcional sin foto; `msleep` en este ciclo; tocar
  sddm/DT/GDSC/VBIF/OPP; modetest fuera del runbook; dos lectores ACM;
  compilar/flashear desde esta preparación.

## 8. Qué he verificado y qué no (honestidad)

Verificado hoy (fichero:línea o comando+salida): inventario de pokes K47
en árbol (grep §0); mecanismo `uke_poke` (`uke-panic-fb.c:240-264`);
reserva de la región (SSH: autodiag + iomem + memmap×2 en cmdline);
pintor activo; sddm off + uptime 39 min + dumper v3 (SSH); pstore/mtd
ausentes (SSH); `l49-capture.diff` dry-run OK; DT power-domains/clocks
(`palawan.dtsi:3357-3382/3390-3415/3471-3600`); vregs DSI
(`dsi_cfg.c:193-197`); timeouts de polls PHY (`dsi_phy_7nm.c:386,999`);
REFUTADO/LECCIONES aplicables. **No verificado**: el contenido actual de
la pantalla (requiere foto física); la causa raíz de la pérdida del ACM
post-login; el valor numérico de `K48-opp-rate` (sigue pendiente).
Hipótesis marcadas: F1–F5, E6-fallback, variante rewrite-en-vivo
(CRITICA-L48 §3, intacta pero fuera de este ciclo).
