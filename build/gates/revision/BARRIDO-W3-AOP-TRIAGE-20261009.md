# BARRIDO W3 — Triaje estático aop_a.bin (idea E, con binario real) — 2026-10-09

Dump: `build/evidencia/aop-dump-20261009/aop_a.bin` (524288 B,
sha256 `3353ea91c49833360b038ba9284f6c917b9352260f6e967a587b37977fc642a0`;
`aop_b.bin` idéntico, mismo sha) + `aop_config_a.bin` (524288 B,
sha256 `45df23554c8e9c0e4602e3ed0088dad71f48a01e6796f1345ee0a244df452ba6`).
Ref plan: `docs/historia/revision/BARRIDO-FASE3-RE-20261009.md` §3.
Runtime ref nuevo: `build/evidencia/aop-dump-20261009/golden-state-full.txt` (cmd-db VIVO).
DT stock: `build/evidencia/stock-dt/stock2-Cliffs7P-uke.dts`.
Disasm de trabajo (no commiteado): scratch `aop_dis.txt`
(`llvm-objdump --arch-name=riscv32 -d`, 79888 líneas).

Corrección al plan §3: `e_machine = 0xf3` **NO es QDSP6/Hexagon** (Hexagon = 0xa4);
0xf3 = 243 = **EM_RISCV**. El AOP de este SoC es RISC-V RVC soft-float, static,
sin section headers. Versión fw: `AOP.HO.5.0-00758-LANAI_E-1` (fileoff `0x16056`).

## 1. ELF: phdrs, entry, código vs certs

`readelf -h -l` aop_a.bin: EXEC, entry `0x13200000`, 11 phdrs (verificado por parse
python independiente — mismos números):

| ph | tipo | fileoff | vaddr | filesz | memsz | flags |
|---|---|---|---|---|---|---|
| 0 | NULL | 0x0 | — | 0x194 | 0 | — (hdr) |
| 1 | LOAD | 0x1000 | 0x0b000000 | 0x14328 (82728) | 0x18000 | RWX |
| 2 | LOAD | 0x16000 | 0x0b0e0000 | 0x9a00 (39424) | 0xc000 | RW- |
| 3 | LOAD | 0x20000 | 0x81c00000 | 0xc74c (51020) | 0x14000 | RW- |
| 4 | LOAD | 0x2d000 | 0x81c14000 | 0x8c (140) | 0x8000 | RW- |
| 5 | LOAD | 0x2e000 | 0x81c1c000 | 0x161e0 (90592) | 0x44000 | RWX |
| 6 | LOAD | 0x45000 | 0x14686000 | 0x4644 (17988) | 0x4644 | RWX |
| 7-8 | LOAD | 0x45000 | 0x1468e000/0x1468f000 | 0 | 0 | RW- |
| 9 | LOAD | 0x4a000 | 0x14692000 | 0x1000 | 0x1000 | RW- |
| 10 | NULL | 0x4b000 | — | 0x2f28 (12072) | 0x2f28 | — |

- Total LOAD filesz = 285988 B = **54,5% del dump**; resto 238300 B =
  hueco `0x4b000-0x80000` + certs. **NO es solo-certs: el criterio de parada no aplica.**
- Cola `0x4b000+`: cadena Qualcomm **SRoT MBNv7** (`Image Signing Root CA 6 SubCA 10`,
  `CASS - SBL40v0`) — firma QTI, sin Xiaomi (a diferencia del zap).
- Anomalía citada: **entry `0x13200000` no cae en ningún LOAD** (verificado por script).
  Los vaddrs son las direcciones físicas de carga fastboot; el entry es el del MBN
  firmado (base de link distinta). No bloquea el análisis: las refs absolutas internas
  (lui 0x81c00/0x81c60/0x81c80) confirman que el mapa `0x81cxxxxx` es el runtime real.

Cobertura de desensamblado (capstone 5.0.7 en venv temporal, modo
RISCV32+RISCVC; llvm-objdump como fuente primaria):

| segmento | contenido real |
|---|---|
| ph1 `0x0b000000` (82 KB) | 38 insns / 0,1% → **DATOS** (tablas de recursos T1, strings `0x132f0+`) |
| ph5 `0x81c1c000` (90 KB) | 30747 insns / **97,6% → CÓDIGO fw AOP** |
| ph6 `0x14686000` (18 KB) | 47,3% → mixto código/datos |

