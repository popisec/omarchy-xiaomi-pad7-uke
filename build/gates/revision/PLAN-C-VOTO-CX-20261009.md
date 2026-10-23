# PLAN-C — VOTO CX ESTILO VENDOR (2026-10-09, solo PC, sin flashear)

> Solo PC: diseño + parche C1 versionado con dry-run. PROHIBIDO
> flashear/tocar la tablet (colgada en k68, presupuesto de hoy agotado:
> 6 escrituras). NO compilado aquí: el build lo hará el coordinador.
> Estado: DISEÑO + DIFF C1 LISTOS, VERIFICADOS CON DRY-RUN.
> Punto de partida: E0 (GPLL0 vivo a 1200M, gfxlvl en DT vivo, cero driver
> RDPM en k52-tree, 0 en Image k68) + crítica W6 aceptada (k64 baseline
> fantasma, axioma-(a) peligroso) + k65/k66/k67/k68 en silencio pre-USB.

## 1. Secuencia EXACTA del bring-up GMU en los clones vendor

Clon: `~/.hermes/profiles/coder/cache/scratch/vendor/op-sm7675`
(`vendor/qcom/opensource/graphics-kernel/` + `vendor/qcom/proprietary/graphics-devicetree/`).
Familia que nos toca: **gen7** (nuestro DT: `qcom,adreno-gmu-732.0` /
`-735.0`; el a6xx clásico usa otro offset — ver nota).

### 1.1 El voto RDPM (offset, valor, orden)

- `adreno_gen7.c:875-876`: `#define GEN7_RDPM_MX_OFFSET 0xf00`,
  `#define GEN7_RDPM_CX_OFFSET 0xf14`.
  (Nota: en `adreno_a6xx.c:848-849` el clásico usa MX 0xf00 / **CX 0xf18**.
  Para 732/735 vale **0xf14**.)
- `adreno_gen7.c:891-902` `gen7_rdpm_cx_freq_update(gmu, freq)`:
  `writel_relaxed(freq/1000, rdpm_cx_virt + 0xf14); wmb();`
  y nada más. Si `rdpm_cx_virt` es NULL, no hace nada (fail-open
  silencioso de fábrica).
- `adreno_gen7_gmu.c:1866-1895` `gen7_gmu_enable_clks(adreno_dev, level)` —
  orden literal (la cita pedida: `adreno_gen7_gmu.c:1868-1885`):
  1. `:1868` voto: `gen7_rdpm_cx_freq_update(gmu, gmu->freqs[level] / 1000);`
  2. `:1870` `kgsl_clk_set_rate(..., "gmu_clk", gmu->freqs[level])`
  3. `:1878` `kgsl_clk_set_rate(..., "hub_clk", adreno_dev->gmu_hub_clk_freq)`
  4. `:1885` `clk_bulk_prepare_enable(gmu->num_clks, gmu->clocks)`
- Doble `/1000` = el valor final es **MHz**: `220000000 → 220000 → 220`.
- Conclusión E0: el voto CX del vendor es **voltaje-por-frecuencia ANTES
  de programar los PLL y habilitar**. k65–k68 suben relojes sin este voto.

### 1.2 Qué guarda el rate antes del voto

- `gmu->freqs[]`: del DT `qcom,gmu-freq-table`
  (`adreno_gen7_gmu.c:2379-2398`). Ref. kalama: `kalama-gpu.dtsi` =
  `<220000000 LOW_SVS>, <550000000 SVS>`. Sin tabla: default
  `GMU_FREQ_MIN/MAX` (su `#define` no está en los headers del clon —
  no se pudo resolver el valor; irrelevante para C1, que no usa tabla).
- Hub: `adreno_gen7.c:329-332` `gen7_init`: `gmu_hub_clk_freq` del gpulist
  (`adreno-gpulist.h`: 200000000 en las entradas vistas) o default 150M.
- En C1 (sin D1/D2, sin rate objetivo) el equivalente es leer el
  **heredado XBL** con `clk_get_rate` y votar `heredado/1e6` MHz
  (fallback 220 si es 0), con `pr_err` del valor ANTES del writel.

### 1.3 Tablas RPMH

