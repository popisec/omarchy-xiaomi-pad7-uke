# Optimización de energía en userspace (solo lectura) — 20-oct-2026 13:00–13:15

Medido por SSH sin generar carga (una muestra de ps, /proc, journal, config). Estado: tablet cargando por USB, perfil `power-saver`, panel 3200x2136@**60 Hz**, backlight 102/2047, uptime 32 min. Sin powertop, así que los ahorros son **estimaciones** (marcadas «est.»), no medidas. Consumo de referencia: 3,6 W despierta frente a 1,4 W de Android, así que hay ~2,2 W que explicar. La CPU de userspace es pequeña; el grueso probablemente está en panel/GPU/SoC. Lo de abajo recorta lo que se puede tocar desde userspace.

## Medidas base
| Fuente | Dato medido | Lectura |
|---|---|---|
| `uke-touchd.py` (otra sesión) | 11,9 % CPU en ps; 12,8–14,4 % en el CSV de uke-bateria-log; 306 k cambios de contexto en 31 min (~165/s) | Lo citado (36 %) era a otro momento. IRQ `uke-touch` 203 954 y `gpi-dma` 207 646 en 1 900 s ≈ **107–120/s**: el sondeo a 120 Hz mantiene vivos CPU, GPI-DMA/SPI y el reloj. |
| arch_timer / IPI «Function call» | 600–850/s y 335–570/s (CSV) | Reflejan que hay cosas despertando a ~120 Hz (tacto) más timers de Quickshell. |
| quickshell | 3,3 % CPU, 819 MB RSS, 36 hilos; hilo principal ~1,9 % de un núcleo medio; 45 k ctxsw | Moderado. 800 avisos `Socket error ... ServerNotFoundError` en 10 min (80/min). |
| Hyprland | 1,2 % CPU | Bien. |
| bt-agent (user omarchy) | 269 reinicios en 10 min (**27/min**) | Fallo: `bt-agent` no está instalado. |
| audit | 735 líneas `audit:` en 10 min (1,2/s); 102 `USER_START`/10 min ≈ 10 sesiones SSH/min | Proviene de las sesiones SSH (otro agente midiendo). Irrelevante en uso normal. |
| journal | 6 225 líneas en 10 min (~10/s); 702,5 MB en disco; `/` al 88 % | Casi todo es bt-agent (269×5 líneas = 1 345), Quickshell (800) y audit (~735). |
| WiFi | `iw wlan0 get power_save` = **off** | Ver hallazgo 2. |
| cpuidle | solo WFI + silver-cluster0; GPU casi todo en 255 MHz (67 s de 112 s) | GPU ya está en reposo; animaciones no pesan. |
| Hyprland | animaciones on, sombras/blur/rounding **off** (default de Omarchy), vrr 0, damage_tracking 2 (completo), `misc:vfr` no existe en 0.56 como opción de lectura | Config ligera; sin ahorro relevante aquí. |
| hypridle | un solo proceso, 300 s atenuar 5 % / 600 s DPMS off / 1800 s suspender | Ver hallazgo 4. |

## Hallazgos ordenados por ahorro/riesgo

### 1. Sondeo táctil a 120 Hz (otra sesión, solo documento el coste)
Coste: ~12–14 % de un núcleo + 120 IRQ/s de `uke-touch` y otras tantas de `gpi-dma` ⇒ impide entrar en estados profundos. Est. **0,2–0,5 W** (tres wakeups por evento: IRQ, DMA y proceso Python). Palancas posibles, **de la sesión Táctil**: (a) conseguir IRQ real (el EBUSY de `sin IRQ`); (b) sondeo adaptativo: 120 Hz solo con contacto reciente y 10–20 Hz tras 2 s sin toque; (c) parar `uke-touch.service` con la pantalla apagada (DPMS). **No lo toco.**

### 2. WiFi con power save desactivado — ahorro est. 0,15–0,4 W, riesgo bajo
`wlan0` tiene `Power save: off` (también así con SSH/Tailscale activos, mientras el router aísla clientes). Con PS on suben la latencia SSH unos 50–200 ms y alguna caída de throughput.
```
# runtime (reversible al instante)
iw dev wlan0 set power_save on
# persistente
cat > /etc/NetworkManager/conf.d/uke-wifi-powersave.conf <<'X'
[connection]
wifi.powersave = 3
X
systemctl reload NetworkManager
```
Revertir: `iw dev wlan0 set power_save off` y borrar el fichero. **Interfiere con la medición en curso** (cambia el consumo base) → aplicar solo cuando el otro agente termine.

### 3. Bucle de reinicios de bt-agent — ahorro est. 0,05–0,15 W, riesgo nulo
`/usr/lib/systemd/user/bt-agent.service` hace `ExecStart=/usr/bin/bt-agent` (paquete `bluez-tools`, ausente), `Restart=on-failure`, `RestartSec=2`: cada 2 s forkea systemd, falla, escribe 5 líneas al journal (UFS) y repite. Ruido: 27 reinicios/min y 135 líneas/min.
Arreglo mínimo, sin tocar /usr:
```
systemctl --user -M omarchy@ mask bt-agent.service      # si no se usa pairing auto-accept
# o: pacman -S bluez-tools (si se quiere el agente)
```
Revertir: `systemctl --user -M omarchy@ unmask bt-agent.service`. (Es BT, pero solo documentado/desactivar un servicio roto; confirmar con la sesión de audio/BT antes de aplicar.)