`aop_config_a.bin`: 4 phdrs, entry `0x81c82014`, solo 8814 B LOAD (**1,7%**);
LOAD1 `0x81c80000` (7808 B, strings `vrm.*`/`ldo*`: config de placa) +
LOAD2 `0x81c82000` (1006 B código). Encaja con DT
`aop_config_region@81c80000` (stock2 L176-180). Es blob de config+solver, no fw.

## 2. Strings: recursos votados y cruce DT + cmd-db vivo

T1 (ph1, fileoff `0x132f0-0x13d80`, vaddr `0x0b0122f0+`): `aop_apps/mpss/adsp/cdsp/wpss`,
`QMP_TOUT`, `PM_PROP_*_RAIL`, tabla de nombres ARC
`gfx.lvl mss.lvl ddr.lvl mmcx.lvl nsp.lvl mxc.lvl lnoc.lvl nsp2.lvl | vrm.gfx vrm.mmcx |
cx.lvl mx.lvl xo.lvl ebi.lvl lcx.lvl lmx.lvl` (fileoff `0x134d9-0x135e4`),
`AOPWASTATE STARCDI1/3 drvs_ddr_votes starc StarcFrq/StarcUpd ARC PRE1/2 ARCPOST1/2
AUXtoAOP wlan_pdc* arc_therm pdc_global/seq/en/tcs aop_server AOP External/DDR Log
AOPABORT PDC_IRQ PDC_GLOB BCM_CHNG PDC_WA AOP_TIME CNOC_ON/OFF EnabCNOC DDR VOTE
RSC_NEED rpmh_sys arc_resc bcm_resc_low/high VOTEINFO cx_vote gfx.mol mmcx.mol
adb_vote clock bcm_starc_0 bcm_snd_*`. Cero hits `gpu/gmu/gx/collapse/retention`:
**el AOP no conoce la GPU; solo arbitra rails por nombre.**

T2 (ph3, fileoff `0x20560+`, vaddr `0x81c00560+`): descriptores ARC de **48 B/recurso**
(`lvl[16] + 8 B + tmr[16] + 8 B`; stride verificado `cx.lvl@0x20560 → mx.lvl@0x20590`).
Cada descriptor lleva la **dirección ARC** que coincide con el cmd-db vivo al byte:

| recurso (fileoff) | campo dir en imagen | cmd-db vivo (golden-state-full.txt:9-25) |
|---|---|---|
| cx.lvl `0x20560` | `0x00030000` | `0x30000: cx.lvl` ✓ |
| ebi.lvl `0x205c0` | `0x00030020` | `0x30020: ebi.lvl` ✓ |
| gfx.lvl `0x20650` | `0x00030050` | `0x30050: gfx.lvl` ✓ |
| gfx.tmr | `0x00030054` | `0x30054: gfx.tmr` ✓ |

