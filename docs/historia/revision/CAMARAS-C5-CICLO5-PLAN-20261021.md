# Cámaras — C5b ciclo 5: IRQ del RX/RDI del CSID + patrón de test del sensor (PREPARADO en el PC, 21-oct-2026; NO ejecutado)

Pedido de la sesión gestora (relay del dueño): «prepara en el PC el siguiente paso del frame RAW: el IRQ del RX del CSID y el patrón de test del sensor OV13B10. Deja listos los módulos, la prueba y los criterios para ejecutarlo en un solo ciclo cuando se libere la tablet y el dueño lo autorice. No hagas builds completos del kernel.» **No se ha tocado la tablet ni el árbol del kernel** (solo módulos fuera de árbol).

## Material
- `camaras/out-rxirq/` (gitignored): los 6 `.ko` con `UKE_RXIRQ=1 UKE_CSID_LOG=1 UKE_PHY_LOG=1 UKE_CPHY_RX_HZ=19200000` y overlay `-DWITH_IOMMU` (vermagic ouke5; lanes `<0 1 2 3>` ya corregidas). `uke-camss.ko` añade los parámetros `uke_rx_mask`, `uke_rdin_mask`, `uke_rx_budget` (0644) y `uke_settle`.
- `camaras/c5-ciclo5.sh` — `--check` (PC) y `--go` (ejecuta; comprueba batería ≥ 30 %, que no haya módulos de cámara, sha de lo copiado; `dmesg -w` a fichero; descarga en orden inverso). **Una sola secuencia, dos pruebas:** A = stream normal con el IRQ habilitado; B = mismo stream con el patrón de test del sensor (`test_pattern=1`, barras). `--check` pasa.
- `camaras/patches/gen-modules.py` (`UKE_RXIRQ`): en el CSID gen3 habilita al empezar el stream `CSID_CSI2_RX_IRQ_MASK` (0xA0) y `CSID_CSI2_RDIN_IRQ_MASK(rdi)` (0xF0 + 0x10·rdi) con la máscara completa y registra `RX_IRQ=…`/`RDIn_IRQ=…` con presupuesto de 200 mensajes (al agotarse, vuelve a enmascarar el RX). Es una **escritura de configuración reversible** (máscaras de IRQ), no un volcado de registros.

## Condiciones para ejecutar (todas)
1. Orden expresa del dueño para este ciclo. 2. La sesión de audio dice «libre» (M1 del micrófono en curso a 21-oct). 3. Batería ≥ 30 % (el script aborta si no). 4. Tablet recién arrancada o sin módulos de cámara. 5. USB (192.168.42.129) + lector ACM único; no Tailscale (un cuelgue lo corta). 6. `dmesg -w` a fichero (lo hace el script). Riesgo: bajo-medio (el IRQ puede disparar una tormenta: tope de 200 mensajes; un cuelgue exigiría reset físico).

## Qué se espera y cómo se lee (criterios)
| Observación | Lectura | Siguiente |
|---|---|---|
| A y B: **0 bytes y ningún `RX_IRQ`/`RDI_IRQ`** | el receptor del CSID no ve **nada**: el problema está antes del CSID (PHY analógico, `lane_regs` de cliffs, rail/reloj del PHY) | H-LREG/H-PWR: comparar lane regs con la tabla OEM; caer a «bloqueado en el PHY» |
| `RX_IRQ` con bits de **error** (ECC/CRC/lane FIFO overflow/SOT) | llegan paquetes pero mal: lanes cruzadas, settle o velocidad | variar `uke_settle` (ya hay barrido), `data-lanes`, `link_frequency` |
| `RDI_IRQ` con **SOF/EOF** pero 0 bytes | el CSID ve tramas: el fallo es el VFE/SMMU/RDI/buffers | mirar `wm`/IOVA, `bufdone`, formato RAW |
| **B da bytes y A no** | el PHY/CSID/VFE/SMMU funcionan; el sensor en modo normal no emite bien | comparar el modo del sensor (registros del modo 2104×1560), reloj externo, link freq |
| **B y A dan bytes** | **frame RAW conseguido** (`stat` del fichero = `4118400` B esperado en 2104×1560 `pgAA`) | guardar el fichero, verificar contenido (sin hacer commit del binario), seguir con 4208×3120 |
| tormenta de IRQ / cuelgue | el enmascarado completo es demasiado | repetir con `uke_rx_mask` acotado (p. ej. solo errores) |
| `Unhandled context fault` | SMMU: parar (no instrumentar) | revisar `0046` |
Techo de 3 ciclos por hipótesis; este ciclo prueba dos (H-RXIRQ y H-SENS), una vez cada una.

## Lo que NO se ha hecho a propósito
Ningún build del kernel (optimización propondrá cambios sobre el mismo árbol; las pruebas usan los módulos fuera de árbol y el kernel v6 ya instalado). No hay referencia de Android para la tabla de lanes del PHY: H-LREG sigue sin forma de contraste.
