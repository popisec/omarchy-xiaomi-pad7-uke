# C5b ciclo 6 — plan (preparado en el PC el 21-oct-2026, SIN tablet; NO EJECUTADO)
Requiere orden del dueño para ESTE ciclo, audio «libre», batería ≥ 30 %, lector ACM único, USB 192.168.42.129. Sin flash ni reinicio (solo carga de módulos, como el ciclo 5). Script: `build/rootfs/deploy/camaras/c5-ciclo6.sh --check | --go`; módulos `out-ciclo6/` (vermagic ouke5, 0 avisos).

## 1. Análisis del ciclo 5 con fuente primaria (medido 21-oct)
Fuente: driver de cámara de Xiaomi, repo público `MiCode/vendor_qcom_opensource_camera-kernel`, rama `uke-v-oss` (submódulo de `ztsubaki/uke-linux`), cliffs = `qcom,csid860` que reutiliza las tablas 880, PHY `qcom,csiphy-v2.2.1`.
- **`RX_IRQ_STATUS=0x100f`** = bits 0–3 `DLn_EOT` + bit 12 (`CPHY_SOT_RECEPTION`, nombre de C-PHY; en D-PHY no está documentado su significado; las máscaras 880 lo clasifican «part-fatal» — resumen de modelo sobre un fichero truncado, NO verbatim). Bits 4–7 `DLn_SOT`, 8 long pkt, 9 short pkt, 19 CRC, 20 ECC, 15–18 overflow por lane, 21/22 VC/DT mapeado/no. **Ninguno de SOT/paquete apareció**: el receptor ve fin-de-transmisión en las 4 lanes pero nunca un inicio ni un paquete.
- **Diferencia real y verificable en la secuencia del CSIPHY** (vendor `cam_csiphy_core.c`, `cam_csiphy_2_2_1_hwreg.h` vs mainline `csiphy_lanes_enable`/`lane_regs_sm8650`):

| paso | vendor (D-PHY 2.2.1) | camss mainline (nuestro kernel) |
|---|---|---|
| reset | `0x1000=0x01` | — |
| lanes | `0x1014 |= lane_enable` | CTRL5 = CLK_EN | lanes (0xd5, igual) |
| comunes | `0x1084=0`, `0x108C=0`, **`0x101C=0x7A`**, `0x1018=1` | `0x1018=1`, **`0x101C=0x02`** |
| tablas de lane | idénticas en valores a `lane_regs_sm8650` (A+B); skew OFF ⇒ 0x00 | igual (sin skew) |
| IRQ | `0x102c..0x1054` = ff/ff/fb/ff/7f/ff/ff/ef/ff/ff/ff | todas a 0 |
| liberar reset | **`0x1000=0x02` al final** | `0x1000=0x00` ANTES de las tablas y nunca 0x02 |
- Settle del vendor = `settle_time/200 MHz` (el de Android «3800000000» ⇒ 19), nosotros 30 (barrido 12–55 sin efecto): no es el problema. Lane table: idéntica ⇒ H-LREG baja. **H-PHYSEQ sube a primera**: el PHY nunca se lleva al estado «liberado» (`0x1000=0x02`) y CTRL7 difiere (0x02 vs 0x7A). Es compatible con lo medido: PHY responde a registros y CSID ve EOT en 4 lanes, sin SOT.
- Android (captura 20-oct): CTRL5 `0xd5` y lane_assign `0x3210` ya coinciden; el Android no expone `0x1000/0x101C` (sin debugfs), así que la comparación de esos dos es solo con el código fuente del vendor.
- Honestidad: mainline sm8650 funciona upstream con su secuencia en otra placa; en cliffs (v2.2.1 vs 2.2.0) puede diferir. Hipótesis, no hecho.

## 2. Diseño (un solo arranque de módulos, 4 variantes × {B patrón de test, A normal})
Parámetros nuevos de `uke-camss` (todos por defecto = comportamiento anterior): `uke_ctl7` (-1 → 0x02), `uke_ctl0_post` (-1 = no escribir), `uke_cmn84` (0/1). Más `uke_rx_mask=0xfffffff0` y `uke_rx_budget=400` repuesto antes de CADA stream (arregla el defecto del ciclo 5).
| variante | ctl7 | ctl0_post | cmn84 | para qué |
|---|---|---|---|---|
| V0 | — | — | 0 | línea base con máscara nueva (B y A por fin legibles) |
| V1 | 0x7a | 0x02 | 1 | secuencia completa del vendor |
| V2 | — | 0x02 | 0 | aísla la liberación de reset |
| V3 | 0x7a | — | 0 | aísla CTRL7 |
Orden fijo V0→V3, B antes que A. Un cambio lógico (H-PHYSEQ) por ciclo; el desglose V2/V3 solo sirve para interpretar V1.

## 3. Criterios (pre-registrados)
- **PASS (hito 2)**: algún `…/B` o `…/A` con bytes > 0 (esperado 2104×1560×10/8 ≈ 4,1 MB). Anotar la variante mínima que lo logra.
- **Señal parcial**: aparecen bits SOT (0x10–0x80), `LONG_PKT` (0x100) o `SHORT_PKT` (0x200) sin bytes ⇒ el PHY ya engancha; siguiente: CRC/ECC (bits 19/20), VC/DT (21/22), formato RDI.
- **Sin cambio** (solo 0x100f/EOT, 0 bytes en las cuatro) ⇒ H-PHYSEQ refutada en 1 ciclo (techo 3); siguiente hipótesis: H-SENS (si B también da solo EOT, el sensor no emite ni con patrón: revisar `0x0100` streaming, lane clock continuous/`0x4800`, MIPI output enable del OV13B10) y la tabla de IRQ del PHY del vendor (`0x102c…`).
- **Abortar** si hay Oops/SMMU fault, `dmesg -w` perdido, o batería < 30 %; el script ya descarga módulos al final. Doble captura (ssh dmesg + ACM) como siempre.

## 4. Fuera de alcance / pendiente
No se ha tocado la tablet. `ctl0_post` y `0x1084/0x108c` no se han verificado en hardware. Las máscaras fatal/part-fatal y la tabla del PHY IRQ vienen de un resumen parcial: verificar en el fichero original antes de basarse en ellas.
