# S5 — Porte del linaje L39 al vivo (display path) (14-oct-2026)

> Base del porte: árbol vivo `build/kernel-pokes/k52-L16-tree` (origen de L19→L43→L44→L45).
> Origen: `build/kernel-pokes/k52L39-tree` (+ ancestros k52L33-tree/k52L27-tree para config).
> Regla cumplida: árboles intactos (solo `diff`, más `patch --dry-run` sobre copia en `/tmp`).

## 1. Qué he leído (lista con fichero:línea de lo relevante)

- `docs/historia/revision/PIPELINE-PANEL-20261014/BRIEF.md:8-24` (estado vivo L45+s286, crux primer DCS).
- `build/gates/revision/AUDITORIA-METODO-20261013.md:16-17` (L39 empaquetó 4 cambios; `=y` wedgeó y se
  revirtió en `5c82899`), `:55` (ronda PHY refutada/inerte con control), `:64-88` (tabla de veredictos
  G1/G4/G5/G6/G7/G8 + escalera, peldaños 2 = reset 15 ms, 3 = PPS ×2 `06708b1`).
- `build/gates/revision/L39-PLAN-20261013.md:292-298` (los 4 símbolos `=m→=y`: BATTMGR, PMIC_GLINK,
  UCSI_PMIC_GLINK), `:325-331` (KTZ8866=y inerte en L39: sin nodo DT en s281).
- `build/gates/revision/L39-RESULTADO-20261013.md §5` (L39 flasheado = G6+G5+L38+`=y`), `§10`
  (L39b: config revertida a `=m`, panel sin `card1` por falta de I2C).
- `NOTAS-OMARCHY.md:3809-3826` (flash L37 `aed378c3`: muerte 29,4 s en `w4-done`, `L37-pps` ×0 ⇒
  PPS nunca ejecutadas), `:4010-4020` (tabla: L36 `b541df0e` flasheado con 2 variables;
  L37 flasheado; **L38 `338d921c` construido 20:33 pero NO flasheado**).
- `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md:12630` (L33 es anterior al parche L36).
- `git show 06708b1` (13-oct 13:31: PPS a los dos links, "sin flash, tablet caída").
- `docs/historia/revision/PIPELINE-PANEL-20261014/s3-reset-tddi.diff` (S3 ya porta el reset 15 ms + doble
  reset + Hi-Z; ver §6).
- Diffs propios: `diff -ru k52L39-tree k52-L16-tree` (drm completo), `drivers/clk/`, `arch/arm64/boot/dts/`
  (idéntico: nada que portar en DT), `drivers/video/backlight/ktz8866.c`, `drivers/soc/qcom/qcom-geni-se.c`,
  `include/linux/uke-poke.h`, y `.config` L27↔L33↔L39↔L45.

## 2. Estado real del asunto (evidencia)

### 2.1. Diff dirigido: 12 hunks, cada uno con su origen

Dirección de lectura: `---` = L39, `+++` = vivo. Ficheros que difieren bajo `drivers/gpu/drm/`:
solo 6 (`dpu_kms.c`, `dsi_host.c`, `dsi_phy_7nm.c`, `msm_drv.c`, `msm_mdss.c`,
`panel-xiaomi-o82-dualdsi.c`); el resto del drm es idéntico. `arch/arm64/boot/dts/` es
**idéntico** entre árboles (el DT del display vive en el dtbo s286, fuera de S5).

