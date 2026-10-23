# INV-GMU-BIN (2026-10-08): anatomía del gen71100_gmu.bin

**Pregunta**: ¿qué necesita el CM3 al arrancar y qué puede faltarle en nuestro entorno
(GPU-on congela el SoC al soltar el reset, S3-rst0; ITCM cargado correcto pero DTCM sin
cambio de ejecución)?

**Método**: 100% offline en el PC. Parseo del contenedor con python3/struct,
desensamblado Thumb-2 (Cortex-M3) con capstone 5.0.9 (pip install --user
--break-system-packages). Referencias: `fw_load`/`fw_start` de
`kernel-pokes/k52-tree/drivers/gpu/drm/msm/adreno/a6xx_gmu.c` y
`registers/adreno/a6xx_gmu.xml`. La tablet NO se ha tocado.

## 0. Verificación de copias

| fichero | md5 |
|---|---|
| `build/pkg/uke-gpu-firmware/gen71100_gmu.bin` | `a02e73fe916137b2c974951c314fac2d` |
| `lib/firmware/qcom/gen71100_gmu.bin` (dentro de `build/init/uke-k34-fw-initramfs.cpio.gz`) | `a02e73fe916137b2c974951c314fac2d` — **IDÉNTICAS** |
| `gen71100_sqe.fw` (pkg vs initramfs) | `cae06160b38f1b0002892a36ef850263` en ambos |
| `gen71100_zap.mbn` (pkg vs initramfs) | `6d0742da447dcaacc8b85b8a0df08a86` en ambos |

Tamaño del gmu.bin: **80680 bytes (0x13b28)**. Consumido íntegro por 15 bloques.

## 1. Contenedor: tabla de segmentos

Formato (coincide con `struct block_header` de `a6xx_gmu.c`, `sizeof = 16`:
`{u32 addr, size, type, value; u32 data[]}`, avance `16 + size`):

El fichero tiene **11 cabeceras con `size==0`** (una TOC/mapa de memoria del build) y
después **4 bloques de payload con `type=0xefbeadde` (= DEADBEEF en LE)**. El driver
salta los `size==0` (`if (blk->size == 0) continue;`) y solo copia los payloads.

### 1a. Cabeceras-TOC (size=0, no se cargan; `value` = tamaño del section en el build)

| # | fileoff | addr (CM3) | type | value | significado |
|---|---------|-----------|------|-------|-------------|
| 0 | 0x000000 | 0x00000000 | 1 | 0x001dc | ITCM @0 (el stub, 476 B) |
| 1 | 0x000010 | 0x00004000 | 1 | 0x1381c | cuerpo del fw (icache BO, 79900 B) |
| 2 | 0x000020 | 0x00000200 | 1 | 0x0396c | sección ITCM @0x200 (la crea el scatter-load) |
| 3 | 0x000030 | 0x00100000 | 1 | 0x1aa78 | SRAM GMU @0x100000 (.data/bss) |
| 4 | 0x000040 | 0x00200000 | 1 | 0x12c80 | SRAM GMU @0x200000 |
| 5 | 0x000050 | 0x00300000 | 1 | 0x24bf8 | SRAM GMU @0x300000 |
| 6 | 0x000060 | 0x10004000 | 1 | 0x02920 | DTCM @base (0x2920 B) |
| 7 | 0x000070 | 0x10007000 | 1 | 0x00f84 | DTCM @0x10007000 (0xf84 B) |
| 8 | 0x000080 | 0x10007fdc | 1 | 0x00018 | DTCM params finales (24 B) |
| 9 | 0x000090 | 0x60000000 | 7 | 0x01000 | (región tipo 7, 4 KiB) |
| 10 | 0x0000a0 | 0x60001000 | 7 | 0x01000 | (región tipo 7, 4 KiB) |

### 1b. Payloads reales (type=0xefbeadde, value=0xefbeadde)

