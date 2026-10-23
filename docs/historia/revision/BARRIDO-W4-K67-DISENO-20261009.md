# BARRIDO-W4-K67-DISEÑO — D1-solo: partir D1/D2 tras el silencio k66 (2026-10-09)

> Solo PC: análisis + parche + build + verificación. PROHIBIDO flashear/reboot
> (presupuesto de escrituras agotado; tablet colgada en k66; testbed k52b2+s273
> conocido-bueno `18c749ea…` en disco).
> Estado: §1-§2 ANÁLISIS COMPLETO + RANKING D2>D1 (este informe) → §3+ EN CONSTRUCCIÓN.

## 0. Hechos (ledger #553-#556 del hermano)

- k65 (D1+D2+D3) flasheado en boot_a → silencio pre-USB 4 min, cero bytes.
- k66 (D1+D2 SIN D3 + poll vendor + G10/G8, Image `69c0a8d6…`, flasheado en
  boot_a) → **MISMO silencio pre-USB 6+ min, cero bytes de consola, sin USB**.
- **D3 EXONERADO como asesino único** (el oops `clk_round_rate(ERR_PTR)` de W3
  §1b no explica nada: sin D3 el silencio persiste idéntico).
- Sospechosos vivos: **D1** (`clk_set_rate(core,220M)` + enable) y **D2**
  (`clk_set_rate(hub,200M)` + enable), ambos sin voto CX (el voto era D3, que
  era un no-op por W3 §1a y ahora ni siquiera existe).
- k67 = D1-SOLO (este informe). k68 = D2-solo (informe hermano, en marcha en
  paralelo). Árbol de decisión: k67 habla ⇒ asesino D2; k67 calla igual ⇒
  asesino D1 (o el enable-path común); ambos hablan ⇒ era D3+contexto (ya
  refutado) o interacción D1×D2.

## 1. Lo que comparte el árbol de relojes con USB (fuente k52-tree, verificado por lectura directa)

Cadena física del GPLL0 (un SOLO PLL en el GCC, compartido por todo el SoC):

- `gcc-palawan.c:48-65` `gcc_gpll0` (alpha PLL) → `:1310-1325`
  `gcc_gpu_gpll0_clk_src` (branch, padre `&gcc_gpll0.clkr.hw`) →
  DT `palawan.dtsi:2526-2529` (gpucc consume `GCC_GPU_GPLL0_CLK_SRC/DIV`) →
  `gpucc-palawan.c:27-28` `DT_GPLL0_OUT_MAIN/DIV` = padres de los RCG de GPU.

Usuarios del MISMO `gcc_gpll0` en el lado GCC/USB (vivos durante el boot):

- `gcc-palawan.c:946-966` `gcc_usb30_prim_master_clk_src`:
  `F(133333333…), F(200000000…), F(240000000…)` todos con `P_GCC_GPLL0_OUT_MAIN`.
- `gcc-palawan.c:1176-…` `gcc_cfg_noc_usb3_prim_axi_clk` (padre = usb master);
  `:1096-…` `gcc_aggre_usb3_prim_axi_clk` (padre = usb master).
  Es decir: **todo el path USB3 (master + cfg_noc + aggre) cuelga del GPLL0**.

Ramas GPUCC (quién toca qué):

- D2: `a6xx_gmu.c:2358` `clk_set_rate(hub_clk,200M)` donde `hub_clk` =
  `gpu_cc_hub_cx_int_clk` (`gpucc-palawan.c:446`, branch con
  `CLK_SET_RATE_PARENT`, padre `gpu_cc_hub_clk_src`) → `gpucc-palawan.c:198`
  `gpu_cc_hub_clk_src` (RCG `clk_rcg2_shared_ops`, **SIN** `CLK_SET_RATE_PARENT`,
  `:203` usa `:155-157` `ftbl_gpu_cc_ff_clk_src` = entrada única
  `F(200000000, P_GPLL0_OUT_MAIN, 6, 0, 0)`).
- Consumidores de ESE MISMO RCG (`hub_clk_src`), todos arrastrados por D2:
  `gpu_cc_ahb_clk` (`:263`, padre `:272` = hub_src) = **el bus de registros del
  GMU**; `gpu_cc_crc_ahb_clk` (`:281`); `gpu_cc_hub_aon_clk` (`:429`);
  `gpu_cc_hub_cx_int_clk` (`:446`, el propio hub).
- D1: `a6xx_gmu.c:2356` `clk_set_rate(core_clk,220M)` donde `core_clk` =
  `gpu_cc_cx_gmu_clk` (`:335`, branch con SET_RATE_PARENT, padre
  `gpu_cc_gmu_clk_src`) → `:182-196` `gpu_cc_gmu_clk_src` (**CON**
  `CLK_SET_RATE_PARENT` `:193`, `:175-180` ftbl =
  `19.2M←TCXO / 220M←PLL1 / 550M←PLL1`): 220M cuelga de `GPU_CC_PLL1`,
  **un PLL dedicado de GPU sin más usuarios** (`:117-131` mapa_1: TCXO, PLL0,
  PLL1, GPLL0, DIV).

Matiz honesto sobre "D2 reprograma un padre vivo del USB": D2 **NO** reprograma
la tasa del GPLL0 (el RCG hub_src no tiene `CLK_SET_RATE_PARENT`: la
propagación muere en el RCG; el PLL sigue a su tasa para USB/NOC). Lo que D2
sí hace en vivo y sin voto CX es: (a) **conmutar el mux del RCG** del rate
heredado de XBL (piso XO 19.2M, el que k52b2/k63/k64 usan sin tocar nada) a
derivar 200M del GPLL0 compartido; (b) **subir de un golpe el bus de registros
(AHB) + CX_INT a 200M sobre el rail CX en piso XBL**. El paso siguiente del
resume (`clk_bulk_prepare_enable` + `gmu_write/read`, `:2362+`) accede al GMU
por un AHB a 200M sin voltaje que lo sostenga: un hang de bus aquí cuelga el
NOC → muerte SoC-wide pre-USB con cero bytes. Ese es el mecanismo que D1 no
tiene: el fallo de D1 (PLL1 dedicado que no engancha, core a 220M sin CX) queda
confinado al GMU-local, con consola viva (rc logueados, `H3-clkFAIL`, timeouts
X9 2 s / RPMH 10 s acotados).

## 2. Ranking D1 vs D2 (por probabilidad de explicar el silencio TOTAL)

1. **D2 — MEDIA-ALTA.** Blast-radius = bus de registros (AHB `:263`) +
   CX_INT + aon + crc, todos a 200M sin voto CX; el RCG vive del GPLL0
   compartido con USB (mismo PLL físico `gcc_gpll0`, aunque su tasa no cambie).
   Un hub/AHB colgado tras el `prepare_enable` deja `gmu_read/write`
   colgados en bus = SoC-wide, compatible con "ni USB enumera, cero bytes".
   Además k52b2 pedía 150M → -EINVAL (reloj XBL intacto, todo a piso XO =
   estado conocido-bueno); k65/k66 son los PRIMEROS en fijar este RCG.
2. **D1 — BAJA para el silencio (MEDIA como fallo local).** 220M va contra el
   PLL1 dedicado (`SET_RATE_PARENT` `:193` lo programa a él, a nadie más); si
   PLL1 no engancha, `clk_set_rate` devuelve rc (logueado, NO aborta) y el
   fallo posterior es GMU-local con consola/USB vivos (H3-clkFAIL / HFI
   timeouts acotados). Para matar USB haría falta un oops síncrono en el hilo
   de probe — y el único oops conocido del diff era D3 (exonerado por
   persistencia del silencio sin él).

Veredicto-análisis: **D2 explica el silencio mejor que D1**. k67 (D1-solo,
este informe) es el discriminador correcto: si habla, D2 es el asesino; si
calla igual, D1 (o el enable común).

## 3. Diseño k67 mínimo (una variable vs k66: SIN D2)

- **D1 intacto** (mismo rate 220M, testigo renombrado `UKE-K67`).
- **D2 ELIMINADO**: ni `clk_set_rate(hub,200M)` ni su testigo; el hub/AHB quedan
  en el rate heredado de XBL (piso XO = estado conocido-bueno de k52b2/k63/k64).
  Testigo negativo `UKE-K67: SIN-D2`.
