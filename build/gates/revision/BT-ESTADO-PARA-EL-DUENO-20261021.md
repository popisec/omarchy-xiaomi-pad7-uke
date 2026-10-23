# Bluetooth de la uke: estado, qué está listo y qué falta (para el dueño, 21-oct-2026)

> Hecho **sin tocar la tablet** (el dueño se la llevó: «que trabajen sin tablet»). Todo lo de abajo se ha probado en el PC con mocks y con un `ssh` simulado;
> **nada de esto está desplegado** en la tablet. Lo que sí se midió en la tablet se cita con su fecha y su fuente. Informes de detalle: `BT-MUDO-20261019.md`,
> `BT-MUDO-FIX-20261021.md`, `BT-DIARIO-PLAN-20261018.md`.

## 0. ACTUALIZACIÓN 21-oct 21:07 — desplegado y probado en la tablet (con tu autorización: «check + deploy + suspensión + consumo»)

> Lo de las secciones 1–8 se escribió **antes** de volver la tablet («nada desplegado»): queda superado por esto. Registros: `build/logs/bt-ciclo-20261021-bt2/` (git-ignorado; las cifras están en `NOTAS-OMARCHY.md`).

| Prueba | Resultado | Evidencia |
|---|---|---|
| Despliegue `--service --sleep --hciqca` | **Hecho**; WiFi/adsp IGUAL que antes | hashes en la tablet: `uke-bt-up.sh` `3e493c5f`, `uke-bt-sleep` `90930b33`, `uke-bt-resume` `e9d026e0` |
| `hci_uart` parcheado | **Cargado en hardware con los defaults: 3 encendidos VERDE, 0 faults** | va en `updates/` (en Arch `extra/` no se busca; el 1.er despliegue abortó por eso: `BT-MUDO-FIX-20261021.md` §10) |
| **Suspensión de 25 s con los Nothing Headphone (a) (D2 con el gancho nuevo)** | **VERDE**: durmió 25 s (alarma RTC, `pm_wakeup_irq=183`), `suspend_fail=0`, adaptador encendido a 1 s de reanudar y **auriculares reconectados solos a los 5 s** (solo se guardó la MAC de audio; el lápiz sigue conectado por su servicio) | log del gancho 19:05:56Z → 19:06:26Z; `dmesg`: `PM: suspend entry/exit (s2idle)`, sin faults |
| Consumo despierto (D3, parte despierta) | BT **no significativo**: apagado (`bt_off`) −0,016 ± 0,035 W; descargado (`bt_down`) −0,034 ± 0,018 W | `bt-consumo.sh`, 3 repeticiones, sistema ≈ 2,46 W; dos primeras fases descartadas (la sesión de audio usaba la tablet) |
| Consumo en suspensión | **Sin medir** (exige USB desenchufado y orden tuya) | — |
| Chip mudo (medir/carga) | **No ejecutado** (sin orden) | — |

Lecciones: (1) `uke-idle-guard` impide `systemctl suspend` mientras haya CUALQUIER sesión SSH abierta (incluida una captura `dmesg -w`): para probar la suspensión usa la consola ACM y lee `dmesg` después. (2) Un lápiz BLE cuenta como «conectado» pero el gancho no lo guarda: la compuerta ahora exige un dispositivo de audio.

## 1. Resumen en diez líneas

1. **El Bluetooth funciona** en ouke4 y ouke5 (WCN6750 por HCI-UART, `hci0` encendido, A2DP/AAC con los auriculares): verificado en la tablet el 18–20-oct.
2. **Suspensión (D2): HECHA y confirmada por el dueño** (anotada el 19-oct: audio → botón de encendido → despertar → los auriculares reconectan solos y suenan; medido el 18-oct 21:25: 26 s dormida, reconexión a los 4 s).
3. **Chip «mudo»** (el primer comando `0xfc00` no recibe respuesta): es **probabilístico, no un bloqueo duro**; con `UKE_BT_CYCLES=3` (opción A, desplegada y verificada
   en un bucle de 12 encendidos: 12/12 VERDE, un ciclo mudo rescatado) se rescata. En ouke5 **0 mudos en 9 arranques** frente a 4 de 10 en ouke4 (p = 0,087: indicio, no prueba).
