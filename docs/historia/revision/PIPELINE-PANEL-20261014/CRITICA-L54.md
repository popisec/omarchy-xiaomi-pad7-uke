# CRÍTICA L54 — screen `regulator_ignore_unused` (hipótesis AVDD) — 14-oct-2026

> Adversarial, solo lectura. Base: `L54-POWER-PANEL.md`, stock `dtbo-stock-decomp.dts`,
> `fase4-display.dts:117-148`, `core.c:6788-6860`, `repack-k52L54.py`, s287 binario, L53 report.

## 1. Hipótesis AVDD: bien fundada en (a–c), FALSA en (d) — parar y releer

- (a) ✓ o82 = `dsi_panel_pwr_supply_O82` (frag@97: vddil8b `0x1cfde0`=1,9 V vía L8B frag@100;
  vsp/vsn `0x588040`=±5,8 V) + frag@98 (TLMM 74/75=`0x4a/0x4b`, boot-on). Sin LAB/IBB en stock ✓.
- (b) ✓ `display_panel_avdd` en `:1543-1556`: `qti-regulator-fixed`, `0x53ec60`=5,5 V,
  `pm8550ve` GPIO 8, `boot-on`, proxy propio.
- (c) ✓ Nuestro DT **no lo declara**: grep vacío en `arch/arm64/boot/dts/qcom/` y en
  `fase4-display.dts` (solo TODO `:117-122`); `strings s287-*.img`: **cero `avdd`**
  (solo `pm8550vs` térmicos). En vivo tampoco existe (`NOTAS:905-907`: summary con vsp/vsn, sin avdd).
- (d) ✗ **El late-cleanup NO puede apagar lo que nunca se registró.** `core.c:6788-6817`:
  itera `regulator_class` (= solo rdevs registrados) y apaga enabled+unused+no-`always_on`
  con full constraints — `boot-on` **no protege** (solo `always_on`/`use_count`; el `disabling`
  de vsp/vsn ~33 s lo prueba, esos SÍ registrados). Sin nodo DT no hay rdev ⇒ el kernel no toca
  pm8550ve-8 ⇒ el pin queda como lo dejó el ABL: **alto, AVDD ya ON**. "Lo apaga ~33 s" es falso;
  el flag no cambia el estado de AVDD. El doc §2 l.42-44 y §4 l.62-63 deben corregirse.

## 2. `regulator_ignore_unused`: qué hace y riesgos

- Exacto (`core.c:6840-6850`, "for debugging purposes"): **salta el late-cleanup entero** ⇒
  preserva TODOS los raíles ABL registrados-y-sin-consumidor (el dip vsp/vsn 33 s→prepare ~55 s
  desaparece, más leftovers de cámara/módem/GPU). Global, no selectivo.
- Side effects: más consumo/calor idle **un boot**; ningún raíl con consumidor cambia; sin riesgo
  de estabilidad ni brick (mismo kernel L53 que vivió 184 s + un token cmdline). Gate/criterio
  extra que SÍ merece: capturar `regulator_summary` por SSH post-boot (qué raíles siguieron on
  vs L53) — barato y es lo que permite atribuir un positivo.

## 3. Veredicto aplicado: L54 NO testea AVDD; testea la familia "power-window"

- Un positivo NO probaría AVDD (ya estaba on) sino algún raíl REGISTRADO (dip vsp/vsn u otro) ⇒
  el follow-up sería bisect por summary, no "declarar AVDD". Un negativo mata la familia entera,
  incluido AVDD-como-raíl-perdido. Sigue siendo un screen barato de una variable.
- Corrección al doc §5(c): `display_panel_avdd/state` saldrá **ausente siempre** (no registrado);
  ausente ≠ apagado. AVDD solo se verifica por nivel del GPIO (`/sys/kernel/debug/gpio`,
  línea pm8550ve-8) o voltímetro, no por summary.

## 4. Cmdline/gates: el encargo traía 646, lo correcto es 632

- Aritmética: ` regulator_ignore_unused`=24, ` ignore_loglevel`=16 ⇒ **624−16+24=632**, no 646
  (624−16+38). El propio script lo detectó y corrigió (cabecera :8-9) y lo gatea dos veces
  (:211 len==632; :526-532 byte-idéntica a k64−video+reclaim+regulator) ✓.
- Quitar `ignore_loglevel` no pierde nada crítico: K53=`pr_err` vive siempre en el ring buffer
  (`dmesg` ✓); netconsole se arma tras red (~10 s+) ⇒ los dumps de 4 s nunca viajaron por ahí
  con ni sin token; ACM bajo loglevel 1 los ocultaría, pero el criterio L54 es LUZ, no dumps
  (L53 ya cerró KTZ-idéntico). Gates intactos: POKE=121, K50×18, S4-DIAG×4, FIX-A1b×6,
  FIX-A1:×0, UKE-K53×1+3 tags, sin wmask/loglevel, KERNEL=k52L53-build + gate G0 anti-rancio ✓.

## 5. Criterio/riesgos

- PASA = luz (o intermedio: blanco/off distinto del negro L53); FALLA = negro idéntico ⇒ muerta
  la familia power-window ⇒ branch B (DCS 0x51, `VERIF-K52B2` §5). Rollback: **L53 `c6b64752…`**
  (verificado en `repack-k52L53-report.txt:39`, fichero presente; L52 `0cd89f96…` como 2º).
  Riesgo brick ~0 (repack-only, 1 escritura `boot_a`, sddm off, s287 se queda).

## VEREDICTO: **PASA flashear L54** (screen seguro y decisivo de la familia power-window),
**NO como confirmación de AVDD**: corregir el doc §2/§4/§5(c) antes de la fila del ledger.
