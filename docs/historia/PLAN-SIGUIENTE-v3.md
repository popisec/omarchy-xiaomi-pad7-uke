# PLAN DE TRABAJO — omarchy-uke (v3, 1-oct-2026) — OBJETIVO: GPU + PANTALLA

> ## ⚠️ SUSTITUIDO por `docs/historia/PLAN-SIGUIENTE-v4.md` (1-oct) — y su §K24 está además RETRACTADO
> Este plan v3 ya no se ejecuta. Su diseño del fix K24 (L125-128: «programar SMR+S2CR+CB
> estilo K19 antes del release») quedó **refutado** el 1-oct: el volcado leía `S2CR` al revés y
> en realidad el SID 5 está **válido y en TRANS por CB1**, así que el S2CR no hay que tocarlo.
> **K24 = mapear el icache@0x4000 en la tabla de CB1.** Ver el banner de corrección de
> `docs/historia/PLAN-SIGUIENTE-v4.md` y `build/gates/revision/V2-critica-k23b.md`.

> **Sustituye a `docs/historia/PLAN-SIGUIENTE-v2.md`** en todo lo relativo a GPU/pantalla (orden del dueño:
> «pantalla + GPU del todo; el resto después»). Lo no cubierto aquí (WiFi/F3, Omarchy/F6,
> táctil/F4, rotación/F7) sigue en v2 P3, detrás de este cierre.
>
> **Restricciones**: esta planificación NO toca la tablet. Git: solo commits locales selectivos
> (sin remotos, sin reescribir historial). Toda ejecución empieza releyendo `docs/historia/ESTADO-VIVO.md`.
>
> **Crítica**: ronda de subagentes BLOQUEADA por cuota («exceed quota limit», 1-oct ~11:15);
> §7 recoge la crítica interna (no independiente) y deja la ronda independiente para sesión nueva.

## §1 Estado de partida (verificado 1-oct ~11:10-11:20, solo lectura)

