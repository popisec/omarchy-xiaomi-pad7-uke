# Plan de 2 boots — V1: rootfs de Arch por `fastboot flash userdata`

**Escrito 27-sep-2026 después de la revisión adversarial.** Sustituye a B2 (que falló) y no toca
nada de lo que funciona.

## Por qué este plan y no el anterior

B2 escribió el rootfs **con `dd` desde el sistema que estaba corriendo sobre esa misma partición**.
El kernel montado en rw siguió escribiendo journal y bitmap encima de la imagen recién escrita, y el
`sync` final consolidó el superbloque **viejo** de Ubuntu sobre el nuevo. Resultado: bitmap con CRC
malo, `/ukeinit` vio una raíz de Ubuntu, y el sistema arrancó como Ubuntu sin red.

**Nobody is mounted cuando se escribe desde fastboot.** Eso es todo el arreglo.

Además, revisado por dos refutadores adversarios, se aclara dos cosas:

1. 🔴 **El ABL no admite un `boot.img` con ramdisk propio**, pero la causa es otro: el hermano tiene
   el initramfs **incrustado dentro del `Image.gz`** (verificado: el kernel del shell descomprime a
   41 355 776 B y contiene un cpio newc en el offset 32 027 845), por eso todos sus boots têm
   `ramdisk_size = 0`. Y `UBUNTU-BOOT.md §10` del hermano ya documentaba la **ley RAMDISK_SZ**
   (5 muertes con `RAMDISK_SZ>0`: B8, B8c, U1, E1, B7U1; ~20 ciclos vivos con `=0`).
   **No hace falta tocar el `boot.img` para este plan.**
2. 🟢 **El gate de raíz del init del hermano es genérico** — en el arranque de B2 imprimió
   `S123: RAIZ UBUNTU VERIFICADA` y proceeded a `switch_root` **con el rootfs de Arch debajo**. El
   chequeo es del estilo `[ -x /sbin/init ] || …`, y Arch pasa (symlinks usr-merged). Y su init
   levanta **NCM + 192.168.42.129 antes del `switch_root`**, así que la red sube aunque el rootfs
   cambie.

⇒ **Con el rootfs limpio puesto por fastboot, la cadena `s244` arranca Arch sin cambios.**

## Pre-vuelo (0 boots, verificado)

| Gate | Estado |
|---|---|
| Nuestra clave pública está en `/root/.ssh/authorized_keys` de la imagen | ✅ `ssh-ed25519 <CLAVE-PUBLICA>…` coincide con `uke-arch-root.pub` |
| `sshd` habilitado en la imagen | ✅ (`INFORME-A2.md`) |
| Gate de raíz del init del hermano es genérico | ✅ (aceptó el rootfs de Arch en B2) |
| Red antes del `switch_root` | ✅ NCM + 192.168.42.129 (el mismo init) |
| `img2simg` disponible | ✅ `/usr/bin/img2simg` |
| `fastboot flash userdata` con sparse | ✅ probado 3/3 por el hermano (`rootfs.simg` 87 MB, ~21 s) |
| Tamaño no tiene que coincidir con la partición | ✅ (105 GB la partición, 1,2 GB la imagen) |

**Artefacto:** `build/rootfs/arch-rootfs.simg`, **1 207 455 712 B**, sha256
`0cdc7386bb1c1d7d7f6cf2ef6ebe569b7cafbaf0dc38480a96e8dd417898614e`.

## Boot 1 — el que importa

1. **Power cycle a fastboot** (`Power + Vol−` unos segundos). Es lo único que no puedo hacer yo:
   el sistema actual no tiene shell, ni red, ni forma de reiniciarse por software.
2. Gates, en este orden y parando si algo falla:
   ```bash
   fastboot getvar battery-voltage        # ≥ 3700 mV (medido 4248-4273 mV)
   fastboot getvar all | grep -E 'current-slot|slot-retry-count|slot-unbootable'
   sha256sum ~/proyectos/omarchy-uke/build/rootfs/arch-rootfs.simg   # = 0cdc7386…
   ```
   El ledger exige **sha pre-registrado antes de escribir**: apuntar el valor de arriba y los 4
   `slot-retry-count`.
3. **UNA escritura:**
   ```bash
   fastboot flash userdata ~/proyectos/omarchy-uke/build/rootfs/arch-rootfs.simg
   ```
4. `fastboot reboot` — **sin tocar `boot_a`, `boot_b`, `dtbo` ni `vendor_boot`**. Se arranca el slot
   activo (`b`, el par bueno) con la cadena intacta.
5. **Vigilar la consola ACM** (`/tmp/opencode/console-uke.log`; soy el único lector, el capturador
   del hermano está parado). Buscar, en este orden:
   `S123: raiz candidata` → `RAIZ … VERIFICADA` → `X9S123-SWITCH` → banner de Arch.
6. **Entrada:** `ssh -i ~/proyectos/omarchy-uke/build/rootfs/uke-arch-root root@192.168.42.129`
   (⚠️ **nuestra** clave, no `id_ed25519`).

**Criterios de ÉXITO.**
- `cat /etc/os-release | grep PRETTY` → Arch Linux ARM
- `uname -m` → `aarch64`; `uname -r` → `7.2.0-rc2-palawan+`
- `systemctl is-system-running` → running | degraded
- `ssh -i …/uke-arch-root root@192.168.42.129 'uname -m'` → `aarch64` **desde el PC**
- `ls /sys/class/drm /dev/input` → vacío: **esperado**, no es un fallo

**Criterios de FRACASO y qué hacer.**
- (a) No aparece `S123` en la consola ⇒ el problema es la cadena, no el rootfs. → Boot 2.
- (b) Aparece `S123` pero no `X9S123-SWITCH` ⇒ el gate de raíz rechazó la imagen. Leer el mensaje
  exacto antes de nada más: dirá qué comprobó.
- (c) Cambia a fastboot ⇒ slot `b` con reintentos agotados. → Boot 2 para restaurar.

## Boot 2 — solo si el Boot 1 falla: restaurar Ubuntu

```bash
# en el PC: la imagen probada del hermano, 87 MB sparse
fastboot flash userdata ~/gpu-work/ramaa/s22/rootfs.simg     # sha pre-registrado antes
fastboot reboot
```
Devuelve el aparato al estado conocido. **Nunca encadenar un tercer flash el mismo día.**

## Lo que NO se hace en este plan

- ❌ No se toca `boot_a` (queda `unbootable`, sin efecto: nadie lo activa).
- ❌ No se toca `boot_b` ni `dtbo_b` (el par bueno, intacto).
- ❌ No se toca `vendor_boot_b` (la regla del proyecto sigue en pie: la ley RAMDISK_SZ se resuelve
  **incrustando** el initramfs en el `Image.gz`, no parcheando el vendor).
- ❌ No se compila kernel. Este plan no necesita ninguno.
- ❌ No se usa `dd` sobre el fs en uso. **Nunca.**
