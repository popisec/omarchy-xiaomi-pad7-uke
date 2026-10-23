# PLAN — RE completo del vendor (`msm_drm.ko`) + integración de REA

> 12-oct-2026. Objetivo: **extraer TODO el conocimiento del panel que tiene el driver vendor**, porque
> el techo del port está en lo que mainline no hace, no en lo que el panel driver no sabe.

---

## 0. Estado del entorno (verificado hoy)

| Recurso | Estado |
|---|---|
| **Ghidra 12.1.4_PUBLIC** | ✅ **ya instalado** en `~/tools/ghidra_12.1.4_PUBLIC` (no estaba en PATH — por eso los agentes previos no lo usaron) |
| `analyzeHeadless` | ✅ probado: importa `msm_drm.ko` sin error (`-processor AARCH64:LE:64:v8A`) |
| Java | ✅ **27** en `/usr/lib/jvm/java-27-openjdk` (Ghidra 12 lo pide ≥21) |
| node / npm / bun | ✅ v26.10 / 12.2 / 1.4.2 → requisito de REA cubierto |
| `llvm-objdump` | ✅ (receta actual de los agentes) |
| **REA** (`npx rea-agents`) | ❌ **pendiente de instalar** |

**Binario objetivo**: `~/proyectos/ubuntu-uke/stock/modules/msm_drm.ko`
ELF aarch64 relocatable, **no stripped**, 6,1 MB, **1629 funciones** (587 `sde`, 423 `dsi`, 226 `mi`, 137 `msm`).

---

## 1. Lo que YA está extraído (no repetir)

`build/gates/revision/SECUENCIA-ENCENDIDO-ANDROID-O82-20261012.md`:
- Secuencia de `dsi_display_prepare` (15 pasos) y `dsi_panel_pre_prepare`
- Los **108 comandos DCS** byte a byte (blob 998 B) — **idénticos** a `o82_prepare` de mainline
- Off-sequence, broadcast dual-DSI, ESD
- Las **5 diferencias** que quedan frente a mainline

**Informes de la tanda de RE con `llvm-objdump` (12-oct, ya entregados):**

| Informe | Hallazgo principal |
|---|---|
| PHY (`dsi_phy_hw_v5_0`, PLL 4nm) | Escribe **21 registros** en enable; mainline no tiene **driver de PLL 4nm** (solo 7nm) ⇒ **sin bitclk posible**. Lane map del DT (`0xAA/0xAA`) vs fijos de mainline (`0x21/0x84`) |
| Host DSI | Orden real: `sw_reset(PHY) → phy_enable(LP11) → host_init → panel_pre_prepare → LINK_CLK → **CTRL_ENABLE** → soft_reset → panel_prepare → (enable) 108 DCS`. **`CTRL_ENABLE` va DESPUÉS de rails+reset**, mainline lo pone antes. Pulso de reset **1 µs vs 20 ms** |
| SDE/MDP | **`sde_kms_cont_splash_config` hace CERO escrituras a registros** — solo estado DRM en RAM. **El vendor NUNCA resetea el display** (`reset_control_*` no aparece en el `.ko`). **Problema: si hay splash activo (`kms+0x9b8`), salta `sde_vbif_init_memtypes` y `set_qos_remap`**; mainline los programa **incondicionalmente** ⇒ **reescribe AMEMTYPE en caliente sobre el pipeline vivo del ABL** |

---

## 2. Lo que falta extraer (el "TODO")

| # | Área | Por qué importa |
|---|---|---|
| R1 | **Tablas de datos del catálogo** (dsi_phy_timing, dphy_lb/hb PLL, lane maps, memtypes, QoS) volcadas a formato C | mainline no puede GENERAR estos valores; hay que portarlos |
| R2 | **Los ~100 writes fijos de `dsi_pll_4nm_configure`** (`pll+0x08..0x25C`) | sin esto no hay reloj; mainline no tiene equivalente |
| R3 | **`dsi_ctrl_get_host_cfg_for_mode`**: cómo el DT se traduce a los structs de host/timing | el mapeo DT→registro es el puente exacto |
| R4 | **`dsi_display_calc_mode_setting` / OPP byte-clock / DSC** | 3200×2136 DSC a 1,19 GHz: validar que mainline calcula lo mismo |
| R5 | **`sde_vbif_init_memtypes` completa** + condición de skip con splash | **el candidato nº1 a la muerte de L26** |
| R6 | **Los DCS del panel**: dónde están en el binario y su estructura (ya byte a byte, falta el código que los envía y sus timings de cola) | secuencia LP vs HS |
| R7 | **ESD/`:c` panel event** y `nt36532_touch.ko` (el táctil, también vendor) | el táctil tampoco funciona |
| R8 | **Nombres de los registros sin xml** (`+0x310/+0x330/+0x2C8` en host; PHY `+0x014/+0x0A0/+0x0F4…`) | mainline no los nombra; hay que saber qué son |

