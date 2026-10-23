# REVIEW-S5 — Revisión adversarial del porte L39→vivo (14-oct-2026)

> Alcance: `docs/historia/revision/PIPELINE-PANEL-20261014/S5-PORT-L39.md` + `docs/historia/revision/PIPELINE-PANEL-20261014/s5a-pps-dual-link.diff` (PIPELINE-PANEL-20261014).
> Método: diff dirigido reproducido (`diff -rq` + `diff -ru --exclude=build`,
> 730 líneas en `/tmp/opencode/s5-full.diff`), `patch --dry-run` y aplicación
> secuencial S3→S5a sobre copias en `/tmp/opencode/` (árboles intactos),
> verificación símbolo a símbolo en `k52-L16-tree`, y contraste de cada cita
> con su fuente. Solo lectura en todo.

## 1. Veredicto: OK-con-notas

El inventario cubre los 10 ficheros que difieren, los veredictos de portar/no
son correctos en los 12 casos, el diff aplica limpio y es compatible con S3/S4,
y el criterio es medible. Pero hay **una discrepancia factual con evidencia
falsa citada (N1)** que debe corregirse antes del flash, más 6 notas menores.
Ninguna cambia el porte (sigue siendo: solo PPS dual-link).

## 2. Lo verificado (evidencia)

- **Cobertura del diff**: `diff -rq k52L39-tree k52-L16-tree` da exactamente 10
  ficheros (más `build/`): `clk/qcom/dispcc-sm8550.c`, `dpu_kms.c`, `dsi_host.c`,
  `dsi_phy_7nm.c`, `msm_drv.c`, `msm_mdss.c`, `panel-xiaomi-o82-dualdsi.c`,
  `qcom-geni-se.c`, `ktz8866.c`, `uke-poke.h`. Los 6 bajo `drm/` que cita S5 §2.1
  son exactos; `arch/` (DT) idéntico (exit 0); `drivers/clk/` solo dispcc. No
  falta ningún fichero del display path.
- **H1/H2/H3/H4** (PHY): LANE_CTRL0 0x15-vs-0x1f, 14 TIMING_CTRL vendor fijos,
  `enable_ssc=true`-vs-`false`, comentario lane-swap con valores 0x21/0x84
  idénticos — todo coincide con el diff (líneas 216-218, 226-233, 241-273,
  279-332 de `/tmp/opencode/s5-full.diff`). Veredictos coherentes con
  `AUDITORIA-METODO-20261013.md:55,68` (G5 inerte en paquete, G7 refutado con
  control L40-vs-L42, G4 refutado L40-vs-L41).
- **H5**: los 2 hunks L34-flush + L36-early-return existen en el diff (líneas
  98-179). Veredicto NO-portar correcto (ver N1 por la justificación).
- **H6 (PPS)**: existe solo en L39 (diff líneas 469-518), ausente en vivo.
  Contenido **verbatim** verificado por script (normalizado, excl. `#include`):
  `body-verbatim: True`, incluyendo el dual-link de `06708b1`
  (`dsi[0]`/`dsi[1]`, `k52L39-tree/…/panel:399-403`) y la nota pic_width.
- **Claim L37** ✓: `NOTAS-OMARCHY.md:3806-3826` — flash `aed378c3`, muerte
  29,4 s en `K48-w4-done`, `grep -c 'L37-pps' = 0` (ACM, 2 arranques). La
  conclusión «no probada, no inerte» es la lectura correcta.
- **H7/H9/H10/H11**: reset 100-vs-15 ms ✓ (diff 414-429); L24-vs-L22 en
  msm_drv/msm_mdss/dpu_kms/dispcc/uke-poke.h ✓; backlight L44+L45 por delante
  en vivo ✓ (diff 592-623); GENI-ICC + KTZ-B1 solo en vivo ✓ (diff 644-711).
- **H12**: `.config` verificados — L39-build `:3855/=m,:6337/=m,:7284/=m`,
  `:5217 KTZ=y`; L45-build `:3855/=m`, KTZ `:5226=y` (ver N2/N3).
- **s5a aplica limpio**: `--dry-run` OK sobre copia; tras aplicar
  `docs/historia/revision/PIPELINE-PANEL-20261014/s3-reset-tddi.diff`, s5a entra con offset 10 líneas, sin fuzz
  (`Hunk #2 succeeded at 371`). S4 toca solo `dsi_host.c`: disjunto por
  construcción. Punto de inserción confirmado en vivo (`panel:360-366`,
  `goto err;` → bloque → `u8 freq_sel[2];`, etiqueta `err:` existe).
- **Símbolos**: `mipi_dsi_picture_parameter_set_multi` en
  `drm_mipi_dsi.h:290-291`, def. `drm_mipi_dsi.c:1553` + `EXPORT_SYMBOL`
  (línea ~1569); `struct drm_dsc_picture_parameter_set` en `drm_dsc.h:283`;
  `drm_dsc_pps_payload_pack` en `drm_dsc_helper.h:24`; `ctx->dsc`
  (`panel:52`), `dsi_ctx` (`panel:330`), `uke-poke.h` incluido (`panel:22`).
- **Coherencia**: peldaño 3 de la escalera citado fiel
  (`AUDITORIA-METODO:86`, «se espera inerte: es corrección de corrección»).
  Sin solape con el hermano: `grep -i pps/dsc/ssc/lane/flush` en su
  `REFUTADO.md`/`LECCIONES.md` solo da falsos positivos (tabla, smmu).
