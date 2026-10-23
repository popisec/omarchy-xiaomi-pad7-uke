# Apuntes nativos + Nextcloud en la tablet — informe de la noche del 22-oct-2026

Sesión «notas-nextcloud» (autónoma; el dueño dormía). Repo de la app: `~/proyectos/notas-nativas` (commits `d58d2ae`, `ae1a057`,
`780f307`). Turno de tablet `notas-nextcloud` durante todo el trabajo.

## Resultado
**La app de apuntes funciona en la tablet y está sincronizada con el Nextcloud del dueño.** Xournal++ 1.3.8 para escribir y `notas` 0.2.1
(`notas-sync`, `notas-nuevo`, `notas-abrir`, `notas-ia`) instalado. La sync va sola cada 2 min por el proxy de tailscaled, en ambos
sentidos. Las pruebas usaron datos de PRUEBA y ya están borradas. `Notas/` en Nextcloud estaba vacía antes de empezar (PROPFIND: solo
la colección), así que no había notas reales que respaldar ni que tocar.

## 1. Proxy de Tailscale (autorizado por el dueño)
- `/etc/default/tailscaled`: `FLAGS="--tun=userspace-networking --outbound-http-proxy-listen=localhost:1055 --socks5-server=localhost:1055"`.
  Copia previa en `/root/tailscaled.default.bak-20261022`. Aplicado por USB, con turno y con reversión automática (no hizo falta).
- Verificado: el SSH por Tailscale vuelve tras el reinicio de tailscaled; `SERVIDOR-01…:9454/status.php` da 200 (0,17 s por HTTP, 0,12 s
  por SOCKS); `PC-PORTATIL:4533` da 302; también resuelve el nombre corto, `.tailnet-ejemplo.ts.net` y la IP 100.x. Internet sin proxy, igual.
- Uso documentado en `build/rootfs/deploy/tailscale/README.md` (commit `8a42fe2`). Avisadas las sesiones Immich+SP y resto-apps.

## 2. Instalación y credencial
- `pacman -U notas-0.2.1-1-any.pkg.tar.zst`. Dependencias ya presentes: python, xournalpp. `libnotify` no está; es opcional, para el aviso del lanzador.
- Credencial: `~omarchy/.config/notas/nextcloud.toml` (600, omarchy), copiada por la entrada estándar de ssh; no se ha mostrado.
  Proxy en `~omarchy/.config/notas/sync.env` (600).
- `notas-sync.timer` de usuario habilitado (arranca a los 30 s y luego cada 2 min). Ojo: `systemctl --user -M omarchy@` se cuelga
  en esta tablet; usar `setpriv --reuid=1001 … systemctl --user` con `XDG_RUNTIME_DIR` y el bus de la sesión.
- Generado el locale `es_ES.UTF-8` (copia de `/etc/locale.gen` en `/root/locale.gen.bak-20261022`): solo lo añade. El idioma del
  sistema sigue siendo C.UTF-8; `notas-abrir` pone `LC_MESSAGES=es_ES.UTF-8` solo a Xournal++ («Save» → «Guardar»).

## 3. Pruebas (medidas completas en `notas-nativas/docs/medidas.md`)
| Prueba | Resultado |
|---|---|
| PC crea → tablet recibe; tablet crea → PC recibe; ediciones cruzadas | OK, contenido idéntico |
| Conflicto (ambos editan) | Copia «(conflicto uke-arch …)» en ambos equipos; principal = remoto; nada perdido |
| Cuaderno dibujado en la tablet → PC (timer, sin intervención) | sha256 igual en ambos lados |
| `.xopp` modificado en el PC (capa «ia») → tablet | sha256 igual; capa `ia` presente |
| Cuaderno abierto en Xournal++ y cambio remoto | **aplazado** (no se pisa); baja al cerrar |
| Borrado PC → Nextcloud → tablet | 5 borrados locales, nada más |
| Lápiz (eventos inyectados en el evdev real) | Trazos con presión variable (ancho 0,42→0,68), goma OK |
| Dedo | Pulsaciones en barra y diálogo OK; arrastrar no pinta (rechazo de palma); zoom con 2 dedos SIN probar |
| Arranque de Xournal++ | 2,43 s en frío, 1,7 s en caliente |
| RSS de Xournal++ | 136–141 MiB (PSS ~96 MiB) |

Las pruebas de entrada se hicieron **inyectando eventos** en `/dev/input/event4` (NT36532) y `event5` (Focus Pen) con
`notas-nativas/tools/pruebas/uke_inject.py`, como `evemu-play`. Pasan por libinput y Hyprland igual que los reales, pero no miden la
latencia del lápiz real ni el apoyo de la mano: eso queda para el dueño.

## 4. Mejoras hechas a partir de las pruebas
- **No pisar cuadernos abiertos**: Xournal++ no recarga el fichero y su siguiente guardado borraría lo bajado. Ahora se aplaza (la
  detección mira el argumento de `xournalpp` y su `.<nombre>.autosave.xopp`).
- Modo de los ficheros bajados según la umask (antes quedaban en 600 por `mkstemp`). Se ignoran los ficheros `~`. Cerrojo `flock` para
  que no corran dos pasadas a la vez. Se podan solo las carpetas que vacía la propia sync, comprobando antes que están vacías.
- `notas-nuevo "<asignatura>" "<título>" --fondo rayado|cuadricula|puntos|liso --abrir` crea `~/Notas/<asignatura>/AAAA-MM-DD HHMM título.xopp`.
  `--lista` muestra las asignaturas. Lanzadores: «Apuntes», «Nuevo apunte» y «Sincronizar notas».
