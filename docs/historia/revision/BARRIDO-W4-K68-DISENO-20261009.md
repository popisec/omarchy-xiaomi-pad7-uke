# BARRIDO-W4-K68-DISEÑO — rama D2-SOLO (gemela de K67), solo PC (2026-10-09)

> Solo PC: parche versionado + verificación. PROHIBIDO flashear/tocar la
> tablet (colgada en k66, presupuesto agotado). NO compilado aquí: el build
> lo hará el coordinador cuando toque (evita duplicar 3 GB + 60 min en
> paralelo al gemelo k67). Estado: PARCHE LISTO + VERIFICADO EN SCRATCH.

## 0. Punto de partida (ledger #553-#556)

- k66 (D1+D2 sin D3 + poll vendor + G10/G8) construido 28/28 gates, sin
  flashear. D3 exonerado como inútil+asesino probable (autopsia W3-K66 §1).
- Si k66 llega a S3 ⇒ D3 era el asesino, fin del discriminador.
- Si k66 calla igual ⇒ el asesino está en D1/D2 o en el enable-path.
  Entonces se parte: **k67 = D1-solo** (gemelo) y **k68 = D2-solo** (este
  fichero). Ambas ramas fork del mismo punto (baseline K65), NO apiladas
  sobre k66.

## 1. Qué aísla k68 vs k67 (matriz 2x2 completa)

| Variante | GMU (core_clk) | Hub (hub_clk) | vs k52b2 conocido-sano |
|---|---|---|---|
| k52b2 (ref) | XBL/heredado (200M pedía → floor 19.2M XO) | XBL/heredado (150M pedía → -EINVAL) | — |
| k66 | 220M exacto (D1) | 200M exacto (D2) | cambia AMBOS |
| **k67 (gemelo)** | **220M exacto (D1)** | **sin tocar (XBL)** | **cambia SOLO GMU** |
| **k68 (este)** | **sin tocar (XBL)** | **200M exacto (D2)** | **cambia SOLO hub** |

- k68 = `k66 menos el hunk D1`: poll vendor + G10/G8 intactos (testigos
  renombrados `UKE-K68`), `clk_set_rate(core_clk,220M)` ELIMINADO,
  `dev_pm_opp_set_rate` ELIMINADO (como en k66), solo queda
  `clk_set_rate(hub_clk,200M)` + testigo `SIN-D1+SIN-D3`.
- Decisión: k68 H3-clk/S3 ⇒ D2 viable, D1 era el problema. k68 en
  silencio + k67 vivo ⇒ D2 es el asesino (candidato nº2 de W3-K66 §2).
  Ambos en silencio ⇒ ni D1 ni D2 por separado: el problema es el
  enable-path o la combinación (ver §4, plan-C).

## 2. Orden de flashes recomendado: k67 primero, k68 después (si k66 calla)

Recomendación: **k67 (D1-solo) antes que k68 (D2-solo)**. Porqué, desde el
código de relojes (`gpucc-palawan.c`, verificado por lectura directa):

- **D1 programa un PLL dedicado.** `ftbl_gpu_cc_gmu_clk_src={19.2M XO,
  220M/550M vía P_GPU_CC_PLL1_OUT_MAIN}` (`gpucc-palawan.c:175-178`,
  `gpu_cc_pll1` dedicado al dominio GPU `:84-100`) y `gpu_cc_gmu_clk_src`
  lleva `CLK_SET_RATE_PARENT` (`:190`). El rate se propaga a un PLL
  propio; **no toca GPLL0 compartido**. Riesgo sistémico bajo; si falla,
  lo esperado es muerte informativa en H3-clk (rutas acotadas X9 2 s +
  RPMH 10 s, W3-K66 §2.3), no silencio pre-USB.
- **D2 cuelga del reloj compartido.** `ftbl_gpu_cc_hub_clk_src={200M}`
  (misma tabla que `ff_clk_src`, `:155-157`) con padre
  `P_GPLL0_OUT_MAIN` ← `DT_GPLL0_OUT_MAIN` (`:27-29`: GPLL0 de GCC,
  compartido con el resto del SoC). `gpu_cc_hub_clk_src` **NO** tiene
  `CLK_SET_RATE_PARENT` (solo el gmu lo tiene): no reprograma GPLL0,
  pero el `clk_bulk_prepare_enable` posterior levanta ramas AHB/hub
  (`gpu_cc_ahb_clk`, `gpu_cc_crc_ahb_clk` ← `hub_clk_src`, `:263-296`)
  que XBL dejó en estado desconocido, sin el voto CX que lo haría viable.
  Es el candidato nº2 de W3-K66 §2 (prob. MEDIA) para el silencio con
  "ni USB enumera". **k68 es la rama de mayor riesgo sistémico.**
- Orden lógico: primero la rama segura (k67). Si k67 vive ⇒ D1 vindicado
  y k68 pasa a ser el experimento de alto valor (confirma o culpa a D2).
  Si k67 calla ⇒ D1 o el enable-path; k68 sigue aportando (silencio en
  ambos = veredicto "ninguno por separado", ver §4), pero con un flash
  de coste ya asumido por la rama barata primero.
- Condición previa a ambos: **solo si k66 calla**. Si k66 llega a S3, D3
  era el asesino y k67/k68 sobran (no gastar escrituras).

## 3. Gates que deberá pasar el futuro build k68

