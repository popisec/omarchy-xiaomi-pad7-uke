# INFORME-K11-BUILD — boot-ukek11.img = kernel K9 RECOMPILADO con el ARMING HORNEADO en el ukeinit del initramfs INTERNO (receta final, #P30)

Fecha: 30-sep-2026 madrugada. Autor: agente constructor K11. **Trabajo sin tablet** (prohibido fastboot/adb/ssh/ttyACM0).
Encargo: `#P30` (PRE-REGISTRO-PANTALLA.md) — K10 probó el arming por initrd **externo** y hoy se demostró que **el ABL de esta
tablet NO carga el initrd externo** (ramdisk_size@12 ignorado; solo migas del built-in). K11 hornea el mismo bloque dentro del
kernel: **boot → ukeinit interno arma a ~5 s (consola viva desde 3,57 s, UFS sin probear hasta 13,8 s) → SMMU bindeado →
dpu probea a 13,9 s y ENCUENTRA el IOMMU → kms init → card0**.

Arena: `/var/tmp/uke-k11` (scripts, ukeinit, logs, initramfs, unpack-verify). Árboles: `rsync -a /var/tmp/uke-k9-tree/ →
/var/tmp/uke-k11-tree/`, build `cp -a /var/tmp/uke-k9-build → /var/tmp/uke-k11-build`. **K9 y `~/gpu-work` intactos** (re-verificado:
boot-ukek9.img `f21cc35f…`, .config K9 sigue apuntando a s181, s181-initramfs.cpio.gz `310eea9a…` solo lectura).
MAKE=/usr/bin/make siempre. Ningún `git commit`.

---

## 0. Entregables y shas

| fichero | bytes | sha256 |
|---|---|---|
| **`build/bootimg/boot-ukek11.img`** (imagen final, 96 MiB) | 100663296 | **`acfed4f39962871ad016c14621edc86000f189cda500c2f35978ff2c7adfe5b8`** |
| kernel dentro de la imagen = Image.gz del build K11 | 16576892 (gz, **+731 vs K9**) / 41355776 (crudo, mismo tamaño que K9) | `c3c41fb0236557bd8fdc0e6d9a35fa1e58675df051fe89d2066f4c7f018a2eba` |
| Image crudo (vmlinux binario) | 41355776 | `af50c429b7aeb31d481892d76d7c3b717250927550644e0c80eb9bb1ef612625` |
| cmdline de la imagen | **356 B** | — (== K9 382 B menos ` arm_smmu.uke_smmu_probe=1`; 255 B base s240 + 4 tokens uke_) |
| initramfs horneado `/var/tmp/uke-k11/uke-k11-initramfs.cpio.gz` | 1013258 (s181: 1012619, **+639 B = +0,06 %**) | `cb10ff4096a9e4608da6c61eeafc79eae0f18291b6ada49ece4ea165f1d4169c` |
| `/ukeinit` K11 (con arming, 323 líneas) | 16572 | `fcdd63f14a99171976f1c038d4110fe7eb57695de452ccfa42021914527d81fc` |
| `/ukeinit` original (s118/s181 built-in, 297 líneas) | 14957 | `0fa49ef98ebc8bf83bda8ce55c1c92ca10376266a1e14a103b7c18ee5a58b2a4` |
| diff del ukeinit | 35 líneas | `/var/tmp/uke-k11/ukeinit-k11.diff` |
| base del repack (shell) | 100663296 | `e3c60969269c0b36f23a37db5b1772128891232517c8d7979bd967b88acab206` (`boot-s240-mem2g.img`) |
| referencias | — | K9 `f21cc35f…`, K8 `5e34596a…` (re-verificadas en G0/G2) |

## 1. Mecanismo del initramfs interno (cómo se hornea el ukeinit)

