# CARGA: Android (vendor) como referencia vs hermano vs nosotros — 14-oct-2026

Fuentes primarias: `extracted-r15/.../07-sys/dmesg-FULL.txt`, `dt-r15/soc/`,
`dtbo-stock-decomp.dts`, hermano `ESTADO-ACTUAL.md:193-258`, `FLASH-LEDGER.md #404/#406`,
`criticas/ronda-29/BATTMGR-DIALECTO.md`, nuestro `CARGA-KERNEL.md` + addendum L60.

## (a) Qué hace Android para cargar

1. **Manda el ADSP, no el kernel AP.** `PMIC PON log: PON Trigger: USB_CHARGER`
   (dmesg-FULL:1642). El AP arranca el ADSP a 5.91 s vía
   `init.qti.write.sh /sys/kernel/boot_adsp/boot 1` (dmesg-FULL:6492-6493) →
   `remoteproc0: Booting fw image adsp.mdt` (:6514/sig). El firmware del ADSP corre el
   `battery_chg` (lado PD) + extensión Xiaomi (`battmngr_xiaomi_*`, `xm_batt_update_work`;
   BATTMGR-DIALECTO §1.4, strings del `adsp.mdt` del hermano).
2. **Protocolo: PMIC GLINK sobre QRTR/servreg.** El kernel AP solo lleva el transporte
   (`pmic_glink` + `qcom,battery_charger`, DT `dt-r15/soc/qcom,pmic_glink/`) y el cliente
   `qti_battery_charger`, que probea a 8.78 s (dmesg-FULL:8441/8483) **DESPUÉS** del PDR.
3. **PDR `charger_pd` = gate de todo.** `PDR: Indication received from
   msm/adsp/charger_pd, state: 0x1fffffff` a 7.13 s (dmesg-FULL:8133-8134), **antes** del
   probe del charger. Sin ese UP, el cliente no tiene servicio contra el que hablar.
4. **Altmode/PD type-C**: `pmic_glink_altmode` existe pero es irrelevante para carga base
   (el hermano lo confirma: no carga por símbolos DRM DP ausentes y no pasa nada).
5. **Thermal**: el DTBO stock trae `mi,thermal` + `mi,temp_term_curr*` + `mi,cycle_*`
   (dtbo-stock-decomp.dts:3041-3058); el thermal que limita corriente vive en el
   firmware/ userspace Xiaomi (`micharge-hal`, `batterysecret`, `batteryantiaging` en
   getprop), no en el kernel AP.

## (b) Tabla pieza | Android | hermano | nosotros | veredicto

