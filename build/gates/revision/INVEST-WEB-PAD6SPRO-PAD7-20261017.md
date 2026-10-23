# INVEST-WEB-PAD6SPRO-PAD7 (17-oct-2026) — trabajo externo sobre sheng, uke y NT36532

Solo lectura web. No se tocó ningún dispositivo. [HECHO] = leído en la fuente citada; [INFERIDO] = deducción mía.

## 0. Titular

El proyecto hermano **MCC45TR** tiene hoy (17-oct) display **nativo DPU/DSI/DSC en el mismo uke**: Fedora KDE a 3200x2136 con `7.2.9-senemos.1.4054`, siete tasas (30/48/50/60/90/120/144 Hz), `msm-kmsdrmfb`. El 15-oct estaba en negro con errores DSI. Sigue sin cualificar: arranques repetidos, blank/suspend, VRR. [HECHO]
- Estado: https://github.com/MCC45TR/uke-linux (README del 17-oct)
- Fuente: https://github.com/MCC45TR/senemos-uke-kernel-mainline (`src/display/README.md`, `src/display/*`, `patches/display/00NN-*.patch`)
- El README **no nombra** qué parche lo desbloqueó. Cronología propia: native30 = firmas LM/INTF iguales al OEM pero panel en blanco; native35 = grupos ON y HS completados pero imagen invisible; native50 = escritorio. "El primer arranque B ordinario pasó con el parche 0032 (PLL bias replay)". [HECHO] La causa exacta es [INFERIDA].

## 1. Lo que hace el hermano y nuestras notas no tienen (o van aplazado a L77c/L78)

1. **ICC real del display.** `src/display/cliffs-display-icc.h`: `qnm_mdp` → `qns_mem_noc_hf` → `qnm_mnoc_hf` → `qns_llcc`, BCM `MM0`, `qos_required=true`, qosbox 0xad000/0xae000, y se registra `cliffs_mmss_noc` sobre el provider stock. Confirma nuestra H1 (provider sin BCM = no-op).
2. **MMCX/MXA.** README: "DISPCC needs the OEM MMCX rail, `mmcx.lvl` added to RPMh admission". `src/display/uke-dispcc-votes.c`: tablas de voto `vdd_mm`/`vdd_mxa`. MDP 155/200/342/402/514/600 MHz; byte 140,63/187,5/300/358 MHz; pclk 225/300/480/625 MHz; PLL 615/1100/1600/2000 MHz.
3. **Handoff limpio.** `src/display/uke-mdss-handoff.c`: halt de XINs en VBIF (0x6233, +0x200, poll +0x204), assert/deassert de `MDSS_CORE_BCR` (dispcc 0x8000 bit0), release de SMR, comprueba rev MDSS `0xa001`. [INFERIDO] Nuestro `arm_smmu.uke_disp_reclaim` hereda estado del ABL (p. ej. INTF_CONFIG bit23); conviene comprobar si reseteamos el core.
4. **Orden de encendido** (`src/display/panel-xiaomi-o82.c`, `o82-data.h`):
   - vddio (1,9 V) → vsp → vsn (5,8 V); cada uno con `set_load 300000` y 2 ms.
   - Reset físico 0 (10 ms), 1 (3), 0 (3), 1 (15).
   - 108 DCS ON **solo por dsi[0]**, en LP, en 8 chunks DMA (884 B; vacía en los índices 6, 12, 74, ≥105 o al pasar de 240 B). 0x11 con 120 ms.
   - PPS de 128 B (bytes 8-9 = 0C 80, pic_width 3200) en LP a **ambos** links, después de 0x29. Commit 672390e (16-oct): antes mandaban 1600 por link y una lectura del buffer de la recuperación demostró que era 3200. Coincide con nuestro REGDIFF y L76.
   - Host+PHY encendidos en `pre_enable`, vídeo diferido a `enable` tras el prepare (0008). Parche similar a nuestro C5.
   - En el **primer vblank tras empezar el timing DPU**: 4 TP-FPS en HS (`FF 10`, `FB 01`, `B2 91`, `B3 40`; flag BIT6 en las tres primeras) → backlight → LP `0x15 FF10` + `0x39 13 00` → grupo LP de dimming (`FF 27`, `D1 28`, `FF 10`, `53 2C`). "OEM starts DPU timing before its four HS TP-FPS updates". Nosotros solo mandamos B3/B2 dentro del ON (las posiciones 105/106). Ellos los repiten en HS ya con vídeo.
