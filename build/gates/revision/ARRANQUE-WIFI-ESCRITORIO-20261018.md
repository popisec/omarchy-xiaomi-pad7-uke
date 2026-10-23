# WiFi y escritorio al arranque, hora y aviso "Setup Wi-Fi" (senemos v3) — 18-oct-2026 ~00:30 CEST

Estado: **preparado y habilitado para el PRÓXIMO arranque; la tablet NO se ha reiniciado** ni se ha tocado
usb0, `10-uke-usb.network`, sddm/Hyprland en marcha, módulos del kernel ni `/etc/modprobe.d` (la blacklist de
ath11k sigue intacta). Todo lo medido es del arranque en curso (kernel `7.2.9-senemos.1.4054.3-ouke3`, uptime
~2100 s al cerrar). Lo que NO se ha podido probar sin reiniciar está en §8.

## 1. Resumen

| Tema | Resultado |
|---|---|
| WiFi al arranque | `uke-wifi.service` pasa de "armado de un solo uso" a **servicio normal enabled**, ordenado tras `uke-carga`, con interruptor `/etc/uke/no-wifi` y guarda anti-bucle (`uke-bootguard`). wpa_supplicant + DHCP los sigue levantando el propio guion (`uke-wifi-up.sh`) + `20-uke-wlan.network`. |
| Escritorio al arranque | Nuevo `uke-desktop.service` (enabled, WantedBy=multi-user.target) que lanza `sddm` tras `uke-carga` y `uke-wifi`, con interruptores `/etc/uke/no-desktop` y `/etc/uke/safe-mode` y la misma guarda. El viejo enlace directo `multi-user.target.wants/sddm.service` (de `boot-desktop on`) se sustituye por esto. |
| Zona horaria | **Europe/Madrid aplicada** (efecto inmediato: la barra pasó de "Saturday 22:20" a "Sunday 00:21" sin reiniciar nada). |
| Sincronización de hora | **No es systemd-timesyncd**: no está instalado como unidad (`org.freedesktop.timesync1: unknown unit`). El cliente NTP es **chronyd** (enabled desde el 17-oct 20:53, `pool 2.arch.pool.ntp.org iburst`, `makestep 1.0 3`, `rtcsync`): 4 fuentes, offset ~1 ms. Habilitar timesyncd chocaría (`chronyd` lleva `Conflicts=systemd-timesyncd`). No hay RTC útil; `fake-hwclock` (enabled) restaura la hora al arrancar. Añadido `chronyc refresh` + `burst 4/4` tras levantar el WiFi. |
| Aviso "Setup Wi-Fi" | Causa localizada (§5). **No resuelto, solo propuesto**: arreglarlo de verdad exige NetworkManager. No se ha descartado el aviso persistido (§5.3). |
| GPU a los 81 s | **Identificado**: lo abrió `modetest -M msm-kms` de la puerta G3 del flash (§6). No fue ningún servicio del sistema. |

## 2. Qué se cambió en la TABLET

Ficheros (todo con `tar | ssh`, root:root; los shas de la tablet == los del repo, comprobado):

| Fichero en la tablet | Qué es |
|---|---|
| `/usr/local/sbin/uke-bootguard` | guarda: interruptores + dead-man de 2 arranques (§3.3) |
| `/usr/local/sbin/uke-desktop-start` | espera udev/nodos DRM, hace `sync` y `systemctl --no-block start sddm`; no hace nada si sddm ya está activo; **nunca reinicia sddm** |
| `/etc/systemd/system/uke-desktop.service` | nuevo; **enabled** |
| `/etc/systemd/system/uke-wifi.service` | reescrito (normal, no armado); **enabled** |
| `/usr/local/sbin/uke-wifi-up.sh` | misma lógica; añadida una rama defensiva: si wlan0 sale con MAC `00:00:..` re-dispara `udevadm trigger --action=add` para que el `.link` la fije (solo actúa con MAC a ceros) |
| `/etc/uke/LEEME` | documentación de los interruptores en la propia tablet |
| `/var/lib/uke/guard/` | estado de la guarda (vacío ahora) |
| `/etc/localtime` | `../usr/share/zoneinfo/UTC` -> `../usr/share/zoneinfo/Europe/Madrid` (valor anterior anotado en `/root/uke-backup-arranque-20261018/localtime.antes.txt`) |

