# S6 — Minucias + DT/config del canal de pantalla (14-oct-2026)

> Solo lectura en tablet (SSH caído: 2 timeouts a `192.168.42.129`, ver §2.5).
> Nada modificado en árboles ni overlays. Dos diffs propuestos + tres items
> cerrados como «no tocar» con evidencia. Hunks disjuntos de S1–S5.

## 1. Qué he leído (lista con fichero:línea de lo relevante)

- `PIPELINE-PANEL-20261014/BRIEF.md` entero (contexto, reglas, formato).
- `build/gates/revision/PREP-MINUCIAS-20261013.md` entero (items a/b/c; el (a)-vci
  es propiedad de **S1**, el (c)-traza-`byte_clk` es propiedad de **S4**; no los toco).
- `PIPELINE-PANEL-20261014/S2-G8.md:127-131,191-203` (S2 cubre solo el pulso
  `msleep→udelay`; §6.1-6.3 difiere restore-VID=H5-5a/5b a S4 y el reorden a S3/S4).
- `PIPELINE-PANEL-20261014/S3-RESET-TDDI.md:6,55,77` (reclama para S6:
  `CLOCK_NON_CONTINUOUS` y «backlight a `o82_enable()`»; ambos se resuelven abajo).
- `PIPELINE-PANEL-20261014/S5-PORT-L39.md:14,25,49-50,119` (KTZ=`y` en ambos builds,
  OPP/`=y` no portables; sin solape con este informe).
- Vivo: `build/kernel-pokes/k52-L16-tree/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`
  (`:591-601` desc, `:513-550` modos, `:563-573` DSC, `:728-758` backlight-probe),
  `drivers/gpu/drm/msm/dsi/dsi_host.c` (`:272,331,337` clock-names, `:909-921`
  `dsi_ctrl_enable`, `:2055` OPP clkname `byte`), `drivers/video/backlight/ktz8866.c`
  (`:490-551` probe).
- Vendor: `~/proyectos/ubuntu-uke/stock/dtbo/stock_uke.dts` nodo
  `qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid` (`:13193-13314`: `:13250` lp11-init,
  `:13253` traffic-mode, `:13293-13294` on/off-cmd-state LP, `:13296` clockrate,
  `:13283-13291` DSC, `:13301-13313` porches 120 Hz, `:13242` reset-seq,
  `:13204` bl_ctrl_external, `:13223` delay_until_first_frame); frags KTZ
  `:13793-13819` + targets `:3700` (frag@105→se0), `:3789` (frag@106→se12).
- Base vendor `build/evidencia/stock-dt/stock2-Cliffs7P-uke.dts`: `:14016`
  `qupv3_se0_i2c: i2c@a80000`, `:14562` `qupv3_se12_i2c: i2c@890000`, `:442`
  `aliases: i2c2 = …/i2c@a80000`, `:21204`/`:21232` símbolos.
- Overlay vivo `build/gates/patches/k52L39-fuentes/fase4-display.dts`
  (`:358-364` panel, `:520-566` frags KTZ+backlight; es la fuente de s286 =
  versión `gpu-work/ramaa/s21/dtbo-gpu/fase4-display.dts` + frags L44/L45,
  verificado por `diff` 14-oct).
- `docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:§6 (:460-466), §7 (:469-494), §8 (:506-518)`,
  `docs/historia/revision/ANDROID-DSI-ENABLE-COMPARISON-20261013.md:§H3 (:143-157), §4 ciclo 4 (:241)`,
  `docs/historia/revision/INFORME-MODO-OPP-DSC-20261013.md:§2-§4` (cálculo byte/pixel/DSC verificado —
  mi aritmética independiente coincide al Hz: byte pedido 118918800, pixel
  158558400), `docs/historia/revision/R8-repaso-android.md:52`, `docs/historia/revision/SHENG-APLICACION-20261013.md:40-63,128-153`,
  `build/gates/patches/l37-continuous-clock.diff` (prior art no aplicado).
