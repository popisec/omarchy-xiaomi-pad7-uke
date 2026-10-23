# BARRIDO-W3-K66-DISEÑO — autopsia del silencio k65 + kernel k66 (2026-10-09)

> Solo PC: parche + build + verificación. PROHIBIDO flashear/reboot
> (presupuesto de escrituras 2/2 agotado; testbed k52b2+s273 vivo por SSH,
> solo lecturas). Estado: AUTOPSIA COMPLETA + K66 EN CONSTRUCCIÓN (ver §7).

## 0. Hechos (ledger #553-#554 del hermano)

- k65 (GMU 220M + hub 200M + voto CX LOW_SVS vía `dev_pm_opp_set_rate` en
  `a6xx_gmu_resume` + K64-vendor_config) flasheado en boot_a → **silencio
  pre-USB 4 min sin ni un byte de consola** (ni siquiera USB enumera).
- k52b2 en el mismo slot con el mismo dtbo s273 arranca con SSH en ~60 s.
- k63/k64 (misma rama, sin D1/D2/D3) al menos daban USB/consola.
- k65 muere ANTES que k63/k64. Delta k64→k65 ≈ SOLO el diff k65
  (k52-build/Image 9-oct 02:02 = k64; k65-build/Image 9-oct 04:06;
  mismo árbol + `k65-cx-viable.diff`; **.config idénticos**, md5
  `d26c1ece22804dae3df139dc4876dcfa` — descartado drift de config).

## 1. Autopsia: el camino D3 en ESTE árbol (k52-tree)

Cadena seguida en fuente (todas las citas verificadas por lectura directa):

- D3: `a6xx_gmu.c:2322` `dev_pm_opp_set_rate(gmu->dev, 220000000)`.
- `drivers/opp/core.c:1404+` (`dev_pm_opp_set_rate`) → `_find_opp_table`
  → `_find_freq_ceil` → `_set_opp` → `_set_opp_level` (`core.c:1178`) →
  `dev_pm_domain_set_performance_state` (`base/power/common.c:450`) →
  `pd->set_performance_state` → `rpmhpd_set_performance_state`
  (`rpmhpd.c:1070`, `guard(mutex)(&rpmhpd_lock)`) → `rpmhpd_aggregate_corner`
  → `rpmhpd_send_corner` (`rpmhpd.c:949`: `sync ? rpmh_write : rpmh_write_async`)
  → `rpmh_write` (`rpmh.c:253`: `wait_for_completion_timeout(..., RPMH_TIMEOUT_MS=10 s)`)
  → `rpmh_rsc_send_data` (`rpmh-rsc.c:642`: con parche uke-X9, timeout 2 s → `-ETIMEDOUT`,
  ya NO "wait forever").

Pero hay DOS cortocircuitos ANTES de llegar al RPMH, ambos verificados:

**(a) El voto CX de D3 NUNCA llega al RPMH (error de diseño FASE2 §1).**
`gmu->dev` = platform device `gmu@3d6a000`, cuyos `power-domains` son
`<&gpucc GPU_CC_CX_GDSC>, <&gpucc GPU_CC_GX_GDSC>` (`palawan.dtsi:2497-2500`).
Los GDSC solo definen `power_on/power_off` (`clk/qcom/gdsc.c:507-511`):
**no tienen `set_performance_state`** ⇒ `dev_pm_domain_set_performance_state`
(`common.c:450-457`) devuelve 0 sin emitir NADA. El `_set_opp_level` → genpd-CX
por el que FASE2 justificaba D3 no existe en este DT: el `dev->pm_domain` del
GMU es un GDSC, no un rpmhpd. D3 como "voto CX" es un no-op *por construcción*.

