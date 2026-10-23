# L54 — Power real del panel o82 y plan backlight (14-oct-2026)

> Base MEDIDA: KTZ idéntico ABL vs nuestro (incl. `0x09=0x9F`, `0x08=0x7F`,
> `0x10=0x80`), display OK (commit+vídeo+DCS 104), sin luz. Tablet
> inaccesible hoy (SSH/telnet rehusados) ⇒ gpio en vivo queda PENDIENTE (cmds §5).

## 1. `uke_panel_vsp/vsn` — qué son (MEDIDO en repo + ledger)

- Definición vigente: `build/gates/patches/k52L39-fuentes/fase4-display.dts:124-148`
  (`fragment@4`): `regulator-fixed`, `display_panel_vsp/vsn`, TLMM **74/75**,
  **5800000 µV**, `regulator-boot-on`, `enable-active-high`, ramp 233.
  Era s238 se llamaban `uke_panel_vsp/vsn`
  (`build/evidencia/2026-09-28/dt-reconstruido/overlay-s238.dts:14719-14741`,
  ramp 0xe9) — mismo HW, distinto nombre. El nombre `uke_panel_*` del summary
  es la era vieja; el vivo es `display_panel_*` (NOTAS:905-907 muestra ambos).
- NO son PMIC/LAB/IBB: son GPIO + regulador fijo. **5800 mV** = voltaje fijo del
  DT, no medición. **0 mA** = no-evidencia (los `regulator-fixed` GPIO no sensan
  corriente; siempre reportan 0).
- El `disabling` ~33 s es el late-cleanup del core:
  `build/kernel-pokes/k52L39-tree/drivers/regulator/core.c:6840-6857`
  (apaga todo `boot-on` sin consumidor). MEDIDO en ledger #P200 (~l.8977):
  `uke_panel_vsp: disabling` + vsn a 33,7 s con `:d` (panel preparado, sin
  modeset, framework suelta los raíles). Con display-ON el `prepare` los
  re-enciende (~55 s): ledger #627 (~l.13293) mide **vsp/vsn ON a 5800 mV tras
  el commit**. Orden de encendido vendor en
  `k52L39-tree/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c:297-322`
  (vddil8b→vsp→vsn, 300 mA + 2 ms); supplies en `:85-88`; `bulk_get` en `:681-682`.

## 2. El power REAL del vendor (MEDIDO en stock DTBO) — corrección al encargo

- El o82 **NO usa `dsi_panel_pwr_supply_sim`** (ese es de otros paneles; la pista
  era errónea). Usa `dsi_panel_pwr_supply_O82`:
  `~/gpu-work/ramaa/s7/dtbo-stock-decomp.dts:13665-13710` (frag@97): 3 entries
  **vddil8b 1,9 V** (`0x1cfde0`, =L8B vía frag@100 `:13750`) + **vsp/vsn ±5,8 V**
  (`0x588040`) — que mapean a frag@98 (`:13711-13748`, TLMM 74/75, boot-on).
- **No hay LAB/IBB en todo el stock** (grep vacío): los ±5,8 V son los GPIO-fixed,
  no el PMIC. Nuestro DT los declara igual ⇒ aquí NO hay divergencia.
- El 4º raíl, el que NO tenemos: **`display_panel_avdd`**, `:1543-1556`:
  `qti-regulator-fixed`, **5,5 V** (`0x53ec60`), **pm8550ve GPIO 8**, `boot-on`,
  con `proxy-supply` propio. El vendor lo enciende a nivel placa (el nodo panel
  no lo consume). Fase4 lo dejó como TODO (`fase4-display.dts:117-122`).
  ⇒ El ABL deja AVDD **encendido**; nuestro kernel lo **apaga ~33 s** (sin
  consumidor declarado) y **nadie lo re-enciende** (nuestro driver solo maneja
  3 supplies). Candidato nº1 de divergencia ABL-vs-nosotros.
- KTZ stock (frag@105/106, `:13794-13821`): `compatible`+`reg` y NADA más (sin
  supplies, sin pinctrl, sin gpios). Nuestro DT coincide. Driver:
  `k52L39-tree/drivers/video/backlight/ktz8866.c:516-525` — `vddpos/vddneg` y
  gpio `enable` son **optional** (ausentes ⇒ NULL, se salta). Sin divergencia.

