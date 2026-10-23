# R1 — Auditoría de la maquinaria UKE-POKE y validación del experimento K7

Fecha: 2026-09-29 (madrugada). Autor: revisor R1.
Alcance: auditoría de código (K1..K6) + validación de la cmdline K7 **antes de flashear**.
Sin tablet: no se ha usado adb/fastboot/ssh/telnet ni `/dev/ttyACM0`. Solo lectura de logs ya
capturados, `~/gpu-work` en solo lectura y escritura bajo `build/gates/revision/` + `/var/tmp`.

**Artefacto auditado (leído del propio fichero, no de memoria):**

| campo | valor |
|---|---|
| ruta | `build/bootimg/boot-ukek7.img` (100 663 296 B) |
| sha256 | `1c1a090bc69e532f7585a1386345d01f2c8c87712a8d2b5f5b064bf7c96722d4` |
| kernel | `kernel_size` @off 8 = 16 567 869 B — **sha256 del payload kernel idéntico al de `boot-ukek6.img`** (`ac878610f9a982a4b11fdd75bf844005944d07084324eba57e2ce4016d94a20c`) ⇒ K7 = K6 sin recompilar ✔ |
| cmdline (382 B, medida) | `… console=ttyGS0,115200 fw_devlink=permissive clk_ignore_unused pd_ignore_unused arm-smmu.disable_bypass=0 arm_smmu.uke_smr_max=0 arm_smmu.uke_keep_boot=1 arm_smmu.uke_attach_log=2 arm_smmu.uke_smmu_probe=1 arm_smmu.uke_reset_mask=12` |
| integridad | NUL-terminada, resto del campo `cmdline[1536]` a cero, `AVB0` @35 438 592, `AVBf` en el footer ⇒ shell AVB intacto ✔ |

Comprobado en el binario (`strings Image`): las cadenas de los params existen **con prefijo
`arm_smmu.`** (`arm_smmu.uke_smmu_probe`, `arm_smmu.uke_smr_max`, `arm_smmu.uke_keep_boot`,
`arm_smmu.uke_attach_log`, `arm_smmu.uke_reset_mask`, `arm_smmu.uke_protect_smr0`,
`arm_smmu.uke_stream_match`, `arm_smmu.disable_bypass`) ⇒ la cmdline de K7 **casa exactamente**
y se parsea (ver §3).

---

## 0. VEREDICTO

### GO — pero con la expectativa CORREGIDA (el K7 no corre a ~1 s: corre a ~0,445 s y puede morir MUDO)

La cmdline K7 es **correcta sintáctica y semánticamente**: no hay ninguna combinación de params
que se rompa por el orden, `uke_reset_mask=12` ejecuta exactamente F4+F5-7 y **no hay ninguna
corrección urgente que hacer a los valores**. El artefacto está verificado y es K6 puro.

**NO cambiar ningún valor de la cmdline.** Sí hay que corregir tres cosas del *diseño/expectativa*:

1. **[URGENTE – expectativa] El probe real cae a los ~0,445 s, NO a ~1 s.** El "retry del deferred
   a ~1 s" del ESTADO-VIVO es falso. Medido en los 4 logs (k2/k5b/k6/k6b): las entradas en el
   probe de apps-smmu son `~0,33 s` (primer probe → `DIFFERIDO`), **`~0,445 s`**, `~3,600 s` y
   `~13,94 s`. Con `uke_smmu_probe=1` en la cmdline, el primer re-entrada (0,445 s) ya pasa el
   *early defer block* y corre el probe de verdad (arm-smmu.c:2951-2964). **A los 0,445 s la
   consola `ttyGS0` NO existe** (se habilita a los 3,572048 s, k6b-migas.log:1498) ⇒ si K7
   wedgea en la ventana temprana, **muere mudo**, sin pstore, con `hung_task_panic=1` (20 s) y
   `panic=10` ⇒ bucle de reinicio (o cuelgue estable, como se vio en #P5: "primero bucle con
   panic=10, después cuelgue estable"). Es exactamente el escenario de #P5 (K1 gate1) — que murió mudo
   con la *misma* arming-por-cmdline. **La ventana es real (es incluso más temprana que Android:
   Android 0,543 s vs K7 ~0,445 s) pero la captura en vivo no está garantizada.**
2. **[URGENTE – expectativa] El primer punto de muerte esperado es el PRIMER write_sme del
   attach, `1de0000.qcedev` idx=1** (evidencia robusta en `k4c-consola-trail.txt:27920-27922`),
   no la fase7. Con `uke_attach_log=2` ese índice **no** está protegido (la RAM solo conoce como
   vivo el idx 0, por `uke_smr_max=0`) ⇒ K7 re-prueba *exactamente* la escritura que mató a K4.
3. **[URGENTE – operativa] Precaución con el bucle**: tras el wedge, `hung_task_timeout_secs=20` +
   `hung_task_panic=1` + `panic=10` ⇒ reinicio cada ~30 s y cada arranque monta el ext4 podrido en
   rw. Tener el rescate a mano y, si el veredicto es wedge mudo, apagar/cortar el bucle pronto;
   `e2fsck` en frío sigue siendo prerequisito (ESTADO-VIVO §2, regla 5: pstore VACÍO).

Las condiciones para que sea un buen experimento están puestas: si el bind sobrevive, a los
3,6 s hay consola y SSH y las migas del 0,445 s están **en el ring buffer** (`log_buf_len=256K`)
⇒ `dmesg | grep UKE-POKE` las recupera enteras. El valor discriminante de K7 es alto: si sobrevive
al storm, la hipótesis "dma vivo" gana; si muere mudo a ~0,45 s, gana "registro/índice protegido".

---

## 1. Mapa completo de params `uke_*`

Fuente: `/var/tmp/uke-k1/drivers/iommu/arm/arm-smmu/arm-smmu.c` y `arm-smmu-qcom.c` (árbol con
K1..K6). Todos se registran con `module_param*` ⇒ para built-in el nombre real lleva prefijo
`KBUILD_MODNAME "."` (`arm_smmu.`) y se parsea en `start_kernel` (init/main.c:1010-1013).
`parameq()` normaliza `-`↔`_` (kernel/params.c:80-100) ⇒ `arm-smmu.disable_bypass` también vale.

| param | tipo / default | fichero:línea (decl / .set / uso) | efecto exacto | .set |
|---|---|---|---|---|
| `uke_smmu_probe` | bool, def. `false` | decl. arm-smmu.c:98; `.set` :116-129; ops/cb :131-138; uso :2951-2963 | Gate del *early defer block*: si `false` el probe de apps-smmu imprime "desarmado" (rate-limited 1/s) y devuelve `-EPROBE_DEFER` para siempre; si `true` deja pasar el probe real (MMIO). | `param_set_bool` + `pr_info` + `driver_deferred_probe_trigger()` **si armado** (en parseo temprano es no-op: `dd.c:191` corta con `driver_deferred_probe_enable==false`, que solo se pone a true en `deferred_probe_initcall`, `dd.c:353-386`) |
| `uke_smr_max` | int, def. `-1` | decl. arm-smmu-qcom.c:481-484; uso :573-588 | Limita el barrido de lectura de SMR de `qcom_smmu_cfg_probe`: `-1`/≥109 = los 110; `0..108` = SMR(0..n); `-2` = no lee ninguno. `=0` deja la RAM con `smrs[0].valid=1` y `smrs[1..109]` **inválidos (aunque el HW tenga ahí mapeos vivos)**. | **no tiene** (module_param plano) |
| `uke_keep_boot` | bool, def. `false` | decl. :218; `.set` :228-239; ops :241-248; usos :1494-1500 (test_smr_masks), :277-289 (máscara) | Para apps-smmu: (a) con él y sin escribir `uke_reset_mask`, la máscara efectiva pasa a `0xfffe` (fase2 fuera); (b) `arm_smmu_test_smr_masks()` no toca HW y asume `smr_mask_mask=0xffff`. | `param_set_bool` + `pr_info` (un solo print) |
| `uke_reset_mask` | int, def. `0xffff` | decl. :219-220; `.set` :250-265; ops :267-274; cálculo efectivo :277-289 | Máscara por fases del reset del apps-smmu (`bit0`=F2, `bit1`=F3, `bit2`=F4, `bit3`=F5+6+7; 1=ejecutar). F1 sGFSR es incondicional. Para otros SMMUs (kgsl) siempre `0xf`. | `param_set_int` (`kstrtoint(val, 0)`, params.c:215-237 ⇒ `"12"`=`12` dec) + `uke_reset_mask_tocado=true` + `pr_info` |
| `uke_attach_log` | int, def. `0` | decl. :361; `.set` :364-373; usos :1043-1044 (flush CB), :1609-1700 (preservar), :1709-1735 (migas+flush), :1784-1789 (install_s2crs) | `0`=silencio; `1`=migas por maestro + volcado BL + `pr_flush` antes de cada escritura; `2`=además **no escribe** el SME cuyo índice la RAM marca vivo del BL (`uke_sme_es_bl`, :413-418). | `param_set_int` + `pr_info` |
| `uke_protect_smr0` | bool, def. `false` | decl. :362; `.set` :384-393; ops :395-402; uso :1661-1672 | Variante "reubicar": si `find_sme` devuelve un índice vivo del BL, el maestro se reasigna al primer índice libre **alto** (`num_mapping_groups-1` hacia abajo, sin tocar 0) y escribe ahí. **Precedencia: con `uke_attach_log>=2`, PRESERVAR gana ⇒ en K7 es código muerto.** | `param_set_bool` + `pr_info` |
| `uke_stream_match` | bool, def. `true` | decl. :181-184; uso :2539-2555 | Si `0`: para apps-smmu fuerza stream-indexing (`smrs==NULL`), se salta barrido y **todo** write de SMR; `num_mapping_groups` se capea a 110 y `s2crs[]` se aloja con 1<<NUMSIDB. No está en la cmdline de K7. | **no tiene** |

### 1.1 Interacción entre `.set` (uke_keep_boot ↔ uke_reset_mask) y orden en la cmdline

- `uke_keep_boot_set()` (arm-smmu.c:228-239) **no toca** `uke_reset_mask` ni `uke_reset_mask_tocado`.
- `uke_reset_mask_set()` (:250-265) **siempre** pone `uke_reset_mask_tocado=true`, sin mirar
  `uke_keep_boot`. Con `tocado=true` la máscara efectiva es `uke_reset_mask & 0xf` (:282-283)
  **independientemente del orden** y de `keep_boot`.
- `uke_smmu_probe_set()` no depende de los demás (solo del bool que él mismo fija).
- ⇒ **El orden en la cmdline NO importa** para el resultado en K7. (En el log se ve el orden del
  parseo — izq→der: `uke_keep_boot`, `uke_attach_log`, `uke_smmu_probe`, `uke_reset_mask`;
  `uke_smr_max` no imprime nada porque no tiene `.set`.)
- Única dependencia de orden *conceptual*: si se hubiera escrito `uke_reset_mask=0xffff` **y**
  `uke_keep_boot=1`, la fase2 volvería a ejecutarse (comentario :214-216) — no es el caso de K7.
- **No hay forma de que la combinación propuesta rompa nada**: `12 & 0xf = 0xc` ⇒ fase2=0, fase3=0,
  fase4=1, fase5-7=1. Precisamente el conjunto medido como superviviente en #P15/K6 disparo 2.

---

## 2. `uke_reset_mask=12` (0xc): qué se ejecuta y qué no

Bits: `#define UKE_RESET_F2 BIT(0)`, `F3 BIT(1)`, `F4 BIT(2)`, `F567 BIT(3)`, `BITS 0xf`
(arm-smmu.c:222-226). **12 = 0b1100 = F4 | F567** ⇒ fase2 (clear/poblar SMR/S2CR) y fase3
(CBAR/SCTLR/FSR por CB) se **omiten**; fase4 y fase5-7 se **ejecutan**.

### 2.1 Qué escribe exactamente cada fase (registro, valor) — arm-smmu.c:2321-2419

| fase | operación exacta | registro(s) y valor | cita |
|---|---|---|---|
| **1 (siempre)** | RMW (read+write del mismo valor) | GR0 `sGFSR` (0x48): `writel(readl(0x48))` | :2333-2335 |
| F2 (OFF) | — | imprimiría SMR(0x800+4i)/S2CR(0xc00+4i) para i=0..109 | :2347-2355 |
| F3 (OFF) | — | escribiría CBAR/CBA2R/SCTLR=0/TCR/TTBR/MAIR + CB_FSR=FAULT en los 71 CB | :2358-2367 |
| **F4 (ON)** | 2 writel sueltos | GR0 `TLBIALLH` (0x6c) = `QCOM_DUMMY_VAL` = **0xffffffff**; GR0 `TLBIALLNSNH` (0x68) = **0xffffffff** | :2370-2373, `QCOM_DUMMY_VAL` arm-smmu.c:53 |
| **F5 (ON)** | RMW **en RAM** (sin escribir aún) de sCR0 + 2 prints | lee GR0 `sCR0` (0x0); `|= GFRE\|GFIE\|GCFGFRE\|GCFGFIE` (0x36); `|= VMIDPNE\|PTM` (0x1800); `&= ~CLIENTPD`; `disable_bypass=0` ⇒ `&= ~USFCFG`; `&= ~FB`; `&= ~BSU`; `VMID16`/`EXIDS` **no aplican** (ID2 bit15=0; ID0 bit8=0) | :2378-2407 |
| **F6 (ON)** | `impl->reset` = `arm_mmu500_reset` | lee GR0 `ID7` (0x3c); lee `sACR` (0x10); si major≥2 `&= ~CACHE_LOCK` (bit26); `\|= SMTNMB_TLBEN\|S2CRB_TLBEN` (bits 8 y 10); **escribe sACR**. Además, por `CONFIG_ARM_SMMU_MMU_500_CPRE_ERRATA=y` (verificado en `.config`): bucle de **71 CBs** → `readl(CB_ACTLR)`, `&= ~CPRE` (bit1), `writel(CB_ACTLR)`, `readl(CB_ACTLR)` | arm-smmu-impl.c:110-148 |
| **F7 (ON)** | 1 writel + poll + 1 writel | `arm_smmu_tlb_sync_global` → `arm_smmu_writel(GR0, sTLBGSYNC 0x70, 0xffffffff)` + poll de `sTLBGSTATUS` (0x74 bit0) — con el impl qcom pasa por `qcom_smmu_tlb_sync` (arm-smmu-qcom.c:89-107); después `arm_smmu_gr0_write(sCR0, reg)` con el `reg` calculado en F5 | :2412-2415 |

Notas finas: F1 no cambia nada (RMW del mismo valor; aun así es una escritura) y F7 **es el único
punto donde se materializa sCR0** (F5 solo lo calcula). Con `mask=12`, F3 no se ejecuta ⇒ los CBs
del BL (p. ej. el que use el UFS) **no se desactivan**; F2 no se ejecuta ⇒ **ni un SMR ni un S2CR**.

### 2.2 Escrituras INCONDICIONALES fuera de las fases (el riesgo residual de mask=12)

Estas NO las puede saltar `uke_reset_mask` y ocurren siempre que el probe real corre:

| # | qué | registro/valor | cita | veredicto medido |
|---|---|---|---|---|
| A | `qcom_smmu_cfg_probe` quirk (se detecta siempre: `quirk=SI`) | escribe `S2CR(num_mapping_groups-1)`=`S2CR(109)` = **0x000100ff** (BYPASS, cbndx 0xff) y **lo relee** (0x000200ff = FAULT) | arm-smmu-qcom.c:532-541 | **SEGURO** (K2/K3/K6b lo hacen y sobreviven a esa altura) |
| B | idem, rama del quirk | `arm_smmu_cb_write(bypass_cbndx=70, CB_SCTLR, 0)` + `GR1 CBAR(70)` = `CBAR_TYPE_S1_TRANS_S2_BYPASS` | arm-smmu-qcom.c:542-556 | superviviente en todos los runs (CB70) |
| C | `arm_smmu_rmr_install_bypass_smr` (se llama SIEMPRE, también con DT sin IORT) | RMW de `sCR0`: **`reg \|= CLIENTPD` y escribe** (el listado de RMRs está vacío en DT ⇒ no escribe SMRs) | arm-smmu.c:2842-2860 (llamada :3072) | fase intermedia no medida con lupa; K4/K6 pasaron de aquí |
| D | fase1 `sGFSR` | GR0 0x48 RMW | :2333-2335 | SEGURO |
| E | **storm de attach** disparado por `iommu_device_register` (:3093) → `bus_iommu_probe` (iommu.c:1954-1997) | por cada uno de los ~57 maestros con `iommus`: `write_sme` (S2CR+ SMR) en el índice que `find_sme` devuelva; y por cada **grupo** `iommu_setup_default_domain` (iommu.c:1977) ⇒ para el wifi (`qcom,wcn6750-wifi`, único con `def_domain_type==0`, arm-smmu-qcom.c:709-727) dominio **TRADUCIDO** ⇒ `arm_smmu_init_domain_context` asigna CB (`start=num_s2_context_banks=0`, :1207) y `arm_smmu_write_context_bank` escribe **CBAR/CBA2R/TCR/TTBR/MAIR/SCTLR del CB 0** | :2148, :1609-1737, :1250, :1308, :1018-1126 | **NO MEDIDO como conjunto**; el primer write_sme es el punto de muerte de K4c (§4) |
| F | handler de fallo global (solo si hay un fault) | GR0 `sGFSR` write | :957 | — |
| G | `arm_smmu_device_group` / TLB ops del dominio | sin MMIO en la ruta de grupo | :2194-2232 | — |

Conclusión §2.2: **mask=12 no convierte el probe en "solo lecturas"**; deja C+B+A+E, y E incluye
la escritura que mató a K4. Lo que sí consigue mask=12 (medido en #P15/K6b) es **cruzar el reset
entero sin muerte** — el asesino medido de las fases (SMR/S2CR x110, SCTLR de CB vivo) queda fuera.

---

## 3. Arming por cmdline: traza real y el error de "~1 s"

### 3.1 Cuándo se ejecuta el `.set` y qué hace

`start_kernel()` → `init/main.c:1010-1013`: `parse_early_param(); parse_args("Booting kernel",
static_command_line, __start___param, __stop___param - __start___param, …)`. Eso corre **antes de
cualquier initcall** ⇒ a la entrada de `arm_smmu_device_probe` (primer probe, ~0,33 s) el estado ya
es: `uke_smmu_armado=true`, `uke_smr_max=0`, `uke_keep_boot=1`, `uke_attach_log=2`,
`uke_reset_mask_tocado=true`, `uke_reset_mask=0xc`.

`uke_smmu_probe_set()` en parseo temprano: `param_set_bool("1")` + `pr_info` + `driver_deferred_probe_trigger()`
→ la función corta en `drivers/base/dd.c:191` (`if (!driver_deferred_probe_enable) return;`) porque
`driver_deferred_probe_enable` solo se pone a `true` en `deferred_probe_initcall()`, `late_initcall`
(dd.c:353-386, símbolo `..._deferred_probe_initcall7`). ⇒ **Sin efectos colaterales** (ni crash ni
reintento prematuro). Lo único que se ve en el log son los 4 prints del parseo.

### 3.2 ¿Defiende el "early defer block" aunque `uke_smmu_armado=1`? SÍ

arm-smmu.c:2929-2937: `static bool ya_diferido; if (!ya_diferido) { ya_diferido = true; print "primer
probe DIFFERIDO"; return -EPROBE_DEFER; }` — se evalúa **antes** de mirar `uke_smmu_armado`. El
primer probe SIEMPRE difiere. El probe real corre en la **primera re-entrada** y esa re-entrada no
es el initcall del driver (el driver solo se registra una vez; `module_init` = **device_initcall
nivel 6**, `nm` del `.o`: `__initcall__kmod_arm_smmu__927_3241_arm_smmu_init6` — **no** es
subsys_initcall), sino el procesamiento de la lista de diferidos.

### 3.3 Los tres trenes de re-entrada (medidos, idénticos en k2/k5b/k6/k6b)

| tren | disparador | hora apps-smmu | evidencia |
|---|---|---|---|
| 1 | "ola" del fork (X9WAVE, `deferred_probe_work_func`, dd.c:83-143) que procesa la lista de diferidos ya en pleno arranque | **~0,41-0,47 s** (2 entradas) | k6b: `[0.444926] X9WAVE-try 15000000.apps-smmu`, `[0.445041] …ENTRANDO`, `[0.445042] …desarmado`; k6: 0,418931; k5b: 0,415939; k2: 0,435372 |
| 2 | `deferred_probe_initcall` (late_initcall, ~3,56 s) + trigger | **3,6006 s** | k6b: `[3.600621] ENTRANDO`, `[3.604942] desarmado`; k2: 3,601223; k5b: 3,600836 |
| 3 | `deferred_probe_timeout_work` (10 s tras el late_initcall, `CONFIG_DRIVER_DEFERRED_PROBE_TIMEOUT=10`) + ola de UFS | **13,92-13,94 s** | k6b: `[13.938805] ENTRANDO`, `[13.938807] desarmado`; k2: 13,910584; k5b: 13,919135 |

**Consecuencia exacta para K7:** como `uke_smmu_armado=1` desde el parseo, en la entrada del tren 1
a las **0,4449 s** el bloque imprime `REINTENTO del probe…` y **entra al probe real** (cfg_probe +
reset + storm). El tren 2 (3,60 s) **no se alcanza** salvo que el probe real devuelva
`-EPROBE_DEFER`/error (no ocurre: no hay ningún camino de defer dentro del probe real) o que muera.

*Nota de trazabilidad (sin efecto en la conclusión):* la fuente de `dd.c` que he leído solo pone
`driver_deferred_probe_enable=true` en `deferred_probe_initcall` (late_initcall, dd.c:353-386) y el
`.o` construido lo confirma (`__initcall__kmod_dd__523_386_deferred_probe_initcall7`), pero los
timestamps de los 4 logs demuestran que la ola de diferidos ya trabaja a los 0,37-0,47 s (50
entradas X9WAVE-try entre 0,375 y ~3,6 s). Sea por el orden real de initcalls del fork o por otra
vía, **el hecho operativo medido —y suficiente para predecir K7— es que `arm_smmu_device_probe`
se re-entra a los 0,4449 s con `ya_diferido=true`**; con arming, esa re-entrada es el probe real
(arm-smmu.c:2951-2964). Merece 5 min de comprobación para el informe (no para la decisión).

### 3.4 ¿Es real la ventana respecto al UFS? SÍ (y es lo único bueno del hallazgo)

Medido en los mismos boots (k6b): `ufshc` **no arranca de verdad hasta 13,799/13,800 s**
(`[13.799777] ufshcd-qcom 1d84000.ufshc: deferred probe timeout, ignoring dependency` —
k6b-migas.log:1538; k4c-consola-trail.txt:94 en 13,800421) y el **mount del rootfs es a 15,61-15,63 s**
(`EXT4-fs (sda32): mounted filesystem…` k6-migas.log:1809 [15.616568]; k4c:243 [15.613209]);
`/ukeinit` arranca a **3,560963 s** (k6-migas.log:1475) y habilita `ttyGS0` a **3,572048 s**
(k6b-migas.log:1541). ⇒ A los 0,445 s **no hay DMA del kernel por el UFS ni rootfs montado**: la
ventana es legítima, incluso más temprana que Android (0,543250 s en
`dmesg-android.txt:1733`, con `Adding to iommu group 0` del ufshc a 0,550689 s, línea 1744).
**La ventana es real; lo que no es real es el "~1 s con consola" del ESTADO-VIVO.**

---

## 4. Muerte K6b, primer attach y dispositivos del DT con `iommus`

### 4.1 K6b: última miga viva

`~/proyectos/out/k6b-migas.log` (K6 + s258 + disparo en caliente a los 90 s):
`[90.424565] arm-smmu: UKE-POKE: reset fase7 tlb_sync_global + write sCR0` es la **última** línea
(después: `Read from remote host … Connection timed out`). No hay ninguna miga de attach ⇒ el
asesino está entre ese print y la primera miga *flush-eada* del attach: `arm_smmu_tlb_sync_global`
(:2414), el `writel(sCR0)` (:2415), `test_smr_masks OMITIDO` (:3086 → :1494) o el inicio del storm.
Ojo: k6/k6b son streams `dmesg -w` por SSH ⇒ la cola puede perderse (el trail robusto es la consola;
regla 3 del ESTADO-VIVO). **No es evidencia de que el probe llegara al attach.**

### 4.2 La evidencia buena (consola robusta): k4c

`build/gates/k4c-consola-trail.txt:27919-27922` (K4, keep_boot sin máscara explícita, 51,653 s):

```
[51.653281] reset fase7 tlb_sync_global + write sCR0
[51.653346] test_smr_masks OMITIDO (uke_keep_boot=1): … streamid_mask=0x7fff smr_mask_mask=0xffff
[51.653598] attach: find_sme(dev=1de0000.qcedev sid=0x480 mask=0x0) -> 1
[51.653605] attach: find_sme(dev=1de0000.qcedev sid=0x481 mask=0x0) -> 2
[51.653609] write_sme idx=1 S2CR(0xc04) type=1 cbndx=0 + SMR(0x804) id=0x480 mask=0x0 valid=1
   ← y silencio
```
⇒ **el primer attach de la tormenta es `1de0000.qcedev`** y la muerte ocurre en su **primera
escritura de SME (idx=1)**: `S2CR(1)` @0xc04 y/o `SMR(1)` @0x804. Además, `S2CR(1)`/`SMR(1)`
están fuera de lo medido como seguro (lo único escrito+releído con éxito fue **S2CR(109)** @0xdb4,
K2). Con `uke_smr_max=0`, `smrs[1..]` son "libres" en RAM **aunque el BL tenga ahí mapeos vivos**
⇒ el driver escribe encima del índice 1 sin saber qué había.

### 4.3 Dispositivos del DT con `iommus` → apps-smmu (phandle 0x129)

Base: `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img` (DTB crudo; descompilado a
`/var/tmp/r1dt/base.dts`) + overlay en la tablet `build/bootimg/s258-panel-gpio2.img`
(payload extraído con `build/bootimg/dtbo-extract.py`, sha256 del payload
`ea6ac36ed395a6f117aa18e82eb382aa53f32fff96bfa6de5501a921c3c3253a`). El overlay **no** toca
`iommus`; sus únicos cambios en apps-smmu son `fragment@160` (`reg=<0x15000000 0x200000>`,
`reg-names="base"`) y `fragment@159` (canario `uke,canary-smmu`) ⇒ el DT efectivo casa con el check
de K7 (`size==0x100000 || 0x200000`, arm-smmu.c:2925-2928). **56 nodos** en la base (el wifi
`qcom,wcn6750-wifi` viene del overlay, `s258.dts:15199-15202`, con `iommus` propio ⇒ ~57 maestros
en el DT efectivo).

Tabla completa en el **Anexo A**. Los importantes:

| nodo | sid / mask | nota |
|---|---|---|
| `ufshc@1d84000` | **0x60 / 0x00** | **coincide exactamente con SMR(0)** (`0x80000060`, mask real 0) ⇒ es el único que `find_sme` reutiliza en idx 0 |
| `qcom,smmu_sde_unsec_cb` | 0x1c00 / 0x02 | **es el `qcom,handoff-smrs = <0x1c00 0x02>` del DT** (base.dts:13186) ⇒ el BL dejó un SMR para el display en un índice **desconocido** (con smr_max=0 no se ve) |
| `1de0000.qcedev` (+hijos) | 0x480/0x481/0x483 | **primer attach medido** (k4c) |
| `qcom,wcn6750-wifi` | (overlay) | único con `def_domain_type==0` ⇒ dominio traducido ⇒ **write_context_bank(CB0) en el storm** |
| vidc, cam_smmu, cvp, fastrpc cb1..17, ipa | 0x1920-0x1947, 0x1c0x, 0xc01..0xc0e, 0x18xx, 0x4a0-0x4a4, 0x1001-0x1087 | 5 fastrpc con varios ids; `msm_cam_smmu_icp` con 5 ids |

### 4.4 ¿Qué attach esperar en K7 temprano y qué miga?

El orden del bus es el mismo que en k4c (mismo DT efectivo, s258) ⇒ el primer maestro es
**`1de0000.qcedev`**. Ello es coherente con el mecanismo: `iommu_device_register` recorre
`iommu_buses[]` = **platform primero, luego pci y amba** (iommu.c:186-196) y, dentro de platform, el
orden del DT; los `tmc@1004xxxx` (con iommus y sid 0x4e0/0x4c0/0x500) son **AMBA** (`arm,primecell`)
y por eso van al final, no antes que qcedev. Con `uke_attach_log=2`, como el idx 1 **no** es "vivo
del BL" según la RAM, `uke_bl=false` ⇒ **sí se escribe**. Migas esperadas (textos de
arm-smmu.c:1627-1734, literales):

```
UKE-POKE: attach: find_sme(dev=1de0000.qcedev sid=0x480 mask=0x0) -> 1
UKE-POKE: attach: find_sme(dev=1de0000.qcedev sid=0x481 mask=0x0) -> 2
UKE-POKE: attach: ESCRIBIR SME idx=1 dev=1de0000.qcedev -> SMR=0x00080480 (id=0x480 mask=0x0 valid=1) | S2CR nominal=0x00010000 (type=1 cbndx=0) [impl->write_s2cr: quirk qcom reescribe]      ← con pr_flush
arm-smmu: UKE-POKE: write_sme idx=1 S2CR(0xc04) type=1 cbndx=0 + SMR(0x804) id=0x480 mask=0x0 valid=1
UKE-POKE: qcom write_s2cr idx=1 quirk: type=0 cbndx=70 reg=0x00000046 en 0xc04
```
Esa 4ª línea es la delatora: si muere justo después de la 3ª (flush-eada) y antes de la 5ª, el
punto exacto es el `writel` de `S2CR(1)` dentro de `qcom_smmu_write_s2cr` (:685). El ufshc **no**
es el primer attach; su `find_sme(... sid=0x60 ...) -> 0` debería salir más tarde (y con
`PRESERVADO`), con migas:

```
UKE-POKE: attach: find_sme(dev=1d84000.ufshc sid=0x60 mask=0x0) -> 0
UKE-POKE: attach: dev=1d84000.ufshc sid=0x60 mask=0x0 -> find_sme elige idx=0, SME VIVO DEL BOOTLOADER (id=0x60 mask=0x0 valid=1)
UKE-POKE: attach: SME idx=0 PRESERVADO (BL vivo): NO se escribe; 1d84000.ufshc queda con el mapeo del bootloader
UKE-POKE: attach: SME idx=0 PRESERVADO (BL vivo): se omite write_sme (no se toca SMR/S2CR)
```

---

## 5. `uke_attach_log=2`: qué se omite exactamente y qué NO

### 5.1 Lo que se OMITE (código exacto)

1. `arm_smmu_master_alloc_smes()`, **2º bucle** (el que "pocan el HW"): `if (… test_bit(i, uke_preservar)) { print "SME idx=%d PRESERVADO…"; continue; }`
   (arm-smmu.c:1685-1700) ⇒ **no se llama `arm_smmu_write_sme`** para ese maestro: ni S2CR ni SMR.
   El índice queda reclamado en RAM (`smrs[idx]` con los valores del BL, `s2crs[idx].count++`,
   `cfg->smendx[i]=idx`, :1675-1681) y el grupo se crea igual (`arm_smmu_device_group`, :2194).
2. `arm_smmu_master_install_s2crs()` (el attach del dominio): `if (uke_attach_log>=2 && test_bit(idx,
   uke_preservados_bl)) { print "install_s2cr idx=%d PRESERVADO…"; continue; }` (:1784-1789) ⇒
   tampoco se escribe el S2CR y **tampoco se actualiza la RAM** (`s2cr->type/cbndx` quedan como
   estaban: BYPASS/0xff) ⇒ el maestro queda "atado" al dominio en RAM pero el HW sigue con el BL.

### 5.2 Lo que NO se omite (el riesgo residual real)

1. **Asignación y programación del CB del dominio nuevo** — para cualquier dominio *traducido*:
   `arm_smmu_init_domain_context()` (:1250 `arm_smmu_alloc_context_bank`, `start=num_s2_context_banks=0`
   ⇒ **el primer CB libre, que con `context_map` casi vacío es CB0**) → `arm_smmu_write_context_bank`
   (:1308) escribe **CBAR(0), CBA2R(0), TCR, TTBR0/1, MAIR0/1, SCTLR=CFIE|CFRE|AFE|TRE|M + S1_ASIDPNE**
   (:1055-1125). En el storm del apps-smmu, **el único maestro con dominio traducido es el wifi**
   (`qcom,wcn6750-wifi`); el ufshc es IDENTITY (no pasa por aquí), pero si el BL tuviera el UFS
   traduciendo por **CB0**, K7 lo pisa en el storm. **Esto no lo protege ningún param.**
2. **TLB**: `arm_smmu_tlb_inv_context_s2`/`s1`, `arm_smmu_tlb_sync_global`… los flushes del dominio
   (no afectan a S2CR(0); el TLBIALLH/NSNH de fase4 ya van con mask=12).
3. **La petición del IRQ de contexto** (`devm_request_irq`, :1314-1335) y el `device_link_add`.
4. **`master_free_smes` NO tiene guarda de preservación** (BUG, §7): si el ufshc se libera
   (`arm_smmu_release_device`, :2165-2180) se llama `arm_smmu_write_sme(idx=0)` con
   `s2cr_init_val` (BYPASS/FAULT) ⇒ **pisaría el mapeo del BL**. No debería ocurrir en K7 (el
   probe_device del ufshc va a éxito), pero es una mina para K8 en un `unbind` en caliente.

### 5.3 ¿Se pisa el CB vivo del BL? ¿Qué miga lo delata? ¿Es seguro para el UFS?

- Con K7: el ufshc es IDENTITY ⇒ no se le programa CB; su S2CR(0) **no se escribe** ⇒ el HW
  conserva el mapeo del BL. El CB que el BL use para el UFS (el candidato medido en #P14 es el 22)
  **no se toca** porque fase3 va omitida. El peligro de "pisar el CB vivo" queda acotado a:
  (a) el CB0 del wifi en el storm, (b) el CB que pida el DPU cuando se bindee por sysfs (plan §6c).
- La miga que lo delataría: `UKE-POKE: write_context_bank idx=0 cfg=asignado (CB_SCTLR en 0x8….0)`
  (arm-smmu.c:1033-1036) **seguida** de la 1ª escritura real ⇒ si la consola muere ahí, el asesino
  es `arm_smmu_write_context_bank` del CB 0 (dominio del wifi).
- ¿UFS seguro? **No hay garantía.** El S2CR(0) del BL queda intacto, pero:
  1. fase5+7 **reescriben sCR0** (quitan `CLIENTPD` y `USFCFG`); el estado actual de la tablet
     (sin driver de SMMU) es el que dejó el ABL, que *funciona*. Si el ABL mantenía el SMMU
     "apagado" por `CLIENTPD=1` (mainline usa justo eso para "turn the thing off",
     arm-smmu.c:3123-3124), K7 lo **enciende** y el tráfico del UFS empezará a traducirse por el
     CB del BL. El UFS trabaja hoy sin driver ⇒ el mapeo vivo es funcional *tal cual está*; con
     sCR0 alterado, no se sabe.
  2. El kernel cree que el ufshc está en dominio IDENTITY (DMA con direcciones físicas) mientras
     el HW conserva el mapeo del BL. Si ese mapeo es TRANS, la DMA del kernel no pasará.
  3. Señal de alarma concreta: `ufshcd-qcom 1d84000.ufshc: Adding to iommu group …` debe salir
     (~0,45 s), el probe real del UFS a 13,80 s y el `EXT4-fs (sda32): mounted…` a ~15,62 s. Si
     en su lugar aparecen errores de UFS/EXT4 o el mount no llega ⇒ **K7 mató al UFS aunque el
     probe del SMMU sobreviviera**. Ese es el criterio de éxito completo (ver §8).

---

## 6. Planes B/C (rankeados) si K7 muere esta noche

### 6.a ¿Existe una máscara que salte TODA escritura del reset? — SÍ (`uke_reset_mask=0`) y NO sirve

Con `mask=0` el reset solo ejecuta fase1 (sGFSR RMW). Pero quedan incondicionales:
- `arm_smmu_rmr_install_bypass_smr()` **escribe sCR0 con CLIENTPD=1** (arm-smmu.c:2858-2860) y el
  reset ya **no** lo revierte (fase5/7 omitidas) ⇒ la SMMU queda "deshabilitada" (semántica exacta
  de CLIENTPD=1 no documentada en el árbol; los comentarios mainline la usan como "apagar la SMMU"
  y "deshabilitar la SMMU hasta que el reset la reactive") de forma **permanente**. Mainline nunca
  deja ese estado ⇒ riesgo nuevo, no medido. **Peor que 0xc.**
- Siguen el quirk (S2CR(109) + CB70/CBAR70) y **todo el storm** (incluida la escritura que mató a K4c).
⇒ `mask=0` no elimina las escrituras letales y añade un estado inconsistente. **NO.**

Lo que sí tendría sentido como B1 (**K8, requiere recompilar**): partir `UKE_RESET_F567` en tres
bits (F5=RMW, F6=impl->reset/ACTLR×71, F7=tlb_sync+**write sCR0**) y probar `0x4|0x8` (F4+F5+F6 sin
la escritura final de sCR0) y `0x4` (solo TLBI). La muerte de K6 disparo 2 (tras el print de fase7)
apunta a F7 como sospechoso, y hoy es imposible aislarlo con la máscara actual (bit3 agrupa 5+6+7).

### 6.b `uke_protect_smr0=1` — semántica y riesgo

Semántica (arm-smmu.c:1661-1672 + helpers :413-431): si el idx elegido es un SME "vivo del BL"
según RAM (`smrs[idx].valid && s2crs[idx].count==0`), se reubica al primer índice libre **alto**
(bucle de `num_mapping_groups-1` hacia abajo, nunca el 0) y se escribe **allí**; SMR(0)/S2CR(0) no
se tocan. Riesgos:
1. **En K7 es código muerto**: con `uke_attach_log>=2` la rama `PRESERVAR` gana (comentario :355;
   código :1649-1672) ⇒ añadirlo a la cmdline **no cambia nada**. No gastar una variable.
2. Alcance limitado: solo protege índices que la RAM conoce como vivos; con `uke_smr_max=0`, solo
   el 0. El SMR del display (`handoff-smrs <0x1c00 0x02>`) está en un índice desconocido ⇒ el
   storm lo puede pisar.
3. Efecto colateral funcional: si el SID ya casaba con el SMR vivo, el HW verá **dos** SMR que
   casan el mismo SID (matching ambiguo; gana el de menor índice) ⇒ el maestro puede quedarse con
   la traducción del BL y no con la del kernel.
4. Escribe en índices altos (109↓): `SMR(109)` @0x9b4 **nunca se ha escrito** (solo se escribió+
   releyó `S2CR(109)` @0xdb4) ⇒ registro no verificado.

Recomendación: **no añadirlo**; si se quiere cubrir "todos los mapeos del BL", el camino es leer el
estado completo (SMR/S2CR/CB) en la **ventana temprana** — que es justo lo que K7 puede habilitar
en un K8 (con el storm ya no letal o protegido).

### 6.c Recuperación SOLO por sysfs (sin reflash) si el boot sobrevive

1. **Primero: salvar la evidencia** (el disco está podrido): `dmesg | grep -E "UKE-POKE|arm-smmu"`
   a un fichero en tmpfs y `scp`; `cat /sys/kernel/debug/devices_deferred`;
   `ls /sys/kernel/iommu_groups/`; `cat /sys/kernel/iommu_groups/*/devices`;
   `ls -l /sys/bus/platform/drivers/arm-smmu/`.
2. **Iterar params sin reflashear** (todos son 0644 en caliente): `echo` sobre
   `/sys/module/arm_smmu/parameters/{uke_reset_mask,uke_attach_log,uke_smr_max,uke_keep_boot,uke_smmu_probe}`.
   Ojo: los params solo se leen en el próximo probe ⇒ hay que re-probar con
   `echo 15000000.apps-smmu > /sys/bus/platform/drivers/arm-smmu/bind` (**desprendido en la
   tablet**, `nohup sh -c '…' &` — regla 2 del ESTADO-VIVO; `suppress_bind_attrs` fue eliminado a
   propósito, arm-smmu.c:3215-3220).
3. **NO hacer `unbind` del apps-smmu con el código actual**: `arm_smmu_release_device` →
   `arm_smmu_master_free_smes` **sin guarda de preservación** (BUG §7.1) ⇒ escribiría `S2CR(0)/
   SMR(0)` con BYPASS/FAULT y es candidato a matar la tablet. Si hay que deshacer algo, **reiniciar
   limpio** (el estado del HW no se puede restaurar por software).
4. La recuperación *efectiva* tras un bind malo es el ciclo de slots ya conocido:
   `set_active a`+`set_active b`+`reboot` (sin flashear) desde fastboot; y si el ABL cae a
   fastboot por `battery-soc-ok`, mismo baile.
5. No hay forma de "apagar" el SMMU desde sysfs una vez bindeado sin el unbind (peligroso). La
   mitigación es no dejar la tablet desatendida tras el bind.

### 6.d Estado del arte (web): handoff de mapeos del bootloader en arm-smmu

Buscado en esta sesión (no de memoria):
- **Mainline (lo que SÍ se fusionó):** `[PATCH v5 2/3] iommu/arm-smmu-qcom: Read back stream
  mappings` (serie de ~2020/2021; en el árbol v5.10+). Es exactamente el bucle que K3 instrumentó:
  lee SMRs y los marca `smrs[i].valid`, **pero inventa el S2CR** (`type=BYPASS, cbndx=0xff`,
  nuestros arm-smmu-qcom.c:610-621) ⇒ no preserva la *ruta* (CB) ni el CB. Ref.:
  `https://github.com/linux-mailinglist-archives/linux-kernel.vger.kernel.org.1/commit/672980ab25ab0cf876b3954a1775d4a6c14f05c3`
  (v5 2/3), y la versión de 5.10 estable `commit/4c12333c35304a5e82c00a65a7ef5cd7eb8dbd17`.
- **Lo que haría falta y NO está en mainline:** `[RFC 0/2] iommu: arm-smmu: Inherit SMR and CB
  config during init` + `[RFC 1/2] iommu: arm-smmu: Handoff SMR registers and context banks`
  (Bjorn Andersson, 5-jun-2019; "Heavily based on downstream implementation by Patrick Daly").
  Mecanismo propuesto (leído del parche): añade `bool handoff` a `struct arm_smmu_s2cr`; lee el
  estado de los SMRs **y** los CBs asociados (`arm_smmu_read_smr_state()`); reemplaza el asignador
  de CB por `__arm_smmu_alloc_cb(dev)` que, si el fwpec del device casa con un SMR marcado
  `handoff`, **toma el cbndx del bootloader** y limpia las demás referencias a ese banco
  (`s2crs[i].cbndx = 0; handoff=false; count--`). Nota del propio RFC: "Any existing page-tables
  will be discarded". **Nunca se fusionó** (solo cayó la parte de lectura). Referencias (archivo de
  listas, mirror):
  `https://github.com/linux-mailinglist-archives/iommu.lists.linux-foundation.org.0/commit/8a48ba6f916495186c0c67a677f09d86896bbe90`
  y `…/linux-kernel.vger.kernel.org.0/commit/1101448015dff3a87545482d8f567081ae9b6bc2`;
  búsqueda: `lore.kernel.org/linux-iommu/?q=handoff`.
- **Downstream Qualcomm/Android (el patrón "portable" real):** propiedad DT `qcom,handoff-smrs`
  (¡nuestro DT la tiene: `<0x1c00 0x02>`, base.dts:13186!) y en el kernel:
  - `arm-smmu: use smr match for handoff-smrs` — cambia el handoff de "por índice de SMR" a "por
    match (id/mask)", porque el índice "could mismatch between ABL and HLOS".
  - `arm-smmu: Correct the index for handoff smrs` (fix del anterior; kfence detectó el bug).
  - `drivers: iommu: arm: arm-smmu-v3: pkvm: preserve handoff streams during EL2 init` — "TZ
    pre-programs NS Streams in SMR/S2CR with bypass mode"; durante el init de pKVM en EL2 se
    resetean los SMR/S2CR NS creando una ventana de fault; el parche **lee `qcom,handoff-smrs` y
    se salta el reset para los SIDs que casan**. Repos de ejemplo:
    `https://github.com/LineageOS/android_kernel_oneplus_sm8850/commit/5187a0fde8d98f8beaaeeeab1cebe87b5aeb4057`.
  - Otro commit relacionado: `ARM: dts: msm: Remove stale display handoff-smrs and reset-smg`
    (existe también la propiedad `reset-stream-mapping-groups` en el driver vendor).
- **Conclusión para K8:** hay mecanismo portable y es el del stack vendor: **handoff dirigido por
  DT** — leer el SMR/S2CR/CB que el BL dejó para los SIDs listados (o para todos los que la RAM
  pueda leer sin morir), marcar esos índices/CBs como "del firmware" y **no escribir nunca en
  ellos** (saltarse SMR/S2CR/CB del reset y del attach). Es el RFC de 2019 + `qcom,handoff-smrs`.
  Nuestro árbol ya tiene la mitad (lectura de SMRs); falta persistir el S2CR/cbndx y el CB.

---

## 7. Errores y bugs vistos en el código UKE-POKE (honestidad brutal)

| # | gravedad | qué | cita |
|---|---|---|---|
| 7.1 | **ALTA (mina)** | `arm_smmu_master_free_smes()` escribe el SME liberado **sin ninguna guarda** (`arm_smmu_write_sme(smmu, idx)`); un `release_device`/detach del ufshc escribiría `S2CR(0)`=BYPASS/FAULT y podría matar la tablet. Asimetría con la preservación del alloc. | arm-smmu.c:1752-1765 (vs :1685-1700) |
| 7.2 | **ALTA (informe)** | La instrumentación de `arm_mmu500_reset` **no tiene miga por CB** en el bucle CPRE de 71 CBs (`read+write CB_ACTLR`); con `CONFIG_ARM_SMMU_MMU_500_CPRE_ERRATA=y` una muerte ahí deja como última línea el print de ID7/sACR y el índice es irrecuperable. En K6 (1er disparo) el asesino sí tuvo miga (fase3), pero F6 es hoy un agujero. | arm-smmu-impl.c:118-145 |
| 7.3 | **MEDIA** | `uke_smr_max=0` deja la RAM **ciega a los SMR 1..109** pero `find_sme` los reparte como "libres" ⇒ el attach escribe índices potencialmente vivos del BL (medido: qcedev idx 1 = muerte K4c). El param "protege" el 0 y **agrava** el resto (el barrido completo es el que lee la verdad, y es el que mata por algún índice). Trade-off no documentado como tal. | arm-smmu-qcom.c:583-588 + arm-smmu.c:1536-1575 |
| 7.4 | MEDIA | El bitmap `uke_preservar` es de 64 bits con guardas `i < 64`; un maestro con >64 stream-ids (no es el caso: máximo 5) pasaría la preservación en RAM pero **se escribiría** el SME protegido en el 2º bucle (la guarda del `continue` es `i<64`). Latente. | arm-smmu.c:1603-1606, :1655-1658, :1690-1693 |
| 7.5 | MEDIA | `uke_reset_mask_set()` imprime "efectivo" como `uke_reset_mask & 0xf` sin consultar `uke_smmu_es_apps()`/`keep_boot`; el texto puede engañar en el análisis del log (afortunadamente con `tocado` coincide con el real). | arm-smmu.c:257-263 vs :277-289 |
| 7.6 | BAJA | `arm_smmu_write_sme()` imprime la miga y **no** flushea; el flush vive en los llamantes (attach: :1734/:1823; volcado: :511). En el reset fase2 (si se activa) y en `master_free_smes` no hay flush ⇒ pérdida de la última línea. | :1447-1471 |
| 7.7 | BAJA | `uke_dump_bl_state()` itera `i=1..` leyendo SMR(i) de los índices que la RAM marque válidos; con `uke_smr_max=-1` (default) eso re-lee todo el banco — la clase de acceso que mató a K2. Hoy lo salva smr_max=0, pero el "default" es el peligroso. | :492-510 |
| 7.8 | BAJA (informe) | `arm_mmu500_reset` y `qcom_smmu_tlb_sync` no imprimen flush; `test_smr_masks` con keep_boot fija `smr_mask_mask = 0xffff` (campo real 15 bits) — valor no medido, sobre-permisivo en la validación del attach. | arm-smmu.c:1494-1500 |
| 7.9 | INFO | Bugs ya corregidos que conviene no re-introducir: (a) `of_property_read_u32` para `reg[1]` (leía siempre el índice 0 ⇒ defer nunca disparaba): documentado en :2913-2923; (b) `FIELD_GET(ARM_SMMU_SMR_MASK)` sin limpiar VALID (K3/K4 imprimían mask=0x8000): corregido con `uke_smr_mask_leido()` :460-463. | — |
| 7.10 | INFO | El "X9WAVE" del fork (dd.c:108-118) es el que procesa la lista de diferidos en la ola temprana; sin él, la arming por cmdline habría caído a los 3,6 s (con consola). **Es un acoplamiento no documentado** del fork con el experimento. | dd.c:83-143 |

---

## 8. Trazado K7 esperado, paso a paso (textos literales, en orden)

Captura: consola robusta + `dmesg` (si sobrevive). Los bloques marcados `[TREN-1]` ocurren a
**~0,445 s (SIN consola serie viva: solo ring buffer)**.

```
# --- start_kernel / parse_args (0,0x s) [cmdline en orden izq→der] ---
arm-smmu: UKE-POKE: uke_keep_boot=1 (solo apps-smmu): fase2 SMR/S2CR OMITIDA y test_smr_masks sin tocar HW
arm-smmu: UKE-POKE: uke_attach_log=2 (0=nada; 1=miga por maestro con flush antes de escribir + volcado BL; 2=ademas PRESERVAR los indices vivos del BL sin escribir)
arm-smmu: UKE-POKE: arming en caliente: uke_smmu_probe=1
arm-smmu: UKE-POKE: uke_reset_mask=12 (0xc, efectivo 0xc) fijado a mano: fase2=0 fase3=0 fase4=1 fase5-7=1 (1=ejecutar)
# (uke_smr_max no imprime en parseo: no tiene .set)

# --- primer probe del driver (~0,33 s) ---
arm-smmu: UKE-POKE: arm_smmu_device_probe ENTRANDO, dev=15000000.apps-smmu
arm-smmu: UKE-POKE: apps-smmu @<ptr> base=0x15000000: primer probe DIFFERIDO para que el reintento caiga con la consola viva

# --- [TREN-1] 1ª re-entrada ~0,445 s: PROBE REAL (aquí se juega todo, sin consola) ---
arm-smmu: UKE-POKE: arm_smmu_device_probe ENTRANDO, dev=15000000.apps-smmu
arm-smmu: UKE-POKE: apps-smmu: REINTENTO del probe, consola ya viva. Lo que viene a continuación es el probe de verdad.
arm-smmu: UKE-POKE: apps-smmu: -> arm_smmu_device_cfg_probe (lectura IDR0/1/2 y PIDR; y qcom_smmu_cfg_probe ESCRIBE el S2CR del ultimo grupo y lo relee, que es el test del bypass quirk)
arm-smmu 15000000.apps-smmu: probing hardware configuration...
arm-smmu 15000000.apps-smmu: SMMUv2 with:
arm-smmu: UKE-POKE: ARMADO — probe real del apps-smmu, lo que sigue puede colgar
arm-smmu: UKE-POKE: cfg_probe ID0=0x4c017e6e (SMS=110 groups)
arm-smmu 15000000.apps-smmu: 	stage 1 translation
arm-smmu 15000000.apps-smmu: 	coherent table walk
arm-smmu 15000000.apps-smmu: 	stream matching with 110 register groups
arm-smmu: UKE-POKE: cfg_probe ID1=0x60000047 pgshift=12 NUMPAGENDXB=6 CBs=71; CB base=0x80000 (mmio=2097152 B)
arm-smmu 15000000.apps-smmu: SMMU address space size (0x100000) differs from mapped region size (0x200000)!
arm-smmu 15000000.apps-smmu: 	71 context banks (0 stage-2 only)
arm-smmu: UKE-POKE: cfg_probe ID2=0x00005111
UKE-POKE: qcom_cfg_probe: VOY a ESCRIBIR S2CR(0xdb4) reg=0x000100ff
UKE-POKE: qcom_cfg_probe: relectura=0x000200ff (TYPE=2; quirk=SI)
UKE-POKE: qcom_cfg_probe: leyendo SMR(0..0) [uke_smr_max=0 grupos=110]
UKE-POKE: SMR[0] -> readl(0x800)
UKE-POKE: SMR[0] = 0x80000060 (valid=1 id=0x60 mask=0x0 [mask sin el bit VALID])
UKE-POKE: qcom_cfg_probe: SMR loop OK (leidos=1 validos=1)
arm-smmu 15000000.apps-smmu: 	Supported page sizes: 0x61311000
arm-smmu 15000000.apps-smmu: 	Stage-1: 36-bit VA -> 36-bit IPA
arm-smmu 15000000.apps-smmu: 	preserved 0 boot mappings
arm-smmu: UKE-POKE: BL estado idx=0: SMR(0) HW=0x80000060 (valid=1 id=0x60 mask=0x0) S2CR(0) HW=<NO LEIDO (letal #P13)> (s2cr0=0)      [+pr_flush]
arm-smmu: UKE-POKE: apps-smmu: -> arm_smmu_device_reset (SMR/S2CR x110, CBAR/SCTLR/FSR x71, TLBIALLH, RMW de sCR0, y arm_mmu500_reset con CB_ACTLR si CONFIG_ARM_SMMU_MMU_500_CPRE_ERRATA)
arm-smmu: UKE-POKE: reset fase1 sGFSR (siempre)
arm-smmu: UKE-POKE: reset fase2 OMITIDA (uke_keep_boot=1, uke_reset_mask=0xc): NO se escribe NI UN SMR ni UN S2CR; los registros del bootloader quedan como estan
arm-smmu: UKE-POKE: reset fase3 OMITIDA (uke_reset_mask bit1=0): no se toca CBAR/SCTLR/FSR de los 71 CBs (los CBs que el bootloader use no se desactivan)
arm-smmu: UKE-POKE: reset fase4 TLBIALLH/TLBIALLNSNH
arm-smmu: UKE-POKE: reset fase5 RMW de sCR0
arm-smmu: UKE-POKE: reset fase6 impl->reset (arm_mmu500_reset)
arm-smmu: UKE-POKE: apps-smmu: -> arm_mmu500_reset: lectura ID7 y RMW de sACR(CACHE_LOCK, SMTNMB, S2CRB_TLBEN)
arm-smmu: UKE-POKE: reset fase7 tlb_sync_global + write sCR0
arm-smmu: UKE-POKE: test_smr_masks OMITIDO (uke_keep_boot=1): sin leer ni escribir SMR; streamid_mask=0x7fff smr_mask_mask=0xffff (campo completo, no medido)
# --- storm de attach (iommu_device_register → bus_iommu_probe) ---
UKE-POKE: attach: find_sme(dev=1de0000.qcedev sid=0x480 mask=0x0) -> 1
UKE-POKE: attach: find_sme(dev=1de0000.qcedev sid=0x481 mask=0x0) -> 2
UKE-POKE: attach: ESCRIBIR SME idx=1 dev=1de0000.qcedev -> SMR=0x00080480 (id=0x480 mask=0x0 valid=1) | S2CR nominal=0x00010000 (type=1 cbndx=0) [impl->write_s2cr: quirk qcom reescribe]     ← [pr_flush]
arm-smmu: UKE-POKE: write_sme idx=1 S2CR(0xc04) type=1 cbndx=0 + SMR(0x804) id=0x480 mask=0x0 valid=1
UKE-POKE: qcom write_s2cr idx=1 quirk: type=0 cbndx=70 reg=0x00000046 en 0xc04
   ⟵ SI LA CONSOLA MUERE AQUÍ: asesino = primer SME write del storm (S2CR(1) 0xc04).
      (el ring buffer se pierde si hay wedge+panic; solo queda el LAST-POKE pintado y el timing)
# … resto del storm (3º id del qcedev 0x483 -> idx 3; xhci 0x40; gpi/geni; vidc; mdss 0x1c00 -> idx libre;
#    fastrpc 0xc01..; cam_smmu; cvp; ipa; wifi -> CB0 asignado+programado) …
platform …: Adding to iommu group N            (uno por grupo)
# --- ufshc (más tarde en el storm) ---
UKE-POKE: attach: find_sme(dev=1d84000.ufshc sid=0x60 mask=0x0) -> 0
UKE-POKE: attach: dev=1d84000.ufshc sid=0x60 mask=0x0 -> find_sme elige idx=0, SME VIVO DEL BOOTLOADER (id=0x60 mask=0x0 valid=1)
UKE-POKE: attach: SME idx=0 PRESERVADO (BL vivo): NO se escribe; 1d84000.ufshc queda con el mapeo del bootloader
UKE-POKE: attach: SME idx=0 PRESERVADO (BL vivo): se omite write_sme (no se toca SMR/S2CR)
# --- evidencia de supervivencia (a partir de 3,56-3,60 s) ---
[ 3.560963] Run /ukeinit as init process
[ 3.572048] printk: legacy console [ttyGS0] enabled
… ssh/consola vivos ⇒ dmesg | grep UKE-POKE  (recupera TODO el tren 1 del ring buffer)
[13.7998] ufshcd-qcom 1d84000.ufshc: deferred probe timeout, ignoring dependency
[15.61xx] EXT4-fs (sda32): mounted filesystem … ro            ⟵ prueba de que el UFS sobrevivió
```

Árbol de lectura del resultado:

| desenlace | lectura |
|---|---|
| wedge mudo ~0,45 s + bucle de panic ~30 s | El probe temprano **no basta** con las fases seguras ⇒ hipótesis "registro/índice vivo protegido" gana (o el firmware/TZ usaba ese SMR). K8: hace falta aislar F7 (partir bit3) y/o handoff dirigido. Foto al panel para leer el LAST-POKE. |
| sobrevive el reset pero muere en el 1er SME (qcedev) | Igual que K4c ⇒ el asesino es el SME write, no la fase7. K8: no escribir índices "libres" a ciegas (leer el banco completo en la ventana temprana = la pregunta de K8). |
| sobrevive el storm pero el UFS no monta (13,8-15,6 s) | El S2CR(0) del BL preservado **no** es compatible con el sCR0 reescrito o con DMA física ⇒ hay que preservar también el S2CR/CB (RFC 2019) o no tocar sCR0. |
| arranca, SSH, rootfs montado, `card0` tras bind del DPU por sysfs | **ÉXITO**: la ventana temporal era la diferencia. Siguiente: modetest + foto (§6c). |

---

## Anexo A — Los 56 nodos del DT con `iommus = <&apps_smmu …>` (orden del DT)

Generado con un parser propio sobre `/var/tmp/r1dt/base.dts` (phandle apps_smmu=0x129) +
`s258.dts` para el wifi. `mask` es el 3er argumento del fwpec.

| # | nodo | sid/mask |
|---|---|---|
| 1 | `soc/tmc@10048000` (AMBA) | 0x4e0/0x20, 0x4c0/0x20 |
| 2 | `soc/tmc@1004f000` (AMBA) | 0x500/0x00 |
| 3 | `qcedev@1de0000` | 0x480/0x00, 0x481/0x00 |
| 4-5 | `qcedev@1de0000/qcom_cedev_{ns,s}_cb` | 0x481/0x00, 0x483/0x00 |
| 6 | `sdhci@8804000` | 0x140/0x00 |
| 7 | **`ufshc@1d84000`** | **0x60/0x00** |
| 8-12 | `iommu_test_device/usecase0..4_apps*` | 0x400/0x00 (×5) |
| 13 | `ssusb@a600000/dwc3@a600000` | 0x40/0x00 |
| 14 | `usb_audio_qmi_dev` | 0x100b/0x00 |
| 15 | `qcom,gpi-dma@a00000` | 0xb6/0x00 |
| 16 | `qcom,qupv3_0_geni_se@ac0000` | 0xa3/0x00 |
| 17 | `qcom,gpi-dma@800000` | 0x436/0x00 |
| 18 | `qcom,qupv3_1_geni_se@8c0000` | 0x423/0x00 |
| 19 | `spf_core_platform/qcom,msm-audio-ion` | 0x1001/0x80, 0x1061/0x00 |
| 20-24 | `qcom,vidc@aa00000/*_cb` | 0x1947/0, 0x1940/0, 0x1944/0, 0x1941/0x04, 0x1943/0 |
| 25 | **`qcom,smmu_sde_unsec_cb`** (display) | **0x1c00/0x02** (= `qcom,handoff-smrs`) |
| 26 | `qcom,smmu_sde_sec_cb` | 0x1c01/0x00 |
| 27-43 | `qcom,msm_fastrpc/qcom,msm_fastrpc_compute_cb1..17` | 0xc01..0xc09/0, 0x1003+0x1043, 0x1004+0x1044, 0x1005+0x1045, 0x1006+0x1046, 0x1007(0x40)+0x1067+0x1087, 0xc0c, 0xc0d, 0xc0e |
| 44-48 | `qcom,cam_smmu/msm_cam_smmu_{ife,jpeg,icp,cdm,cre}` | 0x800/0x20; 0x18a0; 0x1820+0x18c0+0x1800+0x1840+0x1880; 0x1860; 0x18e0 |
| 49-52 | `qcom,cvp@ab00000/cvp_*_cb` | 0x1920, 0x1924, 0x1923, 0x1920 |
| 53-56 | `qcom,ipa@3e00000/ipa_smmu_{ap,wlan,uc,11ad}` | 0x4a0, 0x4a1, 0x4a2, 0x4a4 |
| 57 | `qcom,wcn6750` (overlay s258, `compatible="qcom,wcn6750-wifi"`) | iommu del overlay (`__symbols__ apps_smmu`, s258.dts:3772) — **único dominio traducido** por `def_domain_type` |

## Anexo B — Fila de pre-registro propuesta para #P17 (K7)

> **#P17 — K7 (arming por cmdline, fases 0xc)** · artefacto `build/bootimg/boot-ukek7.img`
> sha256 `1c1a090b…` (100 663 296 B; kernel idéntico a K6) · cmdline exacta la de §0 · **ventana real:
> probe a los ~0,445 s** (tren-1 del deferred; consola `ttyGS0` solo desde 3,572 s) · evidencia de
> éxito: **sobrevive + `dmesg` recuperable a ≥3,6 s** con la traza de §8 y `EXT4-fs (sda32): mounted`
> a ~15,6 s + `Adding to iommu group` del ufshc + `card0` tras bind del DPU · evidencia de muerte
> temprana: USB/consola mudos desde ~0,5 s, `hung_task_panic` a los ~20 s y bucle de panic (~30 s);
> leer foto del panel (LAST-POKE) · rollback: `boot_b` = `build/backup-par-bueno/boot_b-lee.img`
> (`ffff8c51…`) + baile de slots; dtbo_b no se toca (s258) · gates: batería ≥3,7 V, captura robusta
> corriendo ANTES del flash, `e2fsck` en frío pendiente por el ext4.

---

### Resumen de correcciones a la cmdline K7

**Ninguna a los valores.** No añadir `uke_protect_smr0` (código muerto con `attach_log=2`), no
cambiar `uke_reset_mask=12` (es el conjunto medido superviviente), no tocar `uke_smr_max=0`. Lo
único que cambia es la **expectativa** (0,445 s, sin consola) y las precauciones operativas
(captura robusta desde el arranque, foto al panel, vigilar el bucle de panic, rescue a mano).
