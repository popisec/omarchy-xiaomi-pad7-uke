# Revisión de optimización del sistema — 20-oct-2026 (≈23:35, ouke5, uptime 2 min tras el flash v6)

Mediciones por SSH, solo lectura. Complementa (no repite) `BATERIA-20261019.md`, `docs/historia/revision/OPTIM-USERSPACE-20261020.md`, `docs/historia/revision/OPTIM-KERNEL-20261020.md`.

## 1. Mediciones
| Área | Medido | Lectura |
|---|---|---|
| Arranque | kernel 1,06 s + userspace 60,5 s (multi-user; `graphical.target` no se usa). blame: `uke-fix` 24,1 s, `uke-audio-amps` 22,2 s, `uke-desktop` 12,0 s, `uke-bt` 11,3 s, `uke-wifi` 8,1 s, `uke-audio` 7,6 s, `uke-carga` 4,7 s | `uke-fix` es un `sleep 20` + `try-restart sshd` + volcados a kmsg: resto de depuración, no bloquea el escritorio pero repite un reinicio de sshd en cada arranque. |
| Fallidos | `bluetooth.service`: **bluetoothd aborta** (`double free or corruption`, `a2dp_select_capabilities: Unable to select SEP`, core 23:32). Timers `shadow`, `fake-hwclock-save` ahora ok | Caída de bluez en A2DP: **para la sesión BT**. |
| Reposo | IRQ totales **445/s**: arch_timer 296/s (≈37/s por núcleo, HZ=250), IPI call 93/s, `ce2` (SPI táctil) 21,6/s, UART 4,9/s, glink 3,8/s, UFS 3,1/s | El táctil ya no es el 120 Hz de antes (21/s). El tick de 250 Hz + IPI son lo que queda; con `NO_HZ_IDLE` y CPUs en WFI no es grande. |
| CPU reposo (top) | systemd 14,8 % (arranque), python3 12,8 % (uke-touchd tras arranque), quickshell 3,4–4,6 %, Hyprland 1,2–1,9 %, tailscaled 1,5–1,8 % | Todo moderado. quickshell RSS 543 MB. |
| cpuidle | ahora **WFI + silver-c3 + silver-cluster0** (en ouke5 antes eran solo WFI + cluster0): usage cpu0 65 798 / 8 480 / 29 456 | Mejora ya presente; **faltan gold/prime** (cpu3-7 solo muestran los estados `silver`→ comprobar `cpu7`). |
| Governor | cmdline `cpufreq.default_governor=performance`; en marcha **schedutil** (perfil power-saver), `sched_pelt_multiplier=4`; cpu0 441 MHz, cpu3 1,4 GHz, cpu7 480 MHz | Perfil de la sesión batería. |
| devfreq | GPU `simple_ondemand` en 255 MHz; UFS `simple_ondemand` | OK. |
| Memoria | 7,4 GB: usados 1,9 GB, libres 4,4 GB, **sin swap ni zram** (`CONFIG_ZRAM` y `ZSWAP` **no están** en el kernel) | Sin presión hoy, pero sin red ante picos (Firefox). Kernel. |
| THP | `always` | Más compactación/khugepaged en una tablet de 8 GB; `madvise` es lo habitual. |
| Disco | `/` 7,9 G al **89 %** (872 MB libres); journal **747 MB**; pacman cache 274 MB; coredump quickshell 19 MB; **ext4 «not clean with errors»**, sin `has_journal`, montado `rw,norecovery`; errores vivos `deleted inode referenced` (wireplumber, 8 en 2 min) | **Corrupción real y sin journal**: e2fsck en frío pendiente (dueño). Un corte de energía no se recupera. Sin `fstrim` posible sin comprobar. |
| journald | 3 600 líneas en 5 min (≈12/s): kernel 1 790 (arranque, audit, dependencias OF), omarchy-shell 386 (`ServerNotFound` ×362), hypridle 232, tailscaled 204 | Sin tope configurado (`journald.conf.d` no existe). |
| WiFi | `power_save on` (ya aplicado por otra sesión; el .conf de Omarchy dice `powersave=2` pero el runtime está en on) | Hecho. |
| bt-agent | activo, sin reinicios (arreglado) | Hecho. |
| RTKit | `rtkit` ausente: pipewire/wireplumber/portal pierden prioridad en tiempo real (`RTKit error ServiceUnknown` ×3 cada uno) | Latencia de audio y posibles xruns. Paquete: bajar del mirror ALARM con .sig + `pacman -U` (no hecho). |

No medido: latencia de apertura de apps (Firefox, terminal) y consumo vatios (la sesión batería ya midió: suelo 1,39 W, pantalla +1,05 W, 120 Hz +0,45 W). El sistema acababa de arrancar (uptime 2 min), así que cualquier CPU es sesgada al alza.

