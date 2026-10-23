# Runbook: vuelta a Linux con L76R (ledger #654, pre-registrado, NO ejecutado)

Escribe dos particiones: `userdata` ← rootfs Arch 8 GiB (`7e4309f0…`) y `boot_a` ← L76R (`f75a27fd…`).
**Escribir userdata borra el Android actual** (apps y datos de HyperOS).

## Lo que hace el dueño
1. **Decidir** si se puede perder el Android actual (sus apps/datos). Si hay algo que guardar, sacarlo antes.
2. **Cable USB-C de la tablet al PC.** fastboot no funciona por WiFi. (Durante el flash no hay cargador:
   un solo puerto. La batería está ~99 %, de sobra; en fastboot no carga.)
3. **Arrancar la tablet en fastboot**, a elegir:
   - desde el PC, con la tablet aún en Android: `adb -s 192.0.2.13:5555 reboot bootloader`;
   - o a mano: apagar y encender con Power + Volumen-abajo.
   Comprobar en el PC: `fastboot devices` muestra el aparato.
4. **Dar la orden** de ejecutar (Claude lanza los pasos de abajo).
5. **Tras el arranque de Linux**: conectar el **cargador de pared** (≥45 W) y mirar la pantalla:
   decir si hay **contenido** (texto de consola), **negro con luz** o **sin luz**.

## Lo que ejecuta Claude con la orden
```bash
bash build/gates/uke-consola-lector.sh                    # lector ACM unico (regla: nunca arrancar sin lector)
sha256sum build/rootfs/rootfs-uke-l76-8g.img build/bootimg/boot-uke-k52L76r.img
CONFIRMO_BORRAR_ANDROID=1 bash docs/historia/gates-palawan/flash-userdata-l76r-gated.sh
```
El script aborta sin escribir si falla cualquier gate: sha de rootfs/boot/dtbo, batería ≥3700 mV, `slot-retry-count:b` ≥3,
lector ACM vivo. Cada `fastboot flash` comprueba su código de salida; si userdata falla no toca boot_a, y si boot_a falla
no hace set_active ni reboot. Después del reboot espera ~75 s, entra por SSH (RNDIS 192.168.42.129) y mide:
- 19 gates de paridad con el vendor (`L76-GATES: n PASA / m FALLA`), incluido `UKE-L76-RAIL` (ciclo de rieles);
- 4 gates de CARGA (`CARGA-GATES`): adsp running, PDR, Charging/Full, sha adsp.b40;
- guarda-flood (DPMS off si >1500 líneas S4-DIAG).

## Si algo va mal
- **No hay SSH**: el lector ACM guarda la consola en `/var/tmp/uke-sesion-console.log`.
- **Rollback del kernel**: `fastboot flash boot_a build/backup-par-bueno/android-20261017/boot_a.img` (L74) o L76 `1db4bd34`.
- **Volver a Android**: `fastboot set_active b` + `fastboot erase userdata` + `fastboot erase metadata` y reboot (LV-R1).
- Ledger: rellenar el Resultado #654 con lo medido (Claude).
