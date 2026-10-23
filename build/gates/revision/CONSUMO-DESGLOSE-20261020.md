# Desglose de consumo de uke — 20-oct-2026 13:04–13:46 (hora tablet)

Kernel `7.2.9-senemos.1.4054.3-ouke5`, Omarchy (Hyprland + Quickshell), perfil Ahorro, panel 3200x2136@60 Hz, brillo 102/2047 (5 %), WiFi asociada (RED-EJEMPLO-1, 5,5 GHz, `power_save off`), BT con el lápiz conectado, Tailscale activo, batería 1,15 % → 3,9 % **cargando** con cargador de pared (USB `voltage_now` 5,05 V, `current_now` 0,93 A, `input_current_limit` 1 A).
Datos crudos, scripts y trazas: `build/logs/consumo-20261020/` (`b1..b4.jsonl`, `samp.py`, `b1..b4.sh`, `trace-{on,off}.txt.gz`).

## Método
- **Sistema = descarga neta de batería (−V·I de `qcom-battmgr-bat`) + entrada USB (V·I de `qcom-battmgr-usb`)**, a 1 Hz, 45 s por fase tras 8 s de asentamiento. Cada fase registra también CPU ocupada, IRQ/s y residencia en cpuidle (cpu0/3/7).
- Bloques A/B con línea base repetida (al inicio, entre fases y al final). Todo lanzado **desprendido en la tablet** (`systemd-run` + `systemd-inhibit`) para que el SSH no meta carga, con `trap` que restaura el estado.
- La entrada USB se mantuvo constante (4,690–4,697 W) en **todas** las fases, incluso con +4,5 W de brillo: el cargador está limitado por corriente de entrada y toda variación de carga la absorbe la batería. Por eso **los deltas A/B son fiables** aunque el absoluto no lo sea tanto (ver «Incertidumbre»).
- Ruido: la línea base deriva. Pantalla apagada: 11 bases, media **1,386 W, σ = 0,052**; pantalla encendida (5 %, 60 Hz): 7 bases, media **2,433 W, σ = 0,066**. Un delta < ~0,1 W **no es significativo** (una fase sin cambio real —`pelt1`, cuyo `echo` falló— dio 1,284 W, −0,10 W por puro azar).

## Tabla por contribuyente (medido 20-oct-2026)