| # | fileoff (datos) | addr (CM3) | size | destino en `fw_load` |
|---|-----------------|-----------|------|----------------------|
| 11 | 0x0c0 | 0x00000000 | 0x1dc (476) | **ITCM**: `ITCM_START + 0` (476 B) |
| 12 | 0x2ac | 0x00004000 | 0x1381c (79900) | **BO icache** (`fw_block_mem`, offset 0 dentro del BO; IOVA 0x4000) |
| 13 | 0x13ad8 | 0x10007f98 | 0x28 (40) | **DTCM**: reg `DTCM_START + (0x3f98/4)` |
| 14 | 0x13b10 | 0x10007fdc | 0x18 (24) | **DTCM**: reg `DTCM_START + (0x3fdc/4)` |

### 1c. Valores K44 localizados (offsets exactos)

| valor | dónde está en el fichero | qué es |
|---|---|---|
| `0x10007f80` | fileoff **0x0c0** (bloque 11, +0x00) = ITCM[0] | **MSP inicial** (top de pila = final del DTCM − 0x80) |
| `0x00000105` | fileoff **0x0c4** (bloque 11, +0x04) = ITCM[1] | **vector reset** = handler @0x104 (bit0 Thumb) |
| `0x40050001` | fileoff **0x13b14** (bloque 14, +0x04) = DTCM **0x10007fe0** | parámetro pre-cargado (versión fw: MAJOR=4 MINOR=5 STEP=1) |

**Consecuencia**: K44 midió ITCM/DTCM **carga** (coincide 100% con el binario), pero el
`0x40050001` de `DTCM+0xff8` es **dato pre-cargado por fw_load, NO evidencia de
ejecución** (ya corregido en K58/K24 del árbol; aquí queda confirmado desde el binario).

### 1d. Bloque 14 completo (DTCM 0x10007fdc..0x10007ff4) — parámetros de arranque

```
0x10007fdc: 0xffffffff   <- BREADCRUMB de ejecución (el fw lo reescribe, ver §2)
0x10007fe0: 0x40050001   <- magic leído por K58 (reg DTCM_START+0xff8)
0x10007fe4: 0xffffffff
0x10007fe8: 0x40000024
0x10007fec: 0x00000000
0x10007ff0: 0x20060001
```

Bloque 13 (0x10007f98..0x10007fc0): 40 bytes a **cero** (zona de trabajo por encima del
stack: MSP=0x10007f80 crece hacia abajo, nunca la pisa).

## 2. Desensamblado del ITCM (Thumb-2, capstone)

El ITCM es un **boot stub de 476 bytes**, no el fw completo:

```
=== Tabla de vectores (ITCM 0x00..0x0f) ===
0x000: 0x10007f80   MSP inicial (= final DTCM - 0x80)
0x004: 0x00000105   Reset      -> 0x104
0x008: 0x00000145   NMI        -> 0x144 (escribe breadcrumb 3 y va a WFI)
0x00c: 0x00000159   HardFault  -> 0x158 (escribe breadcrumb 4 y va a WFI)

=== Reset handler @0x104 ===
0x104: 4809      ldr  r0, [pc,#0x24]     ; r4=0x10007fdc (literal @0x12c)
0x106: 6801      ldr  r1, [r0]           ; lee breadcrumb pre-cargado (0xffffffff)
0x108: ea4f 2101 lsl.w r1, r1, #8        ; desplaza ventana de stages
0x10c: f101 0101 add.w r1, r1, #1        ; stage 0x01 = "reset handler en marcha"
0x110: 6001      str  r1, [r0]           ; ESCRIBE breadcrumb en DTCM 0x10007fdc
0x112: 4807      ldr  r0, =0x10007f80    ; (literal @0x130)
0x114: f388 8003 msr  MSP, r0            ; re-fija stack pointer
0x118: 4806      ldr  r0, =0xdeadbeef    ; (literal @0x134)
0x11a: f388 8809 msr  PSP, r0            ; marcador PSP
0x11e: 4806      ldr  r0, =0x00001000    ; (literal @0x138)
0x120: 4906      ldr  r1, =0xe000ed08    ; (literal @0x13c) = SCB_VTOR
0x122: 6001      str  r0, [r1]           ; VTOR = 0x1000 (ITCM; lo rellena el body)
0x124: f7ff ffae bl   0x84               ; == secuencia de caches/MMIO (ver abajo)
0x128: f7ff bf72 b.w 0x10                ; salta al scatter-loader de la librería C

=== Función @0x84 (secuencia de arranque de caches) ===
0x084: b5f0      push {r4-r7, lr}
0x086: 4c1d      ldr  r4, =0x10007fdc    ; breadcrumb
0x088: 2114      movs r1, #0x14
0x08a: 6820      ldr  r0, [r4]
0x08c: eb01 2000 add.w r0, r1, r0, lsl #8
0x090: 6020      str  r0, [r4]           ; stage 0x14
0x092: 4d1b      ldr  r5, =0x1807d000    ; ** BASE MMIO (GMU_ICACHE_CONFIG, host 0x1f400) **
0x094: 2600      movs r6, #0
0x096: 606e      str  r6, [r5,#4]        ; 0x1807d004 = GMU_DCACHE_CONFIG  = 0
0x098: 602e      str  r6, [r5,#0]        ; 0x1807d000 = GMU_ICACHE_CONFIG  = 0
0x09a: 8f4f      dsb  sy
0x09c: 8f6f      isb  sy
0x0a2: 2703      movs r7, #3
0x0a4: 616f      str  r7, [r5,#0x14]     ; 0x1807d014 (host 0x1f405) = 3  (operación)
0x0a6-0x0b4: 2301/4601/4a15/3228/6810/4018/4288/d1fb
                 poll: while ((*0x1807d028 & 1) != 1);   ; ** POLL-1: host 0x1f40a bit0 **
0x0b6: 616e      str  r6, [r5,#0x14]     ; = 0 (fin de operación)
0x0b8: 8f4f      dsb
0x0bc-0x0c4: (stage 0x15 al breadcrumb)
0x0c6: 612f      str  r7, [r5,#0x10]     ; 0x1807d010 (host 0x1f404) = 3  (operación)
0x0c8-0x0d6: poll: while ((*0x1807d024 & 1) != 1);   ; ** POLL-2: host 0x1f409 bit0 **
0x0d8: 612e      str  r6, [r5,#0x10]     ; = 0
0x0da: 8f4f dsb / 8f6f isb
0x0e2-0x0e0: nop x6
0x0ee-0x0f6: stage 0x16 al breadcrumb
0x0f8: bdf0      pop {r4-r7, pc}

=== Scatter-loader (librería C ARM) @0x10 ===
0x010: f002 f800  bl   0x18               ; entra al bucle (lr=0x14)
0x014: f003 fff8  bl   0x4008             ; ** LLAMADA AL BODY (icache) tras el bucle **
0x018: a00a      adr  r0, =0x44
0x01a: e890 000c ldm  r0, {r10, r11}    ; r10=0x128+0x44=0x16c, r11=0x198+0x44=0x1dc
0x022: ea4f...   sub  r7, r10, #1
0x02e: f209 090e sub.w lr, pc, #9       ; retorno al bucle (0x29)
0x032: e8ba 0f00 ldm r10!, {r0-r3}      ; lee entradas de 4 palabras
0x036-0x042: r3 = (r3&1 ? r7-r3 : r3)|1 ; bx r3   ; llama a 0x4c (memcpy) o 0x68 (memzero)
...
=== Tras el bucle (r10==r11): 0x02a: f003 fedd  bl 0x4008  ; ** LLAMADA AL BODY (icache) **

=== Funciones auxiliares del stub ===
0x4c: memcpy (ldm/stm por 16 B)     0x68: memzero

=== Handlers de excepción (NMI/HardFault) ===
0x144: (NMI)       stage 3 -> breadcrumb; b 0x140
0x158: (HardFault) stage 4 -> breadcrumb; b 0x140
0x140: 30bf wfi / e7fd b 0x140    ; lazo de espera
```

