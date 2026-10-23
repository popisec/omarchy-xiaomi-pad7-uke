# BARRIDO FASE 1 — 2026-10-09 (dueña del arranque + volcado particiones raw)
- Inicio: 2026-10-09 (CEST). Tablet en fastboot AHORA: device SERIE0001, current-slot a.
- Rol: ÚNICA dueña de consola. PROHIBIDO flashear/set_active/escribir/reboot -f/sysrq/userdata/super.
- Script consola hermano: ~/proyectos/ubuntu-permanente/bin/uke-console-cap.sh (reabre /dev/ttyACM0 en bucle, log ~/proyectos/out/uke-ubuntu_console.log).

## Paso 0 — estado inicial
- `fastboot devices` → SERIE0001 fastboot; `getvar current-slot` → a; /dev/ttyACM0 NO existe (esperado: solo aparece con Linux arrancado).

## Paso 1 — lector de consola armado
- 2026-10-09 02:50:10 CEST: script hermano lanzado como proceso background (pid 333990, verificado con ps).
- Comando: terminal background ~/proyectos/ubuntu-permanente/bin/uke-console-cap.sh (equivale a setsid nohup … &).
- Log destino: ~/proyectos/out/uke-ubuntu_console.log (preexistente 10345614 bytes, sep-28; el script hace append + reabre /dev/ttyACM0 cada 1s).
- Soy la ÚNICA lectora: verificado que no había otra instancia antes (ps vacío).

## Paso 2a — estado fastboot previo (solo lectura)
- battery-voltage 4027 mV (gate ≥3700 OK), battery-soc-ok yes.
- current-slot a, retry a:7 b:7, successful a:no b:yes, unbootable a:no b:no.
- unlocked yes, secure yes, product uke, serialno SERIE0001, kernel uefi, is-userspace no.
- `getvar all` completo capturado arriba (nota: aquí NO hay particiones xbl genéricas sin sufijo _a/_b; sí xbl_a/b, tz_a/b, abl_a/b, hyp_a/b, keymaster_a/b, qupfw_a/b, aop_a/b 0x80000=512K, aop_config_a/b 0x80000).
- Tamaños lista de volcado: aop_a/b 512K, xbl_a/b 8M, tz_a/b 4M, abl_a/b 8M, hyp_a/b 8M, keymaster_a/b 512K, qupfw_a/b 128K, + candidatos xbl_config_a/b 512K, devcfg_a/b 256K, uefi_a/b 5M (estos últimos solo si hace falta; uefi 5M es grande pero raw pequeño — decidir tras inventario).
- PROHIBIDOS intactos: userdata (0x1A767FB000), super (0x2A0000000), system — no se tocan.

## Paso 2b — reboot emitido
- 2026-10-09 02:50:16 CEST: `fastboot reboot` → OKAY. Espero SSH en 192.168.42.129 (timeout 10 min).

## Paso 2c — espera SSH: TIMEOUT 10 min AGOTADO (sin SSH)
- Reboot: 02:50:16 CEST. Última comprobación: 03:00:40 CEST (>10 min). Resultado: SIN SSH.
- Serie temporal (journal PC + sondeos):
  - 02:49:03 tablet en fastboot (18d1:d00d, s/n SERIE0001, bus 3-3, dev 40).
  - 02:50:16 `fastboot reboot` → OKAY; kernel PC: "usb 3-3: USB disconnect, device 40".
  - 02:50:17 dos intentos de enumeración full-speed en 3-3 (dev 41, 42) con "device descriptor read/64, error -71" (EPROTO). Típico del PHY USB reseteándose en transición bootloader→kernel.
  - 02:50:17→03:00:40 SILENCIO USB TOTAL: ningún evento en journal, `lsusb` sin rastro (ni 18d1, ni 2717, ni 05c6:9008 EDL), /sys/bus/usb/devices/3-3 inexistente (puerto eléctricamente vacío), /dev/ttyACM0 jamás apareció, sin interfaz NCM (sin 192.168.42.x en el PC), ping NO, ssh timeout, `fastboot devices` vacío.
- Consola: log ~/proyectos/out/uke-ubuntu_console.log SIN bytes nuevos (10345614 antes y después) — coherente: el gadget acm.usb0 nunca enumeró, no había nada que leer. Lector único verificado (solo mi instancia, pid 333990); se DEJA CORRIENDO para no dejar el buffer sin lector (bug X9DUMP-block) y capturar si la tablet re-enumera.

## Paso 3 — verificación testbed: NO EJECUTADA (sin SSH)
- Corrección recibida: verificación = `uname -a` + `cat /proc/cmdline` + `uptime`. Pendiente de un arranque con SSH.

## Paso 4 — inventario particiones: PARCIAL (solo cara fastboot)
- `getvar all` previo completo (ver paso 2a). /proc/partitions + /dev/disk/by-partlabel PENDIENTES (requieren SSH).

## Paso 5 — volcado raw pequeñas: NO EJECUTADO (sin SSH)
- Destino preparado: ~/proyectos/omarchy-uke/build/evidencia/aop-dump-20261009/ (vacío).
- Lista prevista (de getvar): aop_a/b 512K, aop_config_a/b 512K, xbl_a/b 8M, xbl_config_a/b 512K, tz_a/b 4M, abl_a/b 8M, hyp_a/b 8M, keymaster_a/b 512K, qupfw_a/b 128K, devcfg_a/b 256K. PROHIBIDOS: userdata/super/system.

## DIAGNÓSTICO (FASE 1 bloqueada aquí)
- Hecho: tras `fastboot reboot` sobre slot A (retry 7:7, successful_a=no), la tablet NO re-enumeró USB en ninguna forma durante >10 min: ni fastboot, ni gadget Linux (ACM+NCM), ni EDL 9008. Puerto USB del PC vacío a nivel eléctrico.
- Descartado: batería (4027 mV, gate OK), cable/puerto (fastboot funcionaba 1 min antes en el mismo puerto), doble lector de consola (uno solo).
- Dato relevante: slot-successful:a=no — el testbed de slot A NUNCA marcó un arranque bueno. Hipótesis principal: la imagen de slot A cuelga/muere antes de inicializar el gadget USB (p. ej. panic temprano sin consola o fallo XBL/ABL al cargar boot_a). Hipótesis secundaria: tablet apagada/colgada dura con PHY USB caído.
- NO toco nada más (prohibido cambiar de slot, forzar reboot o re-flashear). Decisión siguiente para el coordinador: inspección física (pantalla/LED), pulsación larga de power o re-enchufar cable; si vuelve a fastboot, leer `getvar slot-retry-count:a` (¿decrementó?) y valorar siguiente paso. FASE 1 queda: pasos 3/4/5 pendientes de un arranque con SSH.
- Lector de consola: SIGUE ACTIVO (pid 333990) como único lector.