- **D3 sigue eliminado** (testigo `UKE-K67: SIN-D3`; el gate negativo K65-D3 se
  conserva y se añade K66-D2 como ausente obligado).
- **Poll vendor + G10/G8 de k66 intactos** (testigos `UKE-K66`, byte-idénticos;
  menos variables: el fw ya no es sospechoso tras k66).
- Parche versionado: `build/gates/patches/k67-d1solo.diff` = k66 menos el hunk
  D2 (hunks 1-2 idénticos a k66; hunk 3 reescrito: `-2306,21/+2346,17`).
  Aplicado al árbol (`patch -p1`, `dry-run -R` OK ⇒ lo compilado == lo
  versionado). En fuente: D1 x1 (`a6xx_gmu.c:2356`), `hub set_rate` x0,
  `opp_set_rate` x0.

### Juicio de seguridad (exigido por el encargo): NO se aborta

D1-solo es conceptualmente seguro como experimento porque su blast-radius es
GMU-local: 220M va contra el PLL1 dedicado (sin más usuarios, §1); el bus de
registros (AHB) queda a piso XBL al estar D2 fuera (accesos lentos-pero-seguros
como k52b2/k63/k64); todos los caminos de fallo mainline están acotados
(rc logueados sin abortar, `H3-clkFAIL`, X9 2 s, RPMH 10 s). Peor caso esperado
= fallo INFORMATICO con consola viva (H3/S3/S4 dicen D1 vs enable-path). El
peor caso absoluto (mismo silencio que k65/k66) no empeora nada ya intentado.
Se procede al build.

Árbol de decisión (experimento k67; k68 = D2-solo corre en paralelo):
- k67 llega a H3-clk/CM3DBG/S3 ⇒ **D2 era el asesino** (confirmado §2).
- k67 en silencio igual ⇒ **D1** (o el enable-path común; k68 lo confirma por
  eliminación si k68 habla).
- k67 S4-pollOK ⇒ estado viable también sin D2 (doble vindicación D1+poll/G10/G8).

## 4. Verificación del Image k67 — COMPLETA 9-oct (~13:11)

- Build incremental sobre copia exacta `k66-build → k67-build` (mismo SRC/CFG/
  toolchain; solo `a6xx_gmu.c` cambiado + relink, 33 s): `Image` **41490944 B**
  (mismo tamaño que k64/k65/k66), `Image.gz` 16707251 B.
  sha256 `6abdb6df4b4fef3eaad51c61ef5c090814ae02ef979ab1d100458215002f5944`
  (Image), `8c597bc8613a4cc159edf731fb565f15b36be2ecf9967e38fe3396420b0fe0e2`
  (Image.gz). Initramfs embebido = cpio K22 `08780e35…` (OK, gate del script).
- `patch -p1 --dry-run -R k67-d1solo.diff` sobre el árbol: OK ⇒ **lo compilado
  == lo versionado**. Receta en `docs/historia/gates-palawan/build-k67.sh` (clon de
  `build-k66.sh` + gates K67; `bash -n` OK).
- Gates de marcadores (`build-k67.sh`): **28/28 OK + 7 mustnt ausentes**,
  incluidos `UKE-K67: D1` (x1), `UKE-K67: SIN-D2` (x1), `UKE-K67: SIN-D3`
  (x1), poll vendor K66 (x1), `GENERAL_10 chipid=` (x2), `GENERAL_8 log=` (x1),
  `UKE-K64: register_config COMPLETADO` (x1), `UKE-POKE` x113; ausentes:
  forma warn `\\x014` del poke, `uke_k19_dump_desc(e[4]`, `0x200000;`,
  `UKE-K65: D3/D2` y **`UKE-K66: D1/D2`** (renombrados/eliminados).
- Warnings: solo el preexistente K61 `frame-larger-than` en
  `uke_k61_rescue_write` (misma clase que k66; sin nueva clase de warning).

## 5. Repack LISTO sin flashear (receta para el dueño; NO ejecutada)

