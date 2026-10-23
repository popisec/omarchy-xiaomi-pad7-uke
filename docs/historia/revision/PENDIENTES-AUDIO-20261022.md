# Pendientes de audio — cierre de sesión, 22-oct-2026

## Estado (verificado en la tablet el 22-oct, ouke5 `7.2.9-senemos.1.4054.3`)
- Tarjeta combinada **e9a** (4 FS19xx + micro WCD9395) persistente al arrancar, con caída automática a e8b (solo altavoces); `uke-audio` y `uke-audio-amps` en VERDE tras reinicio en frío. Commits: 449e543, f5b24e4, 9fef6d5, 7de8f91 (y f513ffd/cc03982 antes).
- Driver con tope duro de volumen 243 (`uke_fs_volmax` por defecto 224), parada siempre atendida, parche 0009 (UAF de q6apm). 8 .ko instalados == `build/rootfs/deploy/audio/out-ouke5/`.
- Micro interno: PipeWire `uke-mic` (hw:UKE,2, 2 ch S16 48k) creado solo. **Variante «siempre abierta» INSTALADA** (`/etc/pipewire/pipewire.conf.d/51-uke-mic.conf`, base en `/root/uke-mic/51-uke-mic.conf.base`): chasquido 5-28 dB → ~1 dB (una de 5 capturas dio 8,4). Informe: `docs/historia/revision/AUDIO-REVISION-CRITICA-20261022-CIERRE.md`; logs `build/logs/audio/e25` (chasquido) y `e26` (variante).
- Units sin comentarios al final de línea (systemd 262): comprobado en el repo.

## Pendiente, con primer paso
1. **Coste de batería de la variante abierta** (ADC/bias siempre encendidos). Primer paso: la sesión optimización/batería mide con y sin (`mic-abierta.sh --go|--revert` + reiniciar PipeWire del usuario). Si es alto → revertir y hacer recorte de ~100 ms en el consumidor.
2. **Micro con pantalla apagada / tras suspensión** (BOB asumido encendido): sin medir. Primer paso: capturar 2 s con la pantalla apagada y tras `systemctl suspend`.
3. **Persistencia de la variante tras reinicio** y tras el `-Syu` (posible `.pacnew` de PipeWire): comprobar `grep pause-on-idle /etc/pipewire/pipewire.conf.d/51-uke-mic.conf` y que existe `uke-mic` tras el próximo arranque.
4. Pruebas de audio abiertas: A3 (orden amp/BCLK, `mute_unmute_on_trigger`), A4, A5 (nodo crudo `uke-alsa-sink` seleccionable), B2 (protección térmica: no hay FSADSP; vigilar `battery/temp` y bajar de escalón).
5. **Mapa físico de los micros** (`mic/auto/`, usa los altavoces como fuente puntual): necesita orden del dueño; luego calibración acústica con el Nothing Phone (2a) a distancia fija por ADB (`phone-sensor.sh` sin probar).
6. Causa raíz del chasquido (sigue sin conocerse); WARN `gpiod_set_value` en `wcd939x_probe` (parche opcional gpiod_cansleep); esclavo SoundWire TX en `Alert` (estado válido).
7. Limpieza del repo (R4): logs de dmesg duplicados, MAC/serial en logs, bullets obsoletos de `docs/historia/ESTADO-VIVO.md`, `e23` sin trackear.

## Decisiones abiertas (del dueño)
- ¿Quitar del repo los ficheros de fabricante aún versionados (dos `fs19xx.fsm`, cadenas de libfsalgocal, XML OEM)? Regla del proyecto: nada de binarios del fabricante.
- ¿Mantener la variante abierta si cuesta batería, o preferir recorte en software?
- Escalón de volumen 4 de `uke-nivel.sh` (requiere `--yes`, vuelve solo a escalón 2 a los 60 s): sigue pausado por petición del dueño.

## Dónde está todo
- Código/despliegue: `build/rootfs/deploy/audio/` (`fs19xx/`, `boot/`, `mic/`, `pipewire/`, `dts/`, `module/`, `kernel/`, `out-ouke5/`).
- Informes: `build/gates/revision/AUDIO-*`, `MICROFONO-M1/M3-*`, `docs/historia/revision/AUDIO-REVISION-CRITICA-20261021.md` y `-20261022-CIERRE.md`; bitácora `NOTAS-OMARCHY.md`; estado `docs/historia/ESTADO-VIVO.md` (sus bullets de audio están desfasados).
- Datos de Android: `build/android/audio-fsadsp-20261020/`. Privado fuera del repo: `/var/tmp/uke-android-bin/`, `/var/tmp/uke-re/`, `/var/tmp/uke-acdb/`, backup de userdata `/var/tmp/uke-userdata-backup/userdata-20261020-213014-fsck.img` (sha 508a9a19…).
- Reglas al tocar la tablet: pedir turno a la sesión principal, cargador, vigía, un solo lector de ACM, `sync` antes de reiniciar, nada de `pacman -S` suelto.
