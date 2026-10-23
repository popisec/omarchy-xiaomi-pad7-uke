# Resto de apps para el tacto + dictado offline en el teclado — 22-oct-2026 (noche, sesión autónoma)

Estado (12:10): **instalado, medido y probado en pantalla** tras el reinicio de recuperación de las 11:37 (la noche se perdió
por la caída de D-Bus de las 03:50, ajena a estas apps). Resultados de la prueba en pantalla en §7. Dudas del dueño en `DUDAS-RESTO-APPS.md`.

## 1. Matrix nativo: Fractal (elegido) frente a NeoChat

Medido en la tablet el 22-oct (`pacman -S --needed --print`, DB alineada tras el `-Syu` a Qt 6.12):
| | Fractal 14.1-1 (ALARM extra) | NeoChat 26.08.2-1 (ALARM extra) |
|---|---|---|
| Paquetes nuevos | **5** (fractal, libshumate, gst-plugin-gtk4, protobuf-c, protobuf*) | **63** (≈30 KDE Frameworks, libquotient, **libolm** (obsoleto), kaccounts/signon, **qt6-webengine 6.11.2** contra qt6-base 6.12) |
| Toolkit | GTK4 4.24 + libadwaita 1.10 (ya en el sistema, adaptable a móvil) | Kirigami/Qt Quick (adaptable, Plasma Mobile) |
| E2EE | matrix-rust-sdk: cifrado, verificación de sesión, clave de recuperación / secret storage | libQuotient: E2EE «parcial» según KDE; foros con fallos de verificación (24.12) |
| Login moderno (OIDC/MAS, matrix.org) | sí desde Fractal 10 | sin evidencia |
| Llavero | org.freedesktop.secrets → gnome-keyring 51.1 (ya instalado) | qtkeychain → kwallet/secret service |

\* `protobuf` está instalado a mano fuera de pacman (misma versión 36.1, ver `APPS-TABLET-20261021.md`): se instala con
`--assume-installed protobuf=36.1-1` y sin el paquete, como el 21-oct.

Fuentes (consultadas 22-oct-2026, informe de subagente): archlinuxarm.org/packages/aarch64/fractal (14.1-1, 30-jul-2026),
archlinuxarm.org/packages/aarch64/neochat (26.08.2-1), discourse.gnome.org/t/fractal-10-rc-released/26254 (OIDC),
gitlab.gnome.org/World/fractal/-/tags (14.2 del 21-oct-2026, aún no en ALARM), apps.kde.org/neochat,
discuss.kde.org/t/neochat-how-can-i-fetch-encryption-keys/18582. RAM: sin medidas publicadas → se mide aquí (§1.1).

**Decisión: Fractal.** Ligero en dependencias, el único con login OIDC/MAS demostrado, E2EE completo y misma pila que
Delfin/Komikku/Foliate. NeoChat arrastra qt6-webengine 6.11.2 desalineado con Qt 6.12 (riesgo de que no arranque).

## 2. Servicios del dueño vistos desde la tablet (22-oct, Dashy de PC-PORTATIL `conf.yml` + curl desde el PC)
| Servicio | URL | Acceso |
|---|---|---|
| Jellyfin 10.11.11 | `https://SERVIDORhost.tailnet-ejemplo.ts.net:9444` | directo (sin Authelia): `/System/Info/Public` 200 |
| Navidrome | `http://PC-PORTATIL:4533` (y `https://SERVIDOR-01…:9445` tras Authelia) | directo en PC-PORTATIL |
| Kavita | `https://SERVIDORhost.tailnet-ejemplo.ts.net:9455` | **tras Authelia** (302 a :9443) → OPDS de Komikku/Foliate no pasa sin regla de bypass |
| Nextcloud | `https://SERVIDORhost.tailnet-ejemplo.ts.net:9454` | directo |
`PC-PORTATIL:8096` y `:5000` no existen (de ahí los 502 del proxy de la sesión notas-nextcloud).
La tablet llega a la tailnet por el proxy HTTP/SOCKS5 de tailscaled en `127.0.0.1:1055` (`deploy/tailscale/README.md`).

