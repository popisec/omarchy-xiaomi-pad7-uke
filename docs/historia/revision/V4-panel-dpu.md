# V4 — Camino del PANEL (DSI/DPU/o82): hueco de instrumentación, sospechosos con datos, sonda 0-flash y coste del siguiente flash

**Solo-lectura 1-oct-2026. Tablet NO tocada, 0 commits, 0 flashes. Único fichero escrito: este.**
Base de código: `build/kernel-pokes/k18-tree` (el que se compila; líneas verificadas iguales en
`~/gpu-work/palawan-linux`). DT fusionado: `build/evidencia/2026-09-28/dt-reconstruido/`
(base vendor + payload s238). Plan vigente citado: `docs/historia/PLAN-SIGUIENTE-v4.md` (=`PLAN`).

**Medido** = fichero:línea o log citado. **Hipótesis** = marcado como tal. Lo no verificable,
en §6.

---

## 0. Punto de partida (medido, no re-descubierto)

- Panel Xiaomi o82 dual-DSI en `build/kernel-pokes/k18-tree/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`,
  21 migas `UKE-P82`: power_on por supply (:279-293), reset por flanco (:256-267), una por comando
  DSI (:218), freq_sel (:350), sleep-out (:355), display-on (:358), backlight (:365-367),
  `prepare: COMPLETO` (:367), entrada de `get_modes` (:414).
- Con `video=DSI-1:d`: 0 migas P82 en todos los logs (ausencia trivial: el panel no se habilita).
- K17-plain (modeset+migas al arranque) **jamás voló**: #P46 sin fila RESULTADO
  (`PRE-REGISTRO-PANTALLA.md:421-425`). La "visibilidad de P82 en muerte real" es **NO VERIFICADA**.
- #P43 medido (`PRE-REGISTRO-PANTALLA.md:385-386`): `modetest -M msm -c` cuelga→panic→reboot 2×,
  **igual con el fw sqe oculto** ⇒ el asesino del open NO es la carga del GPU (refuta el veto v3
  a modetest). U2 §1 + V1-D1 lo recogen; PLAN §P2.1 ordena P2-ctrl primero.
- #P40/#P42 medidos (`PRE-REGISTRO-PANTALLA.md:379-382`): K13-dsid + s260, sistema estable por SSH,
  `card0-DSI-1` + `card0-Writeback-1` + `renderD128`, `[drm] Initialized msm 1.13.0` a 4,06 s.
  **KMS+SMMU+card0 LISTOS; el wedge vive en el camino del panel.**
- SMMU como asesina del panel: REFUTADA (ledger #445: sin el `-22` del dpu y con el kms pasado,
  la muerte igual).

Orden de ejecución real del modeset (código, no memoria): fbdev-client/modetest → `get_modes`
→ cadena de bridges con `pre_enable_prev_first` (el panel pone `prepare_prev_first=true`,
panel driver :653; propagado en `drivers/gpu/drm/bridge/panel.c:302`; orden documentado en
`drivers/gpu/drm/drm_bridge.c:846-888`): **el `o82_prepare` corre ANTES que el enable del host
DSI**. Luego `dsi_mgr_bridge_pre_enable` → encoder enable → kickoff (+DSC) → CRTC enable →
timing on → frame-done/vblank.

---

## 1. Hueco de instrumentación: puntos de miga accionables, en orden de ejecución (ENTREGABLE)

Rutas relativas a `drivers/gpu/drm/msm/` en k18-tree (líneas = las del árbol que se compila).
Cada miga: `pr_info("UKE-P82D: <etiqueta> ...")` + `pr_flush` tras la que pueda preceder a un
wedge (REGLAS.md R13). Solo códigos de retorno, booleanos de estado y lecturas simples por
helpers ya existentes del driver (nada de rangos MMIO: REGLAS.md R3).