### 4. Tiempos de hypridle y atenuación — ahorro est. 0,3–0,8 W en uso real (reposo con pantalla encendida), riesgo bajo
El panel a 5 % ya consume bajo, pero hoy hay 5 min a brillo normal + 5 min a 5 % antes de apagar el panel. El panel DSI (3200x2136) es con diferencia el mayor consumidor (no medido aquí). Propuesta:
```
# ~/.config/hypr/hypridle.conf
timeout = 120   # dim 5 %  (antes 300)
timeout = 180   # DPMS off (antes 600)
timeout = 900   # suspender (antes 1800)
```
Revertir: restaurar valores; hay `hypridle.conf.bak-10s`. Decisión del dueño: él alargó los tiempos el 18-oct. `uke-idle-guard` ya evita suspender con SSH abierta (comprobación cada 10 s con `sleep`).

### 5. Frecuencia del panel — est. 0,1–0,3 W, riesgo bajo
Ya está en 60 Hz (power-saver). En modo equilibrado el perfil usa 90 Hz y en rendimiento 120 Hz. Sugerencia: no pasar de 60 Hz fuera de `rendimiento`; 48 Hz (modo existente) como opción para lectura estática. Cambio = `hl.monitor({ output="DSI-1", mode="3200x2136@48", ... })` en `monitors.lua` o vía `uke-perfil`. Revertir: volver al modo previo.

### 6. Avisos de Quickshell `ServerNotFoundError` (80/min) — ahorro est. <0,05 W, riesgo bajo
Un `Socket` de plugin (candidatos: `crmne.hyprmoncfg/PreviewGuard.qml`, `Panel.qml`, `backmeupplz.navidrome/Service.qml`) reintenta conectar a un socket inexistente (navidrome/hyprmoncfg sin servidor). Deshabilitar los plugins que no se usen en la tablet: `omarchy-shell` → plugins → desactivar `backmeupplz.navidrome` y `crmne.hyprmoncfg` (o quitarlos de la lista de plugins habilitados). Reduce además 800 líneas/10 min de journal. Revertir: reactivarlos. No tocado.

### 7. Polling de la barra
- `uke.bateria/BarWidget.qml`: timer de 10 s que lanza un proceso (`poll`) → 6 forks/min. Ahorro mínimo (<0,02 W). Subir a 30 s en pantalla encendida y 60 s en `power-saver` reduce forks; riesgo nulo.
- `uke.network/Panel.qml`: timers de 1,5–4 s solo con `running: root.opened` (panel abierto): no cuesta en reposo.
- `p0werj0int.powerbar`: timers de 90–250 ms disparados por gestos, no repetitivos.

### 8. uke-bateria-log (60 s) — <0,02 W
Python con `time.sleep(INT)` y `Nice=10`; despierta 1×/min. Dejarlo.

### 9. Servicios en memoria innecesarios para una tablet — ahorro est. <0,05 W (más RAM)
En ejecución: `systemd-homed`, `systemd-nsresourced`, `systemd-userdbd`, `tailscaled` (0,6 % CPU), `wireplumber`, `upower` (0,4 %), `at-spi-dbus-bus`, `gvfs-daemon/metadata`, `xdg-document-portal`, dos `wl-paste --watch` del portapapeles (despiertan por evento). `systemd-homed` no se usa: `systemctl disable --now systemd-homed` (riesgo: ninguno si no hay usuarios homed; revertir con `enable`). Tailscale sirve para SSH por WiFi: dejarlo, pero su polling es casi nulo (260 ctxsw en 31 min).

### 10. Audit y journald a UFS — <0,05 W, riesgo bajo
Hay `audit` activo en el kernel (`auditctl -s` → `enabled 1`, sin auditd, 0 reglas) y los eventos `USER_START/CRED_ACQ` por cada login SSH van al journal (y a consola ttyGS0/nivel 7 si hay lector). En uso normal son pocos; solo importan con sondeos por SSH frecuentes. Opciones: `auditctl -e 0` en runtime, o `audit=0` en cmdline (**requiere reflashear boot.img: otra sesión/ciclo de ledger**). journald: `Storage=persistent` por defecto con 702 MB; para escribir menos a UFS, `/etc/systemd/journald.conf.d/uke.conf`:
```
[Journal]
SystemMaxUse=100M
SyncIntervalSec=5m
```
Revertir: borrar el fichero. Limpieza puntual (`journalctl --vacuum-size=100M`) es borrado de datos: lo dejo a decisión del dueño.

### 11. Animaciones de Hyprland
Activas (`windows`, `fade`, `border`, ~0,1–0,4 s). GPU en 255 MHz el 60 % del tiempo y sombras/blur desactivados: coste despreciable cuando no hay movimiento. Desactivar (`animations = { enabled = false }`) solo ayudaría durante el gesto; no recomendado por ahorro.

## Resumen de prioridades
1. Táctil: sondeo adaptativo/IRQ (0,2–0,5 W, sesión Táctil).
2. WiFi power save on (0,15–0,4 W, aplicar tras las mediciones).
3. hypridle más corto (0,3–0,8 W en uso, decisión del dueño).
4. Enmascarar `bt-agent` (0,05–0,15 W, pregunta a sesión BT).
5. Desactivar plugins `navidrome` y `hyprmoncfg`, journald acotado, `homed` (suman <0,15 W pero quitan ruido).
Total userspace alcanzable est. **0,5–1,2 W** sobre los 3,6 W; el resto hasta ~1,4 W (Android) probablemente exige kernel/firmware (cpuidle de clusters gold/prime, devfreq/panel, DSI LP, modem/BT radios). Esto no está comprobado aquí.

## Dependencias de otras sesiones
Táctil (1), audio/BT (3), reflash cmdline (10 `audit=0`), medición de consumo en curso (2, 4, 5).
