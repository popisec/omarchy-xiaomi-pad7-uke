# INVEST-WEB Pad 5 / Pad 6 / NT36532 (17-oct-2026, solo lectura web)

**Conclusión**: nabu y elish NO usan DSC (no son precedente). Los precedentes útiles son el propio uke (MCC45TR) y pipa/liuqin/OnePlus Pad 2 (NT36532+DSC).

## 1. Mismo equipo (uke, O82 42_02_0b) ya con imagen nativa
github.com/MCC45TR/senemos-uke-kernel-mainline (Linux 7.2.9): KDE por DPU/DSI 3200x2136, 30-144 Hz, 17-oct (builds .4050/.4054). Tras ~50 pruebas "negro con luz"; lo último fue el parche 0032, sin causa única probada. Ver `src/display/README.md` y `patches/display/0003-0034`. Lo que tienen y tú no (verificar):
- **ICC y votos reales**: rutas qnm_mdp→qns_mem_noc_hf→qnm_mnoc_hf→llcc/cnoc + qhs_display_cfg (`cliffs-display-icc.h`), DT `interconnects=<&mmss_noc 21 &mc_virt 512>,<&gem_noc 2 &cnoc_cfg 524>`; votos vdd_mm/vdd_mxa en DISPCC con tablas OEM (`uke-dispcc-votes.c`); RPMh `mmcx.lvl` y `ldob8` (0003). Con eso no vieron underrun (native29). Tu underrun por frame encaja con L78.
- **PHY**: timing OEM de 14 bytes (0010), strength 0xff/cal_sel 1 (0013), host pre/post 0/0 (0016), 7 regs FLL antes del PLL (0018), toggle retime FIFO + CLK_EN_SEL bit4 tras ambos relojes (0014).
- **Orden**: ON+PPS en LP antes del vídeo; tras el 1er vblank 4 cmds HS TP-FPS, backlight, LP normal/dimming (0031); broadcast DMA escalonado slave1→master0 (0019); CTL único (0020); solo el maestro arranca timing (0015); no reprogramar el PLL vivo en cada transferencia (0027/0030; cf. mainline 6cd33b6f4155).
- 0032 (reescribir bias PLL) NO es diferencia: tu rc2 ya incluye 93c97bc8; 7.2.9 lo tiene revertido (44784327815b).

## 2. Pad 6 (pipa, SM8250) y Pad 6 Pro (liuqin, SM8475)
NT36532, DSC 1.1 8bpc→8bpp, slices 450x20, D-PHY 4 lanes, bonded, DSI0 maestro, DSI1 con relojes de PHY0. Parches: Marek "fix video mode DSC" github.com/pipa-mainline/linux/commit/c37efde734 y "WC video DSC" /3ac57068c5 (ya en rc2); "dual-DSC hacks" /0e05d76a46 (initial_lines=3, num_intf=2); driver /b5f85429f7. Usan `dsc_slice_per_pkt=2` (mainline ce73a5db44e3, solo v7.3-rc1), pero tu REGDIFF O82 (WC=800, 2 pkt/línea) implica 1: descartado.
"Negro con luz" resueltos: reset GPIO ACTIVE_HIGH (polaridad invertida deja nRESET activo con DSI "OK") y timings completos en bonded (liuqin: github.com/yzddmr6/linux-sm8450-liuqin, `sm8475-xiaomi-liuqin.dts`).
Táctil TDDI: no hace falta para imagen; el reset del panel borra su firmware RAM y debe recargarse (mismo DT).

## 3. nabu / elish (NT36523)
Sin DSC, 1600x2560@120 RGB888, C-PHY 3 lanes, VIDEO|NON_CONTINUOUS|LPM, dual-dsi-mode+sync-dual-dsi+master-dsi en DSI0.
gitlab.com/sm8150-mainline/linux (sm8150/6.17, `sm8150-xiaomi-nabu.dts`); mainline v7.3-rc2 `sm8250-xiaomi-elish-common.dtsi`.

## 4. OnePlus Pad 2 (NT36532 CSOT, DSC 1.2, 3000x2120@120 bonded)
lkml.iu.edu/2607.3/11161.html (v2, jul-2026): DCS por el 2º enlace; `0x90 0x03`, PPS, `0x9d 0x01`; imagen estable.
