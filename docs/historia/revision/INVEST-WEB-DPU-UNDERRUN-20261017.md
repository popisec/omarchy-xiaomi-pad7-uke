# Investigación web: underrun INTF con DSC dual-DSI (7.2-rc2) — 2026-10-17

Verificado en git.kernel.org (tags v7.2-rc2/v7.2, master=7.3-rc7, linux-next 3-oct). Ya en 7.2-rc2: `data_width` por `dce_bytes_per_line` (3bd3d4999f6f), RGB101010 en DSI, `bits_per_pclk`, pclk bonded, fix PLL bonded 93c97bc8d85d. `dpu_hw_dsc_1_2.c` y `dpu_hw_intf.c` no tienen fixes pendientes en linux-next.

## Prioridad

1. **Desactivar slave antes que master** (linux-next, 2-oct-2026, no está en master). En bonded DSI el reset de CTL del master deja el pipe origen atascado a mitad de frame del slave; si MDSS no colapsa (GDSC), el siguiente enable "no escanea nada: negro con backlight" (probado en Legion Y700 gen5, bonded vídeo). Encaja: negro+backlight, underrun cada frame, atasco posterior al SSPP. Probar: cold boot con una sola modeset (sin fbcon→compositor), comprobar `mdss_gdsc` off en pm_genpd_summary, o cherry-pick (10 líneas). https://lore.kernel.org/r/20261002130712.50612-1-26rote@gmail.com . Pengyu Luo (Y700 Gen4, jul-2026): "DPU roto para dual-DSI": https://lkml.iu.edu/2607.3/05379.html

2. **Ancho INTF con 10bpc** (hilo RGB101010, mar-2026, sin cerrar). INTF trunca `width*bpp/(bpc*3)`: 1600·8/30 = 426, DSI redondea arriba = 427 (asumiendo 2 slices×800 B/link). Pengyu: sin round-up, `status=4`; hardcodeó DISPLAY_DATA_HCTL. Comparar bit a bit HSYNC_CTL/DISPLAY_HCTL/DATA_HCTL (data_width=ceil(1600/6)=267). El parche /24 de Koskovich (4/4) no se fusionó; no usarlo. https://lkml.iu.edu/2603.2/12441.html , https://lkml.iu.edu/2603.2/10997.html , https://lore.kernel.org/r/20260322-USUARIO@example.invalid

3. **Ancho de banda / potencia sin respaldo**: (a) linux-next 480ba24a: `bw_ctl=0` en la primera modeset (solo ib) https://lore.kernel.org/r/20261002130656.50577-1-26rote@gmail.com ; (b) master 811c38907eab: `dev_pm_opp_set_rate(0)` deja el clk sin voltaje https://lore.kernel.org/r/20260728-USUARIO@example.invalid ; (c) DTS sm8650: "bandwidth underflows" por paths ICC erróneos https://lkml.rescloud.iu.edu/2410.0/09125.html . Menos probable (danger=0 apunta a atasco posterior al SSPP). Revisar icc_summary y perf-state MMCX a 514 MHz.

4. **slice_per_pkt>1** (ce73a5db44e3, 7.3, ausente en 7.2-rc2; flag `MIPI_DSI_MODE_DSC_ALL_SLICES_IN_PKT`). OnePlus Pad 2 (SM8650, dual-DSI+DSC 120 Hz) funciona con él: https://lkml.iu.edu/2607.3/11161.html . Solo lado DSI; no explica underrun INTF si tus regs DSI = vendor.

5. **Virtual planes por defecto desde 7.1** (b0907ee59e24): A/B con `msm.dpu_use_virtual_planes=0`.

6. **IRQ falso**: catálogos con `intr_underrun/vsync` mal (ce55101e6ba1 x1e80100, 4ce71cea5746 SA8775P). Tu INTF_1/2 deben ser TOP0_INTR 26/27 y 28/29 (como sm8650).

## No aplicar
- Revert 44784327815b (PLL bonded): re-rompe bonded.
- Redondeo byte clock 6cd33b6f4155/2028280686f4: afecta a DSI 6G v2.9; el tuyo es v2.8.
- Quad-pipe DSC+dual-DSI: revertido (da9168d8ef1c).

No hay issue ni hilo con tu síntoma exacto. lore.kernel.org directo da 403; usé espejos lkml.iu.edu, lore.gitlab.freedesktop.org y git.kernel.org.
