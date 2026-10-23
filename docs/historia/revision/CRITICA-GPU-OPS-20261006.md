# CRITICA-GPU-OPS — revisión operativa de la fase GPU-CM3 (6-oct-2026, pre-#538)

> Revisor: crítico operativo. 100 % offline (tablet NO tocada). Fuentes: FLASH-LEDGER.md
> #532–#537 (hoy), `docs/historia/ESTADO-VIVO.md`, `docs/historia/revision/GPU-PORT-INV-20261006.md` §e (el plan G1–G4 que se
> critica), `BUILD-RECIPE-DORADA.md`, `docs/historia/revision/RUNBOOK-FLASH-FIX529-20261006.md` §E,
> `REGLA-UN-SOLO-LECTOR.md`, cmdline dorada 517 B extraída de
> `boot-ukek49-esd-plyoff.img` (offset 44), `k52-bateria.config`, y los ártefactos en disco
> medidos HOY:
>
> | Artefacto | sha256 | B | Rol |
> |---|---|---|---|
> | `build/bootimg/boot-uke-k55-cbwin.img` | `312b284eb8d07a2191cc539f21dcff1a0153c41b80d6cec8d39bfb51313f0bf7` | 100663296 | → boot_a (G1) |
> | `build/bootimg/s270-boot-dtbo-gpu-on.img` | `91d1e83161ecbfed333cc61b01c20e39cf741f329a85ae2376a2bfd1f0e715e8` | 609111 | → dtbo_a (G1) |
> | `build/bootimg/boot-uke-k52b2-bateria.img` | `18c749ea28a81aef1cc99a7824ea702cc6f739d9c89bcbd83ceaca6ef03e6aea` | 100663296 | rollback boot_a |
> | `build/bootimg/s269-boot-dtbo-touch.img` | `8893fe37d76df53a0634506c5f9cb57f9f1bbb4b9a92c0985cfeb96e6cbcd3e6` | 609219 | rollback dtbo_a |

**Veredicto en una frase**: el plan G1–G4 es viable PERO tal y como está escrito tiene un
punto único de fallo operativo — el re-arm del probe puede congelar la tablet en una muerte
seca sin panic (k53/k54) y el testbed queda muerto hasta que el dueño la fuerce; sin
"conversión de congelación en panic" (sysctls en runtime), streaming dual de logs y reglas
de parada, el N=5 no es una cuantificación, es una lotería con el testbed como apuesta.

---

## 1. El N=5 unbind/bind: cuantificar la raza sin tirar el testbed (RIESGO Nº1)

**El problema real.** El objetivo de G1 es medir la raza (dtcm STALE/OK por intento). Pero
el modo de fallo conocido NO es un panic: entre `S3-rst0` y el poll la máquina muere "EN
SECO, sin panic, sin oops, sin hung-task" (#535, K37→K44b), y k53/k54 REBOOT-LOOPEARON con
panic=10 sin caer a fastboot solas. **Un freeze durante el re-arm nº2 de 5 = tablet
inaccesible y experimento abortado a medias**, con el dueño dormido.

**La palanca que el plan no usa: convertir la muerte seca en panic recuperable.** La
cmdline dorada deja el sistema en modo "gracioso" (último token gana: `hung_task_panic=0`),
pero TODOS los detectores tienen sysctl en runtime, sin reflash y sin reboot
(`k52-bateria.config`: `SOFTLOCKUP_DETECTOR=y`+`INTR_STORM`, `RCU_STALL_COMMON=y`,
`PANIC_TIMEOUT=10`; `CONFIG_PANIC_ON_OOPS` no fijado → nodo escribible):

```sh
# ANTES de cada re-arm (y DESPUÉS revertir lo de hung_task):
sysctl -w kernel.panic_on_oops=1 kernel.softlockup_panic=1 kernel.panic_on_rcu_stall=1
sysctl -w kernel.hung_task_panic=1 kernel.hung_task_timeout_secs=20   # SOLO re-arms
```

