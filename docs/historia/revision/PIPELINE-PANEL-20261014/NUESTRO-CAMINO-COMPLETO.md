# NUESTRO-CAMINO-COMPLETO — pipeline display propio, del probe al apagado (14-oct-2026)

> Solo lectura. SSH caído hoy (`timeout` 14-oct) ⇒ gpio/regulator sysfs en vivo PENDIENTE.
> Base: L52 en tablet (display OK, sin luz), L53/L54 medidos, L55 pendiente de flash.
> `docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-CAMINO-COMPLETO.md` no existe aún ⇒ comparaciones marcadas PENDIENTES.
> Leyenda: **[M]** = medido (fichero:línea/log), **[H]** = hipótesis.

## 1. Panel o82 — qué hace y cuándo (`k52-L16-tree/.../panel/panel-xiaomi-o82-dualdsi.c`)

- **probe** `:664-813` corre a **~0.61 s** **[M]** (`out/CAPTURA-L52-dmesgw.log:1611-12` ESD arm;
  reintentos 0.62 s `:1650-52` y 3.73 s `:1741-44`). Hace: `bulk_get` 3 supplies (sin
  enable) `:681-682`, `reset_gpio=OUT_HIGH` `:732-737`, ESD-irqs 86/87, `drm_panel_of_backlight`
  → KTZ `:786-792` (L45-defer), attach dual-DSI `:796-810`. **Efecto físico: con DT
  `reset-gpios=<&tlmm 2 1>` active-low (`fase4-display.dts:366`) el `OUT_HIGH` = RESET ASERTADO
  desde el probe** **[M código]**.
- **power_on** `:301-335` (vci/L19 opcional `:317-329` + vddil8b→vsp→vsn, 300 mA + 2 ms)
  **solo corre en prepare** **[M]** (commit 54.554→54.566, `dmesg:3190-3203`; `L27-vci-ok` + 104 DCS
  en `CAPTURA-L53-commit-netconsole.log:198-207`). En boot temprano NO corre ⇒ raíles quedan ABL.
- **reset** `o82_reset` `:263-295` (0/10 ms, 1/3 ms, 0/3 ms, 1/15 ms) solo en prepare **[M]**
  (`dmesg:3204-3222`, release2 54.686).
- **init DCS** `o82_send_panel_cmds` `:209-257`: 104 cmds + PPS-L37 + freq + `0x11`/120 ms +
  `0x29` → `prepare: COMPLETO` 55.0238 **[M]** (`dmesg:3228,7185,7256,7299,7329-30`).
- **enable**: sin `backlight_enable` local (L44 lo quitó; `L55-DCS51.md:7-15`); el core enciende el
  KTZ en `drm_panel_enable` tras el modeset (≈ vendor `delay_until_first_frame`) **[M]** (KTZ
  update 55.0241 tras `K47-vid-en`, `dmesg:7331-36` + `atom-tail` + `alive`).
- **unprepare** `:464-500` (`0x28/0x10/0x4f`) solo a remove/shutdown; `get_modes` `:502-535`
  (54.479 y 85.014 — el 2º es sonda userspace, `dmesg:7412`).

## 2. DSI host/PHY (`msm/dsi/dsi_manager.c`, `dsi_host.c`)

- Bridge: `dsi_mgr_bridge_power_on` `:218-253` = phy_enable → `L49-phy-ok` → `host_power_on` ×2
  → `L49-pwron-ok`. Commit 54.505→54.554 **[M]** (`dmesg:3168-3188`).
- Host: `msm_dsi_host_power_on` (`dsi_host.c:2519-2567`) = `K47-host-pwr` → vregs
  (`L49-host-vreg-ok`) → link_clk (`L49-host-clk-ok`) → timing+sw_reset+ctrl_enable
  (`L49-host-ctrl-ok`); DCS por cmd-DMA K50 (`dma-base=0x2000`, `trig-done`) **[M]**.
- Boot: hosts bindean ~47.11 (`UKE-L45`, `dmesg:2874`); **el BCR del MDSS DISPARA ~0.5 s**
  **[M]** (`msm_mdss.c:323` con inherit OFF: `cmdline-orig.txt` sin `msm.uke_panel_inherit`,
  default false `msm_drv.c:69-77`; danza `K48-mdss` 0.52 s `dmesg:1471-86`). El scanout del ABL
  muere aquí.

