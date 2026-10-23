# PLAN-NUEVAS-VIAS — caminos fuera de los hunks contra el release racy (L11 0/6) — 2026-10-10 (solo PC, tablet intacta)

> Encargo del dueño: NUEVOS caminos, pensar fuera de los hunks. Estado: el mismo binario L11
> muere 6/6 en puntos distintos (gbif y pre-rst/write) en 3 boots (#580). Vías agotadas o
> archivadas: hunks L1–L5, combinación L5, fix C1+C2, poll vendor (HFI -110), fw-map, RS
> GENERAL_10/8 (timing, archivado), breadcrumb pre-registro (murió antes), waits vendor,
> retardos acumulados (refutada, RE-TIMING). Presupuesto de escrituras de hoy AGOTADO (28 en
> boot_a): todo lo de coste 0 flashes es ejecutable ya; lo demás es diseño para mañana.
> Tablet VIVA en L11+s250 (slot a). Solo PC: este informe diseña, no construye, no flashea.

Regla transversal (de #580): **n=1 no decide nada**. Todo camino con flash exige criterio
binario + repetición mínima (n≥2 opens en el mismo boot, o reflash idéntico R0-style) antes
de declarar victoria. Y todo kernel nuevo conserva POKE=113 y los testigos verbatim para no
mover el mapa.

Orden de lectura: §0 (ranking y orden recomendado) → §§1–4 (fichas) → §5 (matriz coste/orden).

---

## 0. Ranking y orden recomendado (arriba, sin rodeos)

| # | Camino | Flashes | Qué decide | Por qué este puesto |
|---|--------|---------|------------|---------------------|
| 1 | **P1 pstore/mtdoops tras muerte** | 0 | ¿El kernel dejó last_kmsg del freeze? | Gratis, inmediato, backend YA activo (mtdoops en partición oops, `printk.always_kmsg_dump=1`). Si hay traza, todos los demás caminos se reordenan. |
| 2 | **P5 framebuffer LAST-POKE** | 0 | PC del freeze a nivel instrucción | El segundo canal YA existe en el binario y nunca se leyó. Cero coste, cierra el intervalo [write…fin-flush] de CRITICA-L8. |
| 3 | **P4 watchdog bark como testigo** | 0 (lectura) → 1 (si hay que activarlo) | ¿Hay stall de bus (bark sin bite) o reboot limpio (bite sin bark)? | `QCOM_WDT=y` ya; el bark es IRQ, no cuelga. Distingue freeze-duro de reboot-voluntario. |
| 4 | **P8 batería alta + gates fijos** | 0 | ¿El flake correlaciona con mV/slots? | Ledger #574–#580 muestra deriva 3827→3779 mV. Cargar a >4000 mV y repetir 6 opens cuesta cero flashes. |
| 5 | **P3 ftrace function_graph en DRAM** | 0–1 | Traza del camino open sin UART | `FTRACE+FUNCTION_TRACER+FUNCTION_GRAPH=y` ya en k52L11. Solo tracefs + buffer en DRAM; no añade MMIO al camino. |
| 6 | **B1 diff stock-vs-s250 en PC** | 0 | ¿Qué trae el dtbo stock que s250 no lleva? | Solo PC (dtbo-extract.py + decompilar). Pre-requisito de B2/B3. |
| 7 | **B2 s229-pelado / B3 stock+solo-GPU** | 1 flash dtbo c/u (cero kernel) | ¿s250 mete ruido en el release? | El dtbo no toca el binario L11: si el punto de muerte se mueve solo con cambiar dtbo, el ruido es DT, no kernel. |
| 8 | **C1 lectura GDSC/RSC/clocks en vivo** | 0 | ¿Llega el dominio GX estable al release? | sysfs/debugfs (`power-domain`, `clk_summary`, `regulator`) por SSH con GPU OFF. Foto del estado que el release hereda. |
| 9 | **C4 quitar `clk_ignore_unused pd_ignore_unused`** | 1 (cmdline) | ¿El release solo vive porque todo queda encendido? | Esos dos flags están en NUESTRA cmdline (k52L11 CONFIG_CMDLINE) y enmascaran bugs de GDSC. Quitarlos es el test de honestidad del power. |
| 10 | **C5 interconnect vote mínimo** | 1 | ¿El CM3 liberado atasca el bus por falta de voto BW? | `INTERCONNECT_QCOM_PALAWAN=y` + RPMH vivos. Un voto explícito antes del release, sin tocar registros GMU. |
| 11 | **C6 SMMU fault/debug** | 1 (build con `ARM_SMMU_QCOM_DEBUG`) | ¿Hay fault SMMU (SID5/fetch) en el freeze? | Hoy `QCOM_DEBUG` off; los faults van a dmesg/consola y sobreviven en pstore si P1 funciona. |
| 12 | **C7 hyp-assign / SCM / TZ** | 0 (lectura) → 1 | ¿La GPU sigue asignada al hyp/TZ al soltar el CM3? | `QCOM_SCM=y`, shmbridge. Leer estado antes de tocar nada. Vía larga, pero es la que un ingeniero Qualcomm miraría en 2º lugar tras GDSC. |
| 13 | **D1 kexec desde Android** | 0 flashes Linux (arranca Android stock) | ¿El release vive si el estado power/fw lo deja el vendor y no ABL+k52? | Heterodoxa y barata en riesgo: no toca slots Linux; `KEXEC=y` ya. Si vive, el culpable es el estado heredado del arranque, no el código del release. |
| 14 | **D3 Mesa/render por scp** | 0 kernel | Primer render off-screen por renderD128 | Bloqueada hasta HFI arriba (PRE-RENDER). Preparar pkgs en PC, no instalar hasta que un kernel dé HFI. |
| 15 | **L16-R writes-ciegos + R0-batería** | 1 + 0 | Cierre timing-vs-flake con batería controlada | Solo si P1–P8 no dan causa: L16 (=L11 sin readbacks GBIF) + R0 repetido con batería alta. Último recurso antes de re-arquitectura. |

Lo que se propone ARCHIVAR (no reintentar): hunks L1–L5 sueltos, RS GENERAL_10/8
(archivado por L14), waits vendor, retardos acumulados como ley general (RE-TIMING),
firmware-map (tóxico), bindear apps-smmu por compatible (wedge 6/6, s250 §cabecera).

---

## 1. Instrumentación no-colgante (P1–P6)

Principio común: el bug mata la máquina en DURO (sin SSH, slot tocado, sysrq-b). Todo
instrumento que haga MMIO en el camino del release es sospechoso por definición (L14/L15 lo
demostraron: hasta un readback GBIF mata). Los instrumentos válidos son los que escriben a
DRAM o a registros ya probados, nunca a esclavas nuevas.

### P1. pstore / mtdoops tras una muerte — 0 flashes, HACER PRIMERO

- **Qué mide.** El `last_kmsg` / dmesg del boot muerto, leído en el boot siguiente por SSH:
  `ls /sys/fs/pstore/`, `cat /sys/fs/pstore/dmesg-*.enc` (o `.txt`), más `dmesg | grep -i
  "oops\|panic\|die\|hardirq\|watchdog\|smmu.*fault\|gmu\|hfi"`.
- **Por qué puede funcionar aquí (verificado en PC).** El backend YA está cableado sin que
  nadie lo pidiera: cmdline stock trae `block2mtd.block2mtd=/dev/block/by-name/oops,2097152
  mtdoops.mtddev=0 mtdoops.record_size=2097152 mtdoops.dump_oops=1
  printk.always_kmsg_dump=1`, y el kernel lleva `CONFIG_MTD=y + MTD_OOPS=y + PSTORE=y +
  PSTORE_CONSOLE=y + PSTORE_PMSG=y + PSTORE_RAM=y`. `ftrace_dump_on_oops` también viene en
  cmdline. Es decir: cada muerte con `oops/panic/die` ya vuelca a la partición `oops`.
- **Coste.** 0 flashes. Procedimiento: provocar 1 open que muera (L11 ya muere solo) →
  sysrq-b o power-cycle → boot siguiente por SSH → leer `/sys/fs/pstore/` ANTES de tocar
  nada más. Registrar en ledger: lista de ficheros pstore + últimas 50 líneas.
- **Criterio de éxito.** Aparece `dmesg-*` con la cola del freeze (últimos testigos UKE +
  posible `Internal error`, `smmu fault`, `watchdog bark`, `rcu stall`). Entonces el PC del
  freeze se conoce y los caminos C5/C6 se diseñan sobre evidencia.
- **Criterio de fracaso.** `/sys/fs/pstore/` vacío tras 2 muertes (distintos puntos: gbif y
  pre-rst). Significa freeze por debajo del logbuf (stall de bus síncrono: la CPU no llega a
  volcar) o backend mtdoops no operativo en nuestro boot (verificar `dmesg |
  grep -i mtdoops` en boot vivo: si el driver no bindea, P1 es vía muerta y se pasa a P2).
- **Trampa conocida.** ESTADO-VIVO avisa: "ramoops no sobrevive power-cycle (canal=sda30)".
  Eso es ramoops-DRAM, NO mtdoops-partición: la partición `oops` es flash y SÍ sobrevive.
  No confundir ambos. Si sysrq-b no responde (freeze duro total), el power-cycle largo es el
  camino; mtdoops sobrevive igual.

### P2. ramoops en DRAM reservada — 1–2 flashes, SOLO si P1 da vacío

- **Qué mide.** Lo mismo que P1 pero en DRAM con `ramoops.mem_address/mem_size`, útil si el
  backend mtd resulta no bindear en nuestro árbol (el DT palawan puede no traer el
  `block2mtd` equivalente, o el `oops` by-name no existir en nuestro mapa de particiones).
- **Coste.** 1 flash de DT o cmdline (`ramoops.mem_address=… mem_size=… console_size=…
  ftrace_size=…`) + 1 de verificación. Riesgo: hay que reservar DRAM que no pise
  `mem=2048M` ni el `memmap=0x1A12800$0xE3940000` del cmdline stock. Medir el mapa antes en
  PC (`/proc/iomem` del golden-state k52b2 si existe en evidencia; si no, 1 boot de lectura).
- **Criterio.** Éxito = `dmesg-ramoops` con cola tras 1 muerte. Fracaso = vacío tras 2
  muertes → el freeze está por debajo de todo volcado por CPU (stall síncrono) → pasar a
  P4/P5 (testigos que no necesitan CPU viva: bark IRQ y framebuffer).
- **Orden.** DESPUÉS de P1. No construir sin haber leído P1 dos veces.

### P3. ftrace function_graph del camino open — 0–1 flashes

- **Qué mide.** La secuencia de funciones `msm_open → … → a6xx_gmu_start → release` con
  timestamps, capturada en buffer de DRAM (tracefs), sin UART y sin MMIO nuevo.
- **Por qué es no-colgante.** `CONFIG_TRACING=y + FTRACE=y + FUNCTION_TRACER=y +
  FUNCTION_GRAPH_TRACER=y` YA están en k52L11-bateria.config (líneas 9322–9330). No hace
  falta build: basta `tracefs` en el boot vivo. El trazo vive en DRAM; si la muerte es reboot
  (no power-cycle con pérdida), el buffer puede leerse si el boot siguiente lo vuelca
  (`ftrace_dump_on_oops` ya en cmdline) o si el watchdog-bark lo dispara antes del bite.
- **Procedimiento (0 flashes).**
  ```sh
  mount -t tracefs nodev /sys/kernel/tracing
  echo function_graph > /sys/kernel/tracing/current_tracer
  echo 'a6xx_gmu*' > /sys/kernel/tracing/set_ftrace_filter   # acotar: el buffer es finito
  echo 1 > /sys/kernel/tracing/tracing_on
  # ... provocar el open en otra shell ...
  cat /sys/kernel/tracing/trace_pipe > /tmp/ftrace-open.txt  # o trace tras la muerte si vive
  ```
  Variante con `PSTORE_FTRACE`: hoy `CONFIG_PSTORE_FTRACE is not set` — activarla costaría
  1 build; solo hacerlo si el buffer DRAM se pierde sistemáticamente (P1+P2 vacíos).
- **Coste.** 0 flashes si basta tracefs; 1 build si hay que activar `PSTORE_FTRACE` o
  `IRQSOFF_TRACER` (hoy off) para cazar latencias de IRQ que retrasen el release.
- **Criterio de éxito.** Traza con timestamps hasta N µs del freeze en ≥2 muertes: si el
  delta pre-release varía (jitter grande) → carrera timing confirmada con número, no con
  intuición; si el freeze cae siempre tras la misma función aunque el testigo UART varíe →
  el flake es de drenaje UART, no del release (¡entonces L11 podría estar VIVO y solo mudo!).
- **Criterio de fracaso.** Buffer vacío/corrupto tras 2 muertes (el reboot lo pierde y no hay
  dump-on-oops porque no hay oops). Entonces P3 queda como herramienta intra-boot (opens que
  sobreviven) y se pasa a P4/P5.

### P4. watchdog bark como testigo pre-bite — 0 lectura, 1 si hay que armarlo

- **Qué mide.** Si antes del reboot el watchdog LADRA (bark IRQ) o MUERDE directo (bite):
  bark-sin-bite-inmediato = stall de bus/CPU viva-a-medias (la IRQ aún entra); bite-sin-bark
  = reboot por otro camino (panic/sysrq/TZ); ni-bark-ni-bite = power-cycle manual.
- **Base verificada.** `CONFIG_WATCHDOG=y + WATCHDOG_CORE=y + WATCHDOG_HANDLE_BOOT_ENABLED=y
  + QCOM_WDT=y` en k52L11; cmdline trae `watchdog_thresh=10 hung_task_timeout_secs=20
  hung_task_panic=1`. El QCOM WDT tiene bark (pretimeout IRQ) + bite (reset). Hoy
  `WATCHDOG_SYSFS`, `HRTIMER_PRETIMEOUT` y `PRETIMEOUT_GOV` están off — el bark puede estar
  mudo hacia userspace aunque el HW lo genere.
- **Procedimiento 0-flash.** Tras 1 muerte: leer `dmesg | grep -i "watchdog\|bark\|bite\|wdt"`,
  `/sys/fs/pstore/*` (P1), y el `bootinfo.pureason/pdreason` del cmdline del boot siguiente
  (el bootloader deja la causa del reset: `pureason=0x800001 pdreason=0x2` en el orig —
  comparar tras muerte gbif vs pre-rst; si difieren, ¡son dos muertes distintas con firma
  distinta!).
- **Procedimiento 1-flash (solo si 0-flash no ladra).** Build con `CONFIG_QCOM_WDT` bark-IRQ
  a un handler que hace `uke_poke` a framebuffer (canal P5, sin UART) + `ftrace_dump`. Un
  solo flash, sin tocar el camino del release.
- **Criterio de éxito.** Bark visible antes del reboot en ≥2 muertes → hay ventana IRQ-viva
  entre freeze y reset: esa ventana es donde P3/P5 escriben su evidencia. Fracaso = bite
  directo sin bark en 2 muertes → el reset viene de fuera de la CPU (TZ/hyp/interconnect) →
  refuerza C7 (TZ) y D1 (kexec).

### P5. framebuffer LAST-POKE (el segundo canal que nunca se leyó) — 0 flashes

- **Qué mide.** El PC del freeze a nivel instrucción: los pokes `uke_poke` pintan a framebuffer
  de forma SÍNCRONA y con fallo cerrado (CRITICA-L8 F5). La ACM puede perder bytes en cola;
  el framebuffer no miente.
- **Hecho.** CRITICA-L8 W1 lo deja escrito: "el segundo canal diseñado (uke_poke a
  framebuffer / LAST-POKE) no se explotó: nada en el ledger dice que se leyera pantalla ni
  pstore tras el cuelgue". L8/L11 llevan los pokes DENTRO del binario flasheado.
- **Procedimiento (0 flashes).** Tras 1 muerte con lector ACM armado: fotografiar/leer la
  pantalla (o `cat /dev/fb0`-vía-SSH si el boot siguiente la conserva; si no, foto física
  antes del sysrq-b). Buscar el último poke visible: `pre-rst` vs `write-done` vs `post-rst`
  dirime el intervalo [write…fin-flush] sin nuevo flash.
- **Criterio.** Éxito = el framebuffer muestra un poke que la ACM no trajo (o confirma el
  último ACM) en ≥2 muertes. Fracaso = pantalla ilegible/igual en 2 muertes → el freeze cae
  antes del primer poke post-write o el fb no refresca en stall → pasar a P4.

### P6. `last_kmsg` clásico + `hung_task` — 0 flashes

- Complemento de P1: con `hung_task_panic=1 + watchdog_thresh=10` ya en cmdline, un stall >
  20 s debería panicar SOLO (con traza) en vez de quedarse duro. Si las muertes son reboot
  rápido (<20 s, intérprete ACM con cronómetro), el hung-task no llega: eso ya es un dato
  (muerte rápida = stall síncrono o reset externo, no livelock). Medir el tiempo
  último-testigo→reboot en 3 muertes y anotarlo: <5 s, 5–20 s, >20 s deciden entre
  stall-síncrono / livelock / watchdog-bite.

---

## 2. Aislar s250 vs stock (B1–B3)

Contexto (verificado en PC): en la tablet hay un overlay base **s229** (kgsl-smmu compat +
`iommus=<0x129 0x1c00 0x02>` del DPU + disables, medido que no wedgea) y encima **s250**
(añade 1 fragmento: segundo cliente del DPU hacia kgsl-smmu con phandle literal 0x1c1; NO
toca apps-smmu). La cabecera de mkdtbo-s250.py documenta su propia refutación parcial (el
par SMR estaba invertido en su justificación original; el fragmento final usa phandle
literal y pasa sus gates). Pregunta abierta del dueño: ¿mete ruido s250 en el release de
GPU aunque el release no toque display?

### B1. Diff stock-vs-s250 en PC — 0 flashes, pre-requisito

- **Qué mide.** Qué nodos/propiedades trae el dtbo STOCK (variantes base) que s229/s250
  pisan o añaden: `status`, `compatible`, `iommus`, `power-domains`, `clocks`,
  `interconnects`, `qcom,handoff-smrs`, `qcom,stream-id-range`. Herramienta:
  `build/bootimg/dtbo-extract.py` + `dtc -I dtb -O dts` sobre `build/android/flash-b/
  dtbo-b-stock.img` vs s250-merged.
- **Procedimiento.** Decompilar stock y s250-merged; diff por nodo afectado (apps-smmu,
  kgsl-smmu, mdss, dpu, gpu, gdsc, rpmh). Tabla: propiedad × (stock | s229 | s250).
  Marcar todo lo que s250 añade ENCIMA de s229 (debería ser 1 fragmento) y todo lo que s229
  cambia vs stock (la lista real de riesgo).
- **Criterio.** Éxito = lista cerrada de deltas con veredicto por delta (inocuo / sospechoso /
  necesita-test). Fracaso no existe (es lectura); el riesgo es decompilar mal (verificar con
  los gates G0–G8 del propio mkdtbo-s250.py).
- **Coste.** 0 flashes. Hacer ANTES de B2/B3.

### B2. Boot con s229-pelado (quitar s250, mantener s229) — 1 flash de dtbo

- **Qué mide.** Si el fragmento extra de s250 mueve el punto de muerte del release L11.
  El kernel NO cambia (mismo L11): toda diferencia es 100% atribuible al DT.
- **Coste.** 1 escritura en `dtbo_a` (no en `boot_a`; el rollback es re-flashear s250,
  artefacto en disco). Riesgo bajo: s229 ya estuvo en la tablet y no wedgea.
- **Criterio de éxito.** El mapa de 6 opens cambia de forma estadística (p.ej. 0/6→≥3/6
  supervivencias al release, o el punto de muerte se fija en un solo sitio): s250 mete
  ruido → archivar s250 y seguir sin él. **Criterio de fracaso.** Mismo 0/6 racy en puntos
  distintos → s250 exonerado como causa del flake (puede seguir siendo inútil, pero no es el
  asesino). n≥4 opens antes de decidir.
- **No-flash alternativo (preferido si B1 encuentra sospechoso concreto).** Si B1 aísla UNA
  propiedad sospechosa, el test es s229 + parche de esa propiedad sola, no s229-pelado entero.

### B3. Boot con dtbo STOCK + solo el nodo GPU — 1 flash de dtbo

- **Qué mide.** El experimento de aislamiento máximo: ¿el release L11 vive con el DT que el
  vendor validó, más lo mínimo para que la GPU exista (`kgsl-smmu@3da0000` + `gpu@3d0000`
  + firmwares)? Si vive → el ruido está en algún fragmento s2xx (bisectar después); si muere
  igual → el DT queda exonerado entero y el flake es kernel/power puro.
- **Coste.** 1 flash dtbo + construir el overlay mínimo en PC (derivado de B1: stock +
  compatibles palawan de GPU solamente, sin tocar apps-smmu/mdss/dpu). Riesgo MEDIO: el
  stock puede no traer los compatibles que nuestro kernel necesita para bindear la GPU
  (entonces el open falla en probe, no en release — resultado no-informativo pero no
  destructivo; el rollback es s250).
- **Criterio de éxito.** L11+stock-GPU sobrevive al release n≥2 (aunque muera después en HFI
  -110 estilo #575-mudo: ESO TAMBIÉN ES ÉXITO — el release vive, el problema pasa a ser HFI).
  **Criterio de fracaso.** Muere igual en gbif/pre-rst → DT exonerado → cerrar la vía DT y
  concentrar todo en power (C) y kexec (D1).
- **Orden.** DESPUÉS de B1 y B2. B3 es el más informativo pero el de mayor riesgo de
  resultado no-informativo; B2 primero porque es rollback trivial.

---

## 3. Power / GDSC / RSC / relojes / interconnect / SMMU / TZ-hyp (C1–C7)

Lo que haría un ingeniero de Qualcomm ante un "release racy" (orden suyo, no nuestro):
1º dominios de power y relojes del que se libera (GDSC GX + votos), 2º interconnect/BW,
3º SMMU/faults del fetch del CM3, 4º quién es dueño del HW (hyp/TZ assign). Los hunks L1–L5
atacaron REGISTROS; esta sección ataca SECUENCIAS y DUEÑOS. Ningún camino de esta sección
escribe registros GMU nuevos: solo lee estado, vota power/BW por las APIs, o quita
muletas de cmdline.

### C1. Foto del estado power en vivo (GPU OFF) — 0 flashes, HACER YA

- **Qué mide.** El estado que el release hereda: GDSC GX on/off, votos RSC, relojes GPU
  (gpucc), reguladores (rpmh), `power-domain` del nodo gpu, `clk_summary`, `opp-table`.
- **Procedimiento (SSH, GPU OFF, k52b2 o L11-vivo).**
  ```sh
  cat /sys/kernel/debug/clk/clk_summary | grep -i "gpu\|gmu\|gx\|cx"
  ls /sys/kernel/debug/power-domains/ 2>/dev/null; cat /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null | grep -i "gx\|cx\|gpu"
  cat /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | grep -i "gx\|cx\|gpu\|mx"
  cat /sys/class/devfreq/*/available_frequencies 2>/dev/null; ls /sys/class/devfreq/
  dmesg | grep -i "gdsc\|rpmh\|rsc\|gx.*vote\|aop"
  ```
  Repetir con batería alta y baja (P8): si algún voto/reg aparece solo con batería alta, el
  flake tiene nombre.
- **Coste.** 0 flashes. **Criterio.** Éxito = foto completa archivada en evidencia (es la
  línea base contra la que se comparan C2–C5). Fracaso = debugfs sin esos nodos (defconfig
  sin `PM_ADVANCED_DEBUG` o similar) → se pide 1 build con debug, o se sigue por C4.

### C2. Quitar `clk_ignore_unused` + `pd_ignore_unused` — 1 flash cmdline

- **Qué mide.** Si el release solo sobrevive (cuando sobrevive) porque la muleta deja TODO
  encendido. Esos dos flags están en nuestra CONFIG_CMDLINE (línea 615) y enmascaran
  cualquier GDSC mal secuenciado: con ellos, el dominio GX nunca cae y el CM3 liberado
  encuentra relojes "por accidente"; sin ellos, el orden real de votos queda expuesto.
- **Coste.** 1 flash (solo cmdline del repack, mismo Image L11). Rollback trivial (reflash
  L11 original).
- **Criterio de éxito (el interesante).** Sin muletas el release muere SIEMPRE en el mismo
  punto (determinista) → el flake era la muleta + estado heredado aleatorio → causa raíz
  localizada en secuencia power, a por voto explícito (C3). **Criterio de fracaso.**
  Sigue racy igual → las muletas no son el factor → reponerlas y seguir (C3–C5).
- **Riesgo.** Sin muletas puede no arrancar ni el boot base (otros drivers dependen del
  "todo encendido"). Test previo: quitar UN flag cada vez (`pd_ignore_unused` primero, que
  es el de dominios). Si el boot base no llega a SSH, el experimento es no-informativo y se
  aborta con rollback (1 flash más).

### C3. Voto GX/RSC explícito antes del release — 1 flash kernel (último hunk permitido)

- **Qué mide.** Si votar el dominio GX (GDSC + RSC wake + reloj gpucc) por API antes de
  soltar el CM3 estabiliza el release. Diferencia con D1/D2 archivados: aquellos votaban
  DENTRO del camino con writes sueltos; este vota con las APIs (`pm_runtime_get`,
  `regulator_enable`, `clk_prepare_enable` del `gpucc`/`gdsc_gx`) y VERIFICA el estado
  (leer GDSC status tras votar) antes del release. D1/D2 exoneraron "los votos como
  llamadas con rc=0"; NO probaron "dominio estable medido".
- **Coste.** 1 build+flash (L16-PWR). Sin MMIO GMU nuevo: solo APIs + 1 readback de status
  de dominio (esclava probada: la del clock controller, no la GMU).
- **Criterio.** Éxito = 6/6 supervivencias al release (aunque HFI siga -110: eso es el mudo,
  no el release). Fracaso = racy igual → archivar la vía votos DEFINITIVAMENTE (ya serían
  D1+D2+C3) y pasar a C4/C5.
- **Orden.** DESPUÉS de C1 (hay que saber qué votar) y DESPUÉS de C2 (si C2 determiniza, C3
  es el fix natural; si C2 no cambia nada, C3 pierde prioridad frente a C4).

### C4. Voto de interconnect/BW mínimo — 1 flash kernel

- **Qué mide.** Si el CM3 liberado atasca el bus porque nadie votó ancho de banda para su
  fetch (ITCM/icache vía interconnect). `INTERCONNECT_QCOM_PALAWAN=y + RPMH=y + BCM_VOTER=y`
  están compilados: votar el path GPU→DRAM a mínimo operativo antes del release es 3 líneas
  por API (`icc_set_bw`), cero MMIO.
- **Coste.** 1 build+flash (combinable con C3 en UN solo kernel si C1 lo justifica: votar
  GX + BW juntos; si estabiliza, bisectar después. Para no quemar flashes, C3+C4 van juntos
  salvo que C2 apunte solo a uno).
- **Criterio.** Éxito = release estable n≥4. Fracaso = racy igual → archivar interconnect y
  pasar a C5/C6.

### C5. SMMU faults + `ARM_SMMU_QCOM_DEBUG` — 1 build, 0–1 flashes

- **Qué mide.** Si el freeze lo causa un fault de SMMU en el fetch del CM3 (SID5/GMU) o en
  el GBIF (L15 murió en `gpu_write(GBIF_HALT,0)` + readback: esclava GMU vs traducción
  SMMU son dos hipótesis distintas y un fault-log las dirime).
- **Base.** Hoy `ARM_SMMU=y + ARM_SMMU_QCOM=y` pero `ARM_SMMU_QCOM_DEBUG is not set`; el
  cmdline trae `arm-smmu.disable_bypass=0`. Los faults SMMU van a dmesg (y a pstore si P1
  vive).
- **Procedimiento 0-flash.** En boot vivo: `dmesg | grep -i "smmu.*fault\|Unhandled context
  fault\|fsr\|fsynr\|sid"`, `ls /sys/kernel/debug/iommu/`, estado de `3da0000.kgsl-smmu`.
  Si hay faults históricos, C5 ya pagó sin flash.
- **Procedimiento 1-flash.** Build con `CONFIG_ARM_SMMU_QCOM_DEBUG=y` (solo añade logs, no
  cambia el camino) + reflash L11 idéntico por lo demás. Repetir 4 opens.
- **Criterio.** Éxito = fault SMMU con SID/fsynr en la cola de ≥1 muerte → el fetch del CM3
  o el GBIF traducen mal → el fix es mapeo/stream (vía SMMU, no más hunks GMU). Fracaso = 4
  muertes sin un solo fault → SMMU exonerado como testigo (no como causa última: un stall
  síncrono puede no dejar fault).

### C6. Dueño del HW: hyp-assign / SCM / TZ — 0 lectura, 1 si hay que tocar

- **Qué mide.** Si la GPU/GMU sigue asignada a TZ/hyp cuando soltamos el CM3 (típico
  Qualcomm: el firmware zap/shmbridge y el `hyp_assign` deciden quién toca qué; soltar un
  CM3 cuya memoria aún es del hyp = fetch contra puerta cerrada = stall).
- **Base.** `QCOM_SCM=y + QCOM_TZMEM_MODE_SHMBRIDGE=y`; firmwares `gen71100_{gmu.bin,sqe.fw,
  zap.mbn}` presentes en rootfs (PRE-RENDER §1). El `zap.mbn` (shader analyzer protection?)
  se carga vía SCM al hyp.
- **Procedimiento 0-flash.** `dmesg | grep -i "scm\|tzmem\|zap\|hyp\|assign\|smmu.*attach"`,
  `ls /sys/firmware/qcom/`, `cat /sys/kernel/debug/qcom_scm/*` si existe. Pregunta concreta:
  ¿el `zap` se cargó OK en este boot? ¿hay `hyp_assign` en el camino del open? (grep en
  fuente `a6xx_gmu.c` + `adreno` en PC, 0 flashes).
- **Procedimiento 1-flash (solo si la lectura huele).** Log del estado SCM/hyp-assign justo
  antes del release (solo reads + prints a DRAM/P5, sin cambiar la secuencia).
- **Criterio.** Éxito = evidencia de assign pendiente/fallido correlacionado con muerte.
  Fracaso = assign OK siempre → archivar y pasar a D1.
- **Nota honesta.** Es la vía más larga y la más especulativa; se pone aquí porque el dueño
  la pidió explícitamente ("hyp-assign de la GPU, scm calls") y porque un ingeniero Qualcomm
  la miraría, pero va DESPUÉS de C1–C5 y D1.

### C7. Second-stage bootloader: qué deja ABL vivo — 0 flashes (solo lectura en PC + SSH)

- **Qué mide.** El estado heredado del arranque: qué GDSC/relojes/SMMU deja programados ABL
  antes de saltar a nuestro kernel (el `qcom,handoff-smrs=<0x1c00 0x02>` del DT stock
  demuestra que ABL deja el display VIVO en apps-smmu; ¿qué deja vivo/muerto para la GPU?).
- **Procedimiento.** En PC: `handoff-smrs`, `actlr`, `stream-id-range` del stockuke.dts
  (ya citados en R4 §2.1) + `dmesg` temprano del boot vivo (`S2CR`, `SMR`, `CB` al probe de
  `3da0000.kgsl-smmu`). En SSH: `cat /sys/kernel/debug/iommu/*/s2cr*` si existe. Sin flash.
- **Criterio.** Éxito = mapa "lo que ABL deja programado para GPU" archivado (es el input de
  D1: kexec hereda OTRO estado). Fracaso = nodos debug ausentes → queda como lectura de DT
  en PC (B1 lo cubre parcialmente).

---

## 4. Heterodoxas (D1–D6)

### D1. kexec desde Android stock — 0 flashes Linux, EL EXPERIMENTO BARATO QUE MÁS INFORMACIÓN DA

- **Qué mide.** Si el release L11 vive cuando el estado previo (GDSC, relojes, SMMU, TZ,
  firmwares, AOP/RSC) lo deja el stack VENDOR (Android stock boot) en vez de ABL + nuestro
  kernel mínimo. `CONFIG_KEXEC=y + KEXEC_FILE=y + CRASH_DUMP=y` YA están en k52L11 (líneas
  313–317): el kernel sabe ser imagen kexec.
- **Procedimiento (tablet intacta en el sentido que importa: slots Linux no se tocan).**
  1. Boot Android stock en el otro slot (los imgs stock están en `build/android/flash-b/`).
  2. Desde Android (root/adb): `kexec -l Image-L11 --dtb=… --cmdline=… && kexec -e`.
  3. Provocar opens, contar supervivencias con el MISMO criterio (gbif/pre-rst/HFI).
- **Coste.** 0 flashes en `boot_a` (el riesgo es boot a Android y volver; el rollback es
  reboot a slot A, artefactos intactos). El trabajo es PC: línea kexec correcta (dtb+cmdline;
  el `memmap`/`mem=2048M` del cmdline stock hay que revisarlo para kexec).
- **Criterio de éxito.** El release vive n≥3 bajo kexec → el código del release es BUENO y
  el asesino es el estado heredado (GDSC/SMMU/TZ que ABL+k52 dejan distinto que Android) →
  el fix es replicar el estado vendor, no parchear el release (reabre C-vías con diana).
  **Criterio de fracaso.** Muere igual de racy → el estado heredado NO es el factor (o
  Android y ABL dejan el mismo estado roto) → archivar D1, el bug viaja con el kernel.
- **Por qué va pronto en el orden.** Es el único experimento que cambia TODO el estado
  previo sin cambiar UNA línea del kernel. Un ingeniero Qualcomm lo llamaría "boot-instrumented
  state A/B". Si sale éxito, ahorra 5+ flashes de bisect.

### D2. Batería alta + gates ambientales fijos — 0 flashes, EN PARALELO CON P1

- **Qué mide.** Si el flake es eléctrico/térmico y no lógico. Datos del ledger: 3827→3819→
  3810→3826→3786→3782→3779 mV en #574–#580 (deriva -48 mV con 1 bump); slots 6:6→4:6→5:6.
  El GDSC GX y los OPP de la GPU son los primeros que sufren con V baja (el `GMU OPP table
  OK: 2 opps` de PRE-RENDER §3 + reguladores dummy = el voto real lo hace otro).
- **Procedimiento.** Cargar a ≥4000 mV (o con cargador puesto, anotando `batt` en ledger),
  fijar gates (misma hora, misma temp, lector armado igual), repetir 6 opens mismo L11.
- **Criterio.** Éxito = estabilización (≥5/6 iguales, vivan o mueran) → el flake tiene
  componente eléctrica → todos los flashes futuros se hacen con batería alta y se reabre
  C3 (votos) con diana. Fracaso = 0/6 racy igual con batería alta → exonerado eléctrico.
- **Coste.** 0 flashes. Hacer SIEMPRE en paralelo con cualquier otra vía (es gratis y el
  ledger ya mide mV en cada gate: solo hay que CONTROLARLO en vez de anotarlo).

### D3. Mesa/render por scp — 0 flashes kernel, BLOQUEADA hasta HFI

- **Estado (PRE-RENDER).** Rootfs sin mesa/vulkan/libdrm; tablet sin red → `pacman -U` por
  scp desde PC (`mesa, vulkan-freedreno, libdrm, vulkan-tools, mesa-utils`). Sin conectores
  KMS: el primer render es `vulkaninfo --summary` por renderD128 (off-screen), NUNCA kmscube.
- **Qué mide.** Si HFI+fw bastan para render aunque el display no exista (separa GPU de
  pantalla definitivamente).
- **Criterio.** Bloqueada hasta que un kernel dé HFI arriba (el mudo L11 #575 dio HFI -110:
  D3 espera). Preparar los 5 pkgs en PC (descarga+sha) pero NO instalar hasta HFI. Instalar
  antes quema tiempo y mete variables en el rootfs sin poder medir nada.

### D4. N-opens intra-boot como métrica estándar — 0 flashes (YA HECHO, convertir en protocolo)

- El #580 ya hizo 6 opens/3 boots → 6/6 muertes en puntos distintos. Convertirlo en
  PROTOCOLO: cada kernel futuro se juzga por defecto en 4 opens mismo boot antes de
  declararse (formato ledger: `gbif-ok? pre-rst? write-done? HFI?` por intento).
- **Criterio.** Un kernel "estable" = ≥3/4 opens con el MISMO desenlace. Un kernel "racy" =
  desenlaces distintos. Sin este protocolo, cada n=1 seguirá generando hunks fantasma.

### D5. Abrir card0 SIN release (límite inferior) — 0–1 flashes

- **Qué mide.** Si el flake vive en el release o antes (probe/resume/fw_start). El rescate
  `s3_stage=3 rescue=1 probe_hold=5000` (PRE-RENDER §3) ya permite GPU OFF con card0
  presente. Forzar `msm_open` que retorne ANTES de `a6xx_gmu_start` (1 build, camino
  existente L8-nopoll como plantilla) y repetir 4 opens: si ESO también es racy, el bug no
  es el release (es resume/fw_start/probe) y toda la §3 apunta mal.
- **Coste.** 1 build+flash (hermano de L9). **Criterio.** Estable-sin-release + racy-con-
  release = el release es el asesino (cierra CRITICA-L8 a nivel protocolo). Racy-sin-release
  = reabrir fw_start/resume (el bug está antes).

### D6. CPU affinity / thermal / OPP techo — 0–1 flashes

- **Qué mide.** Si la carrera es CPU-side (migración del `msm_open` entre clusters durante
  el release) o OPP-side (el 2º OPP de la tabla es inestable con V baja).
- **Procedimiento 0-flash.** `taskset -c 0-2` en el proceso que abre card0 (el cmdline ya
  trae `irqaffinity=0-2`: el vendor también pina); leer `scaling_cur_freq` +
  `/sys/class/thermal/*/temp` antes de cada open y anotar en ledger (correlación gratis).
- **Procedimiento 1-flash (solo si 0-flash correlaciona).** Techo al OPP bajo (solo el 1º de
  los 2) o `cpufreq.default_governor=performance` ya en cmdline → verificar que pina de
  verdad. **Criterio.** Correlación temp/freq↔muerte en ≥4 opens → diana térmica/OPP.
  Sin correlación → archivar.

---

## 5. Matriz coste / orden de ejecución (lo que se hace mañana)

Fase 0 (cero flashes, en este orden, en paralelo donde se pueda):
`P1 (pstore) + P5 (foto framebuffer) + P4-lectura (pureason/bark) + P6 (cronometrar
muerte) + C1 (foto power) + C7 (mapa ABL) + B1 (diff stock-vs-s250 en PC) + D2 (cargar
batería) + D4 (protocolo 4-opens) + D6-lectura (temp/freq por open)`.

Fase 1 (1 flash dtbo, kernel intacto): `B2 (s229-pelado) → B3 (stock+solo-GPU si B1 lo
justifica)`.

Fase 2 (1 flash cmdline/kernel, informativos): `C2 (sin muletas) → D5 (open-sin-release,
límite inferior)`.

Fase 3 (1–2 flashes, diana power): `C3+C4 (voto GX+BW juntos) → C5 (SMMU_DEBUG si hay
indicio) → P3-build (PSTORE_FTRACE solo si P1/P2 vacíos)`.

Fase 4 (heterodoxa grande): `D1 (kexec desde Android)` — puede adelantarse a Fase 2 si hay
slot/tiempo, porque no quema `boot_a` y su información reordena todo.

Fase 5 (último recurso): `L16-R (writes-ciegos, sin readbacks GBIF) + R0-batería-alta` con
protocolo D4; `D3 (Mesa)` solo cuando HFI esté arriba; `C6-escritura` solo con indicio SCM.

Criterio de parada: release estable n≥4 (Fase 0–3) o D1-éxito (reorienta a estado vendor).
Si tras Fase 3 + D1 el release sigue 0/N racy, el informe siguiente no es otro hunk: es
re-arquitectura del arranque GPU (deferred probe tras userspace + votos por API, o
portar `handoff-smrs` de R4 §2.1 al arm-smmu v2 para el SID de la GPU).

---

## 6. Lo que este plan NO pide (para que conste)

- Ningún hunk nuevo de registros GMU hasta que P1–P5 den PC del freeze.
- Ningún `gpu_write`/`gmu_read` nuevo en el camino del release (L14/L15: hasta los reads matan).
- Ningún `pr_flush` nuevo pre-release (RE-TIMING: el drenaje UART ya es sospechoso de mover
  la ventana; los testigos nuevos van a framebuffer/DRAM, no a UART).
- Ningún toque a apps-smmu por compatible (wedge 6/6 documentado).
- Ningún flash hoy (presupuesto agotado #580): Fase 0 es lectura + PC + cargador.

*Redactado solo-PC 10-oct-2026. Fuentes: ledger #550–#580, docs/historia/ESTADO-VIVO.md, CRITICA-L8,
RE-TIMING, RE-RS/RSALT, PRE-RENDER, R4 §2.1 (handoff-smrs), k52L11-bateria.config
(PSTORE/MTD/KEXEC/FTRACE/QCOM_WDT/GDSC/RPMH/ICC_PALAWAN/SMMU/SCM), cmdline-orig.txt
(mtdoops/block2mtd/hung_task/watchdog_thresh), mkdtbo-s250.py (cabecera + deltas s229).*
