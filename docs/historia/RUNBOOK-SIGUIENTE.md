# RUNBOOK SIGUIENTE SESIÓN — 1-oct-2026 (reescrito tras la corrección del decode S2CR)

> **Lo que hay que saber antes de tocar nada (1-oct, tarde):**
> 1. El plan vigente sigue siendo `docs/historia/PLAN-SIGUIENTE-v4.md`, con su **banner de corrección** (el
>    volcado del CM3 leía `S2CR` al revés, y el SMMU es un MMU-500 con las CB en 0x20000, no en
>    0x8000). **El árbol de veredicto de 6 ramas sigue siendo válido** —lo que se corrige es qué
>    qué se espera leer en el volcado.
> 2. La tablet quedó **ZOMBI** (ping por USB, sshd muerto) esperando un power-cycle físico. Con el
>    K23 flasheado. **La primera pregunta ya tiene respuesta parcial y es incómoda**: el K23 lleva
>    un dump que **no puede** decir si la tabla de CB1 mapea el icache@0x4000, porque leía
>    direcciones equivocadas. Ese es el motivo del K23b.
> 3. Las reglas están todas en **[`REGLAS.md`](REGLAS.md)** (este runbook antes citaba "las 15
>    reglas de ESTADO-VIVO", que no estaban escritas en ningún sitio).

## Prioridad (orden del dueño): PANTALLA + GPU del todo. El resto (WiFi/F9/Omarchy) después.

## Paso 0 — Antes del power-cycle (todo en el PC, 0 escrituras)

```bash
# 0.1 Fila #P50 en PRE-REGISTRO-PANTALLA.md con la PREDICIÓN comprometida
#     (si no existe ya: escríbela antes de medir; es la regla M8)
# 0.2 Consola: nodo real y lector SIN timeout (el 'timeout 2 cat' pierde la ventana 3,95-4,18 s)
ls /dev/ttyACM*
#     matar el lector viejo y relanzar el patrón de #P40: 'cat' sin timeout con guard [ -e ]
# 0.3 Vigía: confirmar la pausa; y poll de fastboot + poll de SSH EN PARALELO durante el arranque
while :; do fastboot devices; sleep 5; done &
until build/gates/uke-ssh.sh 'echo ok'; do sleep 3; done
```

## Paso 1 — Power-cycle (dueño: power ~12 s + toque) → arranca K23 (slot a)

## Paso 2 — Capturar PRIMERO,(fsck después (el zombi llega a ~280-400 s)

```bash
# CMD1: el anillo dmesg entero, volcado al PC. Es la evidencia que decide; la consola es el respaldo.
build/gates/uke-ssh.sh 'dmesg -n 7; dmesg > /dev/shm/dm.txt; cat /dev/shm/dm.txt' \
  | tee build/logs/despertar-s3s4-full.log
# CMD2: estado drm/kgsl (siempre DESPUÉS de asegurar CMD1)
build/gates/uke-ssh.sh 'cat /sys/bus/platform/devices/3d00000.qcom,kgsl-3d0/power/runtime_status; \
  ls /sys/class/drm/; cat /sys/class/drm/card0-DSI-1/status' | tee build/logs/despertar-drm.txt
# El grep se corre EN EL PC sobre el log volcado:
grep -aE "UKE-K1[789]|K19-dump|K21 completo|CBpage|SME\(|S[0-9]-|S4-poll|H[89]-|H5-|H10-|P3-|CM3DBG|cfg_probe|Loaded GMU|UKE-P82|sCR0" \
  build/logs/despertar-s3s4-full.log
```

## Paso 3 — Leer el veredicto (árbol de 6 ramas, §P0.4 del plan)

| Patrón | Lectura | Qué hacer |
|---|---|---|
| `S3-rst0` + `S4-pollOK` + `H8-cm3` + `H9-hfiq` + `H10-hfi` sin FAIL | **GPU viva de punta a punta** | P2-ctrl (sonda de panel, 0 escrituras) y luego el panel |
| `S3-rst0` + `S4-pollFAIL` (~100 ms) | el CM3 se liberó y no arrancó: fallo limpio | El K23b para leer CB1; el panel por P2-ctrl |
| `S3-rst0` + **ni** `S4-poll*` | el primer read del poll wedgea (firma #P47) | máquina muerta: `CBpage` ya saldrá por consola, K23b y rollback a B |
| **sin** `S3-rst0` | el write del release no retornó (o el dump abortó antes) | el K23b **ya no aporta** (si el dump aborta, no hay `GEO`): mirar el WARN, techo 1 fix |
| WARN/machine-check durante el volcado | el ioremap volvió a salirse | el K23b lo evita por construcción (ceñido al recurso) |
| ni `K19-dump`, o el boot no llega | muerte pre-S2 no modelada | consola + WARN; techo 3 ciclos/hipótesis |

**Con el K23 Specifically, añade esto**: si el volcado imprime `CBpage(2)`/`CBpage(3)` con valores
*plausibles*, **no te fíes**: son CB0 y CB16 leídas con la etiqueta equivocada, y las CB4..CB11
salen de fuera del SMMU. La pregunta «¿mapea CB1 el 0x4000?» **no tiene respuesta con este kernel**.

## Paso 4 — e2fsck ANTES de cada ciclo con reboots sucios (lección de los zombis)

Flujo probado (el §A.2 de `P7-fsck-f9.md` quedó refutado en vivo, ledger #446): parar los 3 sockets
de journald + `mount -o remount,ro /` + **una sesión SSH persistente con keepalives abierta ANTES**
del remount + auto-reboot integrado (patrón `/var/tmp/uke-fsck3-session.log`). Montar ro **siempre**
con `norecovery`. Empezar por el inventario `-fn`. Si el zombi corta el fsck: esperar y reconectar,
**no rebotar**.

## Lo que se decidió en el PC el 1-oct (para no perderlo)

- **K23b** construido y pre-registrado: el volcado del CM3 con la geometría del ID1, el decode de
  `S2CR`/`SMR` correcto, el ioremap ceñido a los 0x40000 del recurso, 8 descriptores (el del
  icache@0x4000 es el índice 4) y `pr_flush` tras `S3-rst0`. Repack con
  `docs/historia/gates-palawan/repack-k18.py --out boot-ukek23b.img --kernel …/k23b-build/… --gate-k23b --dsid`.
- **Reproducibilidad cerrada**: `build/gates/patches/ACUMULADO-palawan-d1c7ef2e0-a-k24.diff` lleva
  todo el proyecto (K1..K24) y está **verificado**: `patch -p1` sobre `git archive d1c7ef2e0`
  reproduce el árbol byte a byte (`SHA-ARBOL-K24.txt`). El kernel ya no depende de un directorio
  ignorado por git.
- **P2-ctrl sigue sin poder ejecutarse**: `modetest` no está en el rootfs de la tablet y no hay
  `libdrm`/`mesa`/`mesa-utils` stageados. Es el primer paso de pantalla y hay que resolverlo
  (scp al NCM + `pacman -U` offline) antes de que sirva de algo.

## Nota sobre subagentes
La cuota de la sesión del 30-sep/1-oct se agotó una vez (la ronda de crítica de v3 hubo que
repetirse). Para auditorías independientes de artefactos: **sesión nueva** con el contexto de
ESTADO-VIVO + PRE-REGISTRO. La ronda del 1-oct (V2) está en `build/gates/revision/V2-critica-k23b.md`.
