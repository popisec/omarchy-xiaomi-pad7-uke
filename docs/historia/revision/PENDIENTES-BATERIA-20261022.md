# PENDIENTES de batería / carga / consumo — traspaso a la sesión de optimización (22-oct-2026)

Sesión «batería» cerrada por fusión. Última actualización de esta sesión: commit anterior `2f4fe76`; este fichero va en un commit propio (ver `git log -1 -- docs/historia/revision/PENDIENTES-BATERIA-20261022.md`). La tablet no se tocó al escribirlo.

## 1. Qué está desplegado y activo en la tablet (21-oct; todo en `build/rootfs/deploy/bateria/`, `deploy.sh apply|revert|status|check`)
| Pieza | Función |
|---|---|
| `uke-bateria-lectura` | % exacto = `charge_counter/charge_full` (= `fg1_rsoc/100`, verificado con Android), W (+ = descarga), tiempo estimado |
| `uke-perfil` + `/etc/uke/perfiles.conf` | perfiles Ahorro/Equilibrado/Rendimiento (ids power-saver/balanced/performance); `powerprofilesctl` falso para Omarchy; persistente (`uke-perfil.service` + autostart `apply-user`). Brillo tope: 25/50/0 %. Reposo hypridle: Ahorro 1/2/10 min, resto 2/3/15 |
| `uke-refresco` + regla udev `90-uke-icl.rules` | 120 Hz con cargador, 60 Hz en batería (por evento), conserva transform/escala. **Probado con cargador; falta probarlo en batería real** (el log mostró 60 Hz en descarga el 21-oct 22:46 en adelante) |
| `uke-icl` (udev + arranque + log) | sube el ICL USB de 100 mA (valor por defecto del firmware) a 500 mA; solo sube, solo con VBUS<6 V ⇒ no afecta a PD/PPS. **Arreglo de «no cargaba con el PC»** |
| `uke-bateria-log` | CSV cada 60 s en `/var/log/uke-bateria/AAAA-MM-DD.csv` (+ `arranques.log` con `bootinfo.pureason`); `uke-bateria-informe [días]` |
| `uke-idle-guard` | inhibe reposo/suspensión mientras haya SSH (puerto 22) |
| `uke-modo-carga` (+`-boton`, `uke-apagar`) | si el arranque es por cargador (`pureason=0x40010`, lista en `/etc/uke/modo-carga.conf`) no arranca `sddm` hasta pulsar el botón. Salida: `touch /var/lib/uke-bateria/forzar-escritorio` |
| Widget `uke.bateria` | `%` exacto + W + perfil en la barra (powerbar), clic = siguiente perfil |
Mediciones armadas en la tablet: **ninguna** (desarmadas 21-oct). Quedó un temporizador transitorio `uke-drenaje-restaura.timer` (inofensivo: enciende pantalla).

## 2. Hallazgos que condicionan el resto (evidencia en `BATERIA-20261019.md`, `docs/historia/revision/ANDROID-VS-LINUX-BATERIA-20261021.md`, `docs/historia/revision/CARGA-LENTA-DRIVERS-20261020.md`, `CONSUMO-DESGLOSE-20261020.md`, `docs/historia/revision/ANDROID-BATERIA-MAPA-20261020.md`)
- Mismo gauge en Android y Linux; signo de `current_now` **opuesto** (Linux + = carga; Android + = descarga); `charge_counter` µAh (Linux) / mAh (Android). Para autonomía fiarse del gauge, no de `current_now`·V (~20 % más alto).
- El ADSP decide ICL/FCC en ambos SO. Cargador PD/PPS 33 W en Linux: **19,7 W** a la batería (+4,45 A a 4,43 V al 93 %). Puerto del PC (SDP): 500 mA; con cable/puerto de 1 A llegó a `input_current_limit=1000000`. El kernel rechaza >500000 desde sysfs (parche Uke en `qcom_battmgr.c:1077`).
- Consumo (20-oct, deltas fiables; con cargador): +1,05 W pantalla encendida vs DPMS off, retroiluminación 2,3 mW/paso (50 % = +2,0 W), 120 Hz +0,45 W / 90 Hz +0,28 W, WiFi 0,36 W; perfiles CPU/GPU sin efecto medible en reposo.
- Absoluto sin cable (21-oct 22:45, Equilibrado, 99 %): **pantalla 5 %/60 Hz 1,97 W; DPMS off 0,93 W** (`medidas/drenaje-linux-20261021-224548.csv`). **65 min de descarga real** (22:46–23:51): 100→95,81 %, **3,88 %/h ⇒ ~24,5 h** (1,50 W por gauge; 1,85 W por corriente) (`medidas/log-2026-10-21.csv`). Autonomía estimada por situación: `docs/historia/revision/AUTONOMIA-PERFILES-20261021.md`.
- Consumidores en el log: `uke-touchd.py` 10–15 % de un núcleo con pantalla encendida (sondeo a 120 Hz por «sin IRQ EBUSY»; 0 con DPMS off), `tailscaled` 2–4 %, IRQ altas (arch_timer ~680/s, IPI ~470/s).

