# RUNBOOK DE LA MAÑANA — 29-sep-2026 (escrito por ZCode durante la noche)

> ⚠️ **SUPERSEDED 30-sep** — este runbook describe la era K7 (boot_b = K7 experimental), ya
> superada por la serie K8–K16. El runbook VIGENTE es `docs/historia/RUNBOOK-SIGUIENTE.md` + `docs/historia/PLAN-SIGUIENTE-v2.md`.
> No ejecutar nada de aquí sin releer `docs/historia/ESTADO-VIVO.md` antes.

Estado al irte a dormir: **boot_b = K7** (experimental, cmdline armada), **dtbo_b = s258**, tablet
COLGADA tras muerte muda #P17 (ver `docs/historia/ESTADO-VIVO.md` y `build/gates/PRE-REGISTRO-PANTALLA.md` #P17).
El único flash de la noche está gastado; **todo lo de abajo es gratis o solo cuesta tiempo**.

## Paso 1 — El experimento gratis: arranque en FRÍO de K7
1. Mantén **power pulsado ~10 s** hasta que apague (pantalla en blanco/splash → negro).
2. Pulsa power para arrancar. NO entres en fastboot, NO conectes nada raro: el USB al PC como
   siempre (la captura de consola del PC ya está corriendo).
3. Espera 2 minutos.

**Por qué importa**: K7 prueba el bind del apps-smmu a ~1 s (la pieza que falta para la pantalla).
Anoche murió muda — pero ese arranque venía de `fastboot reboot` con la sesión USB del ABL VIVA
(el confundidor #P17). Un arranque en frío repite el MISMO experimento con el handoff limpio,
como arranca Android. Puede salir:
- **A. Llega SSH** (`ssh root@192.168.42.129` funciona o aparece /dev/ttyACM0 con log): díme
  **"ya arrancó K7"** y NO toques nada más — el runbook post-SMMU (DPU→card0→modetest) lo
  ejecuto yo desde SSH.
- **B. Muere muda otra vez** (pantalla parada, sin USB limpio): K7 queda refutado también en
  frío. Ve al paso 2.
- **C. Caída a fastboot** (battery-soc aleatorio): vuelve a `fastboot reboot` NO — en su lugar
  apaga con power largo y arranca en frío otra vez (1 reintento); si vuelve a caer, pasa al paso 2.

## Paso 2 — Restaurar el par seguro (solo si B/C)
```
fastboot flash boot_b  build/backup-par-bueno/boot_b-lee.img   # ffff8c51… (s244-bounce)
fastboot flash dtbo_b  <s229>   # d2a29ea5… (ubicación: build/backup-par-bueno/ o gpu-work/ramaa/s21)
fastboot reboot
```
Con eso la tablet vuelve al estado "arranca sano con SSH" de ayer, y seguimos con los planes
B/C (preservación total del handoff / parche estilo ChromeOS — informes R1 y R4 en
`build/gates/revision/`).

## Paso 3 — Con SSH vivo (A, o tras restaurar): salud del disco ANTES de instalar nada
El rootfs ext4 da errores. Ejecutar el runbook `build/gates/prepara/P7-fsck-f9.md` (vía
/forcefsck + fs_passno, sin flashear) ANTES de instalar Omarchy (P6) o iterar más.

## Paso 4 — Con SSH vivo: los extras GRATIS (0 flashes), en este orden
1. **F9-E0**: medir `vendor_boot_a`/`init_boot_a` (P7 las cree BORRADAS — causa probable del
   slot A mudo). Comandos en `prepara/P7-fsck-f9.md` Parte B.
2. **e2fsck** vía P7-A (backup → remount ro → `nohup setsid e2fsck -f -y`) — ANTES de instalar
   nada grande. systemd-fsck NO vale (medido que se salta).
3. **Cadena ADSP + batería**: instalar los módulos YA compilados (copias a prueba de
   reinicio en `build/pkg/modules-uke-k7/` — 24 .ko con vermagic correcto; el set completo
   sigue en `/var/tmp/uke-k1-build`) y ejecutar `prepara/uke-adsp-load.sh` → battmgr con
   datos reales + rotación (libssc ya en rootfs: `monitor-sensor --accel`).
4. **Táctil**: `insmod prepara/novatek/ext/novatek-nt36xxx-spi-ext.ko` + `test-touch.sh`.
5. **WiFi**: payload completo en `build/pkg/uke-wifi-payload.tar.gz` (16 firmwares + 28
   módulos) — plan y discriminador D1 en `prepara/P3-wifi.md`.
6. **Omarchy**: `prepara/install-omarchy-uke.sh` (dry-run primero; gate EXT4 incorporado).

## Lo preparado esta noche (todo en `build/gates/`, TODO verificado en disco)
- `revision/R1-smmu-kseries.md` — auditoría UKE-POKE + GO a K7 + bug ALTA (NUNCA unbind)
- `revision/R2-display-cadena.md` — runbook SMMU→re-bind panel→card0→modetest (ojo CM3)
- `revision/R3-vendor-diff.md` — diff vendor (handoff-smrs, SIDs, timeline Android)
- `revision/R4-nuevas-vias.md` — vías H/C/I + kgsl-smmu independiente para la GPU
- `prepara/P1-rotacion.md` (libssc/QRTR) · `P2-lapiz.md` (+ novatek/ con .ko) ·
  `P3-wifi.md` (+ wifi-test.sh) · `P4-bluetooth.md` · `P5-energia.md` (+ scripts batería) ·
  `P6-omarchy-install.md` (+ install-omarchy-uke.sh) · `P7-fsck-f9.md` ·
  `P8-audio-perifericos.md`
- 857 módulos kernel compilados en `/var/tmp/uke-k1-build` (battmgr, ADSP, lsm6dsx, ath11k…)
- K8 diseñado (#P21 en PRE-REGISTRO): port del handoff — si K7 frío muere, mañana se compila.
