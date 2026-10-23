# V2 — Crítica del K23 y del dump del CM3 (1-oct-2026, tarde)

Ronda independiente (subagente solo-lectura) + **verificación propia de los dos hallazgos que
cambian la decisión**. Sin tablet, sin escrituras al dispositivo. Todo con `fichero:línea`.

**Veredicto en una línea: el K23 que está en la tablet no puede responder la pregunta para la que
se construyó, y el fix K24 no es el que estaba diseñado.**

## 1. BLOQUEANTE — el decode de `S2CR` está al revés

`k18-tree/drivers/gpu/drm/msm/adreno/a6xx_gmu.c:324` (versión K19–K23):
```c
UKE_K19_LOG("SME(%d): SMR=0x%08x (id=0x%04x) S2CR=0x%08x (type=%u cbndx=%u)",
            i, smr, smr & 0x7fff, s2cr, s2cr & 0x3, (s2cr >> 16) & 0xff);
```
Layout real, `drivers/iommu/arm/arm-smmu/arm-smmu.h:113-124`:
```
ARM_SMMU_S2CR_TYPE  = GENMASK(17,16)   /* 0=TRANS 1=BYPASS 2=FAULT */
ARM_SMMU_S2CR_CBNDX = GENMASK(7,0)
ARM_SMMU_SMR_VALID  = BIT(31)   ARM_SMMU_SMR_ID = GENMASK(15,0)
```
El código imprime `type` de los bits **bajos** y `cbndx` de los **altos**: invertido.

Medido (`/var/tmp/uke-sesion-console.log`, dump de las 11.7 s):
```
SME(1): SMR=0x80000005 (id=0x0005) S2CR=0x00000001 (type=1 cbndx=0)
SME(2..5): SMR=0x00000000          S2CR=0x00020000 (type=0 cbndx=2)
```
| | impreso | real |
|---|---|---|
| SME(1), **SID 5 = el icache del CM3** | BYPASS | **TRANS por CB1** |
| SME(2..5), SMR inválido | TRANS→CB2 | FAULT, cbndx 0 (irrelevante) |