## 3. Pendientes (primer paso de cada uno)
1. **Suspensión (s2idle) sin medir** — hipótesis ≤0,3 W. Solo hay suspensiones con cargador (p. ej. 7,75 h el 21-oct). Primer paso: desenchufar con >30 %, dejar suspender por reposo sin SSH abierto 1–2 h, leer en el log las filas `event=resume` (`susp_s`, Δ`charge_uah`); coordinar con la sesión de BT (gancho `uke-bt-sleep`, IRQ 229 del UART BT despierta a 0,7 s) y valorar `modprobe qcom_stats` (pide autorización).
2. **Drenaje real con uso real y de larga duración** (vídeo, navegador, perfiles) — hay 1 pasada de reposo + 65 min. Primer paso: `carga-rapida/medir-linux-descarga.sh` (Tailscale, espera Discharging ≥20 %) y recoger `/var/log/uke-bateria/*.csv`; `uke-bateria-informe 7` (ojo: etiqueta «descarga» también filas `Charging` con drenaje neto >0,3 W; filtrar por `estado=Discharging` para uso real).
3. **Carga rápida en Linux, completa**: falta VBUS (9 V) y tipo; hay 19,7 W al 93 % (cae con el final de carga). El adaptador es PPS **33 W** (no 45 W). Primer paso: batería <80 %, cargador de pared sin cable al PC, `carga-rapida/medir-linux-carga-rapida.sh 180`.
4. **Probar `uke-refresco` en batería real** y el efecto en el widget: desenchufar y comprobar 60 Hz; reenchufar y 120 Hz.
5. **Modo carga**: ver el `pureason` de un encendido normal con botón (los reinicios de audio dan `0x40001`; el de cargador `0x40010`); si coincidieran, usar `forzar-escritorio`.
6. **Referencias de Android sin medir**: descarga real en reposo limpio y carga rápida: scripts `build/android/bateria-20261019/medir-android-{descarga,carga-rapida}.sh` (necesitan la tablet en Android y cambiar el cable). El «~1,4 W de Android» heredado no tiene fuente medida.
7. **WiFi caído (21-oct 23:52)**: `NetworkManager is not running` y Tailscale `offline` visto por USB; causa sin investigar (no es de batería).

## 4. Decisiones abiertas (no autorizadas / otras sesiones)
- DT: `usb-psy-name` en dwc3 y `MaxPower` del gadget USB (propuesta de `docs/historia/revision/CARGA-LENTA-DRIVERS-20261020.md`; requiere autorización y flash; puede retrasar el SSH por USB).
- Kernel (`docs/historia/revision/OPTIM-KERNEL-20261020.md`): `fw_devlink.sync_state=timeout deferred_probe_timeout=30` (0,1–0,4 W, requiere flash); quitar `*_ignore_unused` (alto riesgo); `rcu_expedited` sin efecto medible. **Opción 2 (apagado real sin que el cargador la encienda): NO viable** desde Linux (`docs/historia/revision/PON-CARGADOR-VIABILIDAD-20261020.md`; lo único: `CONFIG_BOOT_CONFIG=y` para ver `androidboot.mode=charger`, hipótesis, requiere flash).
- Userspace (`docs/historia/revision/OPTIM-USERSPACE-20261020.md`): `uke-touchd` por IRQ (sesión Táctil), `bt-agent` reiniciándose 27 veces/min (sesión BT), plugins Quickshell `navidrome`/`hyprmoncfg` con error, journald 702 MB.
- Commit `d047688` (agente de consumo) incumplió «no commitear»; revisado: contenido correcto; recomiendo conservarlo.

## 5. Dónde está todo
- Scripts y despliegue: `build/rootfs/deploy/bateria/` (`README.md`, `deploy.sh`, `carga-rapida/`, `medidas/`, `root/`, `plugin/uke.bateria/`).
- Informes: `build/gates/revision/{BATERIA-20261019,AUTONOMIA-PERFILES-20261021,ANDROID-VS-LINUX-BATERIA-20261021,ANDROID-BATERIA-MAPA-20261020,CARGA-LENTA-DRIVERS-20261020,CONSUMO-DESGLOSE-20261020,OPTIM-KERNEL-20261020,OPTIM-USERSPACE-20261020,PON-CARGADOR-VIABILIDAD-20261020}.md`.
- Datos: `build/android/bateria-20261019/` (capturas Android; `mapa/`, `carga-rapida/`), `build/logs/bateria-20261021/` (CSV 19–21-oct, **ignorado por git**), `build/logs/consumo-20261020/` (A/B del agente; ídem).
- Acceso: `ssh -i build/rootfs/uke-arch-root -o BatchMode=yes root@uke` (Tailscale; respaldo USB `root@192.168.42.129`). Ojo: el script remoto de una unidad no debe sobrescribirse mientras corre.