| Pieza | Android | Hermano | Nosotros | Veredicto |
|---|---|---|---|---|
| Firmware ADSP con `battery_chg`+XM | ADSP bootea a 5.9 s, `battery_chg probe done` 8.8 s | ADSP `running` + fw 49 segs, `uke-adsp.service` | Sin ADSP (nunca arrancado) | Hermano ✓ / nosotros ✗ |
| Transporte glink+QRTR | `qrtr.ko` early (0.41 s), pmic_glink AP | `q6v5_pas,glink_smem,qrtr_smd,pd_mapper,pmic_glink,battmgr` en orden (ESTADO:197) | `=m` pero build con 0 `.ko` ⇒ ausente en flash (CARGA-KERNEL addendum) | Hermano ✓ / nosotros ✗ |
| Locator servreg AP (`pd_mapper`) | implícito (userspace/daemon vendor) | Parche `cliffs→sm8550_domains`; `0x40/0x101` anunciado | No tenemos el parche ni el módulo | Hermano ✓ / nosotros ✗ |
| PDR `charger_pd` UP | `0x1fffffff` a 7.13 s | Mismo mensaje en frío + `Charging` 1.19 A Fast (ESTADO:193-197) | Nunca visto | Hermano ✓ / nosotros ✗ |
| Cliente batería | `qti_battery_charger` downstream (uevents Xiaomi: SOC_DECIMAL, QUICK_CHARGE, pen, wls) | `qcom_battmgr` mainline + parche dialecto 0x50/0x13 | `BATTMGR=m` ausente en imagen; wedge con `=y` (L60 rollback, ledger #639-640) | Hermano ✓ / nosotros pendiente |
| Tablas finas gauge (`mi,cycle_*`, thermal) | DTBO stock frag 18/45+46 | No porteadas (cosmético) | No porteadas; `battmgr` lee por RPC, no por DT | Paridad: nadie las necesita |
| Carga standalone sin OS | PON USB_CHARGER en BL | `off-mode-charge=1`; EDL/fastboot dan mV | `fastboot battery-voltage` 3414-3447 mV | Ambos la tienen (es del PMIC) |

## (c) `charger_pd` que nunca sube — la pieza que falta

Qué es: un **Protection Domain servreg/QRTR** registrado por `pmic_glink.c:410-411`
(`pdr_add_lookup`); el ADSP lo expone (R-37 falsada: está en el DTB del ADSP y sus
strings) y el AP debe tener un **locator** que anuncie `SERVREG_LOC (0x40)` para que el
PDR complete el handshake UP. Cómo lo levanta el vendor: daemon/userspace + qrtr
temprano; en mainline el locator es `qcom_pd_mapper` (`qcom_pdm_start` matchea la raíz
del DT). Por qué no subía en el hermano: `qcom_pdm_domains[]` solo traía
`qcom,palawan`, la raíz real es `qcom,cliffs-mtp/qcom,cliffs/qcom,mtp` ⇒ `-ENODEV`
("no support for the platform") ⇒ sin anuncio 0x40 ⇒ `service_up=false` ⇒ **todas** las
props `-EAGAIN` (ESTADO:251-258; R-35/R-36 falsan H1/H2: transporte y `0x101` sanos).
Se necesita: (1) fw ADSP correcto ya cargado, (2) `qcom_pd_mapper` con `cliffs` en la
tabla, (3) orden glink/qrtr **antes** de `pmic_glink`. Nada de "dark PD": es el mapper
mainline con dos líneas. (#406 lo certificó con sonda QRTR propia: 13 servicios del
ADSP, 0x40 ausente → presente tras el parche.)

## (d) Dialecto Xiaomi 0x50/0x07

Sí, lo habla el ADSP en Android: `xm_batt_update_work ... interval:8` (dmesg-FULL:8493;
10.01 s en el hermano) + uevents `POWER_SUPPLY_SOC_DECIMAL/QUICK_CHARGE_TYPE` y props
`mi,*` del DTBO. Lo consume `qti_battery_charger` downstream (`BC_XM_STATUS_GET/SET`
0x50/0x51, tabla BATTMGR-DIALECTO §1.1; enums 1:1 con mainline en la gen 3.0, sin
renumerar). El parche del hermano (0x50/0x51 silenciosos en ambos callbacks + 0x50/0x79
en notificaciones, sin falsar `complete(&ack)`) es suficiente para lo visto; R-38:
**el 0x50 NUNCA fue la causa del no-cargo** (ruido, no bloqueo). Queda el 0x13
(`BATT_TTF_AVG` responde cadena de 132 B, TTF "No data", cosmético) + ack ya parcheado.

## (e) ¿Cargar SIN ADSP? Sí, con límites

Fundamento: la carga autónoma la lleva el **firmware del PMIC/ADSP** (handshake D+/D-,
QC; PD), no Linux — hay carga en fastboot/apagado (`off-mode-charge=1`; el hermano
midió 3204→3403 mV en EDL). Límites: sin negociación PD cae a **5 V** (lento; con
pantalla ON el balance puede ser nulo — ver docs/historia/revision/PIPELINE-PANEL-20261014/WD19-CARGA.md); puerto de PC = SDP con
`input_current_limit` de solo lectura (500 mA ⇒ ~2.3 W, mantenimiento). Verificar en
uke: `fastboot getvar battery-voltage` (serie 3414-3447 mV nuestra) y, con OS,
`qcom-battmgr-{bat,usb}/uevent` (`VOLTAGE_NOW/CURRENT_NOW/USB_TYPE/CHARGE_TYPE`).

## (f) Recomendación para uke

Secuencia mínima con lo que YA tenemos: (1) pared PD/QC ≥45 W **ahora** (carga
autónoma; nada de dock); (2) próximo kernel = L59 + `QCOM_PMIC_GLINK=y` +
`UCSI_PMIC_GLINK=y` **SIN battmgr** (L61, un cambio por ciclo; battmgr por insmod +
fw ADSP, receta 28-sep); (3) portar del hermano: `pd_mapper`+`battmgr` parcheados
(dialecto+ack) y `uke-adsp.service` con el orden de 6 módulos; (4) `gpr disabled`
(s207) desde el primer dtbo con ADSP (evita el bucle -22 que drenó la batería a las
02:11). NO tocar hasta que la pantalla esté: nada de `=y` para battmgr/qrtr (wedge
probado L60), nada de SMMU/watchdog/runtime-PM, nada de tablas `mi,*` (cosmético).