## 3. GPIOs (MEDIDO en DT; vivo PENDIENTE)

- Stock o82: reset TLMM 2 (`:13194+`, `platform-reset-gpio`), TE 77/78, ESD
  168/169 (`0xa8/0xa9`), vsp/vsn 74/75, AVDD pm8550ve-8. KTZ: **ningún pin**.
- Nuestro DT declara reset gpio2 + vsp/vsn 74/75; **falta AVDD (pm8550ve-8)**.
  HWEN del KTZ: responde a I2C ⇒ alto (ABL lo dejó + pull-up); no es el fallo.

## 4. `regulator_ignore_unused` como L54-a (repack-only, 0 build)

- MEDIDO: cmdline viva lleva `clk_ignore_unused pd_ignore_unused` pero NO
  `regulator_ignore_unused` (`build/bootimg/cmdline-orig.txt`; L53 = 624 B sin
  él). El gate existe en `core.c:6832-6838`.
- Mecanismo: preserva **todos** los raíles del ABL — incluido **AVDD**, que es
  el único que hoy se pierde para siempre en la ventana 33 s→prepare. vsp/vsn
  ya vuelven solos (#627), así que el test **discrimina AVDD**, no vsp/vsn.
- Riesgos: bajos (flag de debug previsto para esto; mantiene también rieles
  ajenos encendidos un boot; no toca SMMU/DT; rollback L52 `0cd89f96…`).

## 5. Recomendación L54 rankeada

1. **(a) `regulator_ignore_unused` repack-only** — coste 0-build, riesgo bajo.
   Si hay luz ⇒ era AVDD (u otro raíl ABL) y se fija en (b). Si no ⇒ se
   descarta toda la hipótesis "ventana de power" de un golpe. Hacer PRIMERO.
2. **(b) Declarar AVDD** (1-build: fixed 5,5 V en pm8550ve-8 + consumidor en el
   driver o82 o `regulator-boot-on`+always-on temporal) — solo si (a) da luz o
   si (a) falla pero AVDD sigue sin medirse encendido.
3. **(c) GPIO en vivo** (0-flash, cuando haya SSH): `cat /sys/kernel/debug/gpio`
   + `regulator_summary` + `cat .../display_panel_avdd/state` (esperado:
   ausente/off). Confirma (a)/(b). Seguro (sysfs/debugfs, sin MMIO).
4. **(d, NO hacer)**: tocar KTZ (regs perfectos), LAB/IBB (no existen en stock),
   HWEN (I2C vivo ⇒ alto), `sim-supply` (el o82 no lo usa).

## 6. Lo que NO se sostiene

- "El panel usa supply SIM" (o82 usa O82-frag@97); "VSP/VSN del PMIC/LAB/IBB"
  (son GPIO-fixed; sin LAB/IBB en stock); "0 mA = sin corriente" (los fixed no
  miden); "KTZ necesita enable-gpios/vddpos-vddneg" (optional por código y
  ausentes en stock); "vsp/vsn apagados en nuestro display" (ON medidos #627).

---

## Corrección (crítica L54, 14-oct noche)

- §2/§4: **FALSO** que el late-cleanup apague el `display_panel_avdd`: `core.c:6788-6817` solo
  apaga reguladores REGISTRADOS; `boot-on` no protege (solo `always_on`/`use_count`). Sin nodo DT
  no hay `rdev` ⇒ el AVDD queda como lo dejó el ABL (ON) y el kernel no lo cambia.
- L54 se re-justifica como **screen de la familia power-window** (raíles registrados: dip 33→55 s
  de vsp/vsn + leftovers), NO como confirmación del AVDD. Positivo ⇒ bisect por
  `regulator_summary`; negativo ⇒ familia muerta ⇒ branch B (DCS 0x51).
- `regulator_summary` nunca listará el AVDD: verificarlo por GPIO si toca, no por summary.
- Cmdline L54 = **632 B** (624−16+24), no 646 (error de aritmética del encargo, corregido).
