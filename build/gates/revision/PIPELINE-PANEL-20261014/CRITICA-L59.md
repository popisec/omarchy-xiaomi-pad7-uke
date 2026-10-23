# CRÍTICA L59 (adversarial, solo lectura) · 14-oct-2026

## 1. Diff aplicado — verificado en vivo
`k52-L16-tree/.../panel-xiaomi-o82-dualdsi.c:32,389-438`: include
`drm_dsc_helper.h` (existe en `include/drm/display/`, declara el pack
`:24`); bloque PPS tras init-cmds, antes de `freq_sel`/0x11/0x29;
2 envíos (`dsi[0]`,`dsi[1]`, restaura `dsi[0]`); idéntico byte a byte a
`docs/historia/revision/PIPELINE-PANEL-20261014/s5a-pps-dual-link.diff` (`diff` = IDENTICOS) y verbatim de
`k52L39-tree:...:365-414`. `uke_poke` declarado (`linux/uke-poke.h:22`);
pinta framebuffer síncrono, NO dmesg (cabecera: falla cerrado). Formatos
`%u/%d` coherentes con los tipos (`u8/u16/bool/int`,
`drm_dsc.h:81-159`); string `pr_info` en una línea (evita el patrón de
fallo previo). Gate doc ya correcto: `≥1` (`L59-PPS.md:33-34`, un solo
`pr_info` para 2 envíos).

## 2. Semántica API — correcta
`mipi_dsi_picture_parameter_set_multi` (`drm_mipi_dsi.c:1553-1570`)
solo usa `ctx->dsi` (`:1556`) y cortocircuita con `accum_err` previo ⇒
los 2 llamados son NECESARIOS y correctos. `accum_err` es el campo real
(`drm_mipi_dsi.h:203-211`). `o82_send_panel_cmds` usa su propio
`dsi_ctx` local ⇒ el `accum_err` exterior arranca en 0: sin
interferencia con los 104 init-cmds (vía `dual_dcs_write_buffer_multi`,
broadcast). `err:` existe (`:483`) y libera bien.

## 3. ⛔ BLOQUEANTE — `goto err` sin `ret` (`:434-436`)
En fallo de PPS, `ret` aún vale 0 (init OK, `:384-387`). `err:` apaga
rieles + assert reset y hace `return ret` = **0 = ÉXITO FALSO con el
panel apagado**. El check final (`:471-473`) sí hace
`ret = dsi_ctx.accum_err`. **Fix (1 línea, obliga a rebuild):**
`if (dsi_ctx.accum_err) { …; ret = dsi_ctx.accum_err; goto err; }`.
Menor: `UKE-L37: PPS enviada` se imprime ANTES del check (log engañoso
en fallo); mover tras él o tolerar (el gate `≥1` sigue válido).

## 4. pic_width/height = 0 — riesgo real, no bloqueante
`o82_dsc_config` (`:644-654`) no define `pic_width/height`; prepare
precede a modeset y `ctx->dsc` se copia en probe (`:793`), así que la
PPS lleva bytes 6-9 = 0 (`drm_dsc_helper.c:146`). El fill de
`dsi_host.c:1034-1035` toca `msm_host->dsc`, posterior e inútil aquí.
Precedente nt36532e: **NO verificable** (ausente en el árbol;
git.kernel.org bloqueado por Anubis) ⇒ coherencia asumida, no probada.
Si `UKE-L37` aparece y sigue negro: añadir `print_hex_dump(…, &pps,
128)` (el struct ES el payload, `BUILD_BUG_ON` 128) y comparar con los
bytes vendor — NO apilar nada más.

## 5. No portado de L39 — nada requerido para la PPS
L38 (reset 15 ms vs 100 ms r7), L27-vci, INHERIT, pokes K47 son de otro
eje; no hay `compression_mode` ni en L39 ni en vivo (el host comprime,
`dsc=85 85`; el blob vendor lleva su enable). Sin `o82_enable` en el
driver ⇒ no hay 2ª oportunidad post-modeset en-driver.

## VEREDICTO: NO-PASA flashear L59 tal cual
**PASA tras aplicar el fix §3 + rebuild + gates** (fuente `L37-pps`×3 /
`UKE-L37`×2; binario en strings; repack clon L58; rollback L58
`763d7869…`). Criterio: PASA = CONTENIDO; FALLA = negra con luz ⇒
verificar bytes PPS (§4), no apilar.
