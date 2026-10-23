# BARRIDO W2 — RE del primer voto GX (2026-10-09)

Objetivo (oleada 2 de FASE 3): qué vota el fw al arrancar, en qué orden respecto a
HFI, qué espera del host ANTES del primer voto, y si mainline/k64 deja sin votar
algo necesario antes de S3-rst0. 100% offline, sin tocar la tablet.
Blanco: `build/pkg/uke-gpu-firmware/gen71100_gmu.bin` (80680 B, sha `435c7bac…9291bb864`).

## 0. Método y herramientas (qué se usó)

- **Contenedor**: parseo propio `python3/struct` (`{u32 addr,size,type,value}` + `16+size`).
  `arm-none-eabi-objdump` **no existe** en el sistema; el paquete `extra/arm-none-eabi-binutils`
  existe en repos pero no está instalado (sin root a mano: no se instaló).
  `llvm-objdump 23.1.1` **no abre blobs raw** (`is not an object file`) y el `objdump` del
  sistema no acepta `-m arm`. Desensamblado con **capstone 5.0.7 instalado por pip en venv
  temporal** (`~/.hermes/profiles/coder/cache/scratch/revenv`, scripts `dump.py/ldis.py/q*.py`).
- **Caveat importante**: el barrido lineal global (base 0x4000, 29641 insns) tiene **zonas de
  desync** (p. ej. `0x1ab4` no aparece como inicio aunque 18 `bl` verificados apuntan allí;
  el scan de bases MMIO daba 23 sitios contra 14 pools reales). Todo lo citado abajo se
  **re-verificó por desensamblado local anclado en boundary** (targets de `bl` / `push`) +
  greps raw de pools por `struct` (independientes de capstone). Lo no verificado se marca.
- Referencias host: `build/kernel-pokes/k52-tree/.../adreno/a6xx_gmu.c` (k52+parches uke
  K61/K64), `a6xx_hfi.h`, `registers/adreno/a6xx_gmu.xml`.

## 1. Formato del body y HFI header (verificado)

Contenedor: 11 TOC `size=0` + 4 payloads `type=0xefbeadde`. Datos:
**bloque 11** ITCM stub 476 B (fileoff `0x0c0`, CM3 `0x0`);
**bloque 12 body fileoff `0x2ac`, CM3 `0x4000` (icache BO), size `0x1381c` (79900 B)**;
bloque 13 DTCM 40 ceros (fileoff `0x13ad8`, `0x10007f98`);
bloque 14 params (fileoff `0x13b10`, `0x10007fdc`: `ffffffff/40050001/ffffffff/40000024/0/20060001`).
Conversión body: `fileoff = 0x2ac + (CM3 − 0x4000)`.
Entry del body: `0x4008` (fileoff `0x42b4`): `bl 0x4348; bl 0x4000; bl 0x114d0; bl 0x4392;
bl 0x4004; bl 0x10cac` (= init GMU, un solo llamador: el entry). `0x10cac` ← solo desde `0x4022`.

HFI header (del lado host, `a6xx_hfi.h` k52, verificado en árbol):
QTBL = `a6xx_hfi_queue_table_header` {version,size,qhdr0_offset,qhdr_size,num_queues,
active_queues} + `a6xx_hfi_queue_header` {status,iova,type,size,msg_size,dropped,
rx/tx_watermark,rx/tx_request,read/write_index}; colas 0=CMD, 1=RESP.
Msg header u32: `ID=(msg&0xff)`, `SIZE=(msg>>8)&0xff`, `SEQ=(msg>>20)&0xfff`.
IDs H2F: 0 INIT, 1 FW_VERSION, 3 BW_TABLE, 4 PERF_TABLE, 5 TEST, 7 ACD, 8 CLX_TBL,
10 START, 11 FEATURE_CTRL (DCVS=0,HWSCHED=1,…,RAIL_ON=5…), 14 CORE_FW_START, 15 TABLE,
**30 GX_BW_PERF_VOTE** {header,ack_type,freq,bw}, 33 PREPARE_SLUMBER. Respuestas F2H 126 ACK / 100 ERROR.