1. `/var/tmp/uke-k9-build/.config`: `CONFIG_INITRAMFS_SOURCE="~/gpu-work/ramaa/s21/rescue-dump/s181-initramfs.cpio.gz"`,
   `CONFIG_INITRAMFS_COMPRESSION_GZIP=y`. En `usr/Makefile`, un fuente **único** terminado en `.cpio.*` se usa **directamente**
   (`cpio-data := $(ramfs-input)`, `compress-y := copy`): el fichero `usr/initramfs_inc_data` es **byte a byte** el .gz fuente
   (verificado en el build K9: `usr/initramfs_inc_data` == s181, sha `310eea9a…`), se `.incbin`-ea en `usr/initramfs_data.o` y
   viaja dentro del Image.gz (blob @35336040 del Image crudo). No va en el boot.img: `ramdisk_size@12 = 0` en s240 y toda la serie K.
2. El `/ukeinit` que ejecuta `rdinit=/ukeinit` es el init de rescate s118/s181 (14957 B) del cpio s181: 43 entradas newc.
3. K11: se generó `/var/tmp/uke-k11/uke-k11-initramfs.cpio.gz` = cpio s181 con **UNA entrada sustituida** (`/ukeinit` con el
   bloque de arming), cabeceras ino/mode/mtime/uid/gid intactas, round-trip exacto, `gzip -9n` determinista (mtime 0) —
   la misma mecánica cpio que K10 (`build-initramfs-k10.py`), aquí como **fuente del CONFIG_INITRAMFS_SOURCE**.
4. En el build K11, `.config` línea 236 → `CONFIG_INITRAMFS_SOURCE="/var/tmp/uke-k11/uke-k11-initramfs.cpio.gz"`.

## 2. La compilación incremental

- Comando: `/usr/bin/make -C /var/tmp/uke-k11-tree O=/var/tmp/uke-k11-build ARCH=arm64 LLVM=1 MAKE=/usr/bin/make -j16 Image.gz`
  (log `/var/tmp/uke-k11/build.log`, rc=0).
- El cambio de fuente dispara exactamente lo esperado en usr/: `COPY usr/initramfs_inc_data` (el .gz nuevo) →
  `AS usr/initramfs_data.o` → `AR usr/built-in.a` → relink completo (`LD vmlinux…`, `OBJCOPY Image`, `GZIP Image.gz`).
- **Nota honesta**: la primera pasada recompiló 3610 objetos, no solo usr/. Causa: los `.cmd` del build dir copiado llevan
  las rutas absolutas del build K9 (`/var/tmp/uke-k9-build`/`-tree`) y `if_changed` las vio cambiadas. El binario es
  equivalente (mismo árbol fuente K9 + mismo `.config` salvo `INITRAMFS_SOURCE`; 408/10096 páginas 4K del Image crudo
  difieren de K9 = relink + utsversion + initramfs). Segunda pasada: **0 objetos, 2,9 s** (estado incremental estable,
  log `/var/tmp/uke-k11/build2.log`).
- Desactivar el arming si hiciera falta (documentado, no hay token de cmdline): (a) la guarda `[ -w "$UKEP" ]` salta el
  arming si `uke_smmu_probe` no existe o es RO → miga `UKE-K11: param AUSENTE o RO…` y boot desarmado intacto; (b) el
  `echo 1` lleva `2>/dev/null`, corre en subshell **desprendido** tras `sync` y su fallo no aborta ni bloquea a PID1
  (sigue `armado rc≠0` → S123); (c) para un boot desarmado **garantizado** con la misma receta: `boot-ukek9.img`
  (kernel sin arming horneado).

## 3. Dónde quedó el arming (ubicación exacta)

Diff completo: `/var/tmp/uke-k11/ukeinit-k11.diff` (35 líneas; hunk `@@ -177,6 +177,32 @@`, mismas líneas que
`build/gates/ukeinit-k10.diff` con migas renombradas `UKE-K10`→`UKE-K11`, cero UKE-K10 residuales). En el ukeinit K11
(323 líneas): **después de la línea 178** (`[ -e /dev/ttyGS0 ] || kmsg "S118 ACMFALLO: sin ttyGS0 tras 60 s"` — fin de la
espera de consola del step **S118**) y **antes de la línea 206** (`# ============ S123: switch_root a Ubuntu (fase 2) ===`).
Bloque (líneas 180-205):