| # | Función y sitio | Qué registrar (diagnóstico que cierra) |
|---|---|---|
| 0 | `msm_fbdev_driver_fbdev_probe` — `msm_fbdev.c:89` | entrada. Distingue "muerte en fbcon del arranque" de "muerte en open manual". |
| 1 | `o82_get_modes` salida — panel driver `:411-443` (solo hay miga de entrada, `:414`) | `return desc->num_modes` (esperado 1) + `connector->display_info.bpc` (=10). Si el wedge es *dentro* de get_modes tras "entrada", hoy es invisible. |
| 2 | `dsi_mgr_bridge_power_on` — `dsi/dsi_manager.c:211` | entrada + `is_bonded_dsi` (esperado 1: ambos DSI llevan `qcom,dual-dsi-mode`, fused `dt-nodos-clave.txt:196-260`) + ret de `dsi_mgr_phy_enable` + ret de cada `msm_dsi_host_power_on`. |
| 3 | `msm_dsi_host_power_on` — `dsi/dsi_host.c:2479` | ret de `regulator_bulk_enable` (vdda/vddio), ret de `link_clk_set_rate`/`link_clk_enable` (`:2507-2515`), `byte_clk_rate`/`byte_intf_clk_rate`. **Este ret separa "reloj/rail DSI" de "panel no responde".** |
| 4 | `dsi_mgr_bridge_pre_enable` — `dsi/dsi_manager.c:278` | rama master/esclavo (`:286-287` retorna sin tocar el host si es slave en bonded) + ret de `msm_dsi_host_enable(host)` y `(host1)`. En bonded el master enciende AMBOS hosts (`:299-310`). |
| 5 | `msm_dsi_host_enable` — `dsi/dsi_host.c:2428` | `msm_host->enabled=true` + `mode_flags & MIPI_DSI_MODE_VIDEO` (esperado 1; el panel declara `MIPI_DSI_MODE_VIDEO\|LPM`, panel driver `:586`). |
| 6 | `dpu_encoder_virt_atomic_enable` — `disp/dpu1/dpu_encoder.c:1337` | entrada + `dpu_enc->dsc` NULL/no-NULL (esperado no-NULL: viene de `msm_dsi_get_dsc_config`, `:639-651`) + `hdisplay/vdisplay` del `cur_mode` (3200×2136). |
| 7 | `dpu_encoder_phys_vid_enable` — `disp/dpu1/dpu_encoder_phys_vid.c:446` | `hw_intf->idx` de cada phys (dual-DSI bonded = 2 phys: master+slave, slave primero en `:1361-1366`), `enable_state`, presencia de `hw_pp->merge_3d` (dual-DSI pasa por `setup_3d_mode`, `:327-328`). |
| 8 | `dpu_encoder_prepare_for_kickoff` / `dpu_encoder_prep_dsc` — `dpu_encoder.c:2070` / `:2018` (+`:2103` llamada, solo `if (dpu_enc->dsc)`) | `catalog->dsc_count` (¿hay ≥2 bloques DSC en SM7675 mainline? **sospechoso DSC, §2.9**), `num_dsc` (esperado 2), `dsc_common_mode` (SPLIT\|MULTIPLEX\|VIDEO), `slice_width` (=800), `pic_width` (=3200). Si `dsc_count<2`, el `WARN(topology->num_intf > 2)` / topología degradada es la firma. Programación real en `dpu_encoder_dsc_pipe_cfg` (`:1990-2012`: `dsc_config` en `dpu_hw_dsc.c:45` / `dpu_hw_dsc_1_2.c:87`, `setup_dsc`+`enable_dsc` del pingpong). |
| 9 | `dpu_crtc_enable` — `disp/dpu1/dpu_crtc.c:1269` | ret de `pm_runtime_get_sync` (`:1280`; GDSC apagado = aquí) + `encoder_mask`. `drm_crtc_vblank_on` en `:1304`. |
| 10 | timing on + vblank IRQ — `dpu_encoder_phys_vid.c:665` (`enable_timing(...,1)`), `:671-695` (irq enable, `control_vblank_irq(...,true)` en `:679`) | `intf_status` vía `hw_intf->ops.get_status` (lectura simple ya usada en `:628-629`) + `get_line_count` (`:706-709`). **Línea que avanza = el DPU escanea aunque el panel esté negro.** |
| 11 | frame-done — `dpu_encoder_phys_vid_wait_for_tx_complete` (`:505-541`, ret; `-ETIMEDOUT` en `:531`) y `dpu_encoder_frame_done_callback` (`:366`) | ret del wait + `pending_kickoff_cnt`. **Timeout aquí con timing on = DPU vivo, frame no completa (underflow/scanout); sin llegar aquí = muerte antes del primer kickoff.** Contador acumulado: `vblank_cb_count` (`dpu_crtc.c:1776-1788`). |

Lectura del veredicto (aproximado hasta medir D4): última miga impresa = punto de muerte ±1
escalón; el sospechoso (d) del plan queda partido en 6 sub-tramos (3-4 = host DSI, 6-8 = DPU/DSC,
10-11 = scanout). Nota K5 (V1): en rama B cada `open()` re-corre la escalera GMU → contar solo
la última `UKE-P82(D)`, no la última miga absoluta; P2-skip elimina el re-lanzamiento.

---

## 2. Sospechosos del panel con datos del DT fusionado (s238)