**(b) D3 probablemente ni siquiera llega a `_set_opp`: oops en `clk_round_rate`.**
La tabla OPP del GMU se crea en `a6xx_gmu_pwrlevels_probe` (`a6xx_gmu.c:3010`,
`devm_pm_opp_of_add_table(gmu->dev)`, retorno IGNORADO en `:3527`) con los 2
OPPs del DT (`palawan.dtsi:2504-2513`, sin reguladores ni interconnects).
Pero NADIE fija clk a esa tabla (`devm_pm_opp_set_clkname` de `adreno_gpu.c:1217`
es para el device GPU, no para `gmu->dev`) ⇒ `opp_table->clk = ERR_PTR(-ENODEV)`
(`opp/core.c:1543`, `_allocate_opp_table`; ningún camino del `_of_add_table`
lo rellena). Y `dev_pm_opp_set_rate` hace, SIN guarda IS_ERR:
`freq = clk_round_rate(opp_table->clk, target_freq)` (`opp/core.c:~1440`).
`clk_round_rate` (`clk/clk.c:1778`) solo filtra `!clk` (NULL), NO `IS_ERR` ⇒
con `0xFFFFFFFFFFFFFFED` desreferencia `clk->exclusive_count` → **data abort
síncrono en EL1 dentro de `a6xx_gmu_resume`**, tras los pr_err D1/D2 (quedan en
logbuf, sin consola que los drene) y antes de H3-clk/USB. Un oops en el hilo
de probe/bind = arranque cuajado pre-USB con cero bytes fuera. (Si la tabla no
existiera —phandle colgante tras el dtbo s273 "gmu-map"—, D3 sería un simple
`-ENODEV` inocuo; el caso (b) exige tabla creada + clk sin fijar, que es el
caso nominal con este DT.)

## 2. Candidatos ordenados (con fichero:línea)

1. **D3 → `clk_round_rate(ERR_PTR(-ENODEV))` → abort síncrono en resume.**
   `a6xx_gmu.c:2322` (llamada) + `opp/core.c:~1440` (`clk_round_rate` sin
   guarda) + `clk/clk.c:1778` (solo `if (!clk)`) + `opp/core.c:1543`
   (clk queda `ERR_PTR`). Único camino del diff con muerte SIN consola y SIN
   timeout que la acote. Probabilidad: ALTA.
2. **D2 (hub 200M exacto) reprogramando en vivo el padre compartido
   `ff_clk_src/GPLL0`.** `a6xx_gmu.c:2320-2321` + `gpucc-palawan.c:ftbl_gpu_cc_ff_clk_src={200M}`.
   k52b2 pedía 150M → -EINVAL (reloj heredado de XBL intacto); k65 FIJA 200M y
   el `clk_bulk_prepare_enable` posterior arranca padres que XBL dejó en un
   estado que mainline no sabe llevar (el voto CX que lo haría viable era D3,
   que es un no-op por §1a). Efecto sistémico (reloj vivo compartido con
   USB/interconnect) compatible con "ni USB enumera". Probabilidad: MEDIA.
   Se aísla con k67 (D1 sin D2 y viceversa) si k66 sigue en silencio.
3. **D1 (GMU 220M exacto) + enable sin voto CX.** `a6xx_gmu.c:2319`. Mismo
   argumento que (2) del lado `gmu_clk_src` (200M pedía XO-floor 19.2M en k52b2;
   220M es exacto y por primera vez el GMU va a velocidad real). Todos los
   caminos mainline aquí están acotados (X9 2 s + RPMH 10 s), así que como
   *cuelgue* es menos probable que (1); como *muerte informativa en H3-clk*
   sería lo esperado, no silencio. Probabilidad: BAJA para el silencio.

Veredicto: **D3 es el asesino más probable, y además era inútil** (§1a).
FASE2 §1 queda refutado en su punto D3: el diseño era sano en D1/D2 y
erróneo en D3 (voto que no vota + oops). D1/D2 quedan bajo sospecha menor
(residual FASE2 confirmado: padre no votado) y k66 los conserva a propósito
como discriminador.

## 3. Diseño k66 mínimo (una variable vs k65: SIN D3)