4. Causa del mudo: **sin determinar** (H1 carrera de 50 ms, H2 contención con el WiFi al arrancar, H3 reapertura del puerto). Hay un `hci_uart` parcheado y un
   protocolo de medida para decidir; **su urgencia bajó** (ouke5 casi no lo necesita).
5. **Consumo en suspensión (D3): sin medir todavía.** La herramienta está lista y probada en el PC (`bt-consumo.sh` + `analiza-consumo.py`); la medida exige la tablet.
6. Preparado hoy: gancho de suspensión más robusto, ayudante de reanudación con **recuperación del chip mudo**, reconexión **solo de los auriculares/audio**, y un
   **orquestador de un solo ciclo** (`ciclo-prueba.sh`) que ejecuta despliegue + medidas + prueba de suspensión con compuertas.
7. En la tablet **siguen** las versiones anteriores del gancho/ayudante/`uke-bt-up.sh` (ver §3): funcionan, pero no tienen las mejoras de hoy.
8. Para probarlo todo hace falta **un ciclo de ~1 h con la tablet, cargador y USB** (§5), con 3 decisiones tuyas (§6). Ningún paso exige reiniciar.
9. `build.sh` → `RESULTADO: OK` (21-oct, `out/test-*.txt`): 103 + 51 + 17 + 61 + 32 comprobaciones y los harnesses de hciqca/consumo.
10. Límite honesto: lo no comprobado en hardware está listado en §7.

## 2. Qué hace el BT en el día a día (y dónde está probado)

| Función | Estado | Evidencia |
|---|---|---|
| `uke-bt.service` arranca antes que `bluetooth.service` y que el escritorio (espera de hasta 25 s, hasta 70 s si el servicio sigue `activating`) | **Desplegado, VERDE** | `docs/historia/ESTADO-VIVO.md` 18–20-oct; `/var/log/uke-bt.log` |
| Panel Bluetooth de la barra de Omarchy con el dedo | **El dueño lo probó** (tras la espera v2) | `BT-DIARIO-PLAN-20261018.md` |
| Auriculares A2DP | **Funciona** (AAC) | idem |
| Reconexión tras suspender | **Funciona (versión desplegada)**; mejorada en el PC (§4) | D2, 18-oct 21:25 (medido) y 19-oct (confirmado por el dueño) |
| Sin despertar prematuro de s2idle | **Funciona (versión desplegada)**: desactiva el despertar por el UART (IRQ 229 / GPIO 43) | 18-oct 21:18 (sin auriculares) y 21:25 (con ellos): 25–26 s dormidos, `pm_wakeup_irq=184` = alarma RTC |
| BT no impide dormir | **Sí** (`power off` + despertar por UART desactivado) | idem |
| Consumo razonable | **Sin medir** | §5, etapa `consumo` |

## 3. Qué hay en la tablet y qué es nuevo en el PC

| Fichero | En la tablet (hash, 19–20-oct) | En el árbol hoy | Diferencia |
|---|---|---|---|
| `uke-bt-up.sh` | `d5caf4dd` | `3e493c5f` | `UKE_BT_HCI_OPTS` (opciones de `hci_uart`) |
| `uke-bt-wait` | `dec89b83` | `dec89b83` | igual |
| `uke-bt.service` | `a934f78f` | `a934f78f` | igual |
| `uke-bt-sleep` | `279361b3` | `90930b33` | solo guarda auriculares/audio; rutas rápidas; `bt-keep-on`; un único `bluetoothctl show` con `timeout` |
| `uke-bt-resume` | versión anterior | `e9d026e0` | **recuperación del chip mudo** tras `power on` fallido |
| `hci_uart.ko` | el de serie | `out-hciqca/hci_uart.ko` en `updates/` | **parcheado** (tiempos ajustables; defaults = serie) |
| `bt-medir.sh`, `bt-consumo.sh` | no están | listos | herramientas de medida |

(Hashes de la tablet: `docs/historia/ESTADO-VIVO.md`. El `.ko` de serie nunca se toca: el parcheado vive en `updates/` —en Arch `extra/` no se busca, ver `BT-MUDO-FIX-20261021.md` §10— y `deploy.sh --revert` lo quita.)