Con esto, un hang de CPU/búsqueda en bus (softlockup/RCU-stall/hung-task) se convierte en
panic → `panic=10` (kernel `PANIC_TIMEOUT=10`) → reboot → **k55+s270 bootea de nuevo en
modo gracioso (probado #536) → SSH vuelve SOLO en ~2 min y el N=5 continúa**. La congelación
pasa de "testbed muerto hasta el dueño" a "contratiempo de 2 minutos autónomo".

**Advertencia importante (no repetir el error K52):** `hung_task_panic=1` NO debe quedar
armado en los boots de nuevos kernels. El fallo gracioso de k55 vive dentro de un poll del
FW-INIT que puede ser largo (gmu_poll_timeout 100 ms–100 s; la tarea duerme en D-state) →
un hung_task a 10-20 s dispararía un panic EN MEDIO del camino gracioso y lo convertiría en
reboot-loop. Regla: **hung_task solo se arma a mano, por SSH, justo antes del unbind, y se
desarma antes de cualquier reboot.** `softlockup_panic`/`panic_on_rcu_stall`/`panic_on_oops`
sí son seguros permanentes (k55 corrió hasta userspace sin ninguno: no hay CPU atascada en
el camino gracioso).

**Diseño del N=5 que propone esta crítica (orden por información/riesgo):**

1. **N=0 gratis: el boot mismo es el re-arm frío.** El veredicto dtcm de k55 en el boot
   (#536: STALE) ya es el intento 1 del dataset. Regístralo como tal.
2. **Capturas pasivas PRIMERO, cero riesgo** (esto lo pone el plan bien): dmesg completo,
   `clk_summary`, `regulator_summary`/GDSC, `interrupts`, todo por SSH ANTES de tocar nada.
3. **Streaming dual armado antes del primer unbind**: (a) `ssh … 'dmesg -w'` desde el PC a
   fichero del host (canal rápido, sobrevive a la muerte: lo impreso llegó), (b) el lector
   ACM en bucle cerrado (§5). Veredicto por intento leído del fichero del HOST, no de la
   tablet (la tablet puede morir en cualquier microsegundo).
4. **Re-arm por sysfs con el driver correcto**: el plan dice "unbind/bind del driver msm" —
   el probe del GMU vive en el driver **`adreno`** (`adreno_device.c:424-429`,
   `.name="adreno"`; el `msm` de `msm_drv.c:856` es el master DRM). Descubrir el nombre del
   device en caliente, no a mano:
   `ls /sys/bus/platform/drivers/adreno/` → link p.ej. `3d00000.qcom,kgsl-3d0`;
   `echo <dev> > …/adreno/unbind` → esperar líneas de teardown en el stream →
   `echo <dev> > …/adreno/bind`. Si el unbind devuelve EBUSY (component del master), plan B:
   unbind del master `msm` (teardown completo de componentes incl. GPU) + bind. Cada intento:
   registrar timestamp, veredicto dtcm (UKE-CM3DBG) y resultado (STALE/OK/freeze).
5. **Margen de recuperación por intento**: tras bind, esperar veredicto ≤ 3 min; si SSH muere,
   sondear retorno de SSH hasta 5 min (boot ~60-90 s + retries). Sin SSH a los 5 min y sin
   señal de panic en consola → muerte seca no convertida → §7 (dueño).

**¿Cuántos freezes tolera la sesión?** Con conversión de panic: los que hagan falta (cada
uno cuesta ~2 min y deja un apagón sucio, ver §3). Sin conversión o con muertes que ni el
softlockup ni RCU-pillan (bus totalmente parado en IRQ context: el `INTR_STORM` puede no
verlo): **límite duro = 1 freeze duro por sesión**; al segundo, STOP de re-arms. Regla de
parada adicional: 2 freezes CONSECUTIVOS en el mismo paso del ciclo (p. ej. siempre en
S3-rst0 tras re-probe) → dejar de re-armar (la raza ya está caracterizada: 100 % repro)
y pasar a G2/G3 con la evidencia recogida.

**Protocolo de recuperación para el dueño (pegar al ledger; ejecución SIEMPRE suya, watchers
PROHIBIDOS #535):**
1. Forzar fastboot: mantener vol− + conectar USB (o vol− + power 10 s si está pegado).
2. `fastboot devices` → debe listar SOLO `SERIE0001`.
3. `fastboot flash boot_a build/bootimg/boot-uke-k52b2-bateria.img` (esperar OKAY, ~1-5 s;
   par bueno estable #537).
4. `fastboot flash dtbo_a build/bootimg/s269-boot-dtbo-touch.img` (OKAY <1 s).
5. `fastboot reboot` — OJO quirk #537.5: si vuelve a fastboot sin intentar arrancar
   (retry-count alto sin consumo), repetir `fastboot reboot`.
6. Verificar: SSH en `192.168.42.129` <90 s → `uname -r`, batería `Charging`, uke-adsp active.
   (Referencia completa: `docs/historia/revision/RUNBOOK-FLASH-FIX529-20261006.md` §E + `ROLLBACK.md`.)

---

## 2. dd de boot_a/dtbo_a por SSH: verificación del argumento y escritura blindada

**El argumento está bien elegido.** Verificado en el rootfs v8/staging: el fstab solo monta
`by-partlabel/userdata` como raíz; `boot_a`/`dtbo_a` NO están montados ni en uso (lo avalan
los 3 dd de hoy, #534/#537). El riesgo real NO es escribir sobre la partición en uso, es
**escribir a medias + reboot**.

**Lo que falta al protocolo actual (checksum previo ya existe), en orden:**

1. **Nunca `scp | dd`.** El dd debe leer un fichero LOCAL de la tablet
   (`scp → ssh 'sha256sum' → ssh 'dd if=/root/img of=… conv=fsync'`). Si el enlace USB
   muere a mitad, se pierde el scp (repetible) pero el dd es local→local y o termina o
   muere entero — nunca queda colgado DEL enlace.
2. **dd desprendido y con timeout**: `ssh … 'timeout 300 dd if=… of=/dev/disk/by-partlabel/boot_a bs=4M conv=fsync; sync'`.
   Esperado: boot 100 MB ≈ 2-4 min por NCM; **EXIT=124 = enlace wedged a mitad → NO
   reboot bajo ningún concepto** → curar el enlace (§4) → REPETIR el dd completo → verificar.
   El dd es idempotente (misma imagen completa).
3. **Verificación post-dd POR RELECTURA de la partición** (el eslabón que falta hoy):
   - boot_a: `ssh … 'dd if=/dev/disk/by-partlabel/boot_a bs=4M count=24 | sha256sum'`
     (24×4 MiB = 100663296 B exactos = tamaño de la imagen Y de la partición) == `312b284e…`.
   - dtbo_a: la imagen (609111 B) es ≤ partición (25165824 B); la relectura compara solo lo
     escrito: `ssh … 'head -c 609111 /dev/disk/by-partlabel/dtbo_a | sha256sum'` == `91d1e831…`.
4. **`sync` doble y tamaño objetivo**: `conv=fsync` + `sync` final (bloques+cola UFS) y
   antes del dd, `blockdev --getsize64` de cada target (boot_a DEBE dar 100663296; dtbo_a
   ≥ tamaño de imagen) — mismo gate que ya hace el script fastboot, replicado para dd.
5. **Regla de oro**: `sha relectura OK ⇒ y solo ⇒ reboot`. Un boot_a sin verificar + reboot
   = boot-loop sin fastboot (k53/k54: NO cae solo) = dueño.
6. **Separación de build dir** (lección #534: el O= compartido pisó el Image.gz k52b con el
   k52c): O= por kernel o snapshot inmediato del Image.gz + sha pre-registrado en la fila
   del ledger ANTES del scp.

---

## 3. Userdata: blindaje (cada reflash revierte los fixes en vivo — #537.4)

1. **Ningún comando de esta fase menciona `userdata`.** En cada fila de pre-registro, línea
   explícita: `objetivos: boot_a, dtbo_a — userdata NO`. Si se envuelve el dd en un script,
   guard: `case "$TARGET" in *userdata*) die;; esac`.
2. **Los freezes son el enemigo indirecto del userdata**: cada uno es un apagón sucio del
   ext4; el v8 ya llevaba ~50 cuando sshd dio REFUSED (#536). El userdata reflasheado anoche
   está limpio — hay que MANTENERLO limpio. Cada sesión: `dmesg | grep -i 'EXT4-fs error'`
   (debe dar 0) y, si sshd vuelve a dar REFUSED o aparecen errores ext4 → **fin de
   escrituras del día** (un fs dañado solo se arregla con el reflash que NO queremos hacer).
3. **Escribir lo mínimo en el rootfs**: logs a ficheros del HOST (dmesg -w, consola), no de
   la tablet. La única escritura recomendada en el rootfs es el sysctl de panic (§7) y es
   pequeña y de una vez.
4. **Regla #537 sin excepciones**: todo fix en vivo (sysctl.d, script parcheado, .ko) →
   también a `build/rootfs/staging/` en el mismo minuto en que se aplica. (El staging ya
   lleva `usr/local/share/uke/mods/{pmic_glink,qcom_battmgr}.ko` — verificado hoy.)

---

## 4. USB wedge (puerto 3-3): detección, curación y CUÁNDO toggle

1. **Nunca preventivo**: cada toggle authorized es una re-enumeración (combustible del
   wedge, #537) y mata momentáneamente el SSH (la red NCM va por ese USB). Toggle SOLO con
   síntoma.
2. **Detección barata antes de cada ciclo scp/dd** (bulk stalla, control OK — #537.3):
   `timeout 10 dd if=/dev/zero bs=1M count=4 | ssh root@192.168.42.129 'dd of=/dev/null bs=1M'`
   → <5 s = enlace sano; timeout = wedge → curar.
3. **Curación** (probada 2× hoy): `echo 0 > /sys/bus/usb/devices/3-3/authorized; sleep 3;
   echo 1 > …/authorized`; esperar re-enum (~5 s) y reconectar SSH. Si había un dd corriendo,
   está abortado a medias → repetir dd + relectura (§2.2) antes de cualquier reboot.
4. **Protección estructural del dd**: al ser local→local (§2.1), el peor caso del wedge a
   mitad es un dd muerto por timeout, no una escritura corrupta silenciosa; la relectura
   sha lo certifica.

---

## 5. Consola y pstore: qué se puede capturar de un boot muerto

**Estado verificado hoy (corregir expectativas del plan):**
- **ramoops NO existe en nuestro DT actual**: el nodo fue ELIMINADO
  (`xiaomi-uke.dts:74-76`, ramoops@9f000000 solapaba adspslpi@9d400000). `CONFIG_PSTORE_RAM=y`
  está pero no registra nada → `/sys/fs/pstore` vacío. La referencia de
  `uke-pstore-read.sh` (ramoops_region 0xa7000000) era del DT vendor-reconstruido de 30-sep:
  NO aplica al testbed actual.
- **mtdoops SÍ es montable con lo que ya hay**: `CONFIG_MTD_OOPS=y` + `CONFIG_MTD_BLOCK2MTD=y`
  + `CONFIG_MTD_BLOCK=y`, y la partición `oops` (2 MiB) existe en la tabla GPT (Android la
  usa con este mismo esquema: cmdline Android = `block2mtd.block2mtd=/dev/block/by-name/oops,2097152 mtdoops…`,
  `EVIDENCIA-PANTALLA-28sep.md:300`). OJO de timing: el parseo del parámetro block2mtd corre
  en initcall ANTES de que exista /dev — **más fiable armarlo en runtime una vez con SSH**:
  `echo '/dev/disk/by-partlabel/oops,2097152' > /sys/module/block2mtd/parameters/block2mtd`
  y `echo mtd0 > /sys/module/mtdoops/parameters/mtddev`; lectura del boot muerto en el
  siguiente boot: `dd if=/dev/disk/by-partlabel/oops bs=4096 | strings | tail -50` (la
  partición es flash cruda: sobrevive a reboot y apagón; lectura sin block2mtd).
- **Límite duro de ambos**: solo escriben en panic/oops. La muerte seca de S3-rst0 NO escribe
  nada — ni pstore ni mtdoops. Para la muerte seca lo único que funciona es (a) streaming
  (§1.3, probado: la ventana 4.118-4.212 s se midió DESDE la consola capturada) o (b) la
  conversión a panic de §1 (que además alimenta mtdoops).

**Consola ACM:**
- NO bajar/subir loglevel de la consola: a 115200 baudios (~11,5 KB/s) el ruido retrasa y
  trunca la ventana crítica; `loglevel=4` ya deja pasar los pr_err de la escalera
  (probado K37→k55). El log completo va por `dmesg -w` vía SSH (sin límite de baudios).
- **El lector debe ser el bucle cerrado SIN sleep en la rama de lectura** (el `sleep 1` del
  sustituto improvisado #537.6 se come hasta ~1 s por re-enumeración, justo la ventana
  0,5-4,1 s):
  `while :; do if [ -e /dev/ttyACM0 ]; then cat /dev/ttyACM0 >> /var/tmp/uke-c3.log || true; else sleep 0.05; fi; done`
  (hueco de re-apertura en milisegundos; UN solo lector — REGLA-UN-SOLO-LECTOR.md; armarlo
  ANTES del reboot y comprobar que sobrevive a la re-enum). El reopen del lector2 sigue
  roto: no usar lector2 para esto.
- `printk.always_kmsg_dump=0` de la dorada es correcto para el boot; los dumpers kmsg
  (mtdoops) disparan igualmente en panic — no tocar.

**Respuesta directa a la pregunta**: sí, se puede leer el "oops" de un boot muerto DESDE
Arch en el siguiente boot (dd de la partición oops, arriba) PERO solo si hubo panic/oops;
para el freeze seco la cobertura es: consola ACM (hasta el microsegundo de la muerte) +
dmesg -w por SSH (hasta el último printk) + conversión de panic (§1) que además deja
volcado+registro en mtdoops para leer después. Ramoops-via-DT queda APARCADO: exigiría
auditoría de PA libre tras el solape ya mordido (A1) — no improvisarlo en una fase con la
tablet iterando cada 2 min.

---

## 6. Sin dueño: techo de la sesión autónoma y parada segura

**Se puede hacer SIN el dueño (dd+reboot por SSH funcionan mientras la máquina no muera):**
- G1 completo tal como se rediseña en §1 (un solo dd de un par de boot YA PROBADO + re-arms
  runtime con conversión de panic).
- G2 entero (análisis offline de capturas vs `build/android/uke-snapshot-r15.sh` — cero
  tablet).
- Builds, repacks, gates, pre-registros de G3 (todo offline en el PC).
- Re-dd del mismo par k55+s270 o del rollback k52b2+s269 (ambos probados).

**NO se puede sin el dueño:**
- **El primer boot de CUALQUIER kernel nuevo (G3)**. k53/k54 congelaron EN BOOT con GPU-on
  y k55 no (la diferencia es 1 commit de sonda); el comportamiento de arranque de un kernel
  nuevo es impredecible → un boot-freeze = tablet hasta el dueño. Regla: G3 solo con el
  dueño localizado y avisado. (Los sysctls de §1 ayudan pero NO cubren el caso k53: si el
  hang es previo a userspace, nadie escribe el sysctl — quedan los valores de /etc/sysctl.d,
  ver abajo.)
- Caída a fastboot sin dueño (no ocurre sola: k53/k54).

**Mejora de bajo costo y persistente (recomendada, se aplica POR SSH al principio de la
sesión y también al staging — regla #537)**: `/etc/sysctl.d/99-uke-panic.conf` con
```
kernel.panic_on_oops = 1
kernel.softlockup_panic = 1
kernel.panic_on_rcu_stall = 1
```
(NUNCA `hung_task_panic` aquí — rompería el camino gracioso de k55, §1). Esto protege
TAMBIÉN los boots de kernels futuros contra las muertes tipo "CPU atascada" y convierte
casi cualquier congelación en panic→dump→reboot autónomo. Reversible con `rm`.

**Parada segura (fin de sesión o presupuesto agotado), en orden:**
1. Desarmar hung_task (si se armó) y verificar `sysctl kernel.hung_task_panic` = 0.
2. Último `sync`; copiar al PC los ficheros de evidencia que vivan en la tablet.
3. Elegir estado de la tablet: si el N=5 cerró sin freeze duro → **dejar k55+s270** (es la
   base de trabajo de G2/G3: GPU-on gracioso). Si hubo cualquier freeze duro, error ext4 o
   sshd REFUSED → **dejar k52b2+s269** (re-dd + relectura + reboot + verificación).
4. Verificación final: SSH <90 s, batería `Charging`, uke-adsp active, `dmesg` sin EXT4-fs
   error. Fila de cierre en el ledger con los 4 shas de la tabla superior.

---

## 7. Presupuesto y orden (decisiones por hora)

Tiempos medidos/estimados: build incremental 3-10 min (full ~14), repack+gates 1-2,
scp 100 MB+sha 2-4, dd+relectura 3-5, reboot+SSH 1,5-2, re-arm runtime 2-6 (con recovery).

| Fase | Coste | Rendimiento esperado |
|---|---|---|
| G1 completo (dd×2 + boot + capturas pasivas + N=5 re-arms) | ~50-60 min | caracteriza la raza (el dato que G3 necesita) |
| G2 (offline, en paralelo a builds) | 0 min de tablet | compara energía/reloj con Android |
| G3 por experimento | 12-25 min | **máximo 5 kernels/sesión de 2-3 h**; para en decisión, no en cansancio |

**Orden de G3 por coste marginal** (primero lo que no requiere rebuild):
1. **Variantes de cmdline** (repack-only: C2 sin `msm.uke_gmu_shared=0`; `msm.uke_smmu_dump=1`
   si hiciera falta) — ~5 min por dato, cero build.
2. **Kernels de 1 línea** (C4: ACTLR 0x32b del CB5 en arm-smmu-qcom).
3. **Multi-fichero** (C5: migas del poll FW_INIT / qmp acd).
Interleaving: mientras compila el kernel n+1, digerir offline los datos del n y actualizar G2.

---

## 8. Correcciones puntuales al plan G1-G4

- **G1**: reordenar dentro de la fase — primero el dd (par probado), luego capturas pasivas,
  luego streaming dual, luego sysctls de panic, y SOLO ENTONCES el N=5. Driver objetivo:
  `adreno` (no `msm`). El boot frío cuenta como intento 1. Reglas de parada de §1. Añadir
  armado de mtdoops (runtime) como seguro de panics.
- **G2**: sin cambios (offline). Añadir como entrada la captura Arch de `regulator_summary`
  + GDSC que G1 ya produce, contra `uke-snapshot-r15` de Android.
- **G3**: gate duro "dueño avisado" por kernel nuevo (§6); O= separado o snapshot inmediato
  del Image.gz con sha pre-registrado (lección #534); continuar el orden de coste de §7.
- **G4**: cuando S4-pollOK aparezca, NO encadenar nada (ni dd, ni re-arm) hasta un soak de
  ≥10 min de uptime con sshd OK y sin EXT4 errors — un GPU vivo abre modos de congelación
  nuevos justo cuando el testbed está más cerca del objetivo.

## 9. Pre-registro mínimo para la fila #538 (pegar al ledger ANTES del dd)

| # | Escritura | Artefacto (sha) | Gate de éxito | Rollback |
|---|---|---|---|---|
| W1 | dd boot_a por SSH | `boot-uke-k55-cbwin.img` `312b284e…` | relectura 100663296 B == sha; boot gracioso, SSH <90 s | dd `boot-uke-k52b2-bateria.img` `18c749ea…` |
| W2 | dd dtbo_a por SSH | `s270-boot-dtbo-gpu-on.img` `91d1e831…` | relectura 609111 B == sha | dd `s269-boot-dtbo-touch.img` `8893fe37…` |
| — | sysctl.d + mtdoops runtime | no es escritura de partición | nodos presentes tras aplicar | rm / valores por defecto |

Los re-arms del N=5 NO son escrituras de partición: no consumen fila de pre-registro; sí
consumen líneas de veredicto (una por intento, apendada en el HOST en tiempo real).