- **D1+D2 intactos** (mismos rates, mismos testigos renombrados `UKE-K66`).
- **D3 ELIMINADO** (ni siquiera endurecido: un voto que no vota no se endurece,
  se quita; el voto CX real se rediseñará en otra oleada contra el device GPU
  con `required-opps`→rpmhpd, fuera del k66). Gate negativo: `UKE-K65: D3`
  ausente en binario.
- **Poll vendor** (W2-RE §4): `(val&0x1ff)==0x100` en vez de `==0xbabeface`
  (el fw jamás escribe `0xbabeface`; éxito=`0x100`, error=`0x101`). Si el CM3
  no completa, fallo limpio con re-assert, no freeze.
- **`0x1f9cf` (GENERAL_10) = chipid real con validación de familia**
  (W2-RE §2): `((x>>16)&0xfff)∈{701,702,703,705,706,709,70a,70b,70f}`;
  si no valida, NO se escribe `0xf` (se conserva el de mainline + testigo).
- **`0x1f9cd` (GENERAL_8) = `(log.iova&~0xfff)|(size/4K-1)`** (W2-RE §3):
  K64 lo pisaba con `0xf` DESPUÉS de que mainline lo programara bien.
- `0x1f9ce/0x1f9d0` se dejan como K64 (menos variables).

Árbol de decisión (experimento k66):
- k66 llega a H3-clk/CM3DBG/S3 ⇒ D3 era el asesino; D1/D2 vindicados.
- k66 en silencio igual ⇒ D1/D2 o el enable-path; siguiente: k67 parte D1/D2.
- k66 llega a S3 y pollFAIL `0x101` ⇒ chipid sigue mal (revisar formato fw).
- k66 S4-pollOK ⇒ el estado viable era la llave (golden-state dirá D1 vs D2).

## 4. Verificación del Image k66 — COMPLETA 9-oct (~12:53)

- Build incremental sobre copia exacta de `k65-build` (mismo SRC/CFG/toolchain;
  solo `a6xx_gmu.c` cambiado + relink): `Image` **41490944 B** (mismo tamaño
  que k64/k65), `Image.gz` 16707138 B.
  sha256 `69c0a8d60cf0fcde0dd6abc708f71f80514722505082943ebbca0df1fdd436f2`
  (Image), `cc896d8f13876904e464dc582496c3e60821e045b2e9d37b8caca9f7af704220`
  (Image.gz). Initramfs embebido = cpio K22 `08780e35…` (OK).
- `patch -p1 --dry-run -R k66-d1d2-vendorpoll.diff` sobre el árbol: OK ⇒
  **lo compilado == lo versionado**.
- Gate binario `\x013UKE-POKE`: presente (forma warn `\x014` ausente) ⇒
  testigos K66 (`pr_err`) pasan el tope K41.
- Gates de marcadores (`build-k66.sh`): **28/28 OK + 4 mustnt ausentes**,
  incluidos `UKE-K66: D1/D2` (x1), `SIN-D3` (x1), `poll vendor` (x1),
  `GENERAL_10 chipid=` (x2: ramas OK/NO-VALIDO), `GENERAL_8 log=` (x1),
  más `UKE-K64: register_config COMPLETADO` verificado x1 en binario,
  y **ausencia de `UKE-K65: D3…`** (gate negativo: D3 fuera del binario).
- Tipos: `log.iova=u64`, `log.size=size_t` (`a6xx_gmu.h:19-20`); el bloque K66
  espeja el patrón mainline (`& GENMASK(31,12) | & GENMASK(7,0)`, cast a `u32`
  en `%#x`, `%zu` para size): sin nueva clase de warning.
- Receta canónica limpia (`O=k66-build` inexistente → full ~60 min) versionada
  en `docs/historia/gates-palawan/build-k66.sh` (clon de `build-k65.sh` + gates K66); el
  artefacto de este informe salió de la vía incremental verificada por gates.

