# ANDROID-POWER-DPU: por qué el KMD sobrevive al bind con el splash vivo

**Fecha:** 13-oct-2026. **Autor:** subagente kernel (sesión hija).
**Fuentes primarias (todas verificadas en esta sesión):**

| Fuente | Identidad |
|---|---|
| Driver real Android | `~/proyectos/ubuntu-uke/stock/modules/msm_drm.ko` — ELF aarch64, NO stripped, 21891 símbolos (`nm`) |
| Método | `llvm-objdump --arch-name=aarch64 -d -r --start-address=A --stop-address=B` (los `bl` del `.ko` son reubicaciones; el símbolo real está en la línea `R_AARCH64_CALL26`). Tamaños de `readelf -sW`. Strings de `.rodata` por offset de sección (base de fichero `0x17128`) |
| DT real | `build/evidencia/android-snap/dt-r15/soc/` (cada property = fichero, u32 big-endian) |
| Mainline | `build/kernel-pokes/k52L27-tree` (`dpu_kms.c`, `clk-rcg2.c`, `dispcc-sm8550.c`, `msm_mdss.c`, `palawan.dtsi`, `xiaomi-uke.dts`) |
| Contexto previo | `docs/historia/revision/CRITICA-CLOCKS-DPU-20261012.md` (parked_cfg=0, ranking), `SECUENCIA-ENCENDIDO-ANDROID-O82-20261012.md` (vía DSI/panel, ya cubierta — aquí NO se repite) |

> Alcance: solo el lado SDE/MDSS (power, VBIF, clocks, genpd, IRQ, handoff). El lado
> DSI/panel/prepare ya está cerrado en SECUENCIA-O82 (no se duplica; se referencia).

---

## 1. El framework de power del SDE — orden exacto

### 1.1 Quién llama a quién (cadena verificada)

```
genpd power_on/off (SOLO si el DT trae #power-domain-cells — en uke NO: §4)
  sde_kms_pd_enable @0x9e5f4  → __pm_runtime_resume(dev)      (nada más)
  sde_kms_pd_disable @0x9e570 → __pm_runtime_idle(dev)        (nada más)
        │
        ▼  runtime-PM del núcleo MSM (msm_drm, .ko:0x164100/0x164158)
msm_runtime_resume @0x164158 → sde_power_resource_enable(h,1) @0x16419c
msm_runtime_suspend @0x164100 → sde_power_resource_enable(h,0) @0x16413c
  │  AMBOS saltan la llamada si [handle+0x1b0] != 0  ← GUARD cont-splash nº0
  │  resume:  0x164184 ldr x8,[x19+0x1b0] / 0x164188 cbz→llamar / else return 0
  │  suspend: 0x16412c ldr x8,[x19+0x1b0] / 0x164130 cbnz→saltar (return 0)
  ▼
sde_power_resource_enable @0xfff08 (size 2236 = 0x8bc)
```

Con splash vivo, **el enable/disable completo de recursos se omite en este nivel**:
los clocks del ABL simplemente siguen corriendo y nadie los re-vota.

### 1.2 `sde_power_resource_enable(h, en)` — orden de operaciones

`w22 = en`; `tbz w22,#0 → 0x10010c` (rama disable). Estructura:

**Rama ENABLE (bit0=1, entra por `0xfff90`):**

| # | Offset | Operación | Símbolo |
|---|---|---|---|
| 1 | `0xfffb8/fffd4/ffff0` | Vota cuotas de buses de datos (3 paths, si sus contadores `+0xd8/+0x100/+0x128` > 0) | `_sde_power_data_bus_set_quota` @0xfe7e0 (estática local) |
| 2 | `0x100004` | Habilita reguladores | `msm_dss_enable_vreg` @0xc612c |
| 3 | `0x100018` | Escala bus de registros | `sde_power_scale_reg_bus` @0xffcf4 = **solo `icc_set_bw`** (0xffd74) + trace; cero clocks |
| 4 | `0x100060` | Voto estado RSC | `sde_rsc_client_state_update` |
| 5 | `0x100074` | **Habilita clocks: `clk_prepare + clk_enable` por clock, SIN tocar rates** | `msm_dss_enable_clk` @0xc6c18 (w2=1). Detalle §3 |
| 6 | `0x1000a0-0x10036c` | Recorre callbacks de eventos registrados (lista en `+0x130`, `blr x8` con magic-check `0xa620bcab`) | `sde_power_handle_register_event` (registro) |
| 7 | `0x1002fc-0x100308` | evtlog + `mutex_unlock`, return | — |

