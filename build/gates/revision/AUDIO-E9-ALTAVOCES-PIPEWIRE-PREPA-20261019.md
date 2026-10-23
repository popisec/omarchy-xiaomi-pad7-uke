# AUDIO E9 — altavoces como sumidero de PipeWire (YouTube, etc.): preparación y riesgos (19-oct-2026)

Preparado SOLO en el PC. La tablet no se ha tocado (un `--check` de lectura: el fichero no está instalado; tarjeta `UKE` presente).

## Estado previo (medido en la tablet, 19-oct 10:32)
PipeWire/WirePlumber 1.6.9 de la sesión `omarchy` activos; sumideros: «Uke (sin audio físico)» (nulo) y «Nothing Headphone (a)» (BT, predeterminado, prioridad ~1010).
«Built-in Audio» [alsa] existe como dispositivo pero NO crea sumidero (sin perfil/UCM para la tarjeta UKE). Por eso hoy YouTube no sale por los altavoces.

## Qué se añade (`build/rootfs/deploy/audio/pipewire/`)
- `51-uke-speakers.conf`: nodo ALSA `uke-alsa-sink` (`hw:UKE,0`, S16LE 48 kHz estéreo, sin mmap como `aplay`, period 1024, suspensión a los 5 s ⇒ el driver para los amps al soltar el PCM, prioridad 10) + `filter-chain` «Altavoces de la tablet (UKE)» (`uke-speakers`, prioridad 1000): ganancia fija ×0,25 (−12 dB) y limitador duro ±0,3 por canal.
- `test-speakers-private.sh`: PipeWire+WirePlumber privados en el PC (el ALSA se sustituye por un sumidero nulo). **Medido: nodo `Audio/Sink` prioridad 1000 [FL FR]; seno de escala completa a vol 1.0 → pico 0,250; con vol 3.0 → pico 0,300 (limitador)**. Resultado OK.
- `deploy-speakers.sh`: `--go` copia el fichero a `/etc/pipewire/pipewire.conf.d/`; `--restart` reinicia pipewire de la sesión; `--revert`; sin `--go` solo prueba en el PC.

## Riesgos
- **Sin FSADSP** (excursión/térmica de Android): las únicas protecciones son `uke_fs_volmax=0xE0` y este limitador (pico ≤ 0,3 ≈ −10,5 dBFS). Medido a oído solo −24 dBFS con 0xE0; a −12 dBFS el nivel es 4× en amplitud. Subir `Mult`/`Max` solo de uno en uno y con medida térmica.
- **Música continua** pone el PCM abierto mucho tiempo (calor): primera prueba con ratos cortos; vigía activo.
- **PipeWire usa PCM sin pasar por `aplay`**: se ha forzado S16/48 k/estéreo/sin mmap, pero el comportamiento del q6apm-dai con el patrón de buffers de PipeWire (xruns, pausa/reanudación) NO está verificado. Un fallo de `audio_process` del ADSP es fatal (recovery desactivado) ⇒ reinicio. Por eso la primera prueba es con vigía, doble captura y un cliente de prueba corto antes de YouTube.
- Elegir `uke-alsa-sink` a mano evita el limitador (se llama «crudo, sin limitador», prioridad 10; no se ofrece por defecto).
- Reiniciar PipeWire corta un instante el audio por BT en uso (la sesión BT usa la tablet).
- Si el Bluetooth está conectado, seguirá siendo el sumidero predeterminado (prioridad mayor): para oír los altavoces hay que desconectarlo o elegir «Altavoces de la tablet (UKE)» con `wpctl set-default`.

## Procedimiento propuesto (cada paso con autorización)
1. `deploy-speakers.sh --go` (solo fichero). 2. `--restart` + `wpctl status` (¿aparece el sumidero?). 3. Con vigía y doble captura: `pw-play` de `uke-1k-m24.wav` a `uke-speakers` (con el dueño escuchando). 4. Música/YouTube un rato corto, subiendo el volumen por escalones.
Reversa: `deploy-speakers.sh --go --revert --restart`.

## Resultado en la tablet (19-oct-2026 10:37)
`deploy-speakers.sh --go --restart`: `uke-speakers` (Audio/Sink, WirePlumber lo lista en «Filters») enlazado a `uke-alsa-sink`; el BT sigue de predeterminado.
`pw-play --target uke-speakers` de un seno 1 kHz −6 dBFS (−18 dBFS tras la cadena), 2 s, vol 0xE0: **el dueño lo oye**. Amps habilitados ~7 s (2 s + 5 s de suspensión) y parados limpio; vigía sin oops. Capturas `build/logs/audio/e14-20261019-*`.
Nota: `omarchy` no puede leer `/root`; los WAV de prueba van a `/tmp`. Pendiente: hacer `uke-speakers` el predeterminado (con el BT conectado gana el BT) y probar música/YouTube en ratos cortos.

## Defecto encontrado y corregido (19-oct, primer arranque en ouke5)
Con `51-uke-speakers.conf` instalado y la tarjeta UKE AUSENTE al login (el audio no cargó), `pipewire` moría («can't create object from factory adapter», `hw:UKE,0` inexistente) y entraba en bucle de reinicios hasta `start-limit-hit`: **sin PipeWire ni BT/audio de escritorio**. Reproducido en el PC con la conf antigua (muere) y corregido con `flags = [ nofail ]` en el objeto ALSA (ahora sigue vivo; nuevo caso 4 en `test-speakers-private.sh`). `deploy-speakers.sh --restart` hace además `reset-failed` de las unidades de usuario. Si la tarjeta aparece DESPUÉS de arrancar PipeWire hay que reiniciar pipewire de la sesión.
Desplegado en la tablet y PipeWire recuperado (23:21, ouke5).