Fusionado = `build/evidencia/2026-09-28/dt-reconstruido/dt-fusionado-s238.dts` (=`FUS`);
overlay = `overlay-s238.dts` (=`OVL`); claves en `dt-nodos-clave.txt` (=`CL`).
Phandles citados en numeración del FUS.

| # | Recurso (nodo) | Quién lo habilita | Si no se habilita |
|---|---|---|---|
| 1 | `vddil8b` → `pmxr2230_l8` (FUS:7790-7798: min=max=0, init 0x1cfde0=1,9 V). Panel: `vddil8b-supply` (CL:294) | panel driver `o82_power_on` índice 0 (:280-293): `set_load(300 mA)` + `regulator_enable` + 2 ms | Lógica del panel apagada: el primer comando DSI falla → `prepare` retorna con `power_on FALLO %d` (:314-318) o `init cmds rc<0` (:326-328). **Firma con miga: muerte ANTES de `cmd[0]`.** |
| 2 | `vsp` → `uke_panel_vsp` (OVL:14719-14729: fixed, +5,8 V 0x588040, `gpio=<0x16b 0x4a>` = TLMM **74**, `boot-on`, ramp 0xe9). Vendor duplicado `display_gpio_regulator_vsp` **disabled** por OVL fragment@156 (verificado OVL:15280-15286) | panel driver índice 1, igual camino | Sin +5,8 V: la lógica puede responder a DCS (cmds OK) pero el panel no pinta. **Discriminador: cmds con rc=0 + pantalla negra = mirar aquí, no el DSI.** |
| 3 | `vsn` → `uke_panel_vsn` (OVL:14731-14741: −5,8 V, TLMM **75**). Vendor duplicado disabled por fragment@157 | panel driver índice 2 | Idem #2 en negativo. |
| 4 | reset → TLMM **GPIO2** (`reset-gpios=<0x16b 0x02 0x01>`, CL:291; pines s258 `gpio2`, OVL:14747+) | `o82_reset` (:254-268) tras `devm_gpiod_get("reset")` en probe (:614) | Probe defiere (`-EPROBE_DEFER`): sin conector, sin modes. **Era s238**: 4 refs activas → shared → proxy → `failed to get reset gpio` (EVIDENCIA-PANTALLA-28sep.md:202,261). **Desde s258**: FRAGMENTO-GPIO.dts apaga las 3 refs vendor → 1 ref → directo (INFORME-K12-BUILD.md:94-98; s260=s258+1 línea). **Medido vigente**: con s260 hay `card0-DSI-1` (#P40) y existe el backlight `ae94000.dsi.0` (EVIDENCIA:264-265; el probe solo llega a registrarlo en :655-658 si el reset salió) ⇒ **reset OK en el linaje actual**. |
| 5 | DSI host vdda → `pmxr2230_l4` (FUS:7733-7741: 1,2 V fijo); PHY vdds → `pmxr2230_l2` (FUS:7694-7702: 0,88-0,95 V). Ctrl: `vdda-supply` (CL:199,256); PHY: `vdds-supply` (CL:186,243) | `msm_dsi_host_power_on` (`dsi_host.c:2504-2509` bulk enable) con `pm_runtime_get_sync` (:2507) | `power_on` retorna <0 → `pre_enable` aborta (`dsi_manager.c:293-297`) **con el panel ya preparado** (prepare corre antes por `prepare_prev_first`). Firma: COMPLETO sí, #3 del §1 no. |
| 6 | Relojes dispcc `clock-controller@af00000` (CL:4620-4633) → DSI0: byte/byte_intf/pixel/core/iface/bus (CL:~260) + PHY iface/ref (CL:243-244); DPU `display-controller@ae01000`: nrt_bus/iface/lut/core/vsync (CL:347-356) | `link_clk_set_rate`+`link_clk_enable` (`dsi_host.c:2507-2515`); runtime-PM en CRTC (`dpu_crtc.c:1280`) | ret <0 en el punto #3/#9 del §1. Sin votos de reloj el primer acceso cuelga: misma firma que #5, se separan por QUÉ ret. |
| 7 | `power-domains`/GDSC: `mdss_ml` = `<0x154 0x00>` (CL:169; 0x154 = dispcc, `#power-domain-cells=1`); DPU y DSI cuelgan del padre (el nodo `mdss_mdp_ml` no lleva `power-domains` propio, CL:347-380) + `resets`/`interconnects mdp0-mem` (CL:170-172) | `pm_runtime_get_sync` en `:2507` y `dpu_crtc.c:1280` | GDSC caído: cuelgue en el get (no ret). Interconnect sin votar: underflow (`underrun_cnt`, `:505` ss.), no wedge. |
| 8 | Backlight `ae94000.dsi.0` (registrado en :655-658, vía DCS 0x51, sin PWM; `backlight_enable` en :366) | `prepare` (:365-367) | Modeset OK + negro + `brightness`=0 ⇒ cable eléctrico, no DSI/DPU. (systemd-backlight falla sobre él, EVIDENCIA:264: existe pero sin usuarios.) |

**Corrección a la pista del encargo (74/75 + gpio-shared-proxy):** con 1 referencia activa
cada uno (duplicados vendor en `disabled` desde s238), los pines **NO son compartidos** y el
proxy **no participa**: umbral en `gpiolib-shared.c:739-763` (`num_nodes<=1 → false`) +
tabla de asimetría en INFORME-GPIO-RESET.md §1 (74/75: 1 ref → directo; GPIO2: 4 refs →
proxy) + AUDITORIA §3.1 (`display_gpio_regulator_vsp/vsn` disabled, `enable-gpios` ausente).
El riesgo real de vsp/vsn es el enable del `reg-fixed-voltage` en sí (#2-3), no el proxy.
**Hipótesis refutada con código; no reabrir sin dmesg nuevo.**

---

## 3. Sonda 0-flash (P2-ctrl, PLAN §P2.1): discriminar sin escribir

Todo bajo `dmesg -w` al PC (doble captura, REGLAS.md R4) y una sola apertura desprendida por
peldaño. `SSH` = sesión viva al sistema K23-dsid estable.

```sh
# (a) ¿el panel recibe corriente? — lectura, 0 ioctls de modeset
ls /sys/class/drm/                                            # espero card0-DSI-1 + Writeback-1 + renderD128 (#P40)
cat /sys/class/drm/card0-DSI-1/status /sys/class/drm/card0-DSI-1/enabled
cat /sys/class/drm/card0-DSI-1/modes                            # con :d vacío; tras quitar :d debe traer 3200x2136
cat /sys/kernel/debug/regulator/regulator_summary | grep -Ei "l8|vsp|vsn|vdda|l2|l4|uke_panel|display_panel"
ls /sys/class/backlight/ ; cat /sys/class/backlight/*/brightness /sys/class/backlight/*/actual_brightness
cat /sys/kernel/debug/devices_deferred                          # ¿sigue el panel diferido por algo?
dmesg | grep -c "UKE-P82"                                       # espero 0 con :d (línea base)
```
- `regulator_summary` sin `uke_panel_vsp/vsn` enabled ⇒ #2-3. Sin `pmxr2230_l8` ⇒ #1.
  (Si el panel probeó, sus 3 supplies existen como consumidores; si falta el nodo, el probe
  ni corrió.)
- backlight `ae94000.dsi.0` ausente ⇒ probe no llegó a :655 ⇒ mirar `devices_deferred`
  (reset, #4).

```sh
# (b) ¿el DPU escanea? — Writeback: DPU+DMA+scanout a memoria, SIN panel
modetest -M msm -c | grep -i writeback                          # nombre exacto del conector WB
# commit atómico con FB_ID sobre el conector Writeback (una sola apertura, captura armada)
```
- WB wedguea ⇒ asesino DPU/DMA (sospechoso d, lado DPU), el panel queda excluido.
- WB completa ⇒ DPU+DMA vivos; el segundo asesino es panel-side (DSI host/cmds/rails).

```sh
# (c) backlight-only (si el probe llegó a :655): valida el camino eléctrico sin modeset
echo <nivel> > /sys/class/backlight/ae94000.dsi.0/brightness    # DCS 0x51 por el link ya entrenado del boot
```
```sh
# (d)-(e) el DSI host ¿envía? — escalera GETCONNECTOR → modeset
modetest -M msm -c                                              # solo abrir+listar; corre get_modes (miga :414)
modetest -M msm -s <conn>@<crtc>:<mode>                         # modeset completo: prepare→DSI→DPU→vblank
dmesg | grep "UKE-P82"                                           # última miga = punto aproximado (§1)
```
- (d) mata ⇒ wedge en get_modes/panel-power/cmds (zona panel driver, con migas por comando).
- (d) vive + (e) mata tras `COMPLETO` ⇒ zona §1 #3-11; la tabla dice el sub-tramo.
- (e) vive ⇒ panel pintando: FOTO (no cierra OBJ 6: falta fbcon al arranque + frío, V1-D9).

Tabla de decisión: **corriente no** (a-falla) / **DSI no envía** (d-falla / e muere en #2-5) /
**DPU no escanea** (b-falla / e muere en #6-11 con cmds OK).

---

## 4. Coste de un flash y siguiente artefacto tras `S4-pollOK`

**Coste (un ciclo, REGLAS.md §2 + PLAN §1/§4):** presupuesto del día AGOTADO (1-oct: ≥5
escrituras documentadas; cualquier escritura más = re-negociación explícita del dueño en la
fila) + `fastboot getvar battery-voltage` ≥3700 mV y cargador de pared + `getvar all`
(4 retry-counts) antes/después, todo a A, B=rollback intacto + consola de lector único SIN
`timeout` + vigía con pausa + e2fsck previo (zombi recurrente) + **una sola fila PRE-REGISTRO
+ una fila del ledger hermano ANTES de flashear, un solo cambio por ciclo**.
**Específico de panel (V1-D2/D3) y gratis en escrituras:** quitar `hung_task_panic=1` de la
cmdline del repack (cada wedge de DSI con ese flag = pánico+reboot+dmesg perdido; K20 midió
el stall análogo como local con máquina viva) y hornear primero las migas del §1 (offline,
0 tablet) — volar P2-plain sin ellas quema el ciclo sin diagnóstico.

**Siguiente artefacto cuando la GPU llegue a `S4-pollOK` (+`H8`/`H9`+`H10-hfi` sin FAIL):**
rama A del árbol §P0.4 → **P2-ctrl primero** (0 escrituras, §3 de este informe: diagnostica
antes de gastar el flash) → **P2-plain**: repack del mismo kernel SIN `video=DSI-1:d` +
migas §1 + sin `hung_task_panic` → modeset del arranque → fbcon → **FOTO**
(`build/logs/evidencia/P5x-foto-N.jpg` + sha en la fila, sin fichero no cierra) → cold boot
+ 2ª FOTO (cierre OBJ 6). En ramas B/C/F, P2-plain NO (M2/G1: sin GPU no hay card0 medido):
ahí el artefacto de panel es **P2-skip** (`msm.uke_skip_load_gpu=1` por cmdline + miga
temprana `UKE-K24: skip_load_gpu=1`, hoy inexistente — grep vacío verificado en V1-D8) como
aislador del segundo asesino, y **K24** (mapear icache@0x4000 en CB1, banner v4) como fix GPU.

---

## 5. Qué dice esto del "asesino unificado" (hipótesis, no medido)

El wedge del CM3-fetch (S3-rst0) y el wedge del camino del panel comparten firma (muerte muda
temprana) pero ya hay una separación medida: #P43 muestra que el open del DRM mata igual sin
el fw sqe, y #P40 muestra el KMS completo y estable con el panel aparcado. **Hipótesis de
trabajo:** dos asesinos independientes (CM3-fetch por un lado; DSI-host/cmds/DSC/rails por
otro), con el del panel aún sin localizar porque su zona entera (§1 #1-11) carece de migas.
Este informe no la cierra: da los instrumentos para cerrarla en 1-2 ciclos (P2-ctrl + P2-plain
con §1). El candidato alternativo (un solo wedge común aguas arriba, p. ej. GDSC/reloj del
MDSS) queda falsable por el peldaño (b): si el Writeback completa, lo común está vivo.

---

## 6. NO VERIFICADO (explícito, para no suponerlo)

1. Visibilidad de `UKE-P82(D)` en una muerte real (K17-plain jamás voló; #P46 sin RESULTADO).
2. Capacidad DSC del DPU mainline en SM7675 (`catalog->dsc_count`, nº de bloques, merge dual-DSI):
   solo leíble en vivo o en el catálogo del árbol (pendiente 1 grep).
3. `min/max` de `pmxr2230_l8` en el dtbo **vigente** (s260/s263): el FUS-s238 dice 0/0
   (FUS:7792-7793) pero OVL-s238 fragment@100 (`&L8B` = `regulator-pmxr2230-l8` del base,
   base:6758) fija min=max=init=0x1cfde0 — el fusionado archivado es anterior a ese
   fragmento o se construyó de otra revisión. `fdtget` sobre el dtbo real lo decide en 1 min.
4. Qué `regulators[]` de `dsi_cfg.c` usa el DSI de esta SoC (visto el patrón vdda+vddio en
   varias tablas; el match por compatible no verificado) — no bloquea: el DT manda vdda(L4)
   al ctrl y vdds(L2) al PHY.
5. Ventana de consola 3,95-4,18 s para las migas del modeset al arranque (U2: la ACM la pierde
   por el flood; P2-plain la necesita o el dmesg por SSH).
6. Líneas de este informe contra `k18-tree` salvo las 20 del §1 verificadas por grep hoy
   (panel driver leído entero; resto msm verificado en palawan-linux + §1 en k18-tree).