Receta: copia de `k65-build` (mismo SRC/CFG/toolchain que k66 §4) + solo
`a6xx_gmu.c` cambiado por `k68-d2solo.diff` + relink. Puerta de linaje:
`patch -p1 --dry-run -R k68-d2solo.diff` OK sobre su árbol ⇒ lo
compilado == lo versionado (verificado aquí en scratch §5; repetir en el
árbol real del build).

- `Image` ~41490944 B (mismo tamaño que k64/k65/k66) + sha256 al ledger;
  `Image.gz` + sha; initramfs embebido = cpio K22 `08780e35…`.
- Gate binario `\x013UKE-POKE` presente (testigos `pr_err` pasan el tope
  K41); forma warn `\x014` ausente.
- Marcadores (clon de `build-k66.sh` con s/K66/K68/): `UKE-K68: D2` x1,
  `SIN-D1` x1, `SIN-D3` ausente→presente como `SIN-D1…+ SIN-D3` x1,
  `poll vendor` x1, `GENERAL_10 chipid=` x2 (ramas OK/NO-VALIDO),
  `GENERAL_8 log=` x1, `UKE-K64: register_config COMPLETADO` x1.
- Gates negativos: `UKE-K65: D1` ausente, `UKE-K65: D3` ausente,
  `UKE-K66:` ausente (cero fugas de la rama hermana), `opp_set_rate`
  ausente en el path de resume.
- Repack (NO ejecutado): misma receta que k66 §5 con
  `boot-uke-k68-d2solo.img`, cmdline byte-idéntica 492 B, `stage=3`
  primero (comparación directa k66-vs-k68: una sola variable = D1 fuera),
  segundo boot `stage=2`. Trazas a buscar: `UKE-K68: D2 … rc=`,
  `SIN-D1`, `GENERAL_10 … OK`, `UKE-CM3DBG: clks core=<heredado>
  hub=200000000` (el core heredado, NO 220M, es la firma de k68).

## 4. Veredicto (3): ¿es D2-solo inseguro o indistinguible?

- **Distinguible: SÍ, sin ambigüedad.** Testigos propios (`UKE-K68: D2`,
  `SIN-D1`) + firma en `CM3DBG` (`core=<XBL> hub=200M` vs `core=220M
  hub=<XBL>` de k67 vs `core=220M hub=200M` de k66). Cero solape si los
  gates negativos se cumplen.
- **Inseguro en sentido daño: NO.** Como k65/k66: solo `clk_set_rate` +
  enable, sin escrituras permanentes, sin tocar SYSRESET ni SMMU; los rc
  no abortan. Riesgo = un flash + 1-2 arranques, igual que cualquier rama.
- **Inseguro en sentido sistémico: es LA rama arriesgada, a propósito.**
  Hub-200M sobre GPLL0 compartido + GMU a rate heredado lento (típ. XO
  19.2M): cruce de dominios hub-rápido/GMU-lento que el fw no espera, y
  el enable levanta el bus sin voto CX. Pero ese riesgo es exactamente lo
  que la hace buen discriminador: si vive, D2 queda vindicado de raíz.
  NO la descarto; la ordeno segunda (§2).
- **Plan-C si k67 Y k68 callan (discriminador alternativo):** el problema
  ya no es ningún rate por separado sino el enable-path
  (`clk_bulk_prepare_enable` levantando padres XBL en estado desconocido)
  o la combinación. Siguiente diseño, no otro rate: **D1+D2 con enables
  diferidos tras USB** — fijar los rates pero mover el
  `clk_bulk_prepare_enable` (o la suelta del reset S1) a un workqueue
  tardío / tras enumerar USB / tras consola ACM viva, de modo que una
  muerte quede CON traza (rates + H3-clkFAIL visibles) en vez de silencio
  cero-bytes. Alternativa menor: fijar rates vía debugfs post-boot con
  GPU en hold (`uke_probe_hold_ms`), separando "muerte por reloj" de
  "muerte por enable" sin flashear a ciegas.

## 5. Bitácora (solo PC, árbol real intacto)

- Árbol `k52-tree` verificado = k66 aplicado:
  `patch -p1 --dry-run -R k66-d1d2-vendorpoll.diff` **OK** (cwd =
  `build/kernel-pokes/k52-tree`; desde la raíz del repo falla por ruta,
  el diff es relativo al árbol, no al repo).
- `k68-d2solo.diff` generado por `diff -u` (labels a/ b/): baseline "a"
  = K65 (misma que k66: reconstruida por `-R` de k66 sobre copia
  scratch), "b" = K65 + hunks 1-2 idénticos (testigos→K68) + hunk3
  D2-solo. Hunks 1-2 byte-iguales a k66 salvo renombre; hunk3 elimina la
  línea `clk_set_rate(core_clk,220M)` + D3 (heredado de k66).
- Verificación en scratch (árbol real NO tocado, gemelo k67 no
  interferido): forward `--dry-run` sobre copia baseline-K65 **OK**;
  `--dry-run -R` sobre copia k68-aplicada **OK** ⇒ el futuro build podrá
  probar linaje igual que k66 §4. Cero `UKE-K66`/`k66_` restantes (25
  marcas K68), cero `UKE-K65`/`opp_set_rate` en resume.
- Evidencia de relojes: `gpucc-palawan.c:155-178,182-211`
  (tablas+padres+flags), `:263-296` (ramas AHB←hub), `palawan.dtsi`
  (GDSC sin perf-state, ya en W3-K66 §1a). NO compilado, NO repack,
  NO flash. Fichero propio: el del gemelo k67 no tocado.