## 2. Entorno desensamblado por símbolo

Strings (bodyoff/CM3/fileoff): `HandleHfiCommand 0xd71b/0x1171b/0xd9c7`,
`GmuSetupIpcMem 0xd7bb/0x117bb/0xda67`, `GmuSetupIpcCore 0xd7ca/0x117ca/0xda76`,
`abortPwrCollapse 0xd991/0x11991/dc3d`, `beginHmPwrCollapse 0xd9a2/0x119a2/dc4e`,
`beginVoteGxOn 0xd9b5/0x119b5/0xdc61`, `RsccSetVoltageVoteData 0xdb74/0x11b74/de20`,
`RsccComputeAbVote 0xdb8b/0x11b8b/de37`, `RsccSendVoting 0xdb9d/0x11b9d/de37+12`,
`GmuPwrRequestPowerOn 0x11380/0x15380/0x1162c`, `GmuPwrQueryGxPowerState 0x11395/0x15395/0x11641`,
`GmuPwrGxBwVote 0x113ad/0x153ad/0x11659`, resto de handlers HFI en `0x1160b..0x15544`
(tabla de nombres de eventos contigua).

### 2a. beginVoteGxOn — función CM3 `0x10e78..0x10ec0` (fileoff `0xd124..0xd16c`)

Único pool con su nombre en `0x10ec4` (fileoff `0x11170`); único `ldr` en `0x10e86`;
**cero `bl` directos** en todo el body (solo vive como puntero `0x10e79` en la tabla de
estados de potencia @CM3 `0x15c34`, fileoff `0x11ee0`, junto a otros 6 handlers del
cluster `0x10xxx..0x11xxx` + IDs `0x10001..3/0x20011..13`). Disassembly íntegro (verificado local):

```
0x10e78: push {r4,lr} | bl 0xc180 (=lee SPTPRAC_PWR_CLK_STATUS 0x1f8ec) | cmp r0,#2
0x10e80: beq 0x10e94   (si status==2 salta el log; si no: dsb + Log(0,0x73,0x1dc,"beginVoteGxOn") vía 0x750)
0x10e94: 0x1ab4(0,3)              ; vota (dominio 0, nivel 3) — ver §2e
0x10e9c: [0x100658]←3             ; variable de estado GX en SRAM GMU
0x10ea2: r0=[0x100054a8+0x588]; si==1 → bl 0x97e0 (=toca SYSRESET 0x1f800)
0x10eb0: bl 0xfad8(0)             ; apply de potencia (llama al applier 0xee30, log 0x750)
0x10eb6: 0x1ab4(0,5)              ; vota (dominio 0, nivel 5)
0x10ebe: return 0
```

### 2b. GmuPwrGxBwVote / RequestPowerOn / QueryGxPowerState / GmuMain — SIN xref estática

`0x153ad/0x15380/0x15395/0x1532e`: **cero pools en código y cero en todo el body**
(grep raw de los 4 u32 LE: 0 hits), cero `movw`/`adr` hacia ellos. Son nombres de la tabla
de eventos sin referencia por puntero: sus appliers reales se despachan en runtime por la
tabla SRAM vía `0xee30` (ver §2d). No se les puede atribuir dirección de función con este material.

### 2c. HandleHfiCommand — función `0xa4bc..0xa948` (fileoff `0xa768..0xabf4`)

Pools del nombre en `0xa8b8` (fileoff `0xab64`); ldrs en `0xa520/0xa53a/0xa560/0xa84e`.
Recibe (ptr_msg,…) con `r7=ptr, r4=[ptr]=header`. Tras guards de tamaño (`r7∈{0,0x7a,0x1f4}`→return):
- `r0=uxtb(r4)` (msg id): `0x1e/0x80/0x83/0x87/0x8c/0x96/0x97/0x99→0xa93e`;
  `0x9a→0xa6f4`; ids `<0x15` por `tbb` en `0xa5aa`; resto → default (`0xaf00(msg,0x6f)` = ACK).
