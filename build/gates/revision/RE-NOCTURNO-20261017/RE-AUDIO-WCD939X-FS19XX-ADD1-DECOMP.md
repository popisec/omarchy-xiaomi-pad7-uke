# ADD1 — Ghidra `fs19xx_dlkm.ko` (127/127 funciones, uke-night-audio, 2026-10-17)

Adenda a `RE-AUDIO-WCD939X-FS19XX.md` (no lo modifica). Fuente: `artifacts/audio/decomp-fs19xx/*.c`.
Todo HECHO (decompilado) salvo marcas. Direcciones = offsets del .ko.

## fsm_i2c_probe (0x6f6c, 1692 B) — secuencia exacta
1. `I2C_FUNC_I2C` check → `check_smartpa_type("fs19xx")` (si otro smartpa ya fijado, probe
   se salta: `devm_kmalloc` 0x308, mutex `i2c_lock`).
2. `fsm_parse_dts` (inlined): lee **`reset-gpio`** (→ request `FS19XX_RST_%02X`, fatal si
   falla), **`interrupts`** (→ request `FS19XX_IRQ`), **`fsm,re25-dft`** (default 0),
   **`spksw-gpio`** (opcional, `FS19XX_SPKSW`).
3. `fsm_vddd_on` (regulator `fsm_vddd`) → reset GPIO: **low, 10 ms, high, 1 ms**.
4. `fsm_probe(dev, i2c_addr)`; si falla → evento Xiaomi `PA i2c exception` (mievent) + vddd_off.
5. Workqueues `fs19xx` (`fsm_work_monitor`, `fsm_work_interrupt`), IRQ: `gpiod_to_irq` +
   `devm_request_threaded_irq(..., NULL, fsm_irq_hander, 0x2002, "fs19xx", ...)` + `disable_irq`
   inicial. `0x2002` = ONESHOT + flanco (primaria NULL).
6. `set_smartpa_type("fs19xx", 7)` → `fsm_codec_register` (solo primer amp: `misc_register`
   + `snd_soc_register_component`).

## Hallazgo: el DT Android NO alimenta la vía IRQ
El código pide la prop **`interrupts`**, pero el DT trae **`irq-gpio`** → `of_get_named_gpio_flags`
falla → IRQ queda inválido y `fsm_request_irq` lo omite (rama "cannot find").
Consecuencia: en uke los 4 amps trabajan **sin IRQ** (solo monitor por workqueue).
Un port mainline puede cablear `interrupts = <&tlmm … IRQ_TYPE_…>` correctamente o replicar
el polling. **HECHO** (código); comportamiento en boot NO VERIFICADO (sin consola).

## fsm_probe (0x316c) — detección
- Lee **registro 0x03** como DEVID; flag `(devid&0xfff0)==0x5b0` (bit2, marca familia 0x5B0).
- `fsm_detect_device(dev, devid>>8)`: byte alto **0x05** / **0x06,0x0B** (bit3) /
  **0x17,0x29** → `fs19xx_ops` (bit5). Otro valor → `-EINVAL` ("not found dev_list").
  FS16xx de uke cae en la rama fs19xx (INFERIDO: 0x17/0x29; lectura del reg 0x03 en
  tablet NO VERIFICADA — se puede leer con `i2cdump 4 0x34` como root, solo lectura).

## fs19xx_reg_init (0x390c) — reset SW + tablas desde firmware
- Danza reset: `reg 0x10 ← 2`, leer, **15 ms**, `reg 0x10 ← 1`, poll **`reg 0x0E`** hasta
  `3`/`0x300` (5 intentos; si no → `fs19xx_i2c_reset` + `-0x6E`).
- `reg 0x14 ← re25<<1` (re25 de `fsm,re25-dft`, 0 en uke).
- `fsm_write_reg_tbl(dev, 0xFFFF)` (tabla común) + `fsm_write_reg_tbl(dev, preset escena)`.
  **Los valores de registros viven en el `.fsm`** (`fsm_parse_preset`), no hardcodeados:
  portar exige el parser de preset o extraer las tablas del blob (4828 B ya en artefactos).

## fs19xx_start_up — rates
`fs19xx_get_srate_bits`: 8000→1, 16000→3, 32000→7, 44100→8, 48000→9, 96000+ (rama aparte).
Música Android usa 48 kHz/24-bit packed (audio_policy). Formatos DAI exactos: NO VERIFICADOS
(struct en .rodata sin resolver en decomp).

## Qué falta (para quien continúe)
`fsm_write_reg_tbl`/`fsm_parse_preset` (formato del blob), `fsm_set_scene` (escenas 0/1/7/9/11/13/15),
`fsm_config_vol`, `fsm_codec_register` (dai_driver completo), `fs19xx_pre_calib` (re25/calib).
