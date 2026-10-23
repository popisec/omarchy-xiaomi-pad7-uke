# C5b ciclo 16 — resultado (22-oct-2026 02:30–02:34; sesión autónoma de cámaras, solo insmod/rmmod, sin flash ni reinicio)
**PRIMER FRAME RAW VALIDADO de la trasera (OV13B10) en Linux.** Causa del fallo de los ciclos 2–15: el reloj de datos del PHY/CSID iba a **19,2 MHz**.

## Causa (hipótesis H7, nueva; 1 ciclo)
Desde el ciclo 2 (H-PHY2, 20-oct) todos los módulos se compilaban con `UKE_CPHY_RX_HZ=19200000` (`gen-modules.py` cambia `csiphy_rx` de `csid_res_sm8650` de 400 MHz a 19,2 MHz). El RCG compartido `cam_cc_cphy_rx_clk_src` alimenta `csiphy1_clk` y `csid_csiphy_rx_clk`: corrían a 19,2 MHz (`docs/historia/revision/CAMARAS-C5-20261020.md` §ciclo 2 lo midió así). H-PHY2 se «refutó» cuando todavía no llegaba nada (lanes mal), pero **el cambio se quedó en todas las builds siguientes**. El 19,2 MHz de Android (`docs/historia/revision/CAMARAS-ANDROID-20261020.md` §3) era una **lectura en reposo**: en esa misma captura `csid_clk` e `ife_2_clk_src` también estaban a 19,2 MHz. Con 4 lanes a 1,12 Gbps hacen falta ≥ 140 MHz de reloj de byte: de ahí el overflow de FIFO por lane (b15–18), el SOT en solo ~50 % de los bursts, los ECC y que el RDI viera ~200 líneas en 10 s.

## Cambio
Módulos `out-ciclo16/` = los del ciclo 15 **sin** `UKE_CPHY_RX_HZ` (`KB/KT=senemos-ouke5`, 0 avisos). Comprobado en el binario: `uke-camss.ko` difiere del del ciclo 15 solo en 3 constantes u32 19 200 000 → 400 000 000 (29 bytes distintos). Script `c5-ciclo16.sh` (Tailscale, `trap` EXIT en PC y tablet, sin printk en el ISR, lectura de `clk_rate` por debugfs a 1 s de cada stream).

## Medido (14 streams; registro `out/c5-ciclo16-20261022-0230.txt`, dmesg `out/c5c16-dmesg-0230.log`)
- `clk(1s): cphy_rx=400000000 csiphy1=400000000 csid_csiphy_rx=400000000 csid=400000000` en los 14.
- **14/14 streams devuelven buffer en < 1 s**, `bytes=4118400`, todos con > 3,9 MB no nulos (imagen) o 2,27 MB (patrón). Antes: 1/17–2/40 buffers, casi vacíos.
- Contadores RX de todo el stream: solo EOT (b0–3) y SOT (b4–7) en las 4 lanes, **ECC (b20) = 0, overflow (b15–18) = 0, underflow = 0**; `b19` (CRC) = 1 en 3 de 14 streams. RDI0: SOF/EOF limpios, `bufdone=1` (3 en streams más largos).
- **Patrón de test (barras de color, `test_pattern=1`)**: 2 streams, sha idéntico `10ef7bcc…`; las 1560 filas con datos; medias por octavo de ancho `1021, 766, 768, 511, 511, 262, 254, 7` = las 8 barras (blanco…negro); constante en vertical. PNG `out/b16-1.png` (no versionado): barras perfectas.
- **Imagen real** (0x4800 = 0x64 de la tabla, 0x7e o 0x76: los tres funcionan igual): 1560/1560 filas, min/max 47/84, media 64,4 = **nivel de negro + ruido** (son las 02:30; escena a oscuras y/o exposición/ganancia por defecto). Siguiente: subir exposición/ganancia (ciclo 17).
- 0 faults SMMU/oops; `restan 0` módulos; batería 96 %.

## Consecuencias
- **Refutados como causa** (eran síntomas del reloj): H1/H2/H4/H5/H6 de `PENDIENTES-CAMARAS-20261022.md` §3. No hacen falta las tablas OFILM (§4a) para tener imagen.
- `0x4800` no importa: la tabla de mainline (0x64) funciona.
- `gen-modules.py`: `UKE_CPHY_RX_HZ` queda como opción de diagnóstico; **no usarla**.