- `0xa93e` (msg 30 y familia): `bl 0xb780` = **HfiUseBottomHalf** (loguea su nombre en `0xb7e2`):
  segundo dispatch por id (`ldrb [msg]`): `0x1e(30)→0xb80e: 0xba44(sp,msg,5)+0xee30(5,val)`;
  `0x0a(10,START)→0xb876→rama 0x2f: 0xba44(sp,msg,0x2f)+0xee30(0x2f,…)`; `0x0d→0xb8ba:
  bl 0xb938(msg,1)` = **HfiWriteMsgPool** ✓ (su nombre, pool `0xbae8`, ldrs `0xba60/0xba8c`);
  `0x0e(14,CORE_FW_START)→0xba44(...,0x30)+0xee30(0x30,…)`; `0x21(33)→tipo 7`;
  `0x80/86/81/84/8c/96→tipos 9/0x36/0xa/0xb/0xc`; default→`0xcf90`.
- `0xba44` = parser por mensaje (16 llamadores: todos los brazos + `0xcfb2/0xcfcc/0xd072/0xd0a2/0xd0de`);
  `0xee30(tipo,valor)` = applier central (50 llamadores en cluster potencia + `0x4d28/0x4d32/…`;
  si `tipo<0x4d` despacha por tabla vía `blx [0x1017bc+idx*8]` — **tabla en SRAM, contenido
  runtime: el applier concreto del voto GX (idx 5) no es atribuible en estático**).
- `0xaf00(msg,status)` / `0xaf38(msg,…)` = enviadores de ACK (31/50 llamadores resp.;
  construyen el ACK en pila y llaman a `0xb320`=escritura a cola); `0xaf80(id,linea,nombre)` =
  HfiCommandRecord (50 llamadores); `0x1f74` = log/assert universal (183 llamadores);
  `0x750` = Log de eventos `(0,0x73,…)` (68 llamadores).

### 2d. Rscc — ComputeAbVote `0xfd10`, SendVoting `0xfd68`, SetVoltageVoteData `0x100c0`

- `RsccComputeAbVote` (`0xfd10..0xfd5a`, push..pop verificado): `ubfx` bits[27:14] de dos
  entradas de tabla + `muls` — cálculo puro, sin MMIO.
- `RsccSendVoting?` (`0xfd68..0x10084`, `push.w..pop.w`): pools del nombre en `0x10094`
  (ldrs `0xfdb0/0xfe42`); llama a `RsccSetVoltageVoteData` (`0xfef4/0xff0c`) y a `0x1a54/0x364`;
  único llamador: `0xfa6c` (verificado).
- `RsccSetVoltageVoteData?` (`0x100c0..`, sin prólogo — leaf con dispatch en `r0∈{2,1,3,5}`,
  default = log nombre + tail `b.w 0x750`): pool en `0x10124` (ldr `0x100d8`); llamadores
  verificados `0xfef4/0xff0c` (dentro de SendVoting), `0x1025e`, `0x11490`.

### 2e. El votante leaf `0x1ab4` y el query `0xc180`

- `0x1ab4` **no es inicio de función** (decode local anclado):
  `adds r3,#0x88; mov r1,r2; adds r0,#0x28; bl 0x1eb4; cbnz…` — entrada alternativa leaf con
  (dominio,nivel). 18 llamadores verificados (capstone resuelve `bl #0x1ab4` en todos;
  comprobación manual del encoding en `0x10e98/0x10eba/0x10014`): todo el cluster de
  potencia `0x10d34..0x11148` con `(0,3)/(0,5)` (+ `(2,…)` en `0x10014/0x10076`).
  `0x1eb4` (push verificado): `r3*=0x4b00; …; r5=[r0]&r1; return (r5==r2)?0:…` — matcher previo al voto.
- `0xc180..0xc18e` (verificado): lee `0x1807e340` = **0x1f8d0 SPTPRAC_PWR_CLK_STATUS**
  (A7XX, según xml) + CmdRecord; llamadores `0xe17e/0x10e7a/0x110e4/0x1112c`.
