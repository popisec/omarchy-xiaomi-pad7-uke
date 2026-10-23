# CRÍTICA adversarial del plan futuro — 14-oct-2026 (~23:4x, solo lectura)

Base: ESTADO-VIVO (L58 vivo, L62 negro-con-luz, L60 wedge), ledger #637–#640, PPS-COMPARA,
L60-FALLO, CARGA-KERNEL+addendum, WD19-CARGA, USB-HOST-DOCK, DESKTOP-REVISION, WIFI/BT-ESTADO.

## 1. Display: el orden L63→s6→PHY es defendible pero le falta una rama barata
- Riesgo: PPS-COMPARA ya demostró **bytes iguales, orden distinto**; L63 prueba el orden
  post-0x29. Si falla, la rama PPS queda cerrada por diseño — bien. Pero entre L63 y s6 falta
  el test de **¿el DDIC responde algo?**: lectura DCS (0x0A get-PPS / 0x04 ID) vía
  `mipi_dsi_dcs_read` en el `enable` (solo lectura, 0 flashes extra si va en el mismo L63).
  Sin eso, un L63-negativo no distingue "PPS ignorada" de "DDIC sordo / link caído".
- Hueco: el re-ranking (i)→(iv) salta la auditoría **encoder-host coherencia** (`dsi_update_dsc_
  timing`: WC=800, eol, 2 pkt/línea) que cuesta **0 flashes** y debería ir ANTES de s6.
- Recomendación: L63 con readback DCS incluido; si negro+err=0+readback OK → s6; si readback
  falla → parar DSC y mirar link/PHY, no s6. **Prioridad: ALTA (es el hito).**

## 2. Carga: el plan `=y` ya mordió; no repetirlo
- Riesgo: L60 (`battmgr=y`) **no arranca** (rollback a L58, a=2 retries gastados). L60-FALLO
  aísla a battmgr con precedente hermano #404/R-32. El addendum de CARGA-KERNEL proponía
  reintentar `=y` en el próximo kernel — **eso es re-pisar el rastrillo**.
- Hueco: la vía buena (módulos .ko + insmod topológico + fw ADSP, receta 28-sep NOTAS:1023)
  **existe en `charge/`** (10 .ko, servicio, loader) pero el plan no la pone como camino
  principal ni le asigna el próximo ciclo vivo.
- Recomendación: **congelar `=y` de battmgr**; próximo ciclo vivo = `charge/uke-charge-run.sh`
  sobre L58 (0 flashes) + `ls /sys/class/power_supply/`. Cargar apagada a pared ≥45 W
  mientras tanto (WD19 descartado: 5 V sin PD). **Prioridad: ALTA (bloquea todo lo demás).**

## 3. Escritorio/táctil: el plan lo infravalora
- Riesgo: DESKTOP-REVISION dice "bloqueo = RAM", pero L58 ya dio 7,2 GiB + zram y la pantalla
  sigue negra **con contenido real en el FB** (auditoría userspace eximida). El escritorio
  está "a ciegas" y PENDIENTES-20261014 pone el táctil como "Baja" — **error**: sin
  NT36532 no hay uso real aunque haya contenido mañana. Hay teclado USB vía dock como
  puente (USB-HOST-DOCK §4), pero nadie lo ha probado en vivo.
- Hueco: F-plan F4 (NT36532→input→libinput→libwacom→hyprland tablet-v2) existe; el informe
  **I-lápiz sigue sin escribirse** y ningún ciclo vivo ha hecho `ls /dev/input / dmesg|grep nt36`.
- Recomendación: subir táctil a **ALTA ya, en paralelo sin flash**: 3 comandos vivos en el
  próximo SSH (input, libinput, dmesg-nt36) + prueba teclado USB por dock. Escribir I con eso.
  **Prioridad: ALTA (es la definición de "usable").**

## 4. Slots/batería: el plan procesal no existe y el riesgo es el nº1
- Riesgo: `slot-retry-count:a=3` y cayendo (cada arranque resta 1; hoy ~10 escrituras contra
  regla ≤2/día). Si `a` llega a 0, el ABL cae a **b (¿qué hay? par viejo, no verificado hoy)**
  y la tablet puede quedar sin boot remoto. `qbootctl -m` (binario listo 27-sep, solo-lectura
  verificada) sigue sin decisión del dueño.
- Hueco: PENDIENTES lo lista como "no bloquea el hito" — **falso encuadre**: es lo único que
  puede matar el proyecto esta noche.
- Recomendación: **moratoria de flashes hasta carga ≥3700 mV + `getvar all` antes/después**;
  decidir `qbootctl -m` (o marcado de éxito) ANTES del próximo flash; máximo 2 escrituras/24 h
  a partir de ahora. **Prioridad: CRÍTICA.**

## 5. Lo que el plan no dice (deuda que muerde pronto)
- H (backup) e I (lápiz) sin escribir; rollback L58/L59 a mano pero **sin `backup-par-bueno.sh`
  verificado esta semana**; fs del PC al 82 % (no 98 %, medido hoy) pero rootfs 4,6 GB sin
  limpieza (locales/staging viejos); consola ACM/netconsole como doble captura **exigida en
  L60-FALLO §2 pero sin dueño asignado**; batería solo medible en fastboot (ciegos en Arch).
- Recomendación: H+I en la próxima sesión sin tablet; `e2fsck`/limpieza antes del próximo
  build grande; ACM armado por defecto. **Prioridad: MEDIA (proceso).**

## Plan revisado 24 h (orden valor/coste, batería baja + retries escasos + sin red tablet)
1. **Pared ≥45 W + `getvar all`** (batería, 4 contadores, slot b contenido). 0 flashes.
2. **Decisión `qbootctl -m`** del dueño (frena la hemorragia). 0 flashes.
3. **L63 a flash** (con readback DCS si cabe en el mismo hunk) + criterio PASA=contenido.
4. **Si L63 falla**: auditoría encoder-host en código (0 flashes) → **s6-noncontinuous**.
5. **Carga sin flash**: `uke-charge-run.sh` + power_supply sobre L58/L63 vivo.
6. **Táctil sin flash**: `/dev/input + libinput + dmesg nt36` + teclado USB por dock.
7. **PHY vendor solo con artefactos** (volcado timings primero, nunca a ciegas).
8. **H+I escritos** + ledger al día + moratoria ≤2 escrituras/día.
