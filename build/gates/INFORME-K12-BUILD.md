# INFORME-K12-BUILD — boot-ukek12.img (kernel K11 + fix PINEO SOLO-VIVO) + s260-boot-dtbo-dpu-iommus.img (iommus en el display-controller)

Fecha: 30-sep-2026 madrugada. Autor: agente constructor K12. **Trabajo sin tablet** (prohibido fastboot/adb/ssh/ttyACM0).
Encargo: `#P32` — K11 logró arming horneado + SMMU bindeado a ~4 s + dpu auto-reprobea, y falla SOLO en
`dpu_kms_mmu_init failed: -22`. K12 ataca las dos causas cerradas: (1) **DT**: `display-controller@ae01000` sin
`iommus` → dtbo **s260** añade `iommus = <&apps_smmu 0x1c00 0x2>`; (2) **kernel**: el handoff pineaba el SID del
display (idx=6) aunque el BL NO lo tenía vivo (`idx=6 PINADO sin estar vivo`) → su S2CR nunca se escribía. K12
pinea SOLO SMR vivos del BL; los handoff-DT no vivos pasan a masters NORMALES.

Arena: `/var/tmp/uke-k12` (scripts, logs, dtbo, initramfs). Árboles: `rsync -a /var/tmp/uke-k11-tree/ →
/var/tmp/uke-k12-tree/`, build `cp -a /var/tmp/uke-k11-build → /var/tmp/uke-k12-build` (los `.cmd` apuntan a rutas
k11 ⇒ recompilación completa esperada, ~3600 objetos, rc=0, log `/var/tmp/uke-k12/build.log`). K11 y `~/gpu-work`
intactos (boot-ukek11.img re-verificado `acfed4f3…`). MAKE=/usr/bin/make. Ningún `git commit`.

---

## 0. Entregables y shas

| fichero | bytes | sha256 |
|---|---|---|
| **`build/bootimg/boot-ukek12.img`** (imagen final, 96 MiB) | 100663296 | **`7c6bfe0d91a58ae11fe78dcb4c8294f3963a477e67228136bc2818cae0f4c240`** |
| kernel dentro de la imagen = Image.gz del build K12 | 16576737 (gz, **−155 vs K11**) / 41355776 (crudo, mismo tamaño que K9/K11) | `6231e2750d629e567c58c17f6403d037cb338a6ca5d529bdb25ccdbc0c72c039` / crudo `8b3bcd2212adafbaabe523d0489a26c54e613a5c6fc52ede8824595c78f03ae9` |
| cmdline de la imagen | **356 B** | — (copiada BYTE A BYTE de boot-ukek11.img offset 44; cero tokens cambiados) |
| initramfs embebido `/var/tmp/uke-k12/uke-k12-initramfs.cpio.gz` | 1013258 | `cb10ff4096a9e4608da6c61eeafc79eae0f18291b6ada49ece4ea165f1d4169c` (== cpio K11: el arming horneado NO cambia) |
| **`build/bootimg/s260-boot-dtbo-dpu-iommus.img`** (dtbo s260) | 608609 | **`6fbb5173b8af5add34e90dcff9d3dce742f7fa9fe76182eda2db123b39685ad7`** |
| payload dtbo del s260 | 608545 | recompilación dtc determinista del descompilado de s258 + fragmento (G2/G1) |
| diff del kernel | 39 líneas (1 hunk) | `build/gates/patches/k12-pinlive.diff` — `0b266683133f295390817410b810a052040f6478bcb4956341c2befe7112cf54` |
| generador dtbo | — | `build/bootimg/mkdtbo-s260.py` — `26d45c6ff93e6660991479f005f0ae64e82f54edad4fb79cfb11b3de47633b7e` |
| repack | — | `/var/tmp/uke-k12/repack-k12.py`; log `build/bootimg/repack-k12-report.txt` (incluye los gates del dtbo) |
| bases de referencia | — | shell s240 `e3c60969…`; boot-ukek11.img `acfed4f3…`; s258 `f4663ff86b30e23ca48982358030c3d7afbc274246f27d2964398d49d522b371` (608469 B); base-dtb.img `3f973c78…` |
| rollback | — | boot: `build/backup-par-bueno/boot_b-lee.img` (`ffff8c51…`); dtbo: s258 (`f4663ff8…`, probado en K10/K11) |

