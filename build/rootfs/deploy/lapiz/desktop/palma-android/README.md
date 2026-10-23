# Rechazo de palma estilo Android para uke-touchd (offline, 21-oct-2026) - NO desplegado

Alternativa EXCLUYENTE a `../uke-touchd-palm.patch` (PalmGuard: bloqueo por tiempo, desactivado con `--palm-hold 0`). No declara
`ABS_MT_TOOL_TYPE` ni emite `MT_TOOL_*` (rompia el pellizco; Hyprland ignora el cancel). Ficheros:
`palm_android.py` (logica pura), `uke-touchd-palm-android.patch` (sobre `tactil/uke-touchd.py` + `lapiz/uke-touchd-pen.patch`),
`test_palm_android.py` (14 pruebas), `sim_palma.py` + `test_sim_palma.py` (demonio real + arnes `analisis-pellizco/harness.py`,
validador kernel-like), `analiza_android.py` (evidencia de Android). **21-oct (2.a pasada, endurecimiento):** `sim_extra.py` + `test_sim_extra.py` (66 escenarios
extra + fuzzing con el demonio real), `test_palm_extra.py` (mitigaciones, fuzz puro, memoria, coste), `bench_palm.py` (us/frame).
Ejecutar todo: `cd build/rootfs/deploy/lapiz/desktop/palma-android && PYTHONPATH=../..:..:. python3 -m unittest discover -p 'test_*.py'` (64 pruebas, ~40 s; `python3 sim_extra.py` imprime la tabla de escenarios, `python3 bench_palm.py` el coste).

## Evidencia de Android (medida, `python3 analiza_android.py`)
- Config: weak 40 ms, strong 64 ms, umbral de movimiento 8 (ambos modos), blockList = solo juegos (irrelevante en Linux).
- event12 solo declara `ABS_DISTANCE` 0..1 (binario) y `BTN_DIGI`: «en rango» es un bit, sin altura.
- Los getevent (cap6/7/8) traen **poco**: 47 contactos de dedo en total, solo 15 a < 2 s de un rango de lapiz, **0 solapados con un rango**.
  Los mas cercanos: 4 contactos de 8-26 ms, quietos, que acaban 170-190 ms ANTES de la entrada del lapiz (cap6, palma llegando), y
  3 dedos de 0,2-0,7 s que empiezan 0,3-2,9 s DESPUES de salir (sin rechazo visible). No permite calibrar ningun umbral: las
  constantes salen del JSON y de la logica, no de estos datos. `build/android/lapiz-20261019/analisis/DATOS-RAFAGA-LAPIZ.md §2`: el chip **no intercala** 4bf dentro de una
  rafaga 0x509 (0 de 2718 frames): el chip ya ciega los dedos mientras escribe; el problema real son las transiciones.
- Escala del umbral 8: HIPOTESIS = pixeles del panel (la escala de Android es 10 u/px y 3200x2136 de pantalla = 1:1). Jitter medido de
  `thp_algo` con un dedo quieto (captura de Android 18-oct): <= 2 px; con 8 hay margen. Si fuera 8 u (0,8 px) seria inutilizable.

## Diseno (reglas en `palm_android.py`)
- **Activo** = ultimo frame 0x509 *presente* hace <= `margin` (100 ms) [equivale a ABS_DISTANCE]. No se usa `in_range` (mantiene 300 ms).
  Modo **fuerte** si ese frame tenia punta (contacto del chip), **debil** si solo hover.
- A. Dedo nuevo sin lapiz activo: pasa **ya**, sin retardo (pellizco sin lapiz = salida identica al demonio sin modulo, probado).
- B. Dedo nuevo con lapiz activo: pendiente 40/64 ms; si se movio > 8 px -> dedo; quieto y lapiz aun activo -> palma (ban); lapiz ya
  inactivo -> dedo. Levantado antes: hover y quieto -> se re-emite como toque de 1 frame; tras escribir -> se descarta (rebote de palma).
