# INFORME-K10-BUILD — boot-ukek10.img = kernel K9 SIN recompilar + arming del probe por ukeinit en ventana con consola (pivot #P28)

Fecha: 30-sep-2026 madrugada. Autor: agente constructor K10. **Trabajo sin tablet** (prohibido fastboot/adb/ssh/ttyACM0).
Encargo: `#P28` (`PRE-REGISTRO-PANTALLA.md`) — los tres boots tempranos armados murieron MUDOS (#P23/#P27/#P28): el probe corre a 0,44 s
pero `ttyGS0` no nace hasta 3,57 s ⇒ cero migas. **K10 difiere el arming al ukeinit** (initramfs): consola viva, UFS aún sin probear.

Arena: `/var/tmp/uke-k10` (scripts, ukeinit, logs, unpack de verificación). Árboles y `~/gpu-work` SOLO lectura. Ningún `git commit`.

---

## 0. Entregables y shas

| fichero | bytes | sha256 |
|---|---|---|
| **`build/bootimg/boot-ukek10.img`** (imagen final, 96 MiB) | 100663296 | **`7ce2cc2d89487ca75192c35fb418b8dae76ddc14534f86d08a9c203ac861c235`** |
| kernel dentro de la imagen (byte a byte el **K9**, sin recompilar) | 16576161 (gz) / 41355776 (crudo) | `03ed849b51f0728c8ac65d0848925d370f6c73bfa5a2b82305fbede4932294be` (== Image.gz del build K9, INFORME-K9 §0) |
| `build/bootimg/repack-k10-report.txt` (gates G0–G8) | — | — |
| initramfs K10 (initrd externo, `/var/tmp/uke-k10/uke-k10-initramfs.cpio.gz`) | 1013256 | `2877714649100be34a480e938cf031fec92c9a6d718340c2b93a20381d0412c2` |
| `build/gates/ukeinit-k10.diff` (35 líneas: bloque de arming + contexto) | — | — |
| `/ukeinit` original (built-in del kernel K9) | 14957 | `0fa49ef98ebc8bf83bda8ce55c1c92ca10376266a1e14a103b7c18ee5a58b2a4` |
| `/ukeinit` K10 (con arming) | 16572 | `7344a88a26855429ab672b5d90e8371101181071f7affa3ea60a800c8f9304d8` |
| cmdline de la imagen | **356 B** | — (ver §2; == K9 menos el token probe) |
| base del repack (shell) | 100663296 | `e3c60969269c0b36f23a37db5b1772128891232517c8d7979bd967b88acab206` (`boot-s240-mem2g.img`) |
| referencias K9/K8 | — | `f21cc35f…` / `5e34596a…` (ambas re-verificadas en G0) |

## 1. Hallazgo estructural (cómo se cambia el ukeinit sin recompilar)

1. El initramfs de los boots K1..K9 **NO viaja en el boot.img**: `ramdisk_size@12 = 0` en el shell s240 y en toda la serie K.
   Va **embebido en el kernel** (`CONFIG_INITRAMFS_SOURCE="…/s21/rescue-dump/s181-initramfs.cpio.gz"`, `CONFIG_INITRAMFS_COMPRESSION_GZIP=y`).
   El blob gzip del Image descomprimido (offset 35336040) es **byte a byte** el cpio de s181 (1938432 B, sha `f398a31b…`).
2. El `/ukeinit` que ejecuta `rdinit=/ukeinit` es el **init de rescate s118/s181** (14957 B), NO el `ukeinit-arch` de
   `mkarch-initramfs.py` (ese cpio vive aparte en `build/bootimg/initramfs-arch-uke.cpio.gz` y no forma parte de la serie K).
3. El kernel K9 tiene `CONFIG_BLK_DEV_INITRD=y` y **sin** `CONFIG_INITRAMFS_FORCE` ⇒ acepta un **initrd externo** y lo
   desempaqueta DESPUÉS del built-in sobre el mismo rootfs: **los ficheros del externo sobreescriben por nombre a los del built-in**.
4. K10 entrega como initrd externo **el mismo cpio de s181 con UNA entrada sustituida** (`/ukeinit` con el arming).
   El resto de las 42 entradas (busybox, symlinks, dump-log.sh, nodos de directorio) es byte a byte el built-in
   (gate 4.9 de verify: solo difiere el `filesize` de la cabecera del ukeinit). Cabeceras conservadas (ino/mtime/mode).

Consecuencia operativa: el boot desarmado queda **idéntico** (req. d) — mismo kernel, mismo userspace; el initrd externo
solo sustituye el script init. Si se quitara el arming del cpio, K10 sería K9-desarmado salvo la cmdline.

## 2. Cmdline K10 (356 B) — reconstruida limpia y verificada byte a byte

```
mem=2048M rdinit=/ukeinit panic=10 memmap=0x1A12800$0xE3940000 console=tty0 fbcon=map:0 hung_task_timeout_secs=20 hung_task_panic=1 watchdog_thresh=10 console=ttyGS0,115200 fw_devlink=permissive clk_ignore_unused pd_ignore_unused arm-smmu.disable_bypass=0 arm_smmu.uke_smr_max=0 arm_smmu.uke_keep_boot=1 arm_smmu.uke_attach_log=2 arm_smmu.uke_reset_mask=12
```

- = cmdline K9 (382 B, == K8/K7 byte a byte) **menos el token ` arm_smmu.uke_smmu_probe=1`** (verificado por `replace`, gate 3.3:
  `cmd == cmd_k9.replace(" arm_smmu.uke_smmu_probe=1","")`; el token NO era el último, por eso no vale añadirlo al final).
- Primeros 255 B == base s240 byte a byte (gate 3.4); 4 tokens `uke_` presentes UNA vez cada uno (3.5); sin espacios dobles,
  NUL-terminada limpia (3.6); tokens de consola/rdinit/panic/mem intactos (3.7). El probe queda **diferido y DESARMADO** al boot
  (los params smr_max/keep_boot/attach_log/reset_mask solo configuran el camino armado; sin `uke_smmu_probe=1` el probe del
  apps-smmu devuelve `-EPROBE_DEFER` y no ejecuta ni una línea del instrumental, INFORME-K9 §6.1).

## 3. La línea añadida al ukeinit (req. a–e), con su contexto

Insertada entre el fin de la espera de `/dev/ttyGS0` (línea 178 del original) y el bloque `S123: switch_root` —
ventana 3,6–13 s: el nodo de consola existe a 3,57 s y el UFS no enumera particiones hasta 13,8 s.

```sh
[ -e /dev/ttyGS0 ] || kmsg "S118 ACMFALLO: sin ttyGS0 tras 60 s"      # <- contexto: fin de la espera de consola

# ============ K10 (#P28): ARMING del probe del apps-smmu CON CONSOLA VIVA ============
UKEP=/sys/module/arm_smmu/parameters/uke_smmu_probe
if [ -w "$UKEP" ]; then
  kmsg "UKE-K10: param presente (valor=$(cat "$UKEP" 2>/dev/null)) a $(cut -d. -f1 /proc/uptime)s"
  sync
  kmsg "UKE-K10: armando probe a $(cut -d. -f1 /proc/uptime)s (ttyGS0: $([ -e /dev/ttyGS0 ] && echo si || echo NO))"
  echo "uke: UKE-K10 armando probe por sysfs" > /dev/ttyGS0 2>/dev/null
  ( sync; echo 1 > "$UKEP" 2>/dev/null; kmsg "UKE-K10: armado rc=$? a $(cut -d. -f1 /proc/uptime)s" ) &
else
  kmsg "UKE-K10: param AUSENTE o RO (kernel sin uke_smmu_probe) - SIN arming, boot desarmado intacto"
fi

# ============ S123: switch_root a Ubuntu (fase 2) ============        # <- contexto: lo que sigue, intacto
```

Decisiones documentadas:

- **(a) Solo si el param existe**: guarda `[ -w "$UKEP" ]` + `2>/dev/null` en el echo. Con un kernel sin `uke_smmu_probe`,
  miga a kmsg y cero arming (boot desarmado intacto).
- **(b) Migas antes/después**: `UKE-K10: armando probe a <N>s` y `UKE-K10: armado rc=<N>` por kmsg (ring + consola), y la de
  arming además por `/dev/ttyGS0` directo (doble canal; si el kernel muere, lo que ya entró en el FIFO del ACM se leyó).
- **(c) Desprendido**: el arming corre en subshell en background tras `sync` — PID1 jamás bloquea en el nodo del param y el
  flujo S123 (fsck/mount/switch_root) sigue su curso. El probe en sí corre en el workqueue del deferred (async); si se cuelga,
  se cuelga un kworker; si el kernel muere entero, las migas ya salieron. Diagnóstico extra: si falta la miga `armado rc=`,
  la muerte quedó DENTRO del propio arming.
- **(d) Resto intacto**: solo se añade ese bloque; gates 4.9 (resto del cpio byte a byte s181) y 5.x (kernel/AVB/cola).
- **(e) Diff separado**: `build/gates/ukeinit-k10.diff` (35 líneas, labels con los shas de origen).

## 4. Gates

### 4.1 Initramfs (`build-initramfs-k10.py`, G0–G4) — VERDE

cpio built-in extraído del Image de `boot-ukek9.img` == s181 (G1); 43 entradas, solo `/ukeinit` sustituido, cabeceras conservadas,
round-trip exacto (G2); el ukeinit del cpio == `ukeinit-k10`, migas presentes y arming ANTES del switch_root (G3);
`gzip -9n` determinista, round-trip, **+637 B vs s181 (+0,06 %, ±10 % OK)** (G4). Sintaxis `sh -n` del ukeinit: OK.

### 4.2 Repack (`repack-k10.py`, G0–G8 → `build/bootimg/repack-k10-report.txt`) — VERDE

G0 shas de las 4 entradas (s240/K9/K8/initramfs). G1 cabecera v4 (header_size 1584, ramdisk_size base 0). G2 cmdlines (§2).
G3 initramfs (43 entradas, ukeinit con arming, ±10 %). G4 kernel: sha == Image.gz K9, crudo 41355776, UKE-POKE=114, 9 params.
G5 ensamblado: `kernel_size@8=16576161`, kernel @4096..16580257, `ramdisk_size@12=1013256`, ramdisk @16580608..17593864,
cmdline @44..400. G6 forma/AVB (AVB0@35438592, AVBf@100663232). G7 deltas: vs s240 confinado a kernel_size+cmdline+kernel+
ramdisk_size+ramdisk (el hueco de la base era todo ceros: **sin dtb/second que pisar**); **vs K9 confinado a cmdline +
ramdisk_size + ramdisk ⇒ kernel byte a byte K9**. G8 publicación + relectura.

### 4.3 Verificación independiente (`verify-k10.py`, 35 gates → `/var/tmp/uke-k10/verify-k10.log`) — **TODOS VERDES**

Forma (96 MiB, v4, AVB0/AVBf) · kernel (sha 03ed849b…, == rango de K9, crudo idéntico, instrumental completo) · cmdline
(356 B, == K9 sin el token probe, 255 B base == s240, tokens únicos) · initramfs (sha del ramdisk en la imagen, cpio 43
entradas, `/ukeinit` == `7344a88a…`, arming único/desprendido/guardado, resto byte a byte s181, +0,06 %) · zonas intactas
(cola AVB == s240, cabecera 1580..4096 == s240, hueco cero, deltas confinados) · herramientas: `unpack_bootimg` rc=0 (kernel y
ramdisk extraídos == esperados) y `avbtool info_image` rc=0 (Footer 1.0, VBMeta offset/size == K9). Nota AVB heredada de K1..K9:
el digest del hash descriptor es el del contenido anterior; `verify_image` no aplica y falla igual con `boot-ukek7.img` (que arrancó).

## 5. Timeline esperado del boot K10 (predicción pre-registrada)

| t | evento | evidencia esperada |
|---|---|---|
| 0,00–0,44 s | kernel; probe del apps-smmu difiere **DESARMADO** (sin token probe) | primer defer `0,44 s` (tren-1 #P20) |
| ~1–3 s | dwc3 registra UDC; ukeinit monta pseudo-FS (mounted a mano) | kmsg ukeinit |
| **3,57 s** | gadget BOUND, `/dev/ttyGS0` vivo | `X9USB-BIND-ok` + `ACMOK` |
| **~4–5 s** | ukeinit pasa el bloque K10: migas `UKE-K10: armando probe a Ns` (kmsg+ACM) → arming desprendido | **consola viva** |
| ~5–6 s | el `.set` dispara `driver_deferred_probe_trigger()`; el probe ARMADO corre con **UKE-POKE visibles**: ID0/1/2, barrido handoff, fases 4-7 (mask 0xc), attach… | migas UKE-POKE en consola |
| **13,8 s** | UFS (ufshc) probea y pide su grupo IOMMU — con consola viva y el SMMU ya bindeado si sobrevivió | migas de attach del UFS |
| ~15,6 s | S123 monta userdata y `switch_root` → arranque normal (SSH) | `X9S123-SWITCH` + `EXT4-fs … mounted` |

## 6. Tabla desenlace → siguiente jugada

| desenlace | lectura | siguiente jugada |
|---|---|---|
| **VIVE** (migas completas + switch_root + SSH) | el probe ARMADO sobrevive en la ventana ~5 s con consola viva y sin UFS — el asesino de la serie K era el contexto temprano (0,44 s), no el probe en sí | SSH → **runbook R2** (re-bind del panel §7 → card0 → modetest/escalera CM3 → foto). Después: arming en frío por defecto si el dueño lo decide |
| **MUERE con migas** | la **ÚLTIMA MIGA visible = punto de muerte exacto** (por fin con consola): p.ej. `wmask[fase1]` (sGFSR RMW incondicional), lectura de IDR/cfg_probe, o el arming mismo (si falta `armado rc=`) | K11 según el punto: F1 silenciable, barrido troceado, o mover el arming más tarde; cada hipótesis es un rung de repack/recompilación dirigido |
| **MUERE MUDO de nuevo** (sin ttyGS0 ni `UKE-K10: armando…`) | el sistema muere ANTES del ukeinit ⇒ causa fuera del SMMU (kernel, dtbo, hardware) — dato nuevo, la serie K nunca había muerto desarmada | rollback inmediato y diagnóstico del boot desarmado (K9-h2 murió armado; esto sería desarmado = terreno distinto) |

## 7. Fila de pre-registro propuesta (#P29/K10) — ANTES de flashear

> **#P29 — K10 (arming diferido por ukeinit; ventana con consola)** · artefacto `build/bootimg/boot-ukek10.img` sha256
> `7ce2cc2d89487ca75192c35fb418b8dae76ddc14534f86d08a9c203ac861c235` (100663296 B; kernel_size@8 = 16576161 = K9 byte a byte;
> ramdisk_size@12 = 1013256; cmdline 356 B = K9 sin `arm_smmu.uke_smmu_probe=1`) · initramfs initrd externo `28777146…`
> (cpio s181 + `/ukeinit` `7344a88a…` con arming; diff `build/gates/ukeinit-k10.diff`) · **canal**: `fastboot flash boot_b`
> (dtbo_b s258 sin tocar) · **gate previo obligatorio**: batería ≥ 3 700 000 µV por getvar (#P26/#P27), captura de consola viva,
> watcher USB, rescate armado, portátil enchufado · **predicciones**: §5/§6 · **rollback**: `fastboot flash boot_b
> build/backup-par-bueno/boot_b-lee.img` (`ffff8c51…`) + baile de slots · **recordatorio**: NUNCA `unbind` del apps-smmu.

Riesgos residuales declarados (honestidad de construcción): (1) es el **primer boot.img de la serie K con ramdisk externo** —
el ABL de stock usa esa vía v4 normalmente, pero en esta tablet no se había ejercitado; si el ABL no cargara el initrd, el boot
usaría el built-in SIN arming = K9 desarmado (no wedge nuevo, resultado: el experimento no dispara, migas `UKE-K10` ausentes);
(2) el arming a ~4-5 s es más tarde que la ventana Android (0,543 s) y más tarde que K7 (0,44 s): si el asesino es una lectura
temprana que requiere el SMMU recién-handoff, K10 puede morir donde K7 no — eso TAMBIÉN es dato (migas visibles).
