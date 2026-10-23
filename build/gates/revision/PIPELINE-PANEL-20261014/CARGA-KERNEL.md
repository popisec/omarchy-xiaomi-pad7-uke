# Carga de batería vs kernel L59 (k52L59, sha e3511595…) — 14-oct-2026

Estado: **estático verificado; vivo PENDIENTE** (tablet ilocalizable:
`ssh -i build/rootfs/uke-arch-root root@192.168.42.129` → timeout 15 s).

## 1. Config `build/kernel-config/k52L59.config` (L59 = L58 byte-idéntico; zram ya en L58)

Cadena de carga PRESENTE (todo `=m` salvo indicación):
- `CONFIG_POWER_SUPPLY=y` (3842), `HWMON=y` (3844)
- `CONFIG_BATTERY_QCOM_BATTMGR=m` (3856) ← expone batería/cargador vía glink
- `CONFIG_QCOM_PMIC_GLINK=m` (7294) ← RPC con firmware PMIC/ADSP
- `CONFIG_TYPEC=y` (6335), `TCPM=m`, `TCPCI=m`, `TYPEC_QCOM_PMIC=m` (6342)
- `CONFIG_TYPEC_UCSI=y` (6343), `CONFIG_UCSI_PMIC_GLINK=m` (6347)
- `CONFIG_TYPEC_MUX_FSA4480=y` (6360); `SPMI=y`, `SPMI_MSM_PMIC_ARB=y` (3550),
  `MFD_SPMI_PMIC=y` (4262), `REGULATOR_QCOM_SPMI=y` (4400), `QCOM_SPMI_ADC_TM5=m` (4129)

AUSENTE (y **esperado**, no es hueco):
- `CONFIG_CHARGER_QCOM_SMBB` (3879) y `CONFIG_CHARGER_QCOM_SMB2` (3904): `is not set`.
  En esta plataforma (PM7550/PM7550BA) la carga la arbitra el **firmware del PMIC
  vía pmic-glink + battmgr**, no `smb5/smblib` en el kernel (el árbol no trae
  `smb5.c`; `qcom_smbx.c` es SMB139x-DC, `qcom_smbb.c` es era PMI8998).
- `CONFIG_EXTCON_QCOM_SPMI_MISC` (7392): `is not set`; el role-switch va por
  `pmic-glink → usb_1_dwc3_hs`, no por extcon-spmi (`EXTCON_USB_GPIO=y` basta).

## 2. Árbol `build/kernel-pokes/k52-L16-tree` + DT

- Drivers existen: `drivers/power/supply/qcom_battmgr.c`,
  `drivers/soc/qcom/pmic_glink.c` (con guard anti-doble-nodo uke, :305-317),
  `drivers/usb/typec/ucsi/ucsi_glink.c`, `tcpm/qcom/qcom_pmic_typec*.c`.
- `arch/arm64/boot/dts/qcom/xiaomi-uke.dts:89-128`: declara `pmic-glink`
  (`qcom,lamma-pmic-glink` + `sm8550` + genérico) con `connector@0`
  (`usb-c-connector`, dual-role) y endpoint → `usb_1_dwc3_hs`. Suficiente:
  `battmgr`/`ucsi`/`altmode` son **aux-devices que crea el propio driver**
  (`pmic_glink.c:343-355`: `ps_aux "power-supply"`, `ucsi_aux`, `altmode_aux`);
  **no falta ningún nodo `charger`/`battery` en DT**.
- Caveat menor: `orientation-gpios = <&tlmm 122>` es valor QRD, marcado
  `TODO(G2)` sin confirmar en uke (:79-83). Afecta orientación CC, no la carga.
- Stock `~/gpu-work/ramaa/s7/dtbo-stock-decomp.dts`: `battery_charger`
  (frag 18/45, props `mi,*` ciclo/term) y `charger_partition` (frag 46) son
  bindings **downstream Xiaomi/ADSP**, sin equivalente mainline; `battmgr`
  lee por RPC glink, no por DT. No hay port de DT pendiente para carga base
  (solo se pierde la tabla fina de gauge `mi,cycle_*`, cosmético).

