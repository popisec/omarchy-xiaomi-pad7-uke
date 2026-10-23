# G4 — Lane map: lo que se sabe, lo que no, y el experimento

## 1. El síntoma que G4 explicaría (medido, L40+s283)

```
prepare → reset COMPLETO → DCS preparado → cmd#0 encolado
    → dsi_err_worker status=4   (DSI_ERR_STATE_FIFO)
    → dsi_err_worker status=5   (DSI_ERR_STATE_FIFO | DSI_ERR_STATE_TIMEOUT)
    → nada. 7 vueltas idénticas. El log se corta.
```

El comando entra en el FIFO del host y **no sale del host**. Eso es exactamente lo que
pasa si el panel **no está escuchando**: un lane map equivocado asigna las lanes físicas
a las lógicas equivocadas y nadie decodifica.

## 2. La fórmula del vendor (`dsi_phy_hw_v4_0_enable.c:98-101`)

```c
writel_relaxed((byte *)(param_2 + 0x12c) | (byte *)(param_2 + 0x12d) << 4,
               *param_1 + 0x34);                      /* LANE_CFG0 */
writel_relaxed((byte *)(param_2 + 0x12e) | (byte *)(param_2 + 0x12f) << 4,
               *param_1 + 0x38);                      /* LANE_CFG1 */
```

Mainline, en cambio, tiene **valores inventados con su propio TODO**:
`dsi_phy_7nm.c:1107-1109` — `writel(0x21, LANE_CFG0); writel(0x84, LANE_CFG1);`

## 3. Cómo el vendor llena el struct (`dsi_phy_parse_dt_per_lane_cfgs`)

```c
num_lanes = *(u32 *)(struct + 0x44);
if (prop_byte_len == num_lanes * 5) {          /* 20 == 4*5 -> PASA */
        dest = struct + 3; i = 0;
        do {
                for (k = 0; k < min(num_lanes,8); k++)
                        dest[i + k] = src[k];
                src += min(num_lanes,8);
                i += 8;                        /* PASO FIJO DE 8 */
        } while (i != 0x28);                   /* 5 iteraciones */
}
```

Con `qcom,platform-lane-config = <0xa0a 0xa0a 0xa0a 0xa0a 0x8a8a>` (5 u32 = 20 bytes):

| iter | offset | valor |
|---|---|---|
| 0 | `struct[0x00]` | `0x00000a0a` |
| 1 | `struct[0x08]` | `0x00000a0a` |
| 2 | `struct[0x10]` | `0x00000a0a` |
| 3 | `struct[0x18]` | `0x00000a0a` |
| 4 | `struct[0x20]` | `0x00008a8a` |

## 4. ⚠️ EL LAYOUT NO CIERRA

El parse escribe en `struct[0x00..0x23]`. La escritura del registro lee de
`struct[0x12c..0x12f]` = 300..303. **Faltan 0x10c = 268 bytes de estructura
intermedia** que no se pueden resolver desde el decompilado: en las dos funciones
`param_2` no es el mismo base.

| Registro | Valor | Estado |
|---|---|---|
| **LANE_CFG0** | `0xAA` | **SÓLIDO.** Dos derivaciones independientes: la fórmula con `0x0a, 0x0a` → `0x0a \| 0xa0` |
| **LANE_CFG1** | `0xAA`? | **SIN RESPALDO.** El "0xAA" del RE para el 2º registro no está derivado de nada. Bajo la hipótesis de bytes consecutivos daría `0x00` |

**Por tanto: `0xAA/0xAA` es medio verdad y medio deseo.** No escribiré `0xAA` en
`LANE_CFG1` presentándolo como "el valor del vendor".

## 5. El experimento

Se aplica **`0xAA/0xAA`**, etiquetado como **hipótesis, no como fix**. Motivo: una
prueba no necesita la respuesta definitiva, necesita una hipótesis falsable.

| Resultado | Lectura |
|---|---|
| El síntoma cambia (FIFO/timeout distintos o desaparecen) | El lane map **importa**. G4 queda confirmado como causa parcial y se depura cuál de los dos registros |
| El síntoma es **idéntico** | **G4 REFUTADO.** El lane map no era el problema; se cierra y se pasa a G7 (SSC) / PLL |

**No se puede atribuir a cuál de los dos registros** si algo cambia: por eso se
etiqueta como hipótesis y no como arreglo.

## 6. Rollback