Cruce DT stock2: los 10 `qcom,resource-name = "*.lvl"` (L6324-6536:
cx/nsp/mss/mxc/mmcx/mx/lcx/lmx/ebi/**gfx.lvl→pmxr2230_s4_level** L6534-6548,
phandle `0x14a`) existen TODOS en T1/T2. `aop_cmd_db_region@81c60000` (L168-171)
y `aop_image_region@81c00000` (L162-166, `0x60000` B: la imagen llena
`0x81c00000-0x81c60000` incl. BSS de ph5) cuadran con el dump.

Niveles vivos (runtime, el dato nuevo): `gfx.lvl = [00 38 40 80 c0 e0 100 140 180
190 1a0 1b0 1c0]`, **`gfx.mol = 0x38`**; `cx.lvl = [00 10 40 80 c0 100 140 180 1a0]`,
`cx.mol = 0x40` (= LOW_SVS). `0x38` es exactamente el nivel base del
`gpu_opp_uke` de s269 (255 MHz): el suelo que AOP impone a GX coincide con el
opp mínimo que mainline usa. Sin contradicción GX a este nivel.

Tabla `vrm.gfx/vrm.mmcx` (ph3, fileoff `0x21774+`, vaddr `0x81c01774+`): registros de
24 B `[magic 0x01000010][nombre 8 B][subtipo 4/8][u32 0x007fe3xx][0]` — 4× vrm.gfx,
4× vrm.mmcx, luego vrm.mss… (solvers VRM por rail; los ptr `0x007fe3xx` no están en
ningún LOAD — ¿offset a TCM no dumpeada o handle? **abierto**).

## 3. Código: tratamiento de gfx.lvl

Función de bring-up en `0x81c1c240-0x81c1c300` (PT_LOAD#5+0x240):
selección condicional por bytes de enable (`lbu …0x36c/0x370/0x374(0x08407xxx)`)
de pares de bases y llamada a rutina común `0x81c21e12`:

- `lui a0,0x81c00` (= `0x81C00000`, tabla T2) y `lui a1,0x81c60` (= **`0x81C60000`,
  cmd-db**, = DT L171) → `jal 0x81c1d50e` (disasm:29400-29440, instr `81c1c24a/260`).
- `lui a0,0x81c80` (= **`0x81C80000`, aop_config**, = DT L178) y `lui a1,0x81ca0`
  → `jal 0x81c1d50e` (disasm `81c1c280/296`).

Registro por grupos en `0x81c1c38e-0x81c1c3e6` (misma callee `0x81c21e12`, 4 callers
en total incl. `0x81c2113e` genérico):

| call | a2 (tabla) | a4 | a0/a3/a5 | qué es |
|---|---|---|---|---|
| `81c1c3a8` | `0x81C00560` = **T2 cx.lvl** (fileoff `0x20560`) | `0x81C003A0` (array niveles u16) | 3 / 0x1c / 0x1c0 | grupo cx |
| `81c1c3c6` | `0x81C00820` = **T2 cx.mol** (fileoff `0x20820`, string `cx.mol@0x20818`) | `0x81C00800` | 3 / 0xe / 0x1c | tabla .mol (suelos) |
| `81c1c3e6` | `0x81C000E8` | `0x81C00000` | 5 / 0x1d / 0xe8 | cabecera/magic |

**No hay call site específico de gfx**: gfx.lvl se procesa por el path genérico
(el grupo cx es el ejemplo visible; los demás grupos se registran igual vía la
estructura de 48 B). No se encontró voto GX con nivel distinto del de mainline:
el fw no contiene niveles propios para gfx (los arrays de niveles u16 en ph3 son
los del cmd-db; el suelo runtime `gfx.mol=0x38` = base opp s269). Chequeos negativos:
sin refs a base RSC `0xadd4000` (`lui 0xadd4` = 0 hits), sin `lui 0x30` (ARC
`0x30000` absoluto — los accesos ARC van por descriptor, no por inmediato),
`gpu/gmu/gx` ausentes en strings.

## 4. Veredicto: qué responde del bloqueo CM3 y qué no

**Responde (VIAS-GPU V2 parcialmente confirmada en su mitad AOP):**
(i) el AOP de este SoC es RISC-V (no Hexagon) y el dump es fw real + tablas
(54,5% LOAD, firma SRoT MBNv7 QTI) — la RE directa es viable, no refutada;
(ii) el AOP **sí arbitra `gfx.lvl`** (descriptor @fileoff `0x20650` = ARC `0x30050`,
rutina de registro genérica, suelos `.mol`, strings `gfx.mol/cx_vote/VOTEINFO`) —
el rail GX tiene un dueño-firmware además del driver;
(iii) el mapa runtime del fw (`0x81c00000` imagen / `0x81c60000` cmd-db /
`0x81c80000` config) es el del DT al byte — s269 hereda bien esas regiones;
(iv) a nivel rail **no hay contradicción con mainline**: suelo vivo `0x38` =
opp mínimo s269; AOP no vota clocks/BW de GPU (sin `gpu/gmu/gx`), solo nivel de rail.

**NO responde (sigue abierto para S3-rst0):**
(a) el orden temporal voto-GX-AOP vs `fw_start`/HFI del GMU (falta correlación con
`beginVoteGxOn` — blanco FASE3 §4 intacto);
(b) si el hang S3-rst0 es fetch-SMMU vs polls (eso lo deciden P1/P2, ya en curso);
(c) qué significan los ptr `0x007fe3xx` de la tabla vrm.gfx y los lui a
`0x0840xxxx/0x0821xxxx` (¿TCM/IMEM no dumpeada? solo se dumpeó `aop_a`+config);
(d) la secuencia RSCC de INV-KGSL-RE (`0x3b11←0x80c808a0`): sin traza en AOP
(el fw no toca RSCC por inmediato; la correlación sigue siendo vía driver/APSS).

**Siguiente paso propuesto (no ejecutado, presupuesto tablet 2/2 agotado):**
comparar `gfx.mol`/suelos tras boot con GPU habilitada (k5x/k6x) vs este golden
(idle, GPU disabled): si AOP sube el suelo de gfx al habilitar la GPU, el voto
inicial que `fw_start` debe replicar sale de ahí.