- `0x97e0..0x9806`: toca `0x1f800` SYSRESET (llamadores `0x10eac/0x11140/0x11246/0x11578`).
- `0xfad8..0xfd06`: potencia grande (llama a `0xee30`, `0x750`, `0xc940/0xc52c…`).

### 2f. Primer voto RSCC localizado: EnableIsense `0x8e80..0x8f26` (fileoff `0x912c..0x9172`)

Loguea su nombre en `0x8ef0` (pool `0x11b05`). Guarda `[estado+0x10]==1` ([struct `0x11a0cc`]);
chequeo de chip `[0x10004104]` contra `0x7020000/0x7020100/0x7050000/0x7050001`;
**`RSCC 0x2306a (0x1808c1a8) ← 2`** en `0x8f0e` + **polls a GPUCC `0x22c00`**
(`[+0x104]` bit15, `[+0x11c]` bit31, `0x8f12..0x8f20`); `ISENSE_CTRL 0x1f95d ← 1`;
marca `[estado+0x10]←1`. Llamadores verificados: `0xcb06` (cluster RSCC), `0xe326/0xe8c2`
(task potencia). Gemela de apagado `0x6960..0x6986` (RSCC←0, ISENSE←0, + escrituras a
`0x4409907c`): llamadores `0xcae2/0xcb54/0xe250/0xe4e4/0xe9c8`.

### 2g. GmuSetupIpcCore `0xa2cc` / IpcMem `0xa378` — runtime, NO boot temprano

- `IpcCore` (`0xa2cc..0xa364`, verificado): trabaja sobre struct SRAM `0x3240b8` (`+0xb34`),
  lee `0x1f971` (`0xa2be`), reporta por `0x1f74` y responde `0xaf80(1,0x354/0x35b/0x362)`.
  Único llamador: `0x6f5c`, dentro del dispatch de eventos **`0x6e64` = EcpHandleNewEvent**
  (loguea ese nombre en `0x6ee0`; dispatch por id de evento con `tbb` para `0x31..0x3a`;
  único llamador verificado: `0x885a`, el loop de drenaje de eventos `0x8846..0x8878`).
- `IpcMem` (`0xa378..0xa408`, verificado): mismo struct (`+0xb34/+0xe0`), responde
  `0xaf80(1,0x343)/(2,0x33a)`. Único llamador: `0x720c`, dentro de `0x7134` ← `0x6f4c`
  = **brazo `0x2f` del dispatch 0x6e64**. Y el evento interno `0x2f` lo genera el brazo
  HFI-START (msg 10, §2c). Cadena: **START → 0xee30(0x2f) → evento 0x2f → IpcMem/Core**.
  El body **no referencia `0x1f985 QTBL_ADDR` por literal absoluto en ningún sitio**
  (grep raw del u32 LE en `0x4000..0x11be8`: 0 hits): la IOVA llega al fw por el struct
  SRAM, vía no totalmente trazada (hueco §4).

## 3. Secuencia reconstruida

### 3a. Boot temprano (función en `0x124c8`, breadcrumbs en DTCM `0x10007fdc`, fileoff base `0x2ac`)

| stage | callee (CM3/fileoff) | efecto verificado |
|---|---|---|
| 5 | `0x134f8` (`0x137a4`) | **lee GENERAL_8 `0x1f9cd`** (`0x134fa/0x13510`) |
| 6 | `0x1446c` (`0x14718`) | **copia `[0x1f9d0]` → DTCM `0x10004000`** |
| — | `0x1e938`, `0x121a8` | (fallo → aborto a tail) |
| 7 | `0x136c8` (`0x13974`) | toca ICACHE_CONFIG `0x1f400` |
| 8 | `0x13548` (`0x137f4`) | toca CM3_CFG `0x1f82d` |
| 0xe | `0x11fa4` (`0x12250`) | toca ICACHE_CONFIG |
| 9 | `0x13e90` (`0x1413c`) | lee HFI_CTRL_STATUS `0x1f980` + GENERAL_0 `0x1f9c5` + timestamp `0x1f889` |
| 0xa | `0x14af0` (`0x14d9c`) | solo SRAM/DTCM |
| 0xb | **`0x12460`** (`0x1270c`, el writer) | reintenta `0x121a8/0x136c8/0x1dfa8`/`0x14520`/**`0x1cc5c/0x12ee8**/`0x144d4`; primer error → §3b |
| 0xc | `0x11f14` + `0x12928` (`0x12bd4`) | `0x12928` **rellama `0x14520` (chip-check)** |
| 0x10 | `0x15c54/0x11cc4/0x14864` | setup final |
| 0x11 (tail) | — | `ICIALLU` (`0xe000ed04`) + return |

