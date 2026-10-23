# Pre-registro ledger F5 — filas escritas ANTES de cada escritura en la tablet

Formato copiado de las entradas #433 (pre-registro con artefacto+sha), #435 (rollback
verificado) y #440 (pre-registro offline con criterios y vuelta atrás) de
`~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`.
**Tres escrituras previstas ⇒ tres filas.** Cada fila se pega al ledger del hermano
ANTES de ejecutar su comando. Nada de lo de abajo se ha ejecutado.

> Prerrequisitos comunes a las tres (ver `check-session-b.sh`): semáforo inter-proyecto
> en verde (ledger sin sesión viva, `ESTADO-ACTUAL.md` del hermano leído), batería
> ≥ 3700 mV, cargador de PARED conectado, 4 `slot-retry-count` registrados, consola ACM
> armada con UN solo lector, vigía fastboot corriendo y pausado durante el flash.
> `build/bootimg/boot-arch-uke.img` construido y con sha medido (hoy NO existe).

---

## F5-B1 — PRE-REGISTRO: copia del par bueno al slot `a` (seguro A/B)

**Artefacto.** `~/gpu-work/ramaa/s21/avb/boot-s244-bounce.img` sha256
`ffff8c51265ff03c84cff15ffdb275f396a666a491eb5d67580be705321db99e`
(100663296 B, medido 26-sep-2026, ver `build/gates/SHA-BUENOS.txt`).
**`dtbo_a` NO se toca** (el dtbo del vendor ya está en ambos slots; el `s229` es
overlay sobre él y `boot` es lo único que cambia de verdad en F5).

**Una sola variable:** el contenido de `boot_a` (pasa de desconocido/stock al `s244`
que hoy arranca en `boot_b`). Nada más cambia.

**Comando (NO ejecutado).**
`fastboot flash boot_a ~/gpu-work/ramaa/s21/avb/boot-s244-bounce.img` ·
relectura: `fastboot` no devuelve el contenido, así que verificación por arranque:
`fastboot set_active a` + `fastboot reboot` + SSH <60 s + `uname -r` =
`7.2.0-rc2-palawan+`, y vuelta a `set_active b`.

**Criterios.**
- ÉXITO: SSH en slot `a` <60 s, kernel #82, `slot-retry-count:a` = 7 tras el `set_active`.
- FALLO: no hay SSH en 90 s ⇒ `set_active b` + `reboot` (el slot `b` no se tocó) y la
  fila se cierra como fallida; no se sigue a B2 ese día.

**Coste en reintentos.** 1 escritura fastboot + hasta 2 arranques (≈2 reintentos del
slot `a`; el `b` queda intacto). Registrar los 4 contadores antes y después.

**Vuelta atrás.** Ninguna necesaria: `boot_b` sigue siendo el par bueno. Si el flash
de `boot_a` quedó a medias, se repite el mismo comando (idempotente).

---

## F5-B3 — PRE-REGISTRO: escritura del rootfs Arch en `userdata` (abandono de Ubuntu)

**Artefacto.** `build/rootfs/arch-rootfs.img.gz` sha256
`bca709a275c1c23c0b7bed3789e63be1ab04f19b0401b5ec3cc5f53edca5e112`
(403133197 B, `gzip -t` OK, magia ext4 verificada; ver `SHA-BUENOS.txt`).
Servido por HTTP desde el PC (`python3 -m http.server`), escrito por SSH con el
canal que ya funcionó (`uke-fase2-install.py`): `wget -O - … | zcat | dd
of=/dev/disk/by-partlabel/userdata bs=4M conv=fsync`.

**Una sola variable:** el contenido de `userdata` (Ubuntu → Arch). El `boot_b` en este
punto SIGUE siendo el `s244` de Ubuntu: si el `dd` falla, la tablet sigue arrancando
Ubuntu del slot `b` contra un userdata a medias (recuperable por el mismo canal).

**Gates previos en la tablet (abortan el `dd`):** `[ -b /dev/disk/by-partlabel/userdata ]`,
magia ext4 (`53ef`) en el destino, `sync` antes y después (reglas 5 y 10 de docs/historia/AGENTS.md).

**Criterios.**
- ÉXITO: `DD-RC=0` + remontaje `ro` SIN `noload` con `/sbin/init` y `/etc/hostname`
  visibles + `sync`.
- FALLO: `DD-RC!=0` o el remontaje no muestra `/sbin/init` ⇒ NO se sigue a B4; se
  reintenta el `dd` o se ejecuta la vuelta atrás total (ver ROLLBACK.md). Un `userdata`
  a medias NO es un brick: el seguro está en el PC.

**Coste en reintentos.** 0 reintentos de slot (no es escritura fastboot, no toca slots).
Coste real: tiempo de transferencia (~384 MiB por RNDIS) + 1 reinicio de verificación.

**Vuelta atrás exacta.** El MISMO comando con el seguro:
`busybox wget -O - http://192.168.42.1:8000/rootfs.img.gz | busybox zcat |
busybox dd of=/dev/disk/by-partlabel/userdata bs=4M conv=fsync; sync`
(`rootfs.img.gz` sha `b6d5411712b…`, 369822577 B, `~/gpu-work/ramaa/s22/`).
Verificación: remontar `ro` y ver el `/etc/hostname` de Ubuntu.

---

## F5-B4 — PRE-REGISTRO: flash de `boot_b` Arch + `set_active b` (primer boot)

**Artefacto.** `build/bootimg/boot-arch-uke.img` sha256 `[PENDIENTE: no existe aún;
pegar aquí el sha medido antes de flashear]` — shell `boot-s244-bounce.img`
(`ffff8c51…`), kernel = el mismo `Image.gz` del `s244`, initramfs `ukeinit-arch`,
cmdline del `s244` con SOLO el token `rdinit` cambiado. Todas las aserciones del
repack (AVB0/AVBf, header v4, 5 tokens, footer idéntico) en verde ANTES de esta fila.

**Una sola variable:** el contenido de `boot_b` (kernel+initramfs de Ubuntu → de Arch;
el kernel binario es el MISMO, solo cambia el initramfs y `rdinit`).

**Comando (NO ejecutado), en este orden:** `fastboot flash boot_b boot-arch-uke.img`
(con sha pre-registrado AQUÍ antes de escribir) → `fastboot set_active b` → `reboot`.
**Nunca al revés** (activar antes de escribir deja al ABL sin `boot.img` válido).

**Criterios (todos, o no es un boot):** `uname -m` = aarch64 · `uname -r` =
`7.2.0-rc2-palawan+` (el MISMO) · `/etc/os-release` = Arch · `systemctl
is-system-running` = running|degraded · `usb0` = 192.168.42.129 · SSH desde el PC ·
consola ACM completa sin truncar.

**Coste en reintentos.** 1 escritura + 1 arranque (≈1-2 reintentos del slot `b`).
**Límite del día: ≤ 2 escrituras/día contando B1.** Si `slot-retry-count:b` < 3,
este ciclo NO se ejecuta (solo lectura).

**Vuelta atrás exacta.** Parcial: `fastboot set_active a` + `reboot` (Ubuntu intacto
gracias a B1, ~2 min). Total (si B3 también quedó mal): parcial + re-`dd` del
`rootfs.img.gz` de Ubuntu (~10 min). Detalle en `ROLLBACK.md`.