Símbolos creados por `systemctl enable`: `multi-user.target.wants/uke-wifi.service` y `.../uke-desktop.service`.
`rm -f /var/lib/uke-wifi/armed` (ya no se usa).

Estado en caliente que dejaron las pruebas (inocuo): `uke-wifi.service` figura `active (exited)` (se arrancó a mano
dos veces: el guion vio `ath11k_ahb` ya cargado, no recargó nada y no paró wpa_supplicant: su PID 1591 no cambió ni
la IP 192.0.2.12); `uke-desktop.service` está `inactive` (lo probé con sddm activo = no-op, y lo paré). sddm
(PID 1696) y Hyprland (PID 1797) no se tocaron en ningún momento. El diario de ESTE arranque contiene líneas de mis
pruebas de la guarda (incluida una "DISPARADA" simulada); desaparecen tras reiniciar.

NO se ha tocado: usb0, `10-uke-usb.network`, `/etc/modprobe.d/*`, módulos cargados, sddm/Hyprland, NetworkManager/iwd.

## 3. Diseño

### 3.1 Orden de arranque (un componente arriesgado cada vez)

```
sshd + networkd (usb0, SSH)  ->  uke-carga (ADSP, ~8 s)  ->  uke-wifi (WPSS, ~25-45 s)  ->  uke-desktop (GMU/GPU)
```
Verificado con las dependencias reales de systemd 262 en la tablet (cierre de `multi-user.target`, 177 unidades,
**sin ciclos de ordenación**; `uke-carga` antes de `uke-wifi` antes de `uke-desktop`, `sshd` antes de `uke-wifi`).
Por qué serializar: si algo cuelga la SoC, el diario/consola ACM dicen cuál fue el último en empezar (WPSS y GMU
nunca coinciden). Coste: el escritorio sale tras el WiFi (estimación, no medida en frío: ~45-70 s tras el arranque del kernel).

Decisiones de diseño:
- **No `After=multi-user.target`** para el escritorio: aunque aquí funciona (uke-fix.service lo hace) un target
  añade ordenación implícita sobre sus Wants; es más predecible ordenar explícitamente tras `uke-carga`/`uke-wifi`.
- **Nada depende de `network-online.target`**: `systemd-networkd-wait-online` está enabled y falla a los 120 s
  (medido; solo lo "quiere" `archlinux-keyring-wkd-sync`), y `multi-user.target` se alcanzó a los 8 s. Si el WiFi
  dependiera de eso, retrasaría todo 2 min.
- `uke-desktop-start` es un wrapper (y no un enlace sddm -> multi-user) para que `uke-session start` y
  `systemctl start sddm` sigan funcionando a mano con los interruptores puestos, y para poder hacer `udevadm
  settle` + `sync` justo antes del primer uso de la GPU.
- wpa_supplicant@wlan0 sigue **sin estar enabled**: lo arranca el guion cuando wlan0 ya existe (su unidad lleva
  `Requires=sys-subsystem-net-devices-wlan0.device`; enabled estorbaría con la blacklist).
- `SuccessExitStatus=2` en uke-wifi: AMARILLO (wlan0 existe pero aún no asocia) no es fallo; wpa_supplicant sigue
  reintentando y networkd hará DHCP cuando asocie.

### 3.2 Interruptores (todos SIN reflashear, por SSH; efecto en el PRÓXIMO arranque)

| Quiero... | Hago |
|---|---|
| Arrancar sin WiFi | `touch /etc/uke/no-wifi` |
| Arrancar sin escritorio (WiFi sí) | `touch /etc/uke/no-desktop` (`uke-session start` a mano sigue valiendo) |
| Arrancar sin ninguno de los dos (solo carga + SSH) | `touch /etc/uke/safe-mode` (o `deploy.sh safe-mode on --go` desde el PC) |
| Volver a activarlos | `rm /etc/uke/no-wifi /etc/uke/no-desktop /etc/uke/safe-mode` |
| Deshabilitar las unidades del todo | `build/rootfs/deploy/arranque/deploy.sh revert --go` (o `systemctl disable uke-wifi uke-desktop`) |
| Ver qué decidió la guarda | `uke-bootguard status`; `journalctl -b -t uke-bootguard`; `journalctl -b -1 -t uke-bootguard` |
| Rearmar tras un disparo | `uke-bootguard reset wifi|desktop|all` |