```sh
# ============ K11 (#P30): ARMING del probe del apps-smmu CON CONSOLA VIVA ============
UKEP=/sys/module/arm_smmu/parameters/uke_smmu_probe
if [ -w "$UKEP" ]; then
  kmsg "UKE-K11: param presente (valor=$(cat "$UKEP" 2>/dev/null)) a $(cut -d. -f1 /proc/uptime)s"
  sync
  kmsg "UKE-K11: armando probe a $(cut -d. -f1 /proc/uptime)s (ttyGS0: $([ -e /dev/ttyGS0 ] && echo si || echo NO))"
  echo "uke: UKE-K11 armando probe por sysfs" > /dev/ttyGS0 2>/dev/null
  ( sync; echo 1 > "$UKEP" 2>/dev/null; kmsg "UKE-K11: armado rc=$? a $(cut -d. -f1 /proc/uptime)s" ) &
else
  kmsg "UKE-K11: param AUSENTE o RO (kernel sin uke_smmu_probe) - SIN arming, boot desarmado intacto"
fi
```

(más el comentario de 14 líneas que documenta la ventana 3,6-13 s y el arming desprendido). El `.set` del param dispara
`driver_deferred_probe_trigger()`: el probe ARMADO del apps-smmu corre en el workqueue del deferred con consola viva y sin DMA de UFS.

## 4. Cmdline K11 (356 B) — reconstruida limpia y verificada byte a byte

```
mem=2048M rdinit=/ukeinit panic=10 memmap=0x1A12800$0xE3940000 console=tty0 fbcon=map:0 hung_task_timeout_secs=20 hung_task_panic=1 watchdog_thresh=10 console=ttyGS0,115200 fw_devlink=permissive clk_ignore_unused pd_ignore_unused arm-smmu.disable_bypass=0 arm_smmu.uke_smr_max=0 arm_smmu.uke_keep_boot=1 arm_smmu.uke_attach_log=2 arm_smmu.uke_reset_mask=12
```

= cmdline K9 (382 B, == K8/K7 byte a byte) **menos el token ` arm_smmu.uke_smmu_probe=1`** (gate: `cmd == cmd_k9.replace(" arm_smmu.uke_smmu_probe=1","")`). Primeros 255 B == base s240 byte a byte; 4 tokens `uke_` una vez cada uno; sin espacios dobles ni en bordes; NUL-terminada limpia; `console=ttyGS0,115200`, `rdinit=/ukeinit`, `panic=10`, `mem=2048M`, `disable_bypass=0` intactos. Al boot el probe queda **diferido y DESARMADO**; el arming lo ejecuta el ukeinit horneado. (Nota: el encargo decía "→ 364 B"; el cálculo real 382−26 = **356 B**, el mismo tamaño que la cmdline K10 ya verificada.)

## 5. Gates (todos VERDES)

### 5.1 Initramfs (`build-initramfs-k11.py`, G0–G4 → `/var/tmp/uke-k11/build-initramfs-k11-report.txt`)

G0 shas de entradas (K9 `f21cc35f…`, s181 `310eea9a…`, ukeinit-k11 `fcdd63f1…`); `usr/initramfs_inc_data` del build K11 == s181
(compress copy, base coherente). G1 el cpio built-in del kernel K9 (@35336040, 1938432 B) == s181 descomprimido. G2 sustitución
solo de `/ukeinit` (43 entradas, cabeceras intactas, round-trip exacto, delta cpio +1500 B). G3 `/ukeinit` del cpio == ukeinit-k11:
6 migas UKE-K11, cero UKE-K10, guarda `[ -w ]`, arming en background, echo a ttyGS0, arming ANTES de S123/switch_root, `sh -n` OK.
G4 `gzip -9n` determinista, round-trip, +639 B vs s181 (+0,06 %, ±10 % OK).