**Rama DISABLE (bit0=0, entra por `0x10010c`):**

| # | Offset | Operación |
|---|---|---|
| 1 | `0x10014c/0x100168` | evtlog + `sde_rsc_client_state_update` |
| 2 | `0x100190-0x100238` | **Bucle `strcmp` sobre los clocks contra el nombre reservado** (`+0x170`, guardado por `sde_power_clk_reserve_rate`): si coincide, `nuevo = min(reservado, actual)` → `msm_dss_single_clk_set_rate(clk)` (¡con el clock TODAVÍA habilitado!) y marca `+0x44=1`. Solo corre si flag `+0x151` y `num_clocks>0` |
| 3 | `0x10024c` | Deshabilita clocks (`msm_dss_enable_clk` con w2=0 → `clk_disable + clk_unprepare`) |
| 4 | `0x10025c/0x10026c` | `sde_power_scale_reg_bus` + `msm_dss_enable_vreg` (votos a 0) |
| 5 | `0x100284-0x1002b8` | `_sde_power_data_bus_set_quota` ×3 (cuotas a 0) |
| 6 | evtlog + `mutex_unlock` | — |

**Hechos clave para el contraste con mainline:**

- El path de **enable NO contiene NI UNA llamada a set_rate** (verificado: la lista
  ordenada de `CALL26` en `0xfff08-0x1007c4` es `mutex_lock, sde_rsc_client_create,
  _sde_power_data_bus_set_quota ×3, msm_dss_enable_vreg, sde_power_scale_reg_bus,
  sde_evtlog_log, sde_rsc_client_state_update, msm_dss_enable_clk, strcmp,
  msm_dss_single_clk_set_rate (solo en rama disable), …`).
- **¿SRC antes que rama? NO hay tal concepto en el SDE**: el SRC (`DISP_CC_MDSS_MDP_CLK_SRC`)
  **no aparece en ninguna lista de clocks del SDE** (ni en DT §3, ni en `strings` del `.ko`:
  no existe `mdp_clk_src`/`MDP_CLK_SRC`/`parked` — solo `strm{0,1}_clks_parked` del lado DSI).
  El SDE solo `clk_get`/`prepare`/`enable`a **ramas**; el RCG padre lo mueve el CCF por
  propagación, y solo cuando alguien pide un rate distinto.
- **¿Con qué rate? Con ninguno en el enable.** Los rates se siembran UNA vez en el
  **probe** (§1.3) y se re-votan en **commits atómicos** (§3.3), nunca en el power-on.

### 1.3 `sde_power_resource_init` @0xfee50 (size 3144) — siembra de rates en probe

Lee del DT (nombres verificados por offset `.rodata`): `clock-names` (0x52718),
`clock-max-rate` (0x29a4e), `clock-rate` (0x3679b), `clock-mmrm` (0x1ac46),
`qcom,platform-supply-entries`, `interconnect-names` + vectores
`qcom,sde-reg-bus` / `qcom,sde-data-bus`, y llama en orden:

```
msm_dss_get_vreg @0xff2f4 → msm_dss_get_clk @0xff308 → msm_dss_mmrm_register @0xff328
→ msm_dss_clk_set_rate @0xff338  ← SIEMBRA los rates del DT (una vez)
→ parseo interconnects (of_icc_get ×4 + icc_set_tag) → __mutex_init …
```

`msm_dss_clk_set_rate` itera `msm_dss_single_clk_set_rate` sobre todos los clocks.
En probe los clocks están CCF-deshabilitados ⇒ para un RCG compartido,
`__clk_rcg2_shared_set_rate` **solo cachea `parked_cfg`, no toca el HW**.
El valor sembrado es el del DT = **514 MHz** = el rate que deja el ABL (§3.2).