`0x144d4` (`0x14780`, dentro del writer): escribe `0x1807e000+0x58/0x5c ← 0x927c00/0x1b77400`
(regs `0x1f816/0x1f817`, sin nombre en xml), `[+0x44]←0`, `[+0x4c]←3` (`0x1f811/0x1f813`,
sin nombre) + `bl 0x1e16c(0x1e)`. `0x14500`: `[0x1f812]←1`; `0x14510`: `[0x1f813]&=~2`.
**Ningún stage escribe votos RSCC/GX.**

### 3b. Protocolo FW_INIT_RESULT (`0x1f81c` = `0x1807e070`, verificado por 3 sitios, sin literal absoluto — grep raw negativo)

- **Error**: `0x124b6` (fileoff `0x12762`): `FW_INIT_RESULT = 0x101` determinista
  (`[sp]=0 → byte=1 → |0x100`). Llamador: writer `0x12460` ← stage 0xb ← `0x12586`.
- **Progreso** (bits[11:9] vía helper `0x1445c`, fileoff `0x14708`:
  `ldr r1,[base+#0x70]; bfi r1,r0,#9,#3; str`): `0x200` (`0x1365c`, tras ack INTR `0x1f99e→0x1f99d`),
  `0x400` (`0x11c42`), `0x600` (`0x12632`), `0x800` (`0x1263e`) — 4 llamadores verificados.
- **Éxito = `0x100`**: `0xadc0` (`0xadee/0xae12`, fileoff `0xb09a/0xb0be`): `r6=0x100;
  str r6,[0x1807e000+#0x70]`. **Solo en path ACK-HFI**: `0xaf00/0xaf38` (status==0 y flag
  `[struct 0x102610+#0xf]≠0`; con `[+0xc]==1`). Llamadores de `0xadc0`: solo `0xaf2c/0xaf5e`
  (verificados). Llamadores de `0xaf00`: 31, todos en región HFI/eventos (`<0xb000`,
  p. ej. `0x6f80/0x6f94/0xa4fa/0xa608…`); **ningún llamador en el boot temprano**.
  La puerta `[+0xf]` la **limpia** la función `0x10ab4` del cluster de potencia
  (`[0x102610]←0; [+0xf]←0`, verificado); su setter (=1) no localizado — candidatos en el
  motor HFI (`0xb1b8/0xb2f6/0xb5f8/0xb6a2/0xb700/0xb8fa/0x142e2`, los otros 7 usuarios del
  struct). **Hueco abierto**: cómo el vendor supera su poll pre-HFI con un `0x100` que solo
  nace de ACKs (ver §4).

### 3c. Qué espera el host ANTES del primer voto (ordenado por momento de uso fw)