| Contribuyente | Δ W (± 1σ) | Evidencia (fase vs bases vecinas) |
|---|---|---|
| **Pantalla encendida en reposo (5 %, 60 Hz) vs DPMS off** | **+1,05 ± 0,08** | 2,43 vs 1,39 (b1, b3, b4) |
| ├ panel+DSI+MDSS+compositor+sondeo táctil (DPMS on, brillo 0) | +0,81 ± 0,07 | `ON_bl0` 2,193 vs off 1,386 |
| └ retroiluminación al 5 % (102/2047) | +0,24 ± 0,07 | `ON_bl0` 2,193 vs bases 2,393/2,467 |
| Retroiluminación al 50 % (1024) | +2,04 ± 0,10 | `ON_bl50` 4,476 |
| Retroiluminación al 100 % (2047) | +4,46 ± 0,12 | `ON_bl100` 6,902 (batería descargando 2,2 W durante 45 s) |
| → pendiente de la retroiluminación | **≈2,2–2,4 mW por paso** (≈0,47 W por cada 10 %) | lineal en 0→102→1024→2047 |
| Refresco 120 Hz vs 60 | **+0,45 ± 0,08** | `ON_hz120` 2,923 |
| Refresco 90 Hz vs 60 | +0,28 ± 0,08 | `ON_hz90` 2,735 |
| Refresco 48 Hz vs 60 | −0,06 ± 0,08 (n.s.) | `ON_hz48` 2,369 |
| **WiFi asociada en reposo (rfkill block)** | **+0,36 ± 0,07** | `OFF_wifi_rfkill` 1,038 vs 1,446/1,354 |
| WiFi `power_save on` (runtime, 45 s) | −0,01 ± 0,12 (n.s.) | `OFF_wifiPS_on` 1,373 |
| Sondeo táctil 120 Hz (proxy sintético: 120 despertares/s × 0,9 ms) | +0,10 ± 0,13 (n.s.; **solo CPU**) | `OFF_proxy_tactil_120Hz` 1,537 vs 1,438/1,446 |
| Perfil Rendimiento (solo CPU/GPU, refresco fijo) — pantalla encendida | −0,07 ± 0,08 (n.s.) | `ON_cpu_rendimiento` 2,409 |
| Perfil Equilibrado (solo CPU/GPU) — pantalla encendida | −0,11 ± 0,08 (n.s.) | `ON_cpu_equilibrado` 2,367 |
| Perfil Rendimiento / Equilibrado — pantalla apagada | +0,09 / −0,03 (n.s.) | 1,472 / 1,357 |
| tailscaled (congelado con `systemctl freeze`) | −0,04 ± 0,07 (n.s.) | 1,350 vs 1,376/1,400 |
| `uke-bateria-log` parado | −0,11 ± 0,06 (n.s.; ≤1 tick por fase, mismo tamaño que el azar) | 1,278 |
| `rcu_expedited` 1 → 0 | +0,04 ± 0,09 (n.s.) | 1,448 |
| GPU | ≈0 en reposo | `pm_genpd`: `gpu_cc_gx_gdsc`/`gpu_cc_cx_gdsc` **off-0**; devfreq en 255 MHz (mín.) |
| UFS | ≈0 (sin palanca) | devfreq 100 MHz (mín.), `clkgate_enable=1` (150 ms), `auto_hibern8=150000`; 8–12 IRQ/s |
| Bluetooth (lápiz conectado) | **no medido** | `rfkill bluetooth` = tocar BT/lápiz (prohibido; riesgo de chip mudo al re-encender, 29 % de arranques en v4) |
| Suspensión s2idle | **no medida** | ver «No hecho» |

**Desglose resultante, pantalla encendida a 5 %/60 Hz ≈ 2,43 W**: suelo despierto con pantalla apagada 1,39 (de los cuales WiFi 0,36) + panel/pipeline/táctil 0,81 + retroiluminación 0,24.
Perfiles: a igual refresco **no cambian nada medible en reposo**; la diferencia entre Ahorro/Equilibrado/Rendimiento es casi toda el refresco (60/90/120 Hz → 0 / +0,28 / +0,45 W).

### Contadores de actividad (mismas fases)
| Estado | CPU ocupada | IRQ/s total | arch_timer/s | IPI «Function call»/s | uke-touch/s | residencia en estado de clúster (cpu0 / cpu3 / cpu7) |
|---|---|---|---|---|---|---|
| Pantalla encendida | 5–6 % | 1 280–1 460 | 660–740 | 250–345 | 120 | 0,21–0,60 / 0,65–0,79 / 0,74–0,89 |
| DPMS off | 3,4–4,8 % | 810–1 070 | 485–600 | 187–312 | **0** | 0,70–0,83 / 0,70–0,80 / 0,79–0,90 |

