# Pendientes: datos de SISTEMA/ARRANQUE a extraer de Android antes de salir (17-oct-2026)

Estado de partida (ESTADO-VIVO, capa 17-oct): tablet en HyperOS OS3.0.303.0, **slot b**, root Magisk
(`su` en `/debug_ramdisk/su`), `boot_a` = L74 `06a1d9fe…`, dtbo s288, `misc` BCB limpio, 4082 mV.
Este documento es solo lectura del repo. Los comandos son de lectura salvo que se marque **[ESCRIBE]**
o **[REINICIA]**. Orden por importancia.

## Prioridad 1: copias de seguridad (sin ellas no hay vuelta limpia)

1. **`vbmeta_system_a` sin copia local** (LV-R2 de docs/guias/LINUX-A-ANDROID-IDA-VUELTA.md; vive en `/dev/sda`).
   Por qué: el paso 0.3 de PLAN-recuperacion-dorada.md queda abierto sin ella.
   `adb shell su -c 'dd if=/dev/block/by-name/vbmeta_system_a of=/sdcard/vbmeta_system_a.img bs=4M'`
   luego `adb pull` y `sha256sum`. **[ESCRIBE en /sdcard]**
2. **Dump completo de arranque por slot.** Los únicos dumps `init_boot_b`/`dtbo_b` son del 3-sep; `boot_a`
   (L74) y `dtbo_a` (s288) no tienen copia de Android. Particiones: `boot`, `init_boot`, `vendor_boot`,
   `dtbo`, `vbmeta`, `vbmeta_system`, `misc` (`_a` y `_b`). Comprobar espacio antes:
   `adb shell su -c 'df -h /sdcard'`. **[ESCRIBE en /sdcard]**
3. **`persist`, `modemst1`, `modemst2`, `fsc`, `fsg`, `countrycode`** (calibración/RF; LV-R4 los prohíbe
   escribir, pero una copia es imprescindible). Mismo patrón `dd`. **[ESCRIBE en /sdcard]**
4. **GPT completo** (sector 0 a 33 del disco): `adb shell su -c 'dd if=/dev/block/sda bs=4096 count=34 of=/sdcard/gpt-sda.bin'`
   (y el disco de `sdb`/`sdc`/`sdd`/`sde` que aplique según `ls -l /dev/block/by-name/`). Sin GPT no se
   reconstruye ningún slot. **[ESCRIBE en /sdcard]**

## Prioridad 2: estado de slots y arranque

5. **Slots y reintentos.** `adb shell su -c 'getprop ro.boot.slot_suffix; getprop ro.boot.verifiedbootstate; getprop ro.boot.bootreason; getprop ro.boot.boot_devices'`
   y, si existe, `bootctl get-suffix`, `bootctl is-slot-bootable 0/1`, `bootctl is-slot-marked-successful 0/1`.
   Por qué: `slot-retry-count:a` fue 7 tras el último flash; la cadena de `qbootctl` sigue pendiente.
   No ejecutar `markBootSuccessful` ni `setActiveBootSlot` (**[ESCRIBE]**).
