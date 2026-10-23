# C5b ciclo 11 — plan (preparado 21-oct-2026 en el PC, sin ejecutar; objetivo del dueño vía gestora: primer frame RAW)
Parte de `docs/historia/revision/CAMARAS-C5-CICLO10-RESULTADO-20261021.md`: con `0x4800` = 0x74/0x76/0x7e el CSID enmarca el inicio de paquete en las 4 lanes (SOT4 ≈ 130–220) y la cabecera sale con ECC erróneo (ECC ≈ 140–210) y a veces con error de 1 bit corregido (`WARNING_ECC` 31–39). Hipótesis (familia nueva, «alineación de lanes en régimen sincronizado»): **orden de lanes entre PHY y CSID y/o temporización de muestreo**. Las pruebas de lane_assign (ciclo 7) y de settle (ciclos 4/7) se hicieron SIN sincronía de SOT, así que no fueron informativas y se repiten ahora (no es un cuarto intento de la misma hipótesis).
Ejecutar requiere orden del dueño para ESTE ciclo + «tuya» de la gestora para la tablet (pedir con «pido tablet: carga de módulos de cámara, ~12 min, sin reinicio»), batería ≥ 30 %, ACM con lector único, doble captura. `build/rootfs/deploy/camaras/c5-ciclo11.sh --check | --go [1|2|3|all]`; **módulos: los de `out-ciclo8/`** (vermagic ouke5; sin build nuevo; `--check` OK). Se recomienda ejecutar por etapas (`--go 1`, luego `2`, `3`): cada llamada recarga y descarga los módulos, ~4–5 min.

## Etapas (modo 2104×1560; máscara RX 0xfffffff0; presupuesto 400 por stream; resumen `RESUMEN … bytes irq SOT SOT4 ECC LONG SHORT CRC OVF WECC`)
1. **lane_assign** — las **24 permutaciones** de {0,1,2,3} (nibble i = lane del PHY que alimenta DLi; identidad = 0x3210) con `0x4800`=0x7e y patrón de test, settle calculado; la identidad se repite como control cada 8 permutaciones y al final (28 streams) porque el régimen no es estable entre arranques.
2. **settle** — {10,15,20,25,30,35,40,50} × {0x7e, 0x76} con patrón, **2 repeticiones** cada uno (32 streams), lane_assign del DT.
3. **skew + settle** — `uke_skew=1`, settle 19 y 30, 0x7e y 0x76, imagen normal (4 streams).

## Criterios (pre-registrados)
- **PASS (hito 2)**: `bytes > 0` o `LONG/SHORT > 0` en cualquier stream. Anotar etapa, permutación/settle y 0x4800; **repetir esa variante 3 veces** antes de darla por buena.
- **Señal parcial** (se ordena por `ECC / SOT4` y por `WECC`): una permutación o settle con ECC/SOT4 claramente menor que el control de su misma etapa (≥ 2× y reproducido en las 2 repeticiones) ⇒ elegir ese valor; ciclo 12 ajusta fino.
- **Refutación**: ECC/SOT4 ≈ control en las 24 permutaciones y en todo el barrido ⇒ la causa no es el orden de lanes ni el settle; siguiente: tabla de IRQ/ajuste del PHY del vendor (`0x102c…`, lane-regs del clock lane), CSID alternativo (csid1/vfe1) y extraer las tablas OFILM de Android (requiere arrancar Android, orden del dueño).
- **Abortar**: Oops/SMMU, batería < 30 %, `dmesg -w` sin crecer, relectura de `0x4800` ≠ escrito.
- Honestidad: el mapa de bits de `0x4800` sigue sin fuente; 0x7e/0x76 son valores empíricos. La señal depende del arranque (0x74 dio SOT4=220 y luego 134 con ECC≈0), de ahí las repeticiones.

## Coordinación con el kernel v7 (optimización)
Los `.ko` de cámara llevan vermagic `7.2.9-senemos.1.4054.3-ouke5` (`CONFIG_MODVERSIONS` off: solo cuenta la release). Si v7 cambia `LOCALVERSION`, hay que recompilar contra su árbol con `KB=<senemos-ouke6/build> KT=<fuente> UKE_SENSDBG=1 UKE_RXIRQ=1 UKE_CSID_LOG=1 UKE_PHY_LOG=1 UKE_CPHY_RX_HZ=19200000 CPPX=-DWITH_IOMMU OUT=…/out-ciclo-v7 build.sh` (~3 min). v7 debe conservar: el parche 0046 (SMMU IFE SID 0x200800 / ACTLR), `CONFIG_I2C_QCOM_CCI`, `MEDIA_*`/`V4L2_*` como módulos y la misma `.config` de `VIDEOBUF2`.