### Tabla scatter (ITCM 0x16c..0x1dc; entradas {src_body, dst, size, func})

| src (body/icache) | dst (CM3) | size | func | efecto |
|---|---|---|---|---|
| 0x11be8 | 0x00000200 | 0x396c | 0x4c memcpy | ITCM 0x200..0x3b6c (incluye VTOR 0x1000) |
| 0x15554 | 0x00100000 | 0x1168 | 0x4c memcpy | SRAM 0x100000 (.data) |
| 0x166bc | 0x00200000 | 0x0080 | 0x4c memcpy | SRAM 0x200000 |
| 0x1673c | 0x10004000 | 0x10e0 | 0x4c memcpy | **DTCM base** (.data) |
| — | 0x00101168 | 0x19910 | 0x68 memzero | SRAM 0x101168 (.bss) |
| — | 0x00300000 | 0x24bf8 | 0x68 memzero | SRAM 0x300000 (.bss) |
| — | 0x100050e0 | 0x1840 | 0x68 memzero | DTCM 0x100050e0..0x6920 (.bss) |

**Las 5 fuentes viven al final del cuerpo del icache (0x11be8..0x1781c; el body acaba
exactamente en 0x4000+0x1381c = 0x1781c).** Sin fetch del icache NO hay datos, NO hay
.bss, NO hay main.

## 3. MMIO del arranque

**Mapeo verificado con 3 anclas**: `addr_CM3 = 0x18000000 + offset_host_bytes`, con
`offset_host_bytes = dword_xml * 4`:

| literal en el fw | dword xml | nombre (a6xx_gmu.xml) |
|---|---|---|
| 0x1807d000 | 0x1f400 | GMU_ICACHE_CONFIG |
| 0x1807e000 (x26 en body) | 0x1f800 | GMU_CM3_SYSRESET |
| 0x1807e220 (x8 en body) | 0x1f888 | GMU_ALWAYS_ON_COUNTER_L |

### 3a. Lo que toca el STUB (todas las escrituras/lecturas del arranque temprano)

| addr CM3 | addr host (byte) | reg (dword) | nombre | acceso |
|---|---|---|---|---|
| 0x1807d000 | 0x7d000 | 0x1f400 | GMU_ICACHE_CONFIG | W 0 (invalidar/desactivar) |
| 0x1807d004 | 0x7d004 | 0x1f401 | GMU_DCACHE_CONFIG | W 0 |
| 0x1807d014 | 0x7d014 | 0x1f405 | **sin nombre en rnndb** (bloque cache/bus cfg) | W 3; luego W 0 |
| 0x1807d028 | 0x7d028 | 0x1f40a | **sin nombre** | **POLL bit0 == 1** (POLL-1) |
| 0x1807d010 | 0x7d010 | 0x1f404 | **sin nombre** | W 3; luego W 0 |
| 0x1807d024 | 0x7d024 | 0x1f409 | **sin nombre** | **POLL bit0 == 1** (POLL-2) |
| 0x10007fdc | — | DTCM | breadcrumb | R/W |
| 0x10007f80 | — | — | MSP (dato, no MMIO) | — |

Los 4 registros sin nombre (0x1f404/05/09/0a) están entre GMU_DCACHE_CONFIG (0x1f401) y
GMU_SYS_BUS_CONFIG (0x1f40f): patrón "escritura 3 → poll bit0 de status → escritura 0"
= **operación de invalidación/flush de cache + status done**, con reloj del bloque
GMU-CC/cache. No hay base GX/RSCC/GPUCC en el stub.

### 3b. El BODY (icache) toca además (del barrido de literales, no exhaustivo)

