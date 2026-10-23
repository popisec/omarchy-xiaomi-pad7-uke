# PLAN-PANTALLA 2026-10-08 (#547) — Ingeniero de pantalla: estado medido, secuencia vendor y encendido por pasos

**Alcance**: solo-lectura por SSH sobre la tablet. Única excepción registrada: la tablet NO
estaba en Arch sino en **fastboot** (`lsusb` 18d1:d00d, `product: uke`, slot a); el dueño
aprobó `fastboot reboot` (0 escrituras, arranca el slot a vigente) y a partir de ahí TODO lo
medido es lectura. Kernel vivo: **k52b2** (#534: `5276fe0f…` desde k52-tree, receta dorada) +
**dtbo s269**, cmdline dorada. Kernel string `7.2.0-rc2-palawan` (igual en todos los builds;
lo que distingue son las migas UKE).

Base de código citada: `build/kernel-pokes/k52-tree/` (drivers/gpu/drm). Evidencia vendor:
`build/evidencia/android-full/extracted-full/{02-display,15-common}/` y ledger hermano
(`~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`, #505–#509).

---

## 1. Estado medido hoy (SSH, boot k52b2 + s269)

| Qué | Valor medido | Lectura |
|---|---|---|
| card0 | `Initialized msm 1.13.0` a 4,03 s; DPU `dpu hardware revision:0xa0010000` | DPU-solo levantó card0 (GPU `disabled`, §1-b) |
| DSI-1 | `status=disconnected`, `enabled=disabled`, `dpms=On`, **`modes` VACÍO** | 100 % explicado por `video=DSI-1:d` (ver §2) |
| Writeback-1 | `status=unknown`, disabled | conector DPU de scanout a memoria (test discriminador de V4 §3b) |
| Backlight | `ae94000.dsi.0` existe: `brightness=307` (0x133), `max=4095`, `bl_power=0` | probe del panel llegó hasta el final (`o82_probe` completo) |
| Migas panel | **CERO** `UKE-P82: prepare` / `get_modes` en el arranque | el panel JAMÁS fue ejercitado: ni un comando DSI de init |
| Migas K47 | `K47-pan-bl` + `K47-host-xfer` ×5 a los 7,65 s | systemd-backlight escribe brightness → `o82_bl_update_status` → `dsi_host_transfer` **falla con -EINVAL** (host sin `power_on`, `dsi_host.c:1774`). Inofensivo, ya documentado |
| ESD | irq 83/84 armadas con dueño (K49); **irq 84 disparó 1× al probe** (val=1) y fue absorbida | el TDDI en estado BL asevera; el dueño funciona |
| Relojes DSI | `dsi0vco/dsi1vco/byte0/byte1/pclk0/pclk1` todos `0 0 0 0` | **PHY DSI nunca entrenada, PLL nunca encendida**; solo ahb/axi del dispcc activos |
| debugfs | montado (1), sin `dsi*`/`mdp*` | el msm mainline no publica debugfs de DSI (es cosa del vendor) |
| Reguladores | `pmxr2230_l4` (vdda ctrl) 1,2 V enabled; `pmxr2230_l2` (vdds PHY) 0,88 V enabled; **`pmxr2230_l8` (vddil8b panel) state=unknown a 1,304 V**; `uke_panel_vsp/vsn` disabled (los `boot-on` los apagó el regulator core a los 33,7 s al no tener consumidor) | **HALLAZGO NUEVO**: L8, el rail de IO del TDDI, está a **1,304 V, no a los 1,9 V** del vendor (init `0x1cfde0`=1 898 976 µV). El driver solo hace `set_load(300 mA)+enable` (`o82_power_on`, panel-xiaomi-o82-dualdsi.c:293-325, SIN `set_voltage`) ⇒ el primer enable la dejaría a 1,304 V |
| DT vivo | `panel@0` = `xiaomi,uke-o82-4202-0b` con `esd-err-gpios`, `ports` a ambos DSI, supplies vddil8b/vsp/vsn; `dsi@ae94000`/`ae96000` okay; `qcom,kgsl-3d0@3d00000` **status=disabled** | s269 aplicado y GPU OFF confirmado (el muro SQE/CM3 de K34–K44 está fuera del camino) |
| Táctil | `novatek-nt36xxx-spi spi0.0`: probe "ok" pero chip **mudo** (SPI `-110`, handshake bootloader fallido a los 46,97 s, "revisar alimentacion TDDI"); `input0` registrado; **irq real 185** (TLMM, trigger falling) | el NT36532 táctil comparte energía con el panel: sin panel no hay táctil. OJO: la **54** de los docs es `ss_phy_irq` (USB) — el "IRQ 54" del fragmento táctil viejo es un error documental; lo vivo es 185 |

Sync-state: `disp_cc` pendiente de `ae94000/ae96000` y de `soc:qcom,dsi-display-primary`
(nodo vendor residual que reclama relojes del dispcc — no bloquea, pero anotado).

---

## 2. Código del fork (k52-tree): qué existe, qué traba, qué falta

**El driver del panel está COMPLETO** (`drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`):
init sequence vendor de 998 B transcrita verbatim (`o82_init_cmds` :99-181), reset 4-flancos
(`o82_reset` :264-287, estirado a 100 ms el release final), dual-DSI bonded broadcast
(`o82_send_panel_cmds` :210 → `mipi_dsi_dual_dcs_write_buffer_multi`), cola de timing 120 Hz
(0xb3=0x40/0xb2=0x91), sleep-out 0x11 + 120 ms, display-on 0x29, backlight por DCS 0x51 a
ambos links (:484-504), DSC 1.1 (slice 800×24, ×2 por link, `o82_dsc_config` :588),
`prepare_prev_first` (:740) y ESD con dueño (:628-704). Un único modo expuesto:
**3200×2136@120** (`o82_modes` :538, `num_modes=1` :608).

**El flujo detect→enable** (orden real, `dsi_manager.c` + `bridge/panel.c`, verificado en
R2/R5/V4): cliente (fbdev/modetest) → `get_modes` (miga `K47-pan-modes`) → panel
**prepare ANTES que el host** (`prepare_prev_first`) → `dsi_mgr_bridge_power_on`
(PHY + `msm_dsi_host_power_on`, migas `K47-host-pwr` :2487) → `dsi_mgr_bridge_pre_enable`
(`K47-host-en` :2433; en bonded el master enciende AMBOS hosts) → encoder/DSC → CRTC →
timing on → vblank. En bonded, la PHY esclava va del PLL del master (cableado del OVL,
R5 §3b). **El catálogo mainline de palawan SÍ tiene bloques DSC**
(`catalog/dpu_10_1_palawan.h`: `dce_0_0/dce_0_1/dce_1_0` :224-236, `.dsc_count` :361) —
el sospechoso DSC 2.9 de V4 queda despejado por código.

**La traba actual es la cmdline**: `video=DSI-1:d` → `DRM_FORCE_OFF`
(`drm_connector.c:158-176` imprime el `[drm] forcing DSI-1 connector off` medido) →
`drm_probe_helper.c:589-596` pone `disconnected` **sin llamar a detect** y sale **antes de
pedir modos** (:641-649) ⇒ `modes` vacío para CUALQUIER usuario, y modetest no puede hacer
`-s` (necesita un modo de la lista). El conector DSI del bridge **siempre detecta
`connected`** (R5 §4): sin el `:d`, sysfs diría `connected` + 1 modo sin tocar HW.

**El viejo "quitar `:d` cuelga el arranque" (#463) YA NO APLICA tal cual**: el cuelgue era el
DPU pidiendo el SQE del GPU y luego el muro CM3 `S3-rst0` (#474–#482); con el GPU
`disabled` en s269, `msm` no toca GPU y `msm_open` con `gpu=NULL` retorna 0 (U2 §1). Es
**no-verificado en el linaje GPU-off** — por eso el paso A lo mide primero con red de
seguridad (timeout + captura), no se asume.

**Lo que falta** (por orden de bloqueo real):
1. **Un des-force**: sin quitar `:d` no hay modeset posible ni por userspace (modetest no
   puede; solo un cliente a medida con `MODE_ID` blob custom lo rodearía — innecesario si
   vamos al paso B). La escalera P82D de V4 §1 **no está horneada en k52** (grep
   `UKE-P82D` = 0 hits): una muerte en la zona DPU/DSC/scanout sería semi-ciega con las
   migas actuales (K47 cubre panel+host power/enable; DPU-side solo `K13`).
2. **El rail L8 en su tensión**: ver hallazgo de §1. Sin `set_voltage`, el panel IO arranca
   a 1,304 V (fuera de spec del vendor: 1,9 V). Puede dar "cmds rc=0 pero panel sin lógica
   válida", o TDDI muerto/marginal. Es la corrección física nº 1.
3. **El backlight** lo controla el TDDI vía DCS 0x51 (no hay PWM): necesita el host
   `power_on`; hasta entonces sysfs devuelve error (medido hoy ×5).

---

## 3. Secuencia del vendor (evidencia android-full) y el "trigger del TDDI"

El dmesg vendor capturado arranca a ~5,2 s (el panel ya está encendido desde el kernel boot;
la primera ON queda fuera de captura). Las ON posteriores (ciclos a 128 s, 369 s y 410 s del
`15-common/dmesg-full.txt`) muestran la secuencia completa de encendido:

```
1. dsi_ctrl_isr_configure: IRQs dsi-ctrl-0/1 registradas (357/358)   [128.452]
2. (oculto en el arranque: rails L8B/vsp/vsn, reset TLMM2 10/3/3/15ms,
    init cmds 998 B en LP a ambos links, DSC en DPU, vídeo HS)
3. dsi_panel_enable: DSI_CMD_SET_MI_ROUND_CORNER_ON (feature OFF → no-op) [128.497]
4. mi_dsi_print_51_backlight_log: "set 51 backlight 65295"            [128.499]
5. dsi_panel_enable: DSI_CMD_SET_ON  (la init/on command del DT)      [128.621]
6. dsi_display_set_power: "Display (primary), Power mode (On)"        [128.621]
7. esd irq enable + second                                            [128.634]
8. "disable insert black after none zero backlight" + dimming          [128.672]
```

Total ON≈170–230 ms. **No existe un comando mágico "boot-complete"** (0x29/0x39 especial):
el trigger del TDDI **ES el propio reset + la init sequence en LP** — la misma que nuestro
driver ya transcribe. Lo que sí está medido con cronómetro (ledger **#508**): el firmware
del TDDI **completa su boot interno ~75–100 ms tras el release final del reset** y entonces
"actúa" (asevera sus líneas ESD/INT). Nuestra secuencia ya respeta esa ventana (release
estirado a 100 ms en K48-rst + sleep-out después), y las aserciones ahora tienen dueño
(K49). El táctil vendor (NVT-ts) está vivo leyendo info del panel por SPI a 6,35 s — con el
panel encendido desde el boot.

Lo que el vendor hace y nosotros no (ninguno bloquea el primer píxel): esd-check por polling
(`qcom,esd-check-enabled`), round-corner (no-op), insert-black de backlight, dimming/CABC,
escritura de count-info al panel por DCS (cosmético), IRQs propias de dsi-ctrl.

---

## 4. Plan de encendido por pasos (sin GPU; comandos exactos)

Vehículos, de menos a más coste: **A** = sesión Arch actual por SSH (0 cambios);
**B** = repack del boot actual cambiando SOLO la cmdline, arrancado con
`fastboot boot` (**boot desde RAM, 0 escrituras** — el slot a queda intacto; caer de vuelta
a fastboot es gratis); **C** = kernel parcheado (set_voltage + escalera P82D), también
arrancable por `fastboot boot` antes de decidir un flash. Gates de fastboot habituales
(batería ≥3700 mV + cargador, exención #508 vigente, capturador armado ANTES del boot).

### PASO A (hoy, 0 cambios): instalar modetest y probar el open DRM con red de seguridad

Instala el staging que el proyecto ya tiene (`build/pkg/staging-p2-ctrl/INSTALAR.txt`;
Arch-ARM libdrm **incluye `modetest`** — verificado en el .pkg: `usr/bin/modetest`):

```bash
# PC
scp -i ~/proyectos/omarchy-uke/build/rootfs/uke-arch-root \
    ~/proyectos/omarchy-uke/build/pkg/staging-p2-ctrl/libdrm-2.4.134-1-aarch64.pkg.tar.xz \
    root@192.168.42.129:/root/
# TAB (ssh)
pacman -U --noconfirm /root/libdrm-2.4.134-1-aarch64.pkg.tar.xz && modetest -V 2>/dev/null || modetest --help 2>&1 | head -1
# captura viva desprendida + vigía de IRQs (antes de cualquier peldaño)
setsid sh -c 'dmesg -w > /root/dmesg-vivo.txt 2>&1' &
```

Peldaño **(a)** — línea base sysfs (0 ioctls): re-leer §1 (status/modes,
`regulator/regulator_summary`, `devices_deferred`, `/proc/interrupts` líneas 83/84/185).
Peldaño **(d)** — **el open DRM** (cierra si #P43 revive en el linaje GPU-off):

```bash
# PC: timeout duro del lado PC; si la tablet cuelga, lo sabremos por el timeout y el tail de dmesg
timeout 30 ssh -i ~/proyectos/omarchy-uke/build/rootfs/uke-arch-root root@192.168.42.129 \
    'modetest -M msm -c 2>&1 | tail -40; echo rc=$?'
```

Con `:d` el GETCONNECTOR ni llega a `detect` (force), así que este peldaño es **puro
open-path** (el asesino histórico #P43 vivía ahí): si vuelve la lista de conectores
(DSI-1 + Writeback-1), el open es SEGURO con GPU off y quedan autorizados B y C. Si cuelga
→ veto total y el asesino sigue vivo — peldaño ORO, cuesta 0.
Extra gratis del mismo peldaño: `modetest -M msm -p` (crtc/encoders: cuántos CRTCs ve el
bonded) y `proptest -M msm` (props del conector). **No** intentar `modetest -s`: con `:d`
no hay modos y fallará sin información.

### PASO B (0 escrituras, RAM boot): quitar el force y dejar que el fbdev haga el modeset

Repack del boot VIGENTE (receta `BUILD-RECIPE-DORADA`; los repack ya soportan cmdline
**plain sin `video=`** — `repack-k34.py` sin `--dsid`, 517 B→sin el token) cambiando UNA
sola cosa: **fuera `video=DSI-1:d`**. Sin kernel nuevo, sin dtbo nuevo. Se arranca en RAM:

```bash
# PC (tras generar boot-uke-k52b3-noforce.img con el repack canónico)
fastboot boot build/bootimg/boot-uke-k52b3-noforce.img
# esperar 60–90 s, luego SSH:
dmesg | grep -aE "UKE-P82|UKE-K47|forcing|Cannot find any crtc"
cat /sys/class/drm/card0-DSI-1/status /sys/class/drm/card0-DSI-1/modes
grep -aiE "dsi0vco|byte0|pclk0" /sys/kernel/debug/clk/clk_summary
```

**Qué esperar en dmesg, paso a paso** (cada línea autoriza la siguiente):

| Momento | Línea esperada | Si no llega / firma |
|---|---|---|
| ~4,0 s | YA NO aparece `forcing DSI-1 connector off` | cmdline vieja |
| modeset del fbdev | `UKE-P82: get_modes: entrada` | cadena DT/bridge rota |
| | `UKE-P82: power_on[0..2] … ENABLED` + `power_on: TODAS OK` | FALLO aquí = rails (L8 a 1,304 V puede ser el porqué) |
| | `K48-rst-A … w4-done` (reset completo, 116 ms) | GPIO2: nunca falló desde s258 |
| | `UKE-K47c: cmd#0 … cmd#104` + `init cmds rc=0` | rc<0 = el TDDI no responde en LP (rail/reset/boot TDDI) |
| | `freq_sel OK` → `sleep-out OK` → `display-on ENVIADO (err=0)` → `COMPLETO` | muerte tras `w4-done` sin `R2-ok` = firma #508 (boot TDDI) — cazador arriba |
| post-panel | `K47-host-pwr` ret=0 → `K47-host-en` ×2 | fallo = vdda/relojes link (`dsi_host.c:2507-2515`) |
| post-host | (DSC/DPU sin migas en k52b2: zona ciega) | muerte muda aquí = país de la escalera P82D (paso C) |
| éxito | `Cannot find any crtc or sizes` **desaparece**; DSI-1 `enabled=enabled` + `3200x2136` en modes | — |

Nota: `console=ttynull` ⇒ aunque el fbdev pinte, no habrá texto de consola en pantalla; el
"píxel" observable es la luz de backlight + el link DSI vivo (y un cliente userspace con FB
si se quiere patrón, ver C).

**Decisión abierta para el dueño (regla de un cambio)**: la variante B-pura (solo cmdline)
mide el comportamiento del sistema SIN el fix del rail; la variante **B'** (cmdline + el
parche de `set_voltage` del paso C, es decir kernel nuevo) mete dos variables pero corrige
un valor MEDIDO fuera de spec (1,304 V vs 1,9 V) que puede dar falso negativo del panel en
B-pura. Mi recomendación: **B'** — el set_voltage no es una variable de diagnóstico, es una
corrección física documentada en §1/§3.

### PASO C (kernel nuevo, también RAM-boot primero): set_voltage + escalera P82D

1. **Parche mínimo** en `o82_power_on` (panel-xiaomi-o82-dualdsi.c:293), antes del loop de
   supplies:

```c
/* Vendor: init 0x1cfde0 = 1 898 976 µV en L8B (qcom,regulator-init-voltage).
 * El qcom-rpmh-regulator mainline NO aplica la init del DT (medido 8-oct:
 * L8 = 1,304 V del BL); sin esto el IO del TDDI arranca fuera de spec. */
ret = regulator_set_voltage(ctx->supplies[0].consumer, 1898976, 1898976);
if (ret < 0)
	return ret;
```

2. **Escalera P82D** (V4 §1, 11 puntos: salida de `get_modes`, `dsi_mgr_bridge_power_on`,
   `msm_dsi_host_power_on` con rets de rails/relojes, `pre_enable` master/esclavo,
   `msm_dsi_host_enable`, `dpu_encoder_virt_atomic_enable` + `dsc` no-NULL,
   `dpu_encoder_phys_vid_enable` con idx de ambos intf, `prep_dsc` con `dsc_count`,
   `dpu_crtc_enable` + ret de pm_runtime, timing-on + `intf_status`/`line_count`,
   frame-done/`-ETIMEDOUT`) — sin ella, una muerte DPU-side es ilegible.
3. Compilar con receta dorada (k52-tree, `LLVM=1`, Image.gz sin módulos), repack plain,
   **`fastboot boot`** primero; flash de boot_a SOLO si el ciclo RAM es verde.

Opcional del mismo árbol: cliente mínimo `uke-mode` (~150 líneas, libdrm; compilar en PC
con `clang --target=aarch64-linux-gnu --sysroot=<glibc-arch-arm-extraído>` enlazando contra
la libdrm del staging extraído) que crea el `MODE_ID` blob (timing de `o82_modes` 3200×2136
@967,428 MHz) + dumb-FB de patrón y commitea: único camino a un modeset con `:d` puesto y
única forma de pintar un patrón real sin contar en el fbcon. Bajar a este caballo solo si A
y B dejan dudas.

---

## 5. Riesgos

| Riesgo | Estado / mitigación |
|---|---|
| Asesino del `open()` DRM (#P43) revive | Medido era con GPU presente; ahora GPU `disabled`. El paso A lo mide con timeout+captura ANTES de cualquier peldaño duro. Si cuelga: veto y vuelta al muro |
| Boot-complete del TDDI (#508: actúa a +75–100 ms del release) | ESD irqs con dueño (K49, absorbió la del probe hoy), release 100 ms, `hung_task_panic=0` (cmdline actual), `plymouth.enable=0`, cazador armable. Firma de muerte tras `w4-done` = reconocible |
| Rail L8 a 1,304 V | Corregido en C (`set_voltage`); en B-pura puede ensuciar la medida — decisión B vs B' anotada arriba |
| Tormenta IRQ en reposo (TDDI sin alimentar) | VSP/VSN con boot-on se apagan a ~33 s; los parasitarios volvieron a la vida "errática" (vidas 99–2746 s del ledger). Vigilar contadores 83/84 entre pasos; si crecen con el sistema idle → re-energizar o re-resetear |
| Muerte ciega en DPU/DSC/scanout | Solo posible en B (migas K47 no cubren DPU-side); el paso C hornea P82D. Aceptable: 1 ciclo RAM para saber DÓNDE mirar |
| EXT4 zombi | e2fsck embebido (K50+) y k62-rescue (#546, reintentos+hold_ms) como colchón del ciclo |
| GPU | No tocar: `kgsl` disabled, `renderD128` inerte; `msm_open` sin GPU es el camino teóricamente seguro que A valida |
| Batería/escrituras | B y C arrancan en RAM: 0 escrituras. Flash solo con gates completos y pre-registro |

---

## 6. Checklist de éxito — qué declarar "PANTALLA ENCENDIDA"

1. dmesg completo y en orden: `get_modes` → `prepare: INICIO` → 3 supplies `ENABLED`
   (L8 a **1 898 976 µV** en `regulator_summary`) → reset `w4-done` → `cmd#0..104 rc=0` →
   `freq_sel OK` → `sleep-out OK` → `display-on ENVIADO (err=0)` → `COMPLETO`.
2. `K47-host-pwr` ret=0 y `K47-host-en` ×2 (master+esclavo del bonded).
3. `clk_summary`: `dsi0vco/dsi1vco` enabled; `byte0/byte1` y `pclk0/pclk1` con rate ≠ 0.
4. sysfs: `card0-DSI-1` → `status=connected`, `enabled=enabled`, `modes` con `3200x2136`.
5. `regulator_summary`: `uke_panel_vsp/vsn` enable_count=1 (+5,8/−5,8 V).
6. `/proc/interrupts`: IRQ de vblank/DPU contando (línea que avanza = DPU escanea);
   83/84 estables (sin tormenta ESD).
7. **Luz visible**: backlight aplicándose ya sin error (`echo 800 >
   /sys/class/backlight/ae94000.dsi.0/brightness` → `K47-host-xfer` con rc=0) + FOTO a
   `build/logs/evidencia/` (sin fichero no cierra, REGLAS).
8. Táctil despierto: re-bind del driver novatek (`/sys/bus/spi/drivers/.../unbind|bind`)
   → chip-id OK en dmesg + contador de **irq 185** crece al tocar.

---

## 7. Táctil NT36532 (anotado, medido hoy)

`novatek-nt36xxx-spi spi0.0` probea (vdd/vddio dummy), pero el chip está **mudo**: cada
transferencia SPI da `-110` y el handshake de bootloader fracasa a los 47 s ("revisar
alimentacion TDDI"). El input device queda registrado; el driver sigue sondeando. **IRQ
real = 185** (TLMM, falling); el "IRQ 54" heredado de los docs/fragmentos es `ss_phy_irq`
de USB — corregir la referencia documental cuando se toque el táctil. Con el panel
encendido (los rails del TDDI arriba), el NT36532 debería responder al primer re-bind;
si sigue mudo con panel ON, el siguiente sospechoso es su línea/CS o el orden de reset
(el vendor lo deja vivo desde el BL, nosotros lo arrancamos frío).
