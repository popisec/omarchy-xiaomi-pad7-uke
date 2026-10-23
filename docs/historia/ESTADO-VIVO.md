# ESTADO VIVO — 22-oct 19:20 (última entrada; este fichero es un log cronológico inverso: la más reciente va la primera)

> - **22-oct 19:20 — PLUGINS DE LA SHELL ARREGLADOS + ELSEWHEN DEL PORTÁTIL** (sesión plugins-tablet): `inotify-tools` (recarga de plugins en caliente), `uke.network` sin los ~60 TypeError por reescaneo, widgets «On demand» de Powerbar visibles (con el dedo eran inalcanzables), tiempo activado y reloj mundial `uke.elsewhen` (tus 5 ciudades, es, °C, 24 h); probados con toques. Informe `build/gates/revision/PLUGINS-TABLET-20261022.md`, dudas `docs/historia/DUDAS-PLUGINS.md`. **Próximos 3 pasos:** (1) el dueño prueba la barra con el dedo (sobre todo el «primer toque»); (2) decidir serpbar/omafind/navidrome y el toque de `uke.bateria` que cambia el perfil; (3) comprobar en el próximo inicio de sesión que ya no sale la notificación de `udiskie` (instalado 19:27).
> - **22-oct 17:05 — BITWARDEN EN LA TABLET** (sesión bitwarden): `rbw` + `wtype` + paquete `omarchy-bitwarden` y plugin `uke.bitwarden` (candado en la barra); probado con toques contra una bóveda de prueba: desbloqueo, relleno de usuario/contraseña/TOTP en Firefox y en una app Qt. Repo `~/proyectos/bitwarden-omarchy`. **Próximos 3 pasos:** (1) el dueño inicia sesión con su cuenta (panel → correo/servidor → contraseña maestra); (2) tecla 🔑 en el teclado en pantalla; (3) bloquear al bloquear pantalla.
> - **22-oct 17:3x — CÁMARAS EN MEGAPIXELS + CARGA AL ARRANQUE HABILITADA** (OK del dueño; sin reiniciar): trasera y frontal con preview y fotos, AE/AWB por software; `uke-camaras.service` + `uke-camaras-lente.service` enabled, a verificar en el próximo arranque (interruptor `/etc/uke/no-camaras`). Detalle: `CAMARAS-MEGAPIXELS-20261022.md`.
> - **22-oct 16:55 — ESCRITORIO TÁCTIL** (sesión escritorio-tactil): teclado con **sugerencias y autocorrección en español** (11/11 pruebas, toques reales), aparición ~180 ms (la cifra de 124 ms se retiró: medida contaminada) y ya no se queda visible en un escritorio vacío; **una app por escritorio a pantalla completa** y dividir/unir con pellizco de 3 dedos; animaciones de 150–220 ms sin blur; **lanzador `uke.launcher`** dentro del shell en lugar de nwg-drawer (−138 MB de RSS en el escritorio); hyprmoncfg retirado y omafind desactivado. Informe `build/gates/revision/ESCRITORIO-TACTIL-20261022.md`, dudas `docs/historia/DUDAS-ESCRITORIO.md`. **Próximos 3 pasos:** (1) el dueño prueba con el dedo (pellizco de 3 dedos, teclado, lanzador); (2) responder las dudas (clic sonoro, autocorrección); (3) revisar el consumo de `uke-touchd-pen.py` (6–15 % en reposo).
> - **22-oct 12:45 — ⚠️ OOPS DEL KERNEL (cámaras) — REINICIAR CON ALGUIEN DELANTE**: al reaplicar por 4.ª vez el overlay de la cámara frontal, corrupción de slab (NULL deref en kmalloc); 2 tareas en D en `of_device_uevent` (una es el aviso de batería). La tablet sigue usable pero no es fiable: **no cargar ni descargar módulos con overlays** hasta reiniciar. Frontal OV08D10 detectada (chip 0x5608) y transmitiendo a 30 fps, aún sin buffers. Detalle: `CAMARAS-MEGAPIXELS-20261022.md`, `docs/historia/DUDAS-CAMARAS.md`.
> - **22-oct 12:10 — DICTADO EN EL TECLADO FUNCIONA EN PANTALLA** (sesión resto-apps): 🎙 → «■ Parar» → texto insertado por IME en ~1,2 s; Fractal/Delfin/Komikku/Foliate probados (Delfin ya conectado a Jellyfin por el proxy); Strawberry no apto para el dedo. **Próximos 3 pasos:** (1) prueba con la voz del dueño; (2) reenvío Navidrome + plugin de la barra (visto bueno); (3) logins y llavero del dueño.
> - **22-oct 04:25 — RESTO DE APPS + DICTADO OFFLINE** (sesión resto-apps): Element/Tuta borrados (sin webapps); **Fractal** (Matrix nativo), Strawberry, socat y qt6-multimedia instalados; `uke-tailnet` (proxy por app) en Delfin/Komikku/Foliate/Fractal; `uke-movil` (scrcpy por Tailscale). **Dictado: Parakeet v3 int8 en la tablet, WER 2,4 %, RTF 0,094** (`uke-dictar`, botón 🎙 en el OSK copiado, carga al reiniciar el shell). Informe `build/gates/revision/RESTO-APPS-DICTADO-20261022.md`, dudas en `DUDAS-RESTO-APPS.md`. **Próximos 3 pasos:** (1) tras recuperar la sesión gráfica, probar 🎙 y las apps con el dedo; (2) Navidrome/Strawberry con el reenvío (visto bueno del dueño); (3) logins del dueño.
> - **22-oct 04:05 — APUNTES + NEXTCLOUD EN LA TABLET: FUNCIONAN** (sesión notas-nextcloud): proxy de tailscaled en `127.0.0.1:1055` (HTTP+SOCKS5; `deploy/tailscale/README.md`), `notas` 0.2.1 + Xournal++ con sync de `~/Notas` cada 2 min, probada en ambos sentidos. **⚠️ Desde las 03:50:38 la pantalla está congelada** (D-Bus sin cuota → logind fuera del bus → Hyprland sin DRM master; causa probable: `uke-lapiz` atascado). Ver `docs/historia/DUDAS.md` e informe `build/gates/revision/NOTAS-NEXTCLOUD-20261022.md`. **Próximos 3 pasos:** (1) recuperar la sesión gráfica (uke-lapiz → logind → Hyprland, sin reiniciar la tablet); (2) prueba del dueño con el lápiz real; (3) IA de corrección (falta modelo/clave).
> - **22-oct 03:37 — CÁMARA TRASERA: FOCO V4L2 + camss `qcom-camss`** (ciclos 21–22): lente `dw9714 7-000c` con `focus_absolute` y enlace auxiliar sensor→lente (lo que busca libcamera). **Próximos 3 pasos:** (1) instalar libcamera 0.7.2 de `extra` (pacman, orden del dueño); (2) `cam`/softISP y una app; (3) persistencia de los módulos.
> - **22-oct 02:53 — CÁMARA TRASERA: FOTOS DE CALIDAD Y 13 MP** (ciclo 20): revelado en el PC (`camaras/raw-develop.py`: demosaico Malvar, WB, ruido, ráfagas) y 4208×3120 funcionando. **Próximos 3 pasos:** (1) CCM/LSC calibrados; (2) libcamera/softISP o V4L2 para una app; (3) frontal OV08D10.
> - **22-oct 02:46 — CÁMARA TRASERA CON AUTOFOCO**: VCM CN3927V en 0x0c (riel l14 por el módulo `uke_rpmh_ldob14`, sin kernel nuevo); AE+AF por contraste → foto enfocada (DAC 448). Informe `CAMARAS-C5-CICLO18-19-RESULTADO-20261022.md`. **Próximos 3 pasos:** (1) demosaico/balance reales; (2) V4L2 del foco o libcamera/softISP; (3) frontal OV08D10.
> - **22-oct 02:35 — CÁMARA TRASERA: PRIMER FRAME RAW VALIDADO** (ciclos 16–17, solo insmod/rmmod): la causa era `cphy_rx` a 19,2 MHz arrastrado desde el ciclo 2; con 400 MHz 20/20 buffers completos, patrón de barras perfecto, imagen real a oscuras que responde a exposición. Informes `CAMARAS-C5-CICLO16/17-RESULTADO-20261022.md`. **Próximos 3 pasos:** (1) foto con luz (trasera mirando a algo); (2) enfoque VCM + demosaico; (3) libcamera/softISP y frontal.
> - **21-oct 21:2x — AUDIO COMPLETO: altavoces + micro persistentes** (commit `3aeb8a3` y siguientes): la tarjeta combinada e9a (TDM FS19xx + captura WCD9395) se carga SOLA al arrancar con fallback automático a e8b; ruta de micro amic1 aplicada; fuente PipeWire «Micro interno (UKE)»; el dueño oye el tono y el micro graba (`MICROFONO-M3-RESULTADO-20261021.md`). Interruptores: `/etc/uke/no-audio-amps` (apaga la etapa 2) o borrar `uke-audio-amps.service.d/e9a.conf` (vuelve a e8b). **Próximos 3 pasos:** (1) comprobar en el próximo reinicio que `uke-mic` se crea solo; (2) mapa físico de micros con `mic/auto/` (orden del dueño); (3) calibración acústica de altavoces y micro con el móvil (el dueño dará control).
> - **21-oct — MICRÓFONO: funciona (M3)**: e9a (altavoces TDM + captura del WCD9395) cargada en caliente sin oops; el WCD9395 se adjunta por SoundWire con un regulador fijo para `vdd-mic-bias` (el kernel de la uke no registra el BOB); PCM `hw:UKE,2` S16/48 k/2 ch, micro mono en el canal 0; ruta mainline ADC1+SWR_MIC0 con señal real (amic1/amic4); rutas del vendor = EIO. Informes `MICROFONO-M1-RESULTADO-20261021.md` y `MICROFONO-M3-RESULTADO-20261021.md`. **Preparado, sin aplicar** (la tablet está fuera de uso): persistencia de e9a al arrancar con fallback a e8b (`mic/deploy-persist-e9a.sh`), UCM «UKE», `51-uke-mic.conf`, mapa de micros (`m3-guion.sh`). **Próximos 3 pasos:** (1) aplicar la persistencia en un ciclo con reinicio; (2) mapear los micros (silencio/inferior/superior/espalda) con amic2/3/5; (3) UCM/PipeWire del micro y calibrar el nivel de los altavoces con el móvil.
> - **20-oct — AUDIO DE LOS ALTAVOCES INTERNOS: HECHO en ouke5** (suena tras arranque en frío sin intervención y lo confirma el dueño; informe `build/gates/revision/AUDIO-ALTAVOCES-CIERRE-20261020.md`, commit `3c1e18a`). `uke-audio.service` + `uke-audio-amps.service` habilitados (VERDES solos), `snd-q6apm` parcheado en `updates/`, PipeWire con `uke-speakers` (×0,25, límite ±0,3, `nofail`) como sumidero predeterminado; tope `uke_fs_volmax=0xE0`. Causa del mudo: tabla PLL de los FS19xx leída con desplazamiento (6,144 MHz = `0x0260/0x0540/0x0018`, traza I²C de Android). Acceso a la tablet por `ssh root@uke` (Tailscale); USB de respaldo. **Próximos 3 pasos (audio):** (1) prueba térmica con música continua en tramos 1/5/15 min con cargador de pared (sin FSADSP, solo protegen el tope y el limitador); (2) comprobar canal izq./der. y escena 0 (`FS19XX Scene`); (3) gancho de tarjeta tardía y `fuse` en `modules-load.d` (preparados en PC, pendientes de instalar). Módulos ouke4 intactos en `out/` (rollback); ouke5 en `out-ouke5/`.
> - **21-oct 21:3x — BT: sesión cerrada con sus PENDIENTES documentados** en `build/gates/revision/BT-SENEMOS-20261018.md` («PENDIENTES (para retomar)»): (1) medidas del chip mudo H1/H2 con el parcheado ya desplegado, (2) consumo en suspensión (USB desenchufado), (3) que el audio suene tras reanudar (lo confirma el dueño). Nada de eso corre sin orden del dueño.
> - **21-oct 21:20 — BT en el 1.er ARRANQUE EN FRÍO con el `hci_uart` parcheado (reinicio de audio 21:12): `uke-bt` VERDE tras 1 reintento del driver (27,3 s), `hci_uart` desde `updates/`, `hci0` encendido, auriculares y lápiz reconectados solos** (solo lectura). Antes: **21-oct 21:07 — BT: SUSPENSIÓN DE 25 s CON AURICULARES VERDE con el gancho/ayudante nuevos** (durmió 25 s, `pm_wakeup_irq=183`, `suspend_fail=0`, adaptador a 1 s, **auriculares reconectados solos a los 5 s**, 0 faults). Antes: **BT DESPLEGADO en la tablet (ouke5/v6) y CONSUMO DESPIERTO MEDIDO**: `deploy.sh --go --service --sleep --hciqca` hecho por USB (hashes en la tablet: `uke-bt-up.sh` `3e493c5f`, `uke-bt-sleep` `90930b33`, `uke-bt-resume` `e9d026e0`, `bt-medir.sh`, `bt-consumo.sh`; WiFi/adsp IGUAL). **El `hci_uart` parcheado va en `updates/`, no en `extra/`** (Arch: `search.conf` = `updates extramodules built-in`; el 1.er despliegue abortó por eso; `BT-MUDO-FIX-20261021.md` §10); `sha256 493ef41c951f…` == `out-hciqca/hci_uart.ko`; **ya cargado en hardware con los defaults (= serie): 3 encendidos VERDE, 0 faults**. Consumo despierto (`bt-consumo.sh`, 3 rep.; log `build/logs/bt-ciclo-20261021-bt2/`): `bt_down` −0,034 ± 0,018 W y `bt_off` −0,016 ± 0,035 W → **no significativos (< 0,1 W)**; las 2 primeras fases se descartan (escalón de 1,3 W a las 20:43 = fin del test M3b de audio, que usaba la tablet a la vez). **Suspensión**: el 1.er intento NO durmió (`systemctl suspend`: «active block inhibitor» por `uke-idle-guard`, que inhibe el reposo mientras haya CUALQUIER sesión SSH; la captura `ssh root@uke dmesg -w` de la sesión de audio lo mantiene); el orquestador ahora lo detecta. Audio cerró su captura y la suspensión se repitió: VERDE (ver arriba).
> - **21-oct 14:2x — BT: TODO LISTO PARA PROBAR EN UN CICLO cuando vuelva la tablet (solo PC; tablet sin tocar por orden del dueño)**: gancho `uke-bt-sleep` más robusto (guarda solo auriculares/audio, rutas rápidas, `/etc/uke/bt-keep-on`, un único `bluetoothctl show` con `timeout`), `uke-bt-resume` con **recuperación del chip mudo** (`--down` + ciclos) y reconexión por MAC, `hci_uart` parcheado (W=1 sin warnings nuevos; control == serie), herramientas de medida (`bt-medir.sh`, `bt-consumo.sh`) y el orquestador `ciclo-prueba.sh` (compuertas USB/ACM/vermagic/batería + etapas deploy→medir→carga→suspensión→consumo). `build.sh` RESULTADO: OK (103+51+17+61+32 comprobaciones + hciqca/consumo). **En la tablet siguen las versiones anteriores** (hook `279361b3`, `uke-bt-up.sh` `d5caf4dd`); el despliegue (`--service --sleep --hciqca`) y las medidas necesitan orden del dueño. Documento para el dueño: `build/gates/revision/BT-ESTADO-PARA-EL-DUENO-20261021.md` (estado, ciclo, 3 decisiones, límites).
> - **21-oct 01:40 — el log persistente muestra 0 mudos en los 9 arranques de ouke5 (incl. v6 #6, VERDE a la primera); ouke4 tenía 4 de 10** (p = 0,087). El «mudo en v6» no consta en el log. La prueba con el `hci_uart` parcheado sigue lista pero su urgencia baja; no desplegar nada nuevo es razonable mientras no vuelva a verse un mudo. Detalle en `BT-MUDO-FIX-20261021.md` §8. Antes: **BT mudo: arreglo propuesto y prueba LISTA en el PC (tablet sin tocar; la tiene audio para M1)**: hipótesis de carrera con los 50 ms de `hci_qca` (el 1.er comando sale con el control de flujo apagado). Preparado sin desplegar: `hci_uart.ko` parcheado con tiempos ajustables (defaults = serie) + `deploy.sh --hciqca` + `bt-medir.sh` + `analiza-medicion.py` (todo con arnés verde). Falta: tablet libre ~25 min, USB+ACM, **orden del dueño** (`deploy.sh --go --service --hciqca` y `bt-medir.sh`); leer antes el log del mudo en v6. Plan y criterios en `build/gates/revision/BT-MUDO-FIX-20261021.md`.
> - **20-oct 21:30 — ouke5 en frío con módulos instalados: BT, WiFi, escritorio y altavoces ARRANCAN SOLOS** (leído por Tailscale): `uke-bt` VERDE a la 1.ª (0 timeouts, 25,9 s), `hci0` `Powered: yes`, lápiz conectado, 0 avisos `org.bluez`, WiFi conectado (192.0.2.11), `uke-audio-amps` activo, `verify` 20/0, sin faults. La opción A (ciclos) no hizo falta en este arranque; sigue verificada solo en el bucle de 12 encendidos. BT del día a día cubierto también en ouke5.
> - **19-oct 23:2x — tablet en ouke5 (reinicio del dueño); BT ARRANCADO A MANO y VERDE a la primera** (`systemctl restart uke-bt.service`, 0 reintentos, `hci0` `Powered: yes`, 0 faults). En el arranque `uke-bt` y `uke-wifi` fallaron porque los módulos de ouke5 (incluidos los `.ko` BT) se instalaron 5 min después de arrancar. **WiFi sigue sin asociar** (NetworkManager inactivo; no tocado, es de la sesión del WiFi). Falta un arranque en frío en ouke5 con los módulos ya instalados para ver BT/WiFi arrancar solos (y la opción A de reintento por ciclos en un arranque real).
> - **19-oct 23:0x — BT listo para el ciclo ouke5 (solo PC; nada flasheado)**: `uke_bt_{uart,b,a}.ko` recompilados contra el árbol ouke5 (`build.sh` OK), vermagic `…-ouke5` en `deploy/bt/out/`; los de ouke4 quedan en `deploy/bt/out-ouke4/` (rollback). `deploy.sh` ahora acepta `UKE_BT_OUT` y se niega si `KB` y `out/` no casan. Detalle en `NOTAS-OMARCHY.md`. Sigue pendiente el reinicio en frío de verificación de la opción A (cuando el dueño lo pida).
> - **19-oct 17:10 — opción A VERIFICADA en un bucle de 12 encendidos (sin reiniciar): 12/12 VERDE y un ciclo mudo rescatado en hardware real** (iteración 5: 4 timeouts, `--down`, 2.º ciclo OK a los 28 s); éxito por intento 55 % en reposo frente a ~28 % en arranques. BT arriba, lápiz conectado. Pendiente: verificar el camino de arranque con hasta 3 reinicios en frío (de uno en uno, con orden del dueño). Antes: **17:01 — opción A DESPLEGADA en la tablet** (`deploy.sh --go --service --wait`, hashes idénticos; unidad `enabled`, `UKE_BT_CYCLES=3`; no arrancó nada). Verificación pendiente (bucle de encendidos + reinicios en frío) con orden del dueño. Antes: opción A implementada en el PC: `uke-bt-up.sh` hace `--down` + nuevo encendido hasta 3 ciclos si el driver se rinde (`UKE_BT_CYCLES=3` en la unidad); `uke-bt-wait` espera hasta 70 s mientras `uke-bt` siga activando. Arnés verde (95 + 17 + 34 + sim). **Falta orden del dueño** para `deploy.sh --go --service --wait` y verificar con arranques en frío. Detalle en `BT-MUDO-20261019.md` §5.
> - **19-oct ~10:30 — BT RECUPERADO SIN REINICIAR e investigado (informe `BT-MUDO-20261019.md`)**: un `--down` + encendido medido en estado mudo respondió a la 4.ª tentativa del driver; `hci0` `Powered: yes`, auriculares reconectados (`uke-bt.service` queda `failed` de arranque hasta `reset-failed`). Estadística: 5 de 17 arranques mudos (29 %); el chip se enciende siempre (SW_CTRL/CTS) y solo falla la 1.ª respuesta a `0xfc00` (todo o nada); WL_EN/rails/firmware descartados. Hipótesis: carrera con los 50 ms de `hci_qca`. Opciones A (reintento por ciclos en el script), B (parche del retardo del kernel), C (medir la tasa con ciclos `power off/on`): decide el dueño.
> - **19-oct 10:24 — el reinicio en frío NO recuperó el BT**: `uke-bt` ROJO otra vez (4.º mudo en 13 arranques, 2.º seguido); `btmgmt` 0 controladores. La sesión del lápiz sigue esperando `hci0`. Siguiente (con orden del dueño): medir el estado durante un intento de encendido y/o apagado completo de la tablet (corte real de rails) en vez de otro reinicio.
> - **19-oct ~10:15 — Linux vuelve de Android (captura de audio) con el BT MUDO otra vez** (`uke-bt` ROJO, 4 × `0xfc00 tx timeout`; `bluetooth.service` activo sin controlador; ficheros intactos tras la restauración). Tercer mudo en 12 arranques en v4. Captura del BT de Android en `build/android/bt-20261019/` (mismo firmware; secuencia `btpower`: WL_EN=1 antes de BT_EN; WL_EN igual en Linux y Android → **descartado como causa**). **Falta**: medir el estado durante un intento de encendido (SW_CTRL/BT_EN/rails/rx de la UART) y recuperar con reinicio en frío; ambos con orden del dueño. La sesión del lápiz espera hci0.
> - **19-oct — D2 HECHO (confirmado por el dueño con el botón de encendido)**: audio sonando → suspender → despertar: los auriculares reconectan solos y suena. Gancho `uke-bt-sleep` + `uke-bt-resume` instalados y verificados (18-oct 21:25: 26 s dormida, reconexión a los 4 s, `pm_wakeup_irq=184`). **BT del día a día cubierto**: panel, A2DP, reconexión tras reinicio y tras suspensión. Quedan: D3 (consumo, hay que desenchufar), suspensiones largas, y la causa del chip mudo ocasional en frío (2 de 9 arranques en v4, se recupera con otro reinicio). Detalle en `BT-DIARIO-PLAN-20261018.md`.
> - **19-oct 10:4x — BT estable en los dos últimos arranques (tras reinicios de la sesión de audio): VERDE (2 reintentos y 0 reintentos), `hci0` `Powered: yes`, 0 avisos de `org.bluez`; el `Xiaomi Focus Pen` consta conectado.** Gancho `uke-bt-sleep` instalado. En v4: 9 arranques en frío, VERDE ×7, chip mudo ×2 (recuperados con otro reinicio). Pendiente: que el dueño confirme que suena el A2DP tras suspender con el botón; D3 (consumo); WiFi `DISCONNECTED` (preexistente, no es del BT).
> - **21:3x — BT RECUPERADO (reinicio en frío 21:22: VERDE tras 2 reintentos) y D2 CON AURICULARES OK**: suspensión de 26 s (21:25:02 → 21:25:28, despertar por la alarma RTC), `uke-bt-sleep` apagó el adaptador, `uke-bt-resume` lo encendió y **reconectó los auriculares a los 4 s**; sin faults. `hci0` `Powered: yes`, `bluetooth.service` activo, gancho instalado (`279361b3…`).
>   Pendiente: que el dueño confirme que **suena** el A2DP tras reanudar, D3 (consumo). El chip mudo en frío (2 de 7 arranques en v4: 17:03 y 21:12) se recupera con otro reinicio; causa sin determinar. WiFi sigue `DISCONNECTED` (preexistente, escaneo atascado; no es del BT). Detalle en `BT-DIARIO-PLAN-20261018.md`.
> - **21:2x — D2 FUNCIONA (sin auriculares): con el gancho corregido s2idle duerme los 25 s** (21:18:35,843 → 21:19:01,951; `pm_wakeup_irq=184` = alarma RTC; `suspend_stats` ok=1 fail=0; sin faults). La causa del despertar instantáneo era el IRQ del RX de la UART del BT (GPIO 43): `pre` pone `disabled` el `power/wakeup` de `888000.qcom,qup_uart` y `post` lo restaura; además `uke-bt-resume` ahora corre vía `systemd-run` (antes lo mataba el cgroup de `systemd-suspend.service`).
>   Gancho **instalado** en la tablet (`279361b3…`). **Falta** la prueba con auriculares (reconexión al reanudar): el chip del BT está **mudo** en este arranque (`uke-bt` AMARILLO, `btmgmt` 0 índices; 2 de 6 arranques) y hace falta un reinicio en frío y que el dueño encienda los auriculares. WiFi `DISCONNECTED` (escaneo atascado, preexistente, no tocado). Detalle en `BT-DIARIO-PLAN-20261018.md`.
> - **21:0x — el BT cargado impide dormir (s2idle despierta a los 0,7 s por el IRQ 229 = GPIO 43, RX de la UART del BT; aviso de la sesión de la tapa, confirmado en solo lectura)**. El gancho `uke-bt-sleep` (D2) apagaría el adaptador antes de dormir, pero **no está instalado y no está probado**: necesita orden del dueño (`deploy.sh --go --sleep` + prueba corta de suspensión). Detalle en `BT-DIARIO-PLAN-20261018.md`.
> - **17:4x — BT RECUPERADO con otro reinicio en frío (17:39) y espera v2 verificada**: `uke-bt` VERDE (1 reintento del driver), `hci0` `Powered: yes`, **auriculares reconectados solos**, Quickshell arrancó a 32 s con 0 avisos de `org.bluez`, WiFi bien, `verify` 19/0. Del 17:3x queda el ROJO aislado (chip mudo, `--down`+`restart` no lo arregló; causa sin determinar; 1 de 5 arranques en v4).
>   **Falta la prueba del panel de la barra con el dedo** (la hace el dueño); D2 (suspensión, gancho `uke-bt-sleep` sin instalar), D3 (consumo) pendientes. Detalle en `BT-DIARIO-PLAN-20261018.md`.
> - **17:3x — BT sin adaptador en este arranque; intento de recuperación sin reiniciar FALLIDO**: `uke-bt-up.sh --down` + `systemctl restart uke-bt.service` (orden del dueño) → otra vez 4 × `0xfc00 tx timeout`; la UART tiene `tx:20 rx:0 brk:2`: **el chip está mudo** (no baudios). 0 faults, WiFi intacto.
>   Pendiente de orden: otro reinicio en frío (3 de 4 arranques en v4 salieron VERDE) y/o leer `BT_EN`/rails con debugfs. El panel no tiene adaptador hasta entonces. Detalle en `BT-DIARIO-PLAN-20261018.md`.
> - **17:1x — corrección v2 de la espera del escritorio DESPLEGADA y reinicio en frío hecho (17:03): la espera funciona** (Quickshell arrancó a 44,8 s con `org.bluez` ya con PID: 0 avisos), `verify` 20/0, WiFi y `bluetooth.service` bien. **Pero `uke-bt.service` salió ROJO y no hay `hci0`**: el chip no respondió a 4 intentos (`0xfc00 tx timeout`, 24–33 s); es el primer ROJO real con el colchón de 8 s (antes VERDE ×3).
>   El panel no tiene adaptador hasta que se arranque el BT (`systemctl restart uke-bt.service` lo recuperó antes) — **pendiente de orden del dueño**; hardening propuesto: reintento por ciclos completos en `uke-bt-up.sh`. Detalle en `BT-DIARIO-PLAN-20261018.md`.
>   (16:5x: el primer `--wait` no esperaba porque `busctl list` muestra `org.bluez` también como solo activable; corregido en `7c073c7`.)
> - **16:2x — BT del día a día (D0+D1 hechos; informe `BT-DIARIO-PLAN-20261018.md`)**: `bluetooth.service` **habilitado** (tras `uke-bt.service` por drop-in, `AutoEnable=true`), arrancado a mano; el panel `omarchy.bluetooth` de la barra
>   **lista, empareja y conecta con el dedo y suena** (el dueño). Ojo: Quickshell no se reengancha a BlueZ si arrancó antes que `bluetoothd` (hubo que `omarchy-restart-shell`); en frío la carrera se espera resuelta por la activación por D-Bus,
>   **sin verificar** (D4, reinicio aparte). Pendiente D2 (gancho de suspensión `uke-bt-sleep`, escrito y probado con mocks, NO instalado), D3 (consumo), D4 (reinicio en frío).
> - **15:3x — sobre el kernel v4 (`7.2.9-senemos.1.4054.3-ouke4`, flasheado por el dueño)**: `uke_bt_{uart,b,a}.ko` recompilados para ouke4 (commit `82aa1fa`, vermagic verificado) e instalados
>   en `/lib/modules/…ouke4/extra` con `deploy.sh --go --module` (depmod de ouke4; el árbol ouke3 intacto). Tras el arranque v4 `uke-bt.service` había fallado (faltaban los .ko, salida limpia, guarda `ok`);
>   `systemctl restart uke-bt.service` → **VERDE al primer intento**, `QCA setup on UART is completed`, UART por DMA `tx:118912 rx:2251` **sin ningún fault SMMU** con los parches 0002+0004 del v4;
>   WiFi 150/150 pings, rails y `s2` como en v3. Pendiente: reinicio en frío en v4 para ver el BT arrancar solo; los .ko ouke3 siguen en el commit `31fbf3f`.
> - **Medido en vivo (informe `build/gates/revision/BT-SENEMOS-20261018.md`, B0–B6)**: overlay de DT en caliente (módulo `uke_bt_b`, sin flash) → UART
>   `ttyHS0` + serdev `serial0-0` → `hci_uart` → chip WCN6750 ROM 1.2 con `qca/msbtfw12.mbn` + `msnv12.bin` en ~2 s (`QCA setup on UART is completed`);
>   auriculares emparejados por **BR/EDR** (descubrir con `scan bredr`: por LE solo no hay A2DP), A2DP **AAC**, 31 min de stream sin cortes ni xruns,
>   WiFi 1860/1860 pings sin pérdida, el dueño **oyó** el tono. Sin rail PA (`pmr735a_s3` no está en la lista de `qcom-rpmh-regulator-uke.c`; dummy) el alcance es suficiente.
> - **Persistencia (B7, 12:0x)**: `uke-bt.service` `enabled` (After=uke-wifi, guarda `uke-bootguard bt`, interruptor `/etc/uke/no-bt`); probado con `systemctl start` (VERDE,
>   guarda `ok`). **Reinicio en frío (12:02) hecho: `deploy/arranque verify` 19/19, hci0 arriba, pero `uke-bt.service` = `failed`**: en frío los 2 primeros
>   intentos de encendido del chip expiraron (`command 0xfc00 tx timeout`) y el 3.º funcionó (`setup completed` a 28,1 s); `uke-bt-up.sh` declaró ROJO antes de tiempo (falso positivo,
>   corrección preparada en PC por la sesión B0, sin desplegar; posible causa: BT encendido 0,3 s después de uke-wifi). La blacklist de `hci_uart` se queda. `bluetooth.service` **sigue deshabilitado** (se arranca a mano: `systemctl start bluetooth.service`).
>   Tras el arranque el chip queda configurado y `hci0` se apaga solo a los ~3 s sin `bluetoothd`. Dirección BD aleatoria local en `/etc/modprobe.d/uke-bt.conf` (modo 600, no versionada).
> - Efecto sobre rails medido: BT on = `s2` pasa de `standby` a `fast` (umbral de carga 200 mA), `s3` +4 usuarios; el WiFi no lo nota.
> - **Pendiente**: (1) [HECHO 12:02, ver arriba]; (2) decidir si se habilita `bluetooth.service` al arranque;
>   (3) kernel v4 (`BT_RFCOMM` para HFP/mic, rail `smpe3` si el alcance lo pide); (4) medir alcance en metros (hoy solo "suficiente" a juicio del dueño); (5) BT + suspensión s2idle.
>   **12:15: corrección desplegada y 2.º reinicio en frío: `uke-bt.service` active/success, `setup completed` a 32,3 s al primer intento (colchón `UKE_BT_SETTLE=8`), `verify` 19/19.**
>   Material en `build/rootfs/deploy/bt/` (`build.sh`, `deploy.sh --check`); revertir: `deploy.sh --go --revert`. Sin commit todavía.

# ESTADO VIVO — 18-oct ~01:15 (senemos v3: TODO ARRANCA SOLO — pantalla, USB/SSH, carga, WiFi, GPU, Omarchy y táctil)

> - Reinicio en frío verificado (19/19) y confirmado por el dueño: escritorio Omarchy en el panel y táctil respondiendo.
>   Orden: carga 7,6 s → WiFi 26 s → escritorio 26,6 s (GMU 28,7 s); táctil con recarga automática tras el reset del panel.
> - Interruptores sin reflashear: /etc/uke/{no-wifi,no-desktop,no-touch,safe-mode}; uke-bootguard omite un componente tras
>   2 arranques fallidos seguidos.
> - **Suspensión s2idle validada** (`systemctl suspend`; ver deploy/suspension). Pendiente: audio (E0 hecho, E2 con orden), Bluetooth, aviso WiFi de Omarchy (NetworkManager),
>   backlight dual (KTZ ×2), lápiz, consumo vs. carga con el USB del PC (bajó 78→67 %), reintentos de slot tras reboots.

# ESTADO VIVO — 18-oct ~00:0x (senemos v3 FLASHEADO: display + USB/SSH + carga + GPU AL ARRANQUE; ledger #660 PASA)

> - Aparato: slot a, **boot_a = v3 `5c9fb2c6…`** (`7.2.9-senemos.1.4054.3-ouke3`, releído), dtbo_a stock `27e61d21`, rootfs 8 GiB
>   con módulos ouke2+ouke3 y Omarchy instalado. fastboot antes: 4099 mV, retry a=7 b=6. Fastboot SIEMPRE manual.
> - Al arranque: panel (underrun 0), USB/SSH, carga (uke-carga, Charging), **GPU con IOMMU y renderD128** (GPU = card0,
>   display = card1). La sesión Omarchy NO arranca sola (cmdline multi-user): `deploy.sh start --go`.
> - WiFi: no arranca solo (uke-wifi.service sin habilitar; wpa_supplicant@wlan0 parado antes del flash).
> - **18-oct ~00:0x: Omarchy (Hyprland sobre la GPU) y WiFi funcionando sobre v3** (.link arreglado: Driver=ath11k).
> - **WiFi y escritorio habilitados al arranque** (uke-wifi/uke-desktop + uke-bootguard; interruptores /etc/uke/*), hora
>   Europe/Madrid con chronyd. **Sin probar en frío.** Audio: investigado (todo por el ADSP). **Táctil FUNCIONA y es persistente** (uke-touch.service; recarga el firmware tras cada reset del panel; probado DPMS).
> - Próximos 3 pasos: (1) reinicio de prueba (WiFi + escritorio + táctil al arranque) + `deploy/arranque/deploy.sh verify`;
>   (2) audio E0 (sesión aparte) → E2; (3) aviso WiFi de Omarchy / NetworkManager (decisión del dueño).

# ESTADO VIVO — 17-oct ~23:5x (igual que abajo + KERNEL v3 PREPARADO, sin flashear)

> **v3 listo (ledger #660 pre-registrado):** `boot-uke-senemos-7.2.9-v3.img` sha `5c9fb2c6…` = ouke2 + `CONFIG_SM_GPUCC_CLIFFS=y`
> (GPU al arranque). Procedimiento: `bash build/gates/flash-senemos-v3-gated.sh --pre` (en v2) → fastboot manual → script sin
> argumentos (1 escritura boot_a). Guarda del repo ya sin gpucc (se aplica a la tablet en `--pre`).

# ESTADO VIVO — 17-oct ~23:2x (senemos v2: PANEL + USB/SSH + CARGA + WIFI + GPU; OMARCHY (Hyprland) EN MARCHA)

> **17-oct ~23:2x — Omarchy corriendo sobre la GPU (freedreno), en caliente.** GPU por E1 (reprobe de kgsl-smmu + adreno;
> causa: -110 del SMMU de la GPU al llegar tarde gpucc_cliffs =m) y primer open sin cuelgue (GMU fw v4.5.1). Hyprland +
> quickshell vivos, fdinfo msm con tiempo de GPU, underrun 0. Captura: `build/logs/capturas/omarchy-gpu-primera-20261017.png`.
> NADA de esto sobrevive a un reinicio salvo carga: GPU necesita kernel v3 (`CONFIG_SM_GPUCC_CLIFFS=y`, quitar gpucc de la
> guarda); WiFi necesita habilitar `uke-wifi.service`; la sesión arranca con `deploy.sh start` (cmdline multi-user).
> **El dueño CONFIRMA el escritorio de Omarchy en el panel (~23:3x).** Próximos 3 pasos: (1) kernel v3 GPU built-in;
> (2) WiFi y escritorio al arranque; (3) táctil, audio, BT, backlight dual (KTZ x2).

# ESTADO VIVO — 17-oct ~22:5x (senemos v2: PANEL + USB/SSH + CARGA + WIFI; Omarchy instalado, sin GPU)

> **17-oct ~22:5x — en vivo sobre senemos v2 (mismo arranque, sin reflashear).**
> - **Carga OK**: `uke-carga.service` (ADSP running, `qcom-battmgr-bat` Charging) — habilitado tras probar el start a mano.
> - **WiFi OK**: `uke-wifi-up.sh --no-net` (WPSS running, ath11k fw WLAN.MSL.3.0-00642, wlan0) + `wpa_supplicant-nl80211@wlan0`
>   → red 5 GHz, DHCP `192.0.2.12`, ping/DNS OK; NTP sincronizado. MAC fija en el .link (ath11k la deja a ceros).
>   NO persiste tras reiniciar: `uke-wifi.service` sin habilitar (armado de un solo uso pendiente de decisión).
> - **Omarchy instalado** (342 pkgs) pero **la sesión cae**: sin GPU no hay render node (EGL `initEGL` aborta) y llvmpipe da
>   SIGILL por SVE (firmware lo oculta). GPU: `gpucc_cliffs` carga OK, pero `adreno … failed to load adreno gpu` (sin cuelgue).
>   Diagnóstico en curso → `build/gates/revision/GPU-SENEMOS-20261017.md`.
> - Guardas de autoload: ath11k, `uke-carga.conf`, `uke-senemos-guard.conf` (gpucc/hci_uart/coresight/cpucp/qcomtee).
> - Próximos 3 pasos: (1) GPU (freedreno) según el diagnóstico; (2) sesión Omarchy sobre la GPU; (3) decidir WiFi al arranque.

# ESTADO VIVO — 17-oct ~22:0x (KERNEL MCC45TR "senemos" v2: PANEL CON IMAGEN + USB/SSH; underrun 0)

> **17-oct ~21:5x — senemos v2 VIVO (ledger #658 hito + #659 resultado).**
> - Aparato: **Linux en slot a**, `boot_a` = **senemos v2 `7848d68d…`** (release `7.2.9-senemos.1.4054.3-ouke2`),
>   **dtbo_a = STOCK `27e61d21…`** (su `uke-abl.c` rechaza s288), userdata = rootfs 8 GiB `7e4309f0…`. slot b intacto.
>   fastboot antes del flash: 4222 mV, retry a=7 b=6. SSH `192.168.42.129` OK. Fastboot SIEMPRE manual (Power+Vol-).
> - **#658 (v1 `4894a841`)**: primera imagen del panel en todo el proyecto: terminal + `uke-arch login`; sin USB.
> - **#659 (v2)**: un cambio = overlay USB sin `usb-psy-name` (dwc3 diferido esperando a `qcom-battmgr-usb`). USB/ACM/NCM a
>   los 10 s, UDC configured; **modetest plano+page-flip 120 Hz: patron SMPTE visible, underrun 0 en 1440 vsync**
>   (nuestro L77b: 1441/1440). Informe `build/gates/revision/SENEMOS-V2-USB-20261017.md`.
> - En vivo (sin reinicio): modulos ouke2 (1105 .ko) en /lib/modules + depmod; guardas modprobe ath11k + `uke-carga.conf`
>   (qcom_q6v5_pas/apr/fastrpc/ucsi_glink/altmode). Reloj puesto a mano (sin RTC/NTP). Carga AUSENTE (uke-adsp falla).
> - Proximos 3 pasos: (1) carga (`build/rootfs/deploy/carga/deploy.sh`), (2) WiFi (`build/rootfs/deploy/wifi/deploy.sh`,
>   tras la carga), (3) Omarchy+GPU; en paralelo `QUE-NOS-FALTABA-20261017.md` (medida senemos vs L76R vs vendor).

# ESTADO VIVO — 17-oct ~18:4x (L76R + rootfs 8 GiB ARRANCAN en slot a; registros = vendor; NEGRO CON LUZ; carga OK)

> **17-oct ~18:4x — L76R VIVO (ledger #654 resultado).**
> - Aparato: **Linux en slot a**, `boot_a` = **L76R `f75a27fd…`** (releido), dtbo s288, userdata = rootfs 8 GiB `7e4309f0…`
>   (+16 paquetes libdrm/cairo instalados en vivo para modetest). SSH `192.168.42.129` OK. Android de slot b ya NO es
>   arrancable sin `erase userdata`+`erase metadata` (LV-R1).
> - **Gates: todos los registros DSI/INTF/DSC/PPS/orden = vendor**; S4-DIAG 0; CARGA 4/4 (Charging). **Visual: NEGRO CON LUZ.**
> - Nueva pista: **underrun 21/vsync 22 en encoder-0** (≈1 por frame), frame_done 0 → el problema esta en el FETCH del DPU
>   (SMMU del display / ICC: faltan qnm_mdp-qns_llcc y qhs_display_cfg del vendor / QoS), no en el enlace con el panel.
> - Proximos pasos: (1) zero-flash: medir underrun/vsync con vblank activo y faults del SMMU del display (K38/K39) durante
>   modetest; (2) L77 = rutas ICC del display + votos MMCX + broadcast HW (C6); (3) KTZ dual en el driver.

# ESTADO VIVO — 17-oct ~12:3x (Android slot b; L76 "paridad vendor" CONSTRUIDO, sin flashear)

> **17-oct ~12:3x — capa CAPTURA VENDOR + L76 (sesion unica; la del panel ya no existe).**
> - Aparato: **Android HyperOS slot b**, root Magisk, adb `192.0.2.13:5555`; `boot_a` = **L74 `06a1d9fe…`**
>   (verificado por sha leyendo la particion). BCB a ceros. Rootfs Arch de userdata PERDIDO (#653): hay que
>   reinstalarlo antes de arrancar cualquier L7x.
> - **Hallazgos medidos en el vendor funcionando** (`build/android/vendor-harvest-20261017b/README.md`):
>   widebus ON + **RGB101010** (VID_CFG0 0x02009140), ACTIVE_H 427 / TOTAL 0x0905023b, INTF_1 572/CONFIG2 0x1011
>   (el "mundo 24" 534/0x090502a6 de L71-L75 era una DERIVACION, nunca medido); PPS unica tras 0x29 con
>   **pic_width 3200 en cada link** (nosotros 1600); ENC_DF_CTRL 0x095c1203; video ON tras la PPS y TE solo INTF_1;
>   DCS por broadcast HW (L77). Informes: `build/gates/revision/*-20261017.md` (PLAN-KERNEL-PANTALLA, REGDIFF,
>   RE-DSI-ENABLE-ORDER, RE-DSI-CMD-FLAGS-SYNC, DCS-COTEJO, PARIDAD-CLK-ICC, DPU-VENDOR, KTZ-DUAL-S289).
> - **L76 construido**: `build/bootimg/boot-uke-k52L76.img` sha `1db4bd349875a21884fe98efde31339855b3b39837d6bc1e3f75f4a2c59c95c3`
>   (repack verde; `docs/historia/gates-palawan/flash-l76-gated.sh` con EB relleno, gates de registros vs vendor). NO flasheado,
>   NO pre-registrado en el ledger. Detalle: `build/gates/revision/L76-PREP-20261017.md`.
> - Backups de 19 particiones verificadas (incl. vbmeta_system): `build/backup-par-bueno/android-20261017/` (fuera de git).
> - Proximos 3 pasos: (1) reinstalar rootfs Arch en userdata; (2) pre-registrar L76 en el ledger y flashear boot_a
>   con orden del dueno; (3) L77 = broadcast HW + KTZ dual; L78 = votos MMCX/ICC display.
> - **17-oct ~13:0x — L76R** = L76 + ciclo de rieles (reset=0, vsn off, vsp off, 500 ms) antes del primer prepare, como el
>   wake del vendor (sleep20). `build/bootimg/boot-uke-k52L76r.img` sha `f75a27fdcae7e46ec76f0c4f5a8c5af652b8f24af65472ada4129dc2efe51073`,
>   repack verde (cmdline L74 622 B), vermagic igual (carga valida). `flash-l76r-gated.sh`: EB relleno, 19 gates de paridad +
>   4 de CARGA. Param: `panel_xiaomi_o82_dualdsi.uke_l76_rail_cycle` / `uke_l76_rail_off_ms`. Patch: build/gates/patches/l76r-rail-cycle.diff.
>   Carga (CARGA-REVISION-L76-20261017.md): kernel OK; el rootfs nuevo debe llevar 6 piezas (mods, firmware sin qcom/, manifest,
>   loader, unit, enable). NO flasheado ni pre-registrado.

# ESTADO VIVO — 16-oct ~13:0x (L73 FLASHEADO y ARRANCA: PPS OEM en vivo + freno anti-flood funciona; escritorio arriba; Charging; veredicto visual pendiente del dueño)

> **17-oct ~05:0x — capa RE NOCTURNA (esta sesión; la del panel sigue siendo la de arriba).**
> El aparato está **en Android (HyperOS OS3.0.303.0, slot b)** con adb inalámbrico y root
> (`192.0.2.13:5555`), **cargando a 4082 mV**; `boot_a` = **L74 `06a1d9fe…`** (+ dtbo s288)
> según el Resultado #652, y **L75 (PHY) lo prepara la otra sesión**. `misc` BCB limpio (medido
> por adb). Noche de RE completa fuera del panel: **12 informes** en
> `build/gates/revision/RE-NOCTURNO-20261017/` (índice `README.md`) — set de parches táctil
> `10–13v3` (W4: delta THP-body plegado + hook pen; dry-run 17/17), frame THP 5748 B + decoder, payload wifi v2 (`2b0dd75a…`), tablas C
> del fs19xx, spec BT/folio/sensores, plan Omarchy offline. Cerrados: GAP-1 del script de carga
> y **fila Resultado #653** del ledger. Bitácora: entrada 17-oct en `NOTAS-OMARCHY.md`.

> ⚠️ **CORRECCIÓN DE AUDITORÍA 13-oct-2026 (tarde).** Esta página está **caducada**:
> afirma que "L38 pendiente" y que "**NO existe ningún L39**" (líneas 16-26), pero el
> 13-oct se construyeron y flashearon **F10/dtbo-s281, L39 y L39d** (commits `6383cdd`,
> `af1ae94`, `0f3d000`, `9796bea`, `4e4e0d5`). Estado real: ver
> `build/gates/revision/L39-HALLAZGO-PANEL-LUZ-20261013.md` (panel emitió luz,
> testimonio sin log; tablet en reset físico pendiente) y
> `build/gates/revision/L39-RESULTADO-20261013.md`. Las capas del 12-oct/13-oct 00:3x
> de este fichero describen L19/L25/L33-L37 y **no son el estado del aparato**.

> **Lo que manda es el ledger**: `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` (#553–#651 resultado).
> Toda afirmación de esta página lleva fecha de medición. Lo que no se re-mida en 14 días → caducado.

## 16-oct ~13:0x — L73 EN SLOT A, VIVO; todos los gates lógicos verdes; falta el OJO del dueño

- **Par vigente**: slot a, **boot_a = L73 `a671d293…`** (flasheado 16-oct ~12:4x con 3414 mV, excepción
  del dueño) + dtbo s288 (sin tocar). SSH vivo (`192.168.42.129`, root, clave `build/rootfs/uke-arch-root`).
- **Gates medidos en vivo** (ledger #651 resultado): PPS con mundo OEM EXACTO
  (`UKE-L73: PPS[19]=B2 [23]=9F [27]=0D [29]=86 [58]=02`), mundo 24 vendor intacto (ACTIVE_H 534,
  TOTAL 0x090502a6, byte 148,648 MHz), ceil INTF ×2, PPS post-0x29 err=0.
- **Freno anti-flood (B2-A) FUNCIONA**: la condición FIFO persiste al commit (17 eventos/250 ms en
  ambos links) pero el log queda acotado: **26 líneas S4-DIAG total vs 143k/20 s de L71**. El sistema
  sobrevive al modeset.
- **Escritorio ARRIBA**: sddm estaba `disabled` → `systemctl start sddm` → greeter active →
  **Hyprland + quickshell vivos**. La pantalla está renderizando el shell de Omarchy —
  **el veredicto CONTENIDO/negro/garbage lo da el dueño mirando la pantalla**.
- **Carga VIVA**: 3ª corrupción de `adsp.b40` cazada por el loader endurecido (se negó a arrancar:
  correcto). Reparada en vivo: scp `charge/firmware/adsp.b40` (sha `42c86837…`) → **`/lib/firmware/`**
  (OJO: la ruta es SIN `qcom/`; el 1er intento fue a `/lib/firmware/qcom/` y no contaba) →
  uke-adsp active, adsp running, PDR 1, **Charging** (150 mA por USB-PC; con pared ~1 A).
  **Ritual anti-corrupción**: al abrir cada sesión, `sha256sum /lib/firmware/adsp.b40` == `42c86837…`.
- **Auditoría de carga** (16-oct, `build/gates/revision/CARGA-AUDITORIA-20261016.md`): stack completo
  y probado (5 boots Charging); condicionado a pared ≥45 W para recuperar de franja agotada.
- Pendientes: (1) veredicto visual del dueño — PASA=contenido; negro con gates verdes ⇒ rama PPS
  cerrada de verdad, residuo = PHY-RX/handoff/FIFO (RX-timings/LP_TIMER, ICC F2); (2) habilitar sddm
  (`systemctl enable sddm`) para que el greeter arranque solo; (3) arreglar `uke-charge-run.sh` para
  que copie `adsp-fw.sha256` (hoy el manifest vive solo en el PC); (4) rollback si hace falta
  (escritura futura): L71 `5e13addf…` / L70 `f2e820d2…`.

## 16-oct ~00:4x — L73 (composite panel) ARMADO; el flash único ABORTADO por el gate de batería

- **Estado del aparato AHORA**: fastboot `SERIE0001`, slot a, **boot_a = L71 `5e13addf…` SIN CAMBIOS**
  (el flash no llegó a ejecutar ninguna escritura). **Batería AGOTADA: 475–557 mV, `battery-soc-ok:no`**
  (4 lecturas 16-oct 00:2x; desplome en fastboot: a las 20:23 marcaba 3681 mV — la tablet pasó ~9 h
  en fastboot sin carga desde la sesión de la mañana). Es el caso #423 / 13-oct 21:0x: **NO escribir
  ni arrancar a esta tensión.**
- **Remedio (el documentado)**: cargador de pared ≥45 W, tablet en fastboot/apagada, HORAS (mejor
  toda la noche; `off-mode-charge=1` está). El USB del PC no carga en fastboot.
- **Cuando haya ≥3700 mV** → ejecutar el flash único ya armado:
  `bash docs/historia/gates-palawan/flash-l73-gated.sh` (1 escritura a `boot_a`; dtbo s288 se queda; rollback L71).
  **L73 pre-registrado #651** (sha `a671d293f738a6325bd18cb4a63a17a52c449b0af2e53adeb9700256960bd37d`,
  gates G0–G8 verdes, commit `1004ac9`). Lector ACM único ARMADO (`/var/tmp/uke-sesion-console.log`).
- **Qué es L73** (revisión por fases A1–A3 + B1–B4, informes
  `build/gates/revision/PANEL-REVISION-*-20261015.md`): k52L72 (mundo 24 sin toggle + ratelimit) +
  **FIX-1** quirk RC OEM del panel (flb=13 + `range_max_qp[0]`=8 + recompute en
  `dsi_populate_dsc_params`: corrige la PPS **y** el encoder DPU — el init 0x91 del propio panel
  certifica flb=13; nuestra PPS difería del OEM en 5 bytes) + **B2-A** freno anti-flood estilo vendor
  (16 eventos/250 ms, IRQ error no re-armada) + **B2-B** ratelimits + **B2-C** ceil INTF /24 (534).
  Criterio: `UKE-L73: PPS[19]=B2 [23]=9F [27]=0D [29]=86 [58]=02` + flood ~0 → **PASA = CONTENIDO**;
  negro sin flood ⇒ rama PPS cerrada de verdad (residuo: PHY-RX/handoff/ICC F2, próximo ciclo).
- **Resumen de la mañana 15-oct** (ledger #646–#650, consolidado en
  `PANEL-REVISION-A1-EVIDENCIA-20261015.md`): L67 BTA sordo (20 reads ret=0; el vendor tampoco lee
  este panel — B4: normal); L68–L71 flasheados; L71 clavó los 3 registros del vendor
  (ACTIVE_H 534, TOTAL 0x090502a6, byte 148,648 MHz) y aun así sin contenido; el flood (143k
  líneas/20 s) lo causa el toggle L68 (L67 sin toggle = limpio) y llenó el root al 100 % (adsp.b40
  recorrupto — 2ª vez; el script L73 lleva guarda-flood DPMS off >1500 líneas).
- **Deuda**: anotar el flash de L73 en el ledger cuando ocurra; adsp.b40/ukeinit: verificar sha al
  abrir cada sesión (corrupción silenciosa recurrente del rootfs sin journal).

## 15-oct ~02:2x — RE Android COMPLETO + L67 (BTA readback) LISTO; tablet apagada limpia

- **Tablet APAGADA limpia** (02:0x; batería 2,856 V cap 0, `Discharging` 166 mA sin pared;
  ledger #645). Para reanudar: **cargador de pared ≥45 W** (off-mode o arranca L66 → carga
  gestionada ~1,4 A probada); cuando haya batería + fastboot: `bash docs/historia/gates-palawan/flash-l67-gated.sh`.
- **L67 = L66 + BTA readback** (primera lectura DCS del proyecto: 0x0A/0x0B/0x0C/0x0D + 0x04 ×2
  links, LP, post-PPS, fail-safe). **boot `56e7b1e5…`** (100663296 B), pre-registrado **#646**;
  SOLO `boot_a` (1 escritura; dtbo s288 ya en slot a). Rollback L66 `1aa5a1f1…`. Carga preservada
  (mismo config `=m`/módulos/release `7.2.0-rc2-palawan`). Crítica del plan: `CRITICA-L67-20261015.md`.
- **RE Android cerrado** (`RE-ANDROID-GAPS-20261015.md`): SPLIT_LINK NO se programa (H2 muerto);
  PPS va al DDIC por vía única `0x0A` (sin `compression_mode`; §1c refutada); timing
  mainline==vendor salvo **widebus** (único bit abierto: mainline H=427 vs vendor H=534;
  discriminante 0-flash `devmem 0xae94028` con commit vivo → candidato nº1-bis tras L67).
  Decomp 3404/3404 funciones, 0 ausentes.
- **Ángulo DDIC** (`ANGULO-DDIC-20261015.md`): `0x0A` = oráculo de 3 bits (D7/D4/D2-D3); un `0x9C`
  cierra DCS+power entera y deja solo vídeo; test **VOID** si no hay línea `UKE-L63` (inherit).
- Pendientes operativos: `qbootctl` (hemorragia de slots) cuando haya SSH; pared; flash L67.

## 14-oct ~22:0x — L59 LISTO para flash (PPS DSC) — sha `e3511595…` (#638)

- La pantalla negra = el DDIC nunca recibía la **PPS de DSC** (host `dsc=85 85` activo; hunk L37
  perdido). L59 = porte L37+L40 + fix `ret`; gates verdes (`L37-pps`=3, `UKE-L37`=2); rollback L58.
- Para el flash: **USB re-enganchado + fastboot**. Criterio: **CONTENIDO en pantalla** + `UKE-L37`≥1.

## 14-oct ~21:0x — 🌅 HITO: ESCRITORIO OMARCHY EN PIE E ILUMINADO (L57)

- **L57 flasheado y funcionando**: luz automática (UKE-L56 a 4,27 s; KTZ 0x02=0x52),
  **MemTotal 7,2 GiB** (D16 aplicado), sddm+autologin omarchy → **Hyprland+quickshell vivos sin OOM**.
- Evidencia: `build/gates/revision/PIPELINE-PANEL-20261014/EVIDENCIA-DESKTOP-20261014.png`.
- Pendientes: touch/lápiz (probar), fcitx5, migraciones Omarchy, consolidación wifi/BT+zram
  (GENI + firmware; frags wifi wedgean — #601). Rollback L54 `1d641e63…`.

## 14-oct ~20:5x — D16 APROBADO (quitar mem=2048M): L56 (luz) pendiente de fastboot; L57 (RAM) en repack

- **Secuencia acordada**: **L56** sha `3e68abe8…` (PWM: luz en cada arranque) → verificar luz →
  **L57** (mismo kernel, sin `mem=2048M`; RAM completa) → escritorio omarchy (plumbing ya listo)
  → verificación `MemTotal` + sddm sin OOM. Rollback L57 = L56.
- Tablet ahora: greeter omarchy iluminado (sddm activo, autologin omarchy).

## 14-oct ~20:4x — L56 listo para flash + escritorio a un blocker (mem)

- **L56** (KTZ PWM_EN=0 en probe; luz en cada arranque): imagen `boot-uke-k52L56.img`
  sha `3e68abe8…`, pre-registro #632, repack verde, crítica PASA, **pendiente de fastboot**.
- **Escritorio**: plumbing listo (home/configs/autologin/disk/uke-dump); la sesión omarchy
  arranca y el **OOM por `mem=2048M`** la mata → **D16 pendiente de decisión del dueño**
  (Opción A: L57 repack sin mem → RAM completa; Opción B: swapfile). Greeter visible iluminado.
- Rollback: L54 `1d641e63…` / L53 `c6b64752…`.

## 14-oct ~12:1x — 🔆🔆 HITO: LA LUZ FUNCIONA (en vivo) — causa = PWM_ENABLE del KTZ8866

- Encontré y **confirmé en vivo** la causa raíz de la falta de luz: KTZ `0x02` bit0 (PWM_ENABLE)=1
  sin pulsos PWM ⇒ Standby (datasheet). Flip a `0x52` (I2C-only) + re-armo → **luz ON** (dueño);
  sysfs 307→0→4095→2048 («más brillo»); commit de vídeo con bit intacto.
- Tablet AHORA: encendida, iluminada, control de brillo vivo (`/sys/class/backlight/2-0011`).
- **Siguiente**: L56 = driver `ktz8866.c` limpia bit0 + re-armo en probe (prep en curso) → build
  → repack → flash → luz en cada arranque → reactivar `sddm` (escritorio Omarchy).
- Rollback vigente: L54 `1d641e63…` / L53 `c6b64752…`. L55 (DCS 0x51) superado y revertido.

## 14-oct ~19:1x — 🔴 #629 L54: negativo limpio (raíles descartados) → L55 = DCS 0x51 interno

- Cleanup bloqueado (`regulator: Not disabling unused regulators` + vsp/vsn enabled todo el boot)
  y **sin luz** ⇒ power-window descartada. KTZ descartado (L53). 
- **Siguiente (L55)**: backlight interno **DCS 0x51** (branch B, recomendación k52b2) — revert
  parcial del hunk L44 en el panel. Rollback L54 `1d641e63…`.

## 14-oct ~19:0x — 🟢 L54 (repack-only) listo para flash — sha `1d641e63…` (screen power-window)

- L53: KTZ = idéntico (ABL vs nuestro) en probe Y commit ⇒ chip descartado. Frente = raíles.
- L54 = mismo kernel + `regulator_ignore_unused` (632 B): preserva raíles registrados del ABL.
  Crítica PASA (no confirma AVDD — no registrado; screen de la familia). Positivo ⇒ bisect;
  negativo ⇒ branch B (DCS 0x51). Rollback L53 `c6b64752…`.
- **Falta**: fastboot (físico) → flash `boot_a` (cold boot restaura el UFS del rescate) → luz.

## 14-oct ~18:4x — 🟢 L53 (instrumento KTZ) listo para flash — sha `c6b64752…`

- 5 volcados `UKE-K53` de los registros del KTZ (estado ABL vs nuestro) + `ignore_loglevel` (624 B).
- El display YA funciona (L52): esto es para la LUZ del backlight (el frente abierto).
- Criterio: `probe-entry` ≠ nuestro ⇒ L54 = fix directo; = defaults ⇒ branch B (DCS 0x51).
- **Falta**: tablet a fastboot → flash `boot_a` + arrancar + leer `grep UKE-K53`.

## 14-oct ~18:3x — 🎉 #627 L52 FLASHEADO: **LA MUERTE DEL COMMIT RESUELTA** (fix SMMU A1b) — backlight = frente abierto

- El commit completa (`K50-trig-done`), vídeo ON, SoC vivo 184 s (la muerte de los 184 s = volcado
  de regmap MMIO mío — lección). Auto-recuperación ✓. La tablet está en el L52, sana, con display.
- **Backlight**: KTZ8866 habilitado y al máximo (registros I2C: 0x08=0x7F, 0x7FF, vendor-exactos,
  sin fault) y sin luz ⇒ camino físico boost→LEDs o receta anterior.
- **En curso**: verificación del proyecto hermano + del k52b2 (¿encendían la pantalla?).
- Rollback L50 `5c5437f6…` (ya no necesario hoy). Evidencia `out/CAPTURA-L52-*.log`.

## 14-oct ~18:2x — 🟢 L52 construido y repack VERDE — FIX-A1b QUIRÚRGICO listo (sha `0cd89f96…`)

- A1b: `wmask=0x0` + `force-idx` solo-para-idx2 ⇒ escrituras HW únicas: SMR(2)+S2CR(2)→TRANS + CB69
  (el idx8 del SDE que abortó en L51 no se toca). Crítica **PASA** (doc corregido: rama por instante
  4.08 s/47 s; splash con faults esperados).
- Repack G0–G8 verdes (cmdline **608 B** sin wmask; `FIX-A1b`×6; POKE=121). Rollback L50 `5c5437f6…`.
- **Falta**: tablet a fastboot → flash `boot_a` + test (armar canales con `stty raw -echo`).

## 14-oct ~18:xx — 🔴 #626 L51 FALLA: el wmask global aborta en write_sme idx8 → rescate (telnet :23 hallado)

- `wmask=0x1C0` escribe 19 SMEs ajenas; idx8 (sde_unsec) → **external abort** + MACHINE_CHECK → muere
  deferred_probe → UFS sin particiones → fallback del `/ukeinit` → **rescate** (getty + telnetd + X9DUMP).
- `FIX-A1` no salió (count 0) ⇒ el test del DCS no se llegó a hacer (NULO, criterio OK).
- Tablet viva en el rescate (**telnet root 192.168.42.129:23**). Reset físico + fastboot → rollback L50
  `5c5437f6…`. **Siguiente (L52): fix quirúrgico de la entrada idx2 sin wmask global.**

## 14-oct ~17:3x — 🟢 L51 construido y repack VERDE — FIX-A1 SMMU LISTO PARA FLASH (sha `e70455e0…`)

- Fix A1 corregido tras la crítica (sin `count==0`; strings y paréntesis reparados) + cmdline
  638 B (`uke_write_mask=0x1C0` + `uke_disp_reclaim=1`). Gates G0–G8 verdes.
- **Criterio**: miga `reclaim display: SMR(2)… lo reutiliza` OBLIGATORIA + superar
  `K47-host-xfer`. Rollback L50 `5c5437f6…`/L49/L48. Riesgo B2: posible wedge de boot (~4 s).
- **Falta**: tablet a fastboot → flash `boot_a` + `set_active a` + reboot + test.

## 14-oct ~17:2x — 🎯 #625 L50 FLASHEADO: **VEREDICTO A** — la muerte es el trigger/fetch del cmd-DMA (SMMU/IOVA)

- Captura: prepare ×2 hosts ENTERO → **`K50-dma-base=2000`** (IOVA VM del KMS) → `vid-ok` →
  `K50-commit` → ⛔. Limpia B/R1 (clocks) y R2 (wait4video).
- **L51 = FIX-A1** (reclaim entrada PINada del BL + `uke_write_mask=0x1C0 uke_disp_reclaim=1`),
  a crítica adversarial antes de build/flash. Rollback L50/L49/L48.
- Tablet auto-recuperada (`a9b73ca0`), sddm off. Evidencia `out/CAPTURA-L50-*.log`.

## 14-oct ~17:2x — 🟢 L50 construido y repack VERDE — LISTO PARA FLASH (1 escritura, `boot_a`)

- **sha `5c5437f6…`** (100663296 B); gates G0–G8 verdes (K50-×18, POKE=115, S4-DIAG×4, L43–L49
  intactos). Build 40 s (incremental, ccache).
- Instrumento: 12 pokes `K50-*` subdividen el path DSI_1 + **F0** (imprime `dma_base`); criterio
  A/B/resume en `L50-INSTRUMENT.md` §3. **Fix A1** listo para L51 (`FIX-SMMU-CLOCKS.md`).
- Runbook §5 (probe `<3>` obligatorio, MAC fresca, `:#0`). Rollback L49 `ccfdea9d…`/L48 `0b1d22c4…`.
- **Falta**: tablet a fastboot → `fastboot flash boot_a` + `set_active a` + reboot.

## 14-oct ~18:00 — 🎯 #624: PUNTO DE LA MUERTE CAPTURADO — el primer DCS del host (netconsole)

- **Captura**: última línea `K47-host-xfer` (`dsi_host_transfer`, `dsi_host.c:1791`) tras
  `cmd#0 dt=39`. Todo lo anterior PASÓ (phy/host-power/panel power+reset) ⇒ F1/F3 limpiados;
  el punto es el path de comando (cmd-DMA).
- **Canal**: reparado — `remote_mac` rancia + `console_loglevel=1` (regla: `dmesg -n 7` + probe
  nivel 3 antes del test). Evidencia: `out/CAPTURA-MUERTE-*.log`.
- **Forensia**: SMMU/IOVA NO traducible con `uke_keep_boot` (candidato nº1) vs vendor (caso sync,
  wedge síncrono). **Siguiente (L50)**: instrumento de subdivisión + print del IOVA (1 escritura;
  rollback L49/L48). Tablet: boot 9bccd0de, sddm off, estable.

## 14-oct 17:xx — 🟡 #623 L49: boot estable + captura del commit a un fix de distancia

- **L49** (`ccfdea9d…`): 5 pokes de captura + `NETCONSOLE` + `iomem=relaxed`; **estable** (sddm off).
- **Captura**: los 3 canales diagnosticados — netconsole (**TX del netpoll sobre `cdc_ncm`
  falla**; el UDP de usuario SÍ llega ⇒ el fix es un parche al netpoll/NCM o un sysfs del
  `uke_lastpoke`), `/dev/mem` (bloqueado en arm64), pantalla (negra: raíles off).
> **Corrección #624**: el fallo del netconsole NO era el TX del netpoll/cdc_ncm (refutado
> con fichero:línea); era `remote_mac` rancia + `console_loglevel=1`.
- **Siguiente (L50)**: fix del canal → `modetest -s` → punto exacto del commit → fix quirúrgico
  (F1 link-clocks candidato nº1). Tablet: L49 viva y cargando.

## 14-oct 15:xx — 🎯 ACTOR CAZADO: `sddm`/Hyprland; display-ON **ESTABLE** sin DM (L48+sddm-off)

> Medido en vivo (dumps v3 + modetest + 0 escrituras). Tablet: **L48 + sddm deshabilitado**, viva y cargando.

- **La muerte display-ON la causaba el DM**: `sddm`→Hyprland en bucle de crash; tras el bind
  (47 s) Hyprland toca el display → **el primer commit (modeset)** → muerte (~50-70 s). Con `:d`
  falla limpio.
- **TEST decisivo**: `systemctl disable --now sddm` → **el boot display-ON SOBREVIVE** (minutos,
  `K48-alive-1/2/3` ✓, se auto-recupera) ⇒ **PASA**. El asesino = el commit, no el suspend
  (los `dpu-susp/mdss-susp` a 47 s no son fatales).
- **Modetest controlado**: `-c` vive; `-s 36@85:#0` **muere <1 s** (sub-segundo, más rápido que
  el dump) ⇒ el punto exacto del commit: **pendiente** (canal del pintado uke_panic_fb).
- Siguiente: capturar el punto del commit (pintado) → fix quirúrgico → vci/DCS.

## 14-oct 14:4x — 🟡 #622 L48 (migas del bind/post-bind): la muerte SE MOVIÓ (~5-11 min vs ~50 s) — abierto

> Medido en vivo (SSH + dumps). Estado final: L45 restaurado + tablet en **cargador de pared**.

- **Los `K48-*` completos**: bind OK a 47.17 s (`post-init` + `Initialized msm-kms minor 1`),
  **`K48-alive-1` a 50.2 s**, `mdss-en/susp` ×9-10 (baile temprano), `dpu-susp` ×2, `res-*` ×2.
- **Sorpresa**: los boots L48 viven **~5-11 min** (no ~50 s como L46/L47); luego el slot se agotó
  → fastboot. Único cambio vs L47 = las migas (inertes) ⇒ ¿perturbación de timing (E6, ~30 pr_err
  del baile mdss)? ¿flakiness? **Abierto**.
- **Bloqueo**: los dumps se sobreescriben entre boots (nombre por uptime); el **dumper v3
  (boot-id)** quedó **pendiente** (SSH caído). Aplicarlo antes del próximo ciclo.
- Pendiente también: el valor de `K48-opp-rate` y el contexto de la muerte del boot de 11 min.

## 14-oct 13:0x — 🔴 #621 L47 (migas + FBDEV=n): FALLA-A — H2-fbdev REFUTADO; el asesino está en el bind del DPU

> Medido en vivo (dumps + SSH). `boot_a` = L47 `b320616b…` (flasheado y caído) → restaurado L45.

- El boot L47 **muere igual a ~50 s** (loop hasta agotar el slot; `pureason=0x80100`). Dump `uke-48`:
  **`K47-dpu-hw-in` + `dpu-res`×2 + `tx-alloc`×2, sin `atom-tail`** ⇒ sin commit (el `=n` retiró el
  auto-modeset ✓) ⇒ **la muerte NO es del fbcon/modeset**: está en el **bind del DPU** (hw init +
  resume + clocks/GDSC del display; el burst `sync_state` lista los GDSCs adf*/af09000).
- Cronología 46.98→46.99 s: probe OK → `dpu-hw-in` → `dpu-res` (1º) → WARN IOMMU (benigno) →
  `tx-alloc`×2 → `dpu-res` (2º) → card1 → `sync_state` (clocks+GDSC) → **silencio** → reset duro.
- **Siguiente (L48)**: migas finas en `dpu_runtime_resume`/`dpu_kms_hw_init` (GDSC/clk) + candidato
  FASE-1 (sembrado SRC/parked_cfg). Rollback: **L45 restaurado** + s287.

## 14-oct 12:3x — 🎯 H2 CAPTURADO: la muerte del boot display-ON es del **enable del display** (pre-DCS)

> Experimento: L46 re-flasheado + volcador `uke-dump` (20 s → LOGFS). El boot muere a ~50-60 s
> (no 13 min: eso incluía el fastboot). Evidencia: `out/h2-dumps/uke-{8,28,48}.txt.gz`.

- Cronología (dump uke-48): probe del panel OK **t=47.04** → `K47-tx-alloc` → `K47-pan-modes` ×2
  (el DRM pide modos) → burst **`sync_state() pending`** de `disp_cc-sm8550`/`gcc-palawan`
  (clocks del display) → **SILENCIO** → reset duro (`pureason=0x80100`; limpio=0x800001).
- **Sin `K47-pan-prep` ni S4-DIAG** ⇒ muere en el **enable del DRM/DSI** (clocks/GDSC/PHY),
  **antes del `prepare()` del panel y del DCS**. Control (L45 display-off): sin modeset, sin
  muerte (1.9 h), card1 disconnected.
- Oops t=8.28 s = `insmod` pmic_glink/ucsi_glink (OOT, `fwnode_get_name+0x38`), **no fatal**,
  issue aparte.
- ⇒ Prioridad reordenada: **enable-path ≺ DCS**; vci sigue sin probarse (no hubo prepare).
  Informe: `PIPELINE-PANEL-20261014/H2-CRASH-CAPTURADO-20261014.md`. **L45 restaurado** + s287.

## 14-oct 11:3x — 🔴 #620 L46+s287 (display-ON): FALLA el test (sin prepare) + 2 hallazgos; L45 RESTAURADO

> Medido en vivo (SSH+ACM). Estado final: `boot_a` = L45 `83647c45…` (restaurado) + `dtbo_a` = s287 `9f3d2b00…`.

- El boot display-ON **arranca y sobrevive** (SSH a los 10 s) pero **el panel no prepara**: probe en
  `-EPROBE_DEFER` hasta **t=47 s** (host DSI secundario `ae96000.dsi` tardío: `phy driver is not
  ready` en su primer probe) → sin card1 a tiempo → sin modeset → sin DCS → **sin voto vci**
  (`vci-supply=0x150` sí verificado en el DT vivo). S4-DIAG: 0 líneas.
- **H2 (nuevo)**: los boots **display-ON se reinician en silencio ~cada 13 min** (7 boots/90 min;
  slot a agotado → fastboot; sin panic/pstore/forklog — el volcador del initramfs falla por el bug
  sdX). No es la muerte del DCS (no hubo prepare). L45+s287 (display-off) vivo >8 min.
- Restaurado **L45** (1 escritura, 3641 mV); dtbo s287 se queda (inerte para L45).
- **Arreglos 12:0x**: volcador periódico `uke-dump` (LOGFS, gzip, 20 s, servicio persistente) ✓;
  **H1 diagnosticado** = gatillo del táctil a t=47 s (deferral por eventos; arreglo fino = DT/G9);
  **experimento H2 en marcha** (L46 re-flasheado + dumper, esperando el reset para capturar dmesg).

## 14-oct 00:4x — 🟢🟢 #619 L45 VERDE: el enlace panel↔KTZ **CERRADO**; sin luz visible con display apagado (esperado)

> Medido en vivo (SSH + ACM). Manda sobre lo anterior. `boot_a` = L45 `83647c45…` + `dtbo_a` = s286 `33d153f2…`.

- **PASA los 4 criterios**: `UKE-L43-ICC` 1 + `X9I2C-icc-get-ok` 1 (sin regresión L43); KTZ
  `probe sucess end` 1 + driver `ktz8866` + `/sys/class/backlight/2-0011` (max 4095);
  **`dmesg | grep -c 'sin backlight externo'` = 0**; **`UKE-L45` = 1** (el panel RE-probeó tras el
  KTZ y resolvió el backlight — el fix `-EPROBE_DEFER` diseñado en #618 funcionó).
- **Prueba de luz (display apagado por diseño, `video=DSI-1:d`)**: sysfs `0` → actual 0; `307` →
  actual 1328; `bl_power=0` + `4095` → actual 2047 y regs 0x04=0x07/0x05=0xff/0x08=0x7f **sin luz
  visible** (testimonio del dueño). **Coherente, no regresión**: la cadena LED/boost solo se
  alimenta con el camino de encendido del panel (L39: blanco al probear con display on); además el
  nodo DT del KTZ no declara `enable-gpios` ni `vddpos/vddneg-supply` (contexto del fix B1). La
  confirmación visual queda para el ciclo con display encendido.
- ⇒ **Backlight cerrado de punta a punta** (canal L44 + enlace panel L45). Siguiente: `vci` (P0) +
  G8 y, después, kernel con display encendido (ataque a la muerte del primer DCS).
- Batería del flash 3689 mV (excepción del dueño registrada); rollback L44 `13c9454d…` / L43 / L19.

## 14-oct 00:0x — 🟡 #618 L44: el canal KTZ FUNCIONA de punta a punta; el panel no se queda el backlight (orden de probe; B2 lo cazó)

> Medido en vivo. `boot_a` = L44 `13c9454d…` + `dtbo_a` = s286 `33d153f2…`.

- **PASA (canal backlight)**: `ktz8866 2-0011: probe sucess end`, driver `ktz8866` bindeado,
  `/sys/class/backlight/2-0011` (max 4095). Brillo (lecturas con `I2C_SLAVE_FORCE`): 307 →
  0x05=a6/0x08=7f; **0 → 0x05=00/0x08=3f**; 1 → 3f. **sysfs→I2C→KTZ→LEDs verificado.**
- **FALLA (panel↔KTZ)**: el panel probea antes que el KTZ (`ret=-517` a t=0.715 vs KTZ t=4.33) y
  `drm_panel_of_backlight` es one-shot ⇒ `backlight=NULL` este boot (el aviso B2 aparece: 1).
- **Fix L45 (un hunk)**: propagar `-EPROBE_DEFER` en el probe del panel (reintento tras el KTZ);
  `dev_warn` solo para errores no-EPROBE_DEFER. Sin regresión L43.

## 14-oct 00:0x — 🟢🟢 L43 VERDE: el bus I2C del KTZ8866 REGISTRA y el chip RESPONDE

> Medido en vivo (SSH). Manda sobre lo anterior. `boot_a` = L43 `5a6d1dee…` + `dtbo_a` = s286 `33d153f2…`.

- Marcadores: `UKE-L43-ICC: ruta 'qup-core' no disponible (-517); sigo sin voto` + `X9I2C-icc-get-ok`
  (x1 c/u, nivel 6 ⇒ por `dmesg`/SSH, no consola). El bus registra como **`i2c-2` (`Geni-I2C`,
  `/dev/i2c-2`)**; clientes del DT: **`2-0011` (ktz8866)** + `2-000e` (wcd939x-i2c).
- Scan SMBus-quick (python, `I2C_SLAVE`): **ACKs en 0x0e y 0x11** ⇒ el **KTZ8866 responde**;
  lecturas: 0x00=0x00 · 0x01=0x21 · 0x04=0x06 · 0x05=0xad · **0x08=0x7f**.
- ⇒ **Canal I2C del backlight externo ABIERTO y verificado** (prerrequisito del panel + la
  observación "desde el otro lado"). Siguiente: (a) driver KTZ8866 + `backlight` del panel (ya
  portado en k52L33-tree; llevarlo al linaje vivo), (b) restaurar `vci` (P0), (c) G8.
- Batería del flash 3686 mV (excepción del dueño); rollback disponible (L19 `71d89ca6…`).

## 13-oct 22:5x — #616 s286: arranca (NO wedgea) pero el bus I2C queda bloqueado por ICC

> Medido en vivo. `dtbo_a` = s286 `33d153f2…` (boota; se queda como vehículo del próximo ciclo).

- `fastboot flash dtbo_a s286` OKAY (594 KB) + `set_active a` + reboot → **arranca**: gadget a los
  15 s, SSH, red OK. **El bus único (SE0) por sí solo NO wedgea** (s284 necesitaba más superficie).
- **Pero el adapter I2C no se registra** (`/sys/class/i2c-adapter` vacío): causa exacta
  `a80000.i2c: deferred probe pending: geni_i2c: Failed to get 'qup-core' ICC path`
  (`qcom-geni-se.c:927`, `devm_of_icc_get`). El proveedor de esa ruta (`interconnect@0`,
  clk_virt) **no tiene driver atado** (`qnoc-palawan` ata los otros). X9ICC-skip neutraliza los
  votos pero no el get ⇒ **fix mínimo: tolerar el get fallido en `geni_icc_get`** (rebuild+flash).
- El nodo `ktz8866@11` está en el DT vivo esperando bus/driver. Oops DPU @~4 s **reproducido** en
  este boot (hallazgo de forklogs; no fatal). Rollback disponible: s275-r2 `67a65bc1…` (1 escritura).

## 13-oct ~22:0x — 🟢 L19 VIVO (SSH) + PILA DE CARGA **VERDE** + forklogs recuperados

> Manda sobre lo anterior. Medido en vivo (SSH + ACM; consola en `out/acm-L19.log`).

- **L19+s275-r2 arranca y llega a SSH** con 3470 mV (`7.2.0-rc2-palawan #1`): pantalla negra por
  diseño (`card1-DSI-1 disconnected/disabled`), red NCM OK (`enp0s20f0u3` PC `192.168.42.1` ↔
  tablet `192.168.42.129`). **Lección NCM**: el enlace se clavó en mitad de un scp lento; se
  recupera con `nmcli con down/up uke-ncm` en el PC (reproducido dos veces).
- **Peldaño 0 desbloqueado**: la partición de rescate está en **`/dev/sdb30`** (PARTLABEL
  `rescue`, 128M ext4), NO en `sda30` (sda = LUN 12M con xbl). **26 forklogs (5,9 MB) copiados**
  a `out/rescue/` (+ `android-kmsg.txt` de 2 MB). `charge/lee-forklog.sh` corregido (resolución
  por PARTLABEL).
- **Pila de carga DESPLEGADA y VERDE**: `uke-adsp.service` active, `adsp=running`, PDR
  `charger_pd state 0x1fffffff`, `qcom-battmgr-bat: status=Charging current_now=3219073
  charge_type=Fast` (3354 mV, cap 1%). Servicio **enabled** (autocarga en futuros boots).
  Bug propio corregido en el guion: `ssh_t` capturaba el "Permanently added" de
  `UserKnownHostsFile=/dev/null` → `-o LogLevel=ERROR`.
- **Banquillo**: `s286` construido (sha `33d153f2…`); minucias preparadas; SPLIT_LINK resuelto (NO).
- **22:4x**: el `uke-adsp.service` falló al arrancar este boot por **`adsp.b40` corrupto en el
  rootfs** (primera corrupción silenciosa ligada a los EXT4) — recopiado desde el PC y verificado:
  `adsp=running`, `Charging`, **batería 3708 mV** ⇒ **gate ≥3700 cumplido** (se puede escribir).

## 13-oct 21:27 — #614 EJECUTADO: L19+s275-r2 en slot a y slot REHABILITADO

> Manda sobre lo anterior. Medido con `getvar` antes/después.

- **Escrituras OK**: `boot_a` ← L19 `71d89ca6…` (Sending OKAY 2,072 s + Writing OKAY 0,078 s) ·
  `dtbo_a` ← s275-r2 `67a65bc1…` (OKAY 0,014/0,002 s). `set_active a` OK. Batería 3386→3382 mV
  (estable; el aparato había recuperado desde la franja agotada — el dueño lo cargó).
- **Medición #P52 CERRADA**: tras `flash` + `set_active a`, `slot-unbootable:a` pasó de `yes` →
  **`no`** y `slot-retry-count:a` de `0` → **`7`** ⇒ **flashear + `set_active` rehabilita un slot
  agotado; no hace falta `qbootctl`** (la vía prohibida sin decisión del dueño queda descartada
  para este caso).
- **SIN reboot por diseño** (3382 < gate 3700; el guard del ABL puede negarse por debajo de
  ~3400). Siguiente: cargar a ≥3700 (apagada, cargador de pared) → encender → L19+s275-r2
  (pantalla negra a propósito; va por SSH/NCM) → `charge/uke-charge-run.sh`.
- **Nota 21:4x (laboratorio offline)**: el gadget real es `acm+ncm` (no RNDIS — etiqueta errónea del
  13-oct; causas candidatas y checklist en `build/gates/revision/RNDIS-NCM-OFFLINE-20261013.md`);
  **s286 construido** y listo para el peldaño 6 (sha `33d153f2…`); SPLIT_LINK resuelto (Android NO
  programa SPLIT_LINK para o82 ⇒ no tocar mainline); minucias preparadas (`PREP-MINUCIAS-20261013.md`).

## 13-oct 21:0x — ⚠️ BATERÍA AGOTADA (~480–580 mV): #614 NO ejecutado; toca cargar en apagado

> Manda sobre lo anterior. Medido: `battery-voltage` 482/531/566/576 mV en cuatro lecturas
> (20:57: 2788 mV ⇒ desplome a la franja "agotada" en ~10 min). Precedente **#423** (26-sep):
> a 434 mV la tablet murió en pleno `Writing 'boot_b'`. **El subagente de #614 paró antes de
> escribir** (sin flash, sin `set_active`) — disciplina correcta.

- El aparato sigue en fastboot (`SERIE0001`), `slot-unbootable:a=yes` / retries 0, **L33+s283 en a**
  (no se tocó). **No se escribe ni se arranca a esta tensión.**
- **Remedio (el del #423):** apagada + **cargador de pared** (`off-mode-charge=1` está puesto).
  Puertos USB de PC: solo 100 mA (0,5 W) — inútil para esto. Desde vacío son **horas** (no los
  15–20 min del caso 3400→3700): mejor toda la noche.
- **Cuando vuelva:** (1) lectura rápida de `battery-voltage`; (2) si ≥3700 → ejecutar **#614**
  (L19+s275-r2 + `set_active a`) + arrancar; (3) con SSH → `charge/uke-charge-run.sh` (carga
  gestionada por ADSP/battmgr, 1,2 A) para no volver a ciegas.
- Lector ACM armado hasta 22:59 (`out/acm-L19.log`) + sniffer udev 2 h (`out/udev-L19.log`).

## 13-oct 20:2x — #613: reflash L33+s283 ejecutado; tras el reboot, aparato USB-silencioso

> Manda sobre lo anterior. Medido: `fastboot flash boot_a`/`dtbo_a` OKAY (shas `bc8b1ca6…` /
> `a8e7d4c0…`, fila #613 pre-registrada en el ledger), `set_active a`, reboot 20:12:46.

- **Tras el reboot no volvió**: 1 s de vida USB (device full-speed, `descriptor read error -71` ×2 —
  el preludio normal de los boots sanos) y **silencio USB total** (>5 min): 0 B de ACM, sin RNDIS,
  sin fastboot. `out/udev-restore-L33.log` y `journalctl -k` como evidencia.
- **INCONCLUYENTE** (regla del gate: un run a 3321 mV <3700 que da 0 B no es evidencia). Hipótesis:
  corte de batería al arrancar (caía ~15 mV/min en fastboot, que no carga; corte documentado
  ~3150 mV) o wedge pre-USB.
- **Siguiente**: cargador de pared (tablet apagada, 30–60 min) → medir `battery-voltage` en fastboot
  **antes** de cualquier otra escritura. Lector ACM único armado hasta 20:57 por si vuelve solo.

## 13-oct 20:0x — VUELTA AL BASELINE L33+s283 (sesión G4/G7/wedge/auditoría)

> Esta sección es **la que manda** sobre todo lo anterior. Mide el estado del aparato
> a las 19:44–20:0x del 13-oct.

### Qué está puesto AHORA

| ranura | artefacto | sha256 |
|---|---|---|
| `boot_a` | `boot-uke-k52L33.img` (flasheado 19:44) | `bc8b1ca6c405089aec4c18fda81d4799c8bfd67a71ef1545dd7184e7c329095f` |
| `dtbo_a` | `s283-boot-dtbo-gpu-display-opp148-nogpr-bl.img` (flasheado 19:53) | `a8e7d4c06af2733445ccf40d15f2efcd1d076cc3702698665c3e5ff076c610d7` |

`current-slot:a` · `slot-retry-count:a=6` · `slot-retry-count:b=6` · ambos `unbootable:no`.
Rollback del dtbo: `s285…` `0b0b16b569e7212bd5f6dfa8a17d43c512a812f9950ca7bcd2084914d181bf06`.

### Dos results de la tarde

1. **G7 (SSC) REFUTADO con grupo de control** (`build/evidencia/G7/`). Cambio único
   `enable_ssc = false → true`. L40 vs L42, mismo dtbo, misma sesión: secuencia y punto
   de parada idénticos. Era el gap mejor fundamentado del proyecto (los 3 parámetros ya
   estaban con los defaults exactos del vendor) y aun así no movió nada.
2. **Wedge de s284 AISLADO** (`build/evidencia/WEDGE/`): escalera s283 → s284 → s285.
   s284 (GPI + 7 GENI) wedgea a 70 s con 0 B. **s285 (solo los 2 fragmentos del GPI-DMA)
   arranca** ⇒ el GPI-DMA es inocuo; el culpable es hacer que los 5 buses I2C proben
   por primera vez.

### Corrección de esta misma sesión: `video done timed out`

Primero afirmé que el mensaje aparecía **solo con s285**. **Es falso**: con s283 también
aparece (3 veces). La correlación real es con el **kernel L33**, y tiene explicación
por cronología, no por misterio:

- `boot-uke-k52L33.img` se construyó el **12-oct 17:53**
- el parche L36 (`if (true) return;` en `dsi_wait4video_eng_busy`, que anula la espera de
  70 ms por comando) entró en el árbol el **12-oct 18:46**

L33 es anterior al parche → ejecuta la espera → puede dar timeout. L40/L42 lo llevan →
dan 0. **L33 es "el último estable" para el arranque pero el kernel más viejo para el
display.** Por eso su firma difiere; no es un cambio del dtbo.

### Firmas medidas (ventana del arranque, ACM)

| | `cmd#0` | `status=4` | `status=5` | `video done` | corta en |
|---|---|---|---|---|---|
| L40 (control) | 5 | 3 | 5 | 0 | `host-xfer` 10,38 s |
| L42 (G7) | 5 | 4 | 5 | 0 | `cmd#0` 10,30 s |
| **L33 + s283** | 3 | **34** | 0 | **3** | 10,29 s |
| L33 + s285 | 3 | 36 | 0 | 4 | 10,34 s |

⚠️ Los **recuentos son el número de vueltas del bucle de reintento y son variables**: lo
que compara es la **secuencia y el punto de parada**, no los números.

### BLOQUEO ACTUAL: el gadget RNDIS no enumera

Con L33+s283 el aparato **llega a usuariospace** (`sshd[765] Server listening on 0.0.0.0:22`,
`Reached target Graphical Interface`) pero **no hay interfaz RNDIS en el PC**, así que no hay
SSH por `192.168.42.129`. Consecuencia: **el peldaño 0 del auditor (leer el forklog de
rescate de `/dev/sda30`) no es ejecutable** — no por el forklog, sino por falta de red.
`charge/lee-forklog.sh` queda escrito y verificado pero sin poder ejecutar.

En fastboot el mismo cable y el mismo puerto enumeran bien (`18d1:d00d`), así que el cable
y el puerto sirven: falla la parte de red del composite gadget.

### Batería

**3419–3440 mV** en todas las lecturas de la tarde (fastboot). **Gate 3700 mV NO cumplido.**
El dueño autorizó flashear por debajo del gate, pero el auditor documentó (E3) que un run a
3233 mV dio 0 B y se leyó como "wedge de PHY" — un falso diagnóstico que costó un ciclo.
**Regla adoptada: cualquier run por debajo del gate que dé 0 B se registra como
INCONCLUYENTE, no como evidencia.**

### Auditoría de método (commit `6232f5b`)

`build/gates/revision/AUDITORIA-METODO-20261013.md` — revisor escéptico, 10 errores de
razonamiento propios con `fichero:línea`, escalera incremental desde L33 con criterio
pasa/falla prefijado por peldaño, y lista de afirmaciones a reescribir. Lo que está bien
queda nombrado también: los grupos de control G4/G7, el aislamiento s283→s284→s285, la
doctrina ACM-lossy y la autocorrección escrita con evidencia.

**Presupuesto**: el 13-oct se hicieron 9 escrituras contra un gate de ≤2/día (~4×).

### Deuda de trazabilidad abierta

**Los flashes de hoy NO se anotaron en `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`**
(L39, L39d, L39b, L40, L41, L42, s284, s285, y hoy s283). Pendiente de escribir.

## 13-oct 12:50 — KTZ8866 portado (local, sin flash, sin tablet)

- Driver backlight externo extendido en k52L33-tree (`ktz,ktz8866` + curva vendor
  exacta); `ktz8866.ko` compila RC=0 sin warnings. DT en
  `build/gates/FRAGMENTO-KTZ8866.dts`. Informe:
  `build/gates/revision/REV-KTZ8866-UKE-20261013.md`.
- Refuta fase4:43-45 (uke NO usa DCS 0x51; es `bl_ctrl_external`, panel ID 0x14).
- Pendiente (requiere ciclo con flash, NO hecho): panel mainline a backlight externo
  + `CONFIG_BACKLIGHT_KTZ8866=m` + decidir 1 o 2 chips (i2cdetect se0/se12).

## 13-oct 00:3x — L38 PENDIENTE (construido + verificado, NO flasheado)

- **Artefacto**: `build/bootimg/boot-uke-k52L38.img` sha
  `338d921cb6203a65938d6fd598186c1ceb9fc3e63cab8b238b7ce0e75e03ba73`
  (100663296 B, kernel `a159c8d7…`, cmdline 585 B sin `video=`, con `systemd.mask=sddm`).
- **Variable**: `o82_reset()` release2 100 ms → **15 ms** (única divergencia del vendor
  en toda la secuencia de reset; todo lo demás audita idéntico).
- **Verificado 2×** (report G0–G8 + verificación independiente del binario descomprimido:
  PPS ×1, marca L38 ×1, early-return dentro, fbdev ×0, POKE 113). Hoja de ejecución:
  `build/gates/PRE-REGISTRO-F9-L38.md`. **NO existe ningún L39** (construirlo ahora
  violaría "un cambio por ciclo").
- **Preflight pendiente** (tablet ausente): batería 3555 mV < gate 3700 ⇒ cargador;
  `slot-retry-count:a` último conocido = 3; `set_active a` SIEMPRE; lector ACM antes
  del reboot; trigger Hyprland-direct a modo **preferido** (nunca 60 Hz forzado);
  doble captura obligatoria (ACM es lossy).

## 12-oct noche — L33→L37: el commit desplegado, 4 muertes medidas

- **L33** (`bc8b1ca6…`, `CONFIG_DRM_FBDEV_EMULATION=n`, sin `video=`): **SSH a los 20 s**;
  `start sddm` a ~205 s ⇒ muerte a **207 s** (`status=4` = FIFO ×10, PLL OK sin `0x20`,
  `cmd#0` encolado, `wait for video done timed out`). Mecanismo del commit automático
  identificado (`drm_fb_helper_single_fb_probe → drm_client_modeset_commit`). Detalle:
  `build/gates/revision/HALLAZGO-L33-DEATH-20261013.md`. Efecto colateral: el modeset
  fallido **envenena el arranque** (3 resets muriendo en `K47-crtc-en` ~10,4 s).
- **L34** (flush `TIMING_FLUSH←1`): nunca se probó limpio (sddm auto-arrancaba por un
  `unmask` mío anterior ⇒ muerte a 10,7 s autoinfligida).
- **L35** (= kernel L34 + `systemd.mask=sddm`, Hyprland-direct 60 Hz): muerte a **149 s**
  en `K48-w4-done`. El mask es generador ⇒ **recuperación automática**, fin de los
  ciclos de rescate manual. Detalle: `L35-RESULTADO-20261013.md`.
- **L36** (early-return `dsi_wait4video_eng_busy` + flush retirado — **2 variables, no 1**;
  gate tautológico; quemó el termómetro `video_done`): muerte a **98 s** en `w4-done`,
  solo ACM. No comparable con L33 (modo 60 Hz inexistente vs preferido ~120 Hz).
- **L37** (PPS de DSC en `o82_prepare`): muerte a **29,4 s** en `K48-w4-done`;
  `L37-pps` ×0 en ACM ⇒ **las PPS nunca se enviaron** (muerte anterior al `prepare`).
  Conclusión: todas las correcciones de panel están aguas abajo del punto de fallo.
- **Punto de muerte (honesto)**: `K48-w4-done` en L34–L37, pero L33-con-100 ms llegó más
  lejos y L34+ solo tienen ACM lossy ⇒ **punto BLANDO**, no atribuible con precisión.
- **Refutado**: "FIFO 8→12" (son 10/10/10; `pr_err_ratelimited` topa), "muerte en el reset"
  (hueco de 100 ms sin líneas ≠ prueba), "ningún DCS llega" (`dsi_manager.c:509-548`:
  DSI_1 dispara a los dos), L37 NON_CONTINUOUS (sheng lo usa y vive).
- **FASE 1 del ROADMAP (1a/1c) CANCELADA**: el OPP ya siembra 514 MHz antes del primer
  enable (`dpu_kms.c:1304-1308` corre en `kms_init`, `msm_kms.c:294`, antes que `hw_init`
  `:307`; techo OPP 514 MHz `palawan.dtsi:3464`; medido SRC a 514 MHz). `parked_cfg=0`
  es falso. La muerte del bind (~4 s) era fbdev auto-commit, ya muerta con L33.
- **RE vendor F0–F3 completa** (Ghidra, 3327 funciones): gap-list en
  `GAPLIST-VENDOR-MAINLINE-20261013.md`. G1 (skip VBIF) candidato tras L38.

## 13-oct ~18:00 — L33 VIVO (el commit del boot ya no mata)

> **Lo que manda es el ledger**: `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` (#553–#612).
> Toda afirmación de esta página lleva fecha de medición. Lo que no se re-mida en 14 días → caducado.

- **Boot**: `boot-uke-k52L33.img` sha `bc8b1ca6c405…`, `slot a`, `slot-retry-count:a=7`
- **Kernel**: `CONFIG_DRM_FBDEV_EMULATION=n` (nada hace commit de modeset en el boot) + cmdline **sin `video=`**
- **SSH abre a los 20 s** (L25–L32 morían a los ~4 s) ✔
- **Mecanismo de la muerte identificado**: `drm_fb_helper_single_fb_probe()` →
  `drm_client_modeset_commit()` (emulación genérica de fbdev). No es `msm.fbdev`.
- **`modetest` no funciona**: el uapi de drm de 7.2-rc2 usa otros nombres de campo
  (`drm_mode_card_res`, `count_modes`, modo en línea en `drm_mode_crtc`). No es un bug
  del driver. Detalle en NOTAS-OMARCHY.
- **Conector `DSI-1`**: conectado, modo `3200x2136`, sin `DRM_MODE_FORCE_*` ⇒ **el
  commit ya se puede lanzar desde userspace** (antes `:d` lo impedía con `-EINVAL`)

### Vigilante: el embebido NO sirve tras switch_root

`diag-snapshot.sh` escribe el ciclo 0 y se queda mudo (proceso vivo, `nanosleep`, pero su
`dmesg|tail > tmp && [ -s tmp ]` falla siempre). **Usar `build/init/diag-watch-ssh.sh`**,
lanzado por SSH con `setsid`: mismo diseño con rutas absolutas, verificado ciclando.

### Trigger del commit

`systemctl unmask sddm && systemctl start sddm` → el greeter `omarchy` hace el modeset
real. Es lo que dispara el commit mortal.

## RESULTADO F3b/L25 (12-oct 05:1x) — **POSITIVO**: `:d` exonerado

Flash de `boot-uke-k52L25.img` (`04cd4980…`): **arranca y vive** (SSH, FD735+GLES, 0 pstore).
`video=DSI-1:d` **NO era lo que mataba el SoC**; lo mortal era el skip del BCR sobre scanout vivo.

| t (s) | Evento | L24 |
|---|---|---|
| 0,329 | gate `L24-skip-mdss-reset` (BCR saltado) | sí |
| **0,490** | **`K47-pan-probe` — el panel entra en probe** (nunca se había visto) | ❌ |
| 0,491 | `probe-ok` + `attach-ok` ×2 (**ambos links DSI enganchados**) | ❌ |
| **3,965** | **`msm_dpu ... bound ae94000.dsi`** | ❌ **L24 MORÍA AQUÍ** |
| 3,969 | `K47-tx-alloc` ×2 (alloc TX del DSI alcanzada) | ❌ nunca llegó |

⇒ El **bind del DPU ya sobrevive** con el BCR saltado. El `prepare` (`K47-pan-prep`) sigue sin correr
porque `:d` mantiene el conector `disconnected` — esperado y pre-registrado.
**Siguiente paso que se abre**: quitar `:d` sobre este mismo build para ejecutar un `prepare` real.

## En una frase

**13-oct 20:0x.** El aparato está en el baseline **L33 + s283** (flasheado 19:44 / 19:53) y
**llega a usuariospace** — pero no hay RNDIS, así que no hay SSH. El fallo del panel sigue
siendo el mismo e inalterado desde hace rondas: **`cmd#0` entra en el FIFO del host y no
sale**; sobrevive a OPP, G5, G6, G4 (refutado con control), G7 (refutado con control) y PPS.
Cinco hipótesis de configuración de PHY/PLL descartadas ⇒ **el modelo "el enlace está mal
configurado" está agotado**; lo que queda es "el panel no está escuchando" (reset real del
TDDI nunca observado, dual-DSI bonded, o línea física). El intento de mirar desde el otro
lado con I2C wedgea el SoC al hacer que los buses proben por primera vez (`build/evidencia/WEDGE/`).

### Próximos pasos (ordenados, con el coste de cada uno)

1. **Resolver el gadget RNDIS** (0 flashes) — desbloquea SSH y con él el **forklog de
   rescate**, que es evidencia gratis sin leer desde hace 39 rondas y es el peldaño 0 del auditor.
2. **Cargar a ≥3700 mV** (cargador de pared, tablet apagada, 30–60 min) — sin esto cualquier
   0 B es ininterpretable.
3. **Anotar los 9 flashes de hoy en `FLASH-LEDGER.md`** — deuda de trazabilidad, causa de que
   esta sesión haya necesitado una auditoría para reconstruir el día.
4. Escalera del auditor desde L33, **1 cambio y 1 escritura por peldaño**, en días distintos:
   peldaño 1 = control de reproducibilidad s283 (ya en pie, solo falta el criterio escrito);
   peldaños 2–5 = reset 15 ms → PPS dual → backlight-warn → G8; peldaño 6 = s286 con **un solo
   bus I2C**, el del KTZ8866 (techo 1 bus por flash). **G5/G6 no se re-prueban** (inertes en
   paquete, sin señal que los pida).

---

### (histórico, 12-oct 03:4x — superado, se conserva por historia)

El aparato estaba SANO (control L19 verde: 13 min uptime, SSH por RNDIS, freedreno FD735 + GLES 3.2,
cero panics) y la pantalla negra de L19 no era un fallo: `video=DSI-1:d` deja el conector
`disabled` y el panel nunca se prepara.

## Estado del aparato (medido 12-oct 03:4x por SSH)

| Qué | Valor |
|---|---|
| Par en slots | **slot a: `boot_a` = L19 `71d89ca6…` + `dtbo_a` = s275-r2** (reflasheado 03:2x como control) |
| Conexión | **RNDIS/USB a `192.168.42.129`** (`ssh -i build/rootfs/uke-arch-root root@…`) — la IP mDNS de docs/historia/AGENTS.md caducó |
| Red del PC | `192.0.2.10/24` (wlan0) — **la red es 192.168.0.x, no 192.168.1.x** |
| Batería | **3543 mV** (leída en fastboot 03:2x) — **por debajo del gate de 3700**; sin cargador en fastboot |
| Slots | `current-slot:a` · `slot-retry-count:a` = **7** ⚠️ (el flash lo sumó; 8 ⇒ unbootable y cae a B) · `b` = 6 |
| Uptime | 13 min, load 0.00 |
| GPU | **VIVA** — Mesa, freedreno, `card0`+`card1`, `renderD128` |
| Pantalla | `card1-DSI-1` = **status `disconnected`, enabled `disabled`, dpms On** |
| Backlight | `ae94000.dsi.0` presente, **307/4095** |
| Link DSI | **VIVO** — `K47-tx-alloc` 4.08 s, `K47-pan-bl`+`host-xfer` 7.72 s (DCS 0x51 llega al panel) |
| Prepare del panel | **NO corre** — 0 marcas `UKE-P82:` (el conector `disabled` lo impide) |
| Panics en este boot | 0 |
| pureason (boot previo) | **`0x800011` = clase PANIC** → el aborto de L22b fue panic de kernel, no cuelgue HW |
| pstore/ramoops | **backend REGISTRADO** (`pstore: Registered ramoops as persistent store backend`, 4 MiB @`0xa7000000`) pero **0 ficheros** — el panic del L22b no se persistió |
| EXT4 | ⚠️ **2 errores nuevos** `__ext4_new_inode: doubly allocated` (journal + NetworkManager) |

## Los 3 hallazgos que cambian el diagnóstico

1. **La pantalla negra de L19 NO es un fallo — es `video=DSI-1:d`.** El conector queda `disabled`, el
   panel nunca se prepara. Por eso no hay ni una marca `UKE-P82:`. **Consecuencia para el plan: quitar
   solo el `resets` del DT no encenderá nada** — hay que además habilitar el conector para que corra el
   `prepare` completo y *entonces* ver si el BCR lo mata.
2. **El aborto de L22b fue un panic (`pureason=0x800011`), no un cuelgue.** Y **ramoops está activo**
   (contra lo que decía un informe), así que un panic futuro **sí** se capturará.
3. **El gate `dispcc.uke_skip_pll` NUNCA disparó.** KBUILD_MODNAME del objeto es `dispcc_sm8550`
   (`Makefile:171`); la cmdline llevaba `dispcc.uke_skip_pll=1`. → **L22b fueron 3 gates, no 4**, y la
   lectura del ledger #612 sobre "gateamos la PLL" es **falsa**.

## Estado del enfoque `panel-inherit` (revisado 12-oct)

- **El "éxito" de L22 se sobreestimó**: lo que se vio fue *backlight con imagen muerta*
  (`o82_prepare` salta **antes** de `backlight_enable`, línea 400 → esa luz venía del ABL).
  El criterio de éxito diseñado (log del pintor sobreviviendo a 4,1 s) **nunca se midió**.
- **Mainline va en la dirección contraria**: 3 series upstream (SDM630/660, SM6125, SM6115) **añaden**
  el reset del MDSS *a propósito* — *"MDSS reset is necessary to have working display when the
  bootloader has already initialized it for the boot splash screen"*.
- **El DT de Android (`qcom,mdss_mdp@ae00000`) NO declara `resets`; mainline sí** (`palawan.dtsi:3368`).
- **No existe hand-off de panel en mainline** para ABL (ni flag en `drm_panel`; el `memory-region` del
  binding `mdss-common.yaml` está vacío). Upstream no aceptaría este hunk.
- **El objetivo real NO es heredar el splash**: es un `prepare` completo del panel que no cuelgue. El
  inherit queda relegado a **instrumento de diagnóstico**.

## Hipótesis viva (ordenadas) y su estado

| # | Hipótesis | Estado |
|---|---|---|
| 1 | `msm_mdss_reset()` (BCR, 20 ms, ~0,45 s) mata la imagen | **Líder, 3 vías convergentes.** Sin traza directa (el reset no loguea) |
| 2 | Clobber de RCG compartido (`clk_rcg2_shared_enable` → `parked_cfg=0`) | Mecanismo verificado; **también a ~0,5 s** vía `dsi_get_config`, no solo a 4,1 s |
| 3 | `dpu_vbif_init_memtypes` sin gate en `hw_init` | Bug real de L22 (ya cerrado en L22b) pero **irrelevante a ~0,5 s** |
| 4 | GDSC colapsada → MMIO contra dominio apagado → bus hang | Plausible; **`pd_ignore_unused` YA está en cmdline**, así que menos probable |
| 5 | Glitch de pinctrl en TLMM 2 al pedir el reset (`GPIOD_OUT_LOW`) | **Nueva, sin probar**; compite en la misma ventana que #1 |
| 6 | IRQ fantasma del MDSS pendiente del ABL (el BCR limpiaba) | **Nueva**; distinguir con contadores en `/proc/interrupts` |
| — | ESD 86/87 del TDDI | **Refutada como causa** (#610): 1 edge por línea, 36 ms de vida posterior = síntoma |
| — | SMMU-panel | Refutada (#445) |

## Próximos pasos (orden)

1. **Higiene (local, sin tablet)**: diff de L22b commitado ✅ · `ESTADO-VIVO` reescrito ✅ · entrada en
   `NOTAS-OMARCHY.md` ✅.
2. **`e2fsck` en frío** — hay 2 errores `doubly allocated` nuevos y cada flash ensucia más el FS.
3. **Build del kernel de diagnóstico**: `msm.uke_panel_inherit=1` **+ quitar `:d`** de la cmdline
   (para que corra el `prepare`) → así se ve si el BCR mata un prepare real. Un solo objetivo, migas.
4. **Variante DT** (sin build): quitar `resets = <&dispcc DISP_CC_MDSS_CORE_BCR>` de `palawan.dtsi`.
5. **Dato gratis**: `/proc/interrupts` para la IRQ del mdss (descarta/refuta #6 sin gastar un ciclo).
6. **Aparcar `panel-inherit`** como estrategia; el camino real es `prepare` completo + modeset propio
   (plantilla: Xiaomi Pad 6S Pro "sheng", SM8550, que sí tiene display en mainline).

## Riesgos activos

- ⚠️ `slot-retry-count:a` = **7**. Si este boot no se marca exitoso → ABL marca A unbootable y cae a B.
  Tras el próximo flash: **`set_active a` + reboot SIEMPRE**.
- ⚠️ **Batería 3543 mV** < gate 3700. Conectar cargador antes de flashear.
- ⚠️ Los gates de L22b están **en el árbol sin diff** → ahora sí hay diff
  (`build/gates/patches/l22b-mdss-reset-vbif-clk.diff`, dry-run verificado) y **reproduce L22 tal cual**.
- ⚠️ `estilo`: el enfoque multigate (L22b = 3-4 gates) **viola la regla de "un cambio por ciclo"**.

> **Lo que manda es el ledger**: `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` (#553–#612). ·
> Diff L22b: `build/gates/patches/l22b-mdss-reset-vbif-clk.diff`. ·
> Críticas de la noche: `build/gates/revision/{PANEL-INHERIT,CRITICA-CLOCKS-DPU,ESD-MASK-TEST}-20261012.md`.