## 1. Cambio del kernel (parche `build/gates/patches/k12-pinlive.diff`)

UN hunk, `drivers/iommu/arm/arm-smmu/arm-smmu.c @@ -2200,21 +2200,24 @@`, dentro de **`arm_smmu_master_alloc_smes()`**:

- **K11 (original, líneas 2213-2217 del árbol k11)**: si el maestro es un `qcom,handoff-smrs` del DT y el idx NO está
  pineado, hacía `smmu->s2crs[idx].pinned = true` y imprimía `UKE-POKE: … idx=%d PINADO sin estar vivo (no se escribira)`.
  Ese es el bloqueo: S2CR del display jamás escrito.
- **K12 (nuevo, árbol k12 líneas 2202-2221: comentario UKE-K12 en 2206-2216, guard `if (uke_handoff_activo(smmu))` en
  2217, miga nueva en 2219-2220)**: el pin de handoff-no-vivo DESAPARECE. Queda la miga:
  `UKE-K12: handoff no-vivo sid=0x%x -> attach normal (se escribe S2CR)` y el maestro cae al camino normal del mainline
  (find_sme → reclama SME en RAM → write_sme/install_s2cr/write_context_bank).
- **Los vivos siguen intocables**: el barrido (`uke_handoff_pin_sweep`, líneas 699-750) sigue pineando SOLO los SMR con
  VALID=1 en HW (hoy idx 0, sid 0x60 UFS); su rama PINADO del attach (2222-2238) y las guardas de write_sme (2291) /
  install_s2cr (2428) / free_sme (2140) / write_smr (1932) quedan literalmente intactas. El barrido NO añade ni quita
  lecturas (misma superficie de lectura segura #P9/#P32).

Marcador verificado en el binario: `UKE-POKE`=113 (K11 114 − el pr_info del pin muerto), `UKE-K12: handoff no-vivo`=1,
`PINADO sin estar vivo`=**0** (el crumb viejo ya no existe), params `uke_smmu_probe/uke_write_mask/uke_handoff/uke_keep_boot`
presentes. Compile: `make -C /var/tmp/uke-k12-tree O=/var/tmp/uke-k12-build ARCH=arm64 LLVM=1 MAKE=/usr/bin/make -j16 Image.gz` rc=0.

**NOTA HONESTA (para la lectura de la consola)**: la cmdline no cambia (356 B), así que `arm_smmu.uke_write_mask` sigue
en su default **0** = silencio total de las escrituras NUEVAS del camino armado (bit6 attach_sme, bit7 install_s2cr,
bit8 ctxbank; uke_wmask_activo() está vivo desde el arming). Consecuencia: en K12 el attach "normal" del display
reclama el SME e instala el dominio **en RAM** pero las escrituras HW imprimirán sus migas `wmask[attach_sme]:
SILENCIADO write_sme idx=N … (bit6=0)` / `install_s2cr … SILENCIADO` — igual que hizo K11 con DSI/GPU/UFS. K12 deja el
pin fuera del camino (cero escrituras HW nuevas vs K11) y quita el bloqueo del -22; la traducción real del scanout
queda para la jugada siguiente si hiciera falta (§6 tabla, fila 3).

## 2. El cmdline K12 (356 B, byte a byte la de K11)

Extraída de `boot-ukek11.img` offset 44 (campo 1536) y escrita sin ninguna modificación (G6: 0 bytes de cmdline
difieren de K11). Primeros 255 B == base s240; 4 tokens `uke_` (`uke_smr_max=0`, `uke_keep_boot=1`, `uke_attach_log=2`,
`uke_reset_mask=12`); sin `uke_smmu_probe=1` (el arming lo hace el ukeinit horneado a ~4 s).

## 3. El dtbo s260 (`build/bootimg/s260-boot-dtbo-dpu-iommus.img`)

Técnica del generador de la serie (`mkdtbo-s253.py`): payload de s258 → `dtc -I dtb -O dts` → inserción TEXTUAL de un
fragmento `target-path` (sin `&`, phandle literal) → `dtc -I dts -O dtb` → empaquetado dt_table propio. Hallazgos de
construcción: el descompilado de s258 tiene **`__symbols__` en medio del fichero (línea ~3270) y fragmentos detrás**
(1105, 158, 2100-2103) — fdtoverlay aplica los fragmentos en orden de árbol, así que el fragmento nuevo se inserta al
FINAL del nodo raíz, tras el último; `fragment@1105` es el que CREA el subárbol mainline `mdss_ml:
display-subsystem@ae00000` (con `iommus = <0x129 0x1c00 0x02>` en el padre desde s231) y su hijo **`mdss_mdp_ml:
display-controller@ae01000`** (compatible `qcom,palawan-dpu`, SIN iommus). El display-controller es además el master
del DRM msm (`dpu_kms.c:1426 msm_drv_probe(&pdev->dev, …)`).

Fragmento añadido (literal, `fragment@1709` — libre: los usados son 0..N/158/159/160/1101/1105/2100-2103, máx 2103):

```dts
	fragment@1709 {
		target-path = "/soc/display-subsystem@ae00000/display-controller@ae01000";
		__overlay__ {
			iommus = <0x129 0x1c00 0x02>;
		};
	};
```

`0x129` = phandle del apps-smmu en el base-dtb.img (297 decimal, verificado con `fdtget`/`fdtdump`); `<0x1c00 0x02>` =
la banda del display, LA MISMA del `qcom,handoff-smrs = <0x1c00 0x2>` del nodo smmu y del mdss padre — así el dpu
comparte banda con el handoff y `uke_handoff_es_dt(0x1c00,0x2)` lo reconoce (ahora como maestro normal).

Gates dtbo (todos VERDES, log en `build/bootimg/repack-k12-report.txt`): **G0** pins s258/base-dtb + herramientas.
**G2** determinismo: dtc v1.8.1 reproduce el payload s258 **byte a byte** (`ea6ac36e…`) ⇒ el delta del s260 es
exactamente el fragmento. **G1** UN target-path, UNA prop, sin `&`/`__fixups__`, 163 fragmentos numéricos únicos,
1709 libre. **G3** fdtoverlay rc=0 sobre base-dtb.img real: display-controller queda CON `iommus = <0x129 0x1c00 0x2>`
(fdtget + fdtdump), apps-smmu intacto (phandle 297, `qcom,handoff-smrs = <0x1c00 0x2>`), mdss padre intacto, y el
**diff semántico del fusionado s260 vs s258 = EXACTAMENTE 1 línea añadida** (el resto del árbol no cambia). **G4**
`__symbols__`/`__fixups__`/`__local_fixups__`, props de raiz y juego de phandles idénticos a s258 (ni un phandle
nuevo). **G5** dt_table: magic 0xD7B7AB1E, header 32/entry 32/count 1/offset 64/page 4096, roundtrip byte a byte con
`dtbo-extract.py`, 608609 B (+140 vs s258, ±1 %, cabe en dtbo_b 610304 con 1695 de margen). **G6** publicación + sha.

## 4. Gates del repack boot-ukek12.img (todos VERDES — `repack-k12-report.txt`)

G0 entradas (s240/K11/Image.gz/cpio con sha). G1 cabecera v4 (1584, ramdisk 0, gzip @4096). G2 cmdline 356 B == K11
byte a byte, sin probe token, base s240 255 B, sin dobles espacios. G3 kernel: 16576737 B (−155), crudo 41355776,
UKE-POKE=113, UKE-K12=1, "PINADO sin estar vivo"=0, params uke_*, blob embebido @35336040 == cpio K12 byte a byte,
`/ukeinit` con 6 migas UKE-K11 y arming antes de switch_root. G4 ensamblado (kernel_size@8=16576737; hueco a ceros).
G5 forma/AVB (AVB0@35438592, AVBf@100663232). G6 deltas: vs s240 confinado a kernel_size@8 + cmdline + kernel;
**vs K11: cmdline IDENTICA (0 B) + kernel recompilado + cola de 155 B a ceros**. G7 publicación + relectura. G8
`unpack_bootimg` rc=0 (kernel extraído == Image.gz K12) y `avbtool info_image` (Footer 1.0, VBMeta offset 35454976 /
size 1728 == K11).

## 5. Escalera de disparo (#P33/K12 propuesto — ANTES de flashear)

Canal: `fastboot flash dtbo_b build/bootimg/s260-boot-dtbo-dpu-iommus.img` + `fastboot flash boot_b
build/bootimg/boot-ukek12.img` (dtbo_b pasa de s258 `f4663ff8…` a s260 `6fbb5173…`). Gate previo: batería ≥ 3 700 000
µV por getvar, un solo lector ttyACM, watcher USB, portátil enchufado. Rollback: boot_b-lee `ffff8c51…` + dtbo s258
`f4663ff8…` + baile de slots. NUNCA `unbind` del apps-smmu.

Consola esperada, línea a línea (t = K11 real):

| t | línea esperada |
|---|---|
| 0,44 s | `UKE-POKE: apps-smmu @…: primer probe DIFFERIDO…` (desarmado, cmdline sin token) |
| 3,57 s | `S118 ACMOK: /dev/ttyGS0 presente t=3` |
| ~4,0 s | `UKE-K11: param presente (valor=0) a Ns` → `UKE-K11: armando probe a Ns (ttyGS0: si)` → `UKE-K11: armado rc=0` |
| ~4,0 s | `UKE-POKE: apps-smmu: REINTENTO del probe, consola ya viva.` → ID0/1/2, cfg_probe, `handoff: PREPARAR` → barrido → `PIN SMR(0) id=0x60 …` → `FIN barrido: … PINADOS=1` |
| ~4,0 s | fases 4-7 del reset con migas `wmask[…]: SILENCIADA/SILENCIADO (bit0/1/2=0)` (igual que K11) → **bind** |
| **~4,1 s** | dpu re-probea solo: `find_sme(dev=… sid=0x1c00 mask=0x2) -> N` → **`UKE-K12: handoff no-vivo sid=0x1c00 -> attach normal (se escribe S2CR)`** ← NUEVA (y ya NUNCA `idx=… PINADO sin estar vivo`) |
| ~4,1 s | migas wmask `SILENCIADO write_sme/install_s2cr idx=N (bit6/7=0)`: el mapeo del display queda en RAM (§1 nota honesta) |
| **~4,1 s** | `dpu hardware revision:0xa0010000` y **SIN** `dpu_kms_mmu_init failed` → `msm_dpu: bound ae94000.dsi / ae96000.dsi / 3d00000.qcom,kgsl-3d0` → **`[drm] Initialized msm …`** → card0 |
| 13,8 s | UFS: attach de sid 0x60 → `idx=0 PINADO (vivo del BL)` (intocado, como siempre) |
| 40-90 s | switch_root → SSH |

## 6. Tabla desenlace → siguiente jugada

| desenlace | lectura | siguiente jugada |
|---|---|---|
| **VIVE con `Initialized msm` + card0 + fbcon en pantalla** | las dos causas del -22 eran el bloqueo completo; la receta cierra | modetest/FOTO (runbook R2 para el panel si hace falta). Si el scanout fuera con faults esporádicos, activar bit6/7/8 (K13, fila 3) para dejar el mapeo escrito en HW |
| **`dpu_kms_mmu_init failed: -22` PERSISTE** (con la miga UKE-K12 ya visible) | el pin ya no es; el -22 nace DENTRO de `msm_iommu_new` (msm_iommu.c:726): es `iommu_paging_domain_alloc` vs `iommu_attach_device` vs `msm_gem_vm_create` (msm_kms.c:180-206) — candidato anotado: el tipo de dominio (el impl qcom declara `def_domain_type = IDENTITY` para todo menos WLAN) contra el paging domain del msm | **K13**: añadir migas en `msm_kms_init_vm`/`msm_iommu_new` con el errno intermedio (y `iommu_dev` elegido: mdp_dev vs mdss_dev), repack solo del kernel |
| **card0 vivo pero SIN imagen / fault de IOMMU en scanout** (CFE de sid 0x1c00) | el S2CR del display necesita dominio REAL escrito en HW: con `uke_write_mask=0` el attach lo dejó solo en RAM (§1) y el stream queda sin match (bypass o fault según el sCR0 que dejó el BL) | siguiente jugada: cmdline K13 con ` arm_smmu.uke_write_mask=0x1c0` (bit6 attach_sme + bit7 install_s2cr + bit8 ctxbank) para que el attach escriba SMR/S2CR/CB de verdad (los vivos siguen pineados; el barrido los protege) |
| **MUERE mudo / antes del ukeinit** | causa fuera del SMMU (nunca visto desarmado en la serie K) | rollback inmediato (boot_b-lee `ffff8c51…`, dtbo s258) y diagnóstico del boot desarmado; la última miga visible = punto de muerte |
| **Wedge por el dtbo** (boot no llega a kernel o muere antes del defer) | s260 aplicado por el ABL toca algo que el fusionado no muestra | rollback dtbo s258 `f4663ff8…`; el G3 (diff de 1 línea contra base real) hace esto improbable |

## 7. Fila de pre-registro propuesta (#P33/K12) — ANTES de flashear

> **#P33 — K12 (fix pineo-solo-vivo + s260 iommus display-controller)** · artefactos `boot-ukek12.img` sha256
> `7c6bfe0d91a58ae11fe78dcb4c8294f3963a477e67228136bc2818cae0f4c240` (100663296 B; kernel_size@8=16576737; cmdline 356 B
> == K11 byte a byte; initramfs K11 intacto) y `s260-boot-dtbo-dpu-iommus.img` sha256
> `6fbb5173b8af5add34e90dcff9d3dce742f7fa9fe76182eda2db123b39685ad7` (608609 B; = s258 + fragment@1709 con
> `iommus = <0x129 0x1c00 0x02>` en display-controller@ae01000; gates G0-G6 verdes) · kernel `6231e275…` = K11 +
> `build/gates/patches/k12-pinlive.diff` (arm-smmu.c `arm_smmu_master_alloc_smes`, hunk @@ -2200,21 +2200,24 @@:
> handoff-DT no vivo → master normal, miga `UKE-K12`; vivos pineados intactos) · **canal**: `fastboot flash dtbo_b` +
> `fastboot flash boot_b` · **gate previo**: batería ≥ 3 700 000 µV, watcher USB, rescate armado · **predicciones**:
> §5/§6 · **rollback**: boot_b-lee (`ffff8c51…`) + dtbo s258 (`f4663ff8…`) + baile de slots · **recordatorio**: NUNCA
> `unbind` del apps-smmu; capturar consola completa (la escalera se lee en las migas, no en un solo resultado).

Riesgos residuales declarados: (1) recompilación completa ⇒ binario no byte a byte K11 (relink/utsversion), como
siempre desde K10; (2) `uke_write_mask=0` deja el mapeo del display en RAM (§1): K12 quita el bloqueo del driver pero
NO garantiza traducción HW — por eso la fila 3 de la tabla; (3) el s260 añade iommus al nodo que el msm mainline
espera, pero el ABL podría rechazar el dtbo completo si algo del fusionado no le gusta (mitigado: diff de 1 línea,
payload reproducible byte a byte, mismo formato de empaquetado que la serie).