---

## 2. VBIF

### 2.1 `sde_vbif_init_memtypes` @0xbd980 (size 500) — dos guards antes de escribir

| Offset | Instrucciones | Efecto |
|---|---|---|
| `0xbd998-0xbd9a4` | `x8=[x0+0x90]; x9=[x8+0x5220]; tbz w9,#31 → 0xbda44` | **Guard nº1**: si el bit31 está SET, NO salta a la escritura: cae al path de mutex+debug y **retorna sin escribir** (`0xbda10` unlock → `___drm_dbg "vbif operations not permitted"` (.rodata+0x4d5b9) → `0xbdb60 ret`). Si está CLEAR (o base NULL en `0xbd9a8`), salta a `0xbda44` = el bucle de escritura |
| `0xbd9b8-0xbda0c` | Segundo test sobre `[[x19+0x90]+0x5220]` bit33 + `w8=[x19+0xd88]` vs 1 + `w8=[x19+0xd80]` vs 6 + máscaras `(1<<w8)&0x64` / `(1<<w8)&0x1a` | **Guard nº2** (tipo de panel / estado): según combinación, o retorna por el mismo `"vbif operations not permitted"` (`0xbda10`) o continúa (`0xbda3c` unlock → escritura) |
| `0xbda44-0xbdb40` | Dos bucles (`+0xd20` y `+0xd28`): `mutex_lock(+0x80)`; por cada XIN `blr set_mem_type(idx, memtype[idx])` (puntero en `+0x68`, valor en `+0xd4`, magic-check `0x5c3594a5`); `mutex_unlock` | **La escritura**: programa los memtypes del DT en cada XIN del VBIF |

### 2.2 El caller la salta entera con splash: `sde_kms_handle_power_event` @0x9eaf8

Dispatch por `w20` (tipo de evento): `cmp #1 → 0x9ecb0` (disable), `cmp #8 → sigue`
(enable); otro valor → return directo (`0x9eb7c b.ne 0x9ed2c`).

**Enable (event=8):** `sde_irq_update(h,1)` @0x9eb8c → `sde_hw_set_rotator_sid`
(si `[[x19+0x90]+0x4ac8]` activo) → callback QoS (`blr` @0x9ebf0) →
**guards cont-splash @0x9ec04-0x9ec2c**:

```
0x9ec00: w10 = [[[x19+0x90]+0x4ac8]+0x7c0]   (flag splash del catálogo)
0x9ec04: cbz w10 → 0x9ec14                     (si no hay splash, seguir)
0x9ec08: cbz x9 → 0x9ed54 (llcc)                (base nula → rama error llcc)
0x9ec0c: ldrb w8,[x8]; cbz → 0x9ed54
0x9ec14: w8 = [x19+0x9b8]; cbnz → 0x9ed2c      ← SKIP: vuelve sin tocar VBIF/QoS
0x9ec1c-0x9ec2c: segundo flag [[[x19+0x90]+0x4ac8]] → cbnz → 0x9ed2c (skip)
0x9ec30: sde_vbif_init_memtypes @0x9ec34  (solo si NO hay splash)
0x9ec38-0x9ec68: callback de perf (blr) → sde_vbif_set_qos_remap @0x9eca8
```

`[x19+0x9b8]` es **el mismo campo que lee `sde_kms_check_for_splash`** @0x9da50
(`ldr w8,[x0+0x9b8]; cset w0,ne` = "¿hay cont-splash?"). Doble cerrojo: caller
(`0x9ec14`) + callee (`0xbd9a4`).

**Disable (event=1):** `sde_irq_update(h,0)` @0x9ecd8 → `strb wzr,[x19+0xdd8]`
→ si no hay splash: callback `+0x50` (`blr` @0x9ed20) → `sde_vbif_axi_halt_request`
@0x9ed28. Con splash: salta directo al halt. Además rama LLCC (`0x9ed54-0x9edbc`):
`llcc_slice_getd/activate/deactivate` con `_printk` de error (no fatal).

### 2.3 ¿Qué escribe y qué pasa si se reescribe lo del ABL?

