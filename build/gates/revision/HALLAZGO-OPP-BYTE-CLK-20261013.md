# ⭐ HALLAZGO PRINCIPAL — el OPP del host DSI corre el link un 26% más rápido de lo que el panel fue validado

> 13-oct-2026. Salida del RE completo del vendor (Ghidra sobre `msm_drm.ko`) + auditoría adversarial.
> **Esto es una línea de DT, no un kernel.** Es el candidato nº1 y el más barato de todo el proyecto.

---

## 1. El hecho

**Mainline pide un byte-clock que el OPP no tiene, y el OPP lo redondea hacia arriba un 26%.**

```
mainline calcula   byte_req = 118.918800 MHz     (dsi_host.c:639-682)
tabla OPP (overlay flashed, fase4-display.dts:390):
                   187.5 / 300 / 358 MHz
dev_pm_opp_set_rate(118918800) → elige el primer OPP ≥ → 187.500000 MHz
                                bitclk real = 187.5 × 8 = 1500 Mbps/lane
```

**Lo que hace Android** (medido, no inferido):

```
panel-clockrate = 0x46E19970 = 1.189.190.000 Hz     (DT stock del panel)
byte_clk        = panel-clockrate / 8 = 148.648.750 MHz   ← MEDIDO en Android
```

```
mainline / vendor = 187,5 / 148,64875 = +26,2 %
```

## 2. Por qué esto y no es cosmético

**Los timings de la PHY se calculan con la tasa PEDIDA, no con la real.**

`msm_dsi_dphy_timing_calc_v4()` (`dsi_phy.c:374-470`) depende **solo** de `bitclk_rate` = el valor
solicitado. El OPP redondea después. Resultado: **los timings están calculados para 951 Mbps/lane y se
ejecutan a 1500 Mbps/lane.**

Al recalcular las fórmulas con la tasa real, **4 de 7 parámetros quedan por debajo de los mínimos
MIPI DSI**:

| Parámetro | mainline (a 951 Mbps) | @ 1500 Mbps real | Mínimo MIPI |
|---|---|---|---|
| `clk_zero` | ok | **bajo** | — |
| `clk_trail` | ok | **bajo** | — |
| `hs_prepare` | ok | **bajo** | — |
| `hs_trail` | ok | **bajo** | — |

## 3. Encaja con la firma de la muerte

| Observado | Explicado por |
|---|---|
| **PLL enganchada** (`status` sin bit `0x20 PLL_UNLOCKED`) | La PLL funciona — solo que a la frecuencia equivocada |
| **`err_work_state=4`** (FIFO) | Las lanes HS no conseguen el lock con timings calculados para otra velocidad ⇒ FIFOAssert |
| **10-15 DCS en LP sí llegan** | Los DCS viajan por el clock de escape, no por el de link. Van bien |
| **`VIDEO_DONE` nunca completa** | El motor de vídeo no arranca porque el link no engancha |
| **Muerte justo tras `K48-w4-done`** | El reset del TDDI sí ocurre; lo que falla es el establecimiento HS después |

## 4. El arreglo

**Una línea de DT. Sin build de kernel, sin tocar el driver.**

Añadir el OPP que falta a la tabla del host DSI, para que `dev_pm_opp_set_rate` aterrice en el valor
del vendor en vez de redondear:

```dts
mdss_dsi_opp_ml: opp-table {
        opp-148648750 { opp-hz = /bits/ 64 <148648750>; };   /* <-- NUEVO: el del vendor */
        opp-187500000 { opp-hz = /bits/ 64 <187500000>; };
        opp-300000000 { opp-hz = /bits/ 64 <300000000>; };
        opp-358000000 { opp-hz = /bits/ 64 <358000000>; };
};
```

> Con `opp-148648750` presente, el `ceil` de 118.918800 cae en **148.648750** ⇒ bitclk
> **1189.19 Mbps/lane**, que es exactamente el `panel-clockrate` del DT de Xiaomi.

**Alternativa si el OPP resultante no es exacto**: quitar el redondeo y fijar la tasa con
`assigned-clock-rates` en el nodo del host DSI (peroojo: `s280` ya intentó sembrar por DT y falló,
así que la vía OPP es la que está probada por el propio kernel).

## 5. Por qué esto no se vio antes

- Los OPP del DPU (`200/325/375/514`) son los que el proyecto ha estado midiendo todo el rato
  (`mdp_clk` a 514 MHz). Los del **host DSI** (`187,5/300/358`) nunca se miraron: no aparecen en
  `clk_summary` porque ese clock no se enciende hasta el commit, y hasta L33 no hubo commit.
- El `-22` del `vsync_clk` y el `rcg didn't update` que centraron el diagnóstico son de **otros**
  clocks (DPU), no del host DSI.

## 6. Verificación antes y después (SSH, cero flashes)

**Antes** (con L33 viva):
```bash
grep -A2 opp- /sys/kernel/debug/clk/clk_summary | grep -i byte
# esperado: byte_clk 187500000  <-- si es esto, el bug está confirmado
grep -E '^\[.*escode|rcg' dmesg | tail
```

**Después** (con el OPP nuevo):
```bash
# el byte_clk debe mostrar 148648750
# y el log debe pasar de K48-w4-done a los 108 DCS (cmd#0)
```

## 7. Nota de honestidad

- Los **4 parámetros bajo mínimos** son un **cálculo propio** del agente sobre las fórmulas de
  mainline, no una medición de hardware. Es coherente con la firma, pero no es prueba.
- La medición del `byte_clk` del vendor (148.648.750) viene de los logs de Android
  (`mi_disp_printk`), no de este binario. Conviene confirmarla en vivo.
- **`panel-clockrate`**: el enunciado del RE decía 1.190.269.040; el valor real en el DT de stock es
  **1.189.190.000** (`0x46E19970`). La diferencia es 0,09% y no cambia la conclusión, pero el
  número bueno es el segundo.

---

## Ficheros

| Qué | Dónde |
|---|---|
| Tabla OPP (overlay) | `~/gpu-work/ramaa/s21/dtbo-gpu/fase4-display.dts:390-401` |
| Cálculo mainline del byte-clock | `build/kernel-pokes/k52L33-tree/drivers/gpu/drm/msm/dsi/dsi_host.c:639-682` |
| `dev_pm_opp_set_rate` del byte | `dsi_host.c:390-391` |
| Validación del modo contra la OPP | `dsi_manager.c:407-433` (`MODE_CLOCK_RANGE`) |
| Cálculo de timings PHY | `dsi_phy.c:374-470` (`msm_dsi_dphy_timing_calc_v4`) |
| `panel-clockrate` del panel | `stock/dtbo/stock_uke.dts`, nodo `o82_42_02_0b` |
| Informe completo | `docs/historia/revision/INFORME-MODO-OPP-DSC-20261013.md` |
| Timings PHY comparados | gap G6 en `GAPLIST-VENDOR-MAINLINE-20261013.md` |