# CRÍTICA ADVERSARIAL L48 — veredicto y correcciones (14-oct-2026, tarde)

> Subagente crítico. Solo lectura; árbol (`build/kernel-pokes/k52-L16-tree`) y tablet no tocados.
> Base leída: `docs/historia/revision/PIPELINE-PANEL-20261014/BRIEF.md`, `H2-CRASH-CAPTURADO-20261014.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/CRITICA-L47.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/L48-PREP.md`,
> `l48-migas.diff`, dumps `out/h2-dumps/uke-48.txt.gz` (actual) + blob `976f714:out/h2-dumps/uke-48.txt.gz`
> (H2 original) + `uke-6780.txt.gz` (control), `out/acm-flash-20261014.log`,
> `docs/historia/revision/ROADMAP-PANTALLA-20261013.md` §FASE 1, `AUDITORIA-METODO-20261013.md` §E9,
> commits `976f714`/`eacef7c`, y código citado abajo con fichero:línea del árbol vivo.

## 0. Veredicto: APROBADO-CON-CAMBIOS

El ciclo está bien apuntado y el diff es limpio, pero el dossier contiene **1 error de gestión
de evidencia grave (§1.4)**, **1 rama del criterio que falta y que puede ser EL resultado (§4.1)**,
**1 hueco de instrumentación que cambia la lectura del "asesino en el bind" (§2.4)** y un gate
de repack inaplicable tal cual (§2.3). Nada exige re-diseñar: todo se corrige en papel + 2 pokes
opcionales-pero-recomendados. Con §5 aplicado, L48 distingue 6 desenlaces en 1 escritura.

## 1. Claim central (bind completa, muerte post-bind): CONFIRMADO con 3 matices + 1 hallazgo grave

### 1.1. El bind completa: SÍ (evidencia + código)

- Dump L47 actual (`uke-48.txt.gz`, boot display-ON sin `video=DSI-1:d`, `pureason=0x80100`):
  `K47-dpu-hw-in` (46.982771) → `K47-dpu-res` → revision `0xa0010000` → WARN IOMMU benigno →
  `K47-tx-alloc`×2 → `K47-dpu-res` (2º, 46.983948) → **`[drm] Initialized msm-kms 1.13.0 …
  on minor 1` (46.984940)** → X9WAVE/sync_state/UFS hasta 47.06 s → snapshot del volcador a 48 s
  (`K47=5`, `card1-DSI-1: unknown`) → fin. Cero `atom-tail`, cero `pan-modes`, cero fbcon/fb0.
- Código: `msm_drm_init` (`drivers/gpu/drm/msm/msm_drv.c:162-197`) ordena
  `component_bind_all` → `msm_drm_kms_init` (hw_init + `pm_runtime_get_sync`/`msm_irq_install`/
  `put_sync`) → `drm_dev_register` (imprime `Initialized`, `drivers/gpu/drm/drm_drv.c:1109`) →
  `msm_debugfs_late_init` → `msm_drm_kms_post_init`. La traza del WARN lo confirma
  (`o82_probe → … → msm_drm_bind → msm_drm_init → msm_drm_kms_init → dpu_kms_hw_init`).
- **MATIZ 1**: el print NO es lo último del bind; después corren `msm_debugfs_late_init`
  (`msm_debugfs.c:350`, trivial) y `post_init` (`poll_init` + `drm_client_setup`, esta última
  no-op con `FBDEV=n`, `drm_client_setup.c:42-53` según CRITICA-L47 §2.2 — no re-verificado,
  citado). "Bind completo al imprimir" es correcto al nivel que importa (hw_init=0 +
  irq_install hechos), pero el criterio debe decir "post-`hw_init`/irq" en vez de "post-bind".
- **MATIZ 2 (exclusiones que el prep no explicita y que sí cierran puertas)**:
  `drm_kms_helper_poll_init` dispara el primer poll a ~+10 s (`DRM_OUTPUT_POLL_PERIOD`,
  `drm_probe_helper.c:266`) ⇒ fuera de la ventana 47→50 s, excluido como asesino.
  El burst `sync_state` es resolución deferred-probe normal (el control lo tiene igual, 47
  líneas en `uke-6780`); `clk_ignore_unused` + `pd_ignore_unused` están en AMBAS cmdlines
  (verificado token a token; solo difieren en `video=DSI-1:d`) ⇒ `clk_disable_unused`/apagado
  de GDSCs están OFF en ambos brazos, excluidos como discriminante.