- Valores: `qcom,sde-vbif-memtype-{0,1}` del DT = **8 celdas × `0x3`** (todo `0x3`).
  El bucle escribe esos memtypes por XIN vía `ops->set_mem_type`.
- Si se reescribiera sobre el VBIF del ABL **con los mismos valores, el estado final
  sería idéntico** (escritura idempotente de un program-once por XIN). El riesgo no es
  el valor sino el momento: con XINs transfiriendo (scanout vivo), tocar VBIF es
  jugársela en mitad de una transferencia — por eso el vendor lo salta por partida
  doble y deja constancia (`"vbif operations not permitted"`). Mainline, en cambio,
  lo reescribe **incondicionalmente** en los dos sitios (`dpu_kms.c:1281` en hw_init y
  `:1466` en runtime_resume, `dpu_vbif_init_memtypes` sin ningún guard).

---

## 3. Los clocks

### 3.1 Qué clocks configura el SDE (DT Android `qcom,mdss_mdp@ae00000`)

| clock-names (6) | clocks (provider,id) | clock-rate | clock-max-rate | clock-mmrm |
|---|---|---|---|---|
| `gcc_bus` | gcc `0x16e`/0x15 | 0 | 0 | 0 |
| `iface_clk` | dispcc `0x154`/0x02 | 0 | 0 | 0 |
| `branch_clk` | dispcc/0x3d | **514 000 000** (`0x1ea30480`) | 600 000 000 (`0x23c34600`) | 0 |
| `core_clk` | dispcc/0x3e | **514 000 000** | 600 000 000 | **0x3e** |
| `vsync_clk` | dispcc/0x49 | 19 200 000 (`0x124f800`) | 19 200 000 | 0 |
| `lut_clk` | dispcc/0x40 | 514 000 000 | 600 000 000 | 0 |

- **El `DISP_CC_MDSS_MDP_CLK_SRC` NO está en la lista.** Ningún clock del SDE es un
  RCG: son todas ramas (+ el bus de GCC). El SDE jamás lo pide (`clk_get`), jamás lo
  vota y jamás lo habilita/deshabilita directamente.
- La siembra 514 MHz **coincide con el rate del ABL** citado en el bloqueo
  (514 MHz). `vsync` 19,2 MHz = XO.

### 3.2 `msm_dss_enable_clk` @0xc6c18 — prepare/enable pelado

Stride de struct `0x78` (120). Con w2=1: `clk_prepare` (0xc6c64) + `clk_enable`
(0xc6c70) por clock, con unwind en error (`clk_disable/unprepare` de los ya
encendidos). Con w2=0: `clk_disable + clk_unprepare`. **Cero lógica de rates.**

### 3.3 `msm_dss_single_clk_set_rate` @0xc6a14 — el `branch_clk` es no-op por nombre

```
strcmp(nombre, "branch_clk")            @0xc6a54, patrón .rodata+0x43b26
  == 0 → 0xc6ad0: return 0 SIN HACER NADA   ← el clock MDP nunca se reprograma por aquí
  != 0 → si cliente MMRM activo (count==2): mmrm_client_set_value (voto agregado, sin tocar CCF)
          si no: clk_set_rate directo       (solo con el clock ya habilitado en commits)
```

Llamantes de `sde_power_clk_set_rate` / `reserve_rate` (grep en `.text` completo):
**solo `sde_core_perf_*`** (`crtc_check` @0x896ac, `crtc_reserve_res` @0x8ac5c,
`crtc_update` @0x8b270, `mode_write` @0x8c03c) = votos de perf en **commits atómicos**,
con clocks habilitados (retarget live gestionado por el CCF + MMRM, no en el power-on).
`sde_power_clk_reserve_rate` @0x100818 solo guarda (nombre→`+0x170`, rate→`+0x190`)
para el paso 2 de la rama disable (§1.2). `get_max_rate` @0x100bfc = bucle `strcmp`.

