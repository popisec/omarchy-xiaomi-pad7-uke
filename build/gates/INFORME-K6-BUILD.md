# INFORME-K6-BUILD — kernel K6: el volcado BL sin la lectura letal de S2CR(0)

Fecha: 2026-09-29 (madrugada). Autor: SG-K6.
Punto de partida: **K5** ya aplicado en `/var/tmp/uke-k1` (árbol) y `/var/tmp/uke-k1-build` (`O=`),
según `build/gates/INFORME-K5-BUILD.md` y `build/gates/patches/k5-attach.diff`.

Contexto medido (#P13, `build/gates/PRE-REGISTRO-PANTALLA.md`; trail `~/proyectos/out/k5b-migas.log`):
con `uke_attach_log=1` el disparo K5b murió **antes del primer print del volcado BL**. Lo único que
el volcado hacía y no estaba medido era `readl(S2CR(0))` (0xc00), el registro de traducción **VIVO
del UFS**; `SMR(0)` es seguro (leído 4 veces hoy). K6 = K5 con **UN cambio**: el volcado no lee S2CR.

> Recordatorio operativo: aquí **NO** se ha tocado la tablet (ni adb, ni fastboot, ni ssh). Solo se
> ha trabajado en `/var/tmp/uke-k1`, `/var/tmp/uke-k1-build` y `/var/tmp/uke-k6`. `~/gpu-work` solo
> lectura. En `omarchy-uke` solo hay ficheros **NUEVOS** sin commitear.

---

## 0. Entregables y shas

| fichero | bytes | sha256 |
|---|---|---|
| `build/bootimg/boot-ukek6.img` | 100663296 (96 MiB exactos) | `c2038e089cbc48dbd514420d5d8b6c6f15678ca0744c22cc7f3a1078d1eb6ced` |
| `build/gates/patches/k6-dump.diff` | 2564 B, 51 líneas, **1 hunk**, 1 fichero, +19/−11 | `dd167e3788f01055e841b6ef0791cf8200c712f243a103e9f57a42b09e7365f2` |
| kernel fuente del empaquetado (`Image.gz`) | 16567869 (K5: 16564346, ver §2) | `ac878610f9a982a4b11fdd75bf844005944d07084324eba57e2ce4016d94a20c` |
| kernel desempaquetado (`Image`) | 41355776 = 39,44 MiB (delta tamaño 0 vs K1-K5) | `850941e4138ead0a12581c8de23202d7a6c886818bab3fc1c7c70072180a6056` |
| `vmlinux` (K6) | 421688400 | `1d8cf2c44672d8394aa7fe8e501fc2f1234d640924d6219a5449dc0b55d08af3` |
| `arm-smmu.c` de K6 (K1+K2+K3+K4+K5+K6) | 108616 B | `0f6f30062ee83918c8876fcbcf7b0859f88fe88ae826d9afbff92a348a6ff6e7` |
| `arm-smmu-qcom.c` de K6 (**sin cambios** vs K5) | 35126 B | `3ed87c75b708798027aa7b6c8e40441e47178e5cdca5d2e132a6688e6af55974` |

```
$ git status --short
?? build/gates/patches/k6-dump.diff
?? build/pkg/panel-o82/            # de otro agente
$ git check-ignore -v build/bootimg/boot-ukek6.img
.gitignore:25:build/bootimg/*.img    build/bootimg/boot-ukek6.img
```

---

## 1. El cambio exacto (único)

**Nota de ubicación:** `uke_dump_bl_state()` vive en **`arm-smmu.c`** (líneas 470-512), **no** en
`arm-smmu-qcom.c` (el encargo nombraba `arm-smmu-qcom.c`, pero allí no hay volcado; el diff lo
confirma: un solo fichero). El parche va contra el árbol K5 y aplica con `patch -p1`.

Los dos únicos sitios (un solo hunk, porque están a 12 líneas):

```diff
@@ -476,29 +476,37 @@
 	smr0 = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_SMR(0));
-	s2cr0 = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_S2CR(0));
-	pr_info("UKE-POKE: BL estado idx=0: SMR(0) HW=0x%08x (valid=%u id=0x%x mask=0x%x) S2CR(0) HW=0x%08x (TYPE=%u CBNDX=%u PRIVCFG=%u)\n",
+	/* UKE-SMMU-CLK (K6, #P13): S2CR(0) NO se lee. ... s2cr0 queda a 0 ... */
+	s2cr0 = 0;
+	pr_info("UKE-POKE: BL estado idx=0: SMR(0) HW=0x%08x (valid=%u id=0x%x mask=0x%x) S2CR(0) HW=<NO LEIDO (letal #P13)> (s2cr0=%u)\n",
 		smr0, (unsigned int)FIELD_GET(ARM_SMMU_SMR_VALID, smr0),
 		(unsigned int)FIELD_GET(ARM_SMMU_SMR_ID, smr0),
-		(unsigned int)uke_smr_mask_leido(smr0),
-		s2cr0, (unsigned int)FIELD_GET(ARM_SMMU_S2CR_TYPE, s2cr0),
-		(unsigned int)FIELD_GET(ARM_SMMU_S2CR_CBNDX, s2cr0),
-		(unsigned int)FIELD_GET(ARM_SMMU_S2CR_PRIVCFG, s2cr0));
+		(unsigned int)uke_smr_mask_leido(smr0), s2cr0);
 ...
 		smr = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_SMR(i));
-		s2cr = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_S2CR(i));
-		pr_info("UKE-POKE: BL estado idx=%d (...): SMR(%d) HW=... S2CR(%d) HW=0x%08x (TYPE=%u CBNDX=%u)\n", ...);
+		s2cr = 0;
+		pr_info("UKE-POKE: BL estado idx=%d (...): SMR(%d) HW=... S2CR(%d) HW=<NO LEIDO (letal #P13)> (s2cr=%u)\n", ...);
```

Y **nada más**: `arm-smmu-qcom.c` idéntico byte a byte; K1-K5 intactos. Las dos lecturas
`gr0_read(...S2CR(0))` que quedan en el árbol están en la fase de **attach** (`arm-smmu.c:1725` y
`:1809`, ramas de ESCRITURA del idx 0 con `uke_attach_log>=1`) y no se han tocado (fuera del
alcance del encargo; ver §3).

Verificación de alcance (el gate que pedía el encargo):

```
$ awk '/^static void uke_dump_bl_state/,/^}/' arm-smmu.c | grep gr0_read
	smr0 = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_SMR(0));
		smr = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_SMR(i));      <-- SOLO SMR
$ grep -rn "gr0_read.*S2CR" drivers/iommu/arm/arm-smmu/
arm-smmu.c:1725   (attach, intacta)
arm-smmu.c:1809   (attach, intacta)
```

---

## 2. Gates

**Build (rc=0)** — `/usr/bin/make -C /var/tmp/uke-k1 O=/var/tmp/uke-k1-build ARCH=arm64 LLVM=1
MAKE=/usr/bin/make Image.gz` (log `/var/tmp/uke-k6/k6-build.log`): `CC arm-smmu.o` + AR/LD/MODPOST/
KSYMS/OBJCOPY/GZIP — la misma secuencia que el build K5.

> Nota operativa nueva: el entorno del harness trae la variable `MAKE` apuntando a
> `~/.local/bin/ZCode.AppImage`; sin `MAKE=/usr/bin/make` el sub-make **no compila nada**
> (rc=0 y no-op: se detecta con `make -n`). Pasar siempre `MAKE=/usr/bin/make`.

**Binario** (`Image` descomprimido):
* `strings` → `NO LEIDO (letal` **x2** (una por miga), las dos format strings exactas x1 cada una,
  `uke_attach_log` x2; resto de marcadores K5 intactos (UKE-POKE x60, `BL estado idx=0`,
  `S2CR(0) HW AHORA`, `ESCRIBIR SME idx=`, 9 params `__param`); **`PRIVCFG` x0** (el formato viejo
  del volcado ha desaparecido).
* Desensamblado de `uke_dump_bl_state` en `vmlinux` (`/var/tmp/uke-k6/dump-disasm.txt`): solo hay
  cargas a `base+0x800` (SMR(0)) y `base+0x804+4i` (SMR(i)); **ningún `0xc00`** (S2CR); `s2cr0` y
  `s2cr` son 0 literales pasados a los dos `printk`; `pr_flush(500,false)` sigue al final.
* Banner esperado: `7.2.0-rc2-palawan … #9 SMP PREEMPT Tue Sep 29 01:02:11 CEST 2026` (K5: #8).

**Tamaño (matiz honesto):** `Image.gz` = 16567869 B vs K5 16564346 = **+3523 B (+0,021 %)**; la
ventana nominal ±3 KiB se queda 451 B corta (vs K4 16565056 = +2813 B, dentro). Causa mecánica: el
cambio elimina un `readl`+argumentos → `arm-smmu.o` −1312 B (440720 → 439408) → re-layout del link
(12,84 M bytes distintos en el `Image` sin comprimir, **mismo tamaño 41355776**), y gzip deja de ser
comparable byte a byte tras un relink. Todos los gates de contenido pasan.

**Empaquetado** (patrón K5 exacto, `/var/tmp/uke-k6/repack-k6.py`): base s240-mem2g `e3c60969…` ok;
cmdline s244/K5 **255 B byte a byte** sin token; `kernel_size@8=16567869`; **96 MiB**;
AVB0@35438592 y AVBf@100663232 presentes; cola intacta byte a byte; delta vs K5 todo en
`kernel_size@8` + ventana kernel.

Independientes sobre el fichero final:
```
$ ls -la build/bootimg/boot-ukek6.img                → 100663296 B
$ dd … skip=8 count=4 | od -An -tu4                  → 16567869
$ unpack_bootimg --boot_img … --out …                → rc=0; kernel == Image.gz (cmp IDÉNTICO)
$ avbtool info_image --image …                       → rc=0 (footer AVB)
```

---

## 3. Escalera (la de K5; ahora el volcado sobrevive)

**Paso 0 — sano:** `fastboot flash boot_b boot-ukek6.img` (sha `c2038e08…` pre-registrado ANTES) +
dtbo b = s258 (panel vivo). Banner `#9`. Params esperados en reposo:
`uke_smmu_probe=N uke_keep_boot=N uke_reset_mask=65535 uke_smr_max=-1 uke_stream_match=Y
uke_attach_log=0 uke_protect_smr0=N`.

**Paso 1 — captura:** `ssh … "dmesg -n 7; dmesg -w" > ~/proyectos/out/k6-migas.log` + consola serie
(un solo lector por canal).

**Paso 2 (A, `uke_attach_log=1`)** — `smr_max=0`, `keep_boot=1`, `attach_log=1`, `protect_smr0=0`,
`probe=1`; bind SIEMPRE desprendido y **al final**. Lo nuevo de K6, tras `SMR loop OK`, es que la
miga del volcado **por fin sale**:

```
UKE-POKE: BL estado idx=0: SMR(0) HW=0x00000060 (valid=1 id=0x60 mask=0x0) S2CR(0) HW=<NO LEIDO (letal #P13)> (s2cr0=0)
```

→ reset (fase2 OMITIDA, fase3 CB×71, TLBI, mmu500, sCR0) → `test_smr_masks OMITIDO` → tormenta de
attach. **OJO**: las 2 lecturas S2CR(0) que quedan (1725/1809) viven en la rama de escritura del
idx 0 con `log>=1`; si el ufshc llega a su `ESCRIBIR SME idx=0`, la de 1725 puede matar **antes del
flush** de ese bloque (el dump, ya flush-eado, sobrevive: eso es lo que compra K6). Si muere en el
attach, la última línea flush-eada es el punto exacto.

**Paso 3 (B, `uke_attach_log=2`)** — preserva el SME vivo del BL (ufshc). Con `log=2` las ramas que
contienen 1725/1809 se **omiten** (`continue` previo) → no se escribe ni SMR(0) ni S2CR(0).
Esperado: `SME idx=0 PRESERVADO (BL vivo)` + `install_s2cr idx=0 PRESERVADO` y **bind completo**
(grupos en `/sys/kernel/iommu_groups/`, apps-smmu fuera de `devices_deferred`). El UFS sigue con la
traducción que dejó el BL (la que hoy le funciona).

**Paso 4 (C, solo si B no basta)** — `uke_protect_smr0=1`: reubica el SME en un idx libre alto
(duplica el match del sid 0x60; es discriminante, no configuración final).

**Paso 5** — con el bind completo: re-bindear dpu/mdss, buscar `Adding to iommu group` + `card0` en
`/sys/class/drm/`.

| desenlace | siguiente jugada | qué se aprende |
|---|---|---|
| muere justo tras la miga del volcado | anotar; el volcado ya no es el sospechoso | ¿reset? (contradice K4) |
| muere en `ESCRIBIR SME idx=0` (ufshc) / sin línea "idx=0 AHORA" | **B**: `log=2` | la lectura 1725 o el write_sme sobre lo vivo |
| muere en `ESCRIBIR SME idx=k>0` (idx libre) | anotar dev/idx; `log=2` | ¿escribir SMR en general mata? (contra K3) |
| muere en `install_s2cr …` | `log=2` si es el preservado; anotar | el S2CR del attach (BYPASS→quirk) |
| muere en `write_context_bank cfg=asignado` | anotar CB | el CB del dominio pisa uno vivo |
| bind completo | Paso 5 | **el SMMU es utilizable con handoff** |

---

## 4. Qué NO se ha hecho

* No se ha flasheado nada ni se ha hablado con la tablet (sin adb/fastboot/ssh).
* `~/gpu-work` no se ha modificado (solo lectura). `~` solo lectura.
* Sin commits: los únicos ficheros NUEVOS de K6 en `omarchy-uke` son
  `build/gates/patches/k6-dump.diff`, `build/bootimg/boot-ukek6.img` (ignorada por `.gitignore:25`)
  y este informe.
* Las 2 lecturas `S2CR(0)` del attach (1725/1809) quedan **como en K5** a propósito (el encargo
  pedía no tocar nada más); su riesgo está anotado en §3.

## 5. Copias de trabajo y reproducibilidad

| ruta | contenido |
|---|---|
| `/var/tmp/uke-k1` | árbol K1+K2+K3+K4+K5+K6 (`arm-smmu.c 0f6f3006…`, `arm-smmu-qcom.c 3ed87c75…`) |
| `/var/tmp/uke-k1-build` | `O=` (config del #82, `Image.gz` K6 `ac878610…`, `vmlinux`, logs) |
| `/var/tmp/uke-k6/` | `k6-dump.diff`, `repack-k6.py`, `repack-k6-report.txt`, `unpack/`, `k5-from-img.gz`/`k5-Image` (K5 empaquetado), `k6-Image(.gz)`, `dump-disasm.txt`, `k6-build.log`, `repro/` |
| `build/gates/patches/k6-dump.diff` | el parche de K6 (contra K5), copia del de `/var/tmp/uke-k6/` |

Cadena reproducida y comparada byte a byte (snapshot K5 → aplicar K6):

```
$ cp /var/tmp/uke-k6/repro/… (copia K5: arm-smmu.c f52b34a3…, qcom 3ed87c75…)
$ patch -p1 -d repro < build/gates/patches/k6-dump.diff
$ sha256sum repro/drivers/iommu/arm/arm-smmu/arm-smmu.c
0f6f30062ee83918c8876fcbcf7b0859f88fe88ae826d9afbff92a348a6ff6e7   (= K6, IDÉNTICO)
```

Es decir: K5 (a su vez `k1..k5` en orden) + `k6-dump.diff` reproducen exactamente el árbol con el
que se ha construido y empaquetado `boot-ukek6.img`.