| addr CM3 | reg | nombre |
|---|---|---|
| 0x1807e000 | 0x1f800 | GMU_CM3_SYSRESET (autoregres al apagar) |
| 0x1807e090 | 0x1f824 | sin nombre (debug CM3) |
| 0x1807e220 | 0x1f888 | GMU_ALWAYS_ON_COUNTER_L (su timestamp) |
| 0x1807e3b0 | 0x1f8ec | GPU_GMU_CX_GMU_RPMH_POWER_STATE |
| 0x1807e640 | 0x1f990 | GMU_GMU2HOST_INTR_SET (nos interrumpe) |
| 0x1807dc80 | 0x1f720 | sin nombre (GMU CC) |
| 0x18080000 | 0x20000 | **SMMU del GMU** (context banks, CB0 en 0x20000) |
| 0x1808b000 | 0x22c00 | GPUCC/CPR (región) |
| 0x1808c1a8 | 0x2306a | **RSCC** (base host 0x8c000) + 0x6a |
| 0x1809481e | 0x25207 | GPUCC/CPR (región GPU_CC_GX_GDSCR 0x24403…) |
| 0x180a1005 | 0x28401 | región GBIF/GX alta |

## 4. El segmento de ICACHE (BO @0x4000, 79900 B)

Es **CÓDIGO + rodata del fw real** (no datos sueltos ni ISRs pre-empaquetados):

- 0x4000: stub de 2 instrucciones (`b51f bd1f` = push/pop).
- 0x4008: destino del `bl` del scatter-loader → `__main` del fw real (llamadas a
  0x4348, 0x114d0, 0x10cac — init de la libc + main del GMU; hay rutinas de división
  64-bit, etc.).
- 0x11be8..0x1781c: **rodata/.data inicializadores** que el scatter-loader copia a
  ITCM/SRAM/DTCM y las tablas .bss que pone a cero.
- Los ISRs reales: la tabla está en ITCM 0x1000 (VTOR), **rellenada en runtime por el
  body**; la copia del scatter deja esa zona a cero (verificado: ITCM 0x1000 ← body
  0x129e8 = ceros). Hasta que el body programe los vectores, cualquier excepción temprana
  cae en la tabla de ceros.

## 5. sqe.fw en gen7: flujo del árbol

1. `adreno_load_fw` (adreno_gpu.c:605) hace `request_firmware` de `gen71100_sqe.fw`,
   `gen71100_gmu.bin` y zap. Solo se salta el GMU fw con GMU-wrapper (uke no lo es).
2. **El sqe NO interviene en el arranque del CM3.** `fw_load` solo distribuye los
   bloques del gmu.bin (ITCM/DTCM/icache/dcache/dummy); el orden interno es irrelevante
   porque es una sola pasada con `SYSRESET=1`, y `fw_start` carga el fw ANTES de soltar
   el reset (`a6xx_gmu_start` es después): **orden ITCM/DTCM correcto**.
3. El sqe se volca en un BO GEM (`a6xx_ucode_load`, a6xx_gpu.c:1047) durante
   `adreno_load_gpu` y su IOVA se escribe en `REG_A6XX_CP_SQE_INSTR_BASE` en
   `a6xx_hw_init` (a6xx_gpu.c:1436) — todo DESPUÉS de que el GMU esté vivo.
4. **BUG LATENTE en nuestro árbol (k52 y también k18)**: `a6xx_ucode_check_version`
   (a6xx_gpu.c:1006) solo conoce `a630/a650/a660_sqe.fw`; con `gen71100_sqe.fw` cae al
   `else` → "unknown GPU, add it to a6xx_ucode_check_version()!!" → `ret=false` →
   `a6xx_ucode_load` devuelve **-EPERM** → `adreno_load_gpu` aborta **antes** de
   `msm_gpu_hw_init`. Cuando ganemos el arranque del CM3, esto bloqueará el init del GPU
   (el clásico "add it to a6xx_ucode_check_version()" de upstream para chips nuevos).

## 6. VEREDICTO

### Qué necesita el CM3 en sus primeras ~100 instrucciones

1. **ITCM cargado** (stub 476 B) y **SYSRESET soltado con reloj del CM3** — K44 ya
   probó la carga (itcm0/1 = vector 100% igual al binario).