No hay "tecla" (botón) de arranque seguro: Power+Vol- es el atajo de fastboot y Vol+ el de recovery, y leer una
tecla en `multi-user` exigiría un lector de evdev; sin reflashear no hay otro parámetro de arranque, así que el
equivalente sin SSH es la guarda automática (§3.3). Si algún día se reflashea el boot, `systemd.mask=uke-wifi.service`
en el cmdline daría un interruptor más.

### 3.3 Guarda automática `uke-bootguard` (por si el cuelgue impide llegar por SSH)

Problema: sin watchdog (R-42) un cuelgue exige reset físico y **cada reset gasta un reintento del slot**; si el servicio
que cuelga se relanza solo en cada arranque, el bucle se come el slot. Antes lo evitaba el flag `armed` (un intento y
a mano); ahora lo evita esta guarda sin renunciar al WiFi cuando todo va bien.

- `ExecCondition=uke-bootguard begin NAME` (exit 1 = la unidad se OMITE sin marcarse fallida: probado, systemd la
  muestra como `Skipped due to 'exec-condition'`): omite si hay `/etc/uke/no-NAME` o `safe-mode`, si está disparada,
  o si el intento anterior dejó un `pending` de otro `boot_id` (= no llegó a "ok").
- `begin` escribe `/var/lib/uke/guard/NAME.pending` + `sync` ANTES de la fase arriesgada y programa un temporizador
  transitorio (`systemd-run --on-active=180`) que da el "ok".
- "ok" = (wifi) el guion `uke-wifi-up.sh` volvió (ExecStartPost, para no culpar al WiFi de un cuelgue del GMU que
  arranca justo después); (desktop) 180 s vivo; y en los dos casos fallo-sin-cuelgue (ExecStopPost) y apagado ordenado.
- 1 intento sin "ok" -> se reintenta (fallos=1); **2 seguidos -> `NAME.tripped`**: se omite hasta `uke-bootguard
  reset NAME`. Un corte de corriente suelto no desactiva nada. Peor caso con un cuelgue determinista: 2 resets
  (2 reintentos de slot) por componente, y el siguiente arranque ya sale sin él y con SSH.
- Parámetros: `UKE_GUARD_MAX` (2), `UKE_GUARD_WINDOW` (180) (poner `Environment=` en la unidad si se quieren otros).
- **Límite**: protege el ARRANQUE de cada componente, no un cuelgue tardío con el "ok" ya dado.
- Probado: `test-bootguard.sh` (máquina de estados, 31 comprobaciones, en el PC y en la tablet), ciclo real con
  `systemd-run` (pending -> ok a los 4 s), y las rutas de omisión en vivo (no-desktop, safe-mode, tripped).

## 4. Qué se cambió en el REPO (sin commit)

Nuevo `build/rootfs/deploy/arranque/`:
- `root/usr/local/sbin/uke-bootguard`, `root/usr/local/sbin/uke-desktop-start`, `root/etc/systemd/system/uke-desktop.service`,
  `root/etc/uke/LEEME`, `MANIFEST.sha256` (regenerado), `test-bootguard.sh`.
- `deploy.sh` con `check` (PC, sin red), `status`, **`verify`** (lista PASA/FALLA para correr tras reiniciar),
  `apply` (DRY-RUN salvo `--go`; instala, `daemon-reload`, enable, zona horaria; `--no-tz --no-wifi --no-desktop`),
  `revert`, `safe-mode on|off`, `regen-manifest`.

Modificados:
- `build/rootfs/deploy/wifi/root/etc/systemd/system/uke-wifi.service` (unidad normal con guarda, ver §3).
- `build/rootfs/deploy/wifi/root/usr/local/sbin/uke-wifi-up.sh` (rama defensiva de MAC a ceros).
- `build/rootfs/deploy/wifi/MANIFEST.sha256` **regenerado** (`deploy.sh --regen-manifest`, 20 ficheros, verificado).
- `build/rootfs/deploy/wifi/deploy.sh`: `--arm` ahora = `systemctl enable` + `uke-bootguard reset wifi` (exige la guarda
  instalada); cabecera/plan actualizados. `apply` de arranque instala también los dos ficheros del WiFi.
- `build/rootfs/deploy/omarchy/remote/uke-setup.sh` (`boot_desktop` ahora (des)habilita `uke-desktop.service` y retira el
  enlace antiguo sddm -> multi-user) y `omarchy/deploy.sh` (texto). `deploy.sh check` de omarchy sigue en verde.
