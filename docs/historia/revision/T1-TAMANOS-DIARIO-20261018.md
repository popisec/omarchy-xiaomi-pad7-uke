# T1 + T6a: tamaños y diario — informe (18-oct-2026)

Paquete, método y mediciones: `build/rootfs/deploy/tablet-t1/README.md`. Aplicado y validado (`configerrors` vacío).
Sin commit; NOTAS/ESTADO-VIVO los integra la sesión gestora.

## Hecho
- Barra 40 px lógicos (sin scale-with-font), fuente base 16, shell reiniciado con `omarchy restart shell`.
- Hyprland: gaps 8/14, borde 4, redimensionar por borde (grab 20 px), swipe táctil de espacios (3 dedos).
- hypridle propio (unit `uke-hypridle.service`): 60 s atenuar al 5 %, 2 min DPMS off, 10 min suspender, sin lock.
- Brillo: confirmado que el comando de Omarchy mueve `uke-backlight` (desde la sesión). Batería: % activado en la barra.

## Hallazgos / avisos
1. El brillo no se puede mover con `sudo -u omarchy brightnessctl` por SSH (falta sesión logind); es normal, no un fallo del slider.
2. `hl.gesture` de 3 dedos vive en looknfeel.lua (no en input.lua, de otra sesión). Si T4 define gestos de 3 dedos, evitar duplicar.
3. En la captura el icono de Wi-Fi de la barra sale tachado; no investigado (fuera de alcance; SSH va por RNDIS). Mirar si el dueño lo ve sin red.
4. Pendiente: probar el ciclo real de idle (dim 60 s → pantalla off 2 min → suspende 10 min) y despertar con el botón; tras el DPMS on el táctil debería recargarse solo.

## Que compruebe el dueño con el dedo
- Barra y textos más grandes; pulsar el reloj, los iconos y los espacios 1-4 sin fallar.
- Arrastrar con 3 dedos horizontal: cambia de espacio.
- Ventanas: borde grueso; arrastrar desde el borde redimensiona.
- Dejarla quieta: a 1 min baja el brillo, a 2 min se apaga, tocar/pulsar la enciende y el táctil responde; a 10 min suspende (botón de encendido despierta).
- Brillo desde el panel/slider; el % de batería junto al icono (arriba a la derecha).