Pre-reset (lo consume el boot): ITCM/DTCM/icache cargados; `FW_INIT_RESULT=0`;
`BOOT_CONFIG=2`; `QTBL_ADDR/INFO`; `FENCE_RANGE_0=0x80c808a0`; `CM3_CFG=0x4052`;
`GENERAL_10=chipid` (**validado**: `0x14520` exige `((x>>16)&0xfff)∈{0x701,2,3,5,6,9,a,b,f}`,
ret≠0 → `FW_INIT_RESULT=0x101` + aborto; corre en el writer y en stage 0xc);
`GENERAL_8` (leído st5), `GENERAL_9` (leído `0x13822/0x139ca`, propósito no decodificado),
`0x1f9d0` (copiado a DTCM st6); `TCM_RET_CNTL=1`; `FAL_INTF 0x1f8f0/f1=1`;
`ICACHE/DCACHE/SYS_BUS=1`; GDSC CX/GX + relojes GMU/GPUCC + RSCC despierto + SMMU
(SID5→CB1 para el fetch `0x4000`, y mapeo QTBL/SFR). Post-reset, pre-voto:
HFI START + tablas (PERF/BW/…) → evento `0x2f` → IPC → PwrTask/tabla de estados →
**primer voto RSCC** (`EnableIsense`: `0x2306a←2`, con **poll a GPUCC** — exige GPUCC
vivo) y **primer voto GX** (`beginVoteGxOn`: `(0,3)` + `[0x100658]←3` + `(0,5)`).

## 4. Veredicto

1. **El freeze S3-rst0 es anterior a cualquier voto**: el fw no emite ningún voto antes de
   estar vivo y recibir HFI (el boot solo lee/valida; el primer `0x2306a←2` y el primer
   `(0,3)/(0,5)` son post-START vía PwrTask). P1/P2/K63 ya sitúan la muerte en polls
   cache-ops o fetch SMMU del stub. **El host no "deja sin votar" nada pre-reset que el fw
   necesite para votar**: la pregunta (4) se responde por la negativa en su formulación
   estricta — lo que falta es entorno físico + valores programados, no votos.
2. **Pero en cuanto el CM3 viva, el k64 lo estrella contra la validación de chip**:
   `uke_k64_vendor_config` (`a6xx_gmu.c:867-872`) escribe `0x1f9cd/0x1f9cf/0x1f9d0 ← 0xf`.
   El fw valida `0x1f9cf` en `0x14520` (familia `0x70x`) → con `0xf` devuelve 3 →
   `FW_INIT_RESULT=0x101` → el poll vendor (`&0x1ff==0x100`) **falla limpio** (no freeze).
   Acción: programar `GENERAL_10` con el chipid real en formato fw (no `0xf`).
3. **K64 pisotea `GENERAL_8`**: mainline programa `GENERAL_8=log.iova|size` (`a6xx_gmu.c:1991`)
   y K64 lo sobrescribe con `0xf` (línea 869); el fw lo lee en stage 5 (`0x134f8`).
   Acción: componer `(log&~0xfff)|size` o reordenar K64 antes del log (el patrón vendor es
   `(ptr&~0xfff)|0xf`, no `0xf` pelado).
4. **El criterio de éxito mainline es imposible con este fw**: k52 hace poll
   `FW_INIT_RESULT==0xbabeface` (mask `0xffffffff`); ningún path del fw escribe ese valor
   (éxito `0x100`, error `0x101`, progreso `0x200/0x400/0x600/0x800`). Acción: poll vendor
   `(val&0x1ff)==0x100`.
5. **GPUCC debe estar vivo antes del primer voto**: `EnableIsense` hace poll bloqueante a
   `0x22c00+0x104/0x11c`; sin GX/GPUCC el fw se cuelga AHÍ (post-boot, distinto de S3-rst0).
6. Huecos (no bloquean el veredicto): (i) lectura fw de `QTBL_ADDR` sin literal — vía struct
   `0x3240b8` sin trazar del todo; (ii) setter de `[0x102610+#0xc]` y cómo el vendor ve `0x100`
   antes de su `hfi_start` (posible llamador oculto en zona de desync, o el poll vendor cubre
   más de lo documentado en KGSL-RE §5); (iii) appliers concretos de `GmuPwrGxBwVote` y
   familia (tabla SRAM runtime vía `0xee30`, idx 5 para msg 30); (iv) `GENERAL_9` y regs sin
   nombre (`0x1f971/73/77/942/43/951/965/66/980-84/997-9e/9c5/9f1/710-29/824-29/811-17`):
   el fw los toca y el xml mainline no los nombra.