- Evidencias: `build/logs/capturas/barra-hora-madrid-20261018.png`, `build/logs/capturas/barra-red-sin-NM-20261018.png`.

Reproducir en una tablet limpia (con el firmware WiFi ya desplegado por `wifi/deploy.sh`):
`build/rootfs/deploy/arranque/deploy.sh apply --go`.

NO actualizado (a decisión del coordinador, no hice commit): `docs/historia/ESTADO-VIVO.md`, `NOTAS-OMARCHY.md`. Texto sugerido al final (§10).

## 5. El aviso "Setup Wi-Fi" de Omarchy

### 5.1 Qué mira (leído en la tablet, `omarchy` 4.0.x)
- Lo genera `/usr/share/omarchy/install/user/first-run/wifi.sh`, llamado desde `omarchy-provision-first-run`
  (`hl.exec_cmd` en `/usr/share/omarchy/default/hypr/autostart.lua:7`). Solo corre si falta
  `~/.local/state/omarchy/done/first-run-user` (**ya existe, creado el 17-oct 21:21**: no se vuelve a generar salvo
  `omarchy-provision-first-run --force`).
- Usa **`nm-online`** (NetworkManager): `nm-online -q -x -t 30`; si falla manda la notificación crítica "Setup Wi-Fi" y
  luego espera `nm-online -q -t 3600` (por eso el aviso "Update System" tampoco sale). **No mira iwd ni impala** (ni
  están instalados: `iwd` y `impala` ausentes; `networkmanager 1.58.1` instalado pero parado/disabled).