### 5.2 Image (`verify-image-k11.py`, V1–V5 → `/var/tmp/uke-k11/verify-image-k11-report.txt`)

V1 Image.gz `c3c41fb0…` 16576892 B (+731 vs K9); crudo 41355776 B (mismo tamaño que K9). V2 **blob embebido @35336040 (mismo
offset que K9) == uke-k11-initramfs.cpio.gz BYTE A BYTE**. V3 cpio 43 entradas, orden y cabeceras intactas, solo `/ukeinit` difiere
de s181. V4 `/ukeinit` del Image == ukeinit-k11 (`fcdd63f1…`), 297→323 líneas (+26), orden S118 (l.178) < ARMING (l.180-205) <
S123 (l.206) < switch_root. V5 instrumental K9 intacto: **UKE-POKE=114** y params uke_* presentes.

### 5.3 Repack (`repack-k11.py`, G0–G8 → `build/bootimg/repack-k11-report.txt`)

G0 shas de las 6 entradas. G1 cabecera v4 (header_size 1584, ramdisk_size base 0). G2 cmdlines (§4). G3 kernel K11 recompilado
con arming horneado (blob byte a byte + ukeinit con 6 migas UKE-K11 antes del switch_root). G4 ensamblado: `kernel_size@8=
16576892`, kernel @4096..16580988, `ramdisk_size@12=0` (initramfs DENTRO del kernel), cmdline @44..400, hueco hasta AVB0 a ceros
(la base era cero ahí: sin dtb/second que pisar). G5 forma/AVB: AVB0@35438592, AVBf@100663232, NUL-terminación limpia.
G6 deltas: **vs s240 confinado a kernel_size@8 + cmdline[44..1580) + kernel[4096..16580988)** (cabecera: 103 B distintos);
**vs K9 confinado a las mismas zonas** (cmdline 37 B; kernel 16348016 B distintos = recompilado — no byte a byte K9, ver §2).
G7 publicación + relectura: `boot-ukek11.img` `acfed4f3…`. G8 herramientas: `unpack_bootimg` rc=0 (kernel extraído == Image.gz K11)
y `avbtool info_image` rc=0 (Footer 1.0, **VBMeta offset 35454976 / size 1728 == K9**).

## 6. Timeline esperado del boot K11 (predicción pre-registrada)

