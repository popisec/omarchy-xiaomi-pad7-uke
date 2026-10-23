# Recolección DRM/DPU solo lectura — tablet uke, Linux 7.2.0-rc2 (L76R), 2026-10-17

Script remoto usado: `collect-remote.sh` (solo cat/ls/dmesg).

| Fichero | Contenido |
|---|---|
| 00-dri-tree.txt | árbol de debugfs dri (dri/1 = ae01000.display-controller; dri/0 = kgsl-3d0) |
| dri1.txt | state, clients, framebuffer, gem, fb, **kms (devcoredump DPU con volcado de registros, ver aviso)**, mm, encoder-*/crtc-*/DSI-1, core_irq, core_perf/*, danger/*, vbif/*, sspp/*; GPU dri/0 solo listado+clients/gem/mm |
| sysdrm.txt | /sys/class/drm atributos |
| irq.txt | /proc/interrupts completo (filtro mdss/dsi/msm en el informe) |
| clk.txt | clk_summary completo |
| icc.txt | interconnect_summary completo |
| reg.txt | regulator_summary |
| genpd.txt | pm_genpd_summary + ficheros por dominio |
| iommu.txt | iommu_groups (no existe debugfs/iommu*) |
| dmesg.txt, dmesg-drm-dpu-dsi.txt, dmesg-filtrado-errores.txt | dmesg y filtrados |

AVISO: leer `dri/1/kms` (y `state`) dispara en el driver un devcoredump/volcado de registros DPU/DSI (lecturas MMIO hechas por el kernel, no por mí vía devmem). El `cat` de crtc state provocó WARN en dpu_crtc.c:628 (dmesg ~1814 s), inocuo. No se leyó crc/data, hw_log_mask ni se escribió nada.

## Comparación con vendor (build/android/vendor-harvest-20261017b)
| Dato | Linux L76R | Vendor |
|---|---|---|
| mdp_clk / pll0 | 514 MHz / 1542 MHz | 514 / 1542 igual |
| pclk0/1 | 158558398 | 158558666 igual |
| byte / byte_intf | 148648498 / 74324249 | 148648750 / 74324375 igual |
| **esc0/1** | **38.4 MHz** | **19.2 MHz** |
| **vsync_clk** | **38.4 MHz** | **19.2 MHz** |
| **disp_cc_mdss_ahb_clk** | **38.4 MHz** (6 usuarios) | 19.2 MHz |
| gcc_disp_hf_axi | enabled (4 usuarios) | enabled |
| disp_cc_pll1 | 1200 MHz, apagado | 600 MHz, apagado |
| ICC display | llcc y ebi: 0 tag, avg 4257792 / peak 800000 (avg>peak) + 2º voto peak 400000; agregados nodo llcc_mc/ebi = 2151741439 / 2147483647 (saturado) | avg 0 / peak 800000 por mdp; además votos de cfg (qhs_display_cfg 14000) y 2500000; llcc_mc 6.05M/8.37M |
| Sin voto de cfg (qhs_display_cfg) en Linux | no aparece | sí |
| uke_panel_vsp / vsn | 1 uso, 5800 mV | 1 uso, 5800 mV igual |
| avdd/ibb | no listados | avdd 0 uso, ibb 0 (apagados) |
| dsi vdda / phy vdds | ae94/96 dsi-vdda 16 mA, phy-vdds 98 mA, vddil8b 300 mA, vci 2600-3544 mV | equivalentes (1.2 V, 0.9 V, 1.9 V) |
| mdss_gdsc | on, 1 usuario (ae00000, SW) | disp_cc_mdss_core_gdsc 1 uso, modo fast |
| mdss_int2_gdsc | off | normal, 0 |

## Estado DRM Linux
- DSI-1 connected/enabled/On, 3200x2136; crtc-0 mixers 0/1 1600x2136; IRQ [0,26]=108, [0,27]=109, [0,28]=108 (underrun por frame); vblank fps:0 count 108.
- `state`: plane-0 con crtc=(null), fb=0 (sin fb activo en el momento de la lectura).
- danger_status todo 0x0 (MDP y SSPP).
- Todos los grupos IOMMU type=identity (incluye ae01000.display-controller, grupo 17); smmu_sde_unsec/sec_cb aparte.
- Interrupciones: msm-kms 217, dsi_isr 109/109, disp_rsc 0.
