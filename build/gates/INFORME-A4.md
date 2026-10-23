# INFORME A4 — auditoría de riesgos del primer boot (F5, grupo B)

Fecha: 2026-09-26/27. Offline, sin tablet, sin flash. Todo lo afirmable está medido en
este PC; el resto va marcado `[NO VERIFICADO]`.

## 1. Todo lo que puede perder la tablet en F5

| # | Pérdida | Causa | Detección temprana | Mitigación |
|---|---|---|---|---|
| 1 | `userdata` Ubuntu (único rootfs útil) | B3 (`dd` Arch) lo sobrescribe por diseño | `DD-RC`, remontaje `ro` sin `/sbin/init` | Seguro `rootfs.img.gz` intacto (sha `b6d54117…`, `gzip -t` OK); re-`dd` ~10 min |
| 2 | `boot_b` bueno | B4 lo sobrescribe; flash a medias | `fastboot` OKAY/FAIL + consola ACM | B1 deja Ubuntu en `boot_a`; `set_active a` (~2 min) |
| 3 | Ambos slots | B1+B4 fallidos + reintentos a 0 (caída a fastboot) | `slot-retry-count` antes/después de cada paso | `fastboot boot` por RAM (sin escribir) + restauración por SSH; ABL intocable |
| 4 | Sesión perdida por BCB sucio | `misc` dice `reboot-bootloader`: el próximo reboot cae a fastboot | releer `misc`, `command[0:32]` | Limpiar `misc` en F0 (paso 6) ANTES de F5; vigía fastboot corriendo |
| 5 | Sesión perdida por fs corrupto | `userdata` ~880 errores; `switch_root`/`mount` falla | `e2fsck` del ukeinit habla por ACM antes de parar | `e2fsck` REAL enlazado en initramfs (gate del §7 de A1); `e2fsck` en frío en F0 |
| 6 | Slot quemado en silencio | Cada arranque fallido gasta 1 reintento; `set_active` olvidado tras flash | 4 contadores registrados por fila | `set_active` al final de cada flash (vuelve a 7); ≤2 escrituras/día; STOP si b<3 |
| 7 | Batería bajo el umbral | fastboot NO carga; UFS a Gear 1 con batería baja ⇒ flash corrupto | `battery-voltage` antes/después | ≥3700 mV + cargador de PARED; si no, solo lectura |
| 8 | Evidencia perdida (falso "sin errores") | Consola 115200 pierde la cola al reset (#428→#429); `dmesg -n 7` olvidado | comparar consola vs `dmesg -w` por SSH | Doble captura siempre; `dmesg -n 7` en el init (ya está en ukeinit-arch) |
| 9 | Colisión inter-proyecto | Hermano con ronda en vuelo (#442); `~/gpu-work` compartido | `check-session-b.sh` paso 1 + leer ledger | Semáforo: sin OK del dueño no se toca nada |
| 10 | `boot_a` dañado por B1 | Flash interrumpido del slot `a` | Arranque de prueba en `a` <60 s (parte de B1) | `boot_b` intacto durante B1; reintentar el flash (idempotente) |

Lo que NO está en riesgo en F5: `abl_*`, `vbmeta`, `vendor_boot_b`, `dtbo_b` (no se
tocan), GPT (solo `set_active`), WiFi/GPU/táctil (no son criterio de F5).

## 2. Los 4 puntos más frágiles de F5 (sin suavizar)

1. **El `by-partlabel/userdata` puede no existir en el initramfs.** Sin udev no hay
   symlinks `by-partlabel`; si el kernel no los puebla vía devtmpfs, el fsck y el mount
   mueren en el primer `fastboot boot`. Es el R1 de A1 y el fallo más probable del
   primer intento. El `die()` hablará por ACM (B2 no escribe nada), pero corrige el
   plan: haría falta resolver por GPT/`blkid` antes del fsck.
2. **El rootfs es un solo punto de fallo sin red de slots.** A/B protege `boot`, pero
   `userdata` es ÚNICO: durante B3-B4 hay una ventana donde ni Ubuntu ni Arch están
   íntegros, y la única red es un `.gz` en el PC + un gadget USB que aún no se ha
   probado con este kernel+initramfs. Si el RNDIS no levanta (R2 de A1) y el `dd` quedó
   a medias, la restauración exige consola ACM + shell de emergencia, no SSH.
3. **F5 depende de F0 y F0 no está hecho.** `misc` sucio + ext4 con ~880 errores +
   fork sin commitear con el experimento `s248` abierto: si el kernel de B4 se
   recompila del árbol actual en vez de reutilizar el `Image.gz` del `s244`, el `s248`
   se cuela en el primer boot y ya no hay "cero variables nuevas". La decisión D20
   (reutilizar el kernel) es load-bearing y hoy es solo una recomendación.
4. **`qbootctl` no existe en la imagen Arch y el slot nunca se marca successful.**
   Sin marcar el slot, cada arranque con fallos de userspace (sin GPU/táctil, reloj en
   1970) gasta reintentos hasta caer a fastboot. F5 no lo instala (no está en ALARM,
   re-archivo AUR pendiente) ⇒ el primer boot tiene un número finito de intentos antes
   de necesitar rescate manual. Mitigación mínima: `qbootctl -m` manual por SSH en
   cuanto haya sesión, antes de instalar nada.

## 3. Qué NO está verificado `[NO VERIFICADO]`

- Tamaño real de la partición `misc` en el aparato: B §4.5 dice 8192 B de ceros,
  REGLAS-PARTICIONES dice `sda12` de 4 MB, y `bcb-clean.bin` son 2048 B. Las tres
  cifras no pueden ser verdad a la vez; medir en el aparato antes de F0-paso 6.
- URL/paquete `qbootctl` para aarch64 (B cita `github.com/linux-msm/qbootctl`; en
  ALARM da 404; el re-archivo AUR no está hecho ni probado en `cliffs`: B §4.4 avisa
  *"may render hardware unusable"*).
- Si el gadget RNDIS levanta en este kernel (`rndis.usb0` in-tree + dwc3 de palawan;
  el nombre de iface puede ser `usb0`/`rndis0`/otro; fallback ECM sin probar).
- `busybox date -s` parsea el formato de `fake-hwclock.data`; `blkid` del busybox
  resuelve PARTLABEL (plan B del punto frágil 1).
- Techo real de `fastboot boot` (~64 MiB, sin fuente primaria) y duración del `e2fsck`
  en frío sobre ~106 GB (no medida; puede ser horas).
- `boot-arch-uke.img` no existe aún: repack, aserciones AVB y sus 5 tokens, pendientes.

## 4. Veredicto

F5 es **razonablemente seguro SI Y SOLO SI** se ejecuta en orden B1→B2→B3→B4 con cada
fila pre-registrada, porque cada escritura tiene vuelta atrás de minutos: B1 regala el
seguro A/B, B2 no escribe nada, B3 se deshace con el `.gz` verificado hoy, B4 con un
`set_active`. El A/B protege el arranque y eso es real, no retórico: el peor caso
recuperable son dos comandos.

Pero el "razonablemente" tiene tres condiciones que hoy NO se cumplen: (a) F0 sin
hacer (`misc` sucio + fs con errores + `s248` abierto en el árbol), (b) el hermano con
ronda en vuelo (#442: semáforo en rojo hasta demostrar lo contrario), y (c) el
`boot.img` Arch sin construir. Con esas tres en rojo, **hoy F5 no se ejecuta: se
prepara**. El rootfs único es el riesgo estructural que ningún gate elimina, solo lo
abarata: un solo `.gz` en un solo disco es un seguro con punto único de fallo, y la
segunda copia es la acción más barata de toda esta auditoría.

`boot-arch-uke.img`: `[NO EXISTE]` — `build/bootimg/` vacío 26-sep-2026.