- `adreno_a6xx_rpmh.c:506-515`: `a6xx_build_rpmh_tables` =
  `build_dcvs_table` (votos GX/CX por nivel → `gx_votes[]`,
  `cx_arc_votes[]`) + `build_bw_table` (votos de bus).
- `a6xx_gmu_gfx_rail_on` (`adreno_a6xx_gmu.c:1244-1256`): escribe
  `GX_VOTE_IDX`/`MX_VOTE_IDX` + `a6xx_rdpm_mx_freq_update(...gx_votes.freq)`
  + OOB boot_slumber.
- Confirmación: `a6xx_complete_rpmh_votes(..., RPMH_VOTE_TIMEOUT=2ms)`
  (`:3026`, llamada `:3042`); PDC/RSC ucode se cargan DESPUÉS de
  `device_start` (first_boot `:2434-2438`). Todo esto vive en el GMU **ya
  alimentado**: sin el voto previo de §1.1 no arranca.

### 1.4 gpu_icc_path / hlos1 (y su equivalente mainline)

- Vendor `first_boot` (`adreno_a6xx_gmu.c:2411-2413`, gen7 idéntico):
  `level = pwrlevels[default].bus_min;`
  `icc_set_bw(pwr->icc_path, 0, kBps_to_icc(pwr->ddr_table[level]))`
  antes de `device_start`, y `icc_set_bw(pwr->icc_path, 0, 0)` tras
  `hfi_start` (`:2450`).
- DT: el path es `gfx-mem` (`palawan.dtsi:2388`, mainline; kalama igual).
- Equivalente k52-tree: `a6xx_gmu_set_initial_bw` (`a6xx_gmu.c:2207`,
  vía `dev_pm_opp_set_opp`) llamado en el resume **después** del enable
  de relojes. El hlos1_vote_gpu_smmu (K61) es el gate del SMMU, no el
  voto CX: no se toca en el plan-C.

## 2. Dónde injertarlo en k52-tree (fichero:línea) + parche mínimo

- Fichero: `build/kernel-pokes/k52-tree/drivers/gpu/drm/msm/adreno/a6xx_gmu.c`
- Función: `a6xx_gmu_resume` (`:2329`).
- Punto: tras `a6xx_gmu_gxpd_get` + `uke_poke("H2-gx")` (`:2345-2346`) y
  **antes** del bloque de rates (`clk_set_rate(hub)` en `:2357`) y del
  `clk_bulk_prepare_enable` (`:2361`). Réplica exacta del orden vendor
  (§1.1: voto → set_rate → enable).
- Estructura `struct a6xx_gmu` (`a6xx_gmu.h:63-140`): **sin campos rdpm**
  (confirmado E0) → no hay `rdpm_cx_virt` que reutilizar; el parche
  resuelve `platform_get_resource_byname(pdev, "rdpm_cx")` contra
  `to_platform_device(gmu->dev)` (igual que `a6xx_gmu_rpmh_init` hace
  con `gmu->dev` en el mismo fichero).
- Diff versionado (NO aplicado al tree): `build/gates/revision/k69-planC-C1.diff`
  (65 líneas: 1 include `<linux/io.h>` + bloque de 46 líneas).
- Fail-open documentado (no cuelga si el RDPM no responde):
  1. recurso ausente → `pr_err("...ausente(fail-open, sin MMIO)")` + sigue;
     **cero accesos MMIO**;
  2. `ioremap` NULL → `pr_err` + sigue;
  3. recurso presente → `writel_relaxed(mhz, b+0xf14); wmb(); iounmap(b)`
     + testigo con `@phys`. `iounmap` inmediato: cero mappings residuales.
- Límite honesto conocido: la base física del bloque RDPM_CX de uke/SM7675
  **no está** en `uke.dts` (DTBO descompilado) ni en `base-uke.dts`
  (solo TPDM-RDPM de coresight) ni en el clon op-sm7675 (el resource
  `rdpm_cx` no aparece en ningún `.dtsi` del clon: lo pondría el DT SoC
  o el bootloader). Caso esperado: recurso ausente → C1 ≡ k52+testigos.
  Queda PROHIBIDO inventar una dirección física a ciegas (un writel a una
  física errónea es peor que D1/D2: abort síncrono posible).

## 3. Variantes por riesgo + primera en flashear mañana

