# RE-AUDIO: WCD939x + FourSemi FS16xx + machine (uke, sesión nocturna 2026-10-17)

Lectura sola. Sin builds, sin flash, sin escritura en tablet. Artefactos nuevos en
`build/gates/revision/RE-NOCTURNO-20261017/artifacts/audio/`:
`tinymix-uke-20261017.txt` (310 líneas, `adb … 'su -c tinymix'`),
`fs19xx.fsm` (copia de /odm/firmware), `dt-fs19xx-props.txt`,
`dts-fs19xx-draft.dtsi` (BORRADOR), `syms-evidence.txt` (modinfo + relocs).
Ghidra de `fs19xx_dlkm.ko` quedó encolado tras otros frentes (flock) → registros/valores
de init quedan PENDIENTES de `decomp-fs19xx`; aquí solo arquitectura verificada por
`strings`/`llvm-readelf`/`llvm-objdump` + DT + tinymix en vivo.

## 1. FS19xx/FS16xx — amplis de altavoces (HECHO salvo marcas)

- Driver vendor `fs19xx_dlkm.ko` v4.0.7, FourSemi, GPL, `depends=miev,machine_dlkm`
  (`.modinfo`, ver `syms-evidence.txt`). **HECHO.**
- Único `compatible`: **`foursemi,fs16xx`** (of_match + `alias=i2c:fs16xx`). El nombre del
  fichero ("fs19xx") ≠ compatible. Ojo: el chip real es FS16xx aunque todo (nodo DT,
  firmware, kcontrols) se llame fs19xx. **HECHO** (rodata `1cb0: fs16xx`, DT x4).
- Bus y direcciones: **i2c-4** (`qcom,i2c-geni` @0x88c000), 4 amps en **0x34, 0x35, 0x36, 0x37**
  (reg u32 = dirección 7 bit). Nodos `fs19xx_smartpa@{34..37}`, todos `status ok`. **HECHO.**
- GPIOs (TLMM `pinctrl@f000000`, phandle 0x16b confirmado; celdas `<phandle gpio flags>`):
  irq 47/69/31/129 (flags 0x2008), reset 30/149/124/123 (flags 0x0). Detalle en
  `dt-fs19xx-props.txt`. Pinctrl `default/sleep` por amp (8 estados
  `fs19xx_irq_{active,sleep}_*`). **HECHO** números; **INFERIDO** qué esquina es cada amp
  (nombres bottom/top-left/right; correlación phandle↔nombre NO VERIFICADA).
- Props DT que parsea el driver (por strings+relocs `of_get_named_gpio_flags`,
  `of_property_read_variable_u32_array`): `reset-gpio`, `fsm,rst-gpio`, `spksw-gpio`,
  `I2cAddress`, `fsm,re25-dft`, más `FS19XX_IRQ` / `FS19XX_RST_%02X` / `FS19XX_SPKSW`.
  En el DT Android **solo existen** compatible/reg/irq-gpio/reset-gpio/pinctrl — el resto
  usa defaults (p.ej. "fsm,rst-gpio cannot find" es ruta tolerada). **HECHO.**
- Secuencia probe (por símbolos+relocs, sin decompilar): `fsm_i2c_probe` → check
  `I2C_FUNC_I2C` → `of_get_named_gpio_flags` → `devm_gpio_request_one` + `gpiod_to_irq` +
  `devm_request_threaded_irq` → `regulator_get("fsm_vddd")`+`set_voltage/enable` →
  `fsm_detect_device` (lee DEVID, "type(%04X) not matched version(%04X)" si falla) →
  `fsm_init_dev_list` (ndev:4, cadena compartida) → `fsm_firmware_init`
  (`request_firmware_nowait`, fichero **`fs16xx.fsm`** por defecto; en uke el que carga es
  `/odm/firmware/fs19xx.fsm` vía `fsm_set_fw_name`) → `fsm_codec_probe`
  (`snd_soc_register_component`, `set_smartpa_type("fs19xx")` hacia machine) →
  "i2c probe completed". **HECHO** arquitectura; valores de registros NO VERIFICADOS.
- DAI: **`fs16xx-aif`**, streams "AIF Playback"/"AIF Capture" (`snd_pcm_hw_constraint_list`
  presente; formatos exactos pendientes de decomp). **HECHO** nombres.
