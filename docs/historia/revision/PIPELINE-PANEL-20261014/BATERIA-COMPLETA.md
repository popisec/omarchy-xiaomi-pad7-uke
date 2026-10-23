# BATERÍA/CARGA completa uke — 14-oct-2026 (MEDIDO vs HIPÓTESIS)

Batería ~3479 mV (serie `fastboot battery-voltage` 3414–3447 mV, CARGA-KERNEL.md:72).
Nada vivo hoy: tablet ilocalizable (CARGA-KERNEL.md:3-4). Todo lo vivo = plan.

## 1. Inventario parte a parte (MEDIDO en fichero salvo marca)

1. **PMIC de carga: PM7550 (PMXR2230, SID1) + PM7550BA (SID7)** — MEDIDO:
   `xiaomi-uke.dts:23-24` incluye `pm7550.dtsi` + `pm7550ba.dtsi`; `docs/historia/revision/PIPELINE-PANEL-20261014/USB-HOST-DOCK.md:8-10`
   (HS via `pm7550ba_eusb2_repeater`). Sin `smb5/smblib` en árbol (CARGA-KERNEL.md:17-21):
   la carga la arbitra el **firmware PMIC/ADSP vía glink**, no el kernel AP. HIPÓTESIS
   razonable: PM7550BA = IC standalone (QC D+/D-, carga en fastboot/apagado).
2. **`battery_charger` DT stock: downstream Xiaomi, sin port mainline** — MEDIDO:
   frag 18/45 (`mi,*` ciclo/term) + `charger_partition` frag 46 (CARGA-KERNEL.md:38-42).
   `battmgr` lee por RPC glink, no por DT ⇒ **nada que portar** (solo se pierde gauge fino).
