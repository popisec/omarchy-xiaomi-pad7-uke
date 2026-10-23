# INV-PERSIST #544 — Por qué el k61 no dejó rastro: anatomía del canal de persistencia y rediseño a prueba de freeze

**Fecha**: 8-oct-2026. **Alcance**: 0 % tablet (estable en Arch con SSH). 100 % offline sobre el
árbol `build/kernel-pokes/k52-tree`, la config `kernel-config/k52-bateria.config`, el DT base
descompilado (`/var/tmp/base.dts`), los dtbo s272/s273, los bootimg k57/k61 y la evidencia
archivada en `build/evidencia/` y `build/gates/`.

**Pregunta que motiva esto**: el boot k61 (`msm.uke_s3_stage=2 msm.uke_rescue=1`, GPU-on) murió
congelado y NO dejó nada: `/sys/fs/pstore` vacío, sda30 sin `UKE61RSC`, y ni una línea `UKE-K61`
en el dmesg del boot siguiente.

---

## 1. Veredicto en una frase

**El ramoops de 0xa7000000 registró, capturó todo el log del k61 en DRAM… y murió con la DRAM:
la recuperación del freeze es un power-cycle físico (sin watchdog activo no hay reset caliente),
y el power-cycle borra la RAM física.** El único canal que sobrevive a un power-cycle —la FLASH
(sda30)— estaba cableado al canal redundante `uke_rescue`, pero pierde la carrera contra la
enumeración de UFS (~150 ms tarde) y por eso tampoco dejó canario. La persistencia del k61 no
falló en un eslabón: falló el **encadenado** de cuatro, y el principal es físico, no software.

---

## 2. Inventario de mecanismos de persistencia EN ESTE KERNEL (k52-tree)

| # | Mecanismo | Medio | ¿Sobrevive a power-cycle? | Estado verificado |
|---|-----------|-------|---------------------------|-------------------|
| 1 | **pstore/ramoops console** (`fs/pstore/ram.c` + `fs/pstore/platform.c`) | DRAM @0xa7000000, 2 MiB console + 2 MiB pmsg | **NO** | Registrado en postcore a **0,039 s** (medido en k49); escritura **síncrona** dentro de cada printk |
| 2 | **uke-prevlog** (`drivers/soc/qcom/uke-prevlog.c`) | Lee crudo la zona 1 del boot anterior y la imprime (`X9PREV`) + LAST-POKE | NO (es lector, no escritor) | **ROTO: comprueba la firma equivocada** (ver §3.4) |
| 3 | **uke_rescue (k61)** (`a6xx_gmu.c`) | **FLASH**, último bloque 4 KiB de sda30 | **SÍ** | Correcto en diseño; **pierde la carrera de timing** (ver §3.5) |
| 4 | **uke-panic-fb** (`drivers/soc/qcom/uke-panic-fb.c`) | FB de la splash ABL @0xE3940000 (`kmsg_dumper`) | NO (y ABL la repinta) | Solo dispara en panic/kmsg_dump; en freeze duro **no se invoca**; volátil |
| 5 | **uke_poke / uke_lastpoke** (`linux/uke-poke.h`) | FB @0xE3940000 | NO | Ojos en vivo; al reset lo pierde todo |
| 6 | **mtdoops + block2mtd** | Flash vía block device como MTD | SÍ | **INERTE**: `CONFIG_MTD_OOPS=y` está en k49..k52 (la premisa de que k52 lo perdió es **falsa**), pero el cmdline no lleva `block2mtd=` ni `mtdoops.mtddev=` → no hay MTD → el driver nunca engancha. Además mtdoops es un `kmsg_dump`-only: **tampoco dispararía en un freeze** |

### 2.1 Config (Q5) — `kernel-config/k52-bateria.config`

