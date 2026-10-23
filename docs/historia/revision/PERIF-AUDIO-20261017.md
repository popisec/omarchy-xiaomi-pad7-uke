# PERIF-AUDIO — uke (Xiaomi Pad 7) — 2026-10-17
Frente AUDIO. Local + adb solo lectura (192.0.2.13:5555, root /debug_ramdisk). DT: /tmp/dtfull/base. Volcado completo: build/android/dt-sound-nodes.txt. Extracciones: build/android/cosecha-20261017/audio/.

## Resumen (≤350 palabras)

**Topología vendor.** Card única `cliffs-mtp-snd-card` (compatible `qcom,pineapple-asoc-snd`, plataforma reportada pineapple) bajo `/soc/spf_core_platform` con LPASS-CDC: macros rx@6AC0000, tx@6AE0000, va@6D44000 (ok) y **wsa@6B00000 DISABLED** — sin WSA amps (wsa883x/884x: 4 nodos todos disabled; dmesg "wsa_max_devs: 0"). **Los 4 altavoces son FourSemi FS16xx** (`foursemi,fs16xx`, fs19xx_smartpa@34-37 en i2c-4/88c000, status ok), audio por TDM del VA macro (TDM-LPAIF_VA-RX-PRIMARY), firmware `fs19xx.fsm` (4828 B, preset "onlybsg"). Codec **wcd9395** (WCD939X_2_0) split por SoundWire: slaves e01170224 (rx-macro) y e01170223 (va/tx); audio analógico USB-C vía wcd-usbss (wcd939x-i2c@e, probe ok). SWR DMICs presentes pero no instanciados en boot (mics = DMIC analógico). Háptico por SWR (swr_haptics@f0170220). Card registrada: card0, 53 dailinks, 112 PCM devices, jacks Headset/Button.

**dmesg vendor.** spf_core probe 2.77 s; clocks audio PRM (va/wsa/rx/tx, 19.2/22.5792 MHz, clk_id 775-792); ADSP arranca 5.7 s (mismo runfile adsp.b00-bNN que ya carga nuestro uke-adsp.service — **no hay fw "adsp_audio" separado: el APM/AudioReach va dentro**); 6.99 s "apm is up" por GPR (spf_core 2:3 responde). Servicios: audio-hal, vendor.audioadsprpcd_audiopd (fastrpc audio PD), c2audio, dolbycodec2.

**Mainline (k52 7.2-rc2).** El stack **audioreach/q6apm SÍ está** (sound/soc/qcom/qdsp6: audioreach, q6apm, q6prm, q6afe/asm, compatibles genéricos `qcom,q6apm`/`qcom,q6prm`) + drivers/soundwire/qcom.c (v1.5.1-v3.1.0). **wcd939x existe** (wcd939x.c + wcd939x-sdw.c, `qcom,wcd9390/9395-codec`; entrada SDW 0x0217/0x10e = 9390; verificar part-id 9395). Macros lpass-rx/tx/va/wsa hasta sm8550 — sin sm8650/palawan (añadir compatibles). NO existe en mainline: spf_core_platform, driver fs16xx (FourSemi, protocolo I2C propietario), wcd-usbss, swr haptics.

**Veredicto.** El ADSP ya arrancado expone GPR/APM que mainline-q6apm sabe hablar (misma generación pineapple; skew de versión por verificar en runtime). Auriculares/línea USB-C + mics: port moderado = machine driver (~250 líneas, plantilla x1e80100.c) + DT nuevo + compatibles de macros. **Altavoces: el bloque duro** — sin driver FS16xx mainline; requiere reingeniería del fs19xx_dlkm.ko vendor (I2C+fw extraído ya). Mínimo "algo de sonido" hoy: USB-C digital (snd-usb-audio, cero port). Palabra clave futuro: `port-audio-wcd9395`, `port-audio-fs16xx`.

## Extracciones (build/android/cosecha-20261017/audio/)
fs19xx.fsm · odm-mixer_paths_cliffs_mtp.xml · odm-resourcemanager_cliffs_mtp.xml · odm-mixer_paths_overlay_static.xml (ctl FSM_*) · odm-mixer_paths_overlay_dynamic.xml · mixer_paths_cliffs_mtp_wcd9395.xml · resourcemanager_cliffs_mtp_wcd9395.xml · audio_policy_configuration.xml · android.hardware.audio.service_64.rc · vendor.qti.audio-adsprpc-service.rc · USUARIO@example.invalid · proc-asound.txt (card0 completo).

## Pendientes
- Verificar part-id SDW del 9395 (driver: SDW_SLAVE_ENTRY 0x0217/0x10e es 9390).
- Probar q6apm contra nuestro ADSP ya arrancado (probe audioreach: coste bajo, decide la mitad barata del port).
- Static analysis de fs19xx_dlkm.ko (protocolo I2C FSM) para el driver de altavoces.