### 1.2. Ventana 47→50 s sin tráfico DRM: SÍ dentro de lo commiteado, con un límite que hay que escribir

- Los 3 `L6-open` de `uke-48` son a 9.44/24.24/39.24 s = **pre-bind** (`msm_open`,
  `msm_drv.c:282-293`; `card1` no existe hasta el bind a 46.98 s ⇒ son clientes de `card0`/GPU).
  **Cero opens, cero `pan-modes`, cero `atom-tail` post-bind en el dump.** C5-commit excluido ✓.
- **LÍMITE**: el dump cubre hasta ~48 s; la ventana 48→50 s es SOLO-ACM y **el ACM de L47 no está
  commiteado**: `out/acm-flash-20261014.log` (582 KB, 156357 líneas) termina en un login a t≈9.5 s,
  sin rastro del boot L47. ⇒ "`~50 s`" y "`sin más migas`" (L48-PREP §0) son testimonio interno,
  no evidencia. No los doy por falsos, pero L48 debe **commitear el ACM** o su FALLA-POST pende
  de captura volátil. Regla nueva: sin ACM archivado, la rama post-bind es INCONCLUYENTE.

### 1.3. El control display-off: bind completo SÍ, "idéntico" con un asterisco honesto

- `uke-6780` (L45+s287, `video=DSI-1:d`, `pureason=0x800001`): `UKE-L45` (47.044902) →
  `tx-alloc`×2 → `Initialized msm-kms minor 1` (47.052273) → vive. **Sin `dpu-hw-in`/`dpu-res`
  porque la imagen L45 no lleva las migas L47** (son nuevas de L47, CRITICA-L47 §1.1), no porque
  el camino difiera. El camino fuente es el mismo salvo `FBDEV=y/n` + 7 pokes inertes.
- Punto ciego del prep (C5): con `:d` el conector va forzado a disconnected y con `=n` no hay
  cliente; en AMBOS brazos no hay commit post-bind. Dentro de la evidencia commiteada, **el
  `:d` no tiene ningún mecanismo kernel-side en la ventana del bind** (solo afecta a futuro
  comportamiento userspace, del que no hay rastro 47→48 s). Consecuencia: si L48 reproduce
  FALLA-POST sin tráfico DRM, las opciones vivas son actor diferido-no-DRM, sddm post-48 s
  (solo-ACM) o flaky/entorno (C6, reforzado: L47 flasheó a **3640 mV, bajo el gate 3700**).
  El criterio debe nombrar C6 en PASA y en FALLA-POST, no solo en PASA.

### 1.4. HALLAZGO GRAVE (proceso): la evidencia H2 fue sobreescrita por L47