**Consecuencias** (esto es lo que hay que escribir en la próxima sesión):
- REFUTADA la cadena «SMR inválido → unmatched → bypass → fetch de física 0x4000» (PRE #P47).
  Salía de mirar las filas con SMR inválido.
- REFUTADO el diseño del K19 («programar SMR/S2CR/CB antes del release»): el S2CR ya está bien.
- **K24 = mapear iova 0x4000 en la tabla de CB1.**

## 2. BLOQUEANTE — las dos fórmulas de dirección de CB eran falsas, y ninguna leía CB1

El SMMU es un **MMU-500 / SMMUv2**, no un v3:
- `palawan.dtsi:2536-2539`: `adreno_smmu: iommu@3da0000`, `reg = <0x0 0x03da0000 0x0 0x40000>`,
  `compatible = "qcom,palawan-smmu-500", …, "qcom,smmu-500", "arm,mmu-500"`.
- Arranque medido: `arm-smmu 3da0000.kgsl-smmu: SMMUv2 with: … stream matching with 24 register
  groups … 22 context banks` y **0** líneas de `differs from mapped region`.
- Fórmula del driver: `arm_smmu_cb_offset = (numpage + n) << pgshift`, con `pgshift =
  ID1.PAGESIZE?16:12` y `numpage = 1<<(ID1.NUMPAGENDXB+1)` (`arm-smmu.c:3480,3489-3495,1523`).
  Sin el aviso de mismatch: `2*numpage<<pgshift == 0x40000` ⇒ **pgshift 12, NUMPAGENDXB 4,
  numpage 32** ⇒ **CB0 = 0x20000, CBn = 0x20000+n*0x1000**, CB0..21 = 0x20000..0x35000.

| bucle del dump | fórmula | veredicto |
|---|---|---|
| 1º (`a6xx_gmu.c:328`) | `0x8000 + i*0x1000` | En SMMUv2, 0x8000 es la tabla de **S1CD**, no las CB. De ahí que no haya **ni una** línea `CB(` en todo el log. Desfase real 0x18000 |
| 2º «K21» (`:342`) | `(i<<16)`, i=2..11 | stride de 64 KB = SMMUv3. `i=2`→0x20000 = **CB0 real** (mala etiqueta), `i=3`→0x30000 = **CB16**, `i≥4`→0x40000.. = **fuera del SMMU** (el recurso acaba en 0x40000) |

**CB1 = 0x3dc1000. Ninguno de los dos bucles la leía** — y es exactamente la CB a la que apunta
el S2CR del SID 5. El gate del plan («no flashear K24 sin `CBpage`») era inejecutable con K23.

Además el ioremap de 2 MB de K23 se sale del recurso: lee 0x3DE0000..0x3E50000, donde vive
`gpu_qtb@0x3de8000` (`~/proyectos/ubuntu-uke/dump/p1-vivo-20260903/dmesg.txt:2.378426`). El
machine-check de K19 (abort del resume antes de S3) fue el mismo modo de fallo con 256 KB: leer
fuera. **La rama D del plan v4 era probable por construcción, no solo posible.**

## 3. ALTA — reproducibilidad: el kernel no se podía reconstruir (CERRADO hoy)

- K19/K20/K21/K23 vivían **solo** en `build/kernel-pokes/k18-tree` (`.gitignore:28`, sin `.git`).
- `k13-tree` (la base "pristine") tiene cambios en `arm-smmu.{c,h,impl}`, `arm-smmu-qcom.c`,
  `msm_iommu.c`, `msm_kms.c` que **no están** ni en el commit del fork (`d1c7ef2e0`) ni en su
  working tree ⇒ tampoco era reconstruible desde el hermano.
- `.config` efectivo sin versionar (apunta al cpio K22 con `INITRAMFS_SOURCE` absoluto).
- **Ningún script** compilaba `k18-build`; `build-pokes.sh` compila el árbol del hermano, que no
  tiene la instrumentación.

**Cerrado**: `ACUMULADO-palawan-d1c7ef2e0-a-k24.diff` (8 ficheros, verificado que `patch -p1` sobre
`git archive d1c7ef2e0` reproduce el árbol byte a byte contra `SHA-ARBOL-K24.txt`),
`build/kernel-config/k23b.config`, `docs/historia/gates-palawan/build-k23b.sh`, `gen-diff-acumulado.py`.
`build/init/uke-k22-initramfs.cpio.gz` **sí** estaba versionado (correcto).

## 4. MEDIA — P2-ctrl no es ejecutable tal como está escrito

`modetest` **no está** en el rootfs que hay en la tablet (`debugfs` sobre
`build/rootfs/arch-rootfs.img`: 6540 entradas en `/usr/bin`, 0 coincidencias) y `build/pkg/` no tiene
`mesa`/`libdrm`/`mesa-utils` (sí lo verificó C8 en su día). El canal que cita el plan
(«A1-auditoria-instalador §4 / v2 P3.5») **sí existe y es bueno**
(`build/gates/prepara/A1-auditoria-instalador.md`, 30-sep, §4 = método NCM-USB con las IP
exactas): lo que faltaba era el paso intermedio, **bajar los paquetes**, que es lo que aporta
`build/gates/stage-p2-ctrl.py` (lee las .db de pacman, resuelve el grafo de verdad y deja
MANIFEST + INSTALAR.txt).

> **Corrección 1-oct**: una primera versión de este informe afirmó que el fichero A1 no existía.
> Era falso, y el error era mío por no comprobarlo. Lo detectó la ronda de huellas
> documentales (`V3-huellas-docales.md`). Aplicar la regla 12 de `REGLAS.md`: un decode o una
> cita se comprueban contra el fichero, no de memoria.

- Hace falta: **`libdrm`** (+`libpciaccess`) para `modetest`; **`mesa` + `mesa-utils`** para
  `eglinfo`; y para cerrar el grafo de `mesa`, `llvm-libs`/`libglvnd`.
- Canal: scp al NCM `192.168.42.129` + `pacman -U` offline (sin WiFi no hay `pacman -S`). El método
  del enlace está en A1 §4; el conjunto de paquetes y el procedimiento, en
  `build/gates/prepara/P2-CTRL-STAGING.md` + `build/gates/stage-p2-ctrl.py`.
- Alternativa 0-paquetes para los peldaños (a)-(c): sysfs (`status`, `modes`,
  `regulator_summary`), `/sys/kernel/debug/dri/0/state`, backlight. El peldaño Writeback
  (b) necesita herramienta o ioctl crudo.

## 5. MEDIA/BAJA — resto

- **`repack-k18.py:92`**: el gate de build rancio solo comparaba la mtime de `arm-smmu.c`; un cambio
  solo en `a6xx_gmu.c` —donde vive el dump— colaba un build viejo. **Arreglado** (4 fuentes +
  marcador obligatorio).
- **`repack-k18.py` no tenía `--out`**: el repack del K23 (02:36) escribió `boot-ukek18d.img`, el
  mismo nombre que #P47 había pre-registrado con otro sha. **Arreglado** (`--out`, `--kernel`,
  `--gate-k23b`).
- **`uke_poke()` no hace `pr_flush`** (`uke-panic-fb.c:250`): si el write del release cuelga en
  D-state, `S3-rst0` se pierde y la rama F («S3 sin S4») queda indistinguible de «sin S3».
  **Arreglado en K23b** con `pr_flush` explícito tras `S3-rst0` y tras el `S4-poll*`.
- **`cfg_probe` no sale por consola**: son `pr_info` (KERN_INFO) en el probe del SMMU, pero el
  arranque de la sesión del 30-sep/1-oct no los tiene en el log de 2,1 MB. Sirve sobre SSH/dmesg,
  no en la consola: el grep del plan debe correrse sobre `desperdida-s3s4-full.log` (el volcado), no
  sobre la captura de consola.
- Los 16 patrones del grep de §P0.3 **existen** todos en el kernel del `.img` (verificado
  descomprimiendo el gzip en el offset 4096; el kernel auditado tiene el mismo sha que
  `k18-build/Image.gz`, `6b601cf8…`). La rama F es distinguible: `S3-rst0` se imprime **después** de
  `gmu_write(SYSRESET,0)` y el poll es `gmu_poll_timeout(…,100,100000)` ≈ 100 ms.
- «18 migas» del §P0.3 son 16 alternativas. Cosmético.

## 6. Lo que este informe NO resuelve

- Si la tabla de CB1 mapea o no el 0x4000: **no se puede saber sin el hardware**. K23b lo mide.
- Si el TCM (origen físico del icache) está dentro del dominio IOMMU del GMU con
  `uke_gmu_shared=1` (rango 0x0..0x80000000 en VA): es el subcaso 3 del plan, y también lo dirá
  K23b (si el descriptor es válido pero apunta a un PA que no es el TCM, el fix es un
  `iommu_map` del TCM, no una entrada de tabla).
- El panel (OBJ 6) no se ha tocado: sigue dependiendo de que la GPU llegue a `S4-pollOK`.