**Contraste mainline** (`k52L27-tree`): `mdss_mdp` trae **5** clocks
(`nrt_bus`=GCC_DISP_HF_AXI, `iface`=AHB, `lut`, `core`=MDP, `vsync`), **sin SRC**,
`dpu_runtime_resume` hace `clk_bulk_prepare_enable` de los 5 (`dpu_kms.c:1460`) **sin
ningún `set_rate` previo** y `dpu_kms_hw_init` llama a `pm_runtime_resume_and_get`
(`:1162`) antes de tocar el HW. El primer enable de la rama `core` propaga al RCG
padre compartido → `clk_rcg2_shared_enable` (`clk-rcg2.c:1423`) escribe
`parked_cfg` (= 0, nunca sembrado) + UPDATE sobre el RCG a 514 MHz del ABL.
En dispcc, `disp_cc_mdss_mdp_clk_src` usa `clk_rcg2_shared_ops` (`dispcc-sm8550.c:639`,
cuyo `.init` además aparca el RCG a safe-source en el probe).

---

## 4. Power domains — el SDE NO gestiona la GDSC (en uke, ni siquiera se registra)

En `sde_kms_hw_init`, `@0x97e60-0x97ec0`:

```
x23 = x19+0x98                                   (struct genpd embebido)
of_find_property(nodo, "#power-domain-cells")    @0x97e74 (.rodata+0x64a6b)
cbz → 0x97efc  (SIN propiedad: SALTA todo lo siguiente)
[x19+0x5d0] = sde_kms_pd_disable @0x9e570        @0x97e94
[x19+0x5d8] = sde_kms_pd_enable  @0x9e5f4        @0x97ea8
pm_genpd_init(genpd, gov=NULL, is_off=1)         @0x97eac
of_genpd_add_provider_simple(nodo)               @0x97ec0
```

- **El SDE se registraría como PROVEEDOR genpd, nunca como consumidor.**
  Y sus callbacks `pd_enable/disable` son solo `__pm_runtime_resume/idle` del propio
  dispositivo (§1.1) — **no tocan ninguna GDSC, ni la apagan ni la encienden**.
- En el DT de uke el nodo `qcom,mdss_mdp@ae00000` **NO trae `power-domains`,
  NO trae `#power-domain-cells`** (verificado: solo `#cooling-cells`,
  `#interrupt-cells`; supplies: `mmcx-supply` + una `platform-supply-entry` `mmcx`
  con todos los voltajes/cargas a 0) **y NO trae `resets`**.
  ⇒ En uke el registro como proveedor **se salta** (el `cbz` de `0x97e78`).
  La GDSC del MDSS queda exactamente como la dejó el ABL (ON), sin que el KMD la
  toque jamás.
- **Contraste mainline** (`palawan.dtsi:3357-3382`): el padre `mdss` declara
  `power-domains = <&dispcc MDSS_GDSC>` + `resets = <&dispcc DISP_CC_MDSS_CORE_BCR>`
  y el hijo `mdss_mdp` `power-domains = <&rpmhpd RPMHPD_MMCX>` + `mdp_opp_table`
  (200/325/375/514 MHz sobre el clock `core`). Mainline sí ata el display al
  framework genpd/OPP; el vendor en uke, no.

---

## 5. IRQs y eventos de power

`sde_irq_update` @0x87a18 (88 B): guarda `w1&1` en `[x0+0x77c]`, lee el hwirq de
`[x0+0x778]`; `w1 bit0=1 → enable_irq` (@0x87a3c), `=0 → disable_irq` (@0x87a44);
si el número es 0, `_printk` y return.

Orden en `sde_kms_handle_power_event`:

| Evento | Offset | Orden |
|---|---|---|
| enable (8) | `0x9eb80-0x9eb8c` | `sde_irq_update(h,1)` **lo primero**, antes de VBIF/QoS. Además `strb 1 → [x19+0xdd8]` |
| disable (1) | `0x9ecd0-0x9ecd8` | `sde_irq_update(h,0)` **lo primero**, antes del halt; `strb 0 → [x19+0xdd8]` |

Ventana: las IRQs que dejó el ABL siguen vivas hasta que corre el disable; en el
power-up el KMD instala/habilita su handler antes de tocar cualquier registro del
DPU/VBIF. No hay reprogramación del controlador de interrupciones del MDSS en el
path (el chained handler del `mdss` se registra una vez en el probe, fuera de este
flujo). Registros relacionados: `sde_kms_cpu_vote_for_irq` (0x96014), notifier
`sde_kms_irq_affinity_{notify,release}` (0x9e2c4/0x9e354) — fuera del bind.

---

## 6. El splash handoff — qué toma y qué NO hace

### 6.1 `sde_kms_cont_splash_config` @0x967b4 (2156 B)

Lista ordenada de `CALL26`: solo DRM-state, **cero programación de HW**:

```
dsi_display_get_info → drm_connector_list_iter_{begin,next,end} → drm_mode_equal
→ drm_atomic_set_mode_for_crtc → drm_mode_copy ×2
→ sde_encoder_update_caps_for_cont_splash → sde_crtc_update_cont_splash_settings
→ sde_plane_pipe → is_sde_plane_virtual → sde_plane_validate_src_addr ×2
(+ _printk/___drm_dbg/mutex; .text+0xa0398 ×2 = sde_kms_inform_cont_splash_res_disable)
```

Toma: el **modo** del ABL (lo iguala al modo DRM del CRTC), las caps del encoder y la
config del CRTC/planos. NO toca: clocks, reguladores, VBIF, QoS, IRQs, GDSC.

### 6.2 `dsi_display_cont_splash_config` @0x13f720 (588 B)

```
__pm_runtime_resume → mutex_lock → dsi_display_clk_mngr_update_splash_status
→ sde_evtlog_log → dsi_ctrl_isr_configure ×2 (toma las ISRs de ambos ctrls)
→ dsi_display_clk_ctrl (vota link/core) → dsi_ctrl_isr_configure ×2
→ dsi_display_clk_mngr_update_splash_status → __pm_runtime_idle → mutex_unlock
→ dsi_panel_bl_handoff (cola: hereda el backlight)
```

NO hace: reset de PHY/host, reguladores, reset-gpio, ni un solo DCS. Solo toma
posesión de clocks/ISRs y marca el estado splash. (El prepare normal, con splash,
salta `pre_prepare/soft_reset/panel_prepare` — ver SECUENCIA-O82 §A.4.)

### 6.3 `sde_rm_cont_splash_res_init` @0x8dbbc (1316 B) + `sde_encoder_in_cont_splash`

- Reserva los bloques HW que el ABL dejó en uso (mixers/ctls/pipes/DSPP) vía
  `_sde_rm_get_hw_locked` (estática), con trazas del inventario
  (`mixer_count/ctl_count/dsc_count`, `finding resources for display/ctl`,
  `lm_cnt/lm_id/pipe_cnt`, `CTL[path] using dsc`) y cierre
  `"cont_splash handoff done, remaining:%d"` (.rodata+0xee71).
- Llamado desde `sde_kms_hw_init` @0x9859c, y después el hw_init **marca como usados**
  los recursos heredados (bucle `0x985b4-0x9865c`: pone a cero las entradas libres
  del RM para los `w22` displays con splash).
- `sde_encoder_in_cont_splash` @0x6997c (28 B): retorna el byte
  `[[enc+0x120]+0x7c9]` (0 si enc nulo) — flag "este encoder lo lleva el splash",
  usado por `sde_kms_pm_resume` (@0x9d654) y `pm_suspend` para decidir el camino.

---

## 7. La pregunta directa

> Mainline escribe `parked_cfg=0` sobre un RCG que el ABL dejó a 514 MHz.
> ¿Hay en el KMD algún mecanismo que evite exactamente eso?

**No existe un guard explícito del tipo `if (!parked_cfg) skip` en el KMD.**
Verificado: `msm_dss_enable_clk` (@0xc6c18) no lee ningún rate; `clk_rcg2_shared_enable`
vive en el driver dispcc (fuera de este `.ko`); si `parked_cfg` fuera 0 en el primer
enable, el CCF del vendor escribiría el 0 igual que mainline. **Lo que existe es una
protección estructural en 5 capas, que hace que `parked_cfg` nunca sea 0 cuando llega
el primer enable:**