6. **BCB de `misc`** (leer, no escribir): `adb shell su -c 'dd if=/dev/block/by-name/misc bs=512 count=2 | xxd'`.
   Por qué: LV-R10 y la trampa `boot-recovery` (#233); conviene confirmar que sigue a ceros.
7. **cmdline real del boot actual y bootconfig**: `adb shell su -c 'cat /proc/cmdline; cat /proc/bootconfig'`.
   Ya tenemos los 54 tokens del DT (docs/historia/revision/ANDROID-SISTEMA-INIT-20261013.md §1); falta el valor de `pureason`,
   `boot_index` y `hwid` de este boot.

## Prioridad 3: firmware que necesita el port

8. **Inventario con sha de `/vendor/firmware` y `/vendor/firmware_mnt/image`.**
   `adb shell su -c 'cd /vendor/firmware && sha256sum * ' > /sdcard/fw-vendor.sha`. Prestar atención a
   `adsp.b40` (sha de referencia `42c86837…` en charge/firmware) y a los `gen71100_*`.
   Por qué: `firmware_mnt/image` lo rellena el modem en vivo (NON-HLOS); hay que separar lo estático.
9. **Remoteprocs**: `adb shell su -c 'for r in /sys/class/remoteproc/*; do echo $r $(cat $r/name) $(cat $r/state); done'`.
   Confirma qué firmware corre en ADSP/CDSP/modem/WPSS y en qué estado.

## Prioridad 4: cargador, battmgr y energía

10. **Batería y cargador.** `adb shell su -c 'dumpsys battery; cat /sys/class/power_supply/battery/{voltage_now,current_now,charge_type,capacity}; cat /sys/class/power_supply/usb/{type,online}'`.
    Por qué: el gate de flash es ≥3700 mV con pared ≥45 W (CARGA-AUDITORIA-20261016); tener la curva
    en Android sirve de referencia para el stack ADSP/battmgr.
11. **PD/UCSI y battmgr**: `adb shell su -c 'ls /sys/class/power_supply/; cat /sys/kernel/debug/usb/ucsi*/* 2>/dev/null | head -50'`.

## Prioridad 5: regulators y PMIC

12. **Resumen global de reguladores** (raíles que el ABL deja encendidos, L54):
    `adb shell su -c 'mount | grep debugfs; cat /sys/kernel/debug/regulator/regulator_summary'`.
    Por qué: `regulator_ignore_unused` depende de qué raíl está ya enabled por el ABL.

## Prioridad 6: layout de userdata y reinstalación de Arch

13. **Tamaños de userdata y metadata**: `adb shell su -c 'blockdev --getsize64 /dev/block/by-name/userdata /dev/block/by-name/metadata; cat /proc/partitions'`.
    Por qué: el rootfs ext4 de 4 GiB (`rootfs-uke-k521.img`, en `/var/tmp`, volátil) y el `rootfs-perm`
    de ~1 GB deben caber. Si se reinstala, LV-R1 exige `erase userdata` + `erase metadata` antes del primer
    boot de Android (esto es la vuelta a Android, no la de Arch).
14. **Copiar `rootfs-uke-k521.img` a sitio persistente** antes de cualquier erase. Es el único rootfs
    completo; no es de Android, pero es lo que se pierde si `/var/tmp` se limpia (no es un dato de Android
    en sí; se anota aquí porque el erase es la operación prohibida que lo arrastra).

## Prioridad 7: thermal y GPU

15. **Thermal zones**: `adb shell su -c 'for z in /sys/class/thermal/thermal_zone*; do echo $z $(cat $z/type) $(cat $z/temp); done; ls /vendor/etc/thermal*'`.
    No hay nada de thermal en el repo. Un port sin thermal zones arriesga sobrecalentamiento.
16. **GPU kgsl** (el `reg_dump` de DSI sigue vacío según COSECHA-20261017 §deuda): `adb shell su -c 'cat /sys/class/kgsl/kgsl-3d0/{gpu_model,gpuclk,max_gpuclk,pwrlevels} 2>/dev/null; cat /sys/kernel/debug/kgsl/kgsl-3d0/* 2>/dev/null | head -200'`.
    `dmesg` del kgsl ya está en `build/android/cosecha-20261017/`, pero no los registros.

## Prioridad 8: arranque en frío desde cero

17. **dmesg desde el arranque**: el buffer de anillo ya cubre `dmesg` completo si no se ha sobrescrito
    (`adb shell su -c 'dmesg -T | head -50; cat /proc/sys/kernel/printk'`). Lo que adbd no captura es lo
    anterior a su arranque: `pstore` (`/sys/fs/pstore`) solo sirve tras un pánico.
    Para capturarlo sin perder adb hace falta un servicio Magisk (`post-fs-data.sh`) que haga
    `dmesg -w > /data/local/tmp/kmsg-boot.txt &`. **[ESCRIBE en /data]** y **[REINICIA]** para que
    tome efecto.

## Notas

- El estado de slots y los shas de referencia vienen de ESTADO-VIVO (capa 17-oct) y de las fechas
  indicadas. El ledger (`~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`) manda, pero no se ha
  leído en esta pasada.
- Ya cubierto y no se pide de nuevo: cmdline del DT, inventario de display en `vendor_boot`, `vendor` .ko
  de display, clk_summary y dmesg vendor de COSECHA-20261017.
- Ninguno de estos comandos toca fastboot ni flashea. Cualquier escritura en `boot_*`, `dtbo_*`, `misc`
  o `set_active` queda fuera de este documento y requiere su propia fila de ledger (LV-R10).
