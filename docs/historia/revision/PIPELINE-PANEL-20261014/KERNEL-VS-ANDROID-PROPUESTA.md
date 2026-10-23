# KERNEL-vs-ANDROID: propuesta «nuestra versión» — 14-oct-2026 (solo lectura, 0 flash)

> Base nuestra: `build/kernel-config/k52L64.config` (9473 lín; MEDIDO: L64==L59, L59==L58; L63 revertido en L64) + árbol `build/kernel-pokes/k52-L16-tree` + diffs `PIPELINE-PANEL-20261014/*.diff`. Android: `build/evidencia/android-snap/**` (dt-r15 + dmesg-FULL r15) + `~/gpu-work/**` + hermano `~/proyectos/ubuntu-permanente/docs/`. [M]=MEDIDO fichero:línea · [H]=HIPÓTESIS.

## 1. Inventario por subsistema (gap real + ¿importa para el hito?)

| Subsistema | Android (driver/config/parche) | Nuestro (estado + config) | Gap real | ¿Importa hito actual? |
|---|---|---|---|---|
| Display DRM/DSI/DPU | msm_drm downstream: cont-splash (salta prepare con splash), DCS en LP, vídeo-engine AL FINAL, 108 cmds `dt=0x39` [M] (`docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-PANTALLA-COMPLETA.md:24-42,54-62`) | `DRM_MSM(+DPU/DSI/KMS)=y`, panel `panel-xiaomi-o82-dualdsi.c` propio, commit OK 184× pero negro-con-luz [M] (`docs/historia/revision/PIPELINE-PANEL-20261014/COMPARATIVA-PANTALLA-A-VS-UK.md:13`) | Transporte (HS vs LP), orden PPS, motor vídeo, clocks lane | SÍ — es el hito (pantalla negra L59→) |
| DSC/PPS | PPS calculada post-0x29, con splash NI SE ENVÍA (IC preconfigurado cmds #100-103 `0x90/91/92/9D`) [M] (`docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-PANTALLA-COMPLETA.md:41-42`) | L59 envía PPS en prepare pre-0x11 (dims L62 1600×2136 OK, RC sde-vs-DRM sin cotejar [H]) [M] (`COMPARATIVA…:12`) | Orden + necesidad real incierta | SÍ — test L63 decide la rama entera |
| GPU/Adreno 732 | ADSP/GMU FW vendor, UBWC cliffs | `lamma.dtsi` OPP 255-950 + `gmu-732` de serie, sin parches kernel [M] (`xiaomi-uke.dts:542-544`); freedreno OK (FD735+GLES, L19) | Ninguno kernel; mesa userspace aparte | NO (ya funciona) |
| Carga battmgr/glink/ucsi/PD | ADSP+PDR+charger_pd `0x1fffffff`, battmgr dialecto Xiaomi [M] (hermano `#406:4021`) | `BATTMGR/GLINK/UCSI=m` en L64 [M] (`diff L63→L64`); `=y` wedgea (L60, L63) [M] (`docs/historia/revision/PIPELINE-PANEL-20261014/CARGA-HERMANO-VS-NUESTRA.md:7`) | `=m` no viaja (build 0 `.ko`) + guard con ventana + sin parche 0x50 + sin rename | SÍ — sin esto no hay sysfs de batería |
| USB dwc3/gadget | gadget ACM+NCM+rndis | `DWC3(+QCOM/DUAL_ROLE)=y`, `F_NCM/F_RNDIS/CONFIGFS_ACM=y` [M] (L64) | Ninguno — gadget enumera (SSH vivo L57) | NO |
| Clocks/OPP/parked | Siembra 514 MHz en probe+enable sin `set_rate`; byte 148648750; PHY `strength 0xff/voltage 0x51`/timings [M] (`ANDROID-PANTALLA…:76-89`) | OPP 514 MHz en `dpu_kms_init` (parked, arquitectura OK) pero byte 118918800 + PHY defaults 4nm [M] (`COMPARATIVA…:10`) | Valores PHY/byte, no arquitectura | Parcial (sosp. 3-4, tras PPS) |
| SMMU/IOMMU | SIDs del BL vivos (splash), stream del display PINado bajo | FIX-A1b quirúrgico (reclaim idx2, sin wmask global) RESOLVIÓ la muerte del commit [M] (`docs/historia/ESTADO-VIVO.md:77-84`, `fix-smmu.diff`) | Cerrado; queda endurecer guard si se toca glink | NO (no reabrir) |
| KTZ/backlight | DUAL KTZ8866 (se0+se12), 1er write 10.85 s tras 1ª trama+300 ms, DCS 0x51 NO usado [M] (`ANDROID-PANTALLA…:110-118`) | `BACKLIGHT_KTZ8866=y`, UN KTZ, luz OK + PWM_EN=0 en probe (L56) [M] (`docs/historia/ESTADO-VIVO.md:45-53`) | Dual innecesario; vci ausente (ver abajo) | NO (luz cerrada) |
| vci/L19 rail | `vci`=L19 2.6 V (init, hasta 3.544 V) [M] (`ANDROID-PANTALLA…:90-92`) | Sin `vci-supply` en DT, driver sin soporte [M] (`COMPARATIVA…:16`) | `docs/historia/revision/PIPELINE-PANEL-20261014/s1-vci.diff` listo, sin flashear | SÍ (P0 fase DCS, tras L63) |
| Input touch/lápiz | `goodix-berlin@0` SPI + `xiaomi_touch` [M] (dt-r15) | `GOODIX(+BERLIN_CORE/SPI)=m`, `NT36XXX_SPI=y`, `HX83112B=m`, `HID_MULTITOUCH=m`, `HID_WACOM=n` [M] (L64) | Falta probar en vivo (pendiente L57); lápiz sin WACOM | Tras pantalla (no ahora) |
| Audio | WCD939x + WSA, SoundWire, sin `request_firmware` DSI [M] | `WCD939X(+SDW)/WSA88xx=m` presentes [M] (L64) | Ninguno bloqueante | NO |
| WiFi/BT | WCN (ath11k), BT QCA | `ATH11K(+AHB/PCI)=m`, `BT_QCA/HCIUART_QCA=m` [M] (L64); frags wifi wedgean #601 | GENI+FW despliegue, no kernel | NO (consolidación posterior) |
| Thermal/sensores | TSENS/SPMI | `QCOM_TSENS=y`, `SPMI_TEMP_ALARM=y`, `SPMI_ADC_TM5=m` [M] | Ninguno | NO |

## 2. Parches que Android/hermano tienen y nosotros no (y al revés)

- Hermano SÍ / nosotros NO: (a) battmgr dialecto **0x50 + ack 0x13** (`ESTADO-ACTUAL.md:206-207,313`); (b) rename dtbo `_log`→`qcom,pmic-glink-log` + `gpr disabled` (`CARGA-HERMANO…:8`); (c) FW 49 segs `ramaa/s24/adsp-fw/` como `*.b??` [M] (`CARGA-HERMANO…:10`). (d) `pd_mapper` cliffs: el hermano lo parcheó, **el nuestro YA lo trae** (`qcom_pd_mapper.c:605-606`) — no portar.
- Nosotros SÍ / vendor-hermano NO: FIX-A1b SMMU reclaim (muerte commit resuelta), KTZ PWM_EN=0 en probe (luz cada arranque), PPS dual-link L59/L62, `zram=y+lz4` (L58), guard pmic-glink `pmic_glink.c:305-317` (con ventana check-then-act sin cerrar — ver §3c).
- Vendor SÍ / nadie lo porta (correcto no portar): cont-splash/saltar-prepare, `sde_dsc_create_pps_buf_cmd` runtime, `battery_charger`/`charger_partition` downstream (`CARGA-KERNEL.md:39-42`).

## 3. LA PROPUESTA «nuestra versión» (próximo kernel consolidado)

**(a) Configs `=y` (lección: los `=m` in-tree NO viajan — build da 0 `.ko`; `CARGA-KERNEL.md:74-82`):**
`BATTERY_QCOM_BATTMGR=y`, `QCOM_PMIC_GLINK=y`, `UCSI_PMIC_GLINK=y` (los 3 a la vez son el wedge L60/L63 — por eso van con §c y orden §e). Ya `=y` y se quedan: `ZRAM/ZSMALLOC`, `KTZ8866`, `QRTR_SMD/PD_MAPPER`, `DWC3/GADGET/NCM`, `GENI I2C/SPI`, `TSENS`. NO tocar: `ATH11K/BT_QCA/WCD939X/HID_MULTITOUCH=m` (módulos futuros por insmod, no builtin).

**(b) Parches a portar (fuente):** 1. battmgr dialecto 0x50+0x13 del hermano (`ramaa/s24/qcom_battmgr.ko`, `BATTMGR-DIALECTO.md`). 2. Guard pmic-glink endurecido (asignar `__pmic_glink` ANTES de crear aux + sufijar aux por nodo; cierra ventana `pmic_glink.c:312-317/343-371`). 3. Display según ranking: `docs/historia/revision/PIPELINE-PANEL-20261014/l63-pps-post.diff` (PPS post-0x29) → `docs/historia/revision/PIPELINE-PANEL-20261014/s6-noncontinuous.diff` (quitar NON_CONTINUOUS) → S4 motor (FLUSH/HS_TIMER/clear-before-unmask, `ENABLE-COMPARISON` 1a-1c). 4. Cotejo offline RC PPS sde-vs-DRM (`drm_dsc_helper.c:316-390`) antes de más flashes PPS.

**(c) Fixes DT:** 1. `docs/historia/revision/PIPELINE-PANEL-20261014/s1-vci.diff` (`vci-supply=<&L19B>` al panel). 2. Rename `_log`→`qcom,pmic-glink-log` + revisar 3er nodo propio (`xiaomi-uke.dts:89-92`) contra los DOS vendor (`CARGA-HERMANO…:8`). 3. `s6-ktz-undup` (quitar se12 fantasma) + `docs/historia/revision/PIPELINE-PANEL-20261014/s2-g8.diff`. 4. NO `gpr disabled` sin medir (era del hermano Ubuntu, no del nuestro).

**(d) Display según ranking (`COMPARATIVA…:18-23`):** nº1 DCS-HS-con-vídeo-ON (test F-b VID-tras-DCS / F-c sin BLOCK_DMA / F-a DCS-en-LP) → nº3 non-continuous/LP11 → nº4 motor. L63 primero: PASA=contenido; FALLA (`UKE-L63 err=0` negro+luz)=rama PPS CERRADA, pasar a nº1/3 sin más flashes PPS.

**(e) Qué NO incluir y por qué:** wifi/BT (frags wedgean #601; va por GENI+FW en userspace, no quema retries), audio/sensores (presentes `=m`, no bloquean hito), DCS 0x51 interno (L55 revertido; vendor usa KTZ), `ZSWAP/ZBUD/BTF` (veredicto `KERNEL-CONSOLIDADO.md:43-44`), segundo KTZ se12 (fantasma).

## 4. Orden de ciclos (1 cambio/ciclo), riesgos, verificación

1. `L63` PPS post-0x29 (1 flash; rollback L62). 2. `s1-vci` (1 flash; verifica `L19 use 1/1`, DCS 0x51 llega). 3. NON_CONTINUOUS o VID-tras-DCS (1 flash; PASA=firma `status=4/5` se mueve). 4. Motor S4 por tabla S4-DIAG (instrumento antes). 5. Carga: rename dtbo s288 (0 kernel) → insmod en vivo glink→battmgr (0 flash, `CARGA-HERMANO…:28`) → solo entonces `=y` triple. Riesgos: slot retries (≤2 escrituras/día, batería ≥3700 mV, ACM único + doble captura, sha pre-registrado). Verificación por ciclo: `UKE-L63 err`, `dsc=85 85`, `ls /sys/class/power_supply` + PDR `0x1fffffff` + `Charging/current_now>0`, `MemTotal`, captura grim.