- `uke-{8,28,48}.txt.gz` llevan nombre por uptime ⇒ el boot L47 los **sobreEscribió**
  (commit `eacef7c`: `uke-48` 48726→48884 B). La cadena fbcon que H2 cita (`uke-48:2926-2933:
  `pan-modes → fb_set_par -16 → fb0 → pan-modes`) **ya no está en el fichero** (verificado:
  0 ocurrencias hoy); solo vive en el blob `976f714` (verificado por `git show`: líneas
  2926/2928/2929/2932/2933 presentes allí).
- CRITICA-L47 §2.1 era correcta contra el blob, pero hoy las citas `H2:línea` cuelgan.
- **Corrección obligatoria (sin coste de escritura)**: copiar los 3 blobs H2 a
  `out/h2-dumps-l46/` (o citar `976f714:out/h2-dumps/uke-{8,28,48}.txt.gz` en H2 §1) y añadir a
  H2 una nota "ficheros rotados por L47 el 14-oct". Sin esto, la mitad de las citas de la noche
  son irreproducibles. El runbook L48 debe fijar nombres por ciclo (p. ej. prefijo `l48-`) o el
  próximo boot volverá a pisar.

## 2. Migas (`l48-migas.diff`): APROBADAS, dry-run limpio, 3 correcciones

### 2.1. Aplicabilidad: BIEN (mejor que L47)

- `patch -p1 --dry-run` contra el árbol vivo: **exit 0, 3/3 ficheros, sin fuzz ni FAILED**
  (verificado). El árbol NO contiene ninguno de los 12 tags nuevos (solo los 9 `K48-*` del panel,
  §2.3). La afirmación "dry-run OK sin tocarlo" del prep es esta vez VERDADERA y reproducible.

### 2.2. Inserciones: todas dentro de su función y en el punto útil (verificado en árbol)

| Tag | Sitio árbol | Juicio |
|---|---|---|
| `K48-hw-resume-ok` | `dpu_kms.c` tras `if (rc<0) goto error;` (~1166), antes del `readl` de revisión | ✓ resume#1 completo (padre+hijo) |
| `K48-hw-mmu-ok` | `dpu_kms.c` tras `_dpu_kms_mmu_init` OK (~1189) | ✓ tras el WARN benigno |
| `K48-hw-vbif-ok` | `dpu_kms.c` rama else del inherit (~1290) | ✓ 2ª escritura VBIF |
| `K48-opp-rate` | `dpu_kms_init` tras `dev_pm_opp_set_rate` (~1321); `dpu_kms` en scope, `dpu_kms_get_clk_rate` existe (`dpu_kms.c:1127`, `dpu_kms.h:170`) | ✓ mide lo que dice (§3) |
| `K48-res-clk-in/ok` | `dpu_runtime_resume` antes/después de `clk_bulk_prepare_enable` | ✓ (tras el early-return inherit ⇒ **si imprimen, inherit=OFF probado**; regla de lectura) |
| `K48-res-vbif-ok / res-enc-ok` | tras `dpu_vbif_init_memtypes` y tras el loop de encoders | ✓ |
| `K48-post-init` + alive-work | `msm_drm_kms_post_init` (`msm_kms.c:392-400` hoy: `poll_init` + `client_setup`) | ✓ contexto único |
| `K48-mdss-en-in/ok` | `msm_mdss_enable` (`msm_mdss.c:232/256`): entrada y tras `clk_bulk` AHB/HF_AXI/MDP_CLK | ✓ único caller `mdss_runtime_resume` (`msm_mdss.c:449-455`) |

- Inertes: `uke_poke` es función real (`include/linux/uke-poke.h`, `pr_err` + pintado lock-free,
  falsada como asesina en X9) ✓; el `delayed_work` no toca locks ni HW ✓. **Matiz E6 honesto**:
  los pokes están falsados, pero el `delayed_work` es maquinaria de temporización NUEVA (no la
  cubre X9 s166/s167); riesgo mínimo (un work en system_wq a +3 s) pero debe declararse, no
  darse por falsado. Limpieza opcional: sobran 3 includes en `msm_kms.c`
  (`kthread.h`, `sched/mm.h`, `uapi/linux/sched/types.h` — el añadido solo usa
  `jiffies.h` + `workqueue.h` + `uke-poke.h`).

### 2.3. Namespace y gates: CORRECCIÓN OBLIGATORIA

- Sin colisión literal: el panel ya tiene 9 `K48-*` (`rst-A`, `w1-done`, `rst-A-ok`, `w2-done`,
  `rst-R-ok`, `w3-done`, `rst-A2-ok`, `w4-done`, `rst-R2-ok`; `panel-xiaomi-o82-dualdsi.c:268-287`)
  y los 12 nuevos son todos distintos ✓.
- Pero el gate propuesto ("12 tags K48 ×1 en `strings`", L48-PREP §6.2) es **inaplicable**:
  (i) el prefijo `K48` cuenta también los 9 viejos del panel; (ii) `alive-1/2/3` **no existen como
  literales** en el binario (solo el formato `"K48-alive-%d"`).
- **Gate exacto que debe llevar el repack clonado de L47**: 11 literales ×1
  (`K48-opp-rate`, `K48-mdss-en-in/ok`, `K48-res-clk-in/ok`, `K48-hw-resume-ok/mmu-ok/vbif-ok`,
  `K48-res-vbif-ok/enc-ok`, `K48-post-init`) + `"K48-alive-%d"` ×1. Y el repack debe clonarse de
  `repack-k52L47.py` actualizando su lista de 7 → esta; reutilizarlo sin cambios daría gates falsos.

### 2.4. Orden esperado y heartbeat: 2 correcciones + 1 hueco (el importante)

- **Corrección A — `mdss-en` sale ×2, no ×1**: el padre se reanuda en resume#1 (get del hijo en
  `hw_init`) y en resume#2 (get del master en `irq_install`, `msm_kms.c:338-340`); la 2ª ocurrencia
  puede ir sin `res-clk` posterior (el hijo ya está despierto). No leer duplicados como anomalía;
  la secuencia útil es el bracketing, no el conteo. (El prep documenta ×2 para `res-*` pero ×1
  para `mdss-en` en su orden esperado §4: inconsistente.)
- **Corrección B — `alive-1` corre contra la muerte**: post_init ≈46.99 s ⇒ alive-1 ≈49.99 s vs
  muerte ~50 s (testimonio). Puede perderse por ms. Regla: alive-1 ausente = muerte <~3 s tras
  post_init (o race); alive-1 sin 2 = 3–8 s; 1+2 sin 3 = 8–15 s; los 3 = >15 s. Y **alive-* es
  SOLO-ACM** (el dump de 68 s no existirá si muere a 50 s): FALLA-POST sin ACM archivado =
  INCONCLUYENTE, no diagnóstico (§1.2).
- **HUECO (recomendación fuerte): faltan las migas de SUSPEND**. Tras `put_sync` de `hw_init` y
  de `irq_install`, sin autosuspend configurado, DPU y MDSS quedan en condiciones de suspenderse
  **en ambos brazos** (conteo a 0 ⇒ `dpu_runtime_suspend`/`mdss_runtime_suspend` inmediatos).
  Hoy nadie mide si tras el bind los clocks del display quedaron ON u OFF — y si quedaron OFF en
  ambos, el relato "asesino en el bind" necesita precisarse (la herida deja firma en el bind pero
  la muerte llega con clocks ya apagados). **Añadir 2 pokes** (siguen siendo instrumento, no
  variable):
  - `dpu_kms.c`, en `dpu_runtime_suspend` antes del `return 0;`:
    `uke_poke("K48-res-susp-ok");` (cuerpo leído: `clk_bulk_disable_unprepare` + loop
    `icc_set_bw(…,0,0)` + `return 0;` — inserción trivial y única).
  - `msm_mdss.c`, en `mdss_runtime_suspend` (`:440-448`: leer el cuerpo al generar el hunk;
    primera sentencia efectiva).
  Lectura: `susp-ok` ×2 tras el bind = clocks OFF post-bind (normal); cero `susp-ok` = referencia
  retenida/clocks ON (releer sospechosos). Un wedge EN el suspend también quedaría bracketeado
  (última miga = entrada sin salida).

## 3. Veredicto FASE-1 (NO sembrar): CONFIRMADO el mecanismo, ACOTAR el alcance

Cadena verificada eslabón a eslabón en el árbol actual:

1. `dpu_kms_init` (`dpu_kms.c:1303-1330`): `dev_pm_opp_find_freq_floor(ULONG_MAX)` → OPP máx =
   **514 MHz** (`palawan.dtsi:3446-3472`, `required-opps rpmhpd_opp_nom`; `operating-points-v2`
   en `:3413`; `devm_pm_opp_set_clkname(dev,"core")` en el probe `:1404`; "core" = 4º clock
   `DISP_CC_MDSS_MDP_CLK` según `:3390-3415`) → `dev_pm_opp_set_rate(dev, 514M)`.
2. La rama `disp_cc_mdss_mdp_clk` lleva `CLK_SET_RATE_PARENT` (`dispcc-sm8550.c:1440-1465`) ⇒
   propaga al SRC `disp_cc_mdss_mdp_clk_src` (`clk_rcg2_shared_ops`, ftbl con 514M en `:587-612`;
   la variante palawan también lo trae ⇒ la duda de tabla no afecta).
3. Clocks OFF (primer enable posterior, en el bind) ⇒ `__clk_rcg2_shared_set_rate` solo cachea
   `parked_cfg` (`clk-rcg2.c:1388-1394`).
4. El primer `shared_enable` escribe `parked_cfg` + UPDATE incondicionalmente (`:1437`), con el
   comentario TODO de `msm_mdss.c:248-255` asumiendo OPP previo. La premisa del ROADMAP
   ("mainline no siembra nada → parked_cfg=0", `docs/historia/revision/ROADMAP-PANTALLA-20261013.md:44-60`) **queda
   refutada en código**: la siembra existe vía OPP.
5. La medida es válida: `clk_rcg2_shared_recalc_rate` recalcula desde `parked_cfg`
   (`clk-rcg2.c:1503-1509`) ⇒ `clk_get_rate("core")` con clocks OFF refleja la siembra ✓.
   Contraejemplos cerrados: `assigned-clock-rates` del VSYNC toca otro SRC (`vsync_clk_src`,
   `:678-690`), no el MDP; el probe de MDSS no habilita clocks (solo reset BCR + `pm_runtime_enable`
   `:435`; `msm_mdss_enable` solo corre vía `mdss_runtime_resume`).
- **Lectura prescrita de `K48-opp-rate`**: `514000000` ⇒ siembra OK, FASE-1a/1c-siembra MUERTAS;
  `19200000` ⇒ el set_rate no llegó (park de `shared_init`) ⇒ FASE-1 revive como fix-OPP;
  `0` ⇒ medida fallida (clock no hallado) ⇒ no decide; otro ⇒ anotar y seguir bracketeando.
  (El `set_rate` ignora su retorno: la medida es el control, bien diseñado.)
- **ACOTACIÓN (lo que el NO no dice)**: cancelado queda "sembrar-como-fix" (1a/1c). SOBREVIVE la
  variante "el primer `shared_enable` reescribe un RCG vivo heredado del ABL" (`:1437`
  incondicional; con inherit=OFF probado por `res-clk-in`): parked_cfg=514 no la excluye. Su fix
  sería 1b/inherit-gate, **otro ciclo**. Que `opp-rate=514` no se lea jamás como
  "clocks exonerados": el criterio FALLA-BIND debe decirlo explícito.

## 4. Criterio (5 ramas) y runbook: FALTA 1 RAMA + 3 AJUSTES

### 4.1. Falta PASA-MODESET (puede ser EL resultado y hoy no tiene casilla)

Si L48 vive, sddm verá `card1-DSI-1` connected y casi seguro modeseteará antes de 6 min ⇒
"**PASA sin atom-tail**" puede ser inalcanzable, y un éxito total (¡luz!) caería fuera de las
5 ramas. Añadir:

- **PASA-MODESET** (vive ≥6 min + `atom-tail` + migas de commit completas —`K47-enc-en`,
  `brg-pre-en`, `mgr-phy-en` viajan en la imagen L48— + sistema estable): el display-path
  funciona con modeset userspace. Siguiente: vci/DCS/brillo con userspace (línea S1/S3/S4).
- **PASA-LIMPIO** (vive ≥6 min, sin `atom-tail`): L47 fue entorno (C6). **Modetest condicional
  pre-autorizado, un solo intento** (comandos CRITICA-L47 §3.2: `modetest -M msm -c` y un `-s`
  con modo DE LA LISTA) ⇒ sub-ramas PASA-B (modeset OK) / FALLA-B (muere: enable-path).
  Sin esto, PASA solo dice "flaky" y exige OTRO flash para lo que este ciclo puede cerrar gratis;
  el riesgo está acotado (equivale a FALLA; rollback ya contado). El "NO modetest" del prep es
  correcto para las ramas FALLA, no para PASA.

### 4.2. Lectura `L6-open` post-bind (C5-open): la triage que falta en FALLA-POST/COMMIT

(`msm_open`, `msm_drv.c:282-293`, primera sentencia = poke + flush ⇒ un open racing la muerte
sí imprime.) En el ACM, tras `post-init`:

- `L6-open` (t>47 s) + muerte sin `pan-modes` ⇒ muerte en open/`load_gpu` (**pista GPU/GMU, no
  display** — reorienta a GMU/icc, no al DPU).
- `L6-open` + `pan-modes` sin `atom-tail` ⇒ muerte entre ioctls userspace (apunta fuera del
  kernel-display).
- Sin `L6-open` ⇒ cero tráfico DRM (kernel-diferido/flaky). Límite honesto: `L6-open` no
  distingue card0/card1; la regla es aproximada por timestamp (mejora opcional, no bloqueante:
  imprimir el minor en `msm_open`).

### 4.3. Resto de ajustes al criterio

- FALLA-COMMIT: añadir orden relativo `alive-1` vs `atom-tail` (si alive-1 va primero, la ventana
  post-bind ya estaba acotada antes del commit).
- FALLA-BIND: precondición `K47-dpu-hw-in` presente (si ausente ⇒ FALLA-TEMPRANA); última miga =
  "murió EN o DESPUÉS" (E6 bien aplicado); sub-lectura OPP de §3 explícita + la acotación
  "514 no exonera el rewrite".
- FALLA-POST: exigir ACM archivado o degradar a INCONCLUYENTE (§1.2, §2.4-B).

### 4.4. Runbook corregido (cambios sobre L48-PREP §6–§7)

1. Pre-vuelo +: **cargador de pared** (en fastboot no carga; docs/historia/AGENTS.md), `dmesg -n 7` antes de
   juzgar (regla 2 hermana), slots ANTES/DESPUÉS en la fila (H2+L47 quemaron `a`; si `b`<3 o
   algún `unbootable` ⇒ aplazar a mañana, sin negociación en caliente), semáforo inter-proyecto
   ✓ (ya citado), ACM lector único + **commitear el ACM** (§1.2, §1.4).
2. Build: L47 + `l48-migas.diff` (+2 susp opcionales) con **gates exactos de §2.3**; cmdline 566 B
   display-ON ✓; `FBDEV=n` se mantiene ✓ (variable única: instrumento).
3. Flash: 1 escritura `boot_a`, s287 intacto, sha pre-registrado + readback al tamaño exacto ✓.
4. Observación: doble captura; SSH intocable salvo PASA-LIMPIO→modetest (§4.1); ≥6 min; mV final.
5. Rollback L45 (2ª escritura, cupo del día) ✓. Riesgo no declarado: **L48+rollback = 2
   escrituras = el tope diario**; cualquier imprevisto mueve el resto a mañana.

## 5. ¿Maximiza información por escritura? Casi — lista cerrada de cambios

**Añadir** (concreto, con sitio): (1) 2 pokes suspend (§2.4-hueco); (2) rama PASA-MODESET (§4.1);
(3) modetest condicional solo-en-PASA (§4.1); (4) triage L6-open (§4.2); (5) lectura opp-rate en
4 valores + acotación FASE-1 (§3); (6) gates exactos 11+1 (§2.3); (7) ACM commiteado + nombres
por ciclo + restaurar evidencia H2 (§1.2, §1.4); (8) precondiciones FALLA-BIND/TEMPRANA (§4.3).
**Quitar/cambiar**: orden `mdss-en` ×1 → ×2 (§2.4-A); "12 tags ×1" → gate exacto; includes
sobrantes (opcional). **No añadir**: VBIF-gates, GDSC, `msm_atomic_commit`, panel/DT, fase-1
(funcional) — otro ciclo. Con esto, 1 escritura distingue 6 desenlaces + cierra FASE-1a/1c +
deja PASA accionable: eso sí es máxima información por escritura.

## 6. Qué he verificado y qué no (honestidad)

Verificado en árbol/dumps/git todo lo citado con fichero:línea. No re-verificado (citado de
CRITICA-L47 §2.2): no-op de `drm_client_setup` con `=n`. No verificado (hedge declarado): punto
exacto del primer schedule en `drm_kms_helper_poll_init` (el periodo 10 s sí,
`drm_probe_helper.c:266`). Hipótesis marcadas: C5-open/sddm post-48 s, C6-flaky, variante
rewrite-en-vivo. Nada de memoria.