## 3. Corrección: el plugin Navidrome NO necesita qt6-multimedia
`backmeupplz.navidrome` 0.2.1 reproduce con un `mpv` sin vídeo por IPC (`Service.qml:252`) y habla Subsonic con
`XMLHttpRequest`; no importa `QtMultimedia` (grep en PC y tablet, mismos sha256). Quien sí importa `QtMultimedia` es
**`radimsem.omafind`** (`ui/Player.qml`, `ui/PreviewLayer.qml`), que está activo en la tablet: su vista previa de vídeo/audio
es la que fallaba. Corrige lo dicho en `docs/historia/revision/PENDIENTES-APPS-20261022.md` §3 y en `APPS-TABLET-20261021.md`.

## 4. Dictado por voz OFFLINE en el teclado

### 4.1 Medida en la tablet (22-oct, 04:05–04:30; `deploy/dictado/bench.sh`)
Corpus: 8 frases de Multilingual LibriSpeech español, split test (113 s, voz leída real, bajadas por la API de filas de Hugging
Face `facebook/multilingual_librispeech`), WER con `wer.py` (minúsculas, sin tildes ni puntuación: la referencia usa ortografía
antigua). RTF = tiempo de proceso / duración del audio, sin contar la carga. Núcleos SM7675: 0-2 A520, 3-6 A720, 7 X4.
| Motor | Hilos / núcleos | WER | RTF | Carga | RSS pico |
|---|---|---|---|---|---|
| **Parakeet TDT 0.6B v3 int8** (sherpa-onnx 1.13.8, `uke-asr`) | **4 / 3-6** | **0,024** | **0,094** | 3,1 s | 1,13 GB |
| Parakeet idem | 5 / 3-7 | 0,024 | 0,103 | 3,2 s | 1,16 GB |
| Parakeet idem | 6 / libres | 0,024 | 0,106 | 3,1 s | 1,13 GB |
| Parakeet idem | 8 / libres | 0,024 | 0,133 | 3,2 s | 1,16 GB |
| whisper.cpp small q5_1 | 5 / 3-7 | 0,056 | 1,156 | (incl.) | 0,48 GB |
| whisper.cpp large-v3-turbo q5_0 | 5 / 3-7 | 0,028 | 5,139 | (incl.) | 0,81 GB |
| whisper.cpp base q5_1 | 5 / 3-7 | 0,116 | 0,409 | (incl.) | 0,21 GB |
Notas: los tiempos de whisper incluyen la carga del modelo por frase (CLI) y el compilado fue `GGML_NATIVE=ON` sin BLAS; aun así
small queda 12 veces por detrás de Parakeet. Parakeet entrega **puntuación y mayúsculas** («Y las almas, buscando algún alivio,
se revuelven…»). Vosk y Speech Note no se midieron: Vosk-es está por detrás de Whisper small en precisión (informe del subagente,
sin cifra verificada) y Speech Note es una app GUI (Flatpak) que no encaja con el botón del teclado.

**Decisión: Parakeet v3 int8 con 4 hilos en los A720.** Latencia de usuario: si la frase dura más de ~3 s, el modelo ya está
cargado al soltar y la transcripción tarda ~0,1 × duración (10 s → ~1 s). Para frases muy cortas (1–2 s) la espera es el resto de
la carga (≤ 3 s). RAM: 1,1 GB solo mientras se dicta (la tablet tiene ~4 GB disponibles; el proceso termina al insertar).

### 4.2 Integración
- `/usr/local/share/uke/dictado/` (678 MB: libs de sherpa-onnx, modelo, `bin/uke-asr`, `bin/whisper-cli` para comparar);
  `/usr/local/bin/uke-dictar` (`run` | `file` | `status`); `/etc/uke/dictado.conf` (`MOTOR`, `HILOS`, `TASKSET`).
  Modelos y binarios de terceros fuera de git: `~/backups/uke-dictado-modelos/SHA256SUMS`.
- `uke-dictar run`: graba la fuente por defecto con `pw-record` (16 kHz mono; «Micro interno (UKE)», sin tocar su config),
  arranca `uke-asr` a la vez (carga mientras hablas), y al leer `stop` transcribe y saca `texto <frase>`; `cancel` lo descarta.