- `~/proyectos/ubuntu-permanente/docs/REFUTADO.md` + `LECCIONES.md`: grep
  `NON_CONTINUOUS|lp11|ktz|byte_cly|mode_flags|backlight.*enable` → cero entradas
  aplicables (verificado 14-oct-2026). `docs/historia/ESTADO-VIVO.md:17,59-63` (s286 vivo),
  `docs/historia/revision/PIPELINE-PANEL-20261014/MANANA.md:7-9` (batería 3682 mV el 13-oct noche — bajo el gate 3700).

## 2. Estado real del asunto (evidencia)

### 2.1 `MIPI_DSI_CLOCK_NON_CONTINUOUS` — SÍ quitar (único cambio de driver)

- Vivo `panel-xiaomi-o82-dualdsi.c:591-596`: el comentario K48-A dice «sin
  CLOCK_NON_CONTINUOUS» pero el flag **está**. Idéntico en L27/L29/L33/L39
  (PREP §b; `l37-continuous-clock.diff` ya lo deriva contra L33 pero **nunca se
  aplicó**: el flag sigue en L16 `:596`).
- Efecto mecánico (vivo `dsi_host.c:909-917`): con el flag se salta
  `LANE_CTRL |= CLKLN_HS_FORCE_REQUEST` + `msm_dsi_phy_set_continuous_clock` —
  el carril de clock no queda en HS continuo desde `power_on`.
- Contrato vendor (fuente primaria, no memoria):
  `stock_uke.dts:13250` `qcom,mdss-dsi-lp11-init` (lanes en LP11 durante power_on)
  + decompilado `_dsi_display_continuous_clk_ctrl` (ENABLE-COMPARISON H3) que
  gobierna el clock continuo por callback en cada voto de clocks. El flag
  contradice ese contrato.
- Qué **NO** cambiar en el mismo hunk (evidencia vendor entre paréntesis):
  - `MIPI_DSI_MODE_LPM` se **queda**: vendor `on/off-command-state = "dsi_lp_mode"`
    (`:13293-13294`) ⇒ comandos en LP; LPM es su equivalente mainline
    (PROFUNDO §6). Quitarlo rompería los 108 DCS en LP.
  - `VIDEO_BURST` **no** se añade: vendor `traffic-mode = "non_burst_sync_event"`
    (`:13253`); el driver no lleva BURST — correcto así (sheng sí lo lleva,
    pero es otro panel: Tianma LCD vs o82 AMOLED; SHENG §tabla:49 y comentario
    del propio `l37` — no es refutación, es diferencia de panel).
  - EOT: vendor `rx-eot-ignore` + `tx-eot-append` (`:13226-13227`); mainline
    añade EOT por defecto — coherente, no tocar.
- `dsi1` hereda `mode_flags` por `desc` (vivo `:764-765`), luego el cambio cubre
  ambos links. Orden de ciclos: H3 = ciclo 4 de ENABLE-COMPARISON §4 (tras 1a–3);
  no apilar con el pulso S2 (un-cambio-por-ciclo). → **`docs/historia/revision/PIPELINE-PANEL-20261014/s6-noncontinuous.diff`**.

### 2.2 Typo `byte_cly → byte_clk` — FANTASMA: no existe, item cerrado sin diff

- `grep -rn "cly"` en todo `omarchy-uke`: solo `docs/historia/revision/PIPELINE-PANEL-20261014/BRIEF.md:66` (el propio encargo) y
  `cataclysm-*` en `build/stage-escritorio/db/index.txt` (paquete, irrelevante).
  En `gpu-work/`: cero hits relevantes (ruido de licencias/docs). **La cadena
  `byte_cly` no existe en ningún .dts/.dtsi/.c/.h del proyecto ni del vendor.**
- Lo que sí es verdad detrás del item: los `clock-names` vendor y mainline
  difieren por diseño (R3-vendor-diff:333: vendor
  `byte_clk,byte_clk_rcg,byte_intf_clk,…` para el binding `sde-kms`;
  overlay `:295-306,:440-451` `byte,byte_intf,pixel,core,iface,bus` para el
  binding mainline). Los nombres del overlay son los que pide el driver vivo
  (`dsi_host.c:272` `byte_intf`, `:331` `byte`, `:337` `pixel`, `:2055` OPP
  clkname `byte`). Correcto, no tocar.