## 4. Reconexión automática de los auriculares tras suspender (preparada hoy)

Flujo (`uke-bt-sleep` + `uke-bt-resume`, probado con 51 comprobaciones de mocks):

1. **Antes de dormir (`pre`)**: desactiva el despertar por el UART del BT (si no, s2idle sale en ~117 ms); pregunta **una vez** a `bluetoothctl` (con `timeout`;
   si no responde, no toca nada); guarda solo las MAC con UUID **Audio Sink / Headset / Handsfree** (ratones/teclados se reconectan solos al moverlos y no
   deben fijar la lista); apaga el adaptador.
2. **Al despertar (`post`)**: restaura el despertar por UART y lanza el ayudante con `systemd-run --no-block --collect` (un `setsid` moría con el cgroup de
   `systemd-suspend.service`: lección del 19-oct).
3. **Ayudante**: espera `bluetooth.service` y `hci0`; `power on`; si **no responde** (chip mudo tras reencender), hace `uke-bt-up.sh --down` + encendido por
   **ciclos** (`UKE_BT_CYCLES=3`) y reintenta (línea de log `ROJO:` si ni así); luego reconecta **cada MAC guardada** (6 intentos × 3 s; vale que el auricular
   reconecte solo). Todo queda en `/var/log/uke-bt.log` (`uke-bt-sleep:` / `uke-bt-resume:`).
4. **Para que el BT se quede encendido al dormir** (p. ej. para probar): `touch /etc/uke/bt-keep-on` (el despertar por UART sigue desactivado).
5. **Para quitarlo todo**: `touch /etc/uke/no-bt`.

**No verificado en hardware** (solo mocks): la ruta de recuperación del chip mudo *tras reanudar* (nunca se ha visto un mudo al reanudar; sí al arrancar).

## 5. El ciclo de pruebas de una sola vez (cuando vuelva la tablet)

Todo lo ejecuta `build/rootfs/deploy/bt/ciclo-prueba.sh` **desde el PC**, por USB (192.168.42.129; **no Tailscale**: el WiFi y el BT comparten chip y la prueba
puede tumbar la sesión). Sin `--go` solo imprime el plan (cero `ssh`); `--check` hace las compuertas de solo lectura.

**Compuertas** (si falla una, para antes de tocar nada): host USB; **un lector** en `/dev/ttyACM0`; release de la tablet == vermagic de los `.ko` de `out/`;
batería ≥ 30 % o cargando; adaptador BT encendido. Cada etapa que falla **para** el ciclo (probado: `set -e` no actúa dentro de `|| die` y se corrigió).

| Etapa | Qué hace | Tiempo | Qué decide |
|---|---|---|---|
| `deploy` | `deploy.sh --go --service --sleep --hciqca` (nada se carga; instala hooks, `uke-bt-up.sh`, `hci_uart.ko` parcheado en `updates/`, `bt-medir.sh`, `bt-consumo.sh`) | ~1 min | — |
| `medir` | `bt-medir.sh -n 20` (4 configuraciones intercaladas) + Wilson/Fisher | ~10 min | **H1**: ¿el mudo es una carrera de 50 ms? |
| `carga` | control `50:50:0` con tráfico WiFi (`-w`) y con carga de CPU (`-l`), 30 ciclos cada uno | ~8 min | **H2**: ¿hay contención al arrancar? |
| `suspension` | `rtcwake -m no -s 25` + `systemctl suspend` con auriculares **conectados**; veredicto VERDE/ROJO (durmió ≥ 20 s, el ayudante registró «reconexión … OK», quedan dispositivos conectados) | ~2 min | reconexión automática |
| `consumo` | lanza `bt-consumo.sh --sin-suspension` (despierto, ~13 min) y explica la parte en suspensión (USB desenchufado, ~1 h con los valores por defecto; `-R 1 -s 180` la reduce) | 13 min + ~1 h | D3 |

Orden recomendado (cada comando lo autorizas tú):

