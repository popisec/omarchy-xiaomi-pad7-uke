# REV-GENI-I2C-DMA — por qué no hay I2C/SPI-GPI y cómo cablearlo (13-oct-2026)

Medido por SSH en la tablet viva (kernel `7.2.0-rc2-palawan`) + código en
`build/kernel-pokes/k52L39-tree/` + DT vivo en `/proc/device-tree` + DT vendor
en `~/proyectos/ubuntu-uke/stock/dtbase/base-uke.dts` + base que se
flashea en `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img`.
El SSH cayó al final de la sesión (2 timeouts de lectura); no se escribió nada
en la tablet. Sin flash, sin reboot, sin tocar `boot_a`/`dtbo_a`.

## 1. Dónde muere el probe del I2C: en ninguna línea — ni se invoca

Evidencia viva:

- `a80000.i2c` existe en `/sys/bus/platform/devices/` pero **sin driver**
  (`readlink .../driver` vacío); el driver `geni_i2c` existe y no tiene NINGÚN
  dispositivo ligado; el dispositivo **no** está en `devices_deferred`.
- `dmesg` no contiene ni una línea del probe I2C: ni siquiera los `pr_info`
  `X9I2C-*` que el árbol lleva en `geni_i2c_probe`
  (`drivers/i2c/busses/i2c-qcom-geni.c:1062-1091`), ni el `dev_info` de
  "Bus frequency not specified" (:1026) que debería salir porque el nodo no
  tiene `clock-frequency`.
- `gcc-palawan ... sync_state() pending due to a80000.i2c` (y `a8c000`,
  `880000`, `88c000`, `890000`): los 5 I2C activos nunca resolvieron.

Causa raíz: el DT (base vendor) declara `compatible = "qcom,i2c-geni"` (nombre
downstream; verificado en vivo por `od` y en `base-uke.dts:14037` y ss.), pero
la tabla OF del driver mainline solo acepta

```
drivers/i2c/busses/i2c-qcom-geni.c:1283-1287
    { .compatible = "qcom,geni-i2c" },
    { .compatible = "qcom,geni-i2c-master-hub", ... },
```

Sin match no hay probe. **No es config** (`CONFIG_I2C_QCOM_GENI=y`,
`CONFIG_SPI_QCOM_GENI=y`, `CONFIG_QCOM_GPI_DMA=y`, `CONFIG_QCOM_GENI_SE=y`
verificados en el `.config` vivo): es el compatible.

## 2. El SPI falla en otro punto de la misma familia: `spi-geni-qcom.c:578`

`dmesg`: `geni_spi a90000.spi: error -ENODEV: Failed to get tx DMA ch`.
El SPI **sí** binda (su compatible ya es `qcom,geni-spi`, apañado por un overlay
anterior junto con `clock-names="se"`) y pasa `devm_clk_get(dev,"se")`
(`spi-geni-qcom.c:1063`), pero su `dmas` en vivo tiene **0 bytes** (el overlay
anterior vació el dmas vendor de 5 celdas sin reponer el de 3) =>
`dma_request_chan(mas->dev,"tx")` (:578) devuelve `-ENODEV` (:580-582).
**No es el mismo punto de fallo que el I2C, pero sí la misma causa de fondo**
(DT vendor sin adaptar a mainline) **y el mismo proveedor roto** (punto 3).

## 3. El proveedor DMA (GPI) no existe: dos fallos encadenados

- Los nodos `qcom,gpi-dma@{a00000,800000}` declaran SOLO
  `compatible="qcom,gpi-dma"` (verificado en vivo y en `base-uke.dts:13986` /
  `:14388`). `gpi_of_match` (`drivers/dma/qcom/gpi.c:2299-2311`) solo acepta
  `qcom,<soc>-gpi-dma` con el comentario explícito de no ampliar la lista sino
  usar `qcom,sdm845-gpi-dma` (ee_offset 0) o `qcom,sm6350-gpi-dma` (ee 0x10000).
  En vivo `qcom,gpi-ee-offset = 0x10000` => toca `sm6350`. Sin match no hay
  driver GPI (ambos `800000/a00000.qcom,gpi-dma` sin driver en sysfs); el único
  DMA vivo es `6c04000.bamdma`. De ahí el `-ENODEV` del SPI.
- Además `gpi_probe` exige `dma-channels` y `dma-channel-mask`
  (`gpi.c:2178-2192`, error si faltan) y el vendor no las trae (usa
  `qcom,max-num-gpii=<0x0c>` + `qcom,gpii-mask=<0x1e>`). Y el vendor usa
  `#dma-cells=<5>` con dmas de 5 celdas `(ch, se, proto, 0x40, x)` mientras el
  xlate mainline espera 3 `(chid, se_idx, QCOM_GPI_*)` con `QCOM_GPI_SPI=1`,
  `QCOM_GPI_I2C=3` (`include/dt-bindings/dma/qcom-gpi.h:7-9`).

## 4. Qué le falta al nodo GENI SE: nada (hipótesis descartada con evidencia)

El wrapper `qupv3_0_geni_se@ac0000` tiene `dmas` vacío, pero **es lo correcto**:
`drivers/soc/qcom/qcom-geni-se.c` no lee `dmas` (solo
`of_property_read_bool(...,"qcom,enable-gsi-dma")` en `:1571` para el modo GSI,
ausente aquí y no necesario). El wrapper probea bien (driver `geni_se_qup`
ligado) y el SPI llega hasta la fase DMA, lo que prueba que `resources_on` +
firmware del SE funcionan. `qcom,enable-gsi-dma`, `#msi-index` o props GSI:
**no hacen falta** (cero ocurrencias de `enable-gsi` en el DT stock).

