# F3 — GAP-LIST EJECUTABLE: vendor → mainline

> 12-oct-2026. Cada fila responde: **"¿qué hace el vendor que mainline no hace, y dónde?"**
> Es la salida de F2 (RE con Ghidra de 3327 funciones de `msm_drm.ko`) y el insumo directo de F4.
> Fuente: `build/vendor-re/decomp/*.c` (Ghidra 12.1.4) + `build/vendor-re/vendor-o82-dsi4nm.h`.

---

## 0. Hallazgos que corrigen lo que se creía

| Se creía | Realidad (medida) |
|---|---|
| El mapa de registros PLL 4nm es distinto del 7nm | **Es el MISMO mapa.** mainline tiene el driver; lo que no tiene es el segundo banco, las tablas de divisores y el bloque de reset |
| Mainline necesita un driver de PLL 4nm completo desde cero | **No**: reutiliza `dsi_pll_7nm.c`; faltan ~3 piezas concretas |
| `0x170/0x174` los escribe el vendor siempre | **Solo en la variante v1**, y uke probablemente usa v0 (predicción por revisión MDP `0x800x`) |
| El skip de VBIF tiene una condición | **Dos**: `kms+0x9b8 != 0` (splash) **O** `catalog+0x4ac8 != 0` (trusted-VM) |

---

## 1. GAP-LIST — ordenado por relación valor/riesgo

### 🔴 G1 — No reprogramar VBIF en caliente (candidato nº1 a la muerte de L26)
**Vendor** (`sde_kms_handle_power_event.c:126-151`, evento 8):
```c
if (kms->splash_alive != 0 || catalog->trusted_vm != 0)
        return;                       // salta memtypes Y qos_remap
sde_vbif_init_memtypes(kms);          // AMEMTYPE 0x160/0x164, +0x170/0x174 en v1
sde_vbif_set_qos_remap(kms);          // 0x550/0x590
```
**Mainline**: `dpu_kms.c:1280` (hw_init) y `dpu_kms.c:1466` (`dpu_runtime_resume`) lo llaman
**incondicionalmente**, sin concepto de splash.
**Por qué mata**: AMEMTYPE fija la cacheabilidad por xin; `ASHARED/AINNERSHARED` fijan
shareability/AxDOMAIN. Reescribirlos con el pipe del ABL escaneando cambia los atributos de
transacciones **en vuelo** → aliasing de caché + cambio de dominio de snoop → el fetch del VBIF aborta
o cuelga el bus. QoS-remap solo reordena arbitraje y OT-limits acota outstanding: molestos, no letales.
**Cambio**: una condición en `dpu_runtime_resume` (y valorar una sola vez en probe).
**Riesgo**: bajo. **Valor**: alto.

### 🟠 G2 — Tablas de divisores de la PLL 4nm
**Vendor**: `pll_4nm_dphy_lb/hb`, 19 filas de 24 B. Ya volcadas a C en `vendor-o82-dsi4nm.h`.
**Mainline**: el framework clk usa OUTDIV de potencias de 2 + BITDIV *one-based* en `CLK_CFG0`.
El vendor escribe el divisor **directo** (panel: `1` para ÷1; one-based daría ÷2). **Confirmar antes
de programar divisores**, o el byteclk sale mal.
**Fila del panel**: bitclk 1.190.269.040 → byteclk 148.783.630 → `dphy_lb[18] = {600M, 1500M, 1, 1}`
→ OUTDIV 0, `CLK_CFG0[3:0] = 1`.
**Riesgo**: medio (afecta al reloj). **Valor**: sin esto no hay bitclk.

### 🟠 G3 — Bloque de reset de la PLL (~120 escrituras fijas)
**Vendor** `dsi_pll_4nm_configure`, rama init: lo hace **siempre**. Volcado a C en el header.
**Mainline**: no lo hace. La mayoría son defaults ya coincidentes ⇒ riesgo bajo, pero es escritura real.
**Riesgo**: bajo. **Valor**: medio.

### 🟡 G4 — Lane map del DT
**Vendor**: `LANE_CFG0/1 (0x34/0x38)` desde `qcom,platform-lane-config` → **`0xAA/0xAA`**.
**Mainline**: **hardcodea `0x21/0x84`**. Con 4 lanes y este map, mainline programa un LaneCFG equivocado.
**Cambio**: leer el lane-config del DT.
**Riesgo**: bajo. **Valor**: alto (puede ser por sí solo un no-arranque del link).

### 🟡 G5 — `LANE_CTRL0` (PHY+0xA0)
**Vendor**: `(clk_strength & 0xF) | 0x10` → `0x15`. **Mainline**: fija `0x1F`.
**Riesgo**: bajo. **Valor**: medio.

### 🟡 G6 — Timings de la PHY: 14 bytes del DT
**Vendor**: los **toma del DT** (`qcom,dsi-phy-timings` del panel) → `{00,27,0a,0a,1b,19,0a,0b,0a,02,04,00,20,0f}`.
**Mainline**: los **calcula** (`msm_dsi_dphy_timing_calc_v4`). Volcados en el header.
**Acción**: calcular con mainline y **comparar** con estos 14; si difieren, la diferencia explica el link.
**Riesgo**: cero (solo comparar). **Valor**: diagnóstico alto.

### 🟡 G7 — `CMODE_1` (PLL+0x250) con SSC
**Vendor**: `0x00` porque el DT activa SSC (`qcom,dsi-pll-ssc-en`). **Mainline**: `0x10` en DPHY.
Mainline tiene el código SSC pero **apagado fijo**; falta cablearlo a la property del DT
(defaults vendor: freq 31500 ppm, offset 4800, adjper 2).

