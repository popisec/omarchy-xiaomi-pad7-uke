# CRÍTICA L63 (adversarial, solo lectura) · 14-oct-2026

## 1. Enable hook — verificado en vivo
`o82_enable` en árbol (`panel-xiaomi-o82-dualdsi.c:606-636`,
`.enable` en `:637`; `UKE-L63`×1, `L63-pps-post` poke OK). Cadena
**probada ya por L62** (sus `UKE-L37/L62` salen por la misma vía):
`dsi_bind` (`msm/dsi/dsi.c:131-136`, `devm_drm_of_get_bridge` →
panel_bridge) → `dsi_manager.c:449` attach → `bridge/panel.c:148` →
`drm_panel_enable` (`drm_panel.c:240`) → nuestro `.enable`. El `.enable`
**sí será llamado**. `ctx->dsi[]` válidos (probe), dims idénticas a L62
(`modes[0].hdisplay/2`=1600, `vdisplay`=2136; `num_modes=1`, `:726`,
índice seguro). Copia local `dsc_link`, ×2 links, restaura `dsi[0]`:
patrón L62 bien reutilizado. `pr_info` en una línea (robusto).
Inherit → skip coherente (prepare tampoco corrió; el panel heredado
conserva la PPS del ABL). Matiz: "vídeo ya andando" es impreciso (el
orden exacto vs el host depende de la cadena); lo garantizado y
suficiente es **despierto + post-0x29** (0x29 en prepare `:486-487`).

## 2. Doble envío OK, sin regresión
Set-PPS es escritura de estado idempotente; el pre-envío L62 ya demostró
no dañar (negra-con-luz sin wedge). Mismas dims pre/post. Coste: 2×128 B
DCS. Errores contenidos: `drm_panel_enable` es `void` y traga el error;
**pero ojo**: `ret<0` → `goto exit` salta `enabled=true` **y el
backlight** (`drm_panel.c:255-266`) ⇒ fallo PPS-post = panel apagado a
oscuras, distinguible por `UKE-L63 err!=0`. Fail-closed, correcto.

## 3. Config carga — 2 líneas exactas, riesgo residual real
`diff k52L62→k52L63` = solo `UCSI_PMIC_GLINK m→y` (`:6347`) y
`QCOM_PMIC_GLINK m→y` (`:7294`); `BATTMGR` sigue `=m` (`:3856`); deps
ya `=y` (`QRTR_SMD:1604`, `Q6V5_PAS`, glink-rpm/smem, `RPMSG_QCOM_*`);
guard doble-nodo presente en árbol (`pmic_glink.c:314-315`). Pero:
**`UCSI=y` no ha arrancado nunca** en ningún árbol (solo argumento de
código "inerte sin ADSP"); `GLINK=y` solo tiene precedente hermano
(R-32 exonera pmic_glink *solo*) y el propio `docs/historia/revision/PIPELINE-PANEL-20261014/L60-FALLO-ARRANQUE.md:11`
lo llama co-sospechoso. L63 mezcla 2 cambios/ciclo (PPS + carga):
aceptable porque los modos de fallo son disjuntos (wedge≠negra), pero
si wedgea no se aprende nada de la PPS y se gasta el ciclo.

## 4. Gates — corrección: "19/1/1" sin fuente
**No localicé el origen de "19/1/1"** en `CARGA-KERNEL.md` ni docs L60:
NO exigirlo. Sustituir por baseline **medido en L62 antes del flash**:
`ls /sys/class/power_supply/ | sort` +
`dmesg | grep -ciE 'pmic.?glink|ucsi'` y repetir en L63 (delta
explícito). Resto válido: fuente `UKE-L63`×1, binario `strings|grep -c
UKE-L63`=1, vivo `UKE-L63 … err=0` + orden L37→L62→L63. Repack clon L62.
Criterio: PASA=contenido; negro+L63 err=0⇒cerrar rama PPS
(`docs/historia/revision/PIPELINE-PANEL-20261014/s6-noncontinuous.diff`); wedge⇒rollback L62 `d52f5967…`/L59 `e3511595…`
y replantear carga (vía `.ko`+insmod, `docs/historia/revision/PIPELINE-PANEL-20261014/L60-FALLO-ARRANQUE.md:58-60`).

## VEREDICTO: PASA flashear L63
Sin correcciones de código. Exigir pre-vuelo completo (batería, slots,
ACM+vigía, pre-registro) + baseline L62 de carga. Gate vivo adicional:
`dmesg | grep -E 'UKE-L(37|62|63)|backlight|ktz'`.