3. **ADSP firmware: LO TENEMOS** — MEDIDO: 58 ficheros en `~/gpu-work/ramaa/s24/adsp-fw/`
   (`adsp.mdt`+`adsp.b00…`, mismo que el hermano #404); copia en
   `build/rootfs/staging/usr/lib/firmware/adsp.b*`. El initramfs de boot solo lleva FW
   GPU (docs/historia/revision/PIPELINE-PANEL-20261014/L60-FALLO-ARRANQUE.md:36-40) ⇒ hay que copiarlo a `/lib/firmware` en vivo.
4. **glink/QRTR/PD_MAPPER (transporte + locator)** — MEDIDO: `pmic_glink.c` registra
   `charger_pd` (`:410-411`); `qcom_pd_mapper.c:605-606` **YA trae `cliffs[-mtp]`**
   (parche hermano aplicado en nuestro árbol); L62: `QRTR_SMD=y`, `PD_MAPPER=y`,
   `PAS=y`, `GLINK_SMEM=y` (config). Sin locator no hay UP (hermano #406).
5. **battmgr/ucsi (clientes)** — MEDIDO: `qcom_battmgr.c:1397-1406,1636-1645` **YA trae
   el parche 0x50/0x51 silencioso sin ack**; aux-devices los crea `pmic_glink.c:343-355`
   (no falta nodo DT). L62: `PMIC_GLINK=m`, `UCSI=m`, `BATTMGR=m` + `.ko` compilados.
6. **PDR `charger_pd` = gate** — MEDIDO en Android: `0x1fffffff` a 7.13 s
   (CARGA-ANDROID-REF.md:18-20) y en hermano en frío #406. Sin UP ⇒ todo `-EAGAIN`.
7. **PD/type-C/altmode** — MEDIDO: `pmic_glink_altmode` irrelevante carga base
   (hermano: no carga por símbolos DRM y no pasa nada, #404). Conector dual-role
   + endpoint HS en `xiaomi-uke.dts:89-129` (docs/historia/revision/PIPELINE-PANEL-20261014/USB-HOST-DOCK.md:10-13).
8. **Thermal** — MEDIDO stock: `mi,thermal`/`mi,temp_term_curr*` en dtbo
   (CARGA-ANDROID-REF.md:23-26); el que limita vive en FW/userspace Xiaomi, no en AP.
9. **Autonomía sin ADSP** — MEDIDO (hermano #403-404): sin PDR-UP el ADSP solo **no
   carga**; `off-mode-charge=1` + pared sí sube mV (3204→3403 en EDL).

## 2. Estado por mundo

| Pieza | Android | Hermano (#404→#406) | Nosotros | Veredicto |
|---|---|---|---|---|
| FW ADSP | bootea 5.9 s, `battery_chg` 8.8 s | `running`, 49 segs, `uke-adsp.service` | 58 segs en staging, nunca cargado | FW ✓ / arranque ✗ |
| glink+QRTR | `qrtr` 0.41 s, glink AP | 6 módulos en orden, 1.19 A Fast | `=y`=y built-in; `=m` con `.ko` L62 | Listo p/insmod |
| pd_mapper | daemon vendor | parche cliffs, `0x40/0x101` OK | parche **ya en árbol** `:605-606`, `=y` | Paridad ✓ |
| battmgr | `qti_battery_charger` | parche 0x50 + `.ko` s24 | parche **ya en árbol**, `.ko` L62 | Paridad ✓ |
| DT pmic-glink | `qcom,pmic_glink/` + `qti,battery_charger` | rename `_log`→`-log` + `gpr disabled` (s207) | **TRIPLE nodo** (2 vendor + `xiaomi-uke.dts:89-92`) + guard con ventana (`:312` check, `:369` set) | **Nuestro riesgo único** |
| Carga FW | PON USB_CHARGER | pared + off-mode | misma (PMIC standalone) | Paridad (HIPÓTESIS: probar pared) |

Wedges distintos, misma firma (docs/historia/revision/PIPELINE-PANEL-20261014/CARGA-HERMANO-VS-NUESTRA.md:15-19): hermano = pareja
QRTR/BATTMGR `=y` (K1/K2); nuestro = **glink y/o ucsi `=y`** (L63; QRTR=y exonerado por L59).

## 3. PROPUESTA (usar lo que YA tenemos; slot a=3, ≤2 escrituras/día)

**(i) Autónoma ya-posible (0 flashes, AHORA):** cargador pared PD/QC ≥45 W directo,
nada de dock (WD19 downstream = 5 V sin PD, docs/historia/revision/PIPELINE-PANEL-20261014/WD19-CARGA.md:10-18). Verificar:
`fastboot getvar battery-voltage` sube serie. Riesgo 0. (HIPÓTESIS: si ni en
apagado sube, el problema es cable/fuente, no kernel.)

**(ii) Gestionada vía módulos+insmod (0 flashes, cuando haya SSH en L58/L59):**
`QRTR/PD_MAPPER/PAS/GLINK_SMEM` ya `=y` ⇒ solo 3 insmod + FW:
1. copiar FW a `/lib/firmware` + `.ko` L62 (`pmic_glink.ko`, `qcom_battmgr.ko`,
   `ucsi_glink.ko`) a `/usr/local/share/uke/mods` (guion `charge/uke-adsp-load.sh` ya existe);
2. `dmesg -n 7` + doble captura (ACM + `dmesg -w`); `insmod pmic_glink.ko` →
   verificar vivo + `PDR: … charger_pd … 0x1fffffff`; 3. `insmod qcom_battmgr.ko` →
   `ls /sys/class/power_supply/` (`qcom-battmgr-{bat,usb,wls}`) → `status=Charging`,
   `current_now>0` (hermano: 1.19 A Fast, #406); 4. `echo start` ADSP según guion
   (orden PAS→glink_smem→qrtr→pd_mapper→pmic_glink→battmgr). Riesgo: oops **en
   runtime** por doble nodo (reversible `rmmod`+reboot, −1 retry), NO wedge mudo.
   Fallback: `drivers_autoprobe=0` + `gpr disabled` si aparece bucle -22 (#406).
**NO TOCAR:** nada `=y`, nada SMMU/watchdog/runtime-PM, nada `mi,*`, nada altmode/DP.

**(iii) Consolidación en kernel (más adelante, 1 rebuild + 1 flash):**
portar rename `_log`→`-log` a rama s28x (s288) + endurecer guard (asignar
`__pmic_glink` ANTES de crear aux, o sufijar aux por nodo) + `QCOM_PMIC_GLINK=y` +
`UCSI_PMIC_GLINK=y` SIN battmgr (L61 aísla sospechoso). Solo si (ii) vive.
