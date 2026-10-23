# Propuesta de kernel para autorizar — 21-oct-2026 (solo PC; nada compilado, nada flasheado)

Base: `docs/historia/revision/OPTIM-KERNEL-20261020.md` (sesión batería, medido en la tablet), capturas de Android en `build/android/rendimiento-20261019/` y mis mediciones de `docs/historia/revision/OPTIMIZACION-20261020.md`. **Corrección a mi informe anterior**: dije que «faltan estados cpuidle de gold/prime». Es falso: el DT ya trae `gold-c3`, `gold-cluster1-c`, `gold-plus-c3`, `gold-plus-clust` y `cluster-pd` (l3-off, cx-ret, llcc-off), idénticos a Android (RESUMEN §Estados de reposo); el problema es que el dominio de cluster casi nunca se usa porque el táctil despierta cada 8 ms. Tampoco recomiendo HZ=100 (ahorro <0,03 W). Los W de abajo son **estimaciones**, no medidas.

## Diferencias con Android (lo único que cambia de verdad)
| Área | Android | Linux ouke5 | Lectura |
|---|---|---|---|
| cpuidle | mismos 3 estados/cluster | igual | sin diferencia estructural |
| governor CPU | `walt`, mínimos 595/634/634 MHz | schedutil (perfil), mínimos 441/480/480 | ya más bajo que Android |
| GPU | msm-adreno-tz 255–950 | simple_ondemand 255–… | sin ganancia |
| votos de ancho de banda | bwmon/L3 DVFS | **sin** devfreq DDR/LLCC/L3; ICC sin `sync_state` | **única diferencia real a estudiar** |
| relojes/raíles | el kernel apaga los no reclamados | `clk/pd/regulator_ignore_unused` | 103 relojes y varios raíles encendidos en reposo |

## Lista priorizada
| # | Cambio | Ganancia est. | Riesgo | Reversión | Cuándo |
|---|---|---|---|---|---|
| 0 | **RUNTIME**: `echo 0 > /sys/kernel/rcu_expedited` y medir IPI1/s | 0,02–0,1 W | nulo | `echo 1` | ya, con orden del dueño (la tablet está con audio M1) |
| 0b | **RUNTIME**: `modprobe qcom_stats` y leer residencias AOSD/CXSD en una suspensión | información | bajo | `rmmod` | idem |
| A | **Flash A** (`kernel/ouke6-optim.config` + cmdline grupo A): `ZRAM` (módulo) + `ZSMALLOC` + `PSI`, governor cpuidle `teo`, `cpufreq.default_governor=schedutil`, `audit=0`, limpiar parámetros muertos | TEO ≤0,05 W; zram = robustez (RAM 7,4 GiB sin swap); `audit=0` quita ruido | bajo | par bueno anterior (`SHA-BUENOS.txt`) | mismo ciclo que el próximo kernel de cámaras |
| B | **Flash B** (cmdline grupo B): `fw_devlink.sync_state=timeout deferred_probe_timeout=30` | 0,1–0,4 W (hipótesis: libera votos DDR/NOC del bootloader) | **medio** (pantalla/GPU) | par bueno | tras A, ciclo propio |
| C | **Flashes C1–C3**: quitar `regulator_ignore_unused`, luego `clk_…`, luego `pd_…` | 0,05–0,2 W | **alto** (un cuelgue exige reset físico, R-42) | par bueno | solo con orden expresa, de uno en uno |
| D | **Investigación**: nodos DT de `qcom-cpu-bwmon`/`llcc-bwmon`/OSM-L3 (módulos ya compilados: `QCOM_ICC_BWMON=m`, `INTERCONNECT_QCOM_OSM_L3=m`) tomados del DT de Android | mayor ganancia potencial (DDR/LLC a la baja en reposo) | medio-alto | par bueno | sesión propia, tras A–B |
| — | Fuera de propuesta: `HZ=100`, `PREEMPT_VOLUNTARY`, `mem_sleep=deep` (sin watchdog; R-42) | <0,03 W / desconocido | — | — | no |

## Qué NO es kernel y rinde más
Táctil: sondeo adaptativo/IRQ real (0,2–0,5 W, ya ≈21 IRQ/s) y hypridle más corto (decisión del dueño). Mientras el táctil despierte a 120 Hz, los estados de dominio de `cluster-pd` no se usarán, así que A–D rendirán menos.

## Condiciones de ejecución (gates de docs/historia/AGENTS.md)
Batería ≥3700 mV en fastboot y cargador de pared, `fastboot getvar all` antes/después, ≤2 escrituras/día, sha pre-registrado en el ledger, consola ACM con lector único, vigía apuntando al par bueno, build desprendido (`setsid nohup … env MAKE=/usr/bin/make ARCH=arm64`). Árbol: `build/kernel-pokes/senemos-ouke6`, **compartido con cámaras**: no se compila hasta coordinarlo con ellas.

Material: `build/rootfs/deploy/optimizacion/kernel/ouke6-optim.config` (fragmento para `merge_config.sh`) y `kernel/cmdline-propuesta.txt`.

## Validación de compilación (21-oct, sin tablet, copia aparte del árbol)
- Copia: `build/kernel-pokes/optim-ouke6/` (fuente de `senemos-ouke6`, build propio con `O=`; no toca los árboles compartidos). Script `build-optim.sh` (`ARCH=arm64 LLVM=1 LLVM_IAS=1 MAKE=/usr/bin/make`, desprendido). `.config` = base ouke6 + `kernel/ouke6-optim.config` (verificado: `ZRAM=m`, `ZSMALLOC=m`, `PSI=y`, `CPU_IDLE_GOV_TEO=y`, `CRYPTO_ZSTD=y`).
- **Resultado: compila (`rc=0`, `Image.gz` + módulos).** `Image.gz` 16 141 020 B (+147 KB frente a los 15 993 943 B del ouke6 base), release `7.2.9-senemos.1.4054.3-oopt1`, `zram.ko` y `zsmalloc.ko` generados. sha256 `Image.gz`: ver `build/kernel-pokes/optim-ouke6/build/arch/arm64/boot/Image.gz`.
- **Ojo (decisión del dueño):** el `LOCALVERSION` del build de validación es `-oopt1`. Para flashear sin recompilar audio/BT/WiFi/cámaras hay que construir con el `LOCALVERSION` de los módulos instalados (`-ouke5`). Borrador de ledger sin pre-registrar: `kernel/LEDGER-BORRADOR-OPT1.md`.
- Los cambios de `cpuidle.governor=teo`, `audit=0`, `fw_devlink…` son cmdline (se hornean en el `boot.img`, no en el `Image`): no se prueban con este build.