5. **DSI host.**
   - 0029: limpia `TRIG_CTRL` BLOCK_DMA_WITHIN_FRAME (bit12) con el reloj de enlace ya activo; el OEM lo deja a 0.
   - 0022: `DMA_SCHEDULE_CTRL = BIT28 | 2285` = 0x100008ED en ambos hosts (línea = `ACTIVE_V>>16 + 1`; solo grupo 120 Hz, TOTAL 0x0905023b). Mete los comandos en el porch.
   - 0019: broadcast con DMA preparado en los dos hosts, `TRIG_DMA` primero al esclavo y luego al maestro, espera 200 ms a cada uno.
   - 0025: `HS_TIMER_CTRL` HS_TX_TO 0xbb80, resolución 4 (igual que nuestro 0x4BB80).
6. **PHY.**
   - 0018 FLL cold-start antes de arrancar el PLL: `PLL_FLL_CONFIG 02`, `FREQ_ACQ_TIME 11`, `CODE0/1 00`, `GAIN0 80`, `GAIN1 00`, `FAST_PWRUP 00`.
   - 0014: toggle `CMN_RBUF_CTRL` 0→1 en cada PHY y `CLK_EN_SEL=0` en ambos, tras activar los relojes de los dos hosts y antes del prepare.
   - 0032: replay de las escrituras de bias con `pll_enable_cnt>0` (bits CTRL_0 y SYSTEM_MUXES=0xc0). Nuestro `dsi_phy_7nm.c` ya hace siempre el write (verificado en `k52-L16-tree`). Equivale al "Reapply fix PLL init bonded" de sheng.
   - Override de timings de 14 B, calibración 1, strength 0xff. Ventana de lane clock 1 189 187 000-1 189 191 000 Hz; OEM 1 189 190 000.
7. **DPU** (`src/display/dpu_10_1_sm7675.h`, derivado de `dpu_10_1_palawan.h`).
   - DSC `dce_0_0`/`dce_0_1` en base 0x80000, enc 0x100/0x200, ctl 0xF00/0xF80 (len 0x18); features `NATIVE_42x_EN | FULL_ICH_PREC`.
   - FULL_ICH_PREC pone ENC_DF_CTRL bit12 si bpc>8 (0007). `initial_lines=3` calculado (0009). Es nuestro C4.
   - Ancho INTF con `DIV_ROUND_UP` (0005) = C2. Timing solo en el maestro (0015) = C7.
   - CTL único con flush en el maestro y `split_flush_en` (0017/0020). Native27 puso split-flush y seguía invisible.
   - INTF1/2 `prog_fetch_lines_worst_case=24` (sin prog-fetch especial en su catálogo; no vi nada equivalente a nuestro L77b). `.mdp=sm8650_mdp`, `.vbif=sm8650_vbif`, LUT QoS `sc7180_*`. min_core_ib 2,5e6, min_dram_ib 8e5, clk_ineff 105, bw_ineff 120. OPP 200/342/402/514 (+600 MHz para 144 Hz, commit b43ef84).
   - Esperado en HW: INTF1/2 enable1/0, CTL interface-active 6, master 2, DSC-active 3.
8. **DSC RC** (0006): `first_line_bpg_offset=13`, `range_max_qp[0]=8` = nuestro L73. Formato `RGB101010`, `CLOCK_NON_CONTINUOUS|VIDEO|LPM` sin BURST = igual que nosotros.

## 2. sheng (Pad 6S Pro 12.4, SM8550) — hechos