`boot-uke-k52L40.img` (`100fe160…`), dtbo `s283` (`a8e7d4c0…`) — la combinación que
produjo el log de evidencia.

---

## 7. PRE-REGISTRO L41 (13-oct 18:58) — escrito ANTES de flashear

| | |
|---|---|
| Artefacto | `build/bootimg/boot-uke-k52L41.img` |
| **sha256** | `c08170bcdb2ce02f3385cba37a75a529e96855ffe81f596a1333ceb5df25359a` |
| Kernel | `Image.gz` sha `b61c6b890af1f728868aa00c3e399ab409461611ab8bee770c4ffb729ee6ece3` |
| dtbo | **s283** `a8e7d4c0…` (s284 queda descartado: es el wedge) |
| Cambio sobre L40 | **solo** los dos `writel` del lane map: `0x21/0x84` → `0xAA/0xAA` |
| Rollback | `boot-uke-k52L40.img` `100fe160…` + dtbo s283 |

**Comparar contra la evidencia de L40**, que está en `build/evidencia/L40/`:

| En L40+s283 (baseline) | En L41+s283 |
|---|---|
| 7 × `cmd#0` → `host-xfer` | ¿? |
| 7 × `status=4` (FIFO) | ¿? |
| 7 × `status=5` (FIFO+TIMEOUT) | ¿? |
| log corta en `host-xfer` t=20.375873 | ¿? |

**Predicción registrada antes de ver el resultado:** el síntoma **no cambiará**.
El razonamiento para dudar: `LANE_CFG0` es sólido pero `LANE_CFG1` no lo es, y un
registro correcto entre dos no es un lane map correcto. Si aun así cambia, el lane map
importa y hay que depurar cuál. Si no cambia, G4 queda **refutado** y el paso siguiente
es **G7 (SSC)**, que nunca se ha mirado y sí afecta directamente a la calidad del reloj
del enlace.

---

## 8. L42 — G7 (SSC): el gap más limpio del proyecto

**Por qué este y no otro.** Mainline tiene TODO el código SSC escrito
(`dsi_pll_calc_ssc()` calcula stepsize/div_per; `dsi_pll_ssc_commit()` programa los
4 registros + `SSC_CONTROL` con `SSC_EN`). Los tres parámetros ya son **los defaults
exactos del vendor**:

```c
config->ssc_freq    = 31500;   /* vendor */
config->ssc_offset  = 4800;    /* vendor */
config->ssc_adj_per = 2;       /* vendor */
config->ssc_center  = 0;       /* = "down-spread", lo que dice el DT */
/* TODO: ssc enable */
config->enable_ssc  = false;   /* <-- LA UNICA LINEA */
```

Y el DT lo pide explícito, en los dos nodos PLL del DSI:
`qcom,dsi-pll-ssc-en;` + `qcom,dsi-pll-ssc-mode = "down-spread";`

**A diferencia de G4**, esta justificación NO depende de derivar un layout que no
cierra. Los valores ya estaban; solo faltaba la bandera. Y por eso el vendor escribe
`CMODE_1 = 0x00` (SSC activo) y mainline escribía `0x10`.

| | |
|---|---|
| Artefacto | `build/bootimg/boot-uke-k52L42.img` |
| **sha256** | `3328366b5c9482bdac12c40f86e35dccc30d07b488f2dedfe6422c35d850154c` |
| Kernel | `Image.gz` sha `39149505688ebba912912cb4d8cf744b9b085e3022902fc806be6ab72e15906e` |
| dtbo | s283 `a8e7d4c0…` (sin cambios) |
| Cambio vs L40 | **una línea**: `enable_ssc = false → true` |
| Rollback | `boot-uke-k52L40.img` `100fe160…` + dtbo s283 |

**Baseline contra el que comparar** (control, 12 s, ya medido):
cmd#0 x5 · FIFO x3 · FIFO|TIMEOUT x5 · ESD x21 · corta en `host-xfer` t=10.385

**Predicción, registrada antes del flash:** si el SSC es la causa, el
`cmd#0 → FIFO → TIMEOUT` **desaparece o cambia**. Si no cambia, **G7 queda
refutado** y el `FIFO + TIMEOUT` ya ha sobrevivido a OPP, G5, G6, G4 y G7 — lo que
apuntaría a algo por debajo del reloj y la configuración de la PHY: el **propio
reloj del panel en el lado del TDDI**, o que el panel nunca sale de reset.