## 3. Vivo — PENDIENTE (tablet apagada/flaky hoy)

Cuando vuelva, en orden:
1. `ls /sys/class/power_supply/` + `cat */uevent` (STATUS/CAPACITY/VOLTAGE_NOW/
   CURRENT_NOW/ONLINE/USB_TYPE/CHARGE_TYPE/HEALTH/INPUT_CURRENT_LIMIT)
2. `dmesg | grep -iE 'smb|charger|battery|power_supply|typec|pd_manager|extcon|glink|battmgr'`
   (esperado: `pmic_glink` probe + aux `power-supply`/`ucsi`, sin panic doble-nodo)
3. `ls /sys/class/typec/ /sys/class/extcon/`; `ls /sys/firmware/devicetree/base/ | grep -iE 'charger|battery|pmic'`
4. Con PC conectado: ¿`ONLINE=1` y `CURRENT_NOW≠0`? (RNDIS enumera datos: el límite
   BC1.2 puede no aplicar → autolímite 500/900 mA; ver `docs/historia/revision/PIPELINE-PANEL-20261014/WD19-CARGA.md` §3.)

## 4. Conclusión

**Veredicto: SÍ, el kernel flasheado trae la carga.** No falta driver, config
ni nodo DT para carga base y reporte (battmgr+glink+ucsi+SPMI/ADC todo presente).
El «no carga» con el dock es **fuente, no kernel**: el WD19 da 5 V sin PD en
downstream (4,5–15 W; `docs/historia/revision/PIPELINE-PANEL-20261014/WD19-CARGA.md:10-18`) y el USB de la tablet es gadget
ACM+NCM (`docs/historia/revision/PIPELINE-PANEL-20261014/USB-HOST-DOCK.md`), combinación que deja carga lenta/nula.
**Acción: cargador de pared, no rebuild.** Si algún `=m` no carga en arranque,
verificar que `qcom_battmgr/pmic_glink/ucsi_glink` están en initramfs/módulos.

## 5. Extra: cargador PD/QC 45 W genérico

**Sí, vale.** El IC de carga (PM7550BA) carga en **standalone**: el handshake
D+/D- (QC) y la negociación PD la lleva el firmware del PMIC/ADSP, no Linux;
hay carga incluso en fastboot/apagado. Sin PD completo cae a 5 V (lento pero
carga); con PD/QC negocia 9–11 V/45 W aunque el OS no traiga nada más.
Fundamento: `docs/historia/revision/PIPELINE-PANEL-20261014/WD19-CARGA.md:20-27` (Pad 7: PD3.0/QC3.0/MI FC2.0, 5–11 V/4,1 A).
Con 3414–3447 mV en fastboot: **pared primero, depurar después**.

## ADDENDUM (14-oct ~23:0x, corrección del ejecutor)

- **Corrección al veredicto**: `BATTERY_QCOM_BATTMGR=m`, `QCOM_PMIC_GLINK=m`,
  `UCSI_PMIC_GLINK=m` — y **nuestro build solo produce `Image.gz` (0 `.ko`)** ⇒ en el kernel
  FLASHEADO esa pila NO está presente (mismo caso que zram=m, que hubo que pasar a `=y` en L58).
- Fix para el PRÓXIMO kernel (consolidación con BT/GENI): `BATTERY_QCOM_BATTMGR=y`,
  `QCOM_PMIC_GLINK=y`, `UCSI_PMIC_GLINK=y` (y revisar el resto de `=m` que importe:
  ath11k ya aparcado). Verificación viva: `ls /sys/class/power_supply/` + `dmesg | grep battmgr`.
- Entretanto la carga (si existe) es autónoma del PMIC/ADSP; sin visibilidad por sysfs.