### 🟢 G8 — Orden de `CTRL_ENABLE` y duración del reset del host
**Vendor**: `sw_reset(PHY) → phy_enable(LP11) → host_init → panel_pre_prepare → LINK_CLK →
CTRL_ENABLE → soft_reset → panel_prepare → 108 DCS`. El pulso de `RESET` es de **1 µs**.
**Mainline**: `CTRL_ENABLE` va **antes** de rails/reset y el pulso es de **20 ms** (×20.000).
**Riesgo**: medio (toca el orden). **Valor**: medio-alto.

### 🟢 G9 — Leer más del DT en el host DSI
**Vendor** lee del DT: `bpp`, porches/pulsos/skew, `traffic-mode`, `virtual-channel-id`,
`t-clk-pre/post`, `lane-*-state`, power-modes, `wr-mem-*`, `te-*`, dfps/qsync.
**Mainline** deriva **todo** del `drm_mode`. El mapa prop→registro completo está en el informe R3.
**Riesgo**: medio. **Valor**: alto a medio plazo (el host programa "valores inventados").

### 🟢 G10 — Segundo banco de la PLL (dyn-refresh)
**Vendor** escribe ~25 valores en `pll[3]` (región 0xAE94200, 0xA0 B). 10 son fijos portables;
5 leen registros vivos del ABL (`PLL+0x154`, `PLL+0x240`, `PHY+0x10`, `PHY+0x14`) ⇒ **shadow del bootloader**.
**Mainline**: ni el DT ni el driver conocen esa región.
**Nota**: afecta solo al banco dyn-refresh, no al path principal del reloj.

---

## 2. Lo que YA coincide (no tocar)

| Punto | Estado |
|---|---|
| `CLK_CTRL = 0x23F` en init | idéntico |
| VREG_CTRL_0/1 (`0x20`/`0x110`) = `0x44`/`0x19` | idéntico (V5_2 DPHY) |
| RESCODE_TOP/BOT (`0xF4`/`0xF8`) = `0x3C`/`0x38` | idéntico (<1.5 GHz) |
| HSTX_STR `0x88`, LPTX_STR `0x55` | idéntico |
| `CTRL_2 (0x2C) = 0x40` | idéntico |
| `TX_DCTRL` por lane `{40,40,40,46,41}` | idéntico |
| HS continuo: el vendor **no** lo fuerza (camino muerto, `cphy-mode=0`) | coherente con K48-A de mainline |
| `dec`/`frac` de la PLL | mainline los calcula igual |
| La mayoría de los fijos de la PLL (`0xBC`, `0x158`, `0x194`, `0x44`, `0x68`…) | idénticos |

---

## 3. Orden de ataque recomendado (F4)

| # | Gap | Tipo | Ciclos | Por qué en este orden |
|---|---|---|---|---|
| 1 | **G1** (skip VBIF) | software | 1 | Es el candidato nº1 a la muerte de 4,03 s **y** el más barato: una condición |
| 2 | **G6** (comparar timings PHY) | cero riesgo | 0 | Diagnóstico puro: si difieren, el link nunca entitlementará |
| 3 | **G4+G5** (lane map + strength) | valores | 1 | 4+5 | Valores del DT que mainline ignora |
| 4 | **G8** (orden + pulso reset) | orden | 1 | Toca la secuencia; necesita los anteriores verdes |
| 5 | **G2+G3+G7** (PLL completa) | reloj | 2-3 | Lo más grande, pero solo si 1-4 no bastan |
| 6 | **G9** (DT completo en host)  | 2 | Trabajo ordinario, para el modo final |

**Reglas**: un gap por flash · sha pre-registrado · `set_active a` siempre · medir por `dmesg`/SSH
con `dmesg -n 7` (**nunca solo por ACM: es *lossy* y ya dio un falso negativo**) · cargador conectado
(batería 3570 mV, gate 3700) y `slot-retry-count:a` con holgura.

---

## 4. Lo que NO se pudo determinar (y cómo cerrarlo)

| Hueco | Cómo cerrarlo |
|---|---|
| Variante VBIF v0/v1 en uke | 1 lectura de `VBIF+0x170` tras boot vendor: si está a 0 → v0 |
| Nombre del banco `[3]` de la PLL | El DT lo llama `dyn_refresh_base` por ajuste de tamaño (0xA0); no confirmado por símbolo |
| Bytes SSC del panel | El DT del PHY no trae `ssc_freq/ppm` ⇒ defaults del driver; falta la fórmula cerrada |
| Plumbing del struct intermedio del PHY enable | Fuentes identificadas (DT panel + DT phy) y mapa registro↔byte entregados |

---

## 5. Ficheros

| Qué | Dónde |
|---|---|
| Tablas y valores en C compilable | `build/vendor-re/vendor-o82-dsi4nm.h` |
| C decompilado (3327 funciones, 19 MB, git-ignored) | `build/vendor-re/decomp/` |
| Script de exportación (reproducible) | `build/tools/ghidra/ExportAllDecompiled.java` |
| Proyecto Ghidra | `~/ghidra-projects/uke-msm_drm` |
| Secuencia de encendido del panel | `build/gates/revision/SECUENCIA-ENCENDIDO-ANDROID-O82-20261012.md` |
| Plan de RE | `docs/historia/revision/PLAN-RE-VENDOR-20261012.md` |