- SSH caído (2 timeouts, §2.5): la comprobación en el DT fusionado vivo queda
  pendiente como higiene, pero sin ninguna fuente que contenga el typo no hay
  diff que proponer. **Hipótesis descartada por ausencia de evidencia.**

### 2.3 Nodo `ktz8866@11` duplicado — el bueno es `ktz_bl_0` (se0/a80000); sobra `ktz_bl_1`

- Origen del duplicado: **el stock**, no nuestro overlay. Stock DTBO frag@105→se0
  y frag@106→se12 (`stock_uke.dts:3700,3789`), ambos `ktz8866@11` sin más props
  (`:13793-13819`). El overlay los espeja fielmente (fragment@7→`&qupv3_se0_i2c`,
  fragment@8→`&qupv3_se12_i2c`, `:528-556`).
- Cuál es el bueno (tres evidencias encadenadas, sin SSH):
  1. `stock2-Cliffs7P-uke.dts:14016` se0 = `i2c@a80000`; `:14562` se12 = `i2c@890000`.
  2. `stock2:442` `aliases: i2c2 = …/i2c@a80000` ⇒ el adaptador nº2 es se0/a80000.
  3. El driver KTZ bindea en `2-0011` (L44, BRIEF §Estado vivo) ⇒ chip físico en
     se0/a80000 ⇒ **`ktz_bl_0` (fragment@7) es el bueno; `ktz_bl_1` (fragment@8,
     se12/890000) es el fantasma**. El panel además solo referencia `ktz_bl_0`
     (fragment@9, `:564`); `ktz_bl_1` no lo referencia nadie (grep §1: solo su
     definición `:550`).
- ¿Hace daño el fantasma? Poco pero real: el probe KTZ **sí hace I/O**
  (`ktz8866.c:549` `backlight_update_status()` al final del probe → writes I2C
  a 0x11 en un bus sin chip → NACKs + ruido en logs) y mantiene un segundo GENI
  con `status=okay`. No explica la muerte DCS (bus I2C ≠ link DSI) — honestidad:
  es higiene, no diagnóstico. → **`docs/historia/revision/PIPELINE-PANEL-20261014/s6-ktz-undup.diff`** (solo dtbo, ciclo propio).
- Pendiente (sin SSH): confirmar en vivo `of_node` de `2-0011` y que tras el
  dtbo sin fragment@8 el backlight sigue resolviendo (`UKE-L45` en dmesg).

### 2.4 DSC/timings/porches (FASE 4 ROADMAP) — TODO coincide; ningún cambio

| Parámetro | Vendor (`stock_uke.dts`) | Mainline vivo | Veredicto |
|---|---|---|---|
| DSC versión/scr | 1.1 (`:13290`), scr 0 (`:13289`) | 1.1, pre-SCR vía `PRE_SCR` (`o82:563-573` + `dsi_populate_dsc_params`) | ✅ |
| slice | 800×24 (`:13287-13288`), 1/pkt (`:13286`), bpp 8 (`:13284`), bpc 10 (`:13285`), block-pred (`:13283`) | idénticos (`o82:566-571`); `slice_count=2`/link = 1600/800 ✅ | ✅ |
| topología | 2 2 2 (`:13265`), dual ctrl+phy (`:13196-13197`), broadcast+cmd-sync (`:13224-13225`) | `is_dual_dsi`, `qcom,dual-dsi-mode`+`sync-dual-dsi` (overlay `:320-324`) | ✅ |
| 120 Hz/link | 1600×2136 (`:13307-13308`), hfp 113 (`:13312`), hbp/hpw 16 (`:13305-13306`), v 26/146/2 (`:13301-13303`), clockrate 1189190000 (`:13296`) | full-3200 duplicado 226/32/32 + 26/146/2 (`o82:513-525`); aritmética del split verificada al Hz (INFORME-MODO §2: pixel 158558400 vs vendor 158558666, Δ266 Hz = ruido) | ✅ |
| 144/90 Hz | hfp 18/304, resto igual (PROFUNDO §7) | entradas `[1],[2]` presentes pero `num_modes=1` (`:583`) porque el prepare siempre escribe `b3/b2` de 120 Hz | ✅ conservador; el switch HS+DFPS-porches es P3 futuro (PROFUNDO §8.9), no este ciclo |
| `panel-clockrate` | 1189190000 = **bitclk/lane** (INFORME-MODO §1: 1745×2310×120=483.7 MHz nativo; C/8=148648750 medido en `state_info`) | sin campo equivalente (el modo lleva pixel-clock 967428 kHz); byte pedido 118918800 vs vendor 148648750 | ⚠️ conocido (R1 OPP-ceil → byte real 187.5M, timings PHY a velocidad equivocada) pero es territorio **G5/G6 = inertes** (BRIEF) y porte **S5** — fuera de S6 |
| PHY tunings/clk-strength/voltaje | `phy-timings=[00 27…]`, strength 0xff, voltage 0x51 | defaults PHY 4nm | segunda vuelta solo con artefactos (PROFUNDO §6) — no tocar |

