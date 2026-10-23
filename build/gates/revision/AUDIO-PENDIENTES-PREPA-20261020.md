# AUDIO — pendientes: pasos 3, 4 y 5 del plan (20-oct-2026, solo PC; tablet sin tocar)

## Hecho en el PC
- **Tarjeta tardía** (`boot/root/usr/local/sbin/uke-audio-amps-up.sh`, `pw_refresh`): tras el VERDE de la etapa 2, si PipeWire de la sesión ya corría y NO existe el nodo `uke-alsa-sink` (conf con `nofail`), reinicia pipewire de ese usuario (con `reset-failed`). Al arrancar la tablet (sin PipeWire todavía) no hace nada; `UKE_AUDIO_PW_REFRESH=0` lo desactiva. Harness: **27 ok, 0 fallos** (cuatro casos nuevos: sin nodo, con nodo, sin PipeWire, refresh=0).
- **`fuse` al arrancar**: `boot/root/etc/modules-load.d/uke-fuse.conf` (`fuse`; `CONFIG_FUSE_FS=m`, el módulo existe en ouke4 y ouke5). `deploy-amps.sh --service` lo instala (y `--revert` lo borra).
- **`docs/historia/ESTADO-VIVO.md`**: bullet de audio al principio (par de kernel ouke5, hecho, próximos 3 pasos).

## Paso 4 (volumen): ya resuelto
El volumen de sesión de WirePlumber persiste entre arranques (el 0,30 sobrevivió a un reinicio) y ahora está en 1,0; el mando `FS19XX Volume` y `uke_fs_vol` están recortados por `uke_fs_volmax` en el driver (`uke_fs19xx.c:327,504,651`). Pendiente solo comprobar que el 1,0 persiste tras el próximo reinicio.

## Pendiente de autorización (instalar en la tablet)
`boot/deploy-amps.sh --go --service` (script con el gancho + `uke-fuse.conf`; solo ficheros, sin reiniciar ni cargar), con `KREL` por defecto ouke4 o `KREL=…ouke5` según el kernel en marcha. Pasos 1 (térmica) y 2 (canales) siguen necesitando tu presencia.
