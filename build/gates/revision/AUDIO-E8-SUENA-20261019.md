# AUDIO E8 — los altavoces SUENAN con el PLL corregido (19-oct-2026)

**Resultado:** el dueño confirma que OYE el tono 2 (1 kHz, −24 dBFS, 2 s, `uke_fs_vol=0xE0`, escena 0) por los altavoces internos.
El tono 1 (−30 dBFS, mismo volumen) no se oyó: el umbral audible a 20-30 cm está entre −30 y −24 dBFS con vol 0xE0.

**Causa raíz del silencio previo (medida con la traza I2C de Android, ver `AUDIO-ANDROID-REFERENCIA-RESULTADO-20261019.md`):**
la tabla PLL del driver se leyó con desplazamiento de palabras ([0..2] en vez de [2..4] de la entrada de 12 B). Para BCLK 6,144 MHz
Android escribe `A1=0x0260, A2=0x0540, A3=0x0018`; el driver corregido hace lo mismo. Solo esa fila está verificada contra Android.

**Prueba:** `uke_fs19xx.ko` sha `09b2eb74b6d32802…`, overlays e7i2c + e3 (+LPI) + e8b, topología original `UKE-tplg.bin`,
`aplay -D hw:UKE,0` con mezclador `PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1`; amps habilitados rc 0, parados limpio, sin oops, vigía sin alarma
(salvo `wlan0=down`, preexistente). Captura: `build/logs/audio/e12-20261019-dmesg.log`.

**No hecho aún (pendiente de autorización del dueño):** persistencia al arranque. Hoy `uke-audio.service` solo levanta e2d (APM/PRM);
faltan e7i2c, e3+LPI, `uke_fs19xx`, e8b, mezclador y política de volumen/`uke_fs_play`. Tras el reinicio de la tablet (sesión BT, 10:16) el estado de prueba se perdió.