### 2.5 Incidencias de método (para el orquestador)

- **SSH caído**: `ssh … root@192.168.42.129` timeout ×2 (14-oct noche). Sin
  escritura intentada; solo lectura. Pendiente: `of_node` de `2-0011`,
  `clock-names` fusionados, `clk_summary` (R1), `i2cdetect` se12.
- **Batería**: MANANA registra 3682 mV la noche del 13-oct (< gate 3700).
  El ciclo de la mañana exige re-medir `fastboot getvar battery-voltage` antes
  de cualquier flash.

## 3. Cambios propuestos (diffs exactos)

- **`docs/historia/revision/PIPELINE-PANEL-20261014/s6-noncontinuous.diff`** (base `build/kernel-pokes/k52-L16-tree`, `patch -p1`;
  rebase a L16 del prior-art `l37-continuous-clock.diff` de L33, nunca aplicado;
  verificado `patch --dry-run` limpio en copia, §4): quita
  `MIPI_DSI_CLOCK_NON_CONTINUOUS` de `mode_flags` (`o82:595-596`), conserva
  `VIDEO|LPM`, amplía el comentario con la evidencia vendor. Hunk único.
- **`docs/historia/revision/PIPELINE-PANEL-20261014/s6-ktz-undup.diff`** (base raíz del repo, `patch -p1`; verificado dry-run en
  copia): elimina `fragment@8` (`ktz_bl_1` en se12/890000) de
  `build/gates/patches/k52L39-fuentes/fase4-display.dts` + ajusta el comentario
  `:520-526`. Solo dtbo; el kernel no se recompila para este ciclo.
- Sin diff (cerrados con evidencia): typo `byte_cly` (§2.2), DSC/timings (§2.4),
  `MIPI_DSI_MODE_LPM`, `VIDEO_BURST`, EOT (§2.1), backlight-en-enable — ver §6.

## 4. Criterio pasa/falla prefijado (comando + salida esperada)

- **s6-noncontinuous** (ciclo H3 = ciclo 4 de ENABLE-COMPARISON §4; boot nuevo +
  mismo dtbo s286; display encendido — quitar `video=DSI-1:d` —; batería ≥3700 mV
  registrada; doble captura ACM + `dmesg -w`; `dmesg -n 7` antes de juzgar):
  **PASA** si hay movimiento de firma direccional (el ráfaga `status=4` de
  `K47-host-en` desaparece, o `cmd#0` recibe ACK, o el punto de muerte se
  desplaza). Juicio:
  `ssh -i build/rootfs/uke-arch-root -o BatchMode=yes root@192.168.42.129 'dmesg | grep -E "status=4|FIFO|TIMEOUT|uke_poke|K47"'`
  vs `out/diag-L33/VENTA-MUERTE-acm-207s.txt` (HALLAZGO-MUERTE-DSI §8).
  **FALLA** (firma idéntica) → H3 refutada con control; no reintentar.