- Kcontrols ALSA (driver + tinymix en vivo, coinciden 1:1): `FSM_Scene`, `FSM_Volume`,
  `FSM_Stop`, `FSM_AMP_ON`, `FSM_Rotation`, `FSM_Ultrasound_Enable`, `FSM_SW_GPIO`.
  Estado idle real: Scene 0, Volume 255, Stop On, AMP_ON Off. **HECHO.**
- IRQ/fault: threaded IRQ por amp (`fsm_irq_hander`→`fsm_work_interrupt`), monitor
  periódico (`fsm_work_monitor`, fault OC/UV/OV/OT/DC/SR/OTW por strings de fs210x-hermano;
  en vendor: `vbat/tempr`, `fsm_get_amb_tempr`, calibración `re25`). **HECHO** mecanismo.
- Firmware `fs19xx.fsm` 4828 B: cabecera ASCII **`00 01 "onlybsg" 00 "1"`** + preset binario
  (proyecto 1, fecha 20240814 según frente audio; checksum OK). Sin magic ELF/estándar:
  formato propietario FourSemi (escenas+regs+ecualización). **HECHO** bytes; semántica
  parcial INFERIDA del driver (`fsm_parse_preset`, scenes, `reg_scene`).

## 2. Machine driver (HECHO)

- `machine_dlkm.ko`: `ALSA SoC msm`, alias `platform:pineapple-asoc-snd` +
  of `qcom,pineapple-asoc-snd[/-stub]`; tarjeta **`cliffs-mtp-snd-card`**
  (truncada a `cliffs-mtp-snd-`/"cliffsmtpsndcar"). 53 links (proc-asound). **HECHO.**
- Handshake smartpa con el amp: importa `set_smartpa_type`/`check_smartpa_type`; tipos
  conocidos `aw882xx/aw884xx/fs19xx/sia91xx/tfa98xx`; en uke **`smartpa_type="fs19xx"`**,
  `smartpa_num` INFERIDO 4. `smartpa_dai_link_select` elige para FS19XX los links
  **TDM-LPAIF_VA-RX-PRIMARY + -VIRT-2 (playback 42/43) y TDM-LPAIF_VA-TX-PRIMARY
  (capture 44)** con codec **`fs16xx.4-0034`** (solo el primer amp) dai **`fs16xx-aif`**;
  el driver amp replica a los 4 en modo sync. **HECHO** (strings+proc-asound+dt-sound-nodes §3).
- WSA: `wsa_max_devs=0`, macros WSA y slaves wsa883x/884x disabled → sin amplis WSA. **HECHO.**

## 3. WCD939x (HECHO salvo variante exacta)

- Vendor `wcd939x_dlkm.ko` (+`_slave`, `wcd_core`, `wcd9xxx`), codec atado a SoundWire:
  `wcd939x-rx-slave` → SDW `e01170224`, `wcd939x-tx-slave` → `e01170223`; nodo
  `wcd939x-codec` compat **`qcom,wcd939x-codec`** + `qcom,split-codec`; `wcd939x-i2c@e`
  es el switch USB-C (usbss), NO el audio. Reset por `qcom,wcd-rst-gpio-node`;
  supplies `cdc-vdd-{rx,tx,mic-bias,buck,px}` (rx/tx 1.8V, mic-bias ~3.296V…), micbias1-4
  a 0xABE; mapas `rx_swr_ch_map/tx_swr_ch_map`. **HECHO** (DT §2 + strings).
- Variante: todo apunta a **WCD9395** (ficheros `*_wcd9395.xml`, strings vendor
  `WCD939X_1_0`/`WCD939X_1_1`) pero el ID leído del chip NO se pudo verificar
  (dmesg rotado por spam wifi, uptime 3596s; sin re-arranque no hay línea de versión).
  **INFERIDO 9395, NO VERIFICADO a nivel registro.**
- Mainline (`k52-L16-tree/sound/soc/codecs/`): `wcd939x.c` + `wcd939x-sdw.c` existen y
  cubren **ambas variantes** (`CHIPID_WCD9390=0x0`/`WCD9395=0x5`, DT
  `qcom,wcd9390-codec`/`qcom,wcd9395-codec`, supplies `vdd-{rxtx,io,buck,mic-bias,px}`,
  `reset_gpio`, MBHC, slaves SDW). Diferencias vendor→mainline: nombre de supplies
  (`cdc-vdd-*` vs `vdd-*`), compat genérico `qcom,wcd939x-codec` (mainline exige
  9390/9395 explícito), y extras Xiaomi (usbss-hs, mievent, `wcd-disable-legacy-surge`).
  **HECHO** (grep, líneas citadas). Codec reutilizable con ajuste de DT.

