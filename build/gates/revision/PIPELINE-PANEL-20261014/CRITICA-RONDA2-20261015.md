# CRÍTICA RONDA 2 — 15-oct-2026 (solo lectura; post-L64)

Veredicto global: el cierre «rama PPS» es válido como *causa-única*, pero el ranking que hereda (nº1) está **medio caído**, el análisis del wedge de carga contiene **un error de código**, y la premisa mayor («el cold-path vendor funciona») **jamás se midió en vivo**.

## 1. ¿«Rama PPS cerrada» bien fundada? SÍ, con un matiz que importa

- Sostiene: pre (L62, `UKE-L62 dims=1600x2136` + `UKE-L37 err=0`) y post-0x29 (L64, `UKE-L63 err=0`) probadas; negro en ambas (ledger #640/#642). Cerrar *bytes+orden* es correcto.
- Lo que NO se sigue: «el DDIC está configurado». Formas en que la PPS no aplica pese a `err=0`:
  a) **PPS en mitad del stream**: el vendor la envía con vídeo-OFF y arranca `vid_engine_enable` al final (COMPARATIVA:13; `ENABLE-COMPARISON §1`, `.ko:0x1473a0`). Nuestro `enable` corre con vídeo ya en marcha (CRITICA-L63:15-17 admite que «vídeo ya andando» no está garantizado; el orden exacto vs commit no se midió). DDIC que solo latcha PPS en idle la ignoraría dos veces.
  b) **Contenido residual**: tablas RC sde-vs-DRM sin cotejar + rama VDC sin verificar (CRITICA-HIPOTESIS H3, en pie; PPS-COMPARA:43-45 lo admite).
  c) **`COMPRESSION_MODE` jamás enviado por nadie**: nuestro código nunca llama a `compression_mode_ext(_multi)` (solo PPS); ningún informe cita el comando que activa DSC en el DDIC. Si el vendor-cold lo manda fuera de `update_pps`, lo hemos omitido siempre.
  d) **Asimetría dual-link** (S4 §2.1: `msm_dsi_manager_cmd_xfer` DSI_0 retorna sin transmitir; DSI_1 dispara ambos): nuestros dos `_multi` por link ⇒ link0 recibe PPS dos veces, link1 una. Idempotente en teoría, sin verificar en cable.
  e) **La premisa mayor es RE, no medida**: el cold-path vendor (108 cmds + PPS) **nunca se observó en vivo** — el ABL siempre deja splash (ANDROID-PANTALLA-COMPLETA:120-126 §7.1-7.2). Nuestro BCR-reset nos pone en un camino que nadie vio funcionar jamás. El cierre PPS es válido; la confianza en «re-init desde cero basta» no.

## 2. `err=0`: qué mide y el test de escucha pendiente

- `err=0` = `dsi_ctx.accum_err` (`panel-xiaomi-o82-dualdsi.c:446-454`, `:627-630`) ← retorno de `mipi_dsi_device_transfer` (`drm_mipi_dsi.c:448-458`) = el host completó el DMA. **Un panel sordo, desconectado o sin vci da exactamente el mismo `err=0`** (S4 §2.3 ya lo dijo; sigue vigente). `status=4/5` es agregado software (`dsi_host.c:1626-1640/1598-1608`); el crudo jamás se imprimió.
- Evidencia de escucha del DDIC: solo el **flash blanco ~0,5 s al probear** (COMPARATIVA:8, marcado `[M mec/H color]`) — débil (puede ser BL sobre panel sin init). Luz + commit OK no prueban al DDIC.
- Test propuesto y **aún sin hacer** (oportunidad perdida en L63/L64): BTA readback `0x0A/0x04` en el `enable` (CRITICA-PLAN §1 lo pidió «en el mismo hunk»; no fue). Barato previo: toggle DPMS y contar flashes (T2, `CADENA-USERSPACE-DRM.md:47-48`).

## 3. Ranking nº1: cae la mitad HS, se sostiene la mitad vídeo

- **«Nuestro DCS va en HS» es FALSO.** `mode_flags` incluye `MIPI_DSI_MODE_LPM` (`panel-xiaomi-o82-dualdsi.c:738`) y `mipi_dsi_device_transfer` hace `msg->flags |= USE_LPM` para **todo** mensaje (`drm_mipi_dsi.c:448-458`), incluida la PPS (`picture_parameter_set`, `:720-732`, msg sin flags). L50 §2a («USE_LPM no aparece en panel ⇒ HS», docs/historia/revision/PIPELINE-PANEL-20261014/L50-DCS-VENDOR.md:29-33) ignora esta vía: refutado por código. Todo nuestro DCS va en **LP, como el vendor**.
- **«VID_MODE_EN antes del DCS» se sostiene**: `dsi_mgr_bridge_pre_enable` → `power_on` → `msm_dsi_host_enable` (`dsi_manager.c:282-310`, `:304-311`) corre antes del prepare del panel (orden outer-first), y `dsi_op_mode_config` arma `VID_MODE_EN` si `mode_flags & VIDEO` (`dsi_host.c:1158-1180`). Vendor: DCS con vídeo OFF.
- Pero el mecanismo «BLOCK_DMA retiene el CMD-DMA» (S4 H-S4-1, `dsi_host.c:874-876` version-gated 6G v1.2+) **murió con L64**: el DMA completa (`err=0` ×2 posiciones). Queda solo «DCS-en-stream ignorado», hipótesis viva pero sin el peso del nº1.
- Nº4 (FLUSH/HS_TIMER/DB_MODE, S4 §2.4 V5; regs existen solo en el xml, ningún `.c` los programa) y nº3 (`NON_CONTINUOUS` sigue en `:739`, vendor LP11-init) **intactos** — heredan el puesto nº1 por defecto, no por mérito nuevo.