2. **DTCM con los parámetros de 0x10007fdc..0x10007ff4 intactos** (fw_load los escribe;
   el reset handler LEE 0x10007fdc y acumula ahí su breadcrumb).
3. **El bloque GMU-CC 0x7d000..0x7d02c OPERATIVO** (ICACHE/DCACHE_CONFIG + los 4 regs
   0x1f404/05/09/0a): el stub invalida caches y **hace DOS POLLS de bit0** (0x1f40a y
   0x1f409) ANTES de tocar cualquier otra cosa. Sin reloj/energía de ese bloque, el
   primer `str`/`ldr` del CM3 en la región cuelga su AHB.
4. **El fetch del icache (SMMU SID5→CB1, IOVA 0x4000)**: tras los polls, el
   scatter-loader LEE el body (memcpy/memzero desde 0x11be8..0x1781c) y hace `bl 0x4008`.
   Sin traducción viva, el CM3 muere justo después del stage 0x16.
5. Nada de IRQs/HFI/RSCC antes de `bl 0x4008`: el HFI_QTBL_ADDR/BOOT_CONFIG/CFG que
   escribe el host los consume el body, no el stub.

### Por qué se para (hipótesis ordenada)

- El freeze al soltar S3-rst0 encaja con un **AHB del GMU wedged por el primer acceso
  del CM3 a un bloque sin reloj** (los polls 0x1f409/0x1f40a): el host después lee
  (poll `FW_INIT_RESULT` / bracket K61) sobre ese mismo bus y arrastra el SoC.
- La hipótesis K24 (icache no llega a la RAM del CM3) sigue viva, pero ocurre **más
  tarde** (post-stage-0x16): el stub no toca SMMU ni DRAM hasta el scatter.
- DTCM sin cambio tras release + ITCM correcto ya descarta "no carga": falta EJECUCIÓN,
  y el binario nos da el marcador exacto para saber hasta dónde llegó.

### EXPERIMENTO (k62): leer el BREADCRUMB, no el magic

El registro a leer es **`REG_A6XX_GMU_CM3_DTCM_START + 0xff7`** (byte offset 0x3fdc →
DTCM CM3 0x10007fdc; el +0xff8 de K58 es el vecino pre-cargado).

1. Con CM3 en reset, tras `fw_load`: leer +0xff7 → debe dar **0xffffffff** (lo escrito
   por el bloque 14). Confirmado como baseline.
2. Soltar SYSRESET (S1) y dejar que se congele.
3. Recuperar el bus (camino k61: bracket/rearme) y releer +0xff7:

| valor leído | veredicto |
|---|---|
| 0xffffffff | el CM3 NO ejecutó ni una instrucción: problema de reloj/CM3 (no icache, no polls) |
| 0xffffff01 | ejecutó el reset handler y murió antes del primer MMIO (improbable) |
| 0xffff0114 | **colgado en POLL-1** (`0x1f40a` bit0): el bloque cache-ops 0x7d02c sin reloj/energía — palanca: gdscr/clk de ese dominio (k62 debe leer GPU_CC_*_GDSCR y el propio 0x1f40a desde el host) |
| 0xff011415 | colgado en POLL-2 (`0x1f409` bit0), misma palanca |
| 0x01141516 | polls OK; murió en el **fetch SMMU SID5→CB1 de 0x4000** (hipótesis K24): instrumentar CB1/GBIF, no el DTCM |
| 0x…04 en byte bajo | **HardFault** (handler @0x158 escribe stage 4): mirar CFSR/fault del CM3 |

Complementos baratos: leer 0x1f409/0x1f40a desde el host ANTES de soltar el reset
(valor de reposo; si el host los lee bien pero el CM3 se cuelga en ellos, el problema es
el dominio del AHB del CM3, no del block); y comprobar que el ALWAYS_ON_COUNTER
(0x1f888) corre (el body lo usa como timestamp).