```bash
cd ~/proyectos/omarchy-uke/build/rootfs/deploy/bt
./ciclo-prueba.sh --check                                     # compuertas (solo lectura)
./ciclo-prueba.sh --go --etapas "deploy medir carga"          # ~20 min
./ciclo-prueba.sh --go --etapas suspension --con-auriculares  # ~2 min (auriculares encendidos y conectados)
./ciclo-prueba.sh --go --etapas consumo                       # lanza la medida despierta; luego la de suspensión a mano
```

**Abortar si**: hay faults del kernel en `dmesg -w`, `modprobe hci_uart` rechaza las opciones (el módulo no es el parcheado), la batería baja de 30 % sin cargar.
**Vuelta atrás**: `deploy.sh --go --revert` (quita todo el BT) o solo el parche: ver `BT-MUDO-FIX-20261021.md` §5.7. Las herramientas de medida restauran el BT al terminar.

## 6. Decisiones que necesito de ti

1. **¿Desplegar** `--service --sleep --hciqca` (mejoras del gancho + parche instalado sin cargar)? Es lo que activa el resto. No reinicia ni carga nada. Si prefieres
   no tocar el hardware sano, **puedes dejarlo todo como está**: lo desplegado funciona (D2 hecho).
2. **¿Medir el mudo (H1/H2)?** Con 0 mudos en 9 arranques de ouke5 tiene menos urgencia; la medida apaga/enciende el chip ~140 veces (~18 min con el BT en ciclos de apagado/encendido; el WiFi comparte chip y puede resentirse).
   Recomendación: hacerla **una vez** para cerrar la causa; si sale «MEJORA» (p < 0,05 y 1.er intento ≥ 90 % en ≥ 20 ciclos) se fija con `--hciqca-conf`, si no, se descarta el parche.
3. **¿Medir el consumo (D3)?** La parte en suspensión exige **desenchufar el USB** ~1 h (o ~25 min con `-R 1 -s 180`, menos resolución) con la tablet fuera de servicio.

## 7. Límites, hipótesis y lo que no se ha podido comprobar

- **Hipótesis (no verificadas)**: H1 carrera de 50 ms tras subir BT_EN; H2 contención con el WiFi; H3 reapertura del puerto sin control de flujo. La estadística actual
  (1.er intento OK 47 % en arranque vs 73 % dentro del arranque, p = 0,11; ouke5 0/9 vs ouke4 4/10, p = 0,087) **no es significativa**.
- **Solo en mocks**: recuperación del mudo al reanudar; `bt-keep-on`; `--hciqca-conf` (se instala `/etc/modprobe.d/uke-bt-hci.conf`); el orquestador contra la tablet real
  (probado con ssh simulado: compuertas, orden, parada ante fallo, veredicto); `bt-consumo.sh` (batería falsa con potencia conocida).
- `hci_uart.ko` parcheado: construido con `LLVM=1` contra el árbol ouke5 (`7.2.9-senemos.1.4054.3-ouke5`, que es también el release del kernel v6 #6); control sin parche
  idéntico al de serie (alias, dependencias, 189 símbolos indefinidos; el parcheado solo añade `param_ops_uint`); **sin warnings nuevos con W=1**. **Nunca se ha cargado en la tablet.**
- La parte de suspensión del consumo mide ΔQ del `charge_counter` con alarma RTC y **solo vale con USB desenchufado**; el análisis descarta las filas con USB > 0,3 W.
- Para cualquier medida: usar **USB** (no Tailscale), un solo lector ACM, avisar a las demás sesiones (audio, cámaras, lápiz, WiFi) antes: comparten el chip o la tablet.

## 8. Ficheros (todo en `build/rootfs/deploy/bt/`)

`ciclo-prueba.sh` (orquestador), `harness/test-ciclo.sh` (32), `hciqca/` (`hci_qca-uke-tiempos.patch`, `build-hciqca.sh`, `bt-medir.sh`, `analiza-medicion.py`),
`consumo/` (`bt-consumo.sh`, `analiza-consumo.py`), `harness/test-consumo.sh`, `harness/test-bt-sleep.sh` (51), `harness/test-deploy-sim.sh` (61), `deploy.sh`
(`--sleep`, `--hciqca`, `--hciqca-conf`; ahora instala también `bt-consumo.sh`), `root/usr/lib/systemd/system-sleep/uke-bt-sleep`, `root/usr/local/sbin/uke-bt-resume`.
