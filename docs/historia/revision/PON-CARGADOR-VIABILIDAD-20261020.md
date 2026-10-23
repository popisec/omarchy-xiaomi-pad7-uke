# ¿Puede Linux impedir que el cargador vuelva a encender la uke tras `poweroff`? (20-oct-2026)

Investigación **de solo lectura**: no se escribió nada en la tablet, no se reinició y no se tocó ningún fichero del repo salvo este informe.
Tablet medida el 20-oct entre 12:28 y 12:36 por SSH (192.168.42.129), kernel `7.2.9-senemos.1.4054.3-ouke5`.

## Veredicto

**NO VIABLE** cortar desde Linux el disparo de encendido del PMIC por cargador (USB_CHG) para que `poweroff` la deje apagada y cargando.
**SÍ VIABLE**, y en parte ya desplegada, la alternativa que usa Android: arrancar en un «modo carga» mínimo. Es lo que el informe `BATERIA-20261019.md` llama opción 1.

## 1. Cómo funciona el PON del PMK8550 en mainline

- `drivers/power/reset/qcom-pon.c`, en el master de torvalds, consultado el 20-oct ([fuente](https://github.com/torvalds/linux/blob/master/drivers/power/reset/qcom-pon.c)):
  - El único registro que toca es `PON_SOFT_RB_SPARE` (0x8f): escribe el motivo de reinicio de `reboot-mode` con `regmap_update_bits`.
  - Compatibles: `pm8916`, `pm8941`, `pms405`, `pm8998` y `pmk8350-pon`.
  - **No tiene ningún código para habilitar o deshabilitar disparos de encendido (triggers).**
- Binding `qcom,pon.yaml` ([fuente](https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/power/reset/qcom,pon.yaml)):
  - Admite `reg` con hlos más pbs (opcional), subnodos `pwrkey`, `resin` y `watchdog`, y `mode-*` (solo bootloader y recovery).
  - **Ninguna propiedad deshabilita el trigger de cargador.** Tampoco la hay en `pm8941-pwrkey`, que solo cubre la tecla y el reset.
- Driver de Qualcomm/Xiaomi para SM8650: `drivers/input/misc/qpnp-power-on.c` ([fuente](https://github.com/Xiaomi-SM8650/android_kernel_xiaomi_sm8650/blob/lineage-22.1/drivers/input/misc/qpnp-power-on.c)). En él, `qpnp_pon_trigger_config()` (L906–931) escribe `QPNP_PON_TRIGGER_EN` (base+0x80), pero antes hace:
  ```c
  if (is_pon_gen3(sys_reset_dev))
          return -EPERM;
  ```
  - En los PMIC Gen3 (subtipos `PON_GEN3_PBS` 0x08 y `PON_GEN3_HLOS` 0x09, L43–44 y L415–418) ni siquiera el driver del fabricante deja configurar los triggers.
  - `qpnp_pon_is_warm_reset` y `wd_config` también devuelven `-EPERM` (L837 y L855).
  - El propio driver dice «PON_GEN3 does not have PON/POFF reason registers» (L2199–2201).
  - **Conclusión**: en Gen3 la configuración de triggers vive en el bloque `PON_PBS` y la gestionan el firmware PBS y el XBL, no el sistema operativo (HLOS).
- El PMK8550 de la uke es Gen3. Así lo describe su DT en vivo:
  ```
  /soc/qcom,spmi@c42d000/qcom,pmk8550@0/pon_hlos@1300
    compatible = qcom,pm8998-pon ; reg = 0x1300 0x0800 ; reg-names = pon_hlos pon_pbs
  ```
  Además, en dmesg aparecen `pmic_pwrkey`/`pmic_resin` sobre `pon_hlos@1300`, y el driver ligado es `qcom-pon`.
- `reboot-mode`: el nodo `/soc/reboot_reason` es `nvmem-reboot-mode` con la celda SDAM `0x7100+0x48` (`restart@48`). Sus modos son `normal`=0x20, `bootloader`=0x02 y `recovery`=0x01. **No existe ningún modo de carga ni de apagado.**
- SPMI en vivo: `/sys/bus/spmi/devices` = `0-00 0-01 0-02 0-03 0-04 0-07 0-0d spmi-0`. No se volcó ningún regmap.

**Posible vía cruda** (un módulo propio que escriba `PON_PBS+0x80` por SPMI): no existe ningún driver ni sysfs para ello. El acceso de escritura del sistema operativo a `PON_PBS` depende de los permisos del árbitro SPMI. **Hipótesis no verificada**: probablemente esté denegado, o lo reprograme el XBL y el PBS en cada arranque.
Aunque funcionara, el riesgo es alto:
- Viola la regla de método nº 3: nada de poke de MMIO o regmap en tiempo de ejecución.
- El registro del PMIC se conserva mientras haya batería, así que el cambio persistiría fuera de nuestro control.
- Una tablet con la batería agotada **no arrancaría al enchufarla**. Hipótesis: el cargador del XBL podría seguir cargando, pero sin verificar.
- No se puede revertir sin volver a arrancar Linux.

**Descartado.**

## 2. Qué hace el bootloader (ABL/XBL) y qué significan pureason y silent_boot

- El ABL de la uke tiene `oem off-mode-charge`, `enable-charger-screen` y `disable-charger-screen` (`docs/informes/B-arranque-arch-uke.md:425-426`), y **`off-mode-charge=1` ya está puesto** (`docs/historia/ESTADO-VIVO.md:206` y `:560`).
- Así lo hace el ABL de referencia de Qualcomm (`QcomModulePkg`, espejo arter97/android_bootable_bootloader_edk2, rama `r`, consultado el 20-oct; [fuente](https://github.com/arter97/android_bootable_bootloader_edk2)):
  - `UpdateCmdLine.c` L85–160, `TargetPauseForBatteryCharge()`: activa el modo carga si se cumplen todas estas condiciones:
    - arranque en frío,
    - sin `HARD_RESET`,
    - sin `KPDPWR`,
    - (`PON1` o `USB_CHG`),
    - cargador presente.
  - En los chips nuevos (`Revision >= CHARGER_EX_REVISION`) lo decide `IsOffModeCharging()` del protocolo de cargador del XBL.
  - L650–662: si se cumple lo anterior, `IsChargingScreenEnable()` es cierto y no es recovery, añade **`androidboot.mode=charger`** («Device will boot into off mode charging mode»).
  - `LinuxLoader.c` L112–121: en modo carga **no descuenta reintentos de slot**.
  - `FastbootCmds.c` L3020–3050 y L3695–3697: `oem off-mode-charge 0/1` solo cambia `ChargingScreenEnable` en devinfo.
  - **Es decir: el ABL nunca deja el equipo apagado.** Con el ajuste a 1 arranca el kernel en modo carga, y con el ajuste a 0 arranca normal. **Es el sistema operativo quien implementa la carga «apagada»**: Android lo hace con su binario `charger`, que solo apaga de verdad (`reboot(POWER_OFF)`) cuando se quita el cable.
- **En la uke no vemos `androidboot.mode`.** Con la cabecera v4 los `androidboot.*` van en el **bootconfig**, y nuestro kernel tiene `# CONFIG_BOOT_CONFIG is not set`:
  - `/proc/config.gz` del 20-oct lo confirma.
  - No existe `/proc/bootconfig`.
  - dmesg avisa «'bootconfig' found on the kernel command line but CONFIG_BOOT_CONFIG is not set» (`out/rescue/forklog-1375.txt:13`).
  - **Hipótesis**: el ABL ya está pasando `androidboot.mode=charger` en estos arranques y lo perdemos.
- `bootinfo.pureason`: es un parámetro de Xiaomi y no hay documentación pública. No se encontró fuente primaria. Tabla de valores observados (`grep` en ambos proyectos y en `journalctl` de los boots −5..0 del 20-oct):

  | valor | n | contexto observado |
  |---|---|---|
  | `0x40010` | 6 | `poweroff` con el cable puesto, luego rearranque solo (19-oct; 20-oct 12:30 y 12:32, `/var/log/uke-bateria/arranques.log`) |
  | `0x40001` | 11 | arranques en frío (Android y Linux), probablemente con el botón de encendido |
  | `0x80001` / `0x800001` | 5 / 27 | `reboot` / `fastboot reboot` (diccionario de `NOTAS-OMARCHY.md:2911`) |
  | `0x80011` / `0x800011` | 3 / 11 | panic |
  | `0x80100` / `0x80110` | 19 / 47 | reset caliente por cuelgue o wedge |

  **Hipótesis**: el bit 0x40000 significa «encendido en frío» y 0x80000/0x800000 «reset caliente». El 0x10 coincide con el bit 4 = `USB_CHG` del antiguo `PON_REASON1` (Gen1/2), lo que encaja con la regla del ABL. Sin fuente primaria.
- `silent_boot.mode=nonsilent` y `pdreason=0x2`: no discriminan. Ambos aparecen igual en todos los tipos de arranque registrados. **Hipótesis**: `silent_boot` es el modo de Xiaomi para encendido programado o por alarma, sin pantalla. Sin fuente.
- `misc`/BCB: solo admite `boot-recovery`, `bootonce-bootloader` y similares. No hay ningún comando de BCB para «modo carga» ni para «mantener apagada». `oem poweroff` es diferido («Will power off after USB out», docs/historia/revision/ANDROID-GPU-ARRANQUE-20261010.md:18), es decir, **el propio ABL no se apaga con el cable puesto**.

## 3. Evidencia en vivo (20-oct, solo lectura)

- `/proc/cmdline` incluye `bootinfo.pureason=0x40010 bootinfo.pdreason=0x2 … silent_boot.mode=nonsilent`.
- Boot −1: termina en `systemd-shutdown[1]: Sending SIGTERM…` (12:22:10). Esto confirma que el apagado fue ordenado.
- Batería al 2 % (3,51 V), `qcom-battmgr-usb` `online=1`, SDP 500 mA, `status=Charging`.
- `CONFIG_POWER_RESET_QCOM_PON=y`, `CONFIG_NVMEM_REBOOT_MODE=y`, `CONFIG_BOOT_CONFIG` sin activar.
- Durante la medición otra sesión apagó y encendió la tablet dos veces (12:30 y 12:32, `pureason=0x40010`), y a las 12:35 el botón de encendido arrancó el escritorio. Este agente no intervino en eso.

## 4. Conclusión, riesgos y cambio mínimo recomendado

- **Bloquear el trigger en el PMIC: NO VIABLE.** No hay API en mainline. El driver de Qualcomm responde `-EPERM` en Gen3 y el registro pertenece al PBS/XBL. Escribir a pelo por SPMI viola las reglas, sus efectos son persistentes y difíciles de deshacer, y podría dejar la tablet sin poder arrancar por cargador.
- **La alternativa sí es viable.** Es el comportamiento estándar de Qualcomm/Android: arranque en «modo carga» hecho por el sistema operativo. La opción 1 ya funciona (`uke-modo-carga`, BATERIA-20261019.md:57). Para que «apagada cargando» se parezca a Android:
  1. **Sin flashear (solo rootfs).** En modo carga:
     - Al **desenchufar el cable** (`qcom-battmgr-usb online=0`) → `sync; systemctl poweroff`. Sin VBUS, el PMIC ya no vuelve a encender.
     - Con el cable puesto, **no** hacer `poweroff`: provocaría el bucle de rearranque.
     - Opcional: suspender (s2idle) con `pmic_pwrkey` como fuente de despertar, para gastar menos.
     - Se revierte con `deploy.sh revert`.
  2. **Con autorización de flash (un cambio por ciclo).** Activar `CONFIG_BOOT_CONFIG=y` en el siguiente kernel y leer `androidboot.mode` en `/proc/bootconfig`. Así el ABL decide de verdad (incluido el caso con el botón pulsado) y desaparece la calibración por `pureason`.
     - Riesgo bajo: es puramente informativo. El bootconfig ya se anexa hoy y ahora el kernel lo ignora.
     - Pero el bootconfig del vendor también mete `swiotlb=noforce` (B §5.3/§5.4, riesgo R16, F:1481). **Hay que verificar** que el parche que ignora `noforce` sigue aplicándose cuando esos parámetros vengan por bootconfig, antes de flashear.
     - Prueba: `poweroff` con el cable puesto → `cat /proc/bootconfig | grep androidboot.mode` debe dar `charger`. Después, arranque con el botón: no debe aparecer.
     - Reversión: el par bueno de `build/backup-par-bueno/`.
- **No tocar** `oem off-mode-charge`: ponerlo a 0 solo haría que arrancase el escritorio completo con el cable, y además es un cambio de devinfo en fastboot.