- C. Dedo quieto llegado <= 64 ms antes del primer frame de lapiz: palma. Ya habia emitido un `down` (inevitable sin retrasar todos los dedos;
  el demonio lo suelta con la rafaga): **un toque espureo posible**, que puede dar un clic.
- D. Continuidad: cada frame de lapiz hace `tr.reset()` (ids nuevos, `next_id` sigue subiendo; el ban por tid seria inutil). Al llegar un frame
  de lapiz cada contacto pasa a «fantasma» (posicion + estado); un contacto nuevo a <= 120 px de un fantasma vivo (<= margin) hereda su
  estado. Sin fantasma, el primer frame de dedos tras una rafaga >= 100 ms que trae un contacto <= 30 ms despues = palma ya apoyada: ban.
  Un dedo deliberado apoyado > 64 ms antes del lapiz se retoma tras la rafaga (nuevo tid).
- E. Sin bloqueo por tiempo: la palma baneada vive baneada mientras el contacto siga (Tracker puede perderla 1 frame: el fantasma la recupera);
  un dedo nuevo tras `margin` sin lapiz pasa sin retardo aunque la palma siga apoyada (pellizco con palma baneada: 2 dedos, probado).
- Cancelacion: solo se decide que `pts` se emiten; `ui.frame()` del demonio ya hace SLOT explicito + -1 por slot + BTN_TOUCH/TOOL 0 + un SYN.

## Resultados de simulacion (arnes real, 4,42 ms/frame): 17 escenarios, 0 violaciones kernel-like
Pellizco sin lapiz y tras rafaga (lineas base 0/700, con/sin dedo apoyado): 2 dedos, el 2.o pellizco empieza <= 66 ms tras un lapiz recien
levantado y a 0 ms con >= 400 ms. Palma antes del lapiz / durante / 20 ms despues / con pellizco encima: 0 `down` tras el primer frame de
lapiz (sin modulo: decenas). Dedo en movimiento tras hover: down a 44 ms; tras escribir: 66 ms. Estres con 4bf intercalado: 0 toques.
Con la bandera apagada la salida es identica byte a byte al demonio sin el parche.

## Limites (revisados el 21-oct, 2.a pasada; cada uno medido en `sim_extra.py`)
- **Down espureo si la palma llega < 64 ms antes del primer frame de lapiz**: sigue siendo inevitable (sin lapiz previo no se retrasa ningun
  dedo; retrasar solo los contactos de area grande no sirve: el area del Tracker son nodos >= umbral dentro de un 3x3, tope 9, y un dedo
  entero ya da 9). Mitigacion evaluada y descartada. Duracion del toque espureo = la espera (<= 64 ms): `palma_antes_del_lapiz`.
- **Dedo quieto que empieza justo tras el lapiz queda rechazado hasta levantarlo** (zona muerta): hover si empieza < 100 - 40 = 60 ms tras el
  ultimo frame de lapiz (gaps 0/20/50 ms: 0 downs), tras escribir si < 100 - 64 = 36 ms (gaps 0/20); a partir de ahi pasa a 44 / 66 ms; con
  >= 120 ms de hueco, a 0 ms. **Mitigacion M1 (opt-in, `--palm-release-ms N`, defecto 0 = apagado):** un contacto baneado quieto, con el lapiz
  inactivo desde hace N ms y que NUNCA tuvo area > `--palm-release-area` (6) pasa a dedo (`dedo_quieto_area_m_gap20_largo`: down a 367 ms con
  N = 300; con area 9, como una palma, nunca: `..._area_f_...`). Apagada por defecto porque una palma pequena de borde apoyada tras escribir
  se liberaria como toque, y la escala del area real no esta medida (HIPOTESIS). No toca nada mas (probado: salida identica en otros escenarios).