| Símbolo | Valor | Línea |
|---|---|---|
| `CONFIG_PSTORE` | **y** | 8500 |
| `CONFIG_PSTORE_CONSOLE` | **y** | 8503 |
| `CONFIG_PSTORE_PMSG` | **y** | 8504 |
| `CONFIG_PSTORE_RAM` (ramoops) | **y** | 8506 |
| `CONFIG_PSTORE_BLK` | no | 8507 |
| `CONFIG_MTD_OOPS` | **y** (también en k49/k50/k51: la config **no lo perdió**) | 2101 |
| `CONFIG_MTD_BLOCK2MTD` | y (inerte sin cmdline) | 2158 |
| `CONFIG_QCOM_WDT` | **y** (nadie lo abre: ver §3.2) | 4161 |
| `CONFIG_WATCHDOG_HANDLE_BOOT_ENABLED` | y (`OPEN_TIMEOUT=0`: mata el WDT heredado del bootloader) | 4136-4137 |
| `CONFIG_DEVTMPFS_MOUNT` | y (los nodos `/dev/sdX` existen en cuanto UFS escanea) | 1900 |

### 2.2 DT y cmdline (Q5)

- **DT base** (`/var/tmp/base.dts:109-116`): el nodo **viene del DT base, no del cmdline**:
  `ramoops_mem: ramoops_region { compatible="ramoops"; reg=<0x00 0xa7000000 0x00 0x400000>;
  console-size=<0x200000>; pmsg-size=<0x200000>; mem-type=<0x02>; }` (sin `no-map` en el base).
  Los dtbo s272 y s273 (`fragment@128`, `target-path="/reserved-memory/ramoops_region"`)
  re-fijan console/pmsg-size y **añaden `no-map`**. Medido en k49:
  `OF: reserved mem: 0x00000000a7000000..0x00000000a73fffff (4096 KiB) nomap non-reusable ramoops_region`.
  OJO: en ESTE árbol `mem-type=2` = **MEMREMAP_WT** (`include/linux/io.h:148-155`: WB=1, WT=2,
  WC=4), no el WC del upstream clásico; funciona igualmente, pero la afirmación del DISENO-K61
  §3.3 ("MEM_TYPE_NORMAL/PAGE_KERNEL") es imprecisa.
- **Cmdline k61** (extraído de `bootimg/boot-uke-k61-staged.img`, offset 44, 1536 B): la dorada
  (`mem=2048M rdinit=/ukeinit panic=10 memmap=… console=tty0 … console=ttyGS0,115200 …`) +
  `msm.uke_s3_stage=2 msm.uke_rescue=1`. **No** hay `ramoops=` (no hace falta: lo pone el DT),
  **no** hay `console=ramoops` (no existe como consola de cmdline: la consola pstore se registra
  sola), **no** hay `block2mtd=` ni `mtdoops.mtddev=`, y `hung_task_panic=0` aparece AL FINAL,
  anulando el `hung_task_panic=1` de arriba (el último valor gana: **los hung-task no panicarán**).

### 2.3 Cadena ramoops verificada eslabón a eslabón (código k52-tree)

1. `ramoops_init` corre en **postcore** (`fs/pstore/ram.c:988`) → registro a **0,039 s** (medido
   en k49: `pstore: Registered ramoops as persistent store backend` + `ramoops: using
   0x400000@0xa7000000, ecc: 0` + `printk: legacy console [ramoops-1] enabled`).
2. La consola pstore escribe **sincrónicamente dentro del printk** en el buffer persistente
   (`fs/pstore/platform.c:394-407`: `pstore_console_write` → `psinfo->write` → `persistent_ram_write`),
   con `CON_PRINTBUFFER|CON_ANYTIME` (replay del log previo al registrarse).
3. La zona console se crea con **sig param 0** (`ram.c:794-795`) ⇒ la firma almacenada en la cabecera
   del buffer es `0 ^ PERSISTENT_RAM_SIG` con `PERSISTENT_RAM_SIG = 0x43474244` de ESTE kernel
   (`fs/pstore/ram_core.c:39`) ⇒ **0x43474244**. Al sondear hace `persistent_ram_save_old()` +
   `zap` (PRZ_FLAG_ZAP_OLD, `ram.c:601-602`), así que el contenido del boot N lo lee el boot N+1
   y la zona queda limpia para el boot N+1.
4. Los ficheros `console-ramoops-0`/`pmsg-ramoops-0` solo aparecen en `/sys/fs/pstore` si (a) el
   sondeo del boot N+1 encontró la firma válida del boot N **y** (b) alguien **monta pstore**.

---

## 3. Por qué el k61 no dejó NADA — los cuatro eslabones rotos

