# REVISIÓN FORENSE BOOTS L46/L47/L48 — timelines, deltas e hipótesis (14-oct-2026)

> Subagente revisor forense. Solo lectura (tablet incluida: SSH no usado; todo sale de
> ficheros ya commiteados + ledger). Base leída: `docs/historia/revision/PIPELINE-PANEL-20261014/BRIEF.md`, `H2-CRASH-CAPTURADO-20261014.md`,
> `docs/historia/revision/PIPELINE-PANEL-20261014/CRITICA-L47.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/CRITICA-L48.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/L48-PREP.md`, `NOTAS-OMARCHY.md` (entradas 14-oct),
> `docs/historia/ESTADO-VIVO.md` (capas 14-oct 11:3x–14:4x), ledger #620/#621/#622.
> Material primario: `out/h2-dumps-l46/uke-{8,28,48}.txt.gz`,
> `out/h2-dumps/uke-{8,28,48,934…1095,2449…2611,6780…6901}.txt.gz`,
> `out/acm-L48.log`, `out/acm-flash-20261014.log`.

## 0. Atribución verificada de cada fichero (sin ella, todo lo demás es humo)

La cmdline va partida en 2 líneas de dmesg: el `grep "video=DSI-1:d"` ingenuo da falso
negativo. Atribución por `video=DSI-1:d` (2ª mitad de la cmdline) + inventario de migas:

| Fichero(s) | `:d` | K47 | K48 | Boot = | Uptime máx |
|---|---|---|---|---|---|
| `h2-dumps-l46/uke-8/28/48` | NO (display-ON) | 0/0/4 | 0 | **L46** (`32cc4329…`, H2) | 47.67 s |
| `h2-dumps/uke-8` | NO | 0 | 33 | **L48 boot-A** (otro boot que 28/48: danza mdss a 0.563 s vs 0.513 s, §3) | 8 s (dump completo con trailer) |
| `h2-dumps/uke-28/48` | NO | 0/5 | 24/42 | **L48 boot-B** (mismas stamps tempranas al µs) | 47.27 s |
| `h2-dumps/uke-934…1095` | SÍ | 2 | 0 | **L45+s287 display-off** (resto en LOGFS del boot post-#621, §6.3) | 1092 s, vivo |
| `h2-dumps/uke-2449…2611` | SÍ | 2 | 0 | **L45+s287 display-off** (boot largo previo, LOGFS persistente) | 2604 s, vivo |
| `h2-dumps/uke-6780…6901` | SÍ | 2 | 0 | **L45+s287 control H2** | 6897 s = 1.9 h, vivo |
| `out/acm-L48.log` (187 KB) | — | 0 | 57 (solo danza temprana) | L48, 7 boots fragmentados | **9.54 s máx. INÚTIL para la muerte** (§6.1) |
| `out/acm-flash-20261014.log` (582 KB) | — | 0 | 0 | pre-L47 (sin bind a 47 s en 156k líneas) | 19.34 s máx. |

K47=2 significa solo `tx-alloc`×2 (imagen sin migas L47: L45/L46). K47=4 = +`pan-modes`×2
(L46 con fbcon). K47=5 = `dpu-hw-in`+`dpu-res`×2+`tx-alloc`×2 (L47/L48, sin commit).

**L47 no tiene dump propio**: sus `uke-{8,28,48}` fueron sobreescritos por L48 (nombres por
uptime; CRITICA-L48 §1.4 ya lo denunció; `h2-dumps-l46/` es la copia de rescate que pide).
Su timeline (§1.2) es testimonio de segunda mano (ledger #621 + citas de CRITICA-L48).

## 1. Timelines

### 1.1. L46 (H2) — `h2-dumps-l46/uke-48.txt.gz`, 3026 líneas, display-ON, `card1-DSI-1: connected`

| t (s) | Línea(s) | Evento |
|---|---|---|
| 0.31 | 908 | `disp_cc_mdss_mdp_clk_src: rcg didn't update its configuration` (también en todos) |
| 0.312 | 909–910 | WARN `clk-rcg2.c:136 update_config` (benigno, en todos) |
| 0.327 | 911–912 | WARN `iommu_set_fault_handler` swapper (benigno, en todos) |
| 0.52–0.60 | — | `dsi_get_phy: phy driver is not ready` (host secundario) + reintentos panel |
| 3.73 | — | `X9WAVE-try ae94000.dsi.0` (reintento) |
| 4.17/5.62/6.83 | — | `novatek … SPI transfer timed out` (táctil mudo) |
| **8.283** | **2327–2332** | **Oops `8600000f`, `Comm: insmod`, `lr: fwnode_get_name+0x38`** (pmic_glink/ucsi_glink OOT; no fatal, sigue) |
| 9.32/24.23/39.24 | 2397+ | `L6-open` ×3 pre-bind (card0/GPU) |
| ~47.03 | (H1) | táctil completa probe → re-probe diferido |
| 47.041333 | 2852 | `UKE-L45: backlight externo resuelto` (probe OK, 5º intento) |
| 47.041382/399 | 2853–2854 | `bound ae94000.dsi` + `bound ae96000.dsi` |
| 47.0414–424 | 2855–2859 | `K49-esd-irq` ×3 (GPIOs 86/87, `val=1`, a nivel; ruido, cf. #610) |
| 47.042765 | 2860 | `dpu hardware revision:0xa0010000` |
| 47.0428–428 | 2861–2868 | handoff SMMU (CB69, wmask) + WARN iommu benigno (igual en control) |
| 47.043093/232 | 2869–2870 | `K47-tx-alloc` ×2 |
| 47.045487 | 2871 | `Initialized msm-kms … minor 1` (bind completo) |
| 47.045499 | 2872 | `L6-open` post-bind (apertura fbcon/udev, no commit aún) |
| 47.045593/47.045689 | 2873–2874 | `K47-pan-modes` + `UKE-P82: get_modes: entrada` |
| 47.050593–052648 | 2875–2879 | `fbcon_init: fb_set_par error -16` → `switching to colour fb 400x133` → `fb0: not in virtual address space` ×2 → `fb0: msm-kmsdrmfb` → 2º `pan-modes`+`get_modes` |
| 47.053944–054 | 2880–2926 | burst **`sync_state`: 47 líneas** (disp_cc, gcc, GDSCs adf*/af*, dsi_ctrl0/1, dp, smmu_sde, dsi-display-primary, wb×2…) |
| 47.054–47.668 | 2927–3018 | cola normal (UFS X9UFS-CLK/SYS1CLK, `UNIPRO … not supported`, `dvfs failed (-22)` — ruido conocido) |
| **47.668222** | **3018** | **última línea dmesg** (`dvfs failed (-22)`, ruido UFS) |
| t=48 s | trailer | dump COMPLETO (`fin del dump t=48s`), `card1-DSI-1: connected`, `K47=4`, `l19 … 0 1 0` (open=1/use=0, §4.4) |
| después | — | **silencio** (dump t=68 s inexistente) → reset duro (`pureason=0x80100` en el siguiente boot; limpio = 0x800001) |

Sin `K47-pan-prep`, sin `K47-host-xfer`, sin S4-DIAG: la muerte es pre-DCS. H2 §1 confirmado
línea a línea, con 2 precisiones: la última línea es a 47.668 s (no "47.6") y el trailer del
dump está intacto (muerte >48 s, no truncamiento).

### 1.2. L47 — SIN dump (sobreescrito); reconstruido de ledger #621 + CRITICA-L48 §1.1–§1.2

| t (s) | Evento (testimonio, no verificable hoy) |
|---|---|
| 8.3 | Oops insmod (asumido igual; sin evidencia propia) |
| 46.982771 | `K47-dpu-hw-in` |
| ~46.983 | `K47-dpu-res` (1º) → WARN IOMMU benigno → `K47-tx-alloc`×2 → `K47-dpu-res` (2º, 46.983948) |
| 46.984940 | `Initialized msm-kms minor 1` |
| 47.0–47.06 | X9WAVE + `sync_state` (GDSCs adf*/af09000) |
| t=48 s | snapshot volcador: `K47=5`, `card1-DSI-1: unknown`. **Cero `atom-tail`, cero `pan-modes`, cero fbcon** (=n funcionó) |
| ~50 s | silencio → reset `0x80100`; loop hasta agotar slot |

Estatuto: FALLA-A (H2-fbdev refutado) descansa en un dump que ya no existe. Las 3 citas
numéricas vienen de CRITICA-L48, que sí lo leyó a tiempo. **Releer §6.2 antes de citar L47.**

### 1.3. L48 boot-B — `h2-dumps/uke-48.txt.gz`, 3036 líneas, display-ON, `card1-DSI-1: unknown`

| t (s) | Evento |
|---|---|
| 0.31–0.32 | mismos `rcg didn't update` + 2 WARNs benignos que L46 |
| 0.513–0.516 | danza mdss temprana: `en-in/ok/susp` ×2 (~0.5 s) |
| 0.597–0.603 | tormenta `K49-esd-armado/irq` ×6 (re-registros del probe diferido) |
| 3.73 | `K49-esd-irq` + `armado` (reintento panel) |
| 4.11 | danza mdss ×1 más (`en-in/ok/susp` a 4.107–4.113) |
| 8.423373 | **Oops insmod idéntico** (no fatal) |
| 9.53/24.24/39.24 | `L6-open` ×3 pre-bind. **Cero `L6-open` post-bind en ventana** (difiere de L46: allí el 4º era fbcon) |
| 43.70/44.92/46.13 | táctil timeouts; 47.143 `SPI write @0xff failed: -110`; 47.1647 `chip SIGUE mudo`; **47.165637 `NT36xxx SPI probe ok`** |
| 47.169059–376 | `K48-mdss-en-in/ok` (resume del padre, 1er `shared_enable`) |
| 47.171323 | `UKE-L45` (probe OK) + `bound` ×2 |
| 47.170542–171145 | `K49-esd-irq`×2 + `armado` (a nivel del probe) |
| **47.172076** | **`K48-opp-rate core=514000000`** (esperado 514000000 ✓ — §4.3) |
| 47.174681–175377 | `K47-dpu-hw-in` → `K47-dpu-res` → `K48-res-clk-in/ok` → `res-vbif-ok` → `res-enc-ok` → `K48-hw-resume-ok` → revision `0xa0010000` |
| 47.1755–787 | handoff SMMU (idéntico a L46) + WARN iommu + `K48-hw-mmu-ok` |
| 47.175938–6071 | `K47-tx-alloc`×2 |
| 47.176273 | `K48-hw-vbif-ok` |
| 47.176383 | **`K48-dpu-susp`** (put_sync del hw_init: clocks OFF) |
| 47.176799–7278 | resume#2 (`K47-dpu-res` + `res-clk-in/ok` + `res-vbif-ok` + `res-enc-ok`) + **`K48-dpu-susp`** |
| 47.178463/8472 | `Initialized msm-kms minor 1` + **`K48-post-init`** |
| 47.182072 | **`K48-mdss-susp`** (padre suspendido: MDP_CLK OFF) |
| 47.183–47.189 | `sync_state` (mismo burst) + UFS |
| **47.268352** | **última línea útil** (`dvfs failed (-22)`, ruido); dump completo a t=48 s |
| trailer | `card1-DSI-1: unknown`, `K47=5`, `l19 … 0 1 0`, `K48`: 12/12 señales del bind + `alive` ausente (dispara a +3 s = 50.2 s, fuera de ventana) |

### 1.4. L48 boot-A — `h2-dumps/uke-8.txt.gz` (huérfano: danza a 0.563 s ≠ 0.513 s de boot-B)

Dump completo a t=8 s con trailer. Danza mdss ×11 (vs ×8/×9), `K49` 13 (9 irq + 4 armado),
`l19 … 0 0 0`, Oops pendiente (aún no: el Oops cae a ~8.3–8.5 s; última línea 8.054 + aviso
FAT `sda14 not properly unmounted`). Dos lecturas: (i) boot que murió entre 8 s y 28 s
(muerte temprana, fenómeno nuevo); (ii) boot vivo durante la copia de las 14:06 (sus
uke-28/48 aún no existían). (ii) es más parsimoniosa (la copia fue a las 14:06, sesión
viva hasta 14:08). En ambos casos: **los dumps muestrean ≥2 boots L48 distintos**.

### 1.5. Controles display-off (viven siempre)

`uke-6780` (1.9 h): probe 47.044902 → tx-alloc×2 → `Initialized` 47.052273 → `L6-open`
47.052286 (¡también hay open post-bind con `:d`! ⇒ open ≠ commit) → `no GPU device` →
`sync_state` (**47 líneas, idénticas**) → vive; trailer `disconnected`, `K47=2`, `l19 0 0 0`.
`uke-934…1095` (≥18 min) y `uke-2449…2611` (≥43 min): misma firma. **El bind es el mismo con
y sin `:d`; lo único que difiere es fbcon/commit vs nada.**

## 2. Respuesta Q2 — ¿por qué L46/L47 mueren a ~50 s y L48 vive 5–11 min?

**Delta de secuencia ANTES del punto de muerte: ninguno.** Comparado L46 (medido) vs L48
(medido), evento a evento: Oops insmod ~8.3 s ambos; L6-open ×3 a 9.5/24.2/39.2 ambos;
táctil mudo + probe-OK gatillado por el táctil ambos (H1); `bound` ×2 ambos; handoff SMMU
idéntico; WARNs idénticos; `sync_state` **47 = 47 líneas**; K49 17/16/17 (ruido ESD ±1);
última línea útil = ruido UFS (`dvfs -22`) ambos. **La única diferencia es un offset global
de ~+130 ms en L48** (probe 47.041→47.171; `Initialized` 47.045→47.178; táctil-ok
47.038→47.165): jitter de resolución de deferred-probe, no cambio de camino. El bind dura
~4 ms en ambos. L47 (testimonio) encaja en el mismo molde a 46.98 (~60 ms ANTES que L46).

Sobre la causa del corrimiento, tres hipótesis ranqueadas:

| # | Hipótesis | Veredicto forense | Experimento que la discrimina |
|---|---|---|---|
| H-a | **Flaky/carrera**: la muerte es una race con varianza intrínseca alta (50 s en L46/L47; 50 s–11 min intra-L48: el propio ledger anota boots de 40 s, 5–6 min y 11 min) | **Favorita**: es la única que explica varianza INTRA-L48 sin invocar nada nuevo | Re-flash L47 archivado (`b320616b…`): si algún boot L47 vive minutos, L48 no movió nada (era flaky); si los 6 mueren a ~50 s, H-a cae |
| H-b | **Perturbación E6**: los ~30 `pr_err` de la danza mdss (0.5 s, ~9–11 pares en-ok/susp + K49) + 12 pokes del bind retardan el enable ~µs–ms y desplazan la race | Posible pero **no falsable post-hoc**: L47 no medía la danza (imagen sin K48) ⇒ no hay baseline; y el offset observado (+130 ms) está 2 órdenes sobre lo que unos `pr_err` explican | El mismo re-flash L47 (control sin pokes) + comparar distribución de muertes; o L48 con pokes silenciados (un ciclo) |
| H-c | **Entorno**: batería 3447 mV al flash (#622, bajo gate 3700) + deriva térmica del crash-loop | Débil como causa principal: L46/L47 murieron a 50 s con MÁS batería (3631/3640 mV); pero la deriva 11→5 min intra-L48 correlaciona con sesión larga | Telemetría en el próximo ciclo (mV + `thermal_zone` en cada dump; el dumper ya trae estado) |

Ninguna hipótesis de "el bind cambió" sobrevive: el bind es el mismo al nivel de
resolución disponible (ms). **El punto de muerte tampoco es el mismo**: L46 muere post-fbcon
sin prepare; L47 post-bind sin commit; L48 post-`post-init` con clocks ya OFF (§3).

## 3. Respuesta Q3 — qué se sabe de la muerte

1. **Es siempre "silencio sin traza" dentro de la ventana cubierta**: ningún WARN/Oops/panic
   nuevo en L48 (mismo set que L46 y que el control vivo: `bootconfig`, `clk-rcg2.c:136`,
   `iommu_set_fault_handler` ×2, Oops insmod `fwnode_get_name+0x38`). El Oops es OOT
   (`ucsi_glink(O+) pmic_glink(O)`, `duplicate symbol qcom_add_glink_subdev…` ×4) y lo tiene
   también el control de 1.9 h ⇒ descartado como asesino (una vez más).
2. **`K48-opp-rate core=514000000`** (`h2-dumps/uke-48.txt.gz`, línea del bind a 47.172076):
   **NUEVO — cierra el hueco que el ledger #622 dejó abierto** ("valor no capturado"). FASE-1a/1c
   (siembra) quedan canceladas con medida en vivo, como pedía CRITICA-L48 §3 (lectura 514M).
   Sobrevive solo la variante rewrite-en-vivo (ciclo aparte, inherit-gate).
3. **Muerte con clocks del display APAGADOS** (L48): `K48-dpu-susp` ×2 (47.176383, 47.177416)
   + `K48-mdss-susp` (47.182072) ⇒ tras `put_sync`, DPU y MDSS se suspenden en ~10 ms, sin
   wedge EN el suspend (las salidas imprimen). El relato "asesino en el bind" queda precisado:
   **herida en el bind (efecto retardado), muerte diferida con clocks OFF**. En L46/L47 el
   suspend no se medía pero el código es el mismo ⇒ inferencia, no medida.
4. **Cada boot capturado sigue a un reset duro**: `pureason=0x80100` en las tres cmdlines
   (L46-uke-48, L48-uke-8/28/48); el reboot limpio es 0x800001. Convergencia con el slot
   quemado (a:6→0 en H2 y L47; a=0 en L48): la muerte es real aunque su instante exacto sea
   testimonio (50 s L46/L47 por ausencia del dump-68; 50.2 s–11 min L48 por SSH + `alive-1`).
5. **`alive-1` a 50.2 s (testimonio ledger) es la miga más tardía jamás capturada**; `alive-2/3`
   (+8/+15 s) no aparecen en ningún fichero ⇒ ninguna muerte documentada vivió >~55 s con
   heartbeat armado… salvo los boots de 5–11 min, cuyo contexto se perdió (§6.3). Tensión sin
   resolver: o `alive-2/3` sí imprimieron y se perdieron con los dumps, o esos boots murieron
   sin dejar rastro ACM (plausible: §6.1).

## 4. Matiz nuevo: vci se reclama pero nunca se habilita

Regulator summary en trailers: L46 y L48 `pmxr2230_l19 … 0 1 0` (open=1, use=0, 2600 mV);
control L45 `0 0 0`. Lectura: el driver S1 **sí resuelve `vci-supply`** (open=1, incluso con
el DT s287 idéntico que en el control donde open=0 por falta de soporte en L45), pero el
`enable` (use=1) solo ocurriría en `o82_prepare/power_on`, que nunca corre. Compatible con
#620 ("sin voto") y un paso más fino: **el claim funciona; el enable sigue sin testear**.
S1 no está refutado ni confirmado; sigue vivo para el ciclo con modeset userspace.

## 5. Respuesta Q4 — hipótesis de idle/suspend

Hechos: tras el bind (47.18 s) el sistema queda idle con DPU+MDSS en runtime-suspend
(clocks OFF probado). En ventana 47–50 s (dump) hay CERO tráfico DRM (cero `atom-tail`,
cero `pan-modes` en L47/L48; el `L6-open` post-bind del control prueba que abrir ≠ commit).
El poll DRM (`poll_init`, +10 s) cae fuera de la ventana 47→50 pero DENTRO de la de los
boots largos: **no excluido para las muertes de minutos** (CRITICA-L48 §1.1 solo lo excluye
<50 s). sddm/userspace post-48 s: sin evidencia (ni `L6-open` tardío en ningún fichero…
porque no hay ningún fichero tardío de display-ON).

| Sospechoso idle | Estado |
|---|---|
| runtime-suspend DPU/MDSS | **Medido e inocente del wedge**: entra y sale limpio (susp-ok ×3). Pero deja los clocks OFF: si algo los necesita después (primer commit userspace), el resume es camino no recorrido en display-ON |
| `sync_state` / GDSC deferred | Burst idéntico (47 líneas) en vivos y muertos ⇒ no discrimina; `clk_disable_unused` OFF en ambas cmdlines (`clk_ignore_unused`+`pd_ignore_unused` verificados) |
| cpuidle PSCI/OSI, thermal, devfreq UFS | Sin señal en ventana; el ruido UFS (`dvfs -22`, `UNIPRO not supported`) es idéntico en el control de 1.9 h ⇒ ruido |
| sddm / open tardío (`L6-open` post-48 s) | **Triage pendiente**: la regla CRITICA-L48 §4.2 no pudo aplicarse (sin ACM/dump tardío). Si el próximo ciclo muestra `L6-open` post-bind + muerte sin `pan-modes` ⇒ pista GPU/GMU, reorienta fuera del display |
| Batería/thermal a los minutos | Sin telemetría al morir (hueco §6.4) |

Ranking: (1) actor userspace diferido (sddm/abort de servicio) — único que difiere `:d` vs
no-`:d` tras un bind idéntico (L48-PREP C5, intacto); (2) race/flaky del enable diferido;
(3) resume del primer commit userspace (camino virgen); (4) entorno. El experimento que los
separa es uno solo: **dumper v3 (boot-id, no sobreescribe) + ACM lector-único fiable + misma
imagen L48** → la próxima muerte larga deja contexto (¿`L6-open`? ¿`atom-tail`? ¿`alive-2/3`?
¿nada?). Sin eso, cualquier hipótesis idle es decoración.

## 6. Respuesta Q5 — lo que NO podemos saber (huecos exactos)

1. **La muerte L47 al detalle**: su dump fue sobreescrito por L48. Solo quedan 3 timestamps
   citados (CRITICA-L48 §1.1) y el ledger #621. Toda comparación "L47 vs L48 antes del punto
   de muerte" más fina que §2 es imposible sin re-flashear L47.
2. **El ACM de la muerte**: `acm-L48.log` solo llega a 9.54 s (48k/50k líneas son basura
   intercalada de baud-loss + spam de `duplicate symbol` del Oops de 8.3 s; 7 boots
   fragmentados, 0 líneas útiles post-10 s). `acm-flash-20261014.log` (156k líneas) no
   contiene ni un `K47`/`K48` (máx 19.3 s). **Las muertes a ~50 s y a minutos no tienen
   ninguna traza seriada commiteada.** Por la regla que la propia CRITICA-L48 §1.2 impuso,
   FALLA-POST pende de captura volátil (SSH-testimonio + dumper).
3. **El contexto de los boots largos**: el dumper v3 (boot-id) no se aplicó (SSH caído);
   `uke-934…` prueban que LOGFS conserva lo viejo, pero los nombres por uptime hacen que
   cada boot pise al anterior: del boot de 11 min no queda ni una línea.
4. **`alive-2/3`, `opp-rate` en otros boots, `L6-open` tardío**: ausentes por §6.2–§6.3
   (opp-rate rescatado en §3.2 para un boot).
5. **Telemetría al morir**: ni mV, ni `thermal_zone`, ni `last_kmsg`/pstore citados en
   #620–#622 para el instante de la muerte. `pmic_glink` OOT (el del Oops) es además el
   camino de lectura de batería: su estado tras el Oops no se verificó.
6. **Atribución fina de restos LOGFS**: `uke-934…1095` se asignan al boot L45 post-#621 por
   eliminación (K47=2 + `:d` + mtime 14:06 + uptime 15–18 min que ningún boot L48 documentado
   reclama… salvo que un L48 viviera 18 min, en cuyo caso serían suyos con `:d` imposible —
   descartado por cmdline). `uke-2449…2611` (41–43 min, `:d`) son de un boot L45 anterior
   sin identidad (posible resto del post-#620). La cadena de custodia LOGFS es débil por
   diseño pre-v3.

## 7. Conclusiones y próximos pasos propuestos (decide el orquestador)

1. **El bind es inocente-como-punto y culpable-como-herida**: idéntico al µs-nivel entre
   L46/L48/control salvo offset global +130 ms; completo (`Initialized` + `post-init`);
   suspende limpio; `opp-rate=514000000` cierra FASE-1-siembra. No pedir más migas del bind.
2. **La varianza del tiempo de muerte (50 s → 11 min) es EL dato nuevo**: apunta a race o a
   actor diferido, no a determinismo del enable. H-a favorita, H-b abierta, H-c débil.
3. **Un cambio por ciclo, en orden**: (i) aplicar dumper v3 + ACM fiable y **re-observar con
   la MISMA L48** (cierra §6.2–§6.4 sin gastar variable; el `alive` + `L6-open` tardío
   discriminan actor-userspace vs flaky); (ii) solo después, re-flash L47 archivado como
   control E6 (discrimina H-a vs H-b). Nada funcional (vci/G8/reset/FASE-1b) hasta que (i)
   diga dónde muere de verdad.
4. Custodia: citar L46 siempre como `h2-dumps-l46/` (o `976f714:`); fijar nombres por ciclo
   en el runbook (CRITICA-L48 §1.4 sigue pendiente de aplicar); commitear el ACM aunque sea
   basura (su basura también es dato: §6.1 dice que el lector serie no da para 115200 con
   el spam del Oops — bajar `loglevel` del insmod o `dmesg -n` no afecta al ACM; hace falta
   lector dedicado o baud menor… otro ciclo).