- OSK (`touch-mode/fork`): tecla **«🎙 Voz»** junto al espacio (ES y US). Primer toque: graba (tecla roja «■ Parar», cabecera
  «Grabando…»); segundo toque: «…» y el texto entra en el campo enfocado por `commit_string` del input-method-v2 (el mismo
  camino que las letras, con acentos). La × de la cabecera cancela mientras graba. Tope de 2 min. IPC:
  `omarchy-shell omarkyy.tablet dictate` / `dictateCancel`; `status` muestra `dict` y `dictMsg`.
- Probado en la tablet (sin pantalla): `uke-dictar file` con una frase MLS → texto exacto con puntuación; `run` con 3 s de
  silencio → «no se entendió nada»; `cancel` → sin procesos huérfanos. **Sin probar todavía**: el botón con el dedo y la
  inserción en una app real (la sesión gráfica está congelada desde las 03:50 por la caída de D-Bus).

## 5. Estado por app (22-oct, 04:55)
| App | Estado en la tablet | Red | Tacto/escala | Falta |
|---|---|---|---|---|
| Element, Tuta (webapps) | **borrados** (copia `/root/backup-webapps-20261022`) | — | — | — |
| Fractal 14.1 | instalado, lanzador con `uke-tailnet` | proxy por app | libadwaita adaptable (escala 2 → 1600×1068 lógicos) | login + verificación del dueño; prueba con el dedo |
| Delfin 0.4.8 | instalado (21-oct), lanzador con `uke-tailnet` | Jellyfin `https://SERVIDOR-01…:9444` | libadwaita | login; reproducir con mpv por el proxy |
| Komikku 50.11 / Foliate 3.3 | instalados (21-oct), lanzadores con `uke-tailnet` | Kavita tras Authelia | libadwaita | regla de Authelia o acceso directo (duda 3) |
| Strawberry 1.2.31 | instalado | necesita `uke-navidrome-fwd` (duda 2) | Qt Widgets: interfaz de escritorio, botones pequeños | decidir frente al plugin de la barra tras probar |
| Plugin Navidrome (barra) | presente, sin activar; no necesita qt6-multimedia | idem | filas de 40 px lógicos (~6 mm): justas para el dedo | activar en `shell.json` tras el reenvío |
| scrcpy 5.0.1 | instalado; `uke-movil` + lanzador «Móvil (scrcpy)» (socat temporal por el proxy) | Tailscale → `nothing-phone-2:5555` | ventana de scrcpy | `adb tcpip 5555` una vez por USB; probar |
| Dictado | `uke-dictar` + Parakeet instalados y probados; botón 🎙 copiado al plugin | offline | tecla 1,3 u. junto al espacio | recargar el shell y probar con el dedo |
| qt6-multimedia | instalado (lo usa `radimsem.omafind`) | — | — | comprobar la vista previa de omafind |

## 6. Para retomar (en orden)
**Pasos 1 y 2 hechos el 22-oct a las 12:06 (ver §7).** Queda el 3 y la prueba con voz real.
1. Cuando la sesión gráfica vuelva: `omarchy-shell omarkyy.tablet status` debe incluir `dict`; si no, `omarchy restart shell`
   (con turno). Abrir un campo de texto, tocar 🎙, hablar, ■ Parar → el texto debe aparecer. Captura con `grim`.
2. Abrir Fractal, Delfin, Komikku, Foliate, Strawberry con el dedo (capturas en vertical y apaisado, con el OSK).
3. Con el visto bueno del dueño: `deploy/resto-apps/deploy.sh navidrome`, activar el plugin y elegir entre él y Strawberry.
Reversión: `deploy/dictado/deploy.sh revert`, `deploy/resto-apps/deploy.sh revert`, plugin del OSK desde
`~omarchy/.local/share/uke-touch-mode/backup-plugin-20261022-dictado`, paquetes con `pacman -Rns` (lista previa
`/root/pkgs-pre-resto-apps-20261022.txt`).

