# AUDIT-RAZONAMIENTO #541 — auditoría de la cadena de conclusiones del día GPU (C1–C7)

**Fecha**: 7-oct-2026 (noche). **Autor**: auditor de razonamientos. 100 % offline — tablet NO tocada
(cero adb/fastboot; en fastboot).
**Alcance**: revisión independiente de C1–C7 (las conclusiones "verificadas" del 6–7 oct) contra el
código real (`k52-tree`), los bootimgs (cmdline extraída del header), los logs de consola
(`uke-console2.log` 3,88 GB, `uke-sesion-console.log`), el binario del fw, el DT fusionado/vendor y
el ledger (#535–#541). Cada veredicto cita la evidencia primaria, no la narrativa previa.

**HALLAZGO ESTRUCTURAL PREVIO A TODO**: el INV #540 (`docs/historia/revision/INV-CM3-FALLO-20261007.md`) razonó sobre
`uke_gmu_shared` con el **default del módulo (=1 en k55–k57)**, pero TODOS los boots GPU-on
k55/k56/k57/k58 llevan **`msm.uke_gmu_shared=0` EN LA CMDLINE** (extraída del header de los
bootimgs en disco, offset 64: `boot-uke-k55-cbwin/k56-cm3dbg/k57-gpuon/k58-gmuown.img`), y los
logs muestran el attach del dominio propio ejecutándose (`UKE-K38: attach dev=3d68000.qcom,gmu
id[0]=0x00000005 (sid=5) -> cbndx=1`, `UKE-K32: init_context dev=3d68000.qcom,gmu`,
`UKE-K39: fault handler instalado en el dominio propio de 3d68000.qcom,gmu` — sin línea K13 de
error ⇒ attach rc=0). Esto ya lo había señalado docs/historia/revision/CRITICA-GPU-PLAN-20261006.md (C0.1) el 6-oct; el
INV #540 (7-oct) **regresó** a la lectura por default. Varios veredictos de #540 quedan tocados.

---

## 1. VEREDICTOS C1–C7

### C1 — "El dtcm-magic STALE demuestra que el CM3 no ejecuta" ⇒ la REFUTACIÓN de #540 es CORRECTA. **CONFIRMADO** (verificado byte-level por este auditor)

- Binario: `build/pkg/uke-gpu-firmware/gen71100_gmu.bin` (md5 `a02e73fe…`). En file-off **0x13b00**
  hay un bloque cuyo header es `addr=0x10007fdc, size=0x18` y cuyo dato contiene, en file-off
  **0x13b14**, la palabra LE `01 00 05 40` = **0x40050001** (verificado con xxd por este auditor).
- El parser (`a6xx_gmu.c:1329-1410`): para a7xx `dtcm_base=0x10004000`; el bloque cae en
  `reg_offset=(0x10007fe0-0x10004000)>>2=0xff8` ⇒ se escribe en `REG_A6XX_GMU_CM3_DTCM_START+0xff8`
  — **exactamente la dirección que `a6xx_gmu_start()` lee en S0** (`gmu_read(gmu,
  REG_A6XX_GMU_CM3_DTCM_START + 0xff8)`, :663).
- Orden: `a6xx_gmu_fw_start` COLD ⇒ `a6xx_gmu_fw_load()` (H7, :1445) → P1–P3 (:1459-1533) →
  `a6xx_gmu_start(gmu)` (:1536) ⇒ **el magic se escribe ANTES de S1-rst1 y antes de leerse**.
- Evidencia viva: `dtcmR val=0x40050001` en TODOS los boots capturados (K17/K58 prints,
  `uke-console2.log` ×5+, `uke-sesion-console.log:114892`), idéntico cada vez = contenido de la
  imagen, no de una ejecución.
- Confirmación adicional: el print `UKE-CM3DBG: dtcm-magic=0x40050001 mask=0x1ff reset_val=0x100`
  (`uke-sesion-console.log:114894`) prueba que el valor alto elegía la rama WARM; con un COLD real
  (`0xbabeface & 0x1ff = 0x0ce ≠ 0x100`) el poll habría FALLADO incluso con un CM3 perfecto.
- Matiz (no cambia el veredicto): "STALE SIEMPRE" vale para COLD con fw_load; en un warm re-arm sin
  `fw_load` el +0xff8 sí retendría el valor de la ejecución anterior (sería informativo).

### C2 — "SME(1) TRANS→CB1 = igual que el vendor = S1 correcto" ⇒ **REFUTADO en su mitad clave**

- **Nuestro CB1 NO era el dominio default vacío** en ningún boot GPU-on desde k55: la cmdline lleva
  `msm.uke_gmu_shared=0` (bootimgs k55/k56/k57/k58, verificado) ⇒ `a6xx_gmu_memory_probe`
  (`a6xx_gmu.c:2123-2142`) hace `msm_iommu_new(gmu->dev, 0)` + attach. Logs: `UKE-K38: attach …
  sid=5 -> cbndx=1`, `UKE-K32 init_context`, `UKE-K39 fault handler instalado en el dominio propio
  de 3d68000.qcom,gmu`, sin K13-error ⇒ **CB1 = dominio PROPIO del GMU, con tablas** (el fw-map
  `icache iova=0x4000 dummy=0x60000000 hfi=0x60008000` vive en ESE dominio). La lectura #540
  ("CB1 vacío por of_dma_configure") describe el código bajo `shared=1` — que no fue el estado de
  ningún boot k55+. (El default-domain vacío sí existiría como estado transitorio antes del attach,
  que lo REEMPLAZA: `iommu.c:2360` permite sustituir al default.)
- **¿CB1 "igual que el vendor"?** Solo en el dato visible (SID5→CB1 TRANS). El CONTENIDO del CB1
  vendor NO está capturado: ni `dmesg-gpu.txt` ni el debugfs kgsl (`globals` trae la entrada
  "GMU SMMU INFO" con direcciones a 0) contienen un volcado de SCTLR/TTBR0 vendor. La inferencia
  razonable (no medida): el vendor Android funciona end-to-end con el MISMO binario cuyo cuerpo
  vive en IOVA 0x4000 consumido por el CM3 vía SMMU ⇒ su banco para SID5 tenía tablas válidas.
  Además, ni siquiera sabemos que el vendor use CB1 (nuestra asignación CB0=GPU/resto desde CB1 es
  de `arm-smmu-qcom.c:332-351` upstream; el vendor DT tiene `qcom,qsmmu-v500`+`qcom,adreno-smmu`
  en `kgsl-smmu@3da0000` y un driver propio `qcom,kgsl-smmu-v2` para gfx3d_user/gfx3d_secure).
- **No confundir con los reads del K19**: las líneas `CBpage(n) … SCTLR M=0 TTBR0=0xf7ff9197…`
  (`uke-console2.log:625618112+`) son BASURA de la ventana +0x20000 (TTBR0s no alineados) — ese
  instrumento NO mide el contenido real de ningún CB (ver C4/C7).

### C3 — "uke_gmu_shared=0 (k58) debía arreglar CB1; k58 congeló igual" ⇒ **NO-DETERMINADO (y el experimento fue un NO-OP)**

- k58 no cambió el dominio: k55–k57 ya corrían `gmu_shared=0` por cmdline (§ hallazgo estructural).
  El cambio REAL de k58 fue el poll (branch COLD fija 0xffffffff/0xbabeface) y prints. Por tanto el
  freeze de k58 **ni refuta ni confirma** la teoría "CB1 vacío": esa teoría (a) ya estaba mal
  planteada (C2) y (b) no fue puesta a prueba por k58.
- Predicción de #540 para k58 ("attach crea dominio nuevo → CB1 con tablas → S4-pollOK") era
  correcta como código pero DE MAS: eso ya ocurría desde k55 sin que el CM3 viviera.
- **Problema de evidencia nuevo (grave)**: k57 y k58 no dejaron NADA por consola — el watcher
  (`uke-console2-trz.log`) registra el último ACM el 7-oct **15:30:49** y después NINGÚN "abierto"
  (k57 flash ~15:31; k58 flash ~20:4x; fb-ud6/ud7 22:41/22:47 son userdata en fastboot). En TODOS
  los boots GPU-on anteriores el gadget ACM subía a ~0,04 s de kernel y la consola capturaba desde
  [0.03x]. Que no haya aparecido ACM en k57/k58 significa que **ninguno de los dos kernels llegó a
  subir el gadget** (muerte <~0,04 s de kernel, o el ABL no llegó a lanzar el kernel — quirk
  reboot/continue #537). El "k58 freeze seco 14 s tras continue" es observación del operador, NO
  está vinculado por evidencia a que k58 llegara siquiera a S3/GPU-on (~4,1 s). **Conclusión: el
  dato k58 no discrimina nada sobre el CM3.**
- El vector de reset del CM3 (C3 pregunta por él): ITCM[0]=0x10007f80 (MSP), ITCM[1]=0x00000105
  (reset Thumb @0x104) — **el vector y el primer código ejecutan DESDE ITCM (físico, sin SMMU)**;
  el primer fetch por SMMU ocurre al saltar al cuerpo @0x4000+ (icache), es decir microsegundos
  tras S3-rst0. K44 B lo confirma escrito y legible.

### C4 — "El freeze seco no lo captura nada" ⇒ **CONFIRMADO como físicamente plausible (con mecanismo acotado)**

- Ventana de muerte medida: en TODOS los boots capturados que ejecutaron S3-rst0 (29 prints
  `S3-rst0` en `uke-console2.log` + 1 en `uke-sesion-console.log`), lo siguiente que aparece es el
  banner de un kernel nuevo ([0.000000]) o silencio — **nunca** un S4-pollFAIL/OK, H8-cm3FAIL,
  "GMU firmware init failed", ni texto de panic. El S3-rst0 lleva `pr_flush` inmediato; el poll
  dura 100 ms ⇒ **la muerte ocurre dentro de la ventana del poll (<~0,1 s tras soltar el CM3)**.
- ¿Por qué nada salta?: `hung_task_panic` = **0 efectivo** (la cmdline lo pone a 1 y LUEGO a 0;
  el último token gana — lo entendió bien CRITICA-OPS) y de todos modos son 20 s; el softlockup
  imprime a ~2×thresh (≈20 s) y no panic por defecto — **pierde la carrera contra el reset
  externo**; el sysctl panic-shield del rootfs v8.1 no llega a aplicarse (GPU-on a ~4 s, en
  initramfs; systemd/sysctl es muy posterior) y además un wedge de bus no genera oops. Todos los
  detectores llegan tarde o desarmados: **correcto**.
- Agente del reset: `qcom_wdt 0.watchdog: error -EBUSY … probe failed -16` en TODOS los boots
  (p.ej. `uke-console2.log:632393276` [0.373987]) ⇒ **Linux no tiene watchdog propio**; el reset
  duro a los ~10–14 s (k58: "14 s tras continue" ≈ 5–7 s de boot + ~7–9 s de hang) es coherente con
  un WDT externo (ABL/AOP) que la CPU colgada deja de alimentar. No demostrado (no hay pstore tras
  hard reset), pero es el único cuadro completo.
- ¿"CPU viva que no nota nada"? **No**: la evidencia es que el GPU-path muere en el primer readl
  del poll (en 29/29 boots nada imprime tras S3) — y cuando el sistema sigue respirando es porque
  el probe del GMU murió ANTES de S3 (caso B: el abort deja el boot vivo, shell initramfs
  imprimiendo errores devfreq durante ~35 min en la cola de `uke-console2.log`). En los boots con
  S3 ejecutado no hay señal de sistema vivo: o reinicio duro, o probe colgado sin salida. Ambos
  cuadros requiren transacción NO-completada (hang) en la isla GPU, no un "error limpio".

### C5 — "k55/k56 pasaron S3 por timing de prints" ⇒ **REFUTADO (falso en su premisa)**

- k55/k56 **nunca pasaron S3**: en los boots que sobrevivieron, el volcado K19 recibió un
  **external abort 0x96000010** leyendo la ventana CB `+0x20000` (`Internal error: synchronous
  external abort … pc: uke_k19_dump_kgsl+0x3f4` — `uke-console2.log:632393455+`; forklog k56 vía
  ledger #539) y eso **mató el probe ANTES de S3-rst0**. La máquina no "aguantó el S3": el S3 no se
  ejecutó. No hay NI UN boot con S3 ejecutado y máquina viva (29/29 murieron en la ventana del
  poll).
- La "raza de prints" (#538/#540) y el "estado de energía heredado del dominio GMU" (alternativa
  C5) apuntan ambas al sitio equivocado: la variable que decide la vida del boot es **cómo responde
  la ventana CB de la kgsl-smmu a esa lectura** — y esa respuesta es BISTABLE en los logs brutos:
  basura coherente en SME + CBpages basura (dump completa → S3 → muerte; líneas 625,6M) o external
  abort (probe muerto → máquina viva; líneas 632,39M). Un tercer desenlace (hang silencioso de la
  propia lectura) es posible por física de bus pero NO está capturado en bruto. Es inestabilidad de
  alimentación/clock de la interfaz SMMU, no del dominio de energía del GMU. Sospechoso físico
  identificado (hallazgo #540 §2, ahora con más peso): **los ids de clock del nodo `kgsl-smmu` en
  el DT fusionado son vendor** (`<gpucc 0x11> <gcc 0x20> <gcc 0x21> <gpucc 0x02>`; m270.dts:16349)
  y con nuestro header `qcom,palawan-gpucc.h` (HLOS1_VOTE=0xf, AHB=0x0; 0x11=HUB_CLK_SRC,
  0x02=CRC_AHB) **arm-smmu habilita gates equivocadas y deja HLOS1_VOTE_GPU_SMMU apagada** —
  exactamente la gate que el vendor usa para la interfaz del SMMU (clk-summary vendor: consumer
  `3da0000.kgsl-smmu`). Fix dtbo-only (renombrar ids), barato y no probado aún.

### C6 — "hub=200 MHz aplicado" ⇒ **NO-DETERMINADO (y FALSO para todos los boots con consola)**

- Los 26 prints `UKE-CM3DBG: clks core=…` de `uke-console2.log` dicen **`hub=400000000` TODOS** —
  el fix C3 (pedir 200 para a740-family; código actual `a6xx_gmu.c:1824-1826`, tabla
  `F(200000000, P_GPLL0_OUT_MAIN, 6)`, gpucc-palawan.c:156) **no estaba en ningún kernel k53–k55**.
  El único "hub=200000000" es el print K56-A del forklog (segunda mano, ledger #539; no hay log
  crudo en el PC). k56/k57/k58 sí llevan el fix en código, pero de k57/k58 no hay salida alguna.
- Vendor: `clk-summary` Android — `gcc_gpll0 = 600 MHz`, `gpu_cc_hub_clk_src = 200 MHz` (⇒ vendor:
  gpll0/3). Nuestro: para obtener 200 con pre_div 6 fijo hace falta **gpll0=1200 MHz** ⇒ nuestro
  gpll0 corre (o corrió en k56) al DOBLE que el vendor. Sin `clk_summary` de nuestros boots (no hay
  userspace en los congelados) no se puede medir directo: inferido del print hub=200 con div 6.
- La teoría del "glitch al enable por pre_div 6": **sin ninguna evidencia** a favor o en contra. Y
  el dato duro nuevo la debilita como eje del problema: los boots con hub=400 murieron IGUAL que se
  congelaron k57 (hub=200 en código) — el rate del hub no separa vivos de muertos. Queda como
  divergencia- del-vendor-a-corregir (gpll0/div), no como causa identificada.

### C7 — "dummy/icache en CB0 pero el CM3 va por CB1 → abort silencioso → wedge → freeze" ⇒ **premisa REFUTADA; la mecánica queda como CANDIDATA VIVA corregida**

- Premisa falsa para k55+: con `gmu_shared=0` el icache/HFI/log/dummy se mapean en el **dominio
  propio del GMU (CB1)** — el MISMO banco por el que fetch-ea el CM3 (K38 attach + fw-map en los
  logs). No hay desajuste CB0/CB1.
- La objeción "k56 SÍ imprimió K44 y el trace tras S3, luego el readl del poll no se cuelga" es
  **inválida**: k56 no llegó a S3 (el abort del dump mató el probe antes). No existe boot alguno con
  S3 ejecutado y poll completado.
- Lo que SÍ aguanta la evidencia es la mecánica general: S3 suelta el CM3 → fetch del vector por
  ITCM (OK físico) → primer fetch fuera de ITCM (@0x4000 vía SID5/CB1) → si la TCU/TBU no completa
  la transacción (gate HLOS1_VOTE apagada / isla medio-viva — ver C4/C5), la isla GPU queda wedged
  → el primer readl del poll cuelga la CPU → sin oops ni panic → reset externo o wedge permanente.
  La ausencia de fault-print del K39 (instalado en el dominio propio; `*** fault: iova=` jamás
  apareció) CUADRA con transacción colgada (no hay fault que entregar) más que con un fault de
  traducción limpio. Alternativa no excluida: el CM3 fetch-ea correcto pero el estado ACD/IFPC
  heredado (sin qmp limpiado en los boots k55–k58: `qcom,qmp` solo entró en s271 y el ACD-off
  depende de que `acd_probe` corra) mata el arranque del fw por otra vía. **NO-DETERMINADO entre
  ambas; el instrumento que lo decide (S4 con prints + AO_HOST_INTERRUPT_STATUS tras S3) nunca ha
  ejecutado en un boot que llegara vivo a S3.**

---

## 2. CRONOLOGÍA FÍSICA de un boot GPU-on que muere (k53/k54/k55 con consola; patrón de los 29 S3)

Todo a uptime del kernel (los prints llevan `pr_flush` — lo que se ve está en el wire):

| t | Evento físico |
|---|---|
| 0,00 s | ABL (vía `fastboot continue`) lanza el kernel. cmdline: `gmu_shared=0`, `panic=10`, `hung_task_panic=0` (efectivo), `watchdog_thresh=10`, `console=ttyGS0`. |
| 0,32 s | `arm-smmu 3da0000.kgsl-smmu` probea: 24 SMRs, 22 CBs. `devm_clk_bulk_get_all` toma los 4 clocks del DT con **ids vendor**: enciende HUB_CLK_SRC+CRC_AHB; **HLOS1_VOTE_GPU_SMMU queda apagada** (gate de la interfaz del SMMU en el vendor). |
| 0,37 s | `qcom_wdt` falla (-EBUSY) ⇒ **sin watchdog Linux**. |
| ~4,07 s | Deferred probe del GPU: `a6xx_gmu_init` → `of_dma_configure` (default domain transitorio del grupo SID5) → `msm_iommu_new` + attach (**K38: sid5→cbndx=1**, dominio propio; K39 handler). |
| 4,10–4,13 s | `a6xx_gmu_resume`: CX GDSC por device-link (MMIO del GMU responde), GX no-op, 7 clocks (k53–k55: **hub=400 MHz**), TCM_RET, rpmh no-op (cold). |
| 4,13 s | `fw_load` COLD: vector+handler (0x1dc) a ITCM; 2 bloques a DTCM — el último escribe **0x40050001 en DTCM+0xff8**; cuerpo del fw (0x1381c) al BO icache @IOVA 0x4000 en DRAM (CB1 propio). `Loaded GMU firmware v4.5.1` (lectura MMIO, NO ejecución). fw-map: icache=0x4000, dummy=0x60000000, hfi=0x60008000. |
| 4,14 s | P1: FW_INIT_RESULT=0, BOOT_CONFIG=0x02; P2: HFI_QTBL_ADDR=0x60008000; CM3_CFG=0x4052, chipid; P3: ICACHE/DCACHE/SYS_BUS=1 (K44 C los lee =1). |
| 4,14 s | S0: lee DTCM+0xff8 → **0x40050001 pre-cargado** (k53–k55: elige rama WARM mask=0x1ff/0x100). |
| 4,14 s | S1-rst1 (SYSRESET=1 ×2+wmb), S2-gen9, K44 A–E (todo sane; ITCM[0..1]=SP/reset del binario). |
| — | [solo k55/56: K19 dump lee SME globals (coherentes) y la ventana CB +0x20000 → **A**: basura — dump completa, sigue a S3 (líneas 625,6M) / **B**: external abort 0x96000010 en `uke_k19_dump_kgsl+0x3f4` — probe muere, NO hay S3, FIN del cuadro, máquina vive (líneas 632,39M; forklog k56)] [k57/k58: dump off → sigue directo a S3] |
| 4,15 s | **S3-rst0** (SYSRESET=0) + flush. El CM3 sale del reset: fetch de SP/vector DESDE ITCM (físico, sin SMMU); el handler @0x104 corre en ITCM; en µs salta al cuerpo @0x4000+ ⇒ **primer fetch por SID5→CB1 a través de la TCU/TBU mal gateada**. La transacción NO completa (ni dato ni error): TBU con outstanding → AHB/NoC de la isla GPU wedged. |
| 4,15 s (+ε) | Primer readl del poll (FW_INIT_RESULT) atraviesa el AHB wedged → **la CPU queda colgada en D-state sin respuesta de bus**. El S4-poke nunca ejecuta (29/29 boots sin un solo print posterior a S3). |
| +10–14 s | La CPU colgada no alimenta al WDT externo (ABL/AOP) ⇒ **bark → reset duro, sin panic, sin pstore** (o, si esa ruta no lo arma, wedge permanente tipo k53/k54). En k58: "freeze seco a los 14 s de continue". |

## 3. CRONOLOGÍA de un boot que "pasa" (k55/k56 graceful)

Idéntico hasta K44 E (4,14 s). La ÚNICA desviación: **el volcado K19, al leer la ventana CB
+0x20000, recibe respuesta de bus de ERROR en vez de silencio** — `synchronous external abort
0x96000010` en la CPU (Data Abort, DFSC=0x10, lectura 32-bit). El abort mata el probe del GMU
(resume abortado con -EIO/panic-shield) ⇒ **S3-rst0 nunca se escribe, el CM3 nunca sale del
reset, la isla nunca se wedgea** ⇒ el boot sigue (shell initramfs / rootfs) y el forklog de sda30
persiste la traza. La máquina no sobrevivió "al S3": jamás llegó al S3.

## 4. LA ÚNICA DIFERENCIA FÍSICA

**Los boots que congelan son exactamente los que ejecutaron S3-rst0 (soltaron el CM3); los que
pasan son exactamente los que NO llegaron a S3 porque la lectura del instrumento sobre la ventana
CB de la kgsl-smmu recibió un external abort y mató el probe antes.** No hay un solo boot con
SYSRESET=0 y máquina viva (29/29 muertos en la ventana del poll; 0 S4 impresos jamás). La variable
que decide si el instrumento aborta (basura / abort / hang) es el estado de la interfaz de la
SMMU — sospechoso físico: la gate `gpu_cc_hlos1_vote_gpu_smmu` apagada por el mismatch de clock-ids
del DT fusionado (C5/C6) — no el estado de energía del dominio GMU ni el timing de prints.

## 5. CONSECUENCIAS OPERATIVAS (para el siguiente boot, no para tocar nada hoy)

1. **k59 iotrace**: su valor real no es el vm-map (ya sabemos que icache/hfi viven en CB1 propio):
   es que por fin puede imprimir QUÉ accesorio muere y si S4 se alcanza — siempre que el boot
   llegue a S3 con consola viva (k57/k58 no dejaron ni ACM: verificar primero que ABL lanza el
   kernel; p.ej. un print temprano persistente tipo forklog/X9 del initramfs).
2. **Fix dtbo barato y sin probar**: ids de clock del nodo `kgsl-smmu` → valores de
   `qcom,palawan-gpucc.h` (`hlos1_vote=0xf`, `ahb=0x0`). Es el único candidato que explica la
   bistabilidad garbage/abort/hang del instrumento Y deja la TCU mal para el fetch del CM3.
3. **El poll fijo COLD de k58 (0xbabeface) sigue SIN VERIFICARSE** (ningún boot llegó a S4). La
   semántica exacta de FW_INIT_RESULT del fw gen71100 sigue siendo una asunción upstream (INV §8).
4. No repetir lecturas crudas de la ventana CB +0x20000 (abort/hang, lección k56/k58), y no usar
   `dtcmR` como discriminador (C1) ni `SME(1)→CB1` como "igual al vendor" (C2).

## 6. EVIDENCIA PRIMARIA (rutas)

- Código: `build/kernel-pokes/k52-tree/drivers/gpu/drm/msm/adreno/a6xx_gmu.c` (S0 :663; branch old
  :668-671 hoy sustituida; fw_load :1329-1410; fw_start :1412+; memory_probe :2109-2147; k19 :495+),
  `…/msm/msm_iommu.c:758-775` (K39/K13), `…/arm/arm-smmu/arm-smmu-qcom.c:221+332-351`,
  `…/clk/qcom/gpucc-palawan.c:155-157` (F 200/6), `include/dt-bindings/clock/qcom,palawan-gpucc.h`
  (ids), `registers/adreno/a6xx_gmu.xml:46` (DTCM_START=0x1c400).
- Bootimgs/cmdline (header offset 64): `build/bootimg/boot-uke-k{55,56,57,58}*.img` — todos
  `msm.uke_gmu_shared=0`; k55/k56 además `msm.uke_smmu_dump=1`; todos `hung_task_panic=1`→`0`.
- Binario: `build/pkg/uke-gpu-firmware/gen71100_gmu.bin` off 0x13b14 (xxd: `01 00 05 40`).
- Logs: `/var/tmp/uke-console2.log` (líneas 124k/189k/312k: K19-dumpOK→S3→banner; 625,6M: CBpages
  basura→S3→banner; 632,39M: abort 0x96000010 en uke_k19_dump_kgsl+0x3f4 tras SME globals, K38/K32/
  K39, SME(0)→CB0/SME(1)→CB1, y cola con shell initramfs viva ~35 min tras el abort),
  `/var/tmp/uke-sesion-console.log:114880-114900` (S3→banner, hub=400),
  `/var/tmp/uke-console2-trz.log` (último ACM 7-oct 15:30:49).
- Vendor: `build/evidencia/android-full/extracted-full/01-gpu/{dmesg-gpu.txt,clk-summary.txt}`,
  `…/14-dt/dt-live.tar.gz` (soc/kgsl-smmu@3da0000: `qcom,qsmmu-v500`+`qcom,adreno-smmu`;
  soc/qcom,gmu@3d69000: `iommus=<… 5 0>`), DT fusionado `/var/tmp/uke-s270/m270.dts` (:16337
  kgsl_smmu clocks ids 0x11/0x02; :21842 kgsl_msm_iommu `qcom,kgsl-smmu-v2`; :21863 gmu).
- Ledger: `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` #535–#541;
  `docs/historia/revision/INV-CM3-FALLO-20261007.md`; `docs/historia/revision/CRITICA-GPU-PLAN-20261006.md` (C0.1 ya señalaba gmu_shared=0);
  `docs/historia/revision/CRITICA-GPU-OPS-20261006.md` (sysctl runtime).

## 7. LÍMITES

- k58/k59 sin consola: el punto exacto de su muerte (¿llegaron a S3?) no es determinable offline.
- El "hub=200000000" de k56 y el "attach rc=0" vía ausencia-de-K13 son evidencia de segunda mano
  (forklog leído por telnet / ausencia de print de error).
- El agente exacto del reset duro (ABL-WDT vs AOP vs PMIC) no es verificable sin instrumentación.
- La semántica real de FW_INIT_RESULT/BOOT_CONFIG del fw gen71100 (vendor kgsl) se asume upstream.