| # | Hunk (fichero) | Origen | Estado en el vivo | Decisión S5 |
|---|---|---|---|---|
| H1 | `LANE_CTRL0 0x1f→0x15` (`dsi/phy/dsi_phy_7nm.c`, en L39) | GAP G5 (`l39`, `vendor-o82-dsi4nm.h:125`) | Ausente en vivo (vivo = `0x1f`) | **NO portar**: inerte en paquete L39, sin señal (auditoría §2). Re-probarlo violaría la escalera |
| H2 | 14 `TIMING_CTRL` vendor fijos (`dsi_phy_7nm.c`) | GAP G6 (RE `dsi_phy_hw_v4_0_cache_phy_timings`) | Ausente (vivo calcula) | **NO portar**: inerte en paquete, sin señal |
| H3 | `enable_ssc=true` (`dsi_phy_7nm.c`) | G7 | Ausente (vivo `false`) | **NO portar**: refutado con control L40 vs L42 (auditoría §2) |
| H4 | lane-map `0xAA/0xAA` + comentario G4 (`dsi_phy_7nm.c`) | G4 (hipótesis falsable) | Valores idénticos (`0x21/0x84` en ambos); solo difiere el comentario | Nada que portar; **refutado con control** L40 vs L41 |
| H5 | `dsi_wait4video_eng_busy` early-return + `pr_info` pre-flush (`dsi_host.c`: L34+L36) | `l34-timing-flush.diff`, `l36-no-video-wait-cmd.diff` | Ausentes en vivo | **NO portar**: L34-flush hizo daño medido (8→12 `status=4`, muerte adelantada; retirado por L36). El early-return se flasheó (L36 `b541df0e`) empaquetado con el flush-fuera, gate tautológico, y **nunca se ejecutó** (muerte en `w4-done`, antes de cualquier DCS). Sin señal; el camino DCS es de S4 |
| H6 | PPS DSC a los dos links + `#include drm_dsc_helper.h` (`panel-…o82….c`) | L37 + L40 (`06708b1`) | Ausente en vivo | **PORTAR (s5a)**: peldaño 3 de la escalera. OJO: L37 se flasheó (`aed378c3`) pero las PPS **nunca llegaron a ejecutarse** (`L37-pps` ×0, muerte en `w4-done`) ⇒ estado real = **no probada**, no "inerte medida". Solo puede evaluarse cuando el punto de muerte pase del reset (peldaño 2/S3 primero) |
| H7 | reset final 100 ms (vivo) vs 15 ms (L39) | L38 (vendor `(0,10),(1,3),(0,3),(1,15)`) | Vivo = 100 ms (discriminador r7) | **Deferido a S3**: `docs/historia/revision/PIPELINE-PANEL-20261014/s3-reset-tddi.diff` ya lo porta (15 ms + doble reset + Hi-Z). S5 no duplica (ver §6) |
| H8 | pokes K47 `pan-pwron/pwron-ok/pan-probe/probe-ok/attach-ok` (panel) | instrumentación L39 | Ausentes (vivo tiene `K47-pan-pwr/pwr-OK/pan-prep/pre-rst…`, `panel-…:293,314,327,351-356`) | **NO portar**: duplican marcadores que el vivo ya tiene en los mismos puntos; valor diagnóstico ≈ 0 |
| H9 | gate L24 `uke_skip_mdss_reset` (L39) vs herencia L22 `uke_panel_inherit` (vivo): `msm_drv.c`, `msm_mdss.c`, `dpu_kms.c`, `clk/qcom/dispcc-sm8550.c`, `uke-poke.h` | L22/L22b vs L24 | Vivo = herencia L22 en 5 ficheros | **NO portar**: es un mecanismo alternativo, no un fix del display path; portarlo **regresaría** el vivo (borraría la herencia). Decisión arquitectónica del integrador, no de S5 |
| H10 | comentario backlight L39b (panel probe) | L39b/L40 | Vivo lo supera (L44 warn + L45 `-EPROBE_DEFER`, `panel-…:746-758`) | Nada que portar (vivo por delante) |
| H11 | KTZ B1 `-ENODEV` + GENI L43-ICC (`ktz8866.c`, `qcom-geni-se.c`) | L44-crítica, L43 | Solo en vivo (L39 = stock) | Dirección inversa: ya están en el vivo. **No regresarlos** |
| H12 | 4 símbolos `=m→=y` | L39-PLAN §5 | Revertidos: L39-build y L45-build tienen `BATTMGR/PMIC_GLINK/UCSI_PM =m` (ambos `.config:3855/6337/7284`); `KTZ8866=y` en **ambos** (L39:5217, L45:5226) | **NO portar**: el `=y` wedgeó (revertido en `5c82899`); lo único útil del paquete (KTZ built-in) ya está en el vivo |

### 2.2. Qué queda en pie para portar

Solo **H6 (PPS ×2)**. Todo lo demás está refutado, inerte, ya presente en el vivo, deferido a
otra sección, o arquitectónicamente incompatible. Un único `s5a-*.diff`, un cambio por ciclo.

## 3. Cambio propuesto (diff exacto, con fichero:línea)

**Fichero**: `docs/historia/revision/PIPELINE-PANEL-20261014/s5a-pps-dual-link.diff`
(aplicable con `patch -p1` desde la raíz del árbol vivo; verificado `--dry-run` OK sobre copia,
y aplicación real sobre copia en `/tmp/opencode/s5a-tree`).

- Hunk 1 (vivo `panel-xiaomi-o82-dualdsi.c:31`): añade
  `#include <drm/display/drm_dsc_helper.h>` (existe en el vivo:
  `include/drm/display/drm_dsc_helper.h:24` declara `drm_dsc_pps_payload_pack`).