## 2. Lista priorizada
### (a) Userspace
| # | Mejora | Ganancia est. | Riesgo | Reversión | Estado |
|---|---|---|---|---|---|
| 1 | journald: `SystemMaxUse=150M` + `SyncIntervalSec=5m`, vacuum a 150 M; coredump `MaxUse=64M` | libera ≈600 MB (89 %→~81 %); menos escrituras a UFS; <0,05 W | bajo (se pierden logs antiguos) | `deploy.sh revert` | **preparado, pendiente de autorización** |
| 2 | THP `always`→`madvise` | menos compactación; mejor latencia | bajo | `revert` | preparado |
| 3 | deshabilitar `systemd-homed` | −RAM/PID, ≈0 W | nulo si no hay usuarios homed | `revert` | preparado |
| 4 | `e2fsck -fy` en frío de `/dev/sda32` (+ crear journal con `tune2fs -j`) | evita corrupción progresiva y errores de wireplumber | medio: requiere desmontar (arrancar de otro sitio) | — | **dueño** |
| 5 | instalar `rtkit` (ALARM .pkg + .sig, `pacman -U` tras comprobar dependencias) | menos xruns de audio | bajo | `pacman -R rtkit` | propuesta |
| 6 | Quickshell: desactivar plugins `backmeupplz.navidrome` y `crmne.hyprmoncfg` (800 avisos/10 min) | CPU + journal, <0,05 W | bajo, visible en la barra | reactivarlos | propuesta (dueño) |
| 7 | `uke-fix.service`: eliminar `sleep 20` y el `try-restart sshd` (mover el `chmod` de `empty.sshd` a tmpfiles) | arranque −24 s en cola, evita reiniciar sshd cada boot | medio (puede dejar sshd sin pasar de mala permisión) | restaurar unit | propuesta |
| 8 | `uke-touchd`: IRQ real/ sondeo adaptativo | 0,2–0,5 W (ya mitigado a ~21 IRQ/s) | — | — | sesión táctil/batería |
| 9 | limpiar caché pacman (274 MB) con `paccache -rk1` | +270 MB libres | nulo | — | propuesta (borrado) |
| 10 | hypridle más corto (120/180/900 s) | 0,3–0,8 W en uso | bajo, **visible** | `hypridle-normal.conf` | decisión del dueño (sesión batería) |

> **Corrección 21-oct**: los puntos (b)2 y (b)3 de abajo están superados por `docs/historia/revision/OPTIMIZACION-KERNEL-PROPUESTA-20261021.md` (gold/prime SÍ tienen estados cpuidle; HZ=100 no se recomienda).

### (b) Kernel (no tocar: v6 recién flasheado por la sesión de cámaras; todo en un solo flash con ledger)
1. **`CONFIG_ZRAM=m/y` + `ZSMALLOC` + `CRYPTO_ZSTD`** (y `ZSWAP` opcional): memoria 8 GB con 0 swap. Ganancia: robustez, no vatios. Riesgo bajo; módulo en `extra/` no requiere flash de boot.
2. **cpuidle**: ya hay `silver-c3`; faltan los estados de los clusters gold (3-6) y prime (7) en el DT (`idle-states`/PSCI domain de ouke5). Ganancia: la mayor del bloque (parte de los 2,2 W entre 3,6 W y 1,4 W de Android); riesgo medio-alto (colgados de PSCI). Referencia: capturas de Android en `build/android/`.
3. **`CONFIG_HZ=100` o `HZ_250` con `NO_HZ_FULL` no**: bajar a HZ=100 recorta ≈150 wakeups/s en arch_timer cuando hay carga; −0,02..0,05 W; latencia −. Riesgo bajo, pero toca todo el kernel: junto con el resto.
4. **`CONFIG_PREEMPT` → `PREEMPT_VOLUNTARY`**: ligero ahorro de overhead; marginal.
5. **governor**: cmdline `cpufreq.default_governor=performance` → `schedutil` por defecto (hoy lo corrige userspace al arrancar el perfil, pero entre `ukeinit` y `uke-perfil` va a máxima) + `TEO` en vez de `MENU` para cpuidle (`CONFIG_CPU_IDLE_GOV_TEO=y`): mejor en dispositivos con estados poco profundos y wakeups periódicos. Ganancia est. 0,05–0,2 W.
6. `audit=0` en cmdline (≈0 W; quita ruido del journal).
7. devfreq de DDR/LLCC (`qcom-cpu-bwmon`, `llcc-bwmon`): hoy sin carga de interconnect por dominios; requiere drivers de la serie senemos — a investigar con camaras para no pisar el árbol.

Coordinación: **no se ha tocado el árbol de kernel**. La propuesta debe ir a `local_6d9b369f` (cámaras) cuando cierre v6, y a la sesión batería (`local_cde7fc8b`) lo de cpuidle/governor.