- `notas-perfil-tablet`: la herramienta inicial es el bolígrafo (estaba en **Texto**: al apoyar el lápiz abría un cuadro de texto y
  saltaba el teclado en pantalla), barra «Toma de notas con mano derecha» y carpetas en `~/Notas`. Aplicado en la tablet, con copia
  `settings.xml.antes-perfil-20261022-034707`.
- 19 tests en verde (`bin/test`).

## 5. Incidencia: sesión gráfica congelada desde las 03:50:38 (NO resuelta; en `docs/historia/DUDAS.md`)
El `dbus-broker` del sistema llegó a 1,1 GB y expulsó a varios pares de root: logind perdió `org.freedesktop.login1`, y Hyprland
(libseat «Sending user's quota exceeded») perdió el DRM master (`atomic drm request … Permission denied`). La pantalla queda congelada
en el último fotograma; SSH, IPC y la sync funcionan. Causa probable: `uke-lapiz.service` dejó de leer la tubería de su
`busctl monitor org.bluez` (PID 1720 en `anon_pipe_write`). Lo agravaron mis ~140 `runuser` (uno por consulta a Hyprland, cada uno con
su sesión PAM), que ya cambié por `setpriv`. **No he reiniciado nada.** Recuperación propuesta a la sesión principal (dos mensajes):
reiniciar uke-lapiz, luego systemd-logind y luego la sesión de Hyprland, sin reiniciar la tablet.

## 6. Pendiente
1. Recuperar la sesión gráfica (decisión de la sesión principal o del dueño, ver §5).
2. Con el dueño: lápiz real (latencia, palma), desplazamiento y zoom con dos dedos, y si la ventana translúcida de Omarchy molesta al escribir.
3. IA (Token Spy): bloqueada. Hace falta el modelo con visión, el permiso de privacidad y la clave (en `docs/historia/DUDAS.md`).
4. Rúbricas por asignatura y estructura `~/Notas/<asignatura>/` real: la crea el dueño con sus asignaturas, no la he inventado.

## 7. Cierre (22-oct 11:56, tras el reinicio de las 11:37)
La sesión principal reinició la tablet; WiFi, logind y Hyprland están bien, y uke-lapiz está parado mientras se arregla su monitor de
busctl. Así quedan la §5 y el punto 1 de la §6. Comprobado a los 17 min de arrancar:
- tailscaled `active` con las FLAGS del proxy y escucha en `127.0.0.1:1055`. `SERVIDOR-01…:9454/status.php` da 200 tanto por HTTP
  (0,18 s) como por SOCKS5, y `PC-PORTATIL:4533` da 302.
- `notas` 0.2.1, credencial y `sync.env` intactos (600), y el locale `es_ES.utf8` sigue presente.
- `notas-sync.timer` activo tras el arranque, sin intervención: pasadas a las 11:50, 11:52 y 11:54, todas con «errores 0». `~/Notas` solo
  tiene el estado y el cerrojo.
**Cerrado.** Queda para el dueño: probar con el lápiz real y con dos dedos, la IA (docs/historia/DUDAS.md) y crear sus carpetas de asignatura.

## 8. Tarde del 22-oct: decisiones del dueño, Xournal++ pulido y paso a `Clases/`
- Decisiones (en `notas-nativas/docs/decisiones.md`): IA **solo con modelo local**; el dedo no dibuja; los apuntes van en la
  carpeta existente **`Clases/`** del Nextcloud; de momento se pule Xournal++.
- Xournal++ verificado en la tablet:
  - menús en español;
  - papel opaco: regla `-default-opacity` en `~omarchy/.config/hypr/hyprland.lua`, con copia `.bak-notas-20261022`;
  - el arrastre con dos dedos desplaza y el pellizco amplía (inyectado);
  - barra «Tablet (notas)» con botones grandes.
  `notas` 0.3.2 añade `notas-anotar` (PDF con fondo relativo, portable entre PC y tablet), `remote_dir` con salvaguarda de estado
  y reintentos con espera exponencial. 61 tests en verde.
- Copia completa de `Clases/` antes de sincronizar: `~/backups/nextcloud-clases-20261022/`, con 257/257 ficheros (910 MB), 0 fallos
  y el sha256 de cada fichero en `MANIFIESTO.json`.
- Pasada de prueba en el PC: **257 descargas y nada más**. La pasada real bajó 23 ficheros y después el Nextcloud empezó a dar
  **502 en todo** (también en `status.php`; a las 16:26 seguía caído, mientras Jellyfin en SERVIDOR-01:9444 sí respondía). Paré la
  pasada del PC. La tablet tiene `remote_dir = "Clases"` y el timer activo: con `~/Notas` vacío su primera pasada solo baja ficheros
  y se completará sola cuando vuelva el servidor. Un PROPFIND fallido aborta la pasada sin aplicar nada. No consta que la caída la
  causara la copia (257 GET seguidos), pero coincide en el tiempo.
- **16:40 — sync de `Clases/` EN PAUSA** (orden del dueño): el Nextcloud corre en PC-PORTATIL (100.64.0.12:8083) detrás del caddy de
  SERVIDOR-01, y PC-PORTATIL está caído. `notas-sync.timer` de la tablet está deshabilitado y `~/Notas` sigue vacío allí. Los 23 ficheros
  del PC se quedan sin tocar. Para reanudar: `systemctl --user enable --now notas-sync.timer` en la tablet.
- **18:46 — `notas-anotar` probado en la tablet** con un PDF real de la copia, en `~/prueba-xpp` (fuera de `~/Notas`, ya borrado).
  Cuaderno en 0,16 s, PDF de fondo visible, tinta guardada y ruta relativa conservada tras guardar en Xournal++.