- Un dedo que se MUEVE > 8 px en la ventana pasa aunque sea una palma arrastrada (= regla de Android). Con la rafaga real (sin intercalado) la
  palma arrastrada tras escribir se banea por acarreo y no pasa (`arrastre_post_rafaga_d0..d8`: 0 downs); en el caso desfavorable de un chip que
  intercalase dedos cada k frames de lapiz, una palma que avanza >= 1 nodo cada ~66 ms pasa tras 84-115 ms (`arrastre_intercalado_k4/k8`);
  mas lenta (`k2_s6`) se rechaza.
- Lapiz fuera de rango > 100 ms con la palma volviendo: no hay lapiz activo, la palma toca (regla A, `palma_va_y_viene_gap200`: 7 downs). Con huecos
  <= 90 ms (palabras seguidas) 0 downs (`gap30/60/90`).
- Dos dedos deliberados con lapiz en hover pueden perder 40-64 ms (scroll/pellizco/3 dedos: primer down a 66,4 ms con la punta, 44 ms en hover).
- Umbral/escala 8 y reglas B/D sin respaldo en datos de Android (hipotesis); el area solo se usa en M1.
- **Hallazgo (no es de este modulo):** `uke-touchd-pen.patch` suelta el dedo (`ui.frame([])`) y hace `tr.reset()` con CUALQUIER 0x509, incluso uno
  sin lapiz presente: un dedo apoyado con un 0x509 de ruido cada 5 frames genera 40 down/up (demonio sin modulo: 40; con modulo: 40). **Opt-in
  `--palm-noise-keep`** (HIPOTESIS: un 0x509 suelto no cambia la linea base 4bf; verificar con el chip): el ruido ya no suelta ni reinicia -> 1 solo
  toque continuo. Sin la bandera, `tracker_reset()` conserva el estado de los contactos entre tids para que el ruido no los retrase 40-64 ms.

## Mitigaciones nuevas (todas con tests; solo `palm_android.py` + el parche)
1. **`replay_start` (por defecto ON, `--palm-no-replay-start` la quita):** al pasar a dedo tras moverse, el primer frame sale en la posicion donde EMPEZO
   el toque y el siguiente en la actual (sin latencia extra). Motivo: `uke-gestures.py` exige que el toque EMPIECE a < 40 px del borde; sin esto un
   deslizamiento desde el borde llegaba 66 ms dentro (`borde_entra_tras_lapiz_gap20`: posicion del 1.er down identica a la de sin lapiz; con la bandera
   quitada, distinta).
2. M1 liberacion de ban (arriba), 3. `--palm-noise-keep` (arriba), 4. tope de fantasmas (16): en una rafaga larga con muchos contactos baneados que
   van y vienen la lista crecia sin limite (los fantasmas se refrescan con cada frame de lapiz); fuzz y `test_tope_de_fantasmas` lo cubren.

