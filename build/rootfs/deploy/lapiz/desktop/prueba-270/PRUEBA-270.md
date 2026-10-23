# Prueba de 270 grados del lapiz (21-oct-2026) — preparada, NO ejecutada

Contexto: 0, 90 y 180 grados OK con dedo y lapiz; 270 pendiente. Revision por codigo (Hyprland v0.56.2, libinput 1.32.0) y simulacion: `python3 -I test_270.py` (6 OK).

## Lo que dice el codigo
- `input:touchdevice:transform` y `input:tablet:transform` usan la MISMA tabla `MATRICES[N]` (InputManager.hpp) via `libinput_device_config_calibration_set_matrix` (InputManager.cpp L1982 y L2027). No hay transform inverso para absolutos.
- libinput solo acepta la matriz en tabletas con `INPUT_PROP_DIRECT` (evdev-tablet.c `tablet_init_calibration`); `uke_pen.py:252` lo activa. Se aplica con `evdev_transform_absolute`, igual que en el tactil.
- Con `output="DSI-1"`, `warpAbsolute` escala el punto ya calibrado sobre `logicalBox()` de DSI-1 (ya girado); el tactil hace `pos * size` del monitor. Equivalentes.
- 270 = transform 3 = `{0,1,0,-1,0,1}`: x'=y, y'=1-x; es la inversa exacta de la de 90 (test). Sin espejo (det +1).
- Con touchmap `0 1 2 3` y sin `penmap`, `uke-pen-sync` da transform 3 al lapiz a 270.

## Guion (en la tablet, como omarchy; o `./prueba-270.sh` por ssh, con `--dry-run` primero)
1. `uke-rotate 270`
2. `uke-pen-sync`
3. `uke-pen-sync --status` (esperado `output` DSI-1, `transform` 3)
4. `hyprctl getoption input:tablet:transform` (int: 3) y `hyprctl getoption input:touchdevice:transform` (int: 3)
5. En rnote, con la tablet en 270, con el lapiz: una linea de la esquina superior izquierda VISIBLE a la inferior derecha VISIBLE, y un cuadrado grande. Repite con el dedo para comparar.

## Como juzgar
- OK: la tinta sale exactamente bajo la punta (igual que el dedo). Linea recta de esquina a esquina, cuadrado cuadrado.
- Falla: la tinta sale en otro sitio. Pon la punta en la esquina superior izquierda de la pantalla (visible) y mira donde aparece la tinta.

## Si 270 sale mal: sintoma -> penmap
Primero comprueba que `--status` da `transform` 3. Si lo da y aun asi falla, el nodo del lapiz no comparte espacio con el dedo en 270 y se compensa con `penmap` (indice = transform del monitor, valor = transform del lapiz; solo se toca el 4.o numero). Pon la punta en la esquina visible SUPERIOR IZQUIERDA y mira donde sale la tinta (comprobar tambien la superior derecha para distinguir giro de espejo):

| tinta (punta en sup-izq / sup-der) | sintoma | 4.o valor de penmap |
|---|---|---|
| sup-der / inf-der | girado 90 horario | **2** (`0 1 2 2`) |
| inf-der / inf-izq | girado 180 (punto simetrico por el centro) | **1** (`0 1 2 1`) |
| inf-izq / sup-izq | girado 90 antihorario | **0** (`0 1 2 0`) |
| sup-izq / inf-izq | espejo diagonal \ (x e y intercambiadas) | **4** |
| inf-izq / inf-der | espejo vertical (arriba <-> abajo) | **5** |
| inf-der / sup-der | espejo diagonal / | **6** |
| sup-der / sup-izq | espejo horizontal (izq <-> der) | **7** |

(Derivada con `M3 * Mr^-1 * M3` sobre las MATRICES de Hyprland; los espejos son involuciones, por eso el valor es el mismo que el del sintoma. Los giros de 90 se invierten: 0<->2.) Referencia de que hace cada transform p a 270 con la punta en las 4 esquinas: `python3 -I test_270.py --tabla`.

Fijar: `echo "0 1 2 N" > ~/.local/state/uke-rotate/penmap && uke-pen-sync && uke-pen-sync --status`. Mas de 3 ciclos sin mejora: anotar hipotesis refutada (regla del proyecto).

## Volver a 0 grados
`uke-rotate 0 && uke-pen-sync && uke-pen-sync --status` (y `rm -f ~/.local/state/uke-rotate/penmap` si se fijo uno de prueba). `prueba-270.sh` lo hace solo al salir (trap).

## Notas
- Nada se ha ejecutado contra la tablet. Estado vivo: `docs/historia/ESTADO-VIVO.md`.
- Posible fallo en `uke-pen-sync` (no editado): si `deg` esta ausente o invalido cae a 0 sin avisar; y `hyprctl eval` con la misma orden identica a la anterior puede no aplicarse (uke-rotate reintenta y verifica; pen-sync no). Si `--status` no muestra transform 3 tras 270, repetir `uke-pen-sync`.
