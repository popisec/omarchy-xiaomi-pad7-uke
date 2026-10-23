# Qué más se puede portar del repo MCC45TR (fuera del display) — 17-oct

Fuente: clon local /tmp/claude-1000/ext-senemos (github.com/MCC45TR/senemos-uke-kernel-mainline, MIT, base Linux v7.2.9
`5fce1616…`, también serie 7.2.10). Su capa de plataforma deriva del port público uke Linux 6.12 de ztsubaki
(github.com/ztsubaki/uke-linux @32cad9cc). Solo lectura de nombres de parche y su README: falta revisar cada diff.
Leyenda: "nuestro síntoma" = medido en L76R/L77b (build/linux-l76r-20261017/sistema, l76r-dmesg-20261017.txt).

| Parche(s) suyo(s) (patches/7.2.9) | Qué hace (según su README/nombre) | Nuestro síntoma / hueco que tocaría | Prioridad |
|---|---|---|---|
| 0004 cliffs-interconnect, 0009 ufs-ic, 0026 lpass-adsp-ic, 0037 gpu-ic (+ display/cliffs-display-icc.h) | proveedor ICC cliffs con nodos/BCM/QoS OEM | voto ICC del display NO-OP, agregados llcc/ebi saturados; underrun por frame | ALTA |
| 0002 uke-rpmh-regulators | reguladores RPMh de uke | smpb/smpe/ldob22 -22 → sin dominios mmcx/cx/mx (MMCX sin votar) | ALTA |
| 0001 cliffs-clock-handoff, 0012 gdsc-shared-gcc-regmap, 0011 rpmh-snapshot-size | handoff de relojes/GDSC del ABL | WARN "rcg didn't update" de dispcc, vsync_clk -22, bi_tcxo div2 | MEDIA-ALTA |
| 0005 uke-smmu-handoff (+ display/uke-display-smmu.c) | handoff SMMU acotado | nuestros hacks arm-smmu (uke_write_mask, FIX-A1b, K38/K39) | MEDIA |
| 0022, 0023, 0025, 0034, 0042 (ktz/backlight) | KTZ8866 errores de escritura, bus QUP1, **backlight emparejado (2 chips)**, blanking, mínimo visible | D-11: solo controlamos 1 de 2 KTZ | MEDIA |
| 0020 adsp-pas, 0024 arc-suppliers, 0028 protection-domain-map, 0031-0033/0035 battery/charger glink, 0029 legacy-cpucp-mailbox | ADSP por PAS con votos CX/MX, PD-map, battmgr/charger sin UCSI | nuestra carga va por .ko fuera de árbol + loader; Oops de insmod ucsi_glink; arm-scmi "failed to setup channel" (¿cpucp?) | MEDIA |
| 0014-0016 WPSS/WLAN | proxy regulators WPSS, raíles RF en orden OEM, SMR WLAN | WiFi no funciona (reset ~7 s) | MEDIA |
| 0008-0010 + src/boot/sm7675-uke-ufs.dtso | PHY UFS sm7675, ICC UFS, admisión DMA/potencia | spam "UNIPRO clk 200 MHz not supported" / "dvfs failed (-22)" | MEDIA-BAJA |
| 0006, 0013, 0043, 0044 + usb2.dtso | USB (DWC3 API, eUSB2/repeater, rol, presupuesto) | eusb2-repeater sin supplies, dwc3 "error finding src/dst node" | BAJA (USB gadget ya va) |
| 0021 gpu-clock-handoff, 0036 adreno732-render, 0039, sm7675-uke-adreno732.dtsi | GPU Adreno 732 con render | toda la saga GMU/CM3 (K-series) | ALTA para el escritorio (después de la pantalla) |
| 0040 epss-core-count | cpufreq EPSS | (revisar cpufreq) | BAJA |
| 0038 handoff-panel-metadata, 0041 sysfb-bounded-damage, patches/boot/0001 abl-dt-hook, 0007 independent-dts | CORREGIDO (ADOPCION-SENEMOS): arrancan con el DT del ABL (vendor_boot + dtbo STOCK) y el kernel lo transforma en uke-abl.c aplicando overlays embebidos; 0007 es un DTS independiente que NO usan para arrancar | nosotros: DT vendor + dtbo s288 (incompatible con su validacion) | estructural |
| (display) panel-xiaomi-o82.c + 0034 | táctil NT36532: reset compartido y `touch_reset_state` para recargar firmware RAM | nuestro táctil sin portar | MEDIA (después de la pantalla) |

Conclusión provisional: casi todos nuestros errores de plataforma conocidos tienen un parche equivalente en su serie, y
varios (ICC, RPMh/MMCX, handoff de relojes/SMMU) son candidatos directos al underrun. Eso pesa a favor de adoptar su base
completa (kernel + DT propio) en vez de portar parche a parche; decisión en docs/historia/revision/ADOPCION-SENEMOS-20261017.md.