## 7. Prueba en pantalla (22-oct, 11:56–12:06, turno `resto-apps`; capturas en `capturas-resto-apps-20261022/`)
Método: `grim` como omarchy (`setpriv`, sin `runuser`), toques simulados con `touch-mode/osk-click.py` (puntero absoluto por
uinput) y teclas/texto por la IPC del OSK; inhibidor de reposo temporal (`systemd-inhibit`, retirado al terminar).
| Prueba | Resultado |
|---|---|
| 🎙 en el OSK (gnome-text-editor) | **OK**: tecla roja «■ Parar» y cabecera «Grabando…» (01); al parar, texto insertado por IME, «listo en 1,2–1,3 s» (02). 3 de 3 inserciones. |
| Precisión con audio por el altavoz de la propia tablet | Regular: «Como por otra parte era tanto lo que el capitán visitaba Upper Cross. Salir de allí.» y variantes; a veces se come el final o deriva al portugués. La grabación llega entera (12,3 s, verificado), pero a −29 dBFS de pico: el bucle altavoz→micro es una mala prueba. Normalizar la ganancia no mejora (probado). **Falta la prueba con voz real del dueño.** |
| Fractal | Arranca (208 MB RSS); pide **crear la contraseña del llavero** (gcr-prompter, en inglés, con el OSK tapando la mitad del diálogo); al cancelar: «Secret Portal Error» (03). Es lo esperado: lo hace el dueño. |
| Delfin | Arranca (176 MB). Servidor añadido con el dedo simulado y el OSK: la ✓ valida `https://SERVIDOR-01…:9444` y trae su nombre `d728b050740f` **por el proxy** (04). Login: el dueño. |
| Komikku | Arranca (311 MB). **Al abrir saca el OSK solo** (enfoca su búsqueda) y tapa media ventana (05); se oculta con la ×. |
| Foliate | Arranca (216 MB); el catálogo OPDS de Project Gutenberg carga (06); tarjetas de ~68 px lógicos, buenas para el dedo. |
| Strawberry | Arranca (179 MB) pero es **interfaz de escritorio** (Qt Widgets, tema claro, iconos de ~20 px lógicos ≈ 3 mm) (07): **no recomendado** para el dedo. Sí trae Subsonic y Jellyfin. |
| `uke-movil` sin el móvil preparado | Falla limpio en ~10 s con aviso, sin dejar socat ni el servidor de adb (corregido en esta prueba). |
Incidente propio: un `pkill` con comillas mal anidadas en mi ayudante SSH mató (como omarchy) `uke-gestures` y el
`app-daemon` de uwsm; ambos relanzados al momento (`systemctl --user start`, `active`). El ayudante pasa ahora la orden por stdin.

**Recomendación de música**: el plugin Navidrome de la barra (QML del propio shell, filas de 40 px lógicos) mejor que Strawberry;
necesita el reenvío `uke-navidrome-fwd` (duda 2). Alternativa sin reenvío: la música de Jellyfin en Delfin, si la hay.

## 8. Limpieza pedida por el dueño (22-oct ~16:05)
Strawberry desinstalado con sus 17 dependencias (config movida a `/root/backup-resto-apps-20261022/strawberry*`) y las 12 webapps
de serie de Omarchy borradas (copia `/root/backup-webapps-20261022`; restaurar = copiar de vuelta + `update-desktop-database`).

## 9. Accesos a los servidores repetidos DESDE LA TABLET (22-oct 16:33, `uke-tailnet curl`, orden del dueño: probar en la tablet)
| URL | Tablet | Nota |
|---|---|---|
| Jellyfin `https://SERVIDOR-01…:9444/System/Info/Public` | 200 | igual que desde el PC; Delfin ya lo validó en pantalla (§7) |
| Kavita `https://SERVIDOR-01…:9455/` y `/api/opds/…` | 302 → Authelia `:9443` | confirmado en la tablet: OPDS bloqueado por Authelia (duda 3) |
| Navidrome `https://SERVIDOR-01…:9445/ping` | 302 → Authelia | la copia de SERVIDOR-01 también va tras Authelia |
| Navidrome `http://PC-PORTATIL:4533/ping` | 000 | **PC-PORTATIL está fuera de la tailnet** («offline, last seen 13m ago»; el PC tampoco llega). Reintentar cuando vuelva |
Todo lo demás de este informe (bancos del dictado, paquetes, apps, OSK) ya se midió o probó en la tablet.

