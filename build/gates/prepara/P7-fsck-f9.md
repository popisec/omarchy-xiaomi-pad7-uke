# P7 — (A) runbook del `e2fsck` en frío SIN flashear + (B) síntesis forense del bloqueo F9

**Agente:** P7-FSCK-F9 · **fecha:** 29-sep-2026 (madrugada) · **estado:** preparado sin tablet
(0 escrituras, 0 flashes, 0 adb/fastboot/ssh). Todo lo de abajo es lectura de disco + análisis;
lo que no he podido medir va marcado **NO VERIFICADO** con la medición que lo cierra.

**Fuentes primarias usadas** (todas leídas en disco):

| Fuente | Para qué |
|---|---|
| `docs/historia/ESTADO-VIVO.md` (líneas 1–83) | estado real de la tablet (K7 en `boot_b`, fs degradado, runbook de la mañana) |
| `F-plan-por-fases.md` §F9 (579–604) y riesgo nº1 (1403, 1544) | definición del bloqueo y criterio de «hecho» |
| `build/gates/PRE-REGISTRO-F5-B1.md` (1–120, 946–1011, 1022–1097, 1101–1164) | los 4 mudos, shas de lo flasheado a `boot_a`, resultado del aislamiento |
| `~/proyectos/out/k6-migas.log`, `k6b-migas.log`, `build/gates/k2-migas-log.txt` | errores ext4 reales y por qué `systemd-fsck` no corre |
| `build/rootfs/arch-rootfs.img` + `dumpe2fs -h` | tamaño/features REALES del fs de `userdata` |
| `build/rootfs/staging/etc/fstab`, `usr/lib/systemd/system/systemd-fsck-root.service` | por qué la vía 1 no puede funcionar |
| `build/init/ukeinit-arch` (233–276), `build/bootimg/mkarch-initramfs.py` (84–96) | plan C: el initramfs de Arch SÍ trae e2fsck |
| `~/gpu-work/ramaa/s21/rescue-dump/s175-initramfs/ukeinit` (s181 real) + `dump-log.sh` | qué hace HOY el init que corre (monta `ro,noload`, no hace fsck) |
| `unpack_bootimg` sobre `boot-ukek6/7`, `boot-pokes`, `boot_b-lee`, `vendor_boot-stock`, `init_boot-stock` | anatomía REAL de la cadena de arranque (esto cambia F9) |
| `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` #236/#238/#241/#275/#303/#384/#385/#431/#444 + `build/gates/REVISTA-PROYECTO-HERMANO.md` §1.2–1.6 | historia del slot A, `erase`, AVB, vendor_boot |
| `build/slot/PROCEDIMIENTO-SLOT.md`, `out/getvar-all-t2.log` | tamaño de particiones y semántica de los flags de slot |

---

## 0. Resumen ejecutivo (las dos respuestas)

- **A — vía de fsck SIN flashear, recomendada:** **SSH vivo → backup mínimo → `mount -o remount,ro /`
  → `e2fsck -f -y -v /dev/disk/by-partlabel/userdata` lanzado con `nohup setsid` (no en primer plano)
  → `e2fsck -fn` ×2 = rc 0 → `sync` → reboot**. Es viable y es la única vía sin flash que repara de verdad:
  `e2fsck` **sí** procede sobre un fs montado *read-only* si se le pasa `-f` (rama de aviso, no de aborto:
  `check_mount()` de e2fsprogs 1.47.4). Lo que **NO** sirve es la vía systemd-fsck: está medido en
  `k6b-migas.log:1918` que `systemd-fsck-root.service` se **salta** con `ConditionPathIsReadWrite=!/`
  porque el init monta `/` rw antes de systemd. Detalle y comandos en §A.