| t | evento | evidencia esperada |
|---|---|---|
| 0,00–0,44 s | kernel K11 (crudo == tamaño K9); probe del apps-smmu difiere **DESARMADO** (cmdline sin token probe) | primer defer `0,44 s` (tren-1 #P20) |
| ~1–3,5 s | dwc3 registra UDC; ukeinit monta pseudo-FS, gadget ACM, serial UKE-S120 | `X9USB-BIND-ok` |
| **3,57 s** | `/dev/ttyGS0` vivo | `S118 ACMOK: /dev/ttyGS0 presente t=3` |
| **~4–5 s** | **ukeinit interno pasa el bloque horneado**: `UKE-K11: param presente (valor=0) a Ns` → `sync` → `UKE-K11: armando probe a Ns (ttyGS0: si)` (kmsg + ttyGS0 directo) → arming desprendido → `UKE-K11: armado rc=0` | **consola viva con migas** |
| ~5–6 s | `.set` dispara el deferred: probe ARMADO del apps-smmu con **UKE-POKE visibles** (ID0/1/2, handoff, fases 4-7 con mask 0xc, attach…) | migas UKE-POKE en consola |
| **13,8 s** | UFS (ufshc) probea pidiendo su grupo IOMMU — SMMU ya bindeado si sobrevivió | migas de attach del UFS |
| **13,9 s** | **dpu probea y ENCUENTRA el IOMMU** (era el objetivo: el defer de dpu se resuelve contra el SMMU armado) | `msm-dpu … arm-smmu` en kmsg |
| ~15,6 s | S123 monta userdata y `switch_root` | `X9S123-SWITCH` + `EXT4-fs … mounted` |
| 40–90 s | arranque normal → SSH | ssh a la tablet |

## 7. Tabla desenlace → siguiente jugada

| desenlace | lectura | siguiente jugada |
|---|---|---|
| **VIVE** (migas UKE-K11 + UKE-POKE completas + switch_root + SSH) | el arming horneado a ~5 s sobrevive; SMMU bindeado → dpu encuentra IOMMU a 13,9 s | **card0 → modetest → FOTO** (runbook R2: re-bind del panel si hace falta). La receta queda cerrada: esta es la build final |
| **MUERE con migas** | la **ÚLTIMA MIGA visible en consola = punto exacto de muerte** (por fin con consola viva): p.ej. `UKE-POKE: wmask[faseN]`, lectura IDR/cfg_probe, o el propio arming (si falta `UKE-K11: armado rc=` la muerte quedó DENTRO del arming) | K12 según el punto: silenciar fase (wmask por cmdline `arm_smmu.uke_write_mask=N` — sigue disponible), barrido troceado, o mover el arming más tarde (repack solo del ukeinit en el cpio) |
| **MUERE MUDO** (sin ttyGS0 ni migas UKE-K11) | el sistema muere ANTES del ukeinit ⇒ causa fuera del SMMU (kernel recompilado, dtbo, hardware) — terreno nuevo: la serie K nunca murió desarmada | rollback inmediato (`fastboot flash boot_b build/backup-par-bueno/boot_b-lee.img`) y diagnóstico del boot desarmado |

## 8. Fila de pre-registro propuesta (#P30/K11) — ANTES de flashear

> **#P30 — K11 (arming HORNEADO en el initramfs interno; receta final)** · artefacto `build/bootimg/boot-ukek11.img` sha256
> `acfed4f39962871ad016c14621edc86000f189cda500c2f35978ff2c7adfe5b8` (100663296 B; kernel_size@8 = 16576892; ramdisk_size@12 = 0 —
> el initramfs va embebido en el kernel, el ABL no carga initrd externo; cmdline 356 B = K9 sin `arm_smmu.uke_smmu_probe=1`) ·
> kernel `c3c41fb0…` = K9 recompilado (árbol/`.config` idénticos salvo `CONFIG_INITRAMFS_SOURCE` → cpio K11 `cb10ff40…` con
> `/ukeinit` `fcdd63f1…`: arming tras S118/ttyGS0 y antes de S123/switch_root; diff `/var/tmp/uke-k11/ukeinit-k11.diff`) · **canal**: `fastboot flash boot_b` (dtbo_b s258 sin tocar) · **gate previo obligatorio**:
> batería ≥ 3 700 000 µV por getvar, captura de consola viva, watcher USB, rescate armado, portátil enchufado · **predicciones**:
> §6/§7 · **rollback**: `fastboot flash boot_b build/backup-par-bueno/boot_b-lee.img` (`ffff8c51…`) + baile de slots ·
> **recordatorio**: NUNCA `unbind` del apps-smmu.

Riesgos residuales declarados (honestidad de construcción): (1) el kernel K11 es una **recompilación completa** del árbol K9
(no byte a byte K9): mismo código fuente y `.config`, pero relink/utsversion nuevos — si el asesino dependiera de una dirección
física concreta del código, K11 puede morir distinto a K9 (eso también es dato, con consola); (2) el arming es incondicional
cuando el param existe y es escribible (no hay token de cmdline que lo desactive; desactivación: §2a-c); (3) la ventana ~5 s es
posterior a la de K7 (0,44 s): si el asesino exige el SMMU recién-handoff, K11 puede morir donde K7 no — con migas visibles.
