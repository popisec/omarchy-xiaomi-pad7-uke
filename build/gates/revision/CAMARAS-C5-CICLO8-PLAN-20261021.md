# C5b ciclo 8 — plan (preparado 21-oct-2026 sin ejecutar; orden del dueño: «prepara el ciclo 8 (lado sensor OV13B10…) sin ejecutarlo»)
Parte de ciclos 5–7 (`…CICLO6-RESULTADO…`, `…CICLO7-RESULTADO…`): el receptor ve EOT constante, SOT esporádicos y **nunca** cabecera de paquete, ni con patrón de test; settle y lane_assign refutados, skew-cal del vendor sube SOT sin paquetes. Hipótesis nueva (otra familia): **H-SENSMODE** — el OV13B10 no emite en la uke lo que el receptor espera.
Evidencia que la motiva (medida): Android arranca `o82_ofilm_ov13b10_wide_i` en **4208×3120@30, «NORMAL TYPE3PD»** (`build/android/camara-20261020/abierta/dmesg-cam.txt`), mientras nuestro driver (mainline, tablas de otro módulo) corre el modo **2104×1560** con las tablas Intel; el módulo OFILM de Xiaomi usa tablas propias (en la librería de sensor de userspace, **no está en el PC**: `~/backups/uke-android-cosecha-20261019/sensores-*` son IMU, no cámara). Sin esas tablas no se puede garantizar equivalencia; este ciclo mide qué hace el sensor.
Ejecutar requiere: orden del dueño para ESTE ciclo, turno libre, batería ≥ 30 %, ACM con lector único, doble captura (el script graba `dmesg -w`), sin flash ni reinicio. `build/rootfs/deploy/camaras/c5-ciclo8.sh --check | --go`; módulos `out-ciclo8/` (ouke5, 0 avisos, `--check` OK).

## Cambios de código (por defecto sin efecto)
`uke_ov13b10`: `uke_dump=1` lee 18 registros concretos (0100 0103 0303 0305 0323–0327 3012 3013 4008 4800 4837 5000 5080 3501 0202) a +50 y +400 ms de `MODE_SELECT=1`, con modo actual en el log; `uke_xreg/uke_xval` escribe UN registro extra tras la tabla del modo y antes de `MODE_SELECT`.

## Matriz (7 streams; máscara RX 0xfffffff0, presupuesto 400 por stream; resumen `RESUMEN … bytes irq SOT SOT4 ECC LONG SHORT CRC OVF WECC`)
| id | modo | pantalla | extra |
|---|---|---|---|
| M B / M A | 2104×1560 | patrón / normal | solo lectura de registros |
| F B / F A | **4208×3120** (el de Android) | patrón / normal | solo lectura |
| X ×3 | 4208×3120 | patrón | `0x4800` = 0x44 / 0x60 / 0x24 (base 0x64) — **especulativas**: no tengo datasheet del bit-map de 0x4800; sirven para ver si algún bit del control MIPI cambia SOT/ECC, no se interpretan sin más |
Diferencia clave de F: 16,4 MB por frame a 10 bpp empaquetado; el mapeo SMMU de 0046 ya cubrió 2104×1560 (4,1 MB); si aparece un fault de SMMU en F es dato, no fallo del ciclo (el script cuenta `Unhandled fault`).

## Criterios (pre-registrados)
- **PASS (hito 2)**: `bytes > 0` o `LONG/SHORT > 0` en cualquier stream. Anotar modo y variante.
- **Lectura del log `uke-sens`**: (a) registros del modo (`0x0305`, `0x0324–0x0327`, `0x4837`) = los de la tabla escrita ⇒ el sensor acepta la configuración; si leen distinto o `0xffff` ⇒ escritura/I2C o reset del sensor mal (nuevo foco); (b) `0x0100` ≠ 1 a +400 ms ⇒ el sensor se paró solo; (c) diferencias M↔F en SOT/ECC.
- **Refutación de H-SENSMODE**: mismos registros correctos y mismo patrón EOT/SOT sin paquetes en M, F y X ⇒ el sensor emite pero no es decodificado, o emite algo que no es CSI-2 de tramas; siguiente (ciclo 9, otra familia): lado CSID/RDI (formato/VC/DT: `RDIn_CFG` con DT 0x2b=RAW10, vc 0) y cambiar a CSID/VFE alternativos (csid1/vfe1) para descartar un bloque concreto; en paralelo, extraer la lib de sensor de Android (`/vendor/lib64/camera/*ov13b10*`, solo lectura con `adb`, tablet en Android — requiere orden del dueño) para tener las tablas OFILM reales.
- **Abortar**: Oops, batería < 30 %, `dmesg -w` sin crecer.
- Honestidad: techo de 3 ciclos por familia ⇒ 8 abre una familia nueva (sensor); si hay PASS parcial no se concluye causa raíz sin repetir.