- La notificación se guardó con `expireTimeout 0` en `~/.local/state/omarchy/notifications/1792272123158-2.json`, así
  que **se muestra en cada sesión hasta que alguien la descarte** (captura del escritorio: "Setup Wi-Fi" y "Learn
  Keybindings" arriba a la derecha).
- Además el **panel de red** (`plugins/panels/network/Panel.qml:68`, `Networking.backend === NetworkBackendType.NetworkManager`,
  y `nmcli` para conectar) y el **icono de red de la barra** leen NetworkManager: con NM parado el icono sale
  "Wi-Fi apagado" tachado aunque wlan0 esté asociada y con ruta por defecto (`barra-red-sin-NM-20261018.png`).

### 5.2 Propuestas (ordenadas de menos a más invasiva)
- **A. Descartar el aviso viejo (no hecho).** El comando oficial es `omarchy-notification-dismiss "Setup Wi-Fi"` (llama a
  `omarchy-shell notifications dismiss`) con el entorno del usuario de la sesión. Lo intenté y **el sistema de permisos
  lo bloqueó** porque interactúa con la sesión viva del dueño; no lo he eludido. Lo puede ejecutar el coordinador o
  basta con que el dueño pulse la X del aviso:
  ```
  ssh -i build/rootfs/uke-arch-root root@192.168.42.129 'U=omarchy; uid=$(id -u $U); xdg=/run/user/$uid; \
    sig=$(ls -t $xdg/hypr | head -1); wld=$(cd $xdg && ls -d wayland-[0-9]* | grep -v "\.lock$" | head -1); \
    runuser -u $U -- env XDG_RUNTIME_DIR=$xdg HYPRLAND_INSTANCE_SIGNATURE=$sig WAYLAND_DISPLAY=$wld \
    omarchy-notification-dismiss "Setup Wi-Fi"'
  ```
- **B. Cosmética del `nm-online` (no hecha).** Un `/usr/local/bin/nm-online` (el PATH da prioridad a `/usr/local/bin`)
  que conteste 0 si hay ruta por defecto vía networkd haría que `wifi.sh` crea que hay red. Solo arregla el aviso
  (y sólo si `first-run` se reejecuta); NO arregla icono ni panel. No lo recomiendo.
- **C. NetworkManager solo para wlan0 (propuesta real, requiere decisión).** Refleja el estado verdadero en barra,
  panel y avisos. Esbozo seguro para usb0 (el gadget quedaría **unmanaged** y seguiría con networkd):
  1. `/etc/NetworkManager/conf.d/10-uke.conf`: `[main] no-auto-default=*` y `[keyfile] unmanaged-devices=*,except:interface-name:wlan0`
     (la sintaxis la acepta `NetworkManager --print-config`, comprobado sin arrancar el demonio).
  2. quitar `20-uke-wlan.network` (networkd no debe hacer DHCP a la vez) y dejar de usar `wpa_supplicant-nl80211@wlan0`
     (NM usa `wpa_supplicant.service` por D-Bus; ya existe `fi.w1.wpa_supplicant1.service`); `uke-wifi-up.sh --no-net` pasa a ser
     el servicio y `NetworkManager.service` se ordena `After=uke-wifi.service`.
  3. crear el perfil con la PSK **ya hasheada** (NM acepta los 64 hex): sin pasar la clave en claro.
  4. riesgo: sin esa condición `unmanaged`, NM se haría con usb0 y se perdería el SSH; y es un cambio de gestor de red
     que conviene probar con `safe-mode`/ACM abierto. Por eso NO lo he hecho.

## 6. Quién abrió la GPU a los ~81 s (solo lectura)

**Fue el propio gate G3 del flash de la v3** (`build/gates/flash-senemos-v3-gated.sh`, líneas ~180-205), no un servicio.

Evidencia (diario persistente del arranque en curso; la GMU carga a 81,35 s):
- `dmesg`: `[81.352828] [drm] Loaded GMU firmware v4.5.1` (+ `adreno ... loaded qcom/gen71100_{sqe.fw,gmu.bin,zap.mbn}` a 81,350-81,358).
- `journalctl -o short-monotonic`: sesión SSH nº 5 desde 192.168.42.1 (el PC) **aceptada a 81,195 s**, GMU a **81,348 s**
  (+0,15 s), sesión cerrada a **111,562 s** (30,4 s = `sleep 30 | modetest ...` del gate). Ningún unit de systemd ni
  otro proceso arrancó entre medias (sddm no existía hasta el arranque manual a 389 s).
- Log del flash (`build/logs/flash-senemos-v3-20261017-235135.log`, líneas 74-114): ahí está la salida de `modetest -M msm-kms -c/-e/-p/-s`.

Mecanismo (código + prueba):
- `drivers/gpu/drm/msm/msm_drv.c:265-273` (árbol `senemos-7.2.9`): `msm_open()` -> `load_gpu()` -> `adreno_load_gpu()`; es decir,
  **cualquier `open()` del nodo DRM de la GPU (card0 o renderD128) arranca el GMU** (el comentario del código: "load gpu on open").
- libdrm resuelve `-M msm-kms` con `drmOpenByName`, que **abre en orden todos los `/dev/dri/card*`** y compara el nombre
  del driver. En v2 `card0` era el display (acierta a la primera); **en v3 `card0` es la GPU** (`msm`) y `card1` el display
  (`msm-kms`), así que el mismo gate abre antes la GPU. Demostrado con un shim `LD_PRELOAD` sobre `open()` en el PC
  (libdrm 2.4.134): `modetest -M <nombre> -c` abre `/dev/dri/card0` y luego `card1`; `modetest -D <ruta>` NO sirve de
  alternativa (`-D` es el busid, no una ruta: recorre igual los nodos).
- El gate G6 afirmaba "renderD128 sin abrir" (cierto: 0 fds) porque corrió **después** de que modetest saliera; el nodo
  que se abrió fue `card0`.
- Resultado: el GMU arrancó bien (`Lucid PLL latch failed. Output may be unstable!` justo antes: **también sale en v2**, boot
  anterior a 5234 s, y el GMU funcionó), sin cuelgue.

Consecuencias prácticas:
1. Cualquier `modetest -M msm-kms` (o cualquier cosa que use `drmOpen` por nombre) en v3 **es un primer uso de la GPU**.
   Si en una prueba futura se quiere que el primer uso sea el de sddm (controlado), no ejecutes modetest antes.
2. En el arranque automático, el primer uso será el de la sesión (Hyprland/aquamarine abre `renderD128` y `card1`; en la sesión
   actual Hyprland tiene abiertos renderD128+card1 y no card0).

## 7. Plan de verificación tras reiniciar (para el coordinador)

Antes de reiniciar (reglas de docs/historia/AGENTS.md): lector ACM único abierto (`uke-console-cap.sh`), sin otro lector; `sync`; nada de
`reboot -f`. Reinicio ordenado: `ssh ... 'sync; systemctl reboot'` (un apagado ordenado con WiFi levantado ya se hizo en v2: poweroff a
los 7018 s, completó). Cada reinicio gasta un reintento del slot (a=7 al flashear).

**Opción de un cambio por ciclo** (regla de docs/historia/AGENTS.md): ciclo 1 solo WiFi (`touch /etc/uke/no-desktop` antes de reiniciar), ciclo 2
con escritorio (`rm /etc/uke/no-desktop`). Si se acepta el riesgo conjunto, un solo reinicio: los dos están serializados y la guarda
limita el daño.

Tras reiniciar (esperar ~90 s; el SSH vuelve antes porque usb0/sshd van primero):
1. `build/rootfs/deploy/arranque/deploy.sh verify` — espera **"RESULTADO: N pasan, 0 fallan"**. Comprueba: unidades enabled/activas,
   sddm/Hyprland/quickshell vivos, guarda sin omisiones, `wlan0` con IPv4 + MAC no nula + `wpa_state=COMPLETED` + ruta por defecto +
   ping 1.1.1.1, usb0 intacto, zona Europe/Madrid, reloj sincronizado, GMU cargado (1 vez) + procesos con la GPU, dmesg sin errores
   de ath11k/GMU/SMMU/Oops, y la línea de tiempos. (Los 5 avisos `regulatory ... -22` de ath11k ya salen en logs anteriores y se
   listan como INFO.)
2. Tiempos esperados (estimación; solo la carga está medida: 8,2 s en este arranque; ver la línea de tiempos de `verify`): `uke-carga` terminada ~8 s; `uke-wifi`
   empieza ~8-9 s y "VERDE: asociado y con IP" ~30-45 s; `uke-desktop-start` ... `Loaded GMU firmware` justo después; escritorio
   en el panel ~50-80 s. Si el WiFi tarda más de 130 s hay un problema (límites del guion: 90 s probe + 40 s asoc).
3. El dueño confirma el escritorio en el panel; capturar `deploy/omarchy/deploy.sh shot` y guardar
   `journalctl -b -o short-monotonic --no-pager > build/logs/arranque-wifi-escritorio-<fecha>.txt` (+ `dmesg`; doble captura, regla 4:
   consola ACM y `ssh ... dmesg -w`).
4. A los >200 s repetir `verify`: la guarda sin `pending` (la prueba de que el "ok" saltó) y `NTPSynchronized=yes` (el WiFi acaba de
   subir; chrony puede tardar ~1 min: es lo único que se puede reintentar sin considerarlo fallo).
5. Decirle al dueño que la hora de la barra debe ser local (Madrid). El aviso "Setup Wi-Fi" seguirá ahí (§5).
6. (Recomendado) segundo reinicio de control: valida persistencia y que el apagado ordenado limpia la guarda (no debe disparar nada;
   `journalctl -b -1 -t uke-bootguard` y `uke-bootguard status`).

Qué NO debería pasar y qué hacer:
- SSH no vuelve: esperar 3 min; si no, reset físico (Power largo) y repetir. La guarda cuenta el intento colgado; al **segundo**
  arranque seguido sin "ok" omite el componente culpable y deja SSH. `uke-bootguard status` + `journalctl -b -1 -k` dicen cuál fue.
- `verify` falla solo en "reloj sincronizado": esperar y repetir (§7.4).
- `uke-wifi` en `failed`: `journalctl -b -u uke-wifi.service`; código 3/4 = WPSS/preflight (no colgó); WiFi sin red pero SSH vivo
  -> diagnóstico normal; `/var/log/uke-wifi.log` y `/var/log/uke-wifi-dmesg-*.txt`.

## 8. Qué NO se ha probado (se probará al reiniciar)

- **El camino de arranque en frío del WiFi** (`modprobe ath11k_ahb` + WPSS lanzado desde systemd a los ~9 s). Lo probado en vivo es la
  unidad con el WiFi ya levantado (idempotente: ejecuta preflight, espera de wlan0 y fase de red). El guion es el mismo de las tres
  pruebas manuales; lo nuevo es cómo lo lanza systemd (PATH mínimo, sin TTY, concurrente con el resto del arranque).
- **sddm arrancado desde `uke-desktop-start` en frío** (probado solo como no-op con sddm activo y con las rutas de omisión).
  `uke-session start` hace lo mismo (`systemctl start sddm`), sin el `udevadm settle` previo.
- El **apagado ordenado con WiFi levantado**: ya ocurrió en v2 (completó) pero sin que el guion `--down` lo precediera.
- `chronyc refresh/burst` tras el WiFi en frío (en vivo respondieron `200 OK`).
- Un **cuelgue real** con la guarda (solo probada su máquina de estados y la mecánica de systemd, no un reset de verdad).
- Efecto secundario conocido: `multi-user.target` ahora espera a `uke-wifi` (hasta 300 s en el peor caso), así que `uke-fix.service` y
  `uke-diag.service` (`After=multi-user.target`, del 3-oct; el primero hace `sleep 20` y `try-restart sshd`; el segundo escribe a
  `/dev/ttyGS0`) correrán más tarde que antes. No molesta, pero conviene saberlo.

## 9. Vuelta atrás

| Nivel | Cuándo | Cómo |
|---|---|---|
| 0. Un componente fuera | WiFi o escritorio dan guerra pero hay SSH | `touch /etc/uke/no-wifi` o `/etc/uke/no-desktop`; efecto al siguiente arranque (en caliente: `uke-session stop`, `uke-wifi-up.sh --down`) |
| 1. Todo fuera | cualquier duda | `touch /etc/uke/safe-mode` (o `arranque/deploy.sh safe-mode on --go`) |
| 2. Volver al modo manual | se quiere quitar el automatismo | `arranque/deploy.sh revert --go` (disable de `uke-wifi` y `uke-desktop` + `reset all`; los ficheros se quedan) |
| 3. Quitar todo | | `systemctl disable uke-wifi uke-desktop; rm /etc/systemd/system/uke-desktop.service /usr/local/sbin/uke-desktop-start /usr/local/sbin/uke-bootguard; rm -r /etc/uke /var/lib/uke`; restaurar `uke-wifi.service` armado: `git checkout -- build/rootfs/deploy/wifi/root/etc/systemd/system/uke-wifi.service` + `wifi/deploy.sh --go` |
| 4. Hora | | `timedatectl set-timezone UTC` (valor anterior: `/etc/localtime -> ../usr/share/zoneinfo/UTC`) |
| 5. Sin SSH tras un cuelgue | | reset físico; la guarda omite el componente al 2.º arranque fallido seguido (§3.3). Si ni arranca: fastboot manual y el rollback ya previsto (`flash-senemos-v3-gated.sh`: v2 `7848d68d`, v3 `5c9fb2c6`) |

## 10. Pendientes y propuestas (no aplicadas)

1. Descartar el aviso "Setup Wi-Fi" persistido (§5.2 A) y decidir si se adopta NetworkManager solo para wlan0 (§5.2 C).
2. Opcional: `systemctl disable systemd-networkd-wait-online.service` (falla a los 120 s cada arranque; solo lo quiere
   `archlinux-keyring-wkd-sync`; no retrasa `multi-user.target`). Pura limpieza.
3. `uke-fix.service` y `uke-diag.service` (3-oct) siguen enabled; `uke-diag` escribe a `/dev/ttyGS0`. Valorar quitarlos.
4. Las líneas `ath11k ... Failed to set the requested Country regulatory setting / failed to process regulatory info -22`
   salen en este arranque y en logs previos (`build/logs`); WiFi funciona; sin diagnosticar.
5. Regla para los gates: en v3, `modetest -M msm-kms` abre la GPU (§6); el G6 "renderD128 sin abrir" debería comprobar también `card0`.

### Texto sugerido para NOTAS-OMARCHY.md
> 2026-10-18 (madrugada, 3): WiFi y escritorio preparados para el arranque (sin reiniciar). `arranque/deploy.sh apply --go`:
> `uke-wifi.service` normal tras `uke-carga`, `uke-desktop.service` (lanza sddm; el cmdline sigue en multi-user), guarda
> `uke-bootguard` (interruptores `/etc/uke/{no-wifi,no-desktop,safe-mode}` + dead-man de 2 arranques), TZ Europe/Madrid
> (chronyd, no timesyncd, sincroniza), GPU a los 81 s = `modetest -M msm-kms` del gate (libdrm abre card0=GPU), "Setup Wi-Fi" =
> `nm-online` del first-run (solo NM). Plan de verificación y vuelta atrás: `build/gates/revision/ARRANQUE-WIFI-ESCRITORIO-20261018.md`.