Receta (NO ejecutar: `repack-k67.py` no creado a propósito; al crearla, clonar
`repack-k66.py` con `KERNEL=k67-build/.../Image.gz`,
`OUT=boot-uke-k67-d1solo.img`, G3 = D1-K67 x1 + SIN-D2 x1 + SIN-D3 x1 +
poll x1 + G10 x2 + G8 x1 + K64-register_config x1, negativos K65-D3/D2 +
K66-D1/D2, `UKE-POKE`=113):

```bash
python3 docs/historia/gates-palawan/repack-k18.py \
  --kernel build/kernel-pokes/k67-build/arch/arm64/boot/Image.gz \
  --out build/bootimg/boot-uke-k67-d1solo.img \
  --dsid \
  --cmdline-append "memmap=0x2B00000\$0xE3940000,loglevel=4,msm.uke_gmu_shared=0,arm_smmu.uke_kgsl_keep=0,hung_task_panic=0,printk.always_kmsg_dump=0,plymouth.enable=0,msm.uke_s3_stage=3,msm.uke_rescue=1,msm.uke_probe_hold_ms=5000" \
  --cmdline-require "msm.uke_s3_stage=3,msm.uke_rescue=1"
```

Cmdline byte-idéntica a k64/k65/k66 (492 B); `stage=3` reproduce el flujo exacto:
comparación directa k66-vs-k67 (una sola variable: D2 fuera). Gates G0-G8 del
script, tamaño exacto 100663296 B, sha al ledger antes de escribir. Segundo
boot recomendado: mismo img con `stage=2`. **NADA de esto ejecutado.**

## 6. Fila de ledger pre-registrada (redactada; NADA ejecutado)

**K67-D1SOLO — PRE-REGISTRO: D1 sin D2 ni D3 + poll vendor + G10/G8.**
**Artefacto.** `build/bootimg/boot-uke-k67-d1solo.img` sha256 `PENDIENTE`
(repack no ejecutado; Image.gz `8c597bc8…398fe0e2` verificado §4).
**Variables vs k66:** D2 eliminado (única variable); poll/G10/G8/K64/P3-stages
intactos. **Comando (NO ejecutado).** `fastboot flash boot_a|boot_b
build/bootimg/boot-uke-k67-d1solo.img` · verificación: consola ACM + pstore;
buscar `UKE-K67: D1 … rc=`, `SIN-D2`, `SIN-D3`, `UKE-CM3DBG: clks
core=220000000 hub=<XBL>`, desenlace S3. **Criterios** (§3): H3-clk/S3 ⇒ D2
asesino; silencio igual ⇒ D1 (confirmar con k68); S4-pollOK ⇒ viable sin D2.
**Coste.** 1 escritura + 1-2 arranques. Registrar los 4 `slot-retry-count`.

## 7. Bitácora

- Relojes trazados en fuente: `gpucc-palawan.c` (RCGs + los 4 consumidores del
  hub_src, flags SET_RATE_PARENT), `gcc-palawan.c` (usb master + cfg_noc cuelgan
  de `gcc_gpll0`), DT (`palawan.dtsi:2522-2533` gpucc←GCC_GPU_GPLL0,
  `:2481-2495` clocks/power-domains del GMU), driver (`a6xx_gmu.c:3165-3170`
  mapeo core/hub, `:2340-2400` resume).
- Matiz registrado: D2 no cambia la tasa del GPLL0 (sin SET_RATE_PARENT en el
  RCG); su peligro es el mux en vivo + AHB/CX_INT a 200M sin voto CX.
- Parche: `k67-d1solo.diff` = copia de k66 menos D2 (cabecera hunk3 corregida
  a `-2306,21/+2346,17` tras quitar la línea `ret=hub`); `apply dry-run` +
  aplicado + `dry-run -R` OK. Backup k66 en `/tmp/a6xx_gmu.k66.c`, base+K65
  en `/tmp/a6xx_gmu.base-k65.c` (fuera del repo; el árbol es gitignored).
- `build-k67.sh` (clon k66 + gates K67, `bash -n` OK); `cp -a k66-build →
  k67-build` + build incremental 33 s → **28/28 + 7 mustnt** (~13:11);
  shas §4. Repack+flash NO ejecutados (receta §5 + ledger §6 redactados).
