# PRE-REGISTRO F4/s280 — 12-oct · **el fix de UN solo clock** (no necesita build)

## Hipótesis

`clk_rcg2_shared_enable` escribe **incondicionalmente** `parked_cfg` sobre el CFG del RCG:

```c
// drivers/clk/qcom/clk-rcg2.c:1437
regmap_write(rcg->clkr.regmap, rcg->cmd_rcgr + CFG_REG, rcg->parked_cfg);
```

`disp_cc_mdss_mdp_clk_src` usa `clk_rcg2_shared_ops` (`dispcc-sm8550.c:639`) y mainline **nunca hace
`set_rate`** de él ⇒ `parked_cfg = 0` ⇒ **escribe 0 sobre el RCG que el ABL dejó a 514 MHz** ⇒ glitch del
core clock del DPU con el INTF escaneando ⇒ cuelgue en el MMIO siguiente.

Android **sí lo vota**: su DT trae 6 clocks y el 6º (`core_clk`) a **514 MHz**. Mainline vota 5.

## Artefacto

- **dtbo**: `build/bootimg/s280-boot-dtbo-gpu-display-mdpvote.img`
- **sha256**: `b1e6e59f53b172b2dfd4b001916c5ef72070fad7022975ab88d234b222a8ba1d`
- **607318 B** (partición `dtbo_a` = 25165824 B)
- **Derivado de**: `mkdtbo-s280.py`, por cirugía dentro del fragmento 1105 existente (0 phandles nuevos,
  0 `__fixups__` nuevos — el nodo mdss lo crea ese mismo fragmento, así que un fragmento aparte sería frágil)

**Diff exacto frente al s275-r2 vivo — SOLO 2 líneas:**
```
> assigned-clocks = <0x154 0x3e>;        /* &dispcc 62 = DISP_CC_MDSS_MDP_CLK_SRC */
> assigned-clock-rates = <0x1ea30480>;   /* 514000000 */
```

## Gates (los dos obligatorios del proyecto, en verde)

- `fdtoverlay -i <base.dtb> -o <merged> s280-pay.dtbo` → **OK (rc 0)**
- `bin/uke-dto-check.py` (proyecto hermano) → **idéntico al resultado del s275 vivo**: 4266 nodos /
  1791 phandles, `assigned-clocks 0x154 0x3e → /soc/clock-controller@af00000`, rate `0x1ea30480`.
  Único aviso: `FALTA touchscreen@0` — **pre-existente también en el s275 vivo** (el nodo real es
  `novatek@0`, presente, `touchscreen-size-x=2136`); es una expectativa obsoleta del checker.
- En el s275, `fdtget ... assigned-clocks` devuelve **`FDT_ERR_NOTFOUND`** ⇒ la property es nueva de verdad.

## Se combina con L28 (ya flasheado antes, este dtbo va encima)

- `boot_a` = L28 (`4d818dc5…`) — skip del BCR + las 5 correcciones Android + **SIN `video=DSI-1:d`**
- `dtbo_a` = **s280** (este)

## Tabla de lectura pre-registrada

| Resultado | Lectura |
|---|---|
| **Vive + imagen** | **El SRC era el asesino.** Primer display real del port |
| **Vive, log activo, panel probean, `prepare` corre** | El clobber estaba en el SRC; ahora toca lo que venga después (link DSI/TDDI) |
| **Vive pero negro, sin `K47-pan-prep`** | El bind pasó pero el prepare sigue sin dispararse |
| **Sigue muriendo a ~4,04 s** | El SRC **no** era el asesino (o no basta solo) ⇒ siguiente: gatear `dpu_runtime_resume` (vbif+clk_bulk), que era el L29 cancelado |

## Medición

**Sólo por SSH.** Antes de medir: `dmesg -n 7` (las migas del panel son `pr_info` en el driver y se
filtran con `loglevel=4`). El ACM pierde la ventana 0,5–4,0 s — comprobar que el gadget enumeró
(`lsusb | grep 1d6b:0104`) antes de declarar una captura vacía.

## Preflight

- [ ] Batería (≥3700 mV) y `slot-retry-count:a`
- [ ] sha del dtbo verificado antes de escribir
- [ ] `set_active a` **siempre**
- [ ] lector ACM armado antes del reboot

## Recuperación (probada 3 veces)

```
fastboot flash boot_a build/bootimg/boot-uke-k52L25.img   # sha 04cd49803b9a…
fastboot flash dtbo_a build/bootimg/s275-boot-dtbo-gpu-display.img  # sha 67a65bc161b6…
fastboot set_active a ; fastboot reboot
```