- **Pregunta clave (.config / uke-poke.h)**: `diff` de `.config`
  L39-build↔L45-build = 13 líneas: initramfs + bloque fbdev
  (`DRM_FBDEV_EMULATION=y`, `DRM_CLIENT*`, `MSM_KMS_FBDEV`,
  `FB_DMAMEM_HELPERS*`). Nada display-pendiente que portar **desde** L39
  (el vivo va por delante; portar sería regresar). `uke-poke.h`: solo el
  renombre L24→L22. **No hay nada más que portar.** (Ver N5 por el matiz
  fbdev.)

## 3. Discrepancias y correcciones

### N1 [factual, corregir antes del flash] — H5 cita un «daño medido» refutado
- S5 §2.1 H5 y §5: «L34-flush hizo daño medido (8→12 `status=4`, muerte
  adelantada; retirado por L36)».
- La fuente lo desmiente: `NOTAS-OMARCHY.md:3654-3665` titula
  «"Los errores de FIFO pasaron de 8 a 12" — FALSO, inventado» (10/10/10 en
  las tres ventanas; `pr_err_ratelimited` topa la ráfaga), y `:3680-3700`
  añade: solo-ACM sin doble captura, modos distintos (preferido vs 60 Hz
  forzado inexistente), gate tautológico. `NOTAS:4024-4026` deja el punto
  como «blando / no atribuible».
- **Corrección**: el veredicto NO-portar se mantiene, pero la justificación
  debe ser «sin señal atribuible (modos distintos, ACM-only, gate
  tautológico) + contraejemplo sheng (enciende sin flush)»,
  **no** «daño medido 8→12». Citar un número ya refutado como evidencia es
  exactamente el error E-atribución que la auditoría denuncia.

### N2 [factual menor] — «4 símbolos `=m→=y`» son 3
- `L39-PLAN-20261013.md:292-298` dice «Cuatro» pero lista 3 (BATTMGR,
  PMIC_GLINK, UCSI_PMIC_GLINK); el revert `5c82899` dice «los 3 símbolos»;
  ambos `.config` confirman 3. Corregir H12 a 3.

### N3 [menor] — líneas `.config` de L45
- H12 «ambos `.config:3855/6337/7284`» es exacto solo en L39-build; en
  L45-build son `3855/6346/7293` (KTZ `5217` vs `5226`). Anotar el desfase.

### N4 [inventario incompleto, sin cambio de veredicto] — H9 omite la herencia en el panel
- H9 lista 5 ficheros (msm_drv, msm_mdss, dpu_kms, dispcc, uke-poke.h) pero el
  vivo tiene **3 hunks más de herencia L22 en `panel-xiaomi-o82-dualdsi.c`**:
  skip en `prepare` (`k52-L16-tree/…/panel:352-361`), skip en `unprepare`
  (`:527-534`), gpio reset `OUT_LOW` + `P82-inh-probe` (`:550-565`).
- Son solo-vivo ⇒ veredicto NO-portar idéntico, pero «12 hunks, cada uno con
  su origen» no los cubre (el diff real tiene 29 hunks `@@` agrupados en 12
  filas). Añadir fila/mención para que el inventario sea exhaustivo.

### N5 [matiz de argumento] — fbdev no es «fuera del display path»
- S5 §6.3: «solo difieren fbdev/initramfs, fuera del display path». Pero
  `L39-RESULTADO-20261013.md §2` establece que `FBDEV_EMULATION=n` + sin
  `video=` ⇒ el kernel no hace modeset al arrancar: fbdev **determina si el
  camino commit/DCS se ejecuta**, que es el centro del crux. El veredicto
  (nada que portar, el vivo ya lleva `=y`) es correcto; corregir el argumento
  a «el vivo ya va por delante; portar `=n` sería regresar».

### N6 [recomendación] — compilar s5a antes del ciclo
- El «precedente de que compila» citado (L37 `aed378c3`) cubre la PPS
  **single-link**; el texto exacto dual-link (`06708b1`) es «sin flash,
  tablet caída». El riesgo es mínimo (misma función ×2), pero un build
  sintáctico sobre copia es barato, de solo-lectura y cierra el hueco:
  aplicar s5a (+S3 si toca) en copia y compilar el objeto antes de pedir
  el flash.

### N7 [sugerencia de criterio] — desempate ACM vs SSH
- PASA exige `≥3 en ambos` (ACM + dmesg). Con ACM lossy documentado, el caso
  «×3 en dmesg-SSH y ×0 en ACM» caería en «no atribuible» pudiendo atribuir.
  Sugerencia: **manda el dmesg por SSH; el ACM corrobora**. Evita quemar un
  ciclo por pérdida de consola, sin riesgo de falso positivo (el dmesg-SSH
  no pierde líneas).

## 4. Respuesta a las 6 preguntas del encargo
1. Inventario: completo en ficheros y veredictos; ver N4 (hunks de herencia
   del panel no listados) y N1 (justificación H5 con número refutado).
2. Claim L37: confirmado en NOTAS:3806-3826; lectura «no probada» correcta.
3. s5a: dry-run OK, aplicación real OK sobre copia, secuencial tras S3 OK
   (offset 10, sin fuzz); símbolos y punto de inserción verificados; S4
   disjunto. Árboles intactos.
4. Coherencia auditoría/REFUTADO/LECCIONES: sí, sin solape con el hermano.
5. Criterio: coherente, medible y conservador; ver N7 para el desempate.
6. ¿Algo más que portar? No: `.config` (13 líneas: initramfs+fbdev, vivo por
   delante) y `uke-poke.h` (solo renombre) verificados. Ver N5.
