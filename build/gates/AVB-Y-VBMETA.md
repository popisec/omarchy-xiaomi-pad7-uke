# AVB y vbmeta en uke — mediciones 28-sep-2026

Medido por subagente de solo-lectura, 28-sep-2026 ~13:15–13:20 UTC.
Objetivo: convertir en evidencia en disco la afirmacion del chat de hoy
("vbmeta_a/b identicos, digest declarado ba30b5f7... no cuadra ni con la
imagen que arranca ⇒ el bootloader no impone la verificacion de boot"),
que no aparecia en ningun fichero del repo.

Script re-ejecutable: `build/gates/medir-avb.sh` (auto-contenido, solo lectura;
guarda su salida en `build/gates/medir-avb-<fecha>.log`).
Salida de referencia de esta sesion: `build/gates/medir-avb-20260928-131843.log`.

## 1. Que se midio (comando literal + salida real)

### 1a. Ficheros locales: existen, tamano, sha

```
$ sha256sum build/backup-par-bueno/boot_b-lee.img build/bootimg/boot-pokes.img
ffff8c51265ff03c84cff15ffdb275f396a666a491eb5d67580be705321db99e  build/backup-par-bueno/boot_b-lee.img
11cf34823441bec66ac41a4af2d1a09fbbfdf6fd5ba67b97ff26cccdb32c61a7  build/bootimg/boot-pokes.img
$ ls -l (ambos)
-rw-r--r-- 1 usuario usuario 100663296 (= 96 MiB, ambos)
```

`boot_b-lee.img` = lectura vuelta de la particion que ARRANCA: su sha
`ffff8c51…` coincide con `avb/boot-s244-bounce.img` de `build/gates/SHA-BUENOS.txt`
(par bueno, slot b). No existe ningun `s244-boot-repack.img` en `build/bootimg/`
ni hace falta: `boot_b-lee.img` ES la imagen que arranca.
`boot-pokes.img` (`11cf3482…`) es la que no arranco.

### 1b. Posicion de AVB0 y AVBf (ambas imagenes, mismos offsets)

```
$ grep -abo 'AVB0' boot_b-lee.img ; grep -abo 'AVBf' boot_b-lee.img
35438592:AVB0
35440832:AVB0
35454976:AVB0
100663232:AVBf
```
Identico en `boot-pokes.img`. Footer (64 B al final): `orig_sz=35454976`,
`vbmeta_off=35454976`, `vbmeta_sz=1728` (= 256+320+1152), version 1.0.

### 1c. Descriptor HASH de boot (vbmeta@35454976, avbtool 1.3.0, SHA256_RSA2048)

Parseado a mano con los offsets del spec (los u32 de longitudes se comprobaron
byte a byte; el primer intento con u64 dio basura y se descarto).
El descriptor cubre el rango **[0, 35454976)** = `image_size` del descriptor =
`orig_sz` del footer (cabecera+kernel+ramdisk+blobs incrustados; excluye el
vbmeta anadido, el footer y el relleno de ceros hasta 96 MiB).
Digest = SHA256(salt || bytes[0:35454976]), segun el spec AVB.

```
part=boot halg=sha256 img_sz=35454976
salt(32B):      97b2c53022e8c0bd0b279c4c592a196126a6eb0a93647c2957b39dcd5f2dc1c9
declarado(32B): ba30b5f79e7d994f0a8a53ded618cc9c209042ca6801bcf6ea37d470c0ec304d
```
Salt y digest declarado **identicos** en ambas imagenes (el vbmeta entero lo es,
ver §2). Digests reales calculados sobre el rango declarado:

```
boot_b-lee (ARRANCA):    real=a738e3c831b3a6aadd9893ab4d12571701287de32d7fc113d5e60c2b49368198  COINCIDE: False
boot-pokes (NO arranco): real=deeb4504a7c63d0d5ca88580e545ac90a5bbee3ebe5ee25f1e9ccd891b76331c  COINCIDE: False
```

### 1d. Cross-check con `avbtool verify_image` (solo lectura, symlink en tmpfs)

```
--- boot_b-lee (arranca) ---
vbmeta: Successfully verified footer and SHA256_RSA2048 vbmeta struct in .../boot.img
sha256 digest of .../boot.img does not match digest in descriptor
/usr/bin/avbtool: Error verifying descriptor.
--- boot-pokes ---  (mismo resultado, palabra por palabra)
```

Nota: `avbtool` exige que el fichero se llame `boot.img` (nombre = particion
del descriptor); se uso un symlink en `mktemp -d`, sin copiar ni renombrar
nada del repo. El aviso del encargo ("avbtool falla en ambas porque el digest
cubre el fichero relleno a 96 MiB") es **incorrecto**: avbtool hashea
`salt || primeros image_size bytes` (35454976), no los 96 MiB; falla en ambas
porque el declarado `ba30…` no es el real de ninguna.

### 1e. Donde difieren lee vs pokes

```
$ cmp -l boot_b-lee.img boot-pokes.img | awk ... 
bytes distintos: 15296249 primero: 9 ultimo: 15362366
desde 15362367 hasta EOF: identicos (ramdisk+vbmeta+footer)
```

Diferencias confinadas a cabecera (u32 LE@8: kernel_size lee=16559711,
pokes=15358270; cmdline comun `mem=2048M rdinit=/uk…`) + zona de kernel.
Los 3 blobs AVB0 y el footer son byte-identicos entre ambas (shas en §2).

### 1f. Tablet por SSH (solo lectura, 2 conexiones, ningun `dd` con `of=`)

```
$ ssh -i build/rootfs/uke-arch-root root@192.168.42.129
uptime: 09:05:41 up 1:03, 1 user, load average: 0.00, 0.01, 0.00
/dev/disk/by-partlabel/boot_b -> ../../sde39
/dev/disk/by-partlabel/vbmeta_a -> ../../sde14
/dev/disk/by-partlabel/vbmeta_b -> ../../sde42
-- vbmeta_a -- 131072
0f7399d952e018e6d869044d0fedfda788a9b8df4f183cd5cc08f4a4bc8dd8a4  -
-- vbmeta_b -- 131072
0f7399d952e018e6d869044d0fedfda788a9b8df4f183cd5cc08f4a4bc8dd8a4  -
```

Contenido de `vbmeta_a` (transferido con `dd|ssh` a `/tmp/opencode`, tmpfs;
parseado en el PC): `avbtool 1.3.0`, SHA256_RSA2048, rollback_index 0,
flags 0; descriptores HASH para `dtbo`, `init_boot`, `vendor_boot`
(**no hay descriptor HASH para `boot`**); 3 CHAIN (`boot` loc 3, `recovery`
loc 1, `vbmeta_system` loc 2, pk 520 B cada una); PROPs `Xiaomi/uke_eea`
(OS3.0.303.0.WOZEUXM); 5 HASHTREE (dm-verity, tag 1). La verificacion de
`boot`, si existiera, vendria del vbmeta encadenado en el footer de la
propia particion boot, no de `vbmeta_a`.

```
$ qbootctl   (lee GPT; no escribe)
Current slot: _b
SLOT _a: Active 0, Successful 0, Bootable 0
SLOT _b: Active 1, Successful 1, Bootable 1
```
(`qbootctl -c/-a` no pueden leer `slot_suffix` del cmdline de este arranque
Arch, pero los flags GPT se leen bien.)

```
-- bateria (13:18 UTC) --
/sys/class/power_supply/qcom-battmgr-bat/capacity: 2
/sys/class/power_supply/qcom-battmgr-bat/voltage_now: 3426071
/sys/class/power_supply/qcom-battmgr-usb/voltage_now: 5198000
/sys/class/power_supply/qcom-battmgr-bat/status: Charging
```

⚠️ **3426 mV < 3700 mV del gate de flasheo, y `capacity` dice 2.**
Aunque esta en carga (USB 5.2 V), la sesion principal NO debe flashear
hasta re-medir ≥ 3700 mV.

### 1g. Blobs AVB0 incrustados en la imagen (origen no determinado)

Dentro del rango hasheado hay dos blobs vbmeta (avbtool 1.2.0, RSA4096, rb 0)
con 1 descriptor HASH (img_sz = su propio offset) + PROPs
ARCH/BRANCH/KERNEL_RELEASE, identicos en ambas imagenes:

```
blob@35438592 (2240 B): e2ebffc33de063f080d51fda42d1207486327ba9bb9839afd83c420908966580
blob@35440832 (2240 B): 4354bf7c53d2720700de8234df5e5e418377dac87d6d28d697a0bae6cd634f4e
blob@35454976 (1728 B): 14e8c07d7036c2020c1d411d24b2f8340e54aa284a2100d1d5fb874e091b81c5  <- el del footer
footer (64 B, ambos):   b8d44d5b1596ff1d1bfbfc2a7d0f7dc2d3ba3848d05e88a4d67cf408947cfde4
```

## 2. Tabla resumen

| Objeto | sha256 / digest | B | Veredicto |
|---|---|---|---|
| `boot_b-lee.img` (ARRANCA, = s244 bueno) | `ffff8c51…99e` | 100663296 | DATO |
| `boot-pokes.img` (NO arranco) | `11cf3482…61a7` | 100663296 | DATO |
| vbmeta_a tablet (sde14) | `0f7399d9…8dd8a4` | 131072 | DATO (confirma el chat) |
| vbmeta_b tablet (sde42) | `0f7399d9…8dd8a4` | 131072 | DATO: identica a vbmeta_a |
| digest boot declarado (ambas imgs) | `ba30b5f7…c304d` | 32 | DATO (confirma el chat) |
| digest boot real, lee | `a738e3c8…8198` | 32 | DATO: ≠ declarado |
| digest boot real, pokes | `deeb4504…631c` | 32 | DATO: ≠ declarado |
| rango cubierto por el descriptor | bytes [0, 35454976) | — | DATO (img_sz = orig_sz) |
| slots | b activa/OK, a inactiva | — | DATO (`qbootctl`) |
| bateria 13:18 UTC | 3426 mV, capacity 2, Charging | — | DATO: bajo gate 3700 mV |

## 3. Conclusion: DATO vs INFERENCIA

**DATOS:**
1. La imagen que arranca (`ffff8c51…`, s244, slot b) **no** cumple el digest
   que su propio descriptor AVB declara (`a738…` real vs `ba30…` declarado).
2. `avbtool verify_image` lo confirma de forma independiente, y anade que la
   **firma del vbmeta sí verifica** (`Successfully verified footer and
   SHA256_RSA2048 vbmeta struct`): la cadena de firma existe, lo que falla
   es solo el digest del contenido de boot.
3. La imagen que no arranca falla el digest **de la misma manera** (`deeb…`
   vs `ba30…`), con vbmeta byte-identico: el digest AVB **no discrimina**
   entre la que arranca y la que no. El fallo de pokes viene de otro sitio
   (contenido del kernel: 15 M de bytes distintos), no del AVB.

**INFERENCIA (no lectura del ABL):** este bootloader, en este estado del
dispositivo, **no impone la verificacion del digest de boot**: una imagen con
digest incorrecto arranca igual. No se ha leido codigo del ABL; es una
inferencia a partir de "una imagen que arranca con digest incorrecto".

## 4. Matiz sobre la inferencia (importante)

- La inferencia se sostiene **solo** en el punto 1 de los datos. Es fuerte
  (arrancar con digest incorrecto es incompatible con "verifica y rechaza"),
  pero no dice *por que*: las hipotesis compatibles incluyen bootloader
  desbloqueado / verificacion desactivada (`vbmeta --disable-verification`),
  ABL que solo comprueba la firma del vbmeta y no el digest, o verified-boot
  en modo permisivo. Distinguirlo exige `fastboot getvar unlocked`,
  `getvar verified-boot-state` y similares — fuera del alcance de esta
  sesion de solo-lectura; queda como trabajo para la sesion principal
  cuando entre en fastboot.
- Razon de apoyo (no decisiva): la firma del vbmeta verifica OK mientras el
  digest falla, lo que encaja con "firma sí, contenido no" pero no lo prueba.
- Correccion a una afirmacion del encargo: `avbtool verify_image` **no**
  falla por hashear el relleno a 96 MiB; hashea `salt || [0, image_size)`
  con `image_size=35454976` del descriptor. El fallo es genuino en ambas.

## 5. Estado de la tablet y flash pendiente

- **La tablet NO se ha tocado**: 3 conexiones SSH, todas con comandos de
  solo-lectura (`ls`, `blockdev --getsize64`, `dd … | sha256sum` por stdout,
  `qbootctl`, `cat /sys/...`). Cero escrituras, cero `dd of=`, cero
  reinicios, cero fastboot. La copia de 128 K de `vbmeta_a` vive solo en
  `/tmp/opencode` (tmpfs) como copia de trabajo, no en el repo.
- **Flash pendiente (NO hacerlo desde aqui)**: la sesion principal espera
  flashear `build/bootimg/boot-pokes.img` con sha `11cf3482…` (verificado
  en §1a, intacto). Con la bateria a **3426 mV** ese flash debe esperar a
  carga ≥ 3700 mV y a re-medir antes del ciclo.
- No se commitea: lo revisa la sesion principal.