- **B — hipótesis F9 más probable (con ranking y experimento que la cierra):** **H1: el slot A no está
  mudo «por la imagen nueva» sino porque le faltan `vendor_boot_a` (DTB + ramdisk vendor) e `init_boot_a`
  (el ramdisk donde vive `/ukeinit`), borradas por el `erase` del 24-sep del proyecto hermano (#384/#385)
  y nunca restauradas.** Las cuatro pruebas fueron «arrancar desde A», no «arrancar esta imagen»: la
  imagen de `boot` nunca fue la variable. Discriminador limpio para mañana: **E1 = copiar a A la cadena
  de B medida en E0** (`vendor_boot_a`+`init_boot_a`+`boot_a`, 3 flashes). Detalle en §B.

---

# PARTE A — `e2fsck` EN FRÍO SOBRE `userdata`, EJECUTABLE SIN FLASHEAR

## A.0 Hechos medidos que gobiernan todo el runbook (con su fuente)

| Hecho | Medida | Fuente |
|---|---|---|
| FS de la raíz | **8 GiB reales** (2 097 152 bloques × 4 KiB, 64 grupos, 32768 bloques/grupo), `has_journal`, `orphan_file`, `metadata_csum`, UUID `e87e257e-a4bd-45ca-a494-c0a4e15c48c8` | `dumpe2fs -h build/rootfs/arch-rootfs.img`; el UUID coincide con el del arranque (`k6b-migas.log:1809`) ⇒ en la tablet está *esa* imagen |
| Partición | `userdata` = `0x1A767FB000` = **113 657 229 312 B (105,85 GiB)**; device `sda32` (por etiqueta: `/dev/disk/by-partlabel/userdata`) | `out/getvar-all-t2.log:197-198`; `:1700` (sda32) |
| Journal | 64 MiB (16 384 bloques); **nunca se ha reproducido** (el init monta `-o ro,noload`) | `dumpe2fs`; `ukeinit` línea 208 del dump; `k6b:1809` («ro without journal») |
| `e2fsprogs` en el rootfs | **1.47.4-1** (`/usr/bin/e2fsck`, también `usr/sbin`), con `fsck.ext4`, `dumpe2fs`, `tune2fs`, `resize2fs` | `build/rootfs/staging/var/lib/pacman/local/e2fsprogs-1.47.4-1` |
| `e2fsck` en el INITRAMFS que corre | **NO existe** (el initramfs del hermano es busybox + applets; 0 entradas `e2fsck` en todos los cpio.s que hay en disco) | `rescue-dump/s175-initramfs/`; barrido de `*initramfs*.cpio.gz` |
| Qué hace el init al arrancar | monta `-t ext4 -o ro,noload`, comprueba `/sbin/init`, **remonta rw** y `switch_root`. **No hace fsck. No mira `/forcefsck`** | `rescue-dump/s175-initramfs/ukeinit` líneas 205–225 |
| `systemd-fsck` raíz | **se salta**: `File System Check on Root Device skipped, unmet condition check ConditionPathIsReadWrite=!/` | `k6b-migas.log:1918`; unit real en `build/rootfs/staging/usr/lib/systemd/system/systemd-fsck-root.service` |
| Montaje de systemd | a los 16,43 s solo *re-monta* según fstab (`systemd-remount-fs`), sin fsck | `k6b:1961-1963` |
| Otras particiones | la única ext4 montada por el sistema es la raíz; `sda30` (rescue, 128 MiB) la monta/usa el *init* para volcar `forklog` en el initramfs; **no** hay `/boot` separado (dir vacío en la imagen, fstab de una sola línea) | `fstab` de staging; `dump-log.sh`; `k6b:1815-1816` |
| Canales vivos | SSH `root@192.168.42.129` (clave `build/rootfs/uke-arch-root`) y consola ACM (`/dev/ttyACM0` en el PC; login `root`, `ttyGS0`) | `build/gates/uke-ssh.sh`; ledger hermano #444 (login) |
| Corrupción observada | errores en **cada** arranque y **crecientes**: k2 2 errores → k4 7 → k5 9 → k6 12 (`bitmap/bg inconsistent` grupos 6,23,26,27,28,29,31,38; `deleted inode referenced` inodo 154008; `doubly allocated` 154012; `freeing already freed block`; `bit already cleared`) | `k2-migas-log.txt:1845-1846`; `k6-migas.log:1834-1840,1978-1980,2095-2096`; `k6b-migas.log:1972,2070-2076,2219-2220` |
| Causa de fondo (medida en código) | el init monta `noload` **y el remount rw no carga el journal** (`__ext4_remount`: si `s_journal == NULL` no se carga) ⇒ la raíz lleva desde el 27-sep corriendo **sin journaling**, y cada corte duro deja metadatos a medias. `Errors behavior: Continue` ⇒ ext4 sigue corrompiendo en silencio | `~/gpu-work/palawan-linux/fs/ext4/super.c:6800`; `dumpe2fs` («Errors behavior: Continue»); B §1186 («el `-o ro,noload` … es la causa raíz», ledger #3059) |
| Punto de partida del fs | la imagen se construyó **limpia**: `e2fsck -fn` sobre ella da 47 668/524 288 inodos y rc=0 → la corrupción es *posterior* (runtime + cortes duros) | `build/rootfs/INFORME-A2.md:122` |

**Nota de tamaño (corrige un riesgo del plan):** B §1236 temía un fsck de 105,9 GB. **No**: el fs es de
8 GiB. El `e2fsck -f` completo debería tardar del orden de decenas de segundos a 2–3 min en UFS, no horas.
La partición de 105,85 GiB es el *contenedor*; el fs ocupa el primer 8 GiB (y el resto conserva datos
viejos: irrelevante para fsck; solo importa si algún día se hace `resize2fs`).

## A.1 Vía 1 — `systemd-fsck` al siguiente arranque: **NO SIRVE. No la ejecutes.**

La receta que pide el plan es esta (queda documentada, pero su veredicto es NO):

```bash
# (documentado, NO recomendado)
ssh -i build/rootfs/uke-arch-root root@192.168.42.129 '
  grep -n userdata /etc/fstab      # debe acabar en "... 0 1" (passno=1)
  touch /forcefsck
  sync
  systemctl reboot'                # y esperar el fsck del siguiente arranque
```

**Por qué no funciona, medido (no inferido):**

1. `systemd-fsck-root.service` lleva **`ConditionPathIsReadWrite=!/`**
   (`build/rootfs/staging/usr/lib/systemd/system/systemd-fsck-root.service:18`). Es decir: **solo corre si
   `/` NO está en rw** cuando systemd arranca. El plan estándar de las distros es: initramfs monta ro →
   `systemd-fsck-root` → `systemd-remount-fs` remonta rw. Aquí el init del hermano remonta **rw él mismo**
   antes del `switch_root`, así que la condición falla y el servicio se salta. **Ya se ve en el log real**:
   `k6b-migas.log:1918: systemd[1]: File System Check on Root Device skipped, unmet condition check ConditionPathIsReadWrite=!/`.
2. `/forcefsck` lo consulta el *helper* `systemd-fsck` **cuando su servicio se ejecuta**; con el servicio
   saltado, el fichero es decorativo. Y el init que corre (s181) **no mira `/forcefsck`** (`ukeinit` líneas
   205–225: solo monta ro,noload → comprueba init → remonta rw).
3. Aunque el servicio corriera, el fsck de una raíz montada **rw** es inseguro: `e2fsck` aborta o pide
   confirmación (`check_mount()`: solo `-n`, o `-f`+montaje ro, pasan sin preguntar). Habría que montar ro
   primero — y eso ya no lo hace systemd.
4. `fs_passno=1` **ya está** en el fstab de la imagen (`build/rootfs/staging/etc/fstab`), así que no hay
   nada que añadir.

**Qué repararía / qué no (si se pudiera ejecutar):** es el mismo `e2fsck -f` ⇒ repararía todo lo mismo que
la vía A.2. No repara la *causa* (el montaje `noload`+rw del init) ni los datos que ya se perdieron dentro
de ficheros (eso acaba en `/lost+found`).

**Variante limpia (para C, §A.4-Cbis):** si algún día se cambia el init para que **no** remonte rw y haga
`switch_root` con la raíz ro, esta vía pasa a ser la buena: el arranque siguiente haría `e2fsck` y systemd
remontaría rw. Es el diseño estándar de Arch y el que convierte `/forcefsck` en un botón de fsck.

## A.2 Vía 2 (RECOMENDADA, sin flash) — SSH: remontar ro + `e2fsck -fy`

### A.2.0 Por qué es válida (y con qué límite)

- `e2fsck` 1.47.4, con el fs **montado read-only** y `-f`, **no aborta**: `check_mount()` deja pasar la rama
  de aviso (`(E2F_OPT_READONLY) || (E2F_OPT_FORCE && mount_flags & EXT2_MF_READONLY)`). Con el fs montado
  **rw** sí aborta (o pregunta) ⇒ **el `remount,ro` es obligatorio**.
- Límite honesto: el kernel sigue teniendo el fs montado (ro). No escribe, pero su copia en memoria del
  superbloque/bitmaps queda **vieja** tras el fsck. **Por eso, después del fsck: `sync` y reboot inmediato
  (no volver a remontar rw).** El reboot deja que el arranque siguiente lea el fs reparado de disco.
- Segunda opción aún más limpia si no te fías: §A.3 (fs **desmontado** de verdad, vía fallback del init).

### A.2.1 Precondiciones (todas deben cumplirse)

1. Tablet **arrancada y estable** en slot **b** con un boot validado (no la dejes con K7 experimentales:
   si el arranque está en pruebas, primero rollback `fastboot flash boot_b boot_b-lee.img` + `dtbo_b s229`).
2. **Batería ≥ 3700 mV** y **cargador de pared conectado durante todo el proceso** (no se puede medir la
   carga desde Arch, NOTAS 28-sep: **desconéctala solo al final**, pero deja el cable puesto).
3. Canal SSH vivo (probarlo antes con `build/gates/uke-ssh.sh -i`) **y** consola ACM disponible como red de
   seguridad: `/dev/ttyACM0` en el PC con **UN SOLO LECTOR** (regla del proyecto; p.ej.
   `~/proyectos/out/captura-robusta.sh` o `cat /dev/ttyACM0 > ~/proyectos/out/fsck-console.log`). El login
   de consola es `root` (ledger hermano #444 documenta el login en `ttyGS0`).
4. **Nadie más usando la tablet**: ni sesiones de flash, ni el proyecto hermano, ni subagentes.
5. Verificar que `e2fsck` es el real y que `/tmp` es tmpfs (si no, usar `/dev/shm`):

```bash
ssh -i build/rootfs/uke-arch-root root@192.168.42.129 '
  e2fsck -V | head -1
  findmnt -no FSTYPE /tmp ; findmnt -no FSTYPE /dev/shm
  findmnt -t ext4 -o TARGET,SOURCE,OPTIONS      # debe salir SOLO la raiz
  dumpe2fs -h /dev/disk/by-partlabel/userdata | egrep "Block count|Block size|Free blocks|Filesystem state|Last checked|Lifetime writes|Errors behavior"
  blockdev --getsize64 /dev/disk/by-partlabel/userdata
  ls -l /dev/disk/by-partlabel/userdata'
```

Guarda esa salida en el PC: es el «antes» (y confirma el tamaño real del fs en el aparato, que hoy es una
inferencia desde la imagen y los logs).

### A.2.2 Backup mínimo previo (obligatorio antes de tocar nada)

No hace falta clonar 8 GiB: lo regenerable está en el PC y lo que no, es pequeño. A `/dev/shm` (RAM, no
toca el fs) y de ahí al PC por scp:

```bash
# En el PC: primer tiempo, guardar el «antes» y llevarse el backup
OUT=~/proyectos/out/fsck-$(date +%Y%m%d-%H%M)
mkdir -p "$OUT"

ssh -i build/rootfs/uke-arch-root root@192.168.42.129 '
  set -e
  dumpe2fs -h /dev/disk/by-partlabel/userdata > /dev/shm/dumpe2fs-antes.txt 2>&1 || true
  ls -l /dev/disk/by-partlabel/ > /dev/shm/partlabels.txt
  blkid > /dev/shm/blkid.txt 2>&1 || true
  findmnt -R > /dev/shm/findmnt.txt
  pacman -Qq > /dev/shm/pkgs.txt
  pacman -Qkk > /dev/shm/pkgs-verify.txt 2>&1 || true
  tar --one-file-system -C / -czf /dev/shm/uke-backup.tgz \
      etc var/lib/pacman/local var/lib/pacman/sync var/log/pacman.log \
      root usr/local/bin usr/local/sbin 2>/dev/null || true
  ls -la /dev/shm/uke-backup.tgz /dev/shm/*.txt
'
scp -i build/rootfs/uke-arch-root -r \
    root@192.168.42.129:/dev/shm/uke-backup.tgz \
    root@192.168.42.129:/dev/shm/dumpe2fs-antes.txt \
    root@192.168.42.129:/dev/shm/partlabels.txt \
    root@192.168.42.129:/dev/shm/blkid.txt \
    root@192.168.42.129:/dev/shm/findmnt.txt \
    root@192.168.42.129:/dev/shm/pkgs.txt \
    root@192.168.42.129:/dev/shm/pkgs-verify.txt \
    "$OUT/"
```

- **Qué se protege:** `/etc` (fstab, red, sshd, sudoers, keymap), la base de datos de pacman (`local` es lo
  que permite reinstalar/reconstruir el sistema; `sync`), `/var/log/pacman.log`, `/root` (scripts y claves
  del proyecto), `/usr/local` (p. ej. `qbootctl`, `build/slot/qbootctl-aarch64`). Si hubiera algo del dueño
  en `/home`, añadirlo al tar.
- **«Partición hermana»:** la única candidata es `rescue` (`/dev/disk/by-partlabel/rescue`, ext4, 128 MiB,
  la monta el init como `/mnt/rescue` para `forklog`). Cabe el tar (unos MB), pero está escrita por el
  init; si se usa, escribir un nombre único y no pisar `forklog*.txt`. Preferible **scp al PC** (el PC tiene
  150 GB libres).
- Si `tar` no está en el rootfs (improbable), valen `cp` a `/dev/shm` de los directorios clave + `pacman
  -Qqe`.

### A.2.3 Diagnóstico read-only (0 riesgo, hazlo siempre antes)

```bash
ssh -i build/rootfs/uke-arch-root root@192.168.42.129 \
  'e2fsck -fn /dev/disk/by-partlabel/userdata 2>&1 | tee /dev/shm/e2fsck-n-antes.txt | tail -40'
```

- `-n` es **seguro con el fs montado** (lo dice el propio `man e2fsck`: «la única excepción es `-n`»).
- **Ojo a la semántica:** con `-n` e2fsck **no reproduce el journal** («skipping journal recovery because
  doing a read-only filesystem check») y el resultado «no es válido si el fs está montado». Sirve como
  **inventario** de lo que va a encontrar (grupos afectados, inodos), no como veredicto. Guarda la salida.

### A.2.4 El fsck (comandos literales)

`/dev/shm` es tmpfs ⇒ el log no escribe en el fs que se repara; y `nohup setsid` ⇒ **si el SSH se cae, el
fsck NO se muere** (sobrevive al `timeout 180` de `uke-ssh.sh`, que si no lo mataría).

```bash
ssh -i build/rootfs/uke-arch-root root@192.168.42.129 '
  set -e
  # 1) quiescencia suave (opcional): que journald/ntp no estén escribiendo
  systemctl stop systemd-timesyncd chronyd 2>/dev/null || true
  sync

  # 2) montar la raiz READ-ONLY (obligatorio: con rw, e2fsck aborta)
  mount -o remount,ro /
  mount | grep " / "        # debe decir "ro" o "ro,relatime"

  # 3) fsck desprendido, log a tmpfs, raya de EXIT
  : > /dev/shm/e2fsck-fy.log
  rm -f /dev/shm/e2fsck-exit
  nohup setsid sh -c '
      echo "INICIO $(date -u +%FT%TZ)" >> /dev/shm/e2fsck-fy.log
      e2fsck -f -y -v /dev/disk/by-partlabel/userdata >> /dev/shm/e2fsck-fy.log 2>&1
      RC=$?
      echo "EXIT=$RC" >> /dev/shm/e2fsck-fy.log
      echo "$RC" > /dev/shm/e2fsck-exit
  ' >/dev/null 2>&1 &

  sleep 2
  echo "lanzado; pgrep: $(pgrep -a e2fsck || true)"
'
```

- `-f` fuerza la revisión completa (necesario: el fs no está marcado «dirty» de forma que e2fsck se ponga
  solo). `-y` responde sí a todo. `-v` da detalle.
- **No** añadas `-p` aquí: `-p` (preen) se para en los errores «serios» y aquí queremos reparación total.
- **No uses `systemctl isolate rescue.target` desde SSH**: `rescue.target` no arrastra `sshd`, así que
  **te deja sin sesión** justo antes del paso crítico. No hace falta: el `mount -o remount,ro /` hace
  `sync_filesystem` antes de girar a ro, y parar servicios es solo cosmético (los que sigan escribiendo
  recibirán `EROFS`, sin más). Si se quiere minimizar ruido, basta `systemctl stop` de los que escriben
  mucho (`systemd-timesyncd`, `chronyd`), nunca del propio `sshd` ni de `systemd-journald` (este último
  se necesita para el log de la sesión).
- Con el fs montado **ro** y `-f`, e2fsck imprime un aviso («Warning! … is mounted») y **continúa**
  (rama de aviso de `check_mount`); no debe pedirte confirmación. Si la pidiera, es que el `remount,ro`
  no se aplicó: aborta y repite A.2.4 paso 2.
- Si el «antes» pidió optimizar directorios (`ext4_dirblock_csum_verify: No space for directory leaf
  checksum`, B §1186), la segunda pasada recomendada es `e2fsck -f -y -D` (puede tardar más; el `-D` solo
  reordena directorios). Es opcional: hazla **solo si** la primera pasada termina pronto y la batería da
  margen.

**Seguimiento (desde el PC, sin tocar el fs):**

```bash
ssh -i build/rootfs/uke-arch-root root@192.168.42.129 '
  pgrep -a e2fsck; tail -5 /dev/shm/e2fsck-fy.log; cat /dev/shm/e2fsck-exit 2>/dev/null'
# o por la consola ACM (login root): tail -f /dev/shm/e2fsck-fy.log
```

Espera a `EXIT=`. Códigos: **0** limpio, **1** corregido, **2** corregido y «reboot requerido», **4**/8
no pudo corregir algo (guarda el log; si 4, repetir con `-fy` una vez más antes de rendirse: la primera
pasada crea huérfanos que la segunda coloca), **32** cancelado.

### A.2.5 Verificación (dos `-n` en verde)

```bash
ssh -i build/rootfs/uke-arch-root root@192.168.42.129 '
  e2fsck -fn /dev/disk/by-partlabel/userdata > /dev/shm/e2fsck-n-1.txt 2>&1; echo "rc1=$?"
  e2fsck -fn /dev/disk/by-partlabel/userdata > /dev/shm/e2fsck-n-2.txt 2>&1; echo "rc2=$?"
  tail -3 /dev/shm/e2fsck-n-1.txt; tail -3 /dev/shm/e2fsck-n-2.txt'
```

**Criterio de hecho:** `rc1 = rc2 = 0` y sin líneas `... contains errors` en las dos pasadas
(`e2fsck -fn` sobre el fs reparado). Límite honesto: siguen siendo dos comprobaciones *con el fs montado
ro* (válidas como criterio práctico de cierre). El «estándar de oro» es un `e2fsck -fn` con el fs
**desmontado** (Plan C, §A.4). Si `rc1≠0`, vuelve a A.2.4 (una pasada más) y anota el número exacto.

### A.2.6 Si el SSH se corta (o la tablet se apaga) A MITAD DEL FSCK

El fsck va con `nohup setsid` ⇒ el corte de SSH **no lo mata**; solo te deja ciego. Protocolo:

1. **No toques nada durante 90 s.** Reconecta: `build/gates/uke-ssh.sh -i`. Con suerte el fsck terminó.
   Mira `/dev/shm/e2fsck-exit` y el final de `/dev/shm/e2fsck-fy.log`.
2. Si SSH no vuelve, usa la **consola ACM** (`/dev/ttyACM0`, login root): `pgrep e2fsck`,
   `tail /dev/shm/e2fsck-fy.log`, `cat /dev/shm/e2fsck-exit`. La consola no depende de sshd.
3. Si el fsck sigue vivo: **espera**. No rebotes. No montes nada. Cuando termine, sigue desde A.2.5.
4. Si el sistema se apagó de verdad a mitad (batería/corte), el fs queda **a medias de reparar**. NO lo
   arranques normal: el init del hermano lo montaría rw (con `noload`) y volvería a escribir encima.
   **Arranca a un entorno donde `userdata` esté desmontado** (Plan C §A.4) y repite `e2fsck -f -y`.
   Con la raíz ro y el fs sin journal activo, un fsck interrumpido es **re-ejecutable**: la segunda pasada
   vuelve a arreglar lo que quedó a medias (por eso el orden de los pasos de e2fsck es transaccional por
   fases).
5. **Nunca** dejes la tablet con el fs a medias y un arranque normal pendiente: es la forma de convertir
   corrupción «reparable» en «pérdida de ficheros».

### A.2.7 Cierre y reboot

```bash
ssh -i build/rootfs/uke-arch-root root@192.168.42.129 '
  sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true; sync
  systemctl reboot -f    || reboot -f'
```

- La raíz sigue **ro** ⇒ el shutdown no debe intentar escribir; `-f` evita que systemd se pelee con
  servicios que no pueden escribir. Si se cuelga: `sync` (por consola) y **pulsación larga de power**
  (reset duro; ya sincronizado).
- **No** remontar rw antes del reboot (ver A.2.0). En el arranque siguiente el init monta el fs ya reparado.
- Después del reboot: `build/gates/uke-ssh.sh 'e2fsck -fn ...'` otra vez (ahora desde el sistema recién
  arrancado) y anotar el estado en el ledger/ESTADO-VIVO. A partir de aquí, **evitar los cortes duros**
  (usar `systemctl poweroff`/`reboot` normales cuando se pueda): cada corte vuelve a ensuciar metadatos
  porque el init sigue montando sin journal.

### A.2.8 Qué repara y qué no (expectativas)

- **Repara**: bitmaps/BG descriptors inconsistentes, contadores de bloques/inodos, dobles asignaciones,
  `freeing already freed block`, inodos «borrados referenciados», cadenas de directorios, huérfanos
  (los mete en `/lost+found`), y reproduce el journal por fin.
- **No repara**: datos dentro de ficheros ya dañados (los trunca/aisla), `errors=continue` del superbloque,
  y **la causa** (init con `noload` + rw + cortes duros). Si no se cambia el init, la corrupción vuelve.
  Opcional post-fsck (una escritura de superbloque, `tune2fs -e remount-ro`): que un error futuro deje el
  fs en ro en vez de seguir corrompiendo. Decidir con el dueño; no es indispensable para cerrar A.

## A.3 Vía 2-bis (sin flash, fs DESMONTADO de verdad) — fallback del initramfs

Se puede conseguir un shell **con `userdata` sin montar** sin flashear: el init del hermano cae a
«fallback fork» (telnet :23 + getty ACM + red) si no encuentra `/sbin/init` en la raíz — **sin montarla rw**
(`ukeinit` líneas 226–234: `umount /mnt/ubuntu` + fallback). Truco: renombrar `/sbin/init` **una vez**
(escritura mínima) y reiniciar:

```bash
# SOLO si la via A.2 te la rechaza e2fsck (p.ej. rc=4 repetido) y quieres el fs desmontado:
ssh ... 'mv /sbin/init /sbin/init.off && sync && systemctl reboot'
# tras el reboot: consola ACM o telnet 192.168.42.129:23  -> shell busybox, userdata SIN montar
```

Entonces, **desde esa shell** (no hay e2fsck en el initramfs: hay que usar el del rootfs, sin montarlo rw):

```sh
# opcional: montar SOLO para leer el binario y sus libs (ro), y ejecutarlo con su propio loader
mkdir -p /mnt/u
mount -t ext4 -o ro /dev/sda32 /mnt/u
/mnt/u/usr/lib/ld-linux-aarch64.so.1 --library-path /mnt/u/usr/lib \
    /mnt/u/usr/sbin/e2fsck -f -y -v /dev/sda32
umount /mnt/u
# restaurar el init y reiniciar
mount -t ext4 -o rw /dev/sda32 /mnt/u && mv /mnt/u/sbin/init.off /mnt/u/sbin/init && sync && umount /mnt/u
busybox reboot -f
```

- **Ventaja**: el kernel que corre nunca montó el fs rw (no hay estado sucio en memoria) y no depende de
  sshd.
- **Riesgos**: el init antiguo tenía ventana de 300 s y se auto-reiniciaba (**la versión que corre hoy,
  s181, tiene ventana INFINITA** — `while :; do sleep 60; done`, verificado en el dump — pero
  **NO VERIFICADO en el aparato con esta versión**); sigue siendo un fsck sobre un fs montado ro (misma
  rama de `check_mount`); y si te equivocas de `sdX` puedes romper otra partición (usar SIEMPRE
  `/dev/disk/by-partlabel/userdata`). Úsala solo como plan B.

## A.4 Vía 3 (Plan C, CON reflashear) — el cambio exacto para parar en shell antes de montar

Aquí sí hay trabajo ya hecho y gates.

**C-1 (preferida, imagen ya construida):** `build/bootimg/boot-arch-uke.img`
(`82c59a52…`, 96 MiB, kernel 16 557 104 B + **ramdisk propio de 2 393 396 B**, `rdinit=/ukeinit-arch`).
Su initramfs (`build/bootimg/initramfs-arch-uke.cpio.gz`) **lleva `e2fsck` REAL + libs**
(`mkarch-initramfs.py:84-96`) y su init hace, en este orden exacto:
`e2fsck -f -p` sobre `by-partlabel/userdata` **antes de montar** (líneas 233–267) → solo si rc 0/1 monta
rw y `switch_root` (líneas 269–276); si rc=2 `sync`+reboot; si rc≥4 **`die()` → shell en `ttyGS0`/`tty0`
con el fs SIN montar** (líneas 92–106). Es decir: **el propio arranque hace el fsck** y, si no puede, te
deja el shell con `e2fsck` a mano para rematarlo.
Coste: **1 flash a `boot_b`** (`fastboot flash boot_b build/bootimg/boot-arch-uke.img`) + volver al par
bueno cuando acabe (`fastboot flash boot_b build/backup-par-bueno/boot_b-lee.img` → 2 en total, o 1 si se
adopta ya el initramfs de Arch como definitivo). **NO VERIFICADO**: el resultado del flash de prueba del
27-sep (`F5-B1`, `PRE-REGISTRO-F5-B1.md:6-66`) no está registrado en el repo; el kernel de esa imagen
(`out/kernel`, sha 32e23e14 en el diag) nunca se validó en la tablet. Antes de usarla: re-verificar sha y
leer su cmdline.

**C-2 (si se quiere un init de reparación dedicado, 100 % reproducido en repo):** añadir al cpio una
variante `ukeinit-fsck` (es una línea más en `mkarch-initramfs.py`) y una imagen con
`rdinit=/ukeinit-fsck`. El cuerpo es el de `ukeinit-arch` **hasta el paso 7** (pseudo-FS, printk 7,
gadget ACM/NCM, red, `e2fsck REAL`) con dos cambios literales:

```sh
# build/init/ukeinit-fsck  (derivado de ukeinit-arch:233-267)
say "ukeinit-fsck: modo reparacion; userdata NO se monta"
[ -b "$USERDATA" ] || resolve_userdata || die "sin userdata"
"$E2FSCK" -f -y -v "$USERDATA" >/dev/kmsg 2>&1 ; RC=$?
say "e2fsck rc=$RC"
"$E2FSCK" -f -n "$USERDATA" >/dev/kmsg 2>&1 ; RC2=$?
say "e2fsck -n rc=$RC2"
sync
if [ "$RC2" = 0 ]; then say "FS LIMPIO: reboot"; sleep 3; reboot -f; fi
exec /bin/sh -i </dev/ttyGS0 >/dev/ttyGS0 2>&1   # deja shell con ACM si no quedo limpio
```

y en el empaquetado: `add('ukeinit-fsck', 0o100755, f(...))` en `mkarch-initramfs.py` +
`RDINIT_SWAP`/token `rdinit=/ukeinit-fsck` en `mkarch-boot.sh` (el builder ya soporta el swap de
`rdinit=`, líneas 100–107). Ensamblarlo es trabajo offline de ~15 min; **el flash no ahorra ninguno**
frente a C-1.

**C-bis (la variante «systemd-fsck para siempre»):** con un init que NO remonte rw y haga `switch_root` con
la raíz ro, el arranque siguiente lo repara systemd (`systemd-fsck-root` + `systemd-remount-fs`) y
`/forcefsck` pasa a ser el botón de fsck (§A.1, variante). Es la solución de fondo, pero exige reflash de
`init_boot` (o adoptar el initramfs de Arch de C-1, que ya fsckea por su cuenta).

## A.5 Orden propuesto para la mañana (encaja con el runbook de `docs/historia/ESTADO-VIVO.md:13-22`)

1. **Power-cycle físico** (10 s) → arranque **en frío** de K7: es gratis y único (#P17). Si K7 vive:
   capturar las migas del apps-smmu y seguir `R2-display-cadena.md` **antes** de nada más (el reboot del
   fsck mataría esa sesión).
2. Si K7 muere mudo: `fastboot flash boot_b boot_b-lee.img` + `fastboot flash dtbo_b` s229 → arranque
   bueno conocido → SSH.
3. **Fsck (A.2)** con backup (A.2.2) y verificación (A.2.5). Es prerequisito antes de más experimentos.
4. Después, **F9 E0/E1** (§B.5). Si en E1 hay que flashear 3–4 particiones, contar el presupuesto
   (≤2 escrituras/día): pedir al dueño la exención explícita, como en los ciclos anteriores
   (`--waiver-bateria`) y anotar el coste real en el pre-registro.

---

# PARTE B — SÍNTESIS FORENSE DE F9 (slot A mudo, 4/4)

## B.1 Lo que se flasheó a `boot_a` y qué se esperaba (cronología de los 4 mudos)

| # | Fecha (28-sep) | `boot_a` | `dtbo_a` | Qué se esperaba | Qué pasó | Fuente |
|---|---|---|---|---|---|---|
| 1 | ~13:03 | `boot-pokes.img` (kernel UKE-POKE v1, sha luego anulado) | `s251` | migas `UKE-POKE` con consola viva | **0 líneas**; slot a `unbootable` a las 13:10:41 | `PRE-REGISTRO-F5-B1.md:1022-1061` |
| 2 | ~13:2x-14:0x | `boot-pokes.img` (sha `81fc9f00…`, condición del diferir siempre falsa) | `s251` | ídem | **mudo** («dos flashes fallidos por bugs de mis scripts») | `:1052-1058` |
| 3 | ~14:0x | `boot-pokes.img` (sha `530a0ef6…`, diferir arreglado) | `s251` | ídem | **mudo**; el 3.er intento dio cero líneas | `:1058-1083`; `NOTAS-OMARCHY.md:1470-1475` |
| 4 | ~14:31–14:35 UTC | `boot-pokes.img` (sha final `11cf3482…`) | `s238` **bueno** (el de `dtbo_b`) | aislar `s251`: si es el culpable, ahora debe arrancar | **CUARTO mudo**: 0× `UKE-POKE`, 1× `Linux version` del kernel bueno (rollback) | `PRE-REGISTRO-F5-B1.md:1101-1164` |

**Lo que fija el conjunto:** los 4 comparten «imagen de `boot` nueva **en el slot A**»; el s251 queda
inocente; los kernels de la serie K **sí** arrancan cuando están en B con la cadena de B (K6+s258 arrancó
«sano», `docs/historia/ESTADO-VIVO.md:6-7`). Caveat de captura: el tramo 14:11–15:01 del log ACM está contaminado por
dos lectores (`REGLA-UN-SOLO-LECTOR.md`), así que «cero líneas» es indicio, **no** prueba; los veredictos
se apoyan además en datos independientes (contadores de slot, rollback limpio, versión de kernel).

## B.2 La cadena de arranque REAL (medida con `unpack_bootimg`, esto reordena F9)

| Pieza | Contenido real | Evidencia (`unpack_bootimg` / archivos) |
|---|---|---|
| `boot` (K1–K7, `boot-pokes`, **`boot_b-lee`**) | **kernel SOLO**. `header v4`, **`ramdisk size: 0`**; cmdline 255–382 B con `rdinit=/ukeinit` | `boot-ukek6/7.img`, `boot-pokes.img`, `boot_b-lee.img` (todas: «ramdisk size: 0») |
| `vendor_boot` (stock ROM) | **el DTB (1 885 961 B, 4 FDTs)** + **ramdisk vendor (34 052 361 B: 347 `.ko`, `first_stage_ramdisk/`, SIN `/init`)** + bootconfig | `vendor_boot-stock.img` (sha `3ee6d4ac…` = el que el hermano verificó en `vendor_boot_b`, #238/#241); `UBUNTU-BOOT.md:15` |
| `init_boot` | **el ramdisk que define `rdinit`**: ahí vive `/ukeinit` (busybox + el init del proyecto, saga S107→S181 que se ve en los logs) | `unpack_bootimg init_boot-stock.img` da el ramdisk *stock* Android (2 308 998 B, sin `ukeinit`); el init que corre (`X9S181: init s172`, `k6b:1492`) **no está** en `boot` (ramdisk 0) ni en `vendor_boot-stock` ⇒ tiene que venir de un ramdisk **no stock** de la tablet. El hueco natural es `init_boot_b`; el `vendor_boot_b` solo podría serlo si el suyo no fuese el ROM (el hermano lo verificó = stock en #241). **E0 lo mide** |
| `dtbo` | overlays (s238/s258…) | `bootimg/s238-…`, `s258-…` |
| `misc` | BCB viejo (`bootonce-bootloader`/`bootloader`), el ABL no lo soporta y no lo limpia | hermano #241; `build/slot/PROCEDIMIENTO-SLOT.md` §4 |

**La conclusión que cambia F9:** «la imagen nueva» que se flasheó a `boot_a` es **solo el kernel**. Para
que arranque hacen falta **también** el DTB (`vendor_boot`), el ramdisk con `/ukeinit` (`init_boot`) y el
overlay (`dtbo`). En el slot B están los tres; **en el slot A faltan dos desde el 24-sep**:

- El proyecto hermano hizo `fastboot erase boot_a init_boot_a vendor_boot_a dtbo_a` + `erase super`
  (ledger #384/#385, líneas 3208-3240) y, buscado hasta su #444, **ninguna entrada posterior restaura
  `vendor_boot_a`, `init_boot_a` ni `super`** (lo verifica `REVISTA-PROYECTO-HERMANO.md:59-63`; solo
  `boot_a`/`dtbo_a` se re-escribieron después: #406, #409, y luego los 4 intentos del 28-sep).
- La sesión forense **midió ceros** en `vendor_boot_a`/`init_boot_a` en la tablet (96 MiB / 8 MiB);
  está anotado en la cabecera de `build/gates/ciclo-restaurar-slot-a.sh` — **NO re-verificado en este
  repo**: lo cierra E0 (§B.5).
- Consecuencia mecánica: sin `vendor_boot_a` no hay DTB que el ABL pase al kernel (el hermano midió que
  `vendor_boot` es **la base del device tree**, #236, y que el ABL camina la cadena de FDTs por
  `totalsize`, #275) ⇒ el kernel muere antes de consola; sin `init_boot_a` no existe `/ukeinit` ⇒ aunque
  el kernel arrancara, no hay userspace/gadget ACM. **Encaja con «cero líneas + slot a unbootable»**.

**Dato que no cuadra al byte (lo dejo abierto, NO VERIFICADO):** el initrd que el kernel dice liberar es
`35508K` (`k6b:1143`) ≈ 36,36 MB ≈ «ramdisk vendor stock + ramdisk `init_boot` stock» (35 509 KiB), y sin
embargo el `init_boot` stock no lleva `/ukeinit`. Ninguno de los cpio custom en disco (s107 gz 1,01 MB;
s181 gz 1,01 MB; s181 lz4 1,15 MB; s181 crudo 1,94 MB) da ese total. Conclusión honesta: **el
`init_boot_b` (o el `vendor_boot_b`) de la tablet NO es ninguno de los ficheros que hay en el repo**;
por eso E0 **mide** las particiones antes de decidir qué copiar.

## B.3 Qué descartó cada prueba (y con qué dato)

| Prueba / medición | Descartó | Dato duro |
|---|---|---|
| 4.º intento con `dtbo_a` = **s238 bueno** y sigue mudo | **el `s251`** (y el contenido de `dtbo_a`) como causa de los mudos | `PRE-REGISTRO-F5-B1.md:1137-1144` |
| `unlocked: yes` + `vbmeta_a == vbmeta_b` (`0f7399d9…`, 131 072 B) + blobs AVB byte-idénticos entre la que arranca y la que no | **AVB/vbmeta por slot** (el ABL no verifica con unlocked; el hashtree es decorativo) | `NOTAS-OMARCHY.md:1457-1465`; `AVB-Y-VBMETA.md` (medido con `medir-avb.sh`, log `medir-avb-20260928-131843.log`) |
| `partition-size:boot_a = 0x6000000` == `boot_b` (96 MiB ambas) | **diferencia de tamaño de partición `boot_a`** | `out/getvar-all-t2.log:145-146` vs `:89-90` |
| Los kernels K1–K6 (mismos ficheros) arrancan en B con `dtbo_b=s258` | **«la imagen de `boot` es mala»** (los ficheros son bootables; lo que cambia es la cadena que los acompaña) | `docs/historia/ESTADO-VIVO.md:6-7`; `NOTAS-OMARCHY.md:1640-1656` |
| El hermano falló distinto (dtbo nuevo en **B**, #431) | Equiparar mecanismos: s241 (vacíar 57 `iommus` + B en kernel) ≠ s251 (cadena `compatible`); solo comparten síntoma | `NOTAS-OMARCHY.md:1558-1560` (apéndice «afirmaciones falsas») |

**Lo que NO descartó el cuarto intento** (y conviene decir): no exoneró a la imagen de `boot` *como
variable de F9* — porque una imagen de `boot` **no puede** arrancar en A con `vendor_boot_a`/`init_boot_a`
vacíos. El aislamiento fue correcto para el `dtbo`, pero la conclusión «lo común es boot nueva» es un
**artefacto**: lo común a los 4 es **arrancar desde A**, no la novedad de la imagen.

## B.4 Hipótesis vivas, rankeadas

| # | Hipótesis | A favor | En contra / dudas | Predicción falsable |
|---|---|---|---|---|
| **H1** | **El slot A está incompleto: `vendor_boot_a` (DTB+ramdisk) e `init_boot_a` (con `/ukeinit`) a ceros desde el erase del 24-sep. Cualquier `boot_a` queda mudo.** | El erase está verificado (#384/#385); ninguna restauración posterior (#444); ceros medidos por la sesión forense (cabecera de `ciclo-restaurar-slot-a.sh`); la anatomía real (§B.2) exige DTB+ramdisk que en A no están; los 4 mudos son «sin consola y slot unbootable» = firma de fallo antes de userspace; los mismos kernels sí viven en B | Los ceros actuales **no** re-medidos aquí; el tamaño del initrd (§B.2 nota) no cuadra del todo; «¿por qué el `erase` de `boot_a`/`dtbo_a` no impidió que los intentos 1-3 los re-escribieran y aun así murieran?» → porque el resto seguía vacío | **E1**: con `vendor_boot_a`+`init_boot_a` restaurados (cadena de B), un `boot_a` **llega a `Linux version`**. Si no llega, H1 refutada |
| **H2** | El `misc` (BCB sucio) mete al ABL en una ruta mala cuando el slot A es el activo | `misc` lleva un BCB viejo que el ABL no limpia (#241) y F0 lo deja pendiente (`DECISION-misc-BCB.md`) | El BCB no tiene semántica de slot conocida y B arranca con el mismo `misc`; el propio doc dice «command=`bootloader`, resto ceros» y que los flags viven en la GPT | **E2**: limpiar `misc` (4 MiB) **no cambia nada** si H1 es la buena |
| **H3** | Estado de slot / atributos GPT de A inconsistentes (más allá de `set_active a`) | La familia de fallos del hermano apunta a «estado de slot pre-handoff» como causa #1 compatible con todo lo medido (su #303: `unbootable/successful/retry/priority`, no el contenido) | `set_active a` re-escribe los attrs (`PROCEDIMIENTO-SLOT.md` §2) y el ABL **sí** intenta A (consume reintentos) ⇒ la selección funciona; E1 re-escribe la GPT con `set_active` | Si E1 arranca, H3 muere de paso; si no, **E3**: comparar dump GPT con `qbootctl` (solo lectura) |
| **H4** | AVB/vbmeta por slot | — | **Refutada con medición** (`unlocked: yes`; `vbmeta_a`==`vbmeta_b`; blobs idénticos) | — |
| **H5** | `boot_a` de distinto tamaño/geometría | — | **Refutada**: `0x6000000` en ambas, imágenes de 96 MiB exactos | — |
| **H6** | XBL solo vuelca consola del slot activo / «arranca y no se ve» | — | Los contadores 7→0 y la caída a fastboot no son compatibles con «arranca invisible»; el canal ACM se crea dentro del kernel, no depende del slot | Si E1 arranca **sin** líneas de consola pero con SSH, H6 sube |

## B.5 Plan de discriminación para mañana (E0–E3, con coste y qué separa cada uno)

**E0 — Medición (0 flashes, 0 escrituras; hacerla SIEMPRE primero).** Estando la tablet arrancada en B
(tras el power-cycle y, si toca, el rollback al par bueno), leer en la tablet y hashear al **tamaño exacto**
(la partición es mayor que la imagen; hashear la partición entera no vale — patrón #241):

```bash
# E0-a) estado de slot (necesita fastboot; si no, se salta y se sigue por SSH)
fastboot getvar current-slot
fastboot getvar slot-unbootable:a   ; fastboot getvar slot-unbootable:b
fastboot getvar slot-retry-count:a  ; fastboot getvar slot-retry-count:b

# E0-b) en la tablet (SSH), solo lectura, hasheando al tamaño EXACTO de imagen
#       (la partición es mayor: boot/dtbo/vendor_boot=96/24/96 MiB, init_boot=8 MiB)
dd if=/dev/disk/by-partlabel/boot_a        bs=1M count=96 | sha256sum
#   esperado si nada cambió desde el 28-sep: 11cf3482… (boot-pokes)
dd if=/dev/disk/by-partlabel/dtbo_a        bs=1M count=24 | head -c 607534 | sha256sum
#   esperado: bdb361df… (s238, el bueno)
dd if=/dev/disk/by-partlabel/vendor_boot_a bs=1M count=96 | sha256sum
#   H1 dice: ceros (sha de 96 MiB de 0x00)
dd if=/dev/disk/by-partlabel/init_boot_a   bs=1M count=8  | sha256sum
#   H1 dice: ceros (sha de 8 MiB de 0x00)
dd if=/dev/disk/by-partlabel/vendor_boot_b bs=1M count=96 | sha256sum
#   esperado: 3ee6d4ac… (stock ROM, hermano #238/#241)
dd if=/dev/disk/by-partlabel/init_boot_b   bs=1M count=8  | sha256sum
#   NO conocido: es el que trae /ukeinit; anotar el sha para comparar con los ficheros del repo

# E0-c) guardar los bytes de la cadena B para usarlos como FUENTE de E1
dd if=/dev/disk/by-partlabel/init_boot_b   of=/root/init_boot_b-lee.img   bs=1M count=8  conv=fsync
dd if=/dev/disk/by-partlabel/vendor_boot_b of=/root/vendor_boot_b-lee.img bs=1M count=96 conv=fsync
scp -i build/rootfs/uke-arch-root \
    root@192.168.42.129:/root/init_boot_b-lee.img \
    root@192.168.42.129:/root/vendor_boot_b-lee.img \
    build/backup-par-bueno/
# (opcional, para el puzzle del initrd): comparar el sha de init_boot_b con
#  ~/gpu-work/ramaa/s21/init_boot_b-s107.img y con los cpio s136/s181 del rescue-dump
```

- Cierra el **NO VERIFICADO** de los ceros (base de H1) y da los **bytes exactos** que hay que copiar a A.
- Además: `fastboot getvar current-slot`, `slot-unbootable:a/b`, `slot-retry-count:a/b` antes de nada.

**E1 — El control limpio: la cadena de B ENTERA en A (3 flashes + `set_active`).**
`fastboot flash vendor_boot_a vendor_boot_b-lee.img` (el medido en E0) + `fastboot flash init_boot_a
init_boot_b-lee.img` (el medido en E0) + `fastboot flash boot_a build/backup-par-bueno/boot_b-lee.img`
(kernel bueno, **no** experimental) → `fastboot set_active a` → `fastboot reboot` → consola ACM con UN
lector + `/dev/ttyACM0`, ventana ≥5 min.

- **Si llega `Linux version`/`S123` en A ⇒ H1 confirmada** y F9 queda cerrada como «slot A incompleto»:
  el `boot` nuevo nunca fue la variable; se puede repetir el ciclo con `boot_a`=pokes para el SMMU.
- **Si sigue mudo ⇒ H1 refutada** y el problema está en el **estado del slot/no-imagen** (H3/H6). Pasa a
  E2/E3.
- Coste real: 3 escrituras (96+8+96 MiB) + 1 `set_active` (GPT). Presupuesto ≤2/día ⇒ exención explícita
  del dueño, pre-registro con shas ANTES de la primera escritura (regla dura del proyecto) y vigía de
  fastboot pausado.
- Variante barata (2 flashes): dejar `boot_a` = pokes `11cf3482…` (ya está) y flashear solo
  `vendor_boot_a`+`init_boot_a`. Ahorra 1 flash pero mete la variable «kernel experimental»; si arranca
  hasta `Linux version` el veredicto de H1 sigue siendo claro (y además deja el SMMU en marcha). Elegir
  según batería/presupuesto; **la de 3 flashes es el control**.

**E2 — El BCB, solo si E1 falla (2 flashes).** Limpiar `misc` con 4 MiB de ceros
(`build/misc-zeros-4m.img`, recomendación de `DECISION-misc-BCB.md`), reintentar el arranque de A (la
cadena ya restaurada en E1). Si arranca ⇒ H2 era la causa (y hay que actualizar el modelo del ABL);
si no, H2 muere y quedan H3/H6. Coste: 1 flash de 4 MiB + el que haga falta para volver a B.

**E3 — Estado/GPT del slot (0-1 flashes, solo lectura primero).** Con la tablet en fastboot:
`fastboot getvar all` completo (los 4 contadores + `current-slot`) y `qbootctl` desde Linux
(`build/slot/qbootctl-aarch64`, `-c`/`-a`/`-b`/`-n` son seguros; `-m` está prohibido sin crítica).
Comparar los attrs de `*_a` vs `*_b`. Si E1+E2 fallan, esta es la vía para ver si el ABL tiene a A por
«no bootable» por algo que no son los datos.

**Orden recomendado:** E0 (gratis) → fsck (Parte A, 5–10 min) → E1 → (si falla) E2 → E3.

## B.6 Lo que NO he verificado (y cómo se cierra)

1. **Los ceros actuales de `vendor_boot_a`/`init_boot_a`**: medidos por la sesión forense, citados en
   `ciclo-restaurar-slot-a.sh`; no re-medidos aquí (sin tablet). → **E0**.
2. **Qué es exactamente el `init_boot_b` de hoy** (no es el stock y no coincide en tamaño con ningún cpio
   del repo). → **E0** (dd + sha + guardar copia).
3. **El estado post-ciclo de los contadores de slot** (los getvar del 28-sep no están en el repo). → **E0**.
4. **El resultado del flash de prueba del 27-sep de `boot-arch-diag.img`** (F5-B1): no hay acta en el repo;
   el sha del fichero en disco (`9cbbe9d9…`) **no coincide** con el pre-registrado (`98d1b40b…`). Si se
   usa C-1, re-verificar antes de flashear.
5. **El estado del fstab/e2fsck dentro de la tablet** (yo lo he leído de la **imagen**, no del aparato).
   → bloque de A.2.1 (es el primer comando del runbook).
6. **La ventana del fallback del init s181** (el dump dice infinita; medido en el cpio, no en el aparato).

## B.7 Cambios de estado que propongo escribir (no los he escrito: fuera de mi alcance)

- `F-plan-por-fases.md` §F9: sustituir «lo común a los 4 es boot nueva en slot A» por **«lo común es
  arrancar desde A, que está incompleto (`vendor_boot_a`/`init_boot_a` a ceros)»**, con el criterio de
  hecho apuntando a **E1**.
- `docs/historia/ESTADO-VIVO.md`: añadir que la cadena real es `boot`(kernel solo) + `vendor_boot`(DTB+ramdisk) +
  `init_boot`(`/ukeinit`), y que **el fsck es prerequisito antes de E1** (reboot).
- `build/gates/ciclo-restaurar-slot-a.sh`: su cabecera ya describe H1; **corregir** que las fuentes de
  `vendor_boot_a`/`init_boot_a` no pueden ser a ciegas las "stock" del repo: el `/ukeinit` que corre **no
  está** en el `init_boot` stock (`5228e6e2…`, es el ramdisk genérico de Android) ni en el `vendor_boot`
  stock de la ROM. Las fuentes deben ser **las imágenes medidas en E0** (`vendor_boot_b-lee.img`,
  `init_boot_b-lee.img`). Restaurar con el `init_boot` stock dejaría a A sin userspace y el ciclo se
  leería como una refutación **falsa** de H1.

---

### Anexo — comandos de una línea (chuleta para la mañana)

```bash
# 0) consola (UN lector) + SSH
cat /dev/ttyACM0 | tee ~/proyectos/out/acm-$(date +%H%M).log        # en una terminal del PC
build/gates/uke-ssh.sh -i                                          # en otra

# 1) backup + diagnostico (A.2.2/A.2.3)  -> ver bloques literales
# 2) fsck (A.2.4)  -> nohup setsid e2fsck -f -y -v /dev/disk/by-partlabel/userdata
# 3) verificar (A.2.5) -> e2fsck -fn x2, rc=0
# 4) reboot (A.2.7) -> sync; systemctl reboot -f

# F9
# E0: dd | sha256sum de *_a y *_b (solo lectura) + guardar init_boot_b/vendor_boot_b
# E1: fastboot flash vendor_boot_a <vendor_boot_b-lee.img>; fastboot flash init_boot_a <init_boot_b-lee.img>;
#     fastboot flash boot_a build/backup-par-bueno/boot_b-lee.img; fastboot set_active a; fastboot reboot
```