---

## 3. Fases

### F0 — Instalar REA y conectarlo al agente  ⏱ ~20 min
```bash
npx rea-agents setup          # elige opencode, revisa y aprueba
```
- Registra el servidor MCP de REA y las instrucciones de flujo.
- Configura el proveedor nativo apuntando a **el Ghidra que ya está** (`~/tools/ghidra_12.1.4_PUBLIC`).
- **Verificación**: arrancar el MCP y comprobar que lista el catálogo de herramientas.
- Si REA no acepta el Ghidra local como proveedor, se cae a **Ghidra headless directo** (F1), que ya está probado.

### F1 — Proyecto Ghidra permanente del `.ko`  ⏱ ~30-60 min
```bash
export JAVA_HOME=/usr/lib/jvm/java-27-openjdk
~/tools/ghidra_12.1.4_PUBLIC/support/analyzeHeadless \
  ~/ghidra-projects uke-msm_drm \
  -import ~/proyectos/ubuntu-uke/stock/modules/msm_drm.ko \
  -processor AARCH64:LE:64:v8A \
  -postScript DecompileAll.java
```
- **Decompilar TODO a C** (no solo desensamblado): los 3 agentes anteriorestiraron solo desensamblado; el pseudocódigo de Ghidra resuelve los valores dinámicos y la lógica de forma mucho más fiable.
- Con `-postScript` exportar el decompilado a fichero por función.

### F2 — Extraer las 8 áreas (R1–R8)  ⏱ paralelo
Un subagente por área, todos con el proyecto Ghidra ya decompilado. Salida: una tabla C por área.

### F3 — Gap-list ejecutable: vendor → mainline  ⏱
Un único documento: **cada registro que Android escribe y mainline no**, con el fichero y línea donde
mainline debería escribirlo. De ahí sale el parche.

### F4 — Parche de mainline, por capas, un flash por capa
Orden sugerido (de menor a mayor riesgo):
1. **PLL 4nm driver** (R2) — sin reloj no hay nada; el más grande pero el más necesario
2. **Lane map + PHY `+0x014` + `+0x0A0`/strength del DT** (R1) — valores, no orden
3. **`prepare_prev_first=false`** (revertir la inversión estructural) — una línea
4. **Skip de VBIF cuando hay splash** (R5) — imitar al vendor: no reescribir AMEMTYPE en caliente
5. **Orden `CTRL_ENABLE` después de rails+reset** + **pulso de reset 1 µs** (host RE)

Cada capa = 1 build + 1 flash, con criterios pre-registrados.

---

## 4. Reglas

- **Un cambio por capa**, sha pre-registrado, `set_active a` siempre.
- **Nada de flashes hasta que F3 esté cerrado**: el gap-list es lo que evita otro ciclo no atribuible.
- **Midiendo**: el ACM es *lossy* (ya dio un falso negativo). Toda afirmación del panel va por `dmesg`/SSH con `dmesg -n 7`, nunca solo por consola.
- `slot-retry-count:a` va en 6-7 ⚠️ y la batería en ~3570 mV (gate 3700). **Conectar cargador antes de F4.**

---

## 5. Criterio de éxito

Un único documento que responda: **"para cada registro que el vendor escribe en el encendido del panel,
¿qué hace mainline?"** — y de él sale el parche que hace que `o82_prepare` corra sin cuelgar.

## 6. Estado

**Pendiente de ejecutar.** La tablet queda en L25 (vivo, SSH, FD735, panel probean x5, `prepare` sin correr).
No se ha tocado nada del kernel ni flashado nada en este plan.