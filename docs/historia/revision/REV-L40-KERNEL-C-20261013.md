# Revisión escéptica del C del kernel — paquete L40 (G5+G6+PPS-dual+backlight+L40+reset)

Fecha: 13-oct-2026. Revisor: subagente C-kernel. Árbol auditado:
`build/kernel-pokes/k52L39-tree` (binario L40 = `build/kernel-pokes/k52L39-build`,
`boot-uke-k52L40.img`). Copias versionadas idénticas (diff-rc=0):
`build/gates/patches/k52L39-fuentes/{dsi_phy_7nm,panel-xiaomi-o82-dualdsi}.c`.
Baseline de comparación: `build/kernel-pokes/k52-L16-tree` (mainline pristino)
y `build/kernel-pokes/k52L33-tree`. No se flasheó ni se tocó `k52L39-build`.

## 1. Veredicto

**L40 NO es un test válido de "¿funciona la PHY del vendor?".** Es un paquete de
mínimo **4 deltas funcionales no probados por separado** (G5, G6, PPS-dual,
backlight-externo+warn) más 1 heredado nunca aislado (reset 15 ms), condicionado
además a un fix de otro agente (overlay I2C s284). Si L40 da imagen (o si da
log limpio), **no se sabrá cuál de los 4 lo causó**; si falla, **no se sabrá
cuál lo rompió**. Viola la regla del proyecto "un cambio por ciclo"
(`docs/historia/AGENTS.md`) y su propio plan L39-PLAN §2-bis, que exigía el cálculo offline
mainline-vs-vendor antes del commit (sigue pendiente).

Agravante de validez: **L40 no puede producir luz visible aunque el DSI funcione**,
porque sin I2C no hay KTZ y el warn deja `panel.backlight == NULL` para siempre
en ese arranque (§3.3). La pregunta que L40 sí puede responder, con criterio de
pasa/falla basado en logs (NO visual), es: **"¿completa el panel prepare+modeset
sin errores DSI con la PHY del vendor?"** — y ni siquiera esa es atribuible a la
PHY por el empaquetado. Juicio visual ("¿se ve algo?") en L40 = falso negativo
por construcción (salvo resto de backlight del ABL, §3.4, que a su vez
contaminaría un "éxito" visual).

Dicho esto: **no encontré ningún bug que rompa el arranque ni NULL-deref**; el
paquete es seguro de flashear (con el I2C arreglado) como vehículo de medición,
no como experimento.

## 2. Hallazgos por gravedad

### H1 (media): L40-warn traga el `-EPROBE_DEFER` y el panel ya no reintenta el backlight nunca
- `panel-xiaomi-o82-dualdsi.c:786-792`: `drm_panel_of_backlight()` → si el KTZ
  aún no probeó, `of_find_backlight()` devuelve `ERR_PTR(-EPROBE_DEFER)`
  (`drivers/video/backlight/backlight.c:615` en este árbol). El código anterior
  lo propagaba (orden correcto: panel espera al KTZ). El warn lo convierte en
  ruido y sigue con `panel.backlight == NULL` permanente: **cuando el I2C se
  arregle (s284), si el KTZ probea DESPUÉS que el panel en el mismo arranque,
  la pantalla quedará a oscuras hasta reboot**, sin ningún error visible.
- El propio commit lo anticipa ("cuando I2C funcione, esto se puede volver a
  endurecer") — lo dejo como deuda explícita con fecha: **revertir 9e7fa34 en
  cuanto s284 dé `/sys/class/i2c-adapter` no vacío**.
- Verificado que NO hay NULL-deref: `backlight_enable/disable(NULL)` devuelven 0
  (`include/linux/backlight.h:315-336`), y `drm_panel_enable/disable` los llaman
  sin chequear (`drivers/gpu/drm/drm_panel.c:262,324`). La pregunta del encargo
  ("posible NULL-deref") queda **refutada por lectura del fuente**.

### H2 (media): el comentario PPS afirma lo contrario de lo que garantiza el código
- `panel-xiaomi-o82-dualdsi.c:391-397`: "pic_width/pic_height del PPS salen del
  template (0 a prepare-time…)". **Falso en la práctica**: con
  `prepare_prev_first = true` (`panel-xiaomi-o82-dualdsi.c:761`) el core llama
  primero al `pre_enable` del host (`dsi_mgr_bridge_pre_enable` →
  `msm_dsi_host_enable` → `dsi_timing_setup`, `dsi_host.c:2597`), que rellena
  `dsc->pic_width = mode->hdisplay` (3200) y `pic_height` (2136) sobre el MISMO
  struct compartido (`msm_host->dsc = dsi->dsc`, `dsi_host.c:1792`) ANTES del
  `prepare` del panel (`drm_bridge.c:179-188` documenta el orden). El PPS llevará
  3200×2136, no ceros. El error es solo de comentario y en dirección segura,
  pero el "pendiente verificar byte a byte" ya es verificable por lectura:
  **el ancho que viaja es el full-mode 3200 idéntico a ambos links, como el
  broadcast del vendor**. Arreglo: corregir el comentario, no el código.
- Chequeos de consistencia que sí cierran: `3200 % 800 == 0`,
  `2136 % 24 == 0` (`msm_dsi_host_check_dsc`, `dsi_host.c:2668`); ambos links
  comparten un solo `drm_dsc_config` (`o82_probe` asigna `&ctx->dsc` a los dos,
  `:796-800`) y ambos hosts escriben el mismo valor — idempotente.

### H3 (baja): cita de referencia inverificable en el árbol
- El comentario PPS (`:377-380`) cita `panel-novatek-nt36532e.c:201-202` "que SI
  funciona en sm8550-mainline (sheng)". **Ese fichero no existe en este árbol**
  (solo hay nt35510/nt35532/nt35560/nt35950/nt36523/nt36672a/nt36672e/…).
  El patrón sí es verificable localmente con `panel-visionox-r66451.c:183-184`
  y `panel-raydium-rm692e5.c` (mismo packer + misma vía DCS) — citar esos en su
  lugar. Diferencia menor pero real: r66451 envía la PPS en `.enable()`, o82 en
  `.prepare()`; con H2 resuelto el orden es equivalente aquí.

### H4 (baja, trazabilidad): `k52L33-tree` ("intacto", "recuperación") ya contiene L37+L38
- `af1ae94` dice "k52L33-tree queda INTACTO", pero hoy contiene el bloque PPS
  single-link (`k52L33-tree/…/panel-xiaomi-o82-dualdsi.c:388`) y el reset a
  15 ms (`:294`). Los árboles `build/kernel-pokes/*` están gitignored y mutan
  sin historia: **ningún tree-dir corresponde de forma demostrable a su imagen
  flasheada**. El delta fuente L33→L40 verificado por `diff -rq` son exactamente
  los 2 ficheros tabulados (más artefactos `.o/.mod` de `=m`/`=y`, esperables),
  así que el contenido de L40 sí está acotado; pero la etiqueta "recuperación"
  de k52L33-tree debería revalidarse contra el sha de `boot-uke-k52L33.img`
  antes de usarla como rollback.

### H5 (informativo): `CONFIG_QRTR_SMD=y` está en L40 pero NO es un delta ni un riesgo nuevo
- `k52L39-build/.config:1604` y `l39-config/.config:1604` tienen
  `CONFIG_QRTR_SMD=y`; pero también `k52L33-build` y `l33-config` (baseline que
  arranca). Los 3 símbolos revertidos a `=m` por `5c82899`
  (BATTMGR, PMIC_GLINK, UCSI_GLINK) sí están en `=m` en el config de L40.
  La prohibición textual del ledger cubre `QRTR_SMD=y`, pero la evidencia local
  (L33 arranca con él) muestra que el wedge medido fue BATTMGR=y+glinks=y, no
  QRTR. **No propongo ningún cambio** (regla del encargo); solo dejo constancia
  de que L40 no introduce riesgo nuevo por aquí.
- `BACKLIGHT_KTZ8866=y` (vs `=m` en L33-build) es inofensivo sin bus I2C
  (el driver probea, no encuentra cliente, no hace nada) y con I2C el binding
  tardío funciona igual built-in que en módulo. No es confound funcional.

## 3. Verificación línea a línea (lo que se pidió explícitamente)

### 3.1 G6 — mapeo TIMING_CTRL_0..13 ↔ 14 bytes: CORRECTO, con evidencia primaria doble
- Orden mainline pristino (`k52-L16-tree/.../dsi_phy_7nm.c:1163-1178`): 0=const
  0x00, 1=clk_zero, 2=clk_prepare, 3=clk_trail, 4=hs_exit, 5=hs_zero,
  6=hs_prepare, 7=hs_trail, 8=hs_rqst, 9=const 0x02, 10=const 0x04, 11=const
  0x00, 12=clk_pre, 13=clk_post. G6 escribe
  `{00,27,0a,0a,1b,19,0a,0b,0a,02,04,00,20,0f}` en ese mismo orden
  (`k52L39-fuentes/dsi_phy_7nm.c:1196-1209`).
- El vendor confirma el orden de forma independiente:
  `dsi_phy_hw_v4_0_commit_phy_timing.c` escribe los bytes `+0x34..+0x41` en
  `PHY+0xb4..+0xe8` paso 4, y `dsi_phy_7nm.xml:48-61` define
  `TIMING_CTRL_0..13 = 0xb4..0xe8` paso 4. (Detalle: el 6.º write del decompilado
  dice `200` decimal = `0xc8` = CTRL_5. Cuadra.)
- `dsi_phy_hw_v4_0_cache_phy_timings.c` confirma "verbatim del DT, exige
  param_3==0xe". Valor `00 27…` confirmado en el DT de stock
  (`L39-PLAN-20261013.md:126`, 6 nodos o82 idénticos).
- La "autoverificación por 4 constantes" del comentario G6 es débil (las fija
  cualquier rama, también CPHY) — pero el mapeo queda probado por el commit
  vendor, no por ella. La narrativa `hs_rqst=47,05ns<50ns` sigue siendo hipótesis
  con input pendiente (tasa pedida vs efectiva, L39-PLAN §2-bis); **no afecta a
  la corrección de las constantes**.
- `diff k52-L16-tree vs parche`: la rama CPHY (`:1156-1167`) es **byte-idéntica**;
  solo cambian la rama DPHY y `lane_ctrl0`. CPHY no se rompió (y en uke ni se
  ejecuta: panel DPHY sin `qcom,dsi-cphy-*`).

### 3.2 G5 — `lane_ctrl0 0x1f→0x15`: CORRECTO, fórmula verificada en el decompilado
- Vendor escribe en AMBAS ramas `LANE_CTRL0 (0xa0) = (strength[0] & 0xF) | 0x10`
  (`dsi_phy_hw_v4_0_enable.c`: rama CPHY `(*(param_2+0x154) & 0xf | 0x10 → 0xa0`;
  rama DPHY `uVar5 = *(param_2+0x154) & 0xf | 0x10; … writel(uVar5, …0xa0)`).
  Con `qcom,platform-strength-ctrl = [55 03 …]` → `(0x55&0xF)|0x10 = 0x15`.
  Aritmética cerrada.

### 3.3 PPS a dos links: CORRECTO, sin bug silencioso
- `mipi_dsi_picture_parameter_set_multi()` lee `ctx->dsi` en cada llamada
  (`drm_mipi_dsi.c:1553-1570`: `dsi = ctx->dsi` + early-return si `accum_err`).
  El panel reasigna `dsi_ctx.dsi = dsi[0] … = dsi[1]` antes de cada envío
  (`panel:399-402`). **La pregunta del encargo queda respondida: sí re-asigna;
  no hay reutilización silenciosa.** El fail-fast del segundo envío si falla el
  primero es la semántica estándar `_multi`, no un bug.
- Vía correcta (PPS = long-write `MIPI_DSI_PICTURE_PARAMETER_SET` por device,
  cada `dsi[i]` registrado en su host → cada envío va a su controlador).
  Sin `compression_mode_ext`, igual que r66451 (video-mode; el host programa
  sus registros de compresión en `dsi_update_dsc_timing`).

### 3.4 Backlight fuera del panel: transición correcta, degradación L40 acotada
- Quitar `o82_bl_update_status` (DCS 0x51) es lo que pide el vendor: ID 0x14 con
  `bl_ctrl_external` nunca escribe 0x51 (`dsi_panel_set_backlight` case 3 → KTZ
  por I2C). El core enciende en `drm_panel_enable()` tras modeset
  (`drm_panel.c:262`), equivalente funcional de `delay_until_first_frame`.
  Apagado en orden correcto: `drm_panel_disable()` (core apaga KTZ, `:324`)
  corre antes que `unprepare` por `pre_enable_prev_first`/`post_disable`
  (`drm_bridge.c:846+`). Sin `.enable/.disable` en el panel: legal, como r66451.
- Con `backlight==NULL`, enable/disable son no-ops seguros (H1). No hay
  regresión de suspend: la ruta `disable→unprepare` (off `0x28/0x10/0x4f` por
  link + corte de rieles) no cambió en comportamiento.
- Matiz visual: si el ABL dejó el KTZ encendido, al no tocarlo el kernel el
  backlight puede **persistir del bootloader** y L40 podría mostrar imagen con
  ajustes rancios — un "éxito" visual así no sería atribuible al kernel.
  Incertidumbre explícita: no medí si el ABL enciende el KTZ.

### 3.5 Reset 15 ms (hunk L38): vendor-correcto, pero confound vigente
- Secuencia `(0,10),(1,3),(0,3),(1,15)` del DT Android ↔ código
  (`:265-294`, GPIO active-low: value 1 = nivel 0 = assert). El 100 ms era
  inventado (r7) y el log mentía ("15ms" durmiendo 100). Correcto revertirlo;
  pero **nunca flasheado solo** → si L40 cambia el punto de muerte respecto a
  L39b, reset y PHY son indistinguibles.

### 3.6 Regresiones: ninguna encontrada
- `dsi_phy_7nm.c` solo afecta al enable del PHY DSI (GPU/Adreno, SMMU, QMP/DP,
  fbdev no lo tocan); rama CPHY intacta; path `disable` intacto; el cálculo de
  timings sigue corriendo (valida, solo se descarta su resultado en DPHY).
  G5/G6 son globales al fichero pero este kernel solo maneja uke (un panel DSI).
- El panel antes no probeaba (sin I2C) → no hay estado funcional que romper;
  el KTZ built-in sin bus es inerte. Riesgo residual: ninguno mecánico; todo el
  riesgo es de atribución.

## 4. Atribución: qué habría que hacer distinto

1. **L40 no debió empaquetar.** El diseño atribuible, con la I2C ya en camino,
   era: (a) s284 solo + panel con backlight DURO → mide si el enlace existe con
   PHY mainline (baseline real, que en 39 rondas nunca existió porque el panel
   ni probeaba); (b) +G5 solo; (c) +G6 solo; (d) +PPS-dual solo. Un cambio por
   ciclo, como exige `docs/historia/AGENTS.md`.
2. **Fijar el criterio de pasa/falla ANTES del flash, en logs, no visual:**
   p. ej. `K47-pan-prep COMPLETO` + `L37-pps-done rc=0` + modeset a 3200x2136
   sin `status=4`/FIFO errors. Con L40-warn, "pantalla negra" es el resultado
   ESPERADO incluso con éxito total del DSI.
3. **Hacer el paso pendiente de L39-PLAN §2-bis** (cálculo offline
   `msm_dsi_dphy_timing_calc_v4` a tasa pedida vs medida, registrando
   `byte_clk_rate` pedida/efectiva): separa cuánto de G6 es "fix real" y cuánto
   es "mismo valor por otro camino", y decide si G5 y G6 son independientes.
4. **Revertir 9e7fa34 en cuanto s284 funcione** (H1) y revalidar el orden
   panel↔KTZ; si se quiere medir DSI antes del I2C, preferir un `modprobe`-tardío
   o cmdline-flag antes que tragar el DEFER en el fuente.
5. **Disciplina de árboles gitignored**: versionar el tree entero o al menos
   `sha256sum` de los `.c` tocados en cada pre-registro (H4 muestra que el
   "intacto" no lo era).

## 5. Una línea por lo que está bien

- G6: mapeo 1:1 probado contra commit vendor + XML de registros.
- G5: fórmula `(strength&0xF)|0x10` verificada en ambas ramas del decompilado.
- PPS-dual: reasignación por link correcta, sin bug silencioso.
- Backlight externo: respeta el vendor (nada de DCS 0x51) y el orden core.
- L40-warn: sin NULL-deref, compra la medición sin romper el arranque.
- Reset 15 ms: vuelve al vendor y corrige un log que mentía.
- CPHY intacta; sin regresiones en GPU/DP/fbdev/suspend; config de carga en `=m`.