### 9.1 Repetido a las 19:07 con PC-PORTATIL de vuelta (desde la tablet, `uke-tailnet curl`)
- **Navidrome `http://PC-PORTATIL:4533/ping` → 200** y `/rest/ping.view` responde Subsonic: la tablet llega. Falta solo el reenvío
  local para el plugin de la barra (duda 2, servicio persistente pendiente del visto bueno del dueño).
- **Kavita**: `SERVIDOR-01…:9455/`, `/api/opds/…` y `/api/health` → 302 a Authelia. Barrido desde el PC de puertos de PC-PORTATIL
  (4567, 5000-5050, 8000-8092, 9000, 9925, 25600): Kavita no se publica directo; hay Suwayomi en `https://PC-PORTATIL…:4567`
  (sin comprobar si Komikku lo soporta). Komikku/Foliate ↔ Kavita sigue bloqueado por Authelia (duda 3: cambio en el servidor).

## 10. Kavita sin Authelia, solo tailnet (orden del dueño 22-oct ~19:15)
- Causa doble: en SERVIDOR-01 `caddy-central` `:8093` (Tailscale serve `:9455`) tenía `forward_auth` de Authelia **y** apuntaba a
  `100.64.0.12:5001`, pero en PC-PORTATIL el contenedor `kavita` publica solo en `127.0.0.1:5001` → aun pasando Authelia daba 502.
- Cambios (servidores del dueño, con copia):
  1. PC-PORTATIL: `tailscale serve --bg --https=5001 http://127.0.0.1:5001` (mismo patrón que Suwayomi/Navidrome; tailnet only).
     Revertir: `tailscale serve --https=5001 off`.
  2. SERVIDOR-01 `~/homelab/caddy/Caddyfile` (copia `Caddyfile.bak-20261022-kavita-noauthelia`): `:8093` sin `forward_auth`,
     `to https://PC-PORTATIL.tailnet-ejemplo.ts.net:5001` + `header_up Host {upstream_hostport}`; `caddy validate` OK y `caddy reload`
     en caliente. No hecho commit en el repo `homelab` (es del dueño). Revertir: copiar el .bak y `caddy reload`.
- Comprobado desde la TABLET (`uke-tailnet curl`): `https://SERVIDOR-01…:9455/api/health` 200 y `https://PC-PORTATIL…:5001/api/health`
  200; `POST /api/Account/login` vacío → 400 (llega a Kavita). Desde el PC: Jellyfin 200 e Immich 302 a Authelia (sin cambios).
- Komikku trae fuente Kavita propia (`komikku/servers/kavita`: dirección + usuario + contraseña, API `/api/Account/login`).
  Dirección para el dueño: `https://SERVIDORhost.tailnet-ejemplo.ts.net:9455`. Foliate (OPDS): `…:9455/api/opds/<API key de Kavita>`.

## 11. Navidrome en la barra funcionando en la tablet (22-oct ~19:26, aprobado por el dueño)
- `deploy/resto-apps/deploy.sh navidrome`: servicio `uke-navidrome-fwd` (socat `127.0.0.1:14533` → `PC-PORTATIL:4533` por el
  proxy de tailscaled) habilitado; `/ping` por 14533 → 200; `navidrome.json` → `http://127.0.0.1:14533` (copia en
  `/root/backup-resto-apps-20261022/`). Plugin activado con `omarchy plugin enable backmeupplz.navidrome --section right`
  (copia de `shell.json` en la misma carpeta).
- El servicio cargaba (884 álbumes, reproducía por IPC) pero **el panel salía con el login**: `Panel.qml:317 TypeError … of null`.
  Causa: con una barra de terceros (powerbar) Omarchy 4.0.6 da a sus widgets la fachada `pluginShellForBarEntry` **sin**
  `_serviceLookup`, así que `serviceFor(<su propio id>)` devuelve null. **En el portátil funciona** porque su Omarchy (checkout
  git en `~/.local/share/omarchy`) lleva un parche local sin commit en `shell/shell.qml` (11 líneas, «LOCAL PATCH (usuario)»):
  `_serviceLookup` limitado al propio id del widget.
- Aplicado el mismo parche en la tablet (orden del dueño) con `deploy/resto-apps/omarchy-parche-servicefor.sh apply`
  (idempotente; copia `/usr/share/omarchy/shell/shell.qml.pre-servicefor`; **reaplicar tras cada actualización de omarchy**,
  `… status` lo dice). `omarchy restart shell` → sin `TypeError`.