## 4. Contradicción PPS: dirimida (las dos citas son verdad enpaths distintos)

- «Calculada, no va al panel / IC preconfigurado» (SECUENCIA:52; ANDROID-DSI-PROFUNDO:484-485) = **cont-splash observado en vivo**: cero DCS entre 3,8 s y 10,84 s (ANDROID-PANTALLA-COMPLETA:31-32). «Existe y envía DCS» (PPS-COMPARA:30-35, `update_pps` + `tx_cmd_set`) = **cold-path, solo RE**. Implicación: con splash el DDIC vive del ABL; nosotros matamos el splash con el BCR y seguimos un cold-path **sin prueba de existencia en cable**. Prioridad: dejar de asumir que «orden vendor = imagen»; falta LP11-init + vídeo-OFF + PHY del cold-path.

## 5. Batería/carga: el «check-then-act» es un error de lectura; el wedge sigue sin causa

- **CAE el análisis del guard**: check (`pmic_glink.c:312-317`) y asignación (`:369-371`) corren bajo el **mismo mutex** (`scoped_guard` / `mutex_lock(&__pmic_glink_lock)`). Los probes serializan; el 2º/3er nodo (incluido el nuestro `xiaomi-uke.dts:89-92`) recibe `-EBUSY` benigno. No hay ventana, no hay colisión de aux. CARGA-HERMANO §c y ledger #642 («ventana check-then-act») están mal.
- Denominador real L60/L63 = `glink+ucsi=y` (L59/L62/L64 `=m` arrancan; L60 añade battmgr, L63 no, ambos wedgean). Mecanismo **desconocido**: los probes no bloquean (L60-FALLO §1 en pie) y el precedente #404 es otra pareja en otro árbol. Citarlo como «triple nodo + guard» es hoy falso.
- Plan insmod (CARGA-HERMANO §d): **seguro de intentar** (runtime, consola viva, `rmmod` reversible; los dups darán `-EBUSY` serializado, no wedge) **pero no concluyente**: éxito en runtime no prueba `=y` en init (el #404 del hermano era camino de init, no de probe).
- `a=3` + 3479 mV (< gate 3700) + ~10 escrituras contra ≤2/día + watchdog sin arreglar (R-42): flashear ahora **viola las propias reglas** y solo es defendible con `getvar all` + decisión `qbootctl` + cargador de pared antes. Sin eso, suicida-adjacente.

## 6. Otras premisas sin verificar (ordenadas por peligro)

1. **Byte clock propio jamás medido en vivo**: «pedido 118918800 vs vendor 148648750» (S6:125; COMPARATIVA:10) con «byte real 187,5M» sin fuente clara. Negro-con-commit-OK + DCS-OK es EXACTAMENTE la firma de link a velocidad equivocada. Test 0-flash: `clk_summary` en L64 vivo. **Es el hueco mayor.**
2. «No hay reads = no hacen falta»: el vendor SÍ lee (`lockdown benigno`, `cell_id rc=-22`, ANDROID-PANTALLA:49-52). Como init vale; como diagnóstico, el BTA sigue siendo el único test de escucha y sigue sin hacerse.
3. «Autónomo carga a 5 V»: del hermano con módulos (1,19 A); en la nuestra, la batería **bajó** a 3479 mV con sistema vivo. Sin `current_now`/`status` medidos en L64, es hipótesis.
4. `pic 1600/link`: se sostiene (VESA por interfaz; `dsi_update_dsc_timing` no usa pic_width, `dsi_host.c:927`).
5. L63 mezcló 2 cambios/ciclo (PPS + carga): violación de regla que costó el test PPS (rescatado por L64; no repetir).

## Qué SE SOSTIENE / qué CAE / 3 acciones

- **SE SOSTIENE**: cierre PPS bytes+orden; VID-antes-DCS; FLUSH/HS_TIMER, NON_CONTINUOUS; H5/H6 slots; KTZ cerrado; guard como código (no como causa).
- **CAE**: «DCS en HS» (L50 §2a refutado por `drm_mipi_dsi.c:448-458` + `panel:738`); «ventana check-then-act del guard» (mutex); «wedge = triple nodo»; «vendor-cold funciona» (nunca observado); «R-32/R-33» (ya corregido a #404).
- **Acciones**: (1) **0 flashes, SSH a L64**: `clk_summary` (byte/bit por link) + `power_supply` + `/dev/input` + `getvar all` + decisión `qbootctl` — el clock decide si el nº1-bis es el link. (2) **Siguiente flash de un solo cambio: BTA readback** (`0x0A/0x04` en `enable`); si el DDIC no responde, parar DSC e ir a link/PHY/vci, no a s6. (3) **Carga sin flash**: `uke-charge-run.sh`/insmod en vivo + pared ≥45 W; moratoria de flashes hasta ≥3700 mV y ≤2/día.
