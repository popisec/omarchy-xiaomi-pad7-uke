# FS: estado real, limpieza segura y plan de cold-boot para resize — 13-oct-2026

Sesión SSH como root a `192.168.42.129` (RNDIS). Cero flashes, cero reinicios, cero desmontajes.
Lecturas: `tune2fs -l`, `dumpe2fs -h`, `blkid`, `dmesg`, `df`/`du`, cpio de initramfs en local.
Escrituras: solo `journalctl --vacuum`, `rm` de `.cache` + 1 coredump, `sync`.

## 1. Corrección a la premisa: cuál es el init REAL

- La cmdline viva lleva **`rdinit=/ukeinit`** (y `init=/init` ignorado mientras haya rdinit).
- **No existe `build/init/ukeinit`** en el repo. El init real es **`build/gates/ukeinit`**
  (linaje fork-shell s118→s172→K50/K51, emite `X9S181`/`S123`), embebido como `/ukeinit`
  en los cpio (`uke-k22`, `uke-k52b2-diag` lo traen; verificado con `cpio -t`).
- **`ukeinit-arch` NO se usa**: no está en ningún cpio ni en ninguna imagen flasheada.
  Su bloque "e2fsck REAL obligatorio + die() si falta" es letra muerta hoy.
- Prueba en vivo: `dmesg` muestra el flujo S123 (`mount ro,noload` → `remount rw` →
  `X9S123-SWITCH`) y `dumpe2fs` dice `Last mounted on: /mnt/ubuntu` (punto de montaje
  exclusivo del init de gates; `ukeinit-arch` usaría `/newroot`).

## 2. Estado real del FS (medido hoy)

| Dato | Valor |
|---|---|
| Device / PARTLABEL | `/dev/sda32`, `userdata`, `uke-root`, UUID `4bf2908c-…` |
| Tamaño partición | **113 657 229 312 B ≈ 105,8 GiB** (`blockdev --getsize64`) |
| Tamaño FS | **4,0 GiB** exactos (1 048 576 bloques × 4 KiB) |
| Tipo efectivo | **`ext2` sin journal** (`blkid TYPE="ext2"`, features sin `has_journal`; montado como `ext4 … norecovery`) |
| Estado superbloque | **`not clean with errors`**, `Errors behavior: Continue` |
| Contador de errores | **53 → 55 durante esta sesión** (ver §4) |
| `Last checked` | **3-oct-2026** (hace 10 días; `mount count 20`, `max -1`, `interval none` = nada lo re-chequea solo) |
| Primer/último error sellado | `__ext4_new_inode` (25-sep 02:33) / `ext4_mb_generate_buddy` (25-sep 13:49), `EFSCORRUPTED` |
| Grupos citados en FASE0 | 14/15/18/19/26, `block bitmap and bg descriptor inconsistent` (este boot no los re-emite en dmesg: el daño está sellado en bitmaps, no en el log vivo) |
| Funcionalidad online | `resize_inode` presente (el grow es posible); e2fsck + resize2fs **1.47.4** en el rootfs |
| Espacio (antes) | `Size 4.0G Used 3.5G Avail 259M Use% 94%`; bloques libres 118 305; inodos libres 155 083/262 144 (41 %) |

Lectura: FS de 4 GiB sobre partición de ~106 GiB, **sin journal**, con bitmaps de grupos
corruptos desde el 25-sep (apagones sucios del SoC sin sync) y **sin ningún fsck desde el
3-oct**. El `e2fsck -f -p` que prometen las notas **no corre en este boot**: el cpio
`uke-k22` (linaje del boot vivo) **no contiene `/bin/e2fsck-k50`** — solo el cpio
`uke-k50-fw-fsck` lo trae (verificado por `cpio -t`). En `dmesg` no hay ni una línea `K50`,
y el kernel avisa: `mounting unchecked fs, running e2fsck is recommended`.

## 3. Backup previo (hecho y verificado ANTES de escribir nada)

Destino local: `build/backup/tablet-20261013/` (PC con 238 GB libres).