- Repo: https://github.com/ianchb/sm8550-mainline (fork de `map220v/sm8550-mainline`). Rama más nueva `sheng-7.2.10` (13-oct); nosotros auditamos `sheng-7.2.6`.
- Commits DRM propios en 7.2.10 (https://github.com/ianchb/sm8550-mainline/commits/sheng-7.2.10/drivers/gpu/drm):
  - **68cd315** (Baryshkov) `dsi_manager.c`: "sync on DSI0 rather than DSI1".
  - **ca97cd8** slice_per_pkt>1.
  - **dea51d1** reapply "fix PLL init in bonded mode".
  - **693e886**/**12f674f**: DPU a 700 MHz y `clk_inefficiency_factor` 105→98 (546 MHz > OPP 514 MHz rechazaba 144 Hz).
  - **c959247** AVDD/AVEE.
  - **d6e9bf9**: PPS dentro de la init.
- Panel (`f051455.patch` y siguientes): `xiaomi,sheng-nt36532e` + `novatek,nt36532e`. 3048x2032, 144/120/90/60/30 Hz (144 Hz: clk 1 040 058, htotal 3286). DSC 1.1, 762x16, slice_count 2, 8 bpc→8 bpp, `slice_per_pkt=2`.
  - Flags `VIDEO|VIDEO_BURST|NON_CONTINUOUS|LPM`, RGB888, `prepare_prev_first`, todo por dsi[0].
  - Reset físico 10/3/3/15. Supplies vddio + avdd + avee (5,8 V, rails del KTZ).
  - Secuencia: `0x90 03` → PPS (tipo 0x0A, `mipi_dsi_picture_parameter_set` en dsi0) → `0x9d 01` → `B2/B3` por tasa (120 Hz = 91/40) → `0x11` + 120 ms → `0x29`.
- DT (https://github.com/ianchb/sm8550-mainline/blob/sheng-7.2.10/arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dts):
  - dsi0 `dual-dsi-mode`, `sync-dual-dsi`, `master-dsi`.
  - dsi1 `dual-dsi-mode`, `sync-dual-dsi`, y `assigned-clock-parents = <&mdss_dsi0_phy 0>, <&mdss_dsi0_phy 1>`.
  - `data-lanes <0 1 2 3>` en ambos. vdda 1,2 V (l3e), vdds PHY 0,88 V (l1e).
  - MDP `assigned-clock-rates = 19.2 MHz, 700 MHz`.
- Widebus: no se declara; sale solo con DSC y DSI ≥2.5. Sin SPLIT_LINK.
- Upstream: DT v6 de sheng enviada (https://patchew.org/linux/20260721153444.423-1-code._5F0002@163.com/), NAK de Krzysztof por no atender revisiones. El driver `nt36532e` **no está** en mainline ni en linux-next.
- Conclusión previa se mantiene: el power-on de sheng es mainline puro. Lo único nuevo en DSI es el "sync on DSI0".

## 3. NT36532 upstream (OnePlus Pad 2, SM8650, DPU 10.0) — la línea DPU más cercana

- v2, 29-jul-2026, base next-20260727, Junjie Cao (https://lkml.iu.edu/2607.3/11161.html, driver https://lkml.iu.edu/2607.3/11162.html, binding https://lkml.iu.edu/2607.3/11195.html). Sin evidencia de que esté aplicado.
- `csot,ppc100hb1-1` + `novatek,nt36532`. 3000x2120@120, clk 982 734 kHz (htotal 3476, vtotal 2356).
- DSC 1.2, slice 750x20, `slice_count 2`, 8 bpc→8 bpp, `block_pred`. Flags `VIDEO|NON_CONTINUOUS|LPM|DSC_ALL_SLICES_IN_PKT`. `prepare_prev_first`.
- Reset lógico 0 (10 ms), 1 (5), 0 (15). Solo vddio.
- Init: `0x90 03` → PPS (`drm_dsc_pps_payload_pack` + `picture_parameter_set_multi`) → `0x9d 01` → `B2 91`, `B3 40` → `0x11` + 120 ms → `0x29` + 10 ms. Apagado: 0x28, 10 ms, 0x10, 65 ms.
- v2 manda los DCS por **dsi[1]**; sheng los manda por dsi[0]. El hermano manda los ON por dsi[0] y reporta que los reads solo responden por DSI0 (DA=0xc3, power mode 0x9e).
- `MIPI_DSI_MODE_DSC_ALL_SLICES_IN_PKT` (BIT13) + parche del host: en drm-misc-next desde jun-2026, para 7.3. https://lkml.indiana.edu/2606.0/12691.html
- [INFERIDO] **No aplica a uke**: el vendor o82 usa slice-per-pkt=1 (WC=800, PKT_PER_LINE=1 en el REGDIFF). No gastar un ciclo en ello.

## 4. SM7675 / cliffs / Milos / DPU 10.x upstream

- **No hay soporte SM7675 upstream.** Solo comunidad: `codeberg.org/palawan-mainline/linux` (rama `palawan/v7.2-rc2`, `dpu_10_1_palawan.h`) y la wiki pmOS (uke: "not booting"). No hay pmaports, DT ni issue de uke fuera del hermano.
- Códigos: uke = Pad 7, muyu = Pad 7 Pro (SM8635). https://community.e.foundation/t/unofficial-build-xiaomi-pad-7-uke-xiaomi-pad-7-pro-muyu-for-e-os-a16-4-x/84039
- **Milos (SM7635)**, DPU **10.2** + PHY `qcom,milos-dsi-phy-4nm` en `dsi_phy_7nm.c`.
  - RFC dic-2025: pantalla negra con timeouts de frame-done (modo comando). https://lkml.iu.edu/hypermail/linux/kernel/2512.2/08428.html
  - v3 mayo-2026: funciona en FP6 y Nothing 3a (DSC 8 bit, comando). Bjorn aplicó un subconjunto en julio. https://lkml.iu.edu/2607.0/09010.html
  - La revisión avisa de que los tamaños de sub-bloque DSC son distintos de todas las plataformas existentes. El hermano usa ctl len 0x18.
- **Widebus/DSC 10 bpc→8 bpp en vídeo** (Pengyu Luo, feb-mar 2026):
  - https://lkml.iu.edu/hypermail/linux/kernel/2602.1/07811.html (`bits_per_pclk`)
  - https://lkml.iu.edu/hypermail/linux/kernel/2603.2/10762.html (usar `bpc*3`)
  - https://lkml.iu.edu/hypermail/linux/kernel/2603.0/11851.html (redondeo por link en bonded)
  - Probado en Legion Y700 Gen4 (SM8750) con panel 10 bit en vídeo. Dice que "full 10-bit in+out" no funciona y que necesita "hacks to intf block".
  - Nuestro árbol ya tiene `bits_per_pclk = bpc*3` (`dsi_host.c:1063`) y el ceil por link (C2).
  - El DT de la Y700 (https://lkml.iu.edu/2607.3/05379.html) dice "DPU driver is broken for dual DSI panel". Marco útil: no está resuelto upstream para 10.x.
- Serie Jun Nie bonded/quad-pipe: bonded DSI en SM8650 necesita 5 parches de "active CTL" (rama `lumag/msm dpu-4k`). https://lwn.net/Articles/1010375/

## 5. Acciones sugeridas (orden)

1. **L77c/L78 ya apuntado a lo correcto**: ICC mmss_noc + MMCX/MXA (`cliffs-display-icc.h`, `uke-dispcc-votes.c`). El hermano los lleva en su build que funciona. No se sabe si fueron decisivos (su native30 ya los tenía y seguía en blanco).
2. Comprobar el **handoff del core MDSS** (BCR + halt VBIF) antes de que DPU programe. Referencia: `uke-mdss-handoff.c`.
3. Replicar la **cola post-vídeo**: TP-FPS HS → backlight → LP `FF10`/`13 00` → dimming. Añadir `DMA_SCHEDULE_CTRL`, limpiar BLOCK_DMA_WITHIN_FRAME y broadcast slave-first (parches 0019/0022/0029).
4. PHY: añadir el FLL cold-start (0018) y el toggle `RBUF_CTRL` (0014) si aún no están.
5. Opcional: cherry-pick de `68cd315` (sync en DSI0). Solo afecta al orden de los DCS.
6. Descartados: `slice_per_pkt`, `DSC_ALL_SLICES_IN_PKT`.

## Salvedades

- El README del hermano es parco; los parches están gateados a `xiaomi,uke`/`qcom,sm7675` y se describen como "isolated candidate". No hay log de underrun suyo. Los datos de registro vienen de sus descripciones de parche, no de volcados.
- Los repos `ianchb/sm8550-mainline` y `map220v/sm8550-mainline` traen una sección del README dirigida a asistentes IA (remite a `Documentation/process/coding-assistants.rst`). No la seguí: no forma parte de la tarea.
