# AUDIO — guion de la ida a Android (referencia de los FS19xx), preparado — 19-oct-2026

**No se tocó la tablet** salvo lecturas (SSH, `dd` de solo lectura de particiones). Nada se ha borrado ni flasheado.

## Hechos medidos hoy (11:03, solo lectura)
- **Slot b ya es Android stock** (sha de lectura de cada partición == imagen de `build/android/flash-b/`): `boot_b` `f5ea7d90…`, `init_boot_b` (Magisk) `b3cfc9b7…`, `vendor_boot_b` `3ee6d4ac…`, `dtbo_b` `27e61d21…`, `vbmeta_b` `0f7399d9…`, `vbmeta_system_b` `b4c81eaa…`. ⇒ **la ida no necesita flashear nada en el slot b** (menos escrituras que en la receta histórica).
- **Slot a (Linux) vigente:** `boot_a` = v4 `fc9309a3…`, `dtbo_a` = stock `27e61d21…`: no se tocan.
- **`misc` NO está a ceros:** contiene un BCB `boot-recovery` + `recovery\n--prompt_and_wipe_data\n--reason=fs_mgr_mount_all` (resto de un intento anterior de Android con el userdata de Linux). Con él, Android iría a recovery y `magiskinit` abortaría («Charger mode or ramdisk is recovery», trampa #233). **Hay que limpiarlo en la ida** (fila nueva **#667** en el ledger hermano).
- Copia verificada de `userdata`: `/var/tmp/uke-userdata-backup/userdata-20261019-105504-fsck.img` sha `6bd9c632…` (cruda `e72914ed…`), clean, centinelas OK, sparse igual. Batería 4,34 V, `Charging`. `uke_fs_play=N`.

## Piezas
`build/gates/ida-android.sh` (`--check`, `--fastboot-check`, `--go`, `--plan`; el `--check` ya se ejecutó en vivo: todo OK salvo el aviso de `misc`), `build/gates/backup-userdata.sh` (`--restore-plan`), `build/android/audio-ref-capture.sh` (captura de solo lectura), ledger hermano **#662 (PASA) y #663-#667 PENDIENTE**.

## Guion paso a paso (cada fase con orden del dueño)
| # | Quién | Qué | Comando exacto |
|---|---|---|---|
| 0 | yo | Avisar a las sesiones (texto abajo) y fijar ventana (1-3 h) | `SendMessage` a BT, batería, lápiz… |
| 1 | yo | Comprobación en Linux (solo lectura) | `build/gates/ida-android.sh --check` |
| 2 | **dueño** | Cargador conectado; tablet a fastboot a mano (ACM con **un solo lector** armado; vigía fastboot apagado/pausado) | — |
| 3 | yo | Gates de fastboot (solo `getvar`): producto, slot actual, `slot-retry-count`/`unbootable` a y b, `is-userspace`, **batería ≥ 3700 mV** | `build/gates/ida-android.sh --fastboot-check` |
| 4 | yo, con orden expresa | **Destructivo**: `erase userdata`, `erase metadata`, `flash misc` (8 KiB de ceros, sha `9f1dcbc3…`), `--set-active=b` | `build/gates/ida-android.sh --go --backup-sha 6bd9c632b262e43c1034da642d07886e0a0a048866a3acdc4e49f426d146f59e --confirm BORRAR-USERDATA` |
| 5 | dueño | `fastboot reboot`; asistente de HyperOS (~15-30 min), opciones de desarrollador, **ADB (y ADB inalámbrico)**; root de Magisk ya en `init_boot_b` | — |
| 6 | yo | Captura con sonido real (el dueño reproduce un tono/sonido del sistema durante 25 s); `adb pull` | `adb push build/android/audio-ref-capture.sh /data/local/tmp/` · `adb shell 'su -c "sh /data/local/tmp/audio-ref-capture.sh 25"'` |
| 7 | dueño + yo | **Vuelta:** tablet a fastboot; `flash userdata` con la copia verificada; `set_active a` (doble a/b/a si hace falta); `reboot` | `build/gates/backup-userdata.sh --restore-plan /var/tmp/uke-userdata-backup/userdata-20261019-105504-fsck.img` |
| 8 | yo | Post: SSH, `misc` a ceros si Android dejó `bootonce-bootloader` (fila propia), ritual `adsp.b40`, `uke-audio`/`uke-bt`/`uke-wifi`; **avisar a las sesiones** | — |
Gates (docs/historia/AGENTS.md): batería ≥ 3700 mV, ≤ 2 escrituras/día y `slot-retry-count:b` ≥ 3 **(la ida son 3 escrituras: erase×2 + misc; pide excepción expresa del dueño a la regla de ≤ 2 por día)**, lector ACM único, una escritura por ciclo con fila pre-registrada.

## Qué avisar a las otras sesiones (texto)
«La tablet uke saldrá de Linux durante ~1-3 h el <fecha/hora> para capturar la referencia de audio en Android (borra y restaura `userdata`; copia verificada). Mientras tanto no hay SSH, BT, WiFi ni escritorio. Antes: terminad lo que estéis haciendo en la tablet y guardad vuestros resultados fuera de ella. Avisaré cuando vuelva Linux; después, comprobad vuestros servicios.»  Destinatarios actuales: `bluetooth-uke-investigac`, `lapiz`, `bateria` (y las que el dueño indique).

## Riesgos
1. **Pérdida del rootfs Linux** si falla la vuelta: mitigado con la copia verificada (también cruda y `.zst`), pero la vuelta debe poder hacerse (`flash userdata` ya hecho dos veces).
2. **Tres escrituras en un día** (> regla de ≤ 2/día): excepción del dueño.
3. `slot-retry-count` y `set_active`: Android puede dejar el slot b en estado raro; vuelta con `set_active a` (LV-R7).
4. Trampa BCB: ya detectada (`misc`); se limpia en la ida y se vuelve a revisar al volver.
5. El asistente de Android puede pedir cuenta/red: se omite; puede alargar.
6. Cargador: en fastboot no carga; ventana corta en fastboot y batería ≥ 3700 mV.
7. Android podría no arrancar (super no verificado: `odm_b` se leyó bien el 18-oct, EROFS válido); si no, vuelta inmediata con la copia.
8. La referencia puede no aclarar la diferencia (coste en horas).

## IDA EJECUTADA (11:07 del 19-oct, por orden expresa del dueño: «ya está en fastboot, puedes flashear»; excepción de 3 escrituras/día autorizada)
Sesiones BT, batería y lápiz avisadas. Gates en fastboot: producto `uke`, slot actual a, `slot-retry-count` a=7 b=6, `unbootable` no/no, batería 4318 mV. `ida-android.sh --go --backup-sha 6bd9c632… --confirm BORRAR-USERDATA`: `erase userdata` OKAY, `erase metadata` OKAY, `flash misc` (8 KiB de ceros) OKAY, `--set-active=b` OKAY. Después `fastboot reboot`. Copia verificada intacta en `/var/tmp/uke-userdata-backup/`. Pendiente: el asistente de Android (dueño), ADB, captura (`audio-ref-capture.sh`) y la vuelta.