## Matriz de escenarios (demonio real, 4,42 ms/frame; 0 violaciones kernel-like en TODOS, con y sin las opciones M1/noise-keep)
`downs` = inicios de contacto emitidos; latencia = ms simulados desde el 1.er frame del dedo hasta su 1.er down.
| Escenario (nombre en `sim_extra.py`) | Resultado |
|---|---|
| Palma arrastrada tras rafaga 1,2 s, deriva 0-8 nodos (`arrastre_post_rafaga_d*`) | 0 downs tras el lapiz |
| Palma que se arrastra con dedos intercalados (`arrastre_intercalado_k*_s*`) | k2/s6: 0; k4/k8: pasa tras 84/115 ms (limite = Android) |
| Palma sube/baja 6 veces, hueco 30/60/90/200 ms (`palma_va_y_viene_gap*`) | 30-90: 0; 200: 7 downs (lapiz fuera de rango) |
| Dedo 1 toque quieto, hover / escritura, hueco 0-500 ms (`dedo_quieto_*`) | ver Limites: zona muerta; >= 120 ms: 0 ms |
| Dedo que se mueve, hueco 20-500 ms (`dedo_mueve_*`) | hover 44,2 ms; escritura 66,4 ms; hueco 0: rechazado; >= 120 ms: 0 ms |
| Scroll 2 dedos / pellizco / gesto 3 dedos tras el lapiz (`scroll2_`, `pellizco_`, `gesto3_tras_lapiz_gap20/60`) | 2/2/3 downs, max simultaneos 2/2/3, 1.er down a 66,4 ms |
| Borde: 1 dedo entra desde fila 0 (`borde_entra_*`) | 66,4 ms, posicion de inicio = la de sin lapiz (replay_start) |
| Lapiz entra y sale 40 veces (3-6 frames) con huecos 2/10/40/90 ms + palma (`lapiz_parpadea_*`) | 1 down (el previo), 0 despues |
| Lapiz parpadea con dedo en movimiento | 29 downs / 30 ciclos (cada 0x509 suelta el dedo: demonio sin modulo 30) |
| 0x509 de ruido aislados: toque nuevo / dedo continuo / bajo hover con palma / palma baneada tras lapiz | 0 ms de retardo; 40 (= sin modulo; 1 con noise-keep); 0 downs; 0 downs |
| 10 dedos sin lapiz / con hover quietos / con hover moviendose | 10 a 0 ms / 0 (palmas) / 10 a 44 ms, max 10 slots |
| tids reutilizados (dedos que entran/salen 20 veces, 0x509 sueltos) | sin violaciones ni slots atascados |
| Rafaga de lapiz de 2 min simulados (27 120 frames) + palma + dedo posterior | 0 downs en la rafaga y la palma; dedo posterior a 0 ms |
| Fuzz demonio: 8 semillas x 2 configuraciones (secuencias de 60 segmentos: reposo, lapiz, ruido, 1-10 dedos quietos/moviendose, mezcla, parpadeo) | 0 violaciones, 0 slots atascados, <= 10 slots |
| Fuzz puro (`AndroidPalm`): 120 semillas x 3 configs x 1500 pasos, tids reutilizados, saltos de reloj de 2 s | invariantes OK (ids unicos, `rec` <= dedos del frame, fantasmas <= 16, nada atascado), 200 k pasos: memoria < 2 MB |
Sin bandera: salida identica byte a byte a la del demonio sin parche (sim con las semillas 0-2 del fuzz, ademas de los casos anteriores).

## Coste por frame (`python3 bench_palm.py`, PC; incluye construir la lista de puntos del propio bench)
Sin lapiz: 0 dedos 1,0 us; 1 dedo 2,2 us; 2 dedos 3,1 us; 10 dedos 10,2 us. Con lapiz activo: 1 dedo 3,9 us; 10 dedos 33,8 us. El camino sin lapiz
queda 5-50 veces por debajo del limite exigido de 50 us (`test_palm_extra.Bench`; en el SoC aarch64, mas lento, seguiria siendo del orden de decenas de us).

## Que probaria el dueno en la tablet (con `--pen --palm-android`, parche aplicado a una copia; no tocar el demonio instalado)
1. Sin lapiz: pellizco y toques normales (debe ser indistinguible; `--verbose`). 2. Escribir con la palma apoyada (antes y despues de acercar
el lapiz): ningun toque ni scroll; levantar la palma y pellizcar al instante. 3. Levantar el lapiz y tocar con el dedo a 0,2 s y a 0,5 s: a 0,5 s
sin retardo. 4. Con el lapiz en hover, toque corto con la otra mano. 5. Registrar `libinput record` en el uinput de dedo para contar downs.
Primero confirmar con `dmesg`/log que los 0x509 son continuos en hover y que no hay 4bf intercalados; ajustar `--palm-move-px` (jitter de una palma
real) y `--palm-margin-ms`. Si el pellizco falla, desactivar: quitar `--palm-android` (sin ella el codigo es el de pen.patch).
