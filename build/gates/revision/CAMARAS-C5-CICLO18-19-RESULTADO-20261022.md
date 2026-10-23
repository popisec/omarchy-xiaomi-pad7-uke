# C5b ciclos 18–19 — autofoco de la trasera (22-oct-2026 02:42–02:45; orden del dueño «sigue con el enfoque (VCM), solo insmod/rmmod»)
**El VCM CN3927V funciona en Linux y la foto sale enfocada.** Sin flash ni reinicio; 0 faults SMMU/oops; 0 módulos al final de cada ciclo.

## Piezas nuevas (`build/rootfs/deploy/camaras/vcm/`, `./build-vcm.sh` → `out-ciclo18/`, ouke5, 0 avisos)
- **`uke_rpmh_ldob14.ko`**: el riel del VCM (`pmxr2230_l14`, 2,8 V fijo; `cam_vaf` del DT de Android) no estaba registrado porque la allowlist de `qcom-rpmh-regulator-uke.c` lo deja fuera a propósito (C3). `gen-ldob14.py` copia ese driver como módulo con una allowlist de **un solo recurso** (`ldob14`); cualquier otro nodo rpmh sin driver se rechaza antes de tocar el hardware. Símbolos (`rpmh_write*`, `cmd_db_*`, proxy-consumer) exportados en ouke5 (`Module.symvers`). Sin kernel nuevo.
- **`uke_cam_vcm.ko`** (overlay `uke-cam-vcm.dtso`): nodo `lens@c` en `i2c-bus@1` del CCI0 (`compatible "uke,cn3927v-vcm"`, `vdd-supply = &pmxr2230_l14`, `vio-supply = &pmxr2230_l20`). `fdtoverlay` verde sobre `out-ciclo16/merged.dtb`.
- **`uke_vcm.ko`**: driver mínimo sin V4L2. Al cargar enciende vio+vdd y **escanea el bus solo por lectura de 1 byte**; el DAC (10 bits, protocolo DW9714 por hipótesis: `[D9..D4] [D3..D0|S]`) se escribe por el parámetro `dac`, solo a `tgt` y nunca a 0x10 (sensor) ni a 0x50–0x57 (EEPROM). Al descargar aparca la lente en pasos de 64.
- `ukeaf.py` (sin numpy, en la tablet): media y contraste de los verdes del centro.

## Medido
- Ciclo 18 (`c5-ciclo18.sh`, registro `out/c5-ciclo18-20261022-0242.txt`): `l14` registrado (2 800 000 µV); escaneo del bus 1: **`0x0c` (VCM) y `0x51` (EEPROM BL24SA64)**; `dac=0` → ACK (`lastret=1`); barrido 0..1023 paso 64 con 17/17 frames completos. Exposición máxima con la escena ya iluminada: **saturado** (media 969/1023), aunque el contraste ya caía de 4,39 (DAC 64) a 3,0 (DAC ≥ 768): la lente se mueve.
- Ciclo 19 (`c5-ciclo19.sh`, registro `out/c5-ciclo19-20261022-0243.txt`): auto-exposición en 2 pasos (exp 3188, g. analógica 1×→máx.; media8 19,6→75,9); autofoco por contraste, grueso (paso 64) + fino (±48, paso 16): **mejor DAC = 448**. Comprobado en el PC con la imagen suavizada 8×8 (sin el ruido de ganancia alta): nitidez 21,97 (DAC 448) frente a 16,95 (DAC 0) y 11,89 (DAC 1023). PNG `out/b19-best-wb.png` (no versionado, enviado al dueño): una caja de cartón con el tapón y el logotipo legibles y la arista del techo nítida; con DAC 1023, borrosa.
- La métrica de la tablet (suma de |diferencias| sin suavizar) está dominada por el ruido con ganancia máxima (variación de ~5 %); escoge bien, pero conviene suavizar antes en una versión futura.

## Pendiente
Demosaico y balance reales (ahora es una vista previa 2×2), V4L2 del VCM (`V4L2_CID_FOCUS_ABSOLUTE`) o libcamera/softISP para una app, frontal (OV08D10), EEPROM (calibración AF en 0x51, solo lectura), persistencia de los módulos en el arranque (requiere decisión del dueño).