- **s6-ktz-undup** (ciclo propio, solo dtbo; 1 escritura dtbo): **PASA** si
  `/sys/firmware/devicetree/base/soc` muestra un solo `ktz8866@11` (bajo
  `i2c@a80000`), `dmesg | grep -E "UKE-L45|ktz8866|backlight"` muestra el bind
  en `2-0011` sin regresión, y la firma DSI no cambia (se espera: no toca el
  link). **FALLA** (backlight perdido o no-probe en se0) → rollback a s286 y el
  fantasma se queda documentado como benigno.
- Verificación sin tablet (ya ejecutada): ambos diffs aplican con
  `patch --dry-run -p1` en copias (verificado 14-oct en /tmp/opencode/s6check);
  tras aplicar, el flag desaparece del código (`mode_flags` limpio; las 2
  menciones restantes de NON_CONTINUOUS son comentarios del propio hunk);
  `ktz_bl_1`/`fragment@8` eliminados salvo mención en el comentario;
  `fdtoverlay -i base -o merged` en verde antes de flashear el dtbo
  (regla AGENTS nº1).

## 5. Riesgos y refutaciones que aplican (REFUTADO/LECCIONES)

- Sin colisión: grep en REFUTADO/LECCIONES sin entradas sobre
  `NON_CONTINUOUS|lp11|ktz|mode_flags` (14-oct-2026).
- H3 no está refutado por sheng: sheng lleva NON_CONTINUOUS y enciende, pero es
  panel Tianma LCD con otro secuenciado; el o82 AMOLED declara `lp11-init` y el
  vendor lo gobierna por callback — paneles distintos, contratos distintos
  (documentado en el propio hunk para no re-discutirlo).
- Riesgo s6-noncontinuous: bajo-medio (P0 aceptado, H3). El clock HS continuo
  desde `power_on` es exactamente lo que el vendor hace por callback; si la
  firma no se mueve, H3 queda refutada con control y se cierra otra vía de
  «configuración del enlace».
- Riesgo s6-ktz-undup: bajo (quitar un nodo que nada referencia; el probe del
  bueno no cambia). Riesgo residual: si el chip físico estuviera en se12
  (contra-evidencia de §2.3.2-3) el backlight se perdería — el criterio §4 lo
  detecta y el rollback es el dtbo s286 intacto.
- Presupuesto: 1 escritura por ciclo, ≤2/día, retries y batería registrados;
  si el gate no da, ambos diffs esperan sin apilarse (E1).

## 6. Qué NO hacer / lo que queda fuera

1. **No** reordenar ENABLE/VID/DCS en este pipeline (disposición del encargo S2→S6):
   orden vendor (SECUENCIA-ANDROID: host_init ×2 → rails+reset → LINK_CLK →
   ENABLE → soft_reset 1 µs → 108 DCS con vídeo OFF → VID_MODE_EN al final,
   `vid_engine_enable.c:25`) vs mainline (`dsi_ctrl_enable:919-921`
   CLK+lanes+ENABLE juntos; `dsi_op_mode_config:1221+1226` VID+ENABLE juntos
   **antes** de los DCS; panel con `prepare_prev_first=true` (`:726`) corre sus
   DCS antes del `pre_enable` del host). Es rediseño del secuenciado DRM, no una
   variable: propiedad de S3 (dónde corre el prepare) + S4 (H5-5a/5b restore y
   vídeo-antes-de-DCS). S6 no produce ese hunk; solo lo deja derivado aquí.
2. **No** añadir `o82_enable()` para el backlight (puntero S3→S6 resuelto como
   innecesario): el driver no define `enable` a propósito — el core DRM enciende
   el KTZ vía `panel.backlight` (`:745-758`, `UKE-L45`) tras el modeset, que es
   el equivalente exacto del vendor `delay_until_first_frame` (`:13223`) con
   `bl_ctrl_external` (`:13204`). Ya correcto, cero diff.
3. **No** tocar OPP/timings-PHY/byte-clock (R1, G5/G6 inertes, S5), ni vci (S1),
   ni pulso/restore (S2/S4), ni reset/power-TDDI (S3), ni re-probar G4/G5/G6/G7.
4. **No** declarar `vci-supply` aquí (S1) ni la traza `byte_clk` pedida/efectiva
   (S4): PREP (a)/(c) pertenecen a esas secciones.