- Hunk 2 (vivo `panel-…:358-363`, tras `init cmds rc=` / `goto err;`, antes de `u8 freq_sel[2];`):
  bloque PPS L37+L40 **verbatim del L39** (`k52L39-tree/…/panel-xiaomi-o82-dualdsi.c:365-414`).
  Compilación conceptual verificada símbolo a símbolo contra el vivo:
  `mipi_dsi_picture_parameter_set_multi` (`include/drm/drm_mipi_dsi.h:290-291`,
  `drivers/gpu/drm/drm_mipi_dsi.c:1553,1570` con `EXPORT_SYMBOL`), `struct
  drm_dsc_picture_parameter_set` (`include/drm/display/drm_dsc.h:283`), `ctx->dsc`
  (`panel-…:52`), `dsi_ctx` (`panel-…:330`), `uke_poke` (vivo lo usa en el mismo fichero),
  etiqueta `err` (existe). Precedente de que compila: L37 se construyó y flasheó (`aed378c3`).
- Posición idéntica a L39 ⇒ **compatible con `docs/historia/revision/PIPELINE-PANEL-20261014/s3-reset-tddi.diff`** (S3 toca reset/probe/`err:`,
  regiones disjuntas; solo desplaza líneas, el contexto del hunk sigue aplicando).

Imperfección conocida y declarada (heredada de L40, en el propio comentario del diff):
`pic_width/pic_height` del PPS salen del template (0 a prepare-time); el vendor los lleva del
modo. Verificación byte-a-byte pendiente (material para S4, no bloquea el peldaño).

## 4. Criterio pasa/falla prefijado (comando + salida esperada)

Precondición de orden (escalera §3): **s5a solo se flashea sobre un kernel cuyo punto de muerte
esté MÁS ALLÁ de `K48-w4-done`** (peldaño 2/S3 cumplido). Sin eso el bloque es inalcanzable y el
ciclo no atribuye (eso fue exactamente L37). Mismo dtbo, modo preferido, doble captura
(ACM + `dmesg -w` por SSH), batería ≥3700 mV registrada antes.

- **PASA** si en la doble captura aparecen `L37-pps-pack`, `L37-pps-send` y `L37-pps-done`
  (comando: `grep -c 'L37-pps' acm.log dmesg.log` ⇒ ≥3 en ambos) **y** a partir de ahí se lee la
  firma: cualquier cambio de firma cuenta como señal (peldaño direccional); firma idéntica =
  "inerte", que es lo que la escalera espera (corrección de corrección).
- **FALLA / no atribuible** si `grep -c 'L37-pps'` = 0 (muerte aún en `w4-done` o antes): el
  peldaño no se ejecutó ⇒ no se concluye nada sobre la PPS; se vuelve al peldaño 2, no se apila
  nada más.
- Gate de parada: al primer peldaño que no cumpla su "pasa", se para y se aísla (auditoría §3).

## 5. Riesgos y refutaciones que aplican (REFUTADO/LECCIONES)

- **E1-empaquetado** (auditoría §2): L39 llevó 4 cambios y L36 llevó 2; s5a es deliberadamente UN
  solo cambio para no repetirlo. No mezclar con S1/S2/S3/S6 en el mismo flash.
- **E3-batería**: L39 leyó "muerte antes de 3,5 s" sin gate previo citado; exigir ≥3700 mV antes.
- **L34-flush**: excluido a propósito; reintroducirlo sería re-probar un daño medido.
- **`=y`**: excluido; wedgeó y se revirtió (`5c82899`); el vivo ya está en el estado post-reversión.
- **G4/G5/G6/G7**: refutados/inertes con control; la tentación de "ya que flasheamos, meter G5+G6"
  es exactamente el error L39. No.
- **L22 vs L24** (H9): si el ciclo display-ON futuro abandona la herencia, es decisión del
  integrador con su propio criterio, no un porte silencioso dentro de S5.
- Refutación que S5 **no** necesita re-leer: `REFUTADO.md`/`LECCIONES.md` del proyecto hermano
  (ningún hunk S5 solapa con sus ~56 refutaciones; verificado por nombre: G4/G5/G6/G7 ya cerrados
  en este proyecto).

## 6. Qué NO hacer / lo que queda fuera

1. No portar H1/H2/H3/H4 (PHY: inertes/refutados), H5 (L34 dañino; L36 sin señal y fuera de la
   escalera), H8 (pokes redundantes), H9 (regresión de herencia), H12 (config wedgeada).
2. No duplicar H7: el reset 15 ms vive en `docs/historia/revision/PIPELINE-PANEL-20261014/s3-reset-tddi.diff` (S3 lo extiende con doble reset y
   Hi-Z; el L38 "puro" ya no existe como opción aislada y S3 es su heredero declarado).
3. No tocar DT/Kconfig: `arch/arm64/boot/dts/` idéntico entre árboles; `.config` display ya
   convergente (KTZ8866=y en ambos; solo difieren fbdev/initramfs, fuera del display path).
4. No adelantar s5a antes que S3: sin peldaño 2, s5a es código muerto (lección L37).
5. Fuera de alcance (BRIEF §"Fuera"): flashear, G8 (S2), minucias DT (S6), muerte DCS (S4).