- `etc-root-config-20261013.tar.gz` (2,3 MB, **1526 entradas**,
  sha256 `9d1270a4…581b60`): `/etc` completo (incl. `ssh_host_*`, `hostname`, `fstab`),
  `/root/.config` (con `hypr/hyprland.lua`), `/root/.ssh`, `/root/diag`,
  `/root/*.log|*.txt|*.sh|*.py`, `/var/lib/systemd`. Verificado por listado
  (`hyprland.lua` ×2 —también en `/etc/skel`—, 4 `ssh_host_*`, `esd-timing.log`).
- `pacman-list-20261013.txt` (862 líneas): `pacman -Qqn` + `pacman -Qqe` (510 paquetes).
- Qué NO se puede perder y dónde está: todo lo crítico vive **en el propio sda32**
  (`/etc`, `/root/.config/hypr`, host keys SSH). No hay segunda partición segura donde
  copiar dentro de la tablet (`sda30`/rescue la usa el recovery de Android; `/tmp` es
  tmpfs volátil). El backup en el PC **es** la red de seguridad.
- `/lost+found` vacío: no hay inodos huérfanos pendientes de reclamar.

## 4. Limpieza segura ejecutada (cifras antes/después)

| Acción | Antes | Después |
|---|---|---|
| `journalctl --vacuum-size=20M` | `journal 113M`, `Archived…take up 112.8M` | `take up 16M`, dir 17M (**−96,8 MB** en ficheros) |
| `rm -rf /root/.cache/*` | 2,5M | 4,0K |
| `rm` 1 coredump `eglgears_wayland` (el SIGSEGV de FASE0 §0.1) | 1,1M | fuera |
| `df /` (tras `sync`) | **Avail 259M, 94 %** | **Avail 266M, 94 %** |
| Bloques libres (superbloque) | 118 305 | 119 535 (+1230 ≈ +5 MB) |

**Anomalía importante (evidencia a favor del fsck urgente)**: se borraron ~100 MB de
ficheros pero el contador de bloques libres solo subió ~5 MB, y `du -xs /` (3,07 GiB)
difiere de `df Used` (3,5 GiB) en ~400 MB aun descontando reserva de root (205 MB).
Sin ficheros borrados-abiertos grandes que lo expliquen (solo memfds/shm pequeños).
Lectura honesta: con los bitmaps de los grupos 14/15/18/19/26 corruptos, **la contabilidad
de espacio no es fiable hasta que e2fsck la reconstruya**. El espacio "liberado" real lo
dirá el fsck, no `df`.
**El contador de errores subió 53 → 55 durante la sesión** (que incluyó las escrituras del
vacuum/rm y el tráfico normal de journald/sddm): el FS sigue degradándose en vivo.

No tocado (documentado como candidato, fuera del alcance seguro de hoy): caché pacman ya
limpia (12K); `/usr/share/locale` 227M + `doc` 114M + `man` 72M (propiedad de pacman,
romperían `-Qk`; restaurarlos exige red+espacio — mejor podarlos **horneando un rootfs
nuevo**, no en vivo); `/usr/include` 185M (necesario para compilar en la tablet);
`esd-timing.log` 3,9M en `/root` (evidencia referenciada por sesiones; ya respaldado).

## 5. ¿Resize online HOY? **NO.**

1. FS en estado `not clean with errors` con 55 errores sellados y contador subiendo →
   `resize2fs` sobre bitmaps corruptos puede reubicar bloques ocupados como libres.
2. Sin journal no hay red de replay si el grow online se interrumpe (p. ej. otra muerte
   del SoC a mitad de la reescritura de descriptores de grupo).
3. La contabilidad de bloques es incongruente (§4): ni siquiera se puede verificar el
   resultado del resize contra `df` de forma fiable.
4. Regla del proyecto: reparar antes de redimensionar. **El orden es (a) fsck en frío →
   (b) resize**, sin excepciones.

## 6. Plan de cold-boot (qué hace el init y qué hay que cambiar)