## 3. Backlights: quién enciende qué y cuándo

- **Externo KTZ8866 (vigente L52–L54)**: `ktz8866.c:405-458` (`0x08` 0x7F↔0x3F + `0x04/0x05`,
  init 0x133=307). Updates **[M]**: 4.174 (probe) `dmesg:2019`, 7.627 `dmesg:2315`,
  55.024 (commit) `dmesg:7336`, 170.61 (manual max) `dmesg:7527`. Commit-time:
  `00 21 53 cd 00 a6 00 00 7f 9f 11 00 32 24 28 00 80` (`CAPTURA-L53-commit-netconsole.log:4343-45`).
- **Interno DCS 0x51**: quitado por L44; vuelve en L55 (diff `docs/historia/revision/PIPELINE-PANEL-20261014/l55-panel-internal-bl.diff`,
  pendiente flash). Vendor: `0x51=0xFFF+0x53=0x24` solo en init (`:171-173`), nunca en runtime
  (case 3 → KTZ) **[M código]** — el 0x51-faltante como causa está tumbado; L55 es camino no
  intentado, no fix deducido.

## 4. Correlación: el BLANCO y el APAGADO

- **t≈0.36 s**: `pm8550ve@8` descartado (`X9SPMI-skip2`, `dmesg:1177`) ⇒ sin gpiochip: el AVDD
  queda ABL-ON todo el boot; el kernel no puede apagarlo **[M]** (corrige L54: `L54-POWER-PANEL.md:91-99`).
- **BLANCO ≈0.5→0.6 s [H sostenida]**: BCR mata scanout (~0.5 s) + probe aserta reset del TDDI
  (0.61 s) con el KTZ aún en estado ABL-ON ⇒ pantalla en reset + backlight encendido = blanco.
  Control: K45 (`msm=n`, 3-oct, `NOTAS-OMARCHY.md:2326`): negro encendido, sin blanco ni off —
  el derribo lo causa el bind msm **[M testimonio]**.
- **Ventana 0.62→3.68 s: NINGÚN evento de power/backlight en dmesg [M]** (barrido filtrado por
  regex sobre `CAPTURA-L52-dmesgw.log`; solo ruido UFS/SPI/audit). El apagado visible no tiene
  causa driver en el log.
- t=4.17 s: re-init + update-ON del KTZ (`dmesg:2019-22`) — **único evento que toca los LEDs en
  la ventana temprana** **[M]**; termina en ON.
- t≈7.63 s: update con el mismo valor ON **[M]** (`dmesg:2315`); sin líneas `systemd-backlight`
  en dmesg ⇒ restore-userspace compatible pero no identificado; no apaga.
- t=33.77 s: `vsp/vsn disabling` **[M]** (`dmesg:2706-7`); no alimentan LEDs; L54 lo tumba
  (cleanup bloqueado + enabled todo el boot + sin luz, `NOTAS-OMARCHY.md:4719-26`).
- t=55.02 s: commit + KTZ-ON + vídeo vivo sin luz **[M]** ⇒ el commit no enciende.

## 5. Hipótesis rankeadas

1. **Blanco = BCR (0.5 s) + reset-asertado-en-probe (0.61 s), KTZ aún ON.** 4 evidencias §4.
   **[M mecanismo; H el color como física del TDDI-en-reset]**.
2. **Apagado = re-init KTZ 4.17 s deja el boost no-arrancado, invisible a regmap.**
   **[H parcial]**: a favor, único evento + regs perfectos-pero-oscuros después; en contra,
   termina en ON y `0x10=0x80` sale igual en commit — falta semántica del flag (datasheet).
3. **Apagado autónomo 0.6–4.17 s sin traza driver** (posible por la ausencia medida; sin mecanismo).
   **[H débil]**.
- **Tumbadas**: KTZ-regs idénticos (L53, `NOTAS-OMARCHY.md:4710` — veredicto por SSH **sin log
  commiteado: hueco de trazabilidad**); power-window (L54 negativo limpio); `systemd-backlight`
  como apagador; `vsp/vsn` 33 s; AVDD-off; ESD (síntoma, #610); DCS-0x51-faltante.
- **Pendiente**: sysfs vivo (`gpio`/`regulator_summary`, SSH caído hoy); bytes `probe-entry`
  K53; datasheet KTZ reg `0x10`; flash L55; comparaciones Android (paralelo).