## 5. Repack LISTO sin flashear (receta para el dueño; NO ejecutada)

```bash
python3 docs/historia/gates-palawan/repack-k18.py \
  --kernel build/kernel-pokes/k66-build/arch/arm64/boot/Image.gz \
  --out build/bootimg/boot-uke-k66-d1d2vendor.img \
  --dsid \
  --cmdline-append "memmap=0x2B00000\$0xE3940000,loglevel=4,msm.uke_gmu_shared=0,arm_smmu.uke_kgsl_keep=0,hung_task_panic=0,printk.always_kmsg_dump=0,plymouth.enable=0,msm.uke_s3_stage=3,msm.uke_rescue=1,msm.uke_probe_hold_ms=5000" \
  --cmdline-require "msm.uke_s3_stage=3,msm.uke_rescue=1"
```

Cmdline byte-idéntica a k64/k65 (492 B); `stage=3` reproduce el flujo exacto:
comparación directa k65-vs-k66 (una sola variable: D3 fuera + poll/G10/G8).
Gates G0-G8 de `repack-k18.py`, tamaño exacto 100663296 B, sha al ledger
antes de escribir. Segundo boot recomendado: mismo img con `stage=2`.

## 6. Fila de ledger pre-registrada (redactada; NADA ejecutado)

**K66-D1D2VENDOR — PRE-REGISTRO: D1+D2 sin D3 + poll vendor + G10/G8.**
**Artefacto.** `build/bootimg/boot-uke-k66-d1d2vendor.img` sha256 `PENDIENTE`
(repack no ejecutado; Image.gz `cc896d8f…f704220` verificado §4).
**Variables vs k65:** D3 eliminado; poll `(val&0x1ff)==0x100`; GENERAL_10=chipid
validado; GENERAL_8=log recompuesto. D1/D2, K64, P3-stages, resto intactos.
**Comando (NO ejecutado).** `fastboot flash boot_a|boot_b
build/bootimg/boot-uke-k66-d1d2vendor.img` · verificación: consola ACM +
pstore; buscar `UKE-K66: D1/D2 … rc=`, `SIN-D3`, `GENERAL_10 … OK`,
`GENERAL_8 …`, `UKE-CM3DBG: clks core=220000000 hub=200000000`, desenlace S3.
**Criterios** (§3): H3-clk/S3 ⇒ D3 asesino; silencio igual ⇒ D1/D2 (k67 los
parte); pollFAIL `0x101` ⇒ chipid aún mal; S4-pollOK ⇒ estado viable = llave.
**Coste.** 1 escritura + 1-2 arranques. Registrar los 4 `slot-retry-count`.

## 7. Bitácora

- Autopsia en árbol: camino D3→OPP→genpd→rpmhpd→RSC trazado con timeouts
  (X9 2 s, RPMH 10 s); cortocircuitos (a) GDSC sin perf-state y (b)
  `clk_round_rate(ERR_PTR)` localizados con fichero:línea; `.config`
  k52-vs-k65 idénticos (md5) ⇒ sin drift de config; k64-vs-k65 en mismo
  árbol ⇒ delta = diff k65.
- `k66-d1d2-vendorpoll.diff` v1 (cabeceras @@ a mano, malformado) → v2
  generado por `diff -u` (`dry-run` OK) → aplicado al árbol.
- `build-k66.sh` creado (clon k65 + gates K66, `bash -n` OK).
- `k65-build` → `k66-build` (`cp -a`, 3.2 G); build incremental + gates
  **28/28 OK** (~12:53); `dry-run -R` OK; shas §4. Repack+flash NO ejecutados.
- Nota para el dueño (solo lectura, sin coste): el oops presunto de D3, si
  ramoops lo capturó, seguiría en pstore del testbed (`uke-pstore-read.sh`);
  `Oops [...] clk_round_rate` confirmaría al candidato nº1 sin flashear nada.
