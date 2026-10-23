# Cierre del ciclo de 22-oct-2026 (tablet reiniciada con las correcciones)

## Verificado tras el reinicio (00:00 CEST, ouke5, evidencia: ssh solo lectura)
- 8 .ko instalados == `out-ouke5` (fs19xx 2bafe13f, e7i2c 9004ad56, e3 4cb583d3, e5 a9e4b7b0, e8b 2f8e8fb9, e9a 85516d3a, snd-q6apm be7eeecb con parche 0009, lpass-dais 80e6045c).
- `uke-audio` y `uke-audio-amps` active, VERDE con e9a, `/run/uke-audio-apm-ok`, bootguard `audio` fallos=0, sin `e9a-hang`.
- `uke_fs_volmax` por defecto 224; escribir 300 deja 243 (tope duro). `uke-mic` ("Micro interno (UKE)") creado solo por PipeWire: condicion de carrera del micro arreglada.
- Sin oops nuevos; los `Call trace` son los conocidos (pmic_arb a 0,17 s, WARN gpiod en wcd939x_probe). Unico unit fallido: `shadow.service` (ajeno).
- Recovery posterior: no vino de este reinicio sino del slot a con los 7 reintentos agotados (Linux no lo marcaba correcto); ya corregido con `uke-boot-ok.service` (commit 5e79ffd de la sesion principal).

## M7: chasquido de arranque de la captura (log `build/logs/audio/e25-20261022-mic-click.log`, silencio en la sala)
- Es **intermitente**: base -22,5 dBFS (delta 20,9 dB sobre el suelo, ~50 ms) en la 1.ª captura, pero 6,0 y 5,4 dB en la 2.ª y 3.ª; en «seguidas» a 0,2 s no depende de la captura en frio (2.ª captura con 22,8 y 26,2 dB).
- Ninguna variante lo elimina: TX0 MODE ADC_LP lo empeora (28,2 dB); ADC_HIFI **satura** (-1 dBFS, no usar); ADC1 Volume 4 lo baja algo (9,8 dB) a costa de ganancia; ADC1 Volume 14 y TX_DEC0 Volume 84 no lo quitan (el delta se mantiene, solo baja todo el nivel). Duracion ~50 ms en todos los casos.
- Conclusion (hipotesis, sin causa raiz): transitorio del ADC/bias al abrir el flujo, no ligado a la ganancia. Mitigacion practica pendiente: descartar los primeros ~100 ms en el consumidor (filtro/recorte en PipeWire o en la app), o mantener la captura abierta. No se toco el driver.

## Mitigacion del chasquido preparada en el PC (sin tocar la tablet; HIPOTESIS por validar)
- `build/rootfs/deploy/audio/pipewire/mic-abierta.sh` genera de `51-uke-mic.conf` la variante «micro siempre abierta» (`session.suspend-timeout-seconds=0`, `node.pause-on-idle=false`, `node.always-process=true`): el PCM `hw:UKE,2` se abre una vez al arrancar PipeWire y no al abrir cada app, que es cuando ocurre el chasquido (M7). Opciones `--render|--check|--go|--revert` (`--go` guarda la base en `/root/uke-mic/51-uke-mic.conf.base`; solo ficheros, aplica al reiniciar PipeWire del usuario).
- Prueba de PC `mic-abierta-test.sh` (PipeWire+WirePlumber privados con fuente nula): base queda `suspended`, variante `running` (sin `always-process` la variante nacia `suspended`: no vale). OK.
- Lo que NO se ha probado: que el chasquido desaparezca en la tablet (el click puede ocurrir tambien al arrancar el flujo en el ADC aunque el PCM siga abierto) ni el coste de bateria (ADC/bias siempre encendidos). Prueba en tablet: `--go`, reiniciar PipeWire, abrir 5 capturas con `uke-mic-click.sh`-like y comparar con base; revertir si no mejora. Alternativa si falla: recorte de ~100 ms en el consumidor.

## Prueba en la tablet de la variante «micro siempre abierta» (22-oct, silencio confirmado por el dueño; log `build/logs/audio/e26-20261022-mic-abierta.log`)
- `mic-abierta.sh --go` + reinicio de pipewire/pipewire-pulse/wireplumber del usuario (sin reiniciar la tablet): `Micro interno (UKE)` sigue creado, `/proc/asound/card0/pcm2c/sub0/status` = RUNNING con PipeWire como dueño (el PCM queda abierto sin clientes).
- 5 capturas de 2,5 s con `pw-record --target uke-mic` (abren un cliente, no el PCM): delta primeros 0,5 s − suelo = 0,5 / −1,3 / **8,4** / 1,2 / 1,5 dB, todas «estable a los 0 ms» (antes, abriendo el PCM: 5-28 dB, ~50 ms). El 8,4 de la #3 queda sin explicar (ruido de sala puntual, sin repetir). Suelo −50 dBFS. Confirma que el chasquido es del abrir/arrancar el PCM, no del cliente. oops=0.
- Estado: **variante dejada instalada** (`/etc/pipewire/pipewire.conf.d/51-uke-mic.conf`; base en `/root/uke-mic/51-uke-mic.conf.base`; revertir: `mic-abierta.sh --revert` + reiniciar PipeWire del usuario). PENDIENTE: coste de bateria (ADC/bias siempre encendidos; lo medira la sesion optimizacion), comportamiento con pantalla apagada/tras suspension, y que persista tras reinicio (la conf esta en /etc: debe).
