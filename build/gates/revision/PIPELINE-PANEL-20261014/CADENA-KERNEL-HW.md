# CADENA-KERNEL-HW — dónde mueren los píxeles (14-oct-2026, solo lectura + `dmesg`/debugfs)

> Boot vivo: L57 (`7.2.0-rc2-palawan`, árbol `k52-L16-tree`), 184 commits, 0 faults display, luz OK.
> **MEDIDO** = visto en log/código/sysfs hoy. **HIPÓTESIS** = marcado.

## 1. Diff DT estático: stock vs nuestro (MEDIDO)

Stock: `~/gpu-work/ramaa/s7/dtbo-stock-decomp.dts:13194` (`o82_42_02_0b`, timing@120).
Nuestro: `fase4-display.dts:347` (nodo sin timings) + `k52-L16-tree/.../panel-xiaomi-o82-dualdsi.c`.
**Idénticos**: resolución 1600×2136/link (3200 total), hfp 113 / hbp 16 / hsync 16,
vfp 26 / vbp 146 / vsync 2, 120 Hz; DSC 1.1, 8 bpp, 10 bpc, slice 800×24,
1 slice/pkt, block-pred, 2 slices; reset 0/10 ms-1/3 ms-0/3 ms-1/15 ms
(nuestro GPIO ACTIVE_LOW lo reproduce físico idéntico; L38 puso los 15 ms);
init 104 cmds verbatim + `b3=0x40 b2=0x91` (120 Hz) + `0x11` +120 ms + `0x29`.
**Sin contraparte nuestra** (usamos defaults mainline): `phy-voltage 0x51`,
`clk-strength 0xff`, `phy-timings 00 27 0a…0f`, `broadcast-mode` /
`cmd-sync-wait-broadcast` (nosotros dual-write por link), `bllp-power-mode` +
`bllp-eof-power-mode`, `rx-eot-ignore` / `tx-eot-append`, `mdp-trigger none` /
`dma-trigger trigger_sw`, `clockrate 0x46e19970` (nuestra OPP: 187/300/358 MHz,
otro dominio — no comparable directo). `mode_flags` nuestro añade
`CLOCK_NON_CONTINUOUS` (K48-A: forzamos bitclk continuo desde power_on;
vendor = LP11 en reset). Nada de esto explica negro-con-sync-OK por sí solo.

## 2. Qué verifican los pokes y el hueco (MEDIDO en código)

K47 (27 en `k52L39-tree`, lista completa en informe): entradas de función
(`pan-probe/prep/modes`, `phy-en/pll-prep/7nm-en`, `host-en/pwr/xfer`,
`mgr-mset/enc-mset/enc-help/crtc-en/vid-en`, `pre-rst/pre-init/pan-dcs`,
`atom-tail`). K50 (12, `l50-instrument.diff`): subdivide DSI_1
(`prep0/1-before/after`, `clk-en/rate`, `mgr-enter/ctrl-ok/commit`,
`dma-base=IOVA`, `trig-done`, `vid-ok`). **Verifican triggers y el IOVA del
cmd-DMA, NUNCA contenido**: nadie comprueba fetch del scanout, ni CRC del
frame, ni qué sale del codificador DSC, ni ACK del DDIC. Hueco total entre
`K50-trig-done` y los fotorreceptores del dueño.

## 3. Fetch del scanout / SMMU (MEDIDO en vivo — sin `modetest`, innecesario)

`uke_disp_reclaim` (FIX-A1b) cubre **un solo SID `0x1c00/mask 0x2`** (SMR idx2
+ CB69, `dmesg: FIX-A1b` ×5: reclaim + force SME/S2CR/CB). Es el único mapeo
display ⇒ **cubre cmd-DMA Y planos MDP a la vez** (mismo stream). Prueba viva
de que el fetch de planos funciona: `debugfs dri/1/crtc-0` muestra plano real
`fb:96 XR24 3200×2136`, 2 mixers ×1600, `core_clk 931 MHz`; **184
`K47-atom-tail`, 0 faults** (`grep fault` solo trae el oops OOT de las 8.39 s,
ya documentado como no fatal, y los handler-install K39); 0 underruns, 0
`video done timed out`. El `prepare` completa 2× (`freq_sel/sleep-out/
display-on err=0`, t=117/222 s). **Plano→MDP verificado por uso; el modetest
destructivo sobra** (pintaría patrón sobre el escritorio del dueño).

## 4. DSC: host SÍ comprime, panel SIN PPS — SMOKING GUN (MEDIDO)

Resource-map vivo (`dri/1/state`): **`dsc=85 85` asignado al crtc** = los dos
codificadores DSC activos. Pero el kernel flasheado **nunca envía la PPS**:
`dmesg | grep -c UKE-L37` = **0**, y `k52-L16-tree/.../panel-…:587` conserva
*"No picture parameter set is sent"* (`grep picture_parameter_set` = 0 en ese
árbol; el hunk L37 solo existe en `k52L39-tree:386-411`). Stream DSC sin PPS ⇒
el DDIC no puede decodificar ⇒ **negro con sync OK, exactamente lo observado**.
(HIPÓTESIS secundaria si la PPS se añade: el propio comentario L37 advierte que
`pic_width/height` salen del template = 0 a prepare-time; verificar bytes.)

## 5. Handshake vendor (MEDIDO en driver)

`0xfb` = **page-select**, no display-on: aparece como `ff XX … fb 01` en el
array (`k52L39-tree:100-169`); el display-on real es `0x29` (enviado, err=0).
`delay_until_first_frame` equivale a nuestro KTZ-enable en
`drm_panel_enable()` post-modeset (driver:43,453) — y **la luz funciona**,
luego esa pata está cerrada.

## 6. Modo actual (MEDIDO)

`modetest -M msm-kms -c`: `#0 3200x2136 120 Hz preferred`
(3426/3458/3490, v 2162/2164/2310 = 2×113, 2×16, 26/2/146 exactos vendor).
Modo nativo correcto, nada "raro".

## Ranking: dónde mueren los píxeles

1. **DDIC sin PPS (host DSC on, panel sin params)** — test: L58 = portar hunk
   L37 a `k52-L16-tree` (+ `pic_width=1600` por link verificado) y mirar luz
   con contenido; `grep UKE-L37` debe dar 2 envíos.
2. **Clock continuo vs LP11 del vendor en reset** (K48-A) — test: quitar
   `CLOCK_NON_CONTINUOUS` un ciclo (barato, mismo L58 si el dueño acepta
   2 vars; si no, L59).
3. **PHY timings/voltage vendor vs defaults mainline** — test: solo si 1–2
   fallan; requiere tallar el PHY 4nm (caro).
4. **Fetch MDP/SMMU — DESCARTADO** (184 commits sin faults, plano real).
5. **Backlight/sync — DESCARTADO** (luz + `modetest` commitea + modo nativo).