### 3.1 Eslabón principal (FÍSICO): el power-cycle de recuperación borra la DRAM

- El freeze del dominio GMU **no se auto-recupera**: ni WDT (el fork no abre `/dev/watchdog0` y
  `WATCHDOG_HANDLE_BOOT_ENABLED` con `OPEN_TIMEOUT=0` apaga el heredado del bootloader), ni
  hung_task panic (anulado en el cmdline), ni soft-lockup panic en un wedge de bus. Lo dice la
  propia evidencia: `evidencia/wedge-cm3-20261001-escalera.txt` — *"El wedge NO se auto-recupera
  … necesita power-cycle fisico"* — y el init k12 — *"el fork desactiva el watchdog ⇒ un panic =
  cuelgo eterno hasta Power fisico"*.
- Un power-cycle **pierde la retención de las celdas DRAM**: TODO lo que el ramoops console
  escribió (y había escrito MUCHO: desde 0,039 s hasta el freeze ~4 s, todas las líneas
  `UKE-K61:`/`UKE-*` estaban en 0xa7000000) se evapora. El framebuffer (canal 4/5) y `/dev/pmsg0`
  mueren igual.
- Esto **no es nuevo ni del k61**: el init de la era k12 ya lo daba por hecho —
  `build/init/uke-k12-initramfs.cpio.gz` (ukeinit s172, cabecera): *"el canal ramoops DDR esta
  muerto (#250), el volcado ahora sale por el ACM"*.

### 3.2 Evidencia de que el canal ramoops NUNCA ha entregado un byte (en toda la vida del proyecto)

`X9COLD` (el lector de pstore del initramfs de la era k12/k22: `mount -t pstore` + contar
`console-ramoops-*`/`dmesg-ramoops-*`) dijo **siempre "0 ficheros"**:

| Boot | Evidencia | Resultado |
|---|---|---|
| k2 (migas) | `build/gates/k2-migas-log.txt:1494` | 0 ficheros |
| k4 | `build/gates/k4-migas-log.txt:1494` | 0 ficheros |
| k10 (bind exitoso) | `build/gates/k10-bind-exitoso-dmesg.log:1497` | 0 ficheros |
| Arch 28-sep | `build/evidencia/2026-09-28/dmesg-arch.txt:1469` | 0 ficheros |
| **t1-k49 (el mejor)** | `build/evidencia/t1-k49-v8/dmesg-t1.txt:1543` | 0 ficheros — **pese a que ese mismo dmesg muestra ramoops registrado y consola habilitada a 0,039 s** |

Y en el **Android stock** tampoco ha aparecido nunca: `ls /sys/fs/pstore` de la captura completa
de android-full-gaps está **vacío** (`extracted-gaps/h11-h14-misc/pstore-ls.txt`, `total 0`).
Cada boot leía el boot anterior; todos dijeron "el anterior no dejó nada". Conclusión medida:
**no hay ni un solo caso observado de entrega ramoops boot→boot en esta tablet**, ni en el fork
ni en stock. La hipótesis del DISENO-K61 §3.3 (*"YA existe, verificado en este árbol"*) es
cierta para el **registro** (k49 lo demuestra) pero **falsa para la entrega end-to-end**, que
nunca se ha presenciado.

### 3.3 ¿El reset caliente preserva la DRAM? (Q3)

- **Reset caliente (WDT bark, sysrq-b, reboot -f): sí por diseño** — es la base de ramoops en
  Qualcomm (el propio DT del vendor reserva la zona para eso; XBL reconstruye el controlador DDR
  preservando contenido en warm boot). **Pero en esta tablet NO hay evidencia local directa**:
  como ningún boot entregó nunca, el camino warm queda sin demostrar aquí.
- **Power-cycle (lo que hacemos tras cada freeze): NO**, físicamente imposible.
- Dato adicional del t1-k49: la zona despierta con contenido **ajeno**, no con ceros ni con la
  firma del boot anterior: `X9PREV: zona no valida (PREV:sig=140039da sz=0
  b0=da39001400000000)`. Esos bytes (`0x140039da` = opcode ARM64 de branch incondicional) sugieren
  que XBL/ABL/UEFI **escribe/reutiliza** 0xa7000000 en el arranque siguiente — segunda razón (además
  del power-cycle) por la que la zona puede llegar inválida incluso tras un reset caliente. Hay que
  medirlo (experimento del §5.4) antes de volver a fiar la depuración a este canal.

### 3.4 Eslabón de software 1: uke-prevlog comprueba la firma equivocada

`uke-prevlog.c:19` — `#define PREV_SIG 0x43474206UL /* PERSISTENT_RAM_SIG */` — es la firma del
**upstream clásico**. ESTE kernel usa `PERSISTENT_RAM_SIG = 0x43474244`
(`fs/pstore/ram_core.c:39`) y crea la zona console con sig param 0 (`ram.c:794`) ⇒ la cabecera
real vale **0x43474244**. Aunque el ramoops sobreviviera, uke-prevlog la descartaría como
"zona no valida" y no imprimiría NADA. (Su timing es correcto: corre en postcore a 0,0387 s,
ANTES del zap de ramoops_init a 0,0395 s — medido en k49. Y compila:
`drivers/soc/qcom/Makefile:44 obj-$(CONFIG_ARCH_QCOM) += uke-prevlog.o`.)

### 3.5 Eslabón de software 2: la carrera del canal sda30 (uke_rescue)

`uke_rescue=1` estaba en el cmdline y el código es correcto (magic + CRC, último bloque 4 KiB,
O_DSYNC, un write por hito). Falla por **timing**: los hitos del k61 disparan
`filp_open("/dev/sda30")` cuando ese nodo **aún no existe**:

- GPU-on armado a **~4,03 s** (mechanismo de armado diferido; t1-k49: `UKE-K11: armando probe a
  3s` → `armado rc=0 a 4s`) → `ENV-END` y `STAGE2-ARM` intentan escribir ~4,0-4,05 s.
- UFS escanea y publica `sda` (y `sda30` con él) a **~4,15 s** (t1-k49: `sd 0:0:0:0: [sda]`).
- Resultado: `filp_open` → ENOENT → `pr_err_once("UKE-K61: rescue sda30 no disponible")` →
  los hitos tempranos (los ÚNICOS que sobreviven a un freeze de 200 ms) no escriben nada. La
  ventana stage2 (4,03→4,23 s) muere ANTES o justo cuando `sda30` aparece; los hitos posteriores
  (`STAGE-SAMPLE`/`STAGE-REARM`) jamás llegan.
- La ironía: la FLASH **sí habría sobrevivido al power-cycle**. El canal correcto perdió por
  ~150 ms. (Y si el k61 murió aún antes — durante ENV, antes de `ENV-END` — ni eso: no hay ningún
  hito de rescate previo a ENV-END.)

### 3.6 Eslabón de software 3: el initramfs actual ya no lee pstore

El `ukeinit-arch` actual (7-oct, idéntico byte a byte al `/ukeinit` del cpio
`uke-k34-fw-initramfs.cpio.gz` usado en la familia k57/k61) **no monta pstore, no tiene X9COLD ni
el volcador de 15 s a sda30** que tenía el init s172/k12 (`X9COLD` líneas 80-92; `S136: volcador
de log persistente lanzado (rescue/sda30 cada 15 s)`). Es decir: incluso si el ramoops hubiera
sobrevivido y uke-prevlog hubiera hablado, el boot de diagnóstico no habría volcado nada a flash
desde userspace.

---

## 4. Respuesta directa a las preguntas

1. **Mecanismos**: ver tabla §2. Ramoops configurado por **DT base** (0xa7000000, 4 MiB: 2 console
   + 2 pmsg, `no-map` vía dtbo, `mem-type=2`=WT) — nada de cmdline. uke-prevlog = lector temprano
   del boot anterior (ROTO por firma). uke_rescue = flash sda30 (correcto, pierde timing).
   uke-panic-fb/uke_poke = FB volátil, solo eyes-on/panic. mtdoops/block2mtd = config presente
   (no se perdió en k52), inerte sin cmdline y además kmsg_dump-only (no sirve para freeze).
2. **k61**: ramoops SÍ registró (mismo config+DT que k49, que lo demuestra a 0,039 s) y la consola
   pstore volcó síncronamente TODO el log hasta el freeze en 0xa7000000. X9COLD vio 0 porque
   X9COLD solo vería algo si la DRAM hubiera sobrevivido **y** porque además el initramfs actual
   ya ni monta pstore. Cada eslabón, verificado en §3.
3. **¿El freeze puede destruir la RAM del ramoops?** El freeze en sí no la borra; **la
   recuperación sí**: sin WDT activo el único camino es el power-cycle físico, que destruye la
   retención de las celdas. Reset caliente lo preservaría (por diseño QCOM), pero aquí nunca se
   ha demostrado end-to-end — y la zona despierta con bytes ajenos (`sig=140039da`), lo que
   sugiere que además el bootloader pisa 0xa7000000 en el arranque siguiente. Evidencia
   histórica: cinco boots con X9COLD=0, X9PREV inválido y hasta Android stock con pstore vacío.
4. **Rediseño**: §5.
5. **Config/cmdline**: ver §2.1 y §2.2. `PSTORE_CONSOLE=y`, `PSTORE_RAM=y`, `PSTORE_PMSG=y`,
   `MTD_OOPS=y` (presente en k49..k52 — premisa falsa), cmdline dorada sin `ramoops=`/`block2mtd=`/
   `console=ramoops` (correcto para ramoops-DT; el bloque MTD está muerto de cmdline).

---

## 5. Rediseño: canal de captura a prueba de freeze (~4 s) — diffs exactos

Objetivo: un boot que congela en el disparo del GPU debe dejar (1) el log completo en FLASH
(sobrevive power-cycle) y/o (2) la DRAM legible mediante un reset **caliente** automático.
Principio: **nada de RAM es persistencia; la flash lo es; el WDT convierte freeze en reset
caliente**.

### 5.A [kernel] Retrasar el disparo del GPU hasta que userspace haya vaciado los canales

Nuevo `module_param` en `a6xx_gmu.c` (junto a `uke_s3_stage`): el resume del GMU se retiene
`uke_probe_hold_ms` desde el boot (msleep en tramos de 100 ms, CPU dormida, cero bus). Cmdline de
boot de diagnóstico: `msm.uke_probe_hold_ms=30000`.

```diff
--- a/drivers/gpu/drm/msm/adreno/a6xx_gmu.c
+++ b/drivers/gpu/drm/msm/adreno/a6xx_gmu.c
@@ -708,6 +708,17 @@
 MODULE_PARM_DESC(uke_rescue,
 	"UKE-K61: 1=escribir tambien el veredicto en el ultimo bloque 4K de "
 	"sda30 (zona rascador marcada UKE61RSC). Defecto 0 (pstore basta).");
+
+/* UKE-PERSIST #544: retener el resume del GMU N ms desde el boot para que el
+ * initramfs vacie ANTES del disparo lo que el freeze puede destruir: pstore a
+ * flash, dmesg a sda30 y el armado del watchdog (reset caliente si congelamos).
+ * El GO lo da el tiempo: quien quiera disparar antes, 0 (defecto, sin cambio). */
+static int uke_probe_hold_ms;
+module_param(uke_probe_hold_ms, int, 0444);
+MODULE_PARM_DESC(uke_probe_hold_ms,
+	"UKE-PERSIST: ms desde boot antes de tocar el GMU (default 0 = sin retencion).");
```

y en `a6xx_gmu_resume`, justo antes de H1-rpm:

```diff
@@ (inicio de a6xx_gmu_resume, antes del primer paso H1)
+	if (uke_probe_hold_ms > 0) {
+		/* ktime_get_boottime() = ms desde el arranque (incluye suspend):
+		 * retener hasta el tope, durmiendo la CPU (cero transacciones). */
+		s64 restante;
+
+		while ((restante = (s64)uke_probe_hold_ms -
+			(s64)ktime_to_ms(ktime_get_boottime())) > 0) {
+			pr_info("UKE-PERSIST: GPU retenido %lld ms mas (vaciado de canales)\n",
+				restante);
+			msleep(min_t(s64, restante, 100));
+		}
+	}
```

(Nótese: el freeze entonces ocurrirá ~30 s; para entonces el initramfs ya habrá hecho §5.C.)

### 5.B [kernel] uke_rescue: reintentar hasta que sda30 exista (matar la carrera §3.5)

En lugar de abandonar al primer ENOENT, guardar el ÚLTIMO registro en un buffer estático y
reintentar en un workqueue cada 500 ms (tope 60 s). Cada hito nuevo SOBREESCRIBE el buffer
(el último veredicto es el que importa) y la primera escritura con éxito desactiva el retry.

```diff
--- a/drivers/gpu/drm/msm/adreno/a6xx_gmu.c
+++ b/drivers/gpu/drm/msm/adreno/a6xx_gmu.c
@@ -354,6 +354,9 @@ (zona uke_k61_rescue_write)
+static char uke_rescue_buf[4096];	/* ultimo registro pendiente */
+static bool uke_rescue_done;		/* ya escrito a flash al menos una vez */
+static void uke_rescue_flush_work(struct work_struct *w);
+static DECLARE_DELAYED_WORK(uke_rescue_work, uke_rescue_flush_work);

 static void uke_k61_rescue_write(const char *tag, u32 a, u32 b)
 {
-	static bool dead;
-	struct file *f;
-	char buf[4096];
-	loff_t pos, size;
+	struct file *f;
+	loff_t pos, size;
 	int len;

-	if (!uke_rescue || dead)
+	if (!uke_rescue)
 		return;
+	/* componer SIEMPRE: el ultimo hito sustituye al anterior en el buffer */
+	memset(uke_rescue_buf, 0, sizeof(uke_rescue_buf));
+	memcpy(uke_rescue_buf, "UKE61RSC", 8);
+	len = scnprintf(uke_rescue_buf + 8, sizeof(uke_rescue_buf) - 8 - 4,
+			"%s a=%u b=%u", tag, a, b);
+	put_unaligned_le32(crc32_le(0, uke_rescue_buf + 8, len),
+			   uke_rescue_buf + sizeof(uke_rescue_buf) - 4);
+	if (uke_rescue_done)
+		return;		/* ya hay canario en flash; el buffer ya no corre prisa */
 	f = filp_open("/dev/sda30", O_WRONLY | O_DSYNC, 0);
 	if (IS_ERR(f)) {
-		pr_err_once("UKE-K61: rescue sda30 no disponible (%ld)\n", PTR_ERR(f));
+		/* #544: UFS puede tardar ~4.2 s (mas que ENV-END/STAGE-ARM):
+		 * reintentar en trabajo diferido, NO abandonar. */
+		if (PTR_ERR(f) == -ENOENT && !delayed_work_pending(&uke_rescue_work))
+			schedule_delayed_work(&uke_rescue_work, msecs_to_jiffies(500));
 		return;
 	}
-	size = i_size_read(file_inode(f));
-	if (size < 8192) {	/* particion absurda: no tocar */
-		dead = true;
-		goto out;
-	}
-	memset(buf, 0, sizeof(buf));
-	memcpy(buf, "UKE61RSC", 8);
-	len = scnprintf(buf + 8, sizeof(buf) - 8 - 4, "%s a=%u b=%u", tag, a, b);
-	put_unaligned_le32(crc32_le(0, buf + 8, len), buf + sizeof(buf) - 4);
-	pos = size - (loff_t)sizeof(buf);	/* SOLO el ultimo bloque */
-	if (kernel_write(f, buf, sizeof(buf), &pos) != sizeof(buf)) {
+	size = i_size_read(file_inode(f));
+	if (size < 8192)
+		goto out;
+	pos = size - (loff_t)sizeof(uke_rescue_buf);
+	if (kernel_write(f, uke_rescue_buf, sizeof(uke_rescue_buf), &pos)
+	    == sizeof(uke_rescue_buf))
+		uke_rescue_done = true;
+	else
 		pr_err("UKE-K61: rescue: escritura incompleta\n");
-		dead = true;
-	}
 out:
 	filp_close(f, NULL);
 }
+
+static void uke_rescue_flush_work(struct work_struct *w)
+{
+	static int intentos;
+	struct file *f;
+	loff_t pos, size;
+
+	if (uke_rescue_done || ++intentos > 120)	/* tope 60 s */
+		return;
+	f = filp_open("/dev/sda30", O_WRONLY | O_DSYNC, 0);
+	if (IS_ERR(f)) {
+		schedule_delayed_work(&uke_rescue_work, msecs_to_jiffies(500));
+		return;
+	}
+	size = i_size_read(file_inode(f));
+	if (size >= 8192) {
+		pos = size - (loff_t)sizeof(uke_rescue_buf);
+		if (kernel_write(f, uke_rescue_buf, sizeof(uke_rescue_buf), &pos)
+		    == sizeof(uke_rescue_buf))
+			uke_rescue_done = true;
+	}
+	filp_close(f, NULL);
+	if (!uke_rescue_done)
+		schedule_delayed_work(&uke_rescue_work, msecs_to_jiffies(500));
+}
```

Efecto: aunque el k61 congele en el primer `readl` del stage2, el trabajo diferido ya tiene el
registro `STAGE2-ARM` en el buffer y lo escribirá a FLASH en cuanto `sda30` aparezca (~150 ms
después) — **la flash sobrevive al power-cycle**. Queda cubierto incluso el caso "muere antes de
ENV-END": añadir `uke_k61_rescue_write("ENV-BEGIN", uke_s3_stage, 0)` como PRIMERA línea de
`uke_k61_env_probe()`.

### 5.C [kernel] uke-prevlog: firma correcta (el lector del boot siguiente)

```diff
--- a/drivers/soc/qcom/uke-prevlog.c
+++ b/drivers/soc/qcom/uke-prevlog.c
@@ -17,7 +17,9 @@
 #define PREV_BASE	0xa7000000UL
 #define PREV_CONSOLE_SZ	0x200000UL
-#define PREV_SIG	0x43474206UL	/* PERSISTENT_RAM_SIG */
+/* #544: ESTE kernel firma la zona console con PERSISTENT_RAM_SIG ^ 0 =
+ * 0x43474244 (fs/pstore/ram_core.c:39 + fs/pstore/ram.c:794, sig param 0).
+ * La 0x43474206 era la del upstream clasico: se acepta por compatibilidad. */
+#define PREV_SIG	0x43474244UL	/* firma de ESTE kernel */
+#define PREV_SIG_OLD	0x43474206UL	/* upstream clasico */
@@ -38,7 +40,8 @@
-	if (sig != PREV_SIG || size > PREV_CONSOLE_SZ - 12) {
+	if ((sig != PREV_SIG && sig != PREV_SIG_OLD) ||
+	    size > PREV_CONSOLE_SZ - 12) {
```

### 5.D [initramfs] Bloque PERSIST para el init de diagnóstico (ukeinit-diag; NO en ukeinit-arch)

`busybox` del cpio k34 **trae los applets `watchdog` y `dmesg`** (verificado por strings). Bloque
a insertar tras el montaje de pseudo-FS en el init de diagnóstico (sin userdata, sin fsck — la
variante `rdinit=/ukeinit-diag`):

```sh
# --- UKE-PERSIST #544: canales pre-GPU (GPU retenido por msm.uke_probe_hold_ms=30000) ---
mkdir -p /sys/fs/pstore
mount -t pstore pstore /sys/fs/pstore 2>/dev/null
n=0
for f in /sys/fs/pstore/console-ramoops-* /sys/fs/pstore/dmesg-ramoops-*; do
  [ -e "$f" ] || continue; n=$((n+1)); kmsg "X9COLD fichero=$f"
done
kmsg "X9COLD fin: $n ficheros de pstore del arranque anterior"
echo uke-persist-canary > /dev/pmsg0 2>/dev/null && kmsg "X9PMSG canary escrito"
# --- 1) volcado de kmsg a FLASH cada 5 s (sobrevive power-cycle) ---
# zona designada: ultimo MiB de sda30 (la misma filosofia del S136 de la era k12)
(
  sleep 6            # esperar a que UFS publique sda (~4.2 s medidos)
  DEV=$(ls /dev/sd? 2>/dev/null | head -1)   # sda; sda30 se resuelve por tamano si sobra
  i=0
  while [ $i -lt 200 ]; do                    # ~16 min de tope
    dmesg > /tmp/kmsg.now 2>/dev/null
    dd if=/tmp/kmsg.now of=$DEV bs=512 seek=$(( $(blockdev --getsz $DEV) - 4096/512*1 )) \
       count=8 conv=notrunc 2>/dev/null       # 4 KiB al final de sda (no userdata)
    sleep 5; i=$((i+1))
  done
) &
# --- 2) watchdog HW: freeze => bark => RESET CALIENTE => la DRAM (ramoops) sobrevive ---
# 15 s de margen; el petting corre SOLO mientras el SoC esta vivo de verdad
echo 15 > /sys/class/watchdog/watchdog0/timeout 2>/dev/null
( while :; do echo 1 > /dev/watchdog0 2>/dev/null || break; sleep 5; done ) &
kmsg "X9WDT armado (15 s): un freeze Longer que eso rebota caliente y conserva ramoops"
```

Notas de diseño de este bloque:
- El petting del WDT **no se para antes del disparo**: si el wedge deja la CPU viva
  (solo muere la isla GMU), el boot continúa por el camino -EAGAIN del k61 y el WDT no molesta.
  Si el wedge mata el scheduling (lo observado), el petting calla y el **bark resetea CALIENTE**:
  el ramoops console (que capturó todo desde 0,039 s) llega intacto al boot siguiente, donde
  uke-prevlog corregido (§5.C) y X9COLD lo entregan. ESE es el mecanismo nuevo que convierte el
  freeze en un dato legible.
- **Prohibido en el boot estable de Arch** (userdata montado rw: un bark a mitad de fsync corrompe).
  Solo en el init de diagnóstico, que no monta userdata.
- `dmesg` + `dd` a sda: corregir el cálculo del seek final contra el tamaño real (el boceto usa
  los últimos 4 KiB; reusable con el mismo formato `UKE61RSC` + CRC para distinguir volcado de
  marcador). Alternativa más simple: repetir el truco del S136 (marcador de época + dd por bloques
  fijos).

### 5.E [cmdline del boot de diagnóstico]

```
<la dorada actual> msm.uke_s3_stage=2 msm.uke_rescue=1 msm.uke_probe_hold_ms=30000
```

NO añadir `console=ramoops` (no existe), NO `ramoops=` (lo pone el DT y ya está bien),
NO `block2mtd=` (mtdoops es kmsg_dump-only: no dispara en freeze; canal muerto sin MTD en cmdline).

### 5.F [procedimiento] Recuperación del freeze

1. Congelado: **esperar 60 s** — si el WDT está armado, bark → reset caliente → boot siguiente
   con `console-ramoops-0` (verificar con `ls /sys/fs/pstore` y el último bloque de sda30 con
   `UKE61RSC`).
2. Si a los 60 s no hay reboot (WDT sin efecto), power-cycle: el canal FLASH
   (dumper §5.D + rescue §5.B) es entonces el único testigo — y ya habrá volcado el log de ~30 s
   de pre-disparo.
3. **Experimento barato para validar el camino caliente** (pendiente desde siempre, sin riesgo
   para la tablet): en el boot estable de Arch, `echo uke61-canary > /dev/pmsg0`, luego
   `echo b > /proc/sysrq-trigger` (reset caliente, sin corte de alimentación); en el boot
   siguiente, `cat /sys/fs/pstore/console-ramoops-0` (systemd-pstore lo archiva en
   `/var/lib/systemd/pstore/`). Si aparece el canario + log: warm path OK. Si la zona vuelve
   inválida (firma ajena), el bootloader pisa 0xa7000000 y el rediseño debe mover la zona
   ramoops a otra dirección libre (p.ej. 0xa6000000, justo bajo wlan_msa que acaba en a7000000)
   — decisión que depende de ESTE experimento.

---

## 6. Límites de esta investigación

- La hipótesis "el k61 congeló en la ventana stage2" es la de los 29/29 precedentes; si congeló
  ANTES (durante ENV), §5.B (ENV-BEGIN + retry) y §5.D (volcado pre-GPU) lo cubren igualmente.
- La dirección exacta del seek del dumper de §5.D es un boceto a cerrar en la implementación
  (tamaño de sda, bloque destino, formato compartido con UKE61RSC).
- Que XBL/ABL pisa 0xa7000000 es una sospecha fuerte (bytes tipo branch en la zona, nunca firma
  válida al despertar), no un hecho medido: el experimento §5.F.3 la confirma o la mata.
- No se ha tocado la tablet: todo lo aquí dicho es de código, config, DT, bootimg y evidencia
  archivada.