- Con DPMS off **el táctil deja de sondear** (IRQ `uke-touch` y `gpi-dma` a 0). Con pantalla encendida `uke-touchd.py` gasta **11 % de un núcleo** (658 ticks en 60 s, 13:08–13:09).
- Traza ftrace de 10 s con DPMS off (`trace-off.txt.gz`, instancia propia, retirada al terminar): IPI por `ttwu_queue_wakelist` 182/s (despertares remotos normales), `generic_exec_single` 34/s; `tick_nohz_handler` 455/s (el tick no se para mucho); **`ath11k_dp_service_mon_ring` 62/s** (temporizador del anillo monitor del WiFi, sigue con la pantalla apagada); `process_srcu` 61/s; despertares por proceso: tailscaled ≈78/s (dos hilos), `rcu_preempt` 45/s, `vigia-adsp.sh` 11,5/s (vigía de otra sesión, bucle de 2 s), dbus-broker 13/s, quickshell 8/s.
- cpuidle: driver `psci_idle`, gobernador `menu`; estados por CPU: WFI, `*-c3`, `*-cluster*`; los tres clústeres pasan 70–90 % del tiempo en el estado de clúster con pantalla apagada. **No se puede ver si el SoC entra en CXSD/AOSD**: `CONFIG_QCOM_STATS=m` sin cargar (y `modprobe` está prohibido).
- cmdline: `clk_ignore_unused pd_ignore_unused regulator_ignore_unused` (210 de 438 relojes habilitados) — **hipótesis** de fuga en el suelo, sin medir.

## El «suelo» de 2–3 W con pantalla apagada frente a ~1,4 W de Android

1. **Hoy el suelo medido es 1,39 ± 0,05 W** (pantalla apagada por DPMS, escritorio vivo, WiFi + BT + Tailscale + ADSP), es decir, **igual que el ~1,4 W de Android**. Con la pantalla encendida a 5 %/60 Hz: 2,43 ± 0,07 W.
2. **Los 2–3 W (y los 3,6–4,6 W) previos venían inflados por la entrada USB**. Las medidas del 19-oct (`medidas-perfiles.csv`) sumaban `usb_w` = 1,87 W (lectura de 0,36 A a 5,19 V), pero entonces el `input_current_limit` era **100 mA** (arreglado el 20-oct con `uke-icl`): la entrada real era ≤ 0,5 W. Con la descarga neta de ese día (Ahorro 2,42 W) + ≤ 0,5 W sale ≤ 2,9 W, compatible con los 2,43 W de hoy (y entonces `uke-touchd` gastaba ~36 % de un núcleo, hoy 11 %). Conclusión: **la lectura `qcom-battmgr-usb/current_now` no es fiable cuando el ICL es bajo**; hoy (ICL 1 A, cargador limitado por entrada) sí es coherente.
3. Composición del suelo de 1,39 W: WiFi asociada sin ahorro **0,36 W (medido)**; userspace (tailscaled, log, RCU, perfiles) < 0,1 W cada uno (no significativo); el resto (~1,0 W) es SoC/DDR/PMIC/raíles siempre encendidos + BT con el lápiz + ADSP + **pérdidas del cargador, que este método cuenta como consumo** (hipótesis: 0,2–0,5 W con 4,7 W de entrada). No se ha podido descomponer más sin cargar `qcom_stats`, sin tocar BT y sin desconectar el cargador.
4. ⚠️ El 1,4 W de Android **no tiene fuente en el repo** (no está en `build/android/bateria-20261019/`): es una referencia sin fecha ni método; tómese como orden de magnitud.

## Incertidumbre del valor absoluto (importante)
- Deltas A/B: ±0,07–0,13 W (1σ), robustos porque la entrada USB es constante.
- Absoluto: depende de que `qcom-battmgr-usb/current_now` sea la corriente real (ver punto 2) y de `qcom-battmgr-bat/current_now`. **Discrepancia sin resolver**: en 13:12–13:43 el `charge_counter` subió a +334 mA de media mientras `current_now` daba +693 mA (y `(V−OCV)/R_int` = (3,720−3,697)/0,060 ≈ 0,38 A a las 13:45). Si el contador de carga tuviera razón, el sistema real sería ~1,3 W mayor que lo de esta tabla. A favor de `current_now`: sigue a los cambios de carga en tiempo real, y a SOC alto (19-oct 22:50–23:30) ambos coincidieron ±25 %; el `charge_counter` avanza a saltos (estuvo 3 min fijo en 343 000 µAh con 0,6 A de carga) y a SOC 1–4 % el gauge compensa la capacidad remanente (**hipótesis**). **Validación pendiente**: descarga sin cargador ≥ 30 min a SOC medio comparando `current_now` con `charge_counter`, o un medidor USB-C en línea.