| Dato | Valor | Fuente |
|---|---|---|
| Tablet | **ZOMBI** (ping 2/2; puertos 22 y 5555 cerrados) | medido hoy; ESTADO-VIVO |
| Slot activo | **a** (experimental desde F9, #P45) | ESTADO-VIVO; #P45 |
| `boot_a` | **K23** `8e7ed4f97290c843b969b5bffd09975bdc031488c723f08f9465e55294d0a687` (96 MiB) — verificado hoy en disco | sha256sum; repack-k18d-report G7 |
| Cmdline K23 | 370 B, variante dsid (**con** `video=DSI-1:d`) | repack-k18d-report G2 |
| `dtbo_a` | **s263** `fe06fccc…` (GPU+GMU al SID 5) — verificado hoy en disco | sha256sum; #P48 |
| Slots b (rollback, INTACTO) | boot **K13-dsid** `e0ee47dc…` + dtbo **s260** `6fbb5173…` — verificados hoy contra `backup-par-bueno/` y `SHA-BUENOS.txt` | sha256sum |
| Vigía fastboot | **PAUSADO y sin proceso vivo** (pausa `/tmp/uke-fastboot-watch.pause`, 02:29) | medido hoy |
| Consola | **Lector único YA VIVO** (loop desde 02:22 con guard `[ -e /dev/ttyACM0 ]`; log `/var/tmp/uke-sesion-console.log`, 2,1 MB, último dato 387 s) | medido hoy; REGLA-UN-SOLO-LECTOR |
| Semáforo hermano | sin sesión viva (ledger #449 = el cierre nocturno de este proyecto) | FLASH-LEDGER tail |
| Presupuesto de escrituras de HOY | **ya consumidas 2** (K22+K23 dd a boot_a, ledger #449) | ledger #449 |

**Qué contiene K23** (cadena acumulada): k16-split + k17-migas (P82, S0, S4) + K18-kgsl-keep +
K19-dump (SME/CBpage/tablas) + K20-gmu-shared + K22-fw-en-initramfs (`lib/firmware/qcom/`) +
K23-ioremap-2MB.
**Marco honesto**: K23 es un **build de instrumentación** (el fix del dump, no del CM3). Nada en
K22/K23 toca el fetch del CM3: **el fix esperado es K24**. Medido en K22: el fw carga a 4,07 s y la
escalera corre en el arranque hasta S2; el dump abortaba antes de S3. **K23 = primer arranque en el
que el dump (y por tanto S3/S4) puede completarse con todo vivo.**

## §2 Definición de «hecho» (medible y persistente)

| Objetivo | Hecho = | Fuente del criterio |
|---|---|---|
| GPU (OBJ 5 / F1a) | `eglinfo -B` = `freedreno` + **GLES 3.2** sobre `renderD128` | OBJETIVOS fila 5; G1-gpu-render §5c |
| Pantalla (OBJ 6 / F1b) | `card0` + conector o82 con `modes` 3200×2136 + **FOTO** + persistencia (power-cycle en frío + 2ª foto) | OBJETIVOS fila 6; PLAN-PANTALLA (no valen vfb ni estado runtime) |
| Cierre conjunto | Hyprland + quickshell visibles en el panel (foto final) | PLAN-PANTALLA cierre |
| Honestidad | Nada se declara hecho sin evidencia en fichero + relectura sha256 + repetibilidad tras frío | docs/historia/AGENTS.md; F criterio global |

**Por qué GPU antes que pantalla en el orden de lectura**: el arranque abre card0 (`msm_open →
load_gpu → GMU`) antes de que el modeset del panel pueda correr; **si el camino GPU se cuelga** el
modeset no llega a ejecutarse (medido #P46/#P47: 0 migas UKE-P82 en las muertes). Pero **si el
camino GPU falla LIMPIO o se le hace dormir (`uke_skip_load_gpu`)**, el modeset corre igual — la
pantalla no depende de la GPU (fbcon no la necesita; `/dev/fb0` no pasa por `msm_open`, G1 §5b).
El plan usa ambas vías; no supone que arreglar la GPU arregle la pantalla.

## §3 Fases

### P0 — Despertar y veredicto del CM3 (0 escrituras; dueño + PC) ~30-60 min

1. **Antes del power-cycle** (PC):
   - Consola: comprobar el lector vivo (`pgrep -af 'ttyACM0'`) y el nodo real (`ls /dev/ttyACM*` —
     si la tablet re-enumera como `ttyACM1`, el loop actual queda CIEGO; relanzar con el nodo
     correcto matando antes el viejo). **Snapshot del log vivo a `build/logs/antes-despertar.log`**
     (precedente: /var/tmp borró árboles vivos).
   - `ls -l /tmp/uke-fastboot-watch.pause` (vigía pausado; recuperación manual, §5).
   - Poll ligero de fastboot durante la ventana de arranque (`while :; do fastboot devices; sleep 5; done`)
     para capturar una caída a fastboot en cuanto ocurra.
2. **Power-cycle** (dueño: power ~12 s + toque). Desenlaces:
   - (i) arranca K23 (slot a) → paso 3.
   - (ii) cae a fastboot → `fastboot getvar all` (contadores) y `battery-voltage`; después
     `set_active a` + `reboot` (reintenta A; resetea retry) o `set_active b` (par estable) según
     lo que diga la consola.
   - (iii) ni consola ni USB → batería/teclas; no insistir (watchdog sin arreglar).
3. **En cuanto responda SSH** (prioridad máxima: el zombi puede volver a los ~280-400 s):
   **capturar primero, fsck después.**
   ```sh
   build/gates/uke-ssh.sh \
     'dmesg -n 7; dmesg | grep -aE "UKE-K1[789]|K19-dump|K21 completo|CBpage|SME\(|S[0-9]-|S4-poll|H[89]-|Loaded GMU|UKE-P82" | tail -140' \
     'cat /sys/bus/platform/devices/3d00000.qcom,kgsl-3d0/power/runtime_status; ls /sys/class/drm/; cat /sys/class/drm/card0-DSI-1/status' \
     | tee build/logs/despertar-s3s4.txt
   ```
   La consola pierde la ventana 3,95-4,18 s → **el veredicto se lee de `dmesg`**, no de la consola.
   Si la sesión SSH no llega: consola ACM + `build/logs/antes-despertar.log`.
4. **Árbol de decisión por migas** (código: `a6xx_gmu.c:408-421`; el dump corre entre S2 y S3):

   | # | Patrón en `dmesg` | Lectura | Siguiente |
   |---|---|---|---|
   | A | `K19-dumpOK` + `S3-rst0` + `S4-pollOK` (+`H8-cm3`/`H9-hfiq`) | el CM3 arrancó: la traducción funciona | P1 y P2a |
   | B | `K19-dumpOK` + `S3-rst0` + `S4-pollFAIL` (el poll caduca a ~100 ms: `gmu_poll_timeout(…,100,100000)`) | el release VOLVIÓ y el CM3 no arrancó: **fallo limpio**; la GPU queda ausente y el sistema sigue | leer `CBpage` → K24; y el camino del panel queda LIBRE → P2 (test de panel) |
   | C | `K19-dumpOK` + **sin** `S3-rst0` | la escritura del release no retorna (K20-style, #P48): stall local | leer `CBpage` (ya impreso) → K24; si además el boot no pinta: P2 con `skip_load_gpu` |
   | D | `K19-dump` sin `K19-dumpOK`, o WARN/machine-check | el dump volvió a fallar | K23b (fix) y repetir el ciclo |
   | E | ni `K19-dump`, o el boot no llega a SSH/consola | muerte anterior a S2 (p. ej. pánico por `hung_task_panic`) | consola + WARN; rollback a b si toca |

   **Esperado razonable: B o C** (nada en K22/K23 arregla el fetch del CM3 — §1). Si sale A,
   revisar dos veces antes de creerlo.
5. **e2fsck** ANTES de cualquier ciclo nuevo (fs de reboots sucios + zombi; flujo
   `prepara/P7-fsck-f9.md` §A.2: dejar la sesión SSH abierta ANTES del remount ro — con `/` en ro
   sshd rechaza conexiones nuevas). Si no hay SSH: vía ACM/initramfs (§A.3 del mismo runbook).

### P1 — GPU de punta a punta (0 flashes; solo si A o tras K24) — cierra OBJ 5

1. **Staging de userspace**: verificado hoy: `build/pkg/` **no** tiene paquetes de mesa
   (`modules-uke-k7`, `panel-o82`, `uke-gpu-firmware`, `uke-wifi-payload`). Obtener
   `mesa libdrm mesa-utils` (aarch64) por el canal USB documentado en A1-auditoría-instalador
   §4 / v2 P3.5 (WiFi muerto) y verificar sha al copiarlos.
2. `eglinfo -B` con doble captura viva y **una sola apertura desprendida** (G1 §5c). Criterio:
   `freedreno` + GLES 3.2.
3. Si el render falla pero S4 llegó: escalera `Z2`/zap + `measure-cm3.sh` (sin más flashes).
4. Registrar (PRE-REGISTRO + ledger + OBJETIVOS fila 5).

### P2 — Pantalla (1-2 repacks + 1-2 flashes; todo a slot A)

Tres artefactos candidatos; se eligen según el veredicto P0 (1 cambio por ciclo, fila propia):

- **P2-plain** = `repack-k18.py` sin `--dsid` (mismo kernel K23, cmdline 356 B **sin**
  `video=DSI-1:d`). Sirve si el camino GPU **completa** (A: vive; B: falla limpio) → el modeset
  corre con el panel habilitado y las **migas UKE-P82** dan el punto exacto:
  - (a) fbcon pinta → **FOTO** + `status`/`modes` del o82 + persistencia (cold boot + 2ª foto) → P3.
  - (b) vive sin pintar → `modes`/`status` por SSH; **no abrir card0 si el CM3 sigue roto**
    (`modetest` abre → CM3); con GPU sana (A) `modetest` es instrumento válido.
  - (c) muere → **última miga UKE-P82 = punto exacto**. Sospechosos ya documentados:
    `power_on[vsp|vsn]` (gpio-shared-proxy), `rst` (GPIO2/tlmm), `cmd[N]` (DSI host), tras
    `prepare: COMPLETO` (scanout/DPU). Tocar rails ⇒ **GO explícito del dueño**.
- **P2-skip** = **`msm.uke_skip_load_gpu=1`** (parche nuevo, ~5 líneas en `msm_drv.c:198-207`;
  diseño en U2 §4) + cmdline plain. **No existe hoy** (grep vacío en `build/kernel-pokes/k18-tree`).
  Sirve si el camino GPU **se cuelga** (C) o como aislamiento del segundo-asesino (abajo): KMS+panel
  con la GPU dormida (fbcon no la necesita; `/dev/fb0` no pasa por `msm_open`). **Prepararlo offline
  ya** (0 tablet) para tenerlo listo; gate: una miga que pruebe que el param se aplicó.
- **K24** = fix del mapeo del CM3 (GPU). Diseñar **con el `CBpage` de K23** (no antes):
  - Si el dump muestra `SME(5)` inválido (SMR/S2CR sin traducir) → **K19-style**: programar a mano
    SMR id=5 mask=0 + S2CR translate→CB + CB con tabla que mapee iova 0x4000 → phys del TCM, entre
    S2 y S3 de `a6xx_gmu_start` (el vendor lo hace vía TZ).
  - Si `SME(5)` es válido pero la tabla del `TTBR0` **no mapea 0x4000** (o el CB no es el del
    dominio) → **K21-style**: mapear el icache en la tabla que el CB ve en el instante del release
    (o corregir el puntero del CB).
  - Si ambos son válidos → el problema no es la traducción: volver a la evidencia (¿SID? ¿el BO
    no es el que el CM3 fetcha?).
  Mantener `video=DSI-1:d` en K24 (la GPU se prueba por `renderD128`; el panel va en P2-*).
- **Segundo-asesino (hipótesis independiente, no olvidarla)**: #P40 midió que un boot **sin fw y
  con el panel habilitado** también murió tras el ENOENT, y U2 §1 atribuyó esa muerte al camino del
  panel/scanout. La teoría unificada (S3) solo cubre las muertes CON fw. Es decir: arreglar el CM3
  **no garantiza** el modeset. El test de panel (P2-plain/P2-skip) es el que lo decide; las migas
  P82 y los informes de rails/GPIO ya están preparados.

**Presupuesto**: ≤2 ciclos hoy (además de los 2 ya consumidos por K22/K23 — ver §4).

### P3 — Persistencia y cierre

1. Artefacto final (kernel K2x + s263) verificado por relectura en slot A; cold boot + 2ª foto +
   `eglinfo` post-frío.
2. `ESTADO-VIVO` + `NOTAS` + `OBJETIVOS` + fila `#P5x` + ledger hermano + commit.

## §4 Reglas operativas del ciclo (obligatorias)

- **Presupuesto/ciclo**: batería ≥3750 mV + cargador de pared; portátil enchufado; **≤2
  escrituras/día**. **OJO 1-oct: ya hay 2 (K22/K23)** → cualquier escritura de hoy requiere
  **exención declarada del dueño en la fila** (precedente #P44/#P45). `getvar all` antes/después.
  - Batería si NO hay fastboot: `prepara/bateria.sh` / `/sys/class/power_supply/*/voltage_now` por
    SSH; si hay fastboot: `fastboot getvar battery-voltage`.
- **Pre-registro**: fila en `PRE-REGISTRO-PANTALLA.md` + `FLASH-LEDGER` del hermano con sha256 del
  artefacto ANTES de flashear; relectura al tamaño exacto.
- **Slots**: todo a **A**; **B = rollback** (K13-dsid+s260), no se toca. `set_active a|b` como
  reset de contadores.
- **Escritura a boot_a**: hacerla TEMPRANO en la ventana de boot (el zombi llega a ~280-400 s);
  `dd` a `/dev/disk/by-partlabel/boot_a` + `sync` + **`drop_caches`** + relectura sha256 +
  **reinicio limpio** (no `sysrq-b`: no persiste); si el zombi corta a mitad → power-cycle y
  rehacer (nunca dejar boot_a a medias).
- **Consola**: **lector único** (hoy vivo; verificar nodo ACM antes/después; si muere, relanzar con
  guard `[ -e ]` y matar el `cat` huérfano); **doble captura** (ACM + `ssh dmesg`); la ventana
  3,95-4,18 s se pierde → el veredicto sale de `dmesg`/ftrace.
- **Vigía**: hoy pausado y sin proceso → recuperación manual (§5). Si se re-arma: ARMAR CON PAUSA
  antes del flash, `rm -f` solo tras leer el desenlace.
- **Fastboot**: por teclas físicas (el ABL ignora BCB); en fastboot no carga bajo umbral.
- **e2fsck antes de cada ciclo con reboots sucios**; zombi ⇒ capturar primero, fsck después; no
  confiar en `systemctl reboot` si ya zombifica.
- **SMMU**: nunca instrumentación en runtime; nunca volcar rangos MMIO.
- **Semáforo hermano** antes de cada flash (hoy: libre).
- **Arranques experimentales**: power-cycle en frío mejor que `fastboot reboot` (USB del BL vivo en
  el handoff — #P17).

## §5 Red de recuperación (comandos literales)

- Tablet en fastboot con A agotado: `fastboot set_active a && fastboot reboot` (reintenta A) — o
  `fastboot set_active b` para volver al par bueno.
- Rollback: `fastboot set_active b` + (si B se hubiera pisado, que no es el caso)
  `fastboot flash boot_b build/backup-par-bueno/boot-ukek13-dsid.img`.
- Vigía (si se re-arma): `setsid nohup bash build/gates/uke-fastboot-watch-k16.sh >/dev/null 2>&1 &`
  — restaura el par a la 3ª caída; NO dejarlo armado sin pausa durante una observación.
- Consola: reutilizar el lector vivo; si hay que relanzarlo, matar también el `cat` hijo huérfano
  (REGLA-UN-SOLO-LECTOR).

## §6 Riesgos vivos (top)

| # | Riesgo | Evidencia | Mitigación |
|---|---|---|---|
| R1 | K23 es el **primer arranque con el dump completo**: desenlace inédito (¿S4? ¿fallo limpio? ¿stall?) | #P48 (stall runtime vive); K22 (sin S3 vive); código `a6xx_gmu.c:408-421` | árbol de decisión §P0.4 (5 ramas); captura desde el segundo 0; slot B; recovery manual |
| R2 | Zombi (~280-400 s) enmascara el veredicto | 3 zombis anoche (#P49) | capturar `dmesg` primero; fsck; escribir temprano |
| R3 | fs sin journal se re-ensucia con cada wedge | #P49 | e2fsck antes de cada ciclo (P7 §A.2/A.3) |
| R4 | Dump K23 ilegible → K24 a ciegas | K19/K22 (bug propio) | no flashear K24 sin `CBpage`; rama D = K23b; alternativa ftrace |
| R5 | Panel nunca ejercitado end-to-end (0 migas P82) | #P46/#P47 | P2-plain/P2-skip con migas P82 + informes rails/GPIO; GO del dueño para rails |
| R6 | **Segundo asesino** en el camino del panel (muertes sin fw, #P40/U2) | #P40; U2 §1 | no dar el modeset por hecho tras el fix GPU; el test de panel lo decide |
| R7 | `mesa`/`eglinfo` ausentes y sin .pkg staged | verificado hoy; U2 §5 | obtener por USB (A1 §4 / v2 P3.5) antes de P1 |
| R8 | Sin vigía vivo + A agotable → fastboot sin rescate | medido hoy | operador con §5 delante + poll de fastboot |

## §7 Crítica incorporada

**Ronda independiente (subagentes): BLOQUEADA por cuota** — 5 intentos (4 ejes en paralelo + 1
suelto) devolvieron `exceed quota limit` (1-oct ~11:15). Es el mismo límite que anotó la sesión
nocturna; el remedio documentado es **sesión nueva** con el contexto de ESTADO-VIVO + PRE-REGISTRO.
**Pendiente: re-ejecutar la ronda (kernel/GPU-SMMU, pantalla/DSI, operativo, método) en sesión nueva.**

**Crítica interna (NO independiente — sesgo del mismo autor; aplicada al plan):**

| # | Sev | Hallazgo | Evidencia | Resolución en este plan |
|---|---|---|---|---|
| C1 | BLOQUEANTE | El árbol original confundía «sin S3» con «dump abortado»: la escritura del release puede NO retornar sin que el dump falle (medido en K20) | `a6xx_gmu.c:414-415`; #P48 («S3-rst0 NO imprime… la escritura no retorna») | Árbol de 5 ramas (A-E) con `K19-dumpOK`/`volcado K21 completo` para separar D (dump) de C (stall) |
| C2 | ALTA | El plan presentaba «S4-pollOK» como el desenlace esperado; nada en K22/K23 arregla el fetch del CM3 | §1; #P47/#P48 | §1 lo declara build de instrumentación; esperado B/C |
| C3 | ALTA | «Arreglar la GPU ⇒ el modeset funciona» es falso como inferencia: hay muertes sin fw (sin CM3) con el panel habilitado | #P40; U2 §1 | R6 + P2-plain/P2-skip como test independiente del panel |
| C4 | ALTA | `S4-pollFAIL` (poll de ~100 ms) es un desenlace con valor propio: GPU ausente y camino del panel libre | `gmu_poll_timeout(…,100,100000)`; U2 §1 (msm_open sigue con gpu=NULL) | Rama B del árbol + P2-plain |
| C5 | MEDIA | El lector de consola puede quedar ciego si el nodo re-enumera como `ttyACM1` (el loop solo mira ACM0) | `uke-run.py` (el nodo no es fijo); loop PID 8778 | P0.1: verificar nodo + relanzar si toca; snapshot del log |
| C6 | MEDIA | No había gate de batería para el caso «la tablet arranca en Arch» (getvar solo en fastboot) | runbook/REGLA | §4: `prepara/bateria.sh` por SSH |
| C7 | MEDIA | Presupuesto: 1-oct ya consumió 2 escrituras (K22/K23) → hace falta exención del dueño | ledger #449 | §1 y §4 lo declaran |
| C8 | MEDIA | `build/pkg/` no tiene mesa/libdrm/mesa-utils staged (el plan lo daba por posible) | `ls build/pkg` verificado hoy | R7 + P1.1 (obtener por USB) |
| C9 | MEDIA | dd a boot_a con zombi a la vista: riesgo de escritura a medias | #P49 | §4: dd temprano + sync + drop_caches + relectura; rehacer si corta |
| C10 | MEDIA | e2fsck asumía SSH vivo; si el boot se cuelga no hay vía | P7 §A.2 vs §A.3 | §P0.5: vía ACM/initramfs (§A.3) como fallback |
| C11 | BAJA | Cautela de `modetest` mal generalizada (solo aplica si el CM3 sigue roto) | G1 §5b; #P47 | P2(b) matizado |
| C12 | BAJA | La descripción de las migas P82 («21») no cuadra con «una por comando DSI del init»; el gate solo exige ≥20 | repack G3 («P82>=20»); K17 §pre-registro | P2 describe lo que cubren, sin fijar el número |
| C13 | BAJA | Referencias por PID volátiles | — | §7 usa patrones (`pgrep -af`) |
| C14 | BAJA | Corte de CONSOLE en la ventana 3,95-4,18 s podría explicar «S3 no imprime» en K20 | #P44 (migas ilegibles en esa ventana) | El veredicto se lee de `dmesg`, no de consola (§P0.3) |

## §8 Gaps documentales a cerrar en P0 (0 tablet) — de la revisión de hoy

1. `docs/historia/RUNBOOK-SIGUIENTE.md:29` cita «Reglas que salvan ciclos (ESTADO-VIVO, 15 reglas)» y **esas
   reglas no existen** en ESTADO-VIVO ni en su historial git (`git log -S` vacío): crear
   `REGLAS.md` canónico (o sección en ESTADO-VIVO) con las reglas pagadas.
2. `README.md` §Reglas sigue citando el par `s244-bounce`+`s229` como vigente (docs/historia/AGENTS.md ya lleva
   el banner «solo ESTADO-VIVO manda»): actualizar.
3. `OBJETIVOS.md` fila 1 dice «e2fsck PENDIENTE» (cerrado 1-oct) y fila 6 cita «tras K19» (ya es
   K23): refrescar.