| Var | Qué hace | Riesgo | Qué discrimina si calla |
|---|---|---|---|
| **C1** | solo sonda+voto oportunista RDPM, **sin subir rates** (core+hub = XBL). Diff ya redactado. | **~0**: si el recurso falta (esperado), cero MMIO, cero cambios de reloj; si existe, un writel+ wmb con iounmap. | ¿sobrevive al probe? (casi seguro sí). Si el recurso EXISTE y aun así calla: voltaje solo no basta. Si falta: C1 ≡ k52+testigos, puerta de C2. |
| C2 | C1 + D1 (core 220M exacto tras el voto; hub queda XBL como k67). Réplica completa del orden vendor. | medio: programa `gpu_cc_pll1` dedicado (el menos sistémico, tesis k67). | Si C1 calla y C2 vive → faltaba rate con voto previo. Si ambas callan → el voto no llegó (base ausente) o el asesino está en el enable-path. |
| C3 | enables diferidos tras USB: resume-stub que devuelve 0 (GMU apagado, GPU muerta) + trigger manual (sysfs/debugfs) con USB vivo para el bring-up real. | bajo para USB, alto para el modelo de boot (cambia qué significa "arrancar": sin GPU hasta trigger). | Último recurso diagnóstico si C1+C2 callan: separa "mata el boot" de "mata el GMU". |

**Primera en flashear mañana: C1.** Porqué: riesgo ~0 fail-open (cero MMIO
en el caso esperado), coste 1 slot, y es la única que puede revelar —vía
testigo `UKE-C1` en pstore/forklog— si el bloque RDPM existe en el DT
fusionado sin arriesgar un abort. Además, si por sorpresa el recurso
existe, C1 sería el primer kernel que vota voltaje CX sin tocar relojes;
su silencio demostraría que el voltaje solo no basta y apuntaría al
enable-path/D1-D2. C2 solo tiene sentido DESPUÉS de C1 (mismo voto ya
probado in situ + una sola variable nueva = D1).

## 4. Receta REDACTADA sin ejecutar (la ejecuta el coordinador)

Build (clon de `build-k68.sh`, NO ejecutado aquí):

```bash
cp docs/historia/gates-palawan/build-k68.sh docs/historia/gates-palawan/build-k69.sh
# en build-k69.sh: s/K68/C1/ ; s/k68/k69/ ; aplicar el diff tras el checkout:
#   patch -p1 < build/gates/revision/k69-planC-C1.diff   # dentro de k69-tree
./docs/historia/gates-palawan/build-k69.sh   # ~60 min, lo hace el coordinador
```

Verificación (gates, sin flashear):

```bash
grep -c 'UKE-C1' k69-tree/drivers/gpu/drm/msm/adreno/a6xx_gmu.c  # >=4
grep -c 'H2-cxvoto' k69-tree/drivers/gpu/drm/msm/adreno/a6xx_gmu.c # 1
grep -c 'linux/io.h' k69-tree/drivers/gpu/drm/msm/adreno/a6xx_gmu.c # 1
# Image ~41 MB + sha256 al ledger; strings Image | grep -c UKE-C1 (>=4)
```

Repack + flash (mañana, 1 slot):

```bash
# repack boot_a con Image k69 (receta RUNBOOK-FLASH-FIX529), boot stage=2
# trazas: `UKE-C1: voto CX pre-rate: rdpm_cx ...` + `H2-cxvoto` en pstore/forklog
```

Fila ledger #559 REDACTADA (pendiente de build+flash del coordinador):

```
#559 k69/C1 (PLAN-C) — voto CX vendor fail-open sin rates. Esperado: rdpm_cx
ausente → pr_err + sigue (≡k52+testigos). Resultado: ___. pstore: ___.
Decisión: si PRESENTE+vive → C1 era el voltaje; si PRESENTE+calla → pasar a
C2; si ausente+calla → pasar a C2 (voto ya probado in situ + D1).
```

Dry-run ejecutado en este turno (sin compilar): `patch --dry-run` del diff
contra copia de `a6xx_gmu.c` → `patch_rc=0`, aplica limpio; balance
llaves/paréntesis del bloque = 0/0; `git status build/kernel-pokes/k52-tree/`
vacío (tree intacto, el diff es archivo nuevo sin aplicar).