1. **Siembra en probe (§1.3):** `sde_power_resource_init → msm_dss_clk_set_rate`
   (@0xff338) programa los rates del DT — `branch/core/lut = 514 MHz` = el rate del
   ABL — mientras los clocks están CCF-deshabilitados, es decir, solo se cachea
   `parked_cfg`, sin tocar el HW. El primer `shared_enable` posterior restaura 514 M,
   no clobbera.
2. **El enable no vota rates (§1.2):** el path de `sde_power_resource_enable(h,1)`
   no contiene ninguna llamada a set_rate; solo `prepare+enable`.
3. **`branch_clk` es no-op por nombre (§3.3):** `msm_dss_single_clk_set_rate` retorna 0
   sin hacer nada si el clock se llama `branch_clk` (`strcmp` @0xc6a54 → `0xc6ad0`).
   El clock de la rama MDP no se puede reprogramar por esta vía ni queriendo; el resto
   va por MMRM (`mmrm_client_set_value`) o `clk_set_rate` solo en commits.
4. **Skip completo con splash (§1.1 + §2.2):** `msm_runtime_{resume,suspend}` omiten
   `resource_enable` si `[handle+0x1b0]` (guards en `0x164188`/`0x164130`), y
   `handle_power_event`/`vbif_init_memtypes` omiten VBIF+QoS (guards en `0x9ec14` y
   `0xbd9a4`). Con splash vivo el primer enable real ocurre en el primer commit
   post-handoff, con todo el estado ya coherente.
5. **El SRC no existe para el SDE (§3.1):** no está en el DT, no se pide, no se vota.
   Todo rate va a ramas; el RCG solo se mueve por propagación CCF hacia valores ya
   sembrados.

**Los 3 candidatos más probables para por qué Android sobrevive (ordenados):**

| # | Candidato | Por qué es el más probable |
|---|---|---|
| 1 | **Siembra 514 M en probe + enable sin set_rate** (capas 1+2) | Es la diferencia exacta y suficiente contra el `parked_cfg=0` de mainline: el primer `shared_enable` del vendor escribe de vuelta el rate del ABL; el de mainline escribe 0. Un solo mecanismo explica el bind que sobrevive vs el que muere en `dpu_kms_hw_init` (~3,96 s). Verificable en vivo comparando el CFG del RCG antes/después del bind en cada kernel |
| 2 | **Skip de todo el power-on con splash** (capa 4, guards `0x164188`/`0x164130`/`0x9ec14`/`0xbd9a4`) | Con splash, el vendor ni siquiera llega a ejecutar el enable: elimina de raíz la ventana del clobber durante el boot. Mainline no tiene equivalente (resume y vbif incondicionales) |
| 3 | **Cero gestión de GDSC/BCR en uke** (§4: sin `resets`, sin `power-domains`, sin `#power-domain-cells` ⇒ `pm_genpd_init` saltado) + VBIF idempotente saltado (§2.3) | Quita los otros dos pisos del trifecta mainline (reset duro + parking del RCG en probe + reescritura VBIF). Cada uno es independientemente letal con el scanout vivo; el vendor no ejecuta ninguno |

**Nota de honestidad:** el lado dispcc del vendor (el `shared_init` que en mainline
aparca el RCG en el probe, `clk-rcg2.c:1516-1545`) NO está en este `.ko` y Xiaomi no
publica el techpack display (`uke-v-oss` no lo trae — ya verificado el 12-oct, ver
SECUENCIA-O82 §D). No se puede descartar que el dispcc vendor use
`clk_rcg2_shared_no_init_park_ops` (que no aparca) en vez de `shared_ops`; sería la
6ª capa. Lo afirmable con evidencia local es lo de arriba.

**Implicación práctica para mainline** (no pedido, se deja en una línea): sembrar el
rate del SRC antes del primer enable (p. ej. `assigned-clock-rates` sobre
`DISP_CC_MDSS_MDP_CLK_SRC` a 514 M, o `clk_set_rate` en el probe del DPU antes del
`prepare_enable`), + saltar `dpu_vbif_init_memtypes` con splash heredado, es el
equivalente mínimo de las capas 1+4. El BCR ya está gateado (L22b/L24) y no forma
parte de este informe.