## 5. El arreglo: `build/gates/FRAGMENTO-GENI-I2C-DMA.dts` (9 fragmentos, un cambio)

Sobre la base vendor, con `target-path` + phandles literales (`0x1df`=gpi0,
`0x228`=gpi1, verificados en `base-dtb.img` por `fdtget`; convención de
`touch-fix.dts`). Índices SE copiados del dmas vendor (wrapper0:
a80000->0, a84000->1, a8c000->3, a90000->4; wrapper1: 880000->0, 88c000->3,
890000->4). Valores espejo de `palawan.dtsi`:

- 2× gpi-dma: `compatible="qcom,palawan-gpi-dma","qcom,sm6350-gpi-dma"`,
  `#dma-cells=<3>`, `dma-channels=<12>`, `dma-channel-mask=<0x1e>`.
- 5× i2c activos (`a80000`, `a8c000`, `880000`, `88c000`, `890000`):
  `compatible="qcom,geni-i2c"`, `clock-names="se"` (el vendor trae `"se-clk"`
  y el driver pide `"se"` en `i2c-qcom-geni.c:1019`; sin esto el probe moriría
  con `-ENOENT` justo después del fix del compatible), `dmas` 3 celdas +
  `dma-names="tx","rx"`.
- 2× spi activos (`a84000` SE1, `a90000` SE4): `compatible="qcom,geni-spi"`,
  `clock-names="se"`, `dmas` 3 celdas proto=1 (repone el dmas vacío del a90000).
- No se toca `status`, ni el wrapper SE, ni pinctrl/interconnects (nombres
  `qup-core/qup-config/qup-memory` ya coinciden con `qcom-geni-se.c:117-118`).

Gates (13-oct, locales):

- `dtc -@` compila (solo warnings de phandle literal, esperados standalone).
- `fdtoverlay -i base-dtb.img -o merged.dtb geni-fix.dtbo` => **OK**; `fdtget`
  sobre el fusionado confirma los 9 nodos (compat, clock-names, dmas
  `1df/228 ...`, `dma-channels=12`, `mask=0x1e`); el hijo `wcd939x_i2c@e` del
  i2c@a80000 se conserva.
- `uke-dtbo-check.py` (payload envuelto en dt_table mínimo): fdtoverlay OK,
  todos los phandles resuelven (`dmas 0x1df`, `clocks 0x16e`, pinctrl…).
  Único `FALTA: .../spi@a90000/touchscreen@0`: **preexistente, no regresión**
  (la base no trae ningún hijo de touch; los ponen otros fragmentos del dtbo
  vivo —hoy `novatek@0`+`goodix-berlin@0`— y este overlay no toca hijos ni
  `status`: en base el spi@a90000 sigue `disabled`, lo habilita el dtbo vivo).

Aplicación pendiente (requiere ciclo con flash, NO hecho): insertar los 9
fragmentos en el payload del dtbo vigente antes del último `};`, renumerando
`fragment@N` si colisionan (método de `mk-dtbo-touchfix.py`), con fila de
ledger. Éxito esperado: 5 adaptadores en `/sys/class/i2c-adapter/`,
`Geni-I2C adaptor successfully added` en dmesg, fin del `Failed to get tx DMA
ch` del SPI. **Esto además arregla el SPI/táctil** (misma GPI-DMA) y desbloquea
el KTZ8866 (`ktz8866@11` ya cuelga del i2c@a80000 en vivo).

## 6. Incertidumbres explícitas (no determinable sin boot)

- FIFO vs GPI en I2C: `setup_gpi_dma` solo corre si `GENI_IF_DISABLE_RO` tiene
  `FIFO_IF_DISABLE` (`i2c-qcom-geni.c:1107-1115`); se lee en runtime. Si el FIFO
  está activo, el I2C registra sin GPI; el SPI (`a90000`) ya demostró necesitar
  GPI, así que el fix cubre ambos casos.
- `spi@a84000` en vivo tiene `status=ok` pero compatible/clock-names vendor
  (`qcom,spi-geni`/`se-clk`): su probe muere en silencio en el `clk_get`
  (sin mensaje). El fragmento lo cubre; no se pudo releer en vivo por la caída
  del SSH.
- `spi@a8c000` trae `status="disable"` (typo por `"disabled"` en algún overlay):
  inofensivo (≠okay => deshabilitado), fuera de ámbito, se deja constancia.

## 7. Lo que ya está bien (una línea por punto)

- Config del kernel: los 4 símbolos (`I2C_QCOM_GENI`, `SPI_QCOM_GENI`,
  `QCOM_GPI_DMA`, `QCOM_GENI_SE`) están `=y` y compilan.
- Wrapper GENI SE: probea, binda `geni_se_qup`, no necesita `dmas` ni GSI.
- Interconnects/pinctrl/IRQs de los nodos QUP: nombres y valores compatibles
  con mainline, sin tocar.
- Hijos existentes (`wcd939x_i2c@e`, `ktz8866@11`, `novatek@0`,
  `goodix-berlin@0`): el overlay no los altera.