**Lo que hace el init actual al arrancar** (verificado en `dmesg` vivo + código):
S123 espera partición >20 GB → `mount -o ro,noload` → verifica init → `remount rw` →
`switch_root`. **Fsck: NO** (cpio sin `e2fsck-k50`; el bloque K50 de `build/gates/ukeinit`
se salta en silencio). **Resize: NO** (ningún init lo implementa).

**Pasos propuestos (1 flash, con gates del proyecto: batería ≥3700 mV, slot-retries,
consola ACM + `dmesg -w` en doble captura, `sync` antes de reset):**

1. **Rebuild del boot.img con initramfs que SÍ lleve fsck**: reutilizar el precedente
   `L19fsck`/`#602` (cpio `uke-k50-fw-fsck`, que ya trae `/bin/e2fsck-k50`) o re-empaquetar
   el cpio del kernel actual añadiéndole el binario. El bloque K50 ya existe en
   `build/gates/ukeinit:250-261` (`e2fsck -fy`, `rc 0/1` sigue, `2` reboot, `4+` parada
   manual sin bucle). Ojo: K50 corre `-fy` **sin `-f` forzado general** sobre un fs sin
   journal y con 55 errores — prever que pida el reboot de `rc=2` y que `rc=4` deje la
   tablet en shell de emergencia (recuperable por SSH/RNDIS, no es brick: no toca slots).
2. **Verificar en el siguiente SSH**: `tune2fs -l` debe decir `clean`, `Error count`
   congelado, y `df`/`du` reconciliados (el §4 da el test: el gap de ~400 MB debe cerrar).
3. **Resize, dos opciones equivalentes; recomendada (b)**:
   - (a) Online tras boot limpio: `resize2fs /dev/sda32 8G` primero (crecimiento por
     etapas 4→8→16G, verificando `tune2fs` entre pasos), luego al tamaño objetivo
     (p. ej. 16–32G; no hace falta reclamar los 106G de golpe y un FS menor se chequea
     más rápido). Cero flashes adicionales.
   - (b) Offline en el propio initramfs (más seguro: FS desmontado): añadir tras el
     bloque K50 un `resize2fs -p /dev/$UBUNTU <tamaño>` condicionado a `rc` 0/1 del
     fsck. Requiere enlazar `resize2fs` en el cpio igual que `e2fsck-k50`.
4. **Endurecer para el futuro** (mismo flash o el siguiente): fijar `SystemMaxUse=20M`
   en `journald.conf` del rootfs (el journal volvió a 17M hoy pero sin límite volverá a
   crecer), y valorar `tune2fs -O has_journal` en frío (daría journaling real; hoy el FS
   es ext2 efectivo y cada muerte sucia es corrupción directa) — opcional, documentar
   decisión aparte.
5. **Restricciones vigentes hoy**: `slot-retry-count:a = 7` (ESTADO-VIVO 12-oct; un ciclo
   fallido más puede volcar a slot B) y batería 3543 mV < gate 3700 → **cargador de pared
   y `set_active a` + reboot tras el flash**, como marca el protocolo.

## 7. Resumen operativo

- FS: `not clean`, 55 errores, bitmaps corruptos (grupos 14/15/18/19/26), sin fsck desde
  el 3-oct, sin journal (ext2 efectivo), 4 GiB usados de ~106 GiB de partición.
- Backup crítico en PC verificado (tar 1526 entradas + sha + lista de 510 paquetes).
- Recuperado hoy: journal −96,8 MB en fichero (pero `df` solo +7M por bitmaps corruptos),
  `.cache` y 1 coredump fuera. `259M → 266M`, sigue al 94 %.
- El boot actual NO hace fsck (cpio sin `e2fsck-k50`; `ukeinit-arch` no se usa en
  ninguna imagen). El resize online hoy es **inseguro**: esperar al cold-boot con
  initramfs-fsck (precedente L19fsck/#602), verificar `clean`, y entonces resize
  (online por etapas u offline en el init).