## 3. Aplicado (autorizado por el dueño, `deploy.sh apply`, 23:4x)
| Cambio | Antes | Después |
|---|---|---|
| journald `SystemMaxUse=150M`, `SyncIntervalSec=5m` + vacuum | 746,5 M | **149,1 M** |
| `/` | 6,7 G usado, 872 M libres, **89 %** | 6,1 G, **1,5 G libres, 81 %** |
| THP | `always` | `madvise` (persistente por tmpfiles) |
| `systemd-homed` | enabled/active | disabled/stopped |
| coredump | sin tope | `MaxUse=64M` (los cores existentes siguen; se aplica al siguiente) |
Verificado: journald activo, sin unidades nuevas fallidas (solo `bluetooth.service`, previo). Reversión: `deploy.sh revert` (no recupera logs vacuados). Efecto en vatios no medible (<0,05 W est.); el beneficio es espacio y menos escrituras a UFS. Pendiente de pedir al dueño: #4–#10 y la propuesta de kernel (§2b).

## 4. Hallazgos para otras sesiones
- **BT**: `bluetoothd` aborta con `double free` al seleccionar SEP A2DP (coredump 23:32, `/var/lib/systemd/coredump/`).
- **Lápiz/táctil**: ahora ≈21 IRQ/s de `ce2`.
- **Dueño**: ext4 con errores y sin journal: `e2fsck` en frío antes de seguir acumulando ciclos.

## 5. Segunda tanda (autorizada por el dueño, 23:4x)
- **Los «128 GB»**: `userdata` (sda32) mide **105,9 GB**, pero el ext4 (`uke-root`, 2 097 152 bloques de 4 KiB = **8 GiB**) se grabó con la imagen de 8 GiB y **nunca se amplió**; `lsblk` ve sda de 117,1 GiB. Es el único hueco: el resto son particiones Android (super 10,5 G, etc.). **Ampliación en caliente RECHAZADA por el kernel**: `ext4_resize_begin: There are errors in the filesystem, so online resizing is not allowed` (error ext4_lookup #67972 = `/home/omarchy/.local/state/wireplumber`, entrada que apunta al inode borrado 70795; 10 errores, EFSCORRUPTED). **Siguiente paso**: `e2fsck -fy /dev/sda32` con el fs desmontado (arrancar el rescate/`rescue` o parar todo y remontar `ro`; requiere al dueño) y luego `resize2fs /dev/sda32` (online o en frío; `Reserved GDT blocks` 255, de sobra). Backup de userdata antes (no hay uno reciente).
- **rtkit 0.14-2** instalado (mirror ALARM, .sig verificada por pacman -U; la BD local decía 0.14-1 y daba 404, el mirror ya tiene -2; dependencias ya presentes). `rtkit-daemon` se activa por D-Bus; pipewire/wireplumber lo usarán al reiniciarse (no reiniciados).
- **Quickshell**: quitados de `shell.json` (barra) `backmeupplz.navidrome` y `crmne.hyprmoncfg`; backup `shell.json.bak-optim-20261020`. Avisos `ServerNotFound`: **160 por 2 min → 0 en 30 s**; quickshell sigue vivo. Los plugins siguen instalados (se vuelven a añadir desde las preferencias de powerbar).
- **uke-fix.service**: reducido a `chmod 755 /usr/share/empty.sshd` (Before=sshd) + `tmpfiles.d/uke-sshd.conf`; elimina 24 s de `sleep` y el `try-restart sshd` en cada arranque. Original en `/var/lib/uke-optim/uke-fix.service.orig`. **Verificar en el próximo arranque en frío** (sshd debe seguir arrancando).
- **Caché pacman**: `paccache -rk1` no encontró nada que podar (una versión por paquete, 274 MB); no se borró nada.

## 6. Disco: fsck + resize HECHO (21-oct 03:1x–03:27, autorizado por el dueño)
- Backup previo: `~/backups/uke-rootfs-20261020.tar.zst` (6,28 GB sin comprimir, sha256 `dc58fc26…`, verificado).
- `/` no se podía remontar ro con el escritorio vivo (EBUSY: sddm, gvfs, tailscaled…): por USB (`192.168.42.129`) se enmascaró journald, se pararon sddm/touch/lapiz/bt/tailscaled/NM/user@ y `remount,ro,norecovery` funcionó. `e2fsck -fn` (inventario): diferencias de bitmap de bloques/inodos; `-fy`: contadores corregidos, 1 pasada; segunda `-fy` y `-fn` limpias, `state: clean`. Log: `build/logs/e2fsck-optim-20261021.log`. Las máscaras de journald se retiraron antes del reinicio (quedan solo las preexistentes de hibernate/sleep).
- Reinicio con `sync` + sysrq-s/b a las 03:25. Tras él, `resize2fs` **en caliente**: 2 097 152 → **27 748 347 bloques**; `df`: **105 G, 6,1 G usados, 94 G libres, 7 %**.
- Verificado 03:27: `--failed` vacío; uke-wifi/bt/audio/audio-amps/desktop/touch/lapiz, tailscaled, bluetooth, NM, sddm, rtkit activos; WiFi asociado, Tailscale ok; 0 errores `EXT4-fs error`/SMMU en dmesg; journal 142,6 M; THP madvise persistió; quickshell vivo. `bluetooth.service` ya no falla. Pendiente: confirmar con el dueño táctil/audio en uso real.