## Los 5 cambios con mayor ahorro esperado
1. **Apagar la pantalla antes (hypridle)**: cada minuto de reposo con pantalla encendida cuesta **+1,05 W** frente a DPMS off (y DPMS además para el sondeo táctil). Hoy: atenuar a 300 s, DPMS a 600 s. Propuesta: DPMS a 120–180 s. Ahorro medido: 1,05 W mientras dure el reposo.
2. **Brillo**: ≈ 0,47 W por cada 10 % (2,3 mW/paso, medido 0→100 %). Al 50 % la retroiluminación sola gasta 2,0 W, el mayor consumidor del sistema. Tope de brillo en Ahorro (hoy 35 %) y valores bajos por defecto.
3. **Refresco 60 Hz también en Equilibrado** (hoy 90 Hz): −0,28 W; Rendimiento a 120 Hz cuesta +0,45 W. Los topes de CPU/GPU de los perfiles no ahorran nada medible en reposo; 48 Hz no mejora a 60.
4. **WiFi: 0,36 W asociada en reposo**. `iw … power_save on` no dio ahorro medible en 45 s (posible que el firmware no lo aplique: **hipótesis**, a comprobar con más tiempo y con `wifi.powersave=3` de NM); el temporizador `ath11k_dp_service_mon_ring` despierta 62 veces/s. Opción segura: desconectar/rfkill la WiFi con pantalla apagada sin SSH, o en modo carga. Ahorro: hasta 0,36 W.
5. **Suspender (s2idle) antes** (hoy 1 800 s): el suelo despierto es 1,39 W; el de suspensión no está medido (**hipótesis**: < 0,3 W) → ~1 W mientras dure el reposo largo. Requiere medirlo con el gancho `uke-bt-sleep` (sesión BT) y sin cargador.
(6.º: sondeo táctil adaptativo o por IRQ — proxy de solo CPU +0,10 ± 0,13 W; con SPI/GPI-DMA est. 0,1–0,3 W, **hipótesis**; sesión Táctil.)

## No hecho y por qué
- **Bluetooth (rfkill)**: prohibido tocar BT/lápiz; además el re-encendido del chip falla a veces (chip mudo). No medido.
- **Suspensión**: `systemctl suspend` ejecuta `uke-bt-sleep` (apaga el adaptador y desconecta el lápiz = tocar BT), y con `rtcwake -m freeze` directo el IRQ del RX de la UART BT despierta a los 0,7 s (ESTADO-VIVO 18-oct). Además, cargando no se separa el drenaje en suspensión de la entrada USB.
- **pelt**: `/proc/sys/kernel/sched_pelt_multiplier` no existe en este kernel (el parámetro de cmdline no tiene efecto visible); la fase quedó como línea base extra.
- **cpufreq/cpuidle forzados**: no se deshabilitaron estados (solo se midió la residencia).

## Efectos colaterales (para otras sesiones)
- **13:40:13–13:41:12**: WiFi en `rfkill block` 53 s (volvió con IP en 6 s; temporizador de rescate cancelado). El vigía de audio (`/root/vigia-adsp.sh`) anotó `ALARMA[ wlan0=down ]` en ese intervalo: **es de este experimento, no un fallo**.
- Estado restaurado y verificado 13:45: Ahorro (schedutil 1,11/1,40/1,21 GHz, GPU máx 500 MHz), 60 Hz, brillo 102, DPMS on, `power_save off`, `rcu_expedited=1`, tailscaled `running`, `uke-bateria-log` activo, rfkill sin bloqueos, sin unidades `uke-consumo*` ni instancias de ftrace. Batería 3,89 % cargando.