- Probado en la tablet con toques: panel con los 884 álbumes y portadas (09), álbum → «Play» → suena «DOLCE DONCELLA» 0:05/2:41 con
  controles (10); pausado al terminar. Pega táctil: casillas y botones de control de ~20 px lógicos (~3 mm), pequeños; filas de
  álbum de ~52 px lógicos, cómodas.

## 12. Navidrome persistente sin parchear Omarchy: plugin `uke.navidrome` (22-oct ~20:35)
- El parche de §11 se perdería con cada actualización de Omarchy. Sustituido por un **fork del plugin** en
  `deploy/resto-apps/uke.navidrome/` (MIT, de backmeupplz.navidrome 0.2.1): manifiesto solo `bar-widget` (no registra servicio en el
  shell) y el panel **crea su propio `Service`** (`readonly property Item ownService: Service {}`), así no depende de `serviceFor`.
  Además, para el dedo: botones de reproducción de ~22 → 40 px lógicos, filas de 40 → 52 y casilla de 20 → 28 con zona de toque ±12.
- Despliegue: `deploy/resto-apps/deploy.sh navidrome-fork` (desactiva `backmeupplz.navidrome`, activa `uke.navidrome`; copia de
  `shell.json` en `/root/backup-resto-apps-20261022/`). **Parche de Omarchy revertido** (`omarchy-parche-servicefor.sh revert`;
  `status` → 0), y aun así funciona: panel con 884 álbumes, Shuffle → suena «Demasiao Tarde», pausa (capturas 11 y 12). Un solo mpv.
- Aviso inocuo: `Service.qml:62 TypeError` una vez durante `omarchy restart shell` (callback XHR de la instancia que se destruye).
- Turno: el de notas-nextcloud llevaba 46 min, su sesión no era alcanzable y no había procesos de sync → `uke-turno pedir --forzar`.

## 13. Komikku abre con el teclado: causa raíz (22-oct ~22:20, medido en la tablet, turno `pantalla`)
- Komikku activa el input method a los ~3 s de abrir y lo mantiene (muestreo de `omarkyy.tablet status`: `imActive` 0 0 1 1 1…).
  Por AT-SPI, el foco está en el botón «Añadir cómic nuevo», no en un campo de texto.
- Pruebas mínimas GTK4 (`deploy/resto-apps/pruebas/`): `GtkSearchBar` oculta con `set_key_capture_widget(ventana)` **y** un widget
  con foco ⇒ GTK habilita text-input ⇒ el OSK sale solo (sin key-capture: 0 0 0 0 0; con: 1 1 1 1 1). Un `WebKit.WebView` oculto
  **no** lo provoca (0 0 0 0 0 0). Komikku hace exactamente eso (`komikku/library/__init__.py:101`, buscar al teclear). Es
  comportamiento normal de GTK: cualquier app GNOME con «escribe para buscar» hará lo mismo.
- No se puede distinguir por los eventos del IME de un campo vacío real ⇒ propuesta: lista por app de «sin auto-mostrar»
  (`~/.local/state/uke-touch-mode/no-auto`, con `info.febvre.Komikku`), abriendo el teclado a mano con el gesto o el botón.
  **No aplicado**: el OSK lo lleva la sesión escritorio-tactil (tiene cambios sin commit en `touch-mode/fork/`); se le ha pasado
  el diagnóstico y la propuesta.

### 13.1 Arreglo aplicado por escritorio-tactil y verificado en la tablet (22-oct 22:16, turno `pantalla`)
Lista `~/.local/state/uke-touch-mode/no-auto` (se lee al arrancar la shell; `status` muestra `app` y `noAuto`). Komikku: `imActive`
0 1 1 1 1 1 1 1 pero teclado 0 en todo momento (captura 13, pantalla de bienvenida limpia); `omarkyy.tablet show` lo abre a mano
(teclado=True); gnome-text-editor (no listado) sigue abriéndolo solo (imActive=True, teclado=True). Para otras apps GNOME con
«escribe para buscar»: añadir su app id a ese fichero y reiniciar la shell.