## 4. TPLG / firmware de audio (HECHO)

- `find /vendor /odm -iname '*tplg*'` → **vacío**: no hay `.tplg` (ruta AudioReach/APM:
  el grafo va dentro de `adsp.b00-bNN`, sin firmware separado). **HECHO.**
- `/vendor/etc/audio/`: `sku_{cliffs,pineapple}[_qssi]` con mixer/resourcemanager/policy
  por SKU (uke usa `sku_cliffs/*wcd9395*`). `/odm/etc/audio`: `.wav` de calibración de
  altavoces (tl/tr/bl/br-spk[_hp], spk_cal_silence, spk_dsm_test…), `misound_*spk*.bin`,
  `mis_*spk*.bin`. Sin `.acdb` visibles. **HECHO.** Dónde debería estar un tplg mainline:
  `/lib/firmware/qcom/cliffs/*` o topo embebida en machine (q6apm + `topology.c` existen
  en árbol). **INFERIDO** (estándar qcom, no medido en uke).

## 5. Mixers de fábrica para música por altavoz (HECHO, lista corta)

Ruta = TDM-VA → amps (NO pasa por WSA: el `path speaker` del mixer base solo toca WSA,
  inerte en uke). Lo que hay que replicar en ALSA/UCM, de
  `odm-mixer_paths_overlay_static.xml` + tinymix idle:
  `FSM_Scene=0` (stereo) / `7,9,11,13` (esquinas tl/tr/bl/br) / `1` (mono-2),
  `FSM_Volume=243` (stereo) / `235` (esquinas), `FSM_Stop=1` en reposo,
  `FSM_Ultrasound_Enable=0`, `FSM_SW_GPIO=0` (1 = handset/ultrasonidos),
  `FSM_AMP_ON`/`FSM_Rotation=0`. Base añade `RX_HPH PCM=1`, ADC/IIR de micrófonos
  para speaker-mic. **HECHO.**

## 6. Gap mainline + orden de trabajo propuesto

1. **NO existe** driver FS16xx/FS19xx en el árbol: `fs210x.c`+`fs-amp-lib.c` solo cubren
   FS2104/FS2105S (`foursemi,fs2105s`, DEVID 0x45/0x20). El fsm-vendor (v4.0.7, escenas,
   presets, sync 4-dev, misc ioctl, mievent) no es reutilizable tal cual. Vía barata:
   extender `fs210x.c`/`fs-amp-lib` con DEVID/preset de FS16xx o portar el fsm mínimo
   (probe+regmap+scene/vol via `.fsm`). **HECHO** gap.
2. **NO existe** machine para pineapple+wcd939x+FS: `x1e80100.c` no referencia wcd93xx
   ni smartpa (portátiles WSA). Hay que escribir machine (`pineapple-asoc-snd` con
   3 links TDM-VA + auxiliares wcd939x + q6apm BE). **HECHO** gap.
3. WCD939x SÍ existe en mainline (ver §3) → solo DT+supplies. q6apm/q6prm/audioreach
   existen (`qdsp6/` completo incl. `q6apm-lpass-dais.c`, `topology.c`). **HECHO.**
- Orden (barato primero): **(a)** q6apm contra ADSP (el runfile adsp ya opera; probar
  BE `CODEC_DMA`/VA-TX con tinymix/ucm mínimo y confirmar PCM capture de mics por SWR);
  **(b)** driver amp (I2C probe+DEVID+reset+irq+firmware+`fs16xx-aif`, scenes 0/7/9/11/13);
  **(c)** machine con los 3 links TDM-VA + UCM que replique §5; **(d)** WCD939x RX/headset
  (HPH/USB-C analógico) al final — música por altavoz no lo necesita.
- Dependencia panel: ninguna funcional (solo compartirían ventana de flasheo futura;
  este frente no flashea). Decomp `decomp-fs19xx` pendiente de la cola Ghidra.
