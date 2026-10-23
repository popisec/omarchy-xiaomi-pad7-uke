# CÁMARAS de la uke — plan por etapas C0..C8 (19-oct-2026)

Sesión de cámara (fase 1). Sustituye en lo operativo al estudio de viabilidad `CAMARA-VIBRACION-20261018.md` (que sigue siendo válido como panorama; las correcciones están en §0).
Material: `build/rootfs/deploy/camaras/` (léase su `README.md`). **Nada de esto se ha cargado ni flasheado en la tablet**; lo único hecho en ella fue la línea base de solo lectura de C1 (`out/c1-baseline-20261019-1717.txt`).
Etiquetas: **[MEDIDO]** fichero o ssh de lectura del 19-oct; **[LEÍDO]** fuente o web (URL y fecha); **[INFERIDO]** sin verificar.
Rutas cortas: **DTA** = `build/android/dt-full-uke-android/base/soc/`, **BASE** = `build/kernel-pokes/senemos-7.2.9/dt/res-live-final.dtb` (el DT que ve el kernel), **KT** = `build/kernel-pokes/senemos-7.2.9/linux-7.2.9/`, **CAM** = `build/rootfs/deploy/camaras/`.

## 0. Veredicto y correcciones al estudio del 18-oct

**Viable y mucho más corto de lo estimado: casi todo lo que se creía «clonar» ya existe en el árbol 7.2.9.** El único cambio de kernel es una línea de allowlist de reguladores; todo lo demás va fuera de árbol (módulos + overlay en caliente, el patrón del BT y el audio). Hito 1 (chip-id del sensor trasero por CCI) = **C4**; hito 2 (frame RAW) = **C5**.

| Estudio 18-oct decía | Medido el 19-oct | Efecto |
|---|---|---|
| «CAMSS: clonar recursos de sm8650 con 5 csiphy, no verificado» | **El mapa de la uke == el de `sm8650.dtsi`**: `csid_wrapper acb6000`, `csid0/1/2 acb8000/acba000/acbc000`, lite `accb000/acd0000`, `csiphy0..4 ace4000..acec000`, `vfe0/1/2 ac62000/ac71000/ac80000`, las **15 IRQ SPI idénticas** (601,603,431,605,376,477,478,479,448,122,602,604,688,606,377) y los **SID de SMMU idénticos** (`0x800/0x20` IFE, `0x18a0/0x40`, `0x1860/0`). Solo falta csiphy5 (`acee000`) | recurso `cliffs` = sm8650 con 5 CSIPHY; **sin parche de lógica**, solo una entrada en la tabla (C5) |
| «CAMCC: no hay camcc-cliffs, diffear contra sm8550/milos, M–L» | La fuente OEM `camcc-cliffs.c` (MiCode `uke-v-oss`) da los **mismos offsets que `camcc-sm8650.c`**: MCLK0 `cmd_rcgr 0x15000`, CCI0 `0x131cc`, CPHY_RX `0x1104c`, CSI1PHYTIMER `0x15104`, `max_register 0x1603c`, PLL0..9 en `0x0..0x9000`; el `gdscr` de titan_top es `0x132bc` en mainline y el vendor lo expone como `adf32bc` (=`ade0000+0x132bc`). Los nombres de reloj de Android son un **subconjunto** de los de sm8650 (solo sobra `debug_mux`) | `camcc-sm8650.c` parcheado (3 cambios) en vez de un driver nuevo (C2) |
| «Faltan en ouke4 los rieles l20, l14, bob1, pmr735a_l6, pm_v6c_l3» | Los 5 **existen en el DT vivo** con su `rpmh-regulator-*` pero **sin driver enlazado**: `qcom-rpmh-regulator-uke.c:2000` solo admite 18 recursos por nombre (`strcmp(resource_name, …)`), el resto sale con `-ENODEV` | parche de 3 nombres (`ldob20`, `ldoe6`, `ldoc3`) = **única razón de kernel nuevo** (C3). `bobb1` y `ldob14` se dejan fuera a propósito |
| «Frontal en I²C GENI normal» | Confirmado: `i2c@880000` (QUP1 SE0, 400 kHz) = i2c-6 de Android. En Linux **no existe** (`/dev/i2c-2,4,5`): `uke_scope_qup_buses` lo deja `disabled` | se enciende con el truco E7 del audio (C6) |
| «Motor de vibración: probablemente no» | Refuerzo: `dumpsys vibrator_manager` de Android lista **`Vibrators:` vacío** y todos los toques de `performHapticFeedback` salen `ignored_unsupported` (`varios-20261019/vibracion.txt`) | fase 2 al final (§7) |

Hallazgos nuevos que condicionan el diseño (todos [MEDIDO] salvo indicación):
- **`GCC_CAMERA_AHB_CLK` no está registrado en `gcc-cliffs`** (ID 10 = NULL; en Android es `measure_only`: AHB de cámara siempre activo). Un `<&gcc 10>` en el DT daría `-ENOENT`; `camcc-sm8650` solo usa `DT_IFACE` en el enum (0 usos como padre), así que el overlay rellena esa ranura.
- **No hay `rpmhpd` en la uke**: el kernel usa reguladores de nivel (`vdd_mx/vdd_mxc/vdd_mm`, ya en el nodo vendor de camcc; las tres rails ya están a nivel 384 por otros usuarios). El módulo camcc parcheado los vota (como `uke-dispcc-votes.c` hace con el dispcc).
- **Sin capa interconnect de cámara**: `qnoc-cliffs-usb` solo cubre USB/display; no hay `MASTER_CAMNOC_HF`. El camss parcheado usa **0 rutas ICC** (si no, `devm_of_icc_get` fallaría en el probe). Riesgo asociado en C5 (ancho de banda del NoC sin voto).
- **`apps-smmu` es `qcom,sm7675-boot-smmu`/`usb-smmu`** (SMMU de arranque con handoff); ya hay `cam_hf_qtb@14d2000` en el DT. Es el riesgo mayor de C5 (§6, R1).
- Los dispositivos vendor de cámara **no reservan MMIO** (`/proc/iomem` sin entradas `ac1…/ace…`): los nodos nuevos del overlay no colisionan.
- `gpio3` (reset del frontal) es `egpio` («func1 out low»): GPIO de propiedad especial; R5.
- `CONFIG_RESET_GPIO=m` (necesario para que `ov08d10` use `reset-gpios`), `CONFIG_OF_OVERLAY=y`, `CONFIG_I2C_QCOM_CCI=m`, `CONFIG_VIDEO_QCOM_CAMSS=m`, `CONFIG_SM_CAMCC_8650=m` ya activos; **no** están `VIDEO_OV13B10`, `VIDEO_OV08D10` ni ningún VCM → por eso van como módulos propios.

## 1. Mapa de cada cámara (desde el DT de Android + capturas)

Fuentes: DTA `qcom,cci0@ac15000/qcom,cam-sensor0`, `…/i2c@880000/qcom,cam-sensor1`, `qcom,csiphyN`, pinctrl y gpio-regulators; `build/android/varios-20261019/camaras-kernel.txt` (probe); `sensormodule.bin` de `odm-camera.tar` (fuera de git; solo se leyeron resolución y registro de id).

| | **Trasera «wide»** (cámara 0) | **Frontal** (cámara 1) |
|---|---|---|
| Sensor / módulo | OV13B10, Ofilm `o82_ofilm_ov13b10_wide_i`, 13 MP, **4208×3120** | OV08D10, AAC `o82_aac_ov08d10_front_i`, 8 MP, **3264×2448** |
| Bus de control | **CCI0 (`ac15000`) master 1**; pines **gpio72 SDA / gpio73 SCL** (`uke_cci_i2c_*`); IRQ SPI 426. CCI1 (`ac16000`) sin hijos | **I²C GENI `i2c@880000`** (QUP1 SE0 = i2c-6), 400 kHz, `uke_qupv3_se8_*`, IRQ SPI 373. **No usa CCI** |
| Dirección | `0x20` (8 bit) = **`0x10`** (7 bit) | `0x20` = **`0x10`** |
| Chip-id (Android) | `0x0d42` en reg `0x300b` (mainline: `0x560d42` en `0x300a`, 24 bit) → coincide | `0x5647` (mainline espera `0x5608` en regs `0x00/0x01`, máscara `0xfff0`) → **no coincide, se lee en C6** |
| CSIPHY | **csiphy1** `ace6000` (SPI 478, `v2.2.1`) | **csiphy4** `acec000` (SPI 122, `v2.2.1`) |
| Lanes | **4** [INFERIDO: 4208×3120 a 10 bit; el XML de lanes de Android no está cosechado] | **2** (el sensor solo tiene 2; el driver solo admite 2) |
| Lane map del PHY | por defecto `1 2 3 4` [INFERIDO; el vendor tiene `laneAssign` en el XML] | `1 2` |
| MCLK | **MCLK0 gpio64** `cam_mclk` (4 mA), 19,2 MHz (`0x124f800`); camcc vendor `0x69` → mainline `CAM_CC_MCLK0_CLK`=96 | **MCLK4 gpio68** `cam_aon_mclk4` (2 mA), 19,2 MHz, `use-shared-clk`; vendor `0x71` → `CAM_CC_MCLK4_CLK`=104 |
| Reset / pwdn | **gpio14** (`cam_sensor_wide_*_rst`, función gpio, activo-bajo en el sensor) | **gpio3** (`cam_sensor_front_*_rst`, `qcom,apps`/`qcom,remote`; `egpio`) |
| Rieles | `vana`=`camera_wide_avdd_ldo` (regulator-fixed, **gpio79**, 2,8 V, 100 µs de rampa, 102 mA) → avdd; `vio`=`pmxr2230_l20` 1,8 V (106 mA) → dovdd; `vdig`=`pmr735a_l6` 1,2 V (129 mA) → dvdd; `custom1`=`pmxr2230_s2` 1,256 V (454 mA; ya encendido por otros); `bob`=`pmxr2230_bob1` 3,3 V (padre; display ya lo usa); `vaf`=`pmxr2230_l14` 2,8 V (150 mA, solo VCM) | `vana`=`camera_front_avdd_ldo` (**gpio160**, 2,8 V) → avdd; `vio`=`pmxr2230_l20` → dovdd; `vdig`=**`pm_v6c_l3`** 1,2 V → dvdd; `custom1`=`pmxr2230_s2`; `bob` |
| Actuador (AF) | **CN3927V** (`com.qti.actuator.o82_ofilm_ov13b10_cn3927v_wide_i_actuator.so`), CCI0 master 1, riel `l14`. **Dirección I²C no cosechada**; sin driver mainline identificado (búsqueda web 19-oct sin resultados) | sin actuador (foco fijo) |
| EEPROM | **BL24SA64** (`…bl24sa64…eeprom.so`), CCI0 master 1; dirección no cosechada [INFERIDO típica 0x50] | **GT24P64E** en **0x51** del i2c-6 (`6-0051`) |
| Orientación (Android) | `Facing: Back`, `Orientation 90`; roll vendor `0x5a`, yaw `0xb4` | `sensor-position-roll 0x10e` = 270 |
| Flash | `qcom,camera-flash0`: `flash_led@ee00` en `pmxr2230@1` (`flash_0/flash_3`, `torch_0/3`, `led_switch_2`) | — |

Otros bloques del DT que **no** se usan (ISP propietario): `cam-cpas`, `icp` (+firmware), `ipe0`, `bps`, `jpeg*`, `cre`, `rt-cdm0-4`, `sfe0/1`, `tpg13-15`, `ife-lite`, `csid-lite`. Mainline ofrece solo captura RAW por CSID/VFE; el procesado lo hace libcamera (soft-ISP). Lens: apertura 2,2, focal 3,79 mm (trasera).

## 2. Estado en mainline y linux-next (medido por web el 19-oct-2026; caduca el 2-nov-2026)

| Pieza | Estado | Fuente (fecha) |
|---|---|---|
| CAMSS sm8550 / sm8650 | Compat y recursos en el árbol 7.2.9 (`camss.c: sm8550_resources`, `sm8650_resources`); nodos `camss` en `sm8550.dtsi` y `sm8650.dtsi` [MEDIDO en KT]. DT de sm8550 aplicado por Bjorn en jul-2025 | [lkml 2507.0/05628](https://lkml.iu.edu/hypermail/linux/kernel/2507.0/05628.html) (jul-2025) |
| CAMSS sm8750 | Serie en revisión, **v6 del 21-jul-2026**, depende de series sin fusionar (Kaanapali, CAMCC Maili/Hawi); no es nuestro SoC | [lkml 2607.2/10269](https://lkml.iu.edu/2607.2/10269.html) (21-jul-2026) |
| CAMCC | `camcc-sm8550/sm8650/milos/sm8750/kaanapali` en 7.2.9 [MEDIDO]. SM7635 (Milos) por Luca Weiss, jun-2025. **No existe `camcc-cliffs`/sm7675 en mainline ni en listas** (búsqueda 19-oct sin resultados); la única fuente cliffs es la OEM (MiCode `uke-v-oss`, última actualización 9-ene-2025) | [lkml 2506.3/07254](https://lkml.iu.edu/hypermail/linux/kernel/2506.3/07254.html) (jun-2025); [MiCode branches](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/branches/all?query=uke) (consultado 19-oct) |
| CCI | `i2c-qcom-cci.c` con `qcom,msm8996-cci`/`sm8450-cci` (v2); sm8650.dtsi usa `"qcom,sm8650-cci","qcom,msm8996-cci"` [MEDIDO] | KT |
| **OV13B10** | Driver con `dvdd/dovdd/reset/sensor_clk` ya en 7.2.9, **pero sin `of_match_table`** [MEDIDO]. Serie de Antoine Bernard (DT + binding, Xiaomi Pad 6): v1 20-mar-2026, v2 21-mar-2026; **estado de fusión no confirmado** | [lkml 2603.2/10505](https://lkml.iu.edu/hypermail/linux/kernel/2603.2/10505.html), [binding v2 2603.2/12424](https://lkml.iu.edu/2603.2/12424.html) (mar-2026) |
| **OV08D10** | En 7.2.9 ya hay **binding yaml, `of_match`, `reset-gpios`, regulators dovdd/avdd/dvdd, reloj 19,2/24 MHz** [MEDIDO]. Serie de Matthias Fend: v1 feb-2026, v3 mar-2026, fixups jun-2026. El driver espera chip-id `0x5608` | [lkml 2602.3/04698](https://lkml.iu.edu/2602.3/04698.html), [v3 8/9 2603.3/00753](https://lkml.iu.edu/2603.3/00753.html), [fixups 2606.2/04602](https://lkml.rescloud.iu.edu/2606.2/04602.html) |
| VCM CN3927V | **Sin driver ni compatible conocido** (búsqueda 19-oct: nada). Hermanos mainline: `dw9714/dw9719/dw9768/dw9807` (todos `# not set` en ouke4) | web 19-oct-2026 |
| libcamera | Soft-ISP + soft-IPA en el pipeline `simple`, **habilitado solo para `qcom-camss`** (probado en X13s); RFC de pipeline `camss` nuevo abril-2026 («New»). Existe libcamera **v0.7.2** (docs). Helpers de sensor para OV13B10/OV08D10 **no confirmados** | [patch 19882](https://patchwork.libcamera.org/patch/19882/) (2024), [RFC 26512](https://patchwork.libcamera.org/patch/26512/) (abr-2026), [docs v0.7.2](https://docs.libcamera.org/master/internal-api/classlibcamera_1_1ipa_1_1CameraSensorHelperFactoryBase.html) |

## 3. Vía mínima a la primera imagen

`OV13B10 ──(CCI0 m1: gpio72/73)── camcc(MCLK0, CCI0, titan_top GDSC) ; OV13B10 ══MIPI D-PHY 4 lanes══ csiphy1 → csid → vfe RDI0 → /dev/videoN (RAW10 4208×3120)`
- Datos de control: `i2c-qcom-cci` (ya `=m`) con `compatible "qcom,sm8650-cci","qcom,msm8996-cci"` + nodo `i2c-bus@1`.
- Reloj/energía: `camcc-cliffs-uke.ko` = copia de `camcc-sm8650.c` con **3 cambios** verificables (`gen-modules.py` exige cada edición exactamente una vez): `compatible "qcom,cliffs-camcc"`, quitar `cam_cc_pll10` de la lista (la uke tiene PLL0..9), y votar `vdd_mx/vdd_mxc/vdd_mm` en el probe (parámetro `vote_level`, 128 = SVS).
- Sensor: `uke_ov13b10.ko` = el driver del árbol + `of_match_table "ovti,ov13b10"` + un `dev_info` con el chip-id leído (el probe **enciende y lee el id**: cargar el módulo = hito 1).
- Captura: `uke-camss.ko` = `qcom-camss` del árbol con una entrada `qcom,cliffs-camss` (recursos sm8650, `csiphy_num=5`, 0 rutas ICC) y driver renombrado para no chocar con el `qcom-camss` de serie. RDI (CSID → VFE) en RAW; sin ISP propietario.
- Userspace: `media-ctl` + `v4l2-ctl --stream-mmap` (C5), después libcamera `simple` con soft-ISP (C7).
- **Cero parches al árbol compartido salvo el de C3** (que no está aplicado: `CAM/patches/0045-uke-rpmh-camera-rails.patch`, dry-run OK contra KT).

## 4. Etapas

Convenciones: «Autorización» = qué exige docs/historia/AGENTS.md. Toda carga de módulo/overlay y todo flash exigen **orden expresa del dueño en esa etapa**; el flash, además, fila pre-registrada en `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`, sha y fastboot a mano. Cada etapa: `dmesg -n 7` antes, **doble captura** (consola ACM + `ssh … dmesg -w > fichero`), un solo lector de ACM, y `sync` antes de cualquier reinicio. **Nunca** instrumentar SMMU ni volcar MMIO/regmap (se evita incluso `…/regmap` de debugfs de camcc). Techo de 3 ciclos por hipótesis.

| Etapa | Qué | Criterio de «hecho» | Riesgo | Autorización |
|---|---|---|---|---|
| **C0** PC | Plan, mapa, overlays, módulos, build, gates | **HECHO 19-oct.** `CAM/build.sh` = `RESULTADO: OK`: 4 `.dtbo` sin avisos; `fdtoverlay` sobre BASE con las 4 etapas y con cada prefijo; `check-cam.py` 37 comprobaciones OK; 8 `.ko` con vermagic ouke4, 0 avisos de compilación; `MANIFEST.sha256` | nulo | ninguna |
| **C1** tablet, solo lectura | Línea base | **HECHO 19-oct 17:17** (`out/c1-baseline-20261019-1717.txt`): sin iomem de cámara, sin driver en `ldob20/ldoe6/ldoc3/ldob14/bobb1`, pines 14/64/68/72/73 sin dueño, rieles `s2/l2/l4` y niveles `mx/mxc/mmcx` ya a nivel 384, batería 96 % | nulo | ssh de lectura (permitido) |
| **C2** relojes en caliente — **HECHO 19-oct (autorizado por el dueño), PASA; ver `docs/historia/revision/CAMARAS-C2-20261019.md`** | `push C2` + `insmod uke_cam_camcc.ko` (overlay) + `insmod camcc-cliffs-uke.ko` | probe sin errores; `clk_summary` muestra `cam_cc_*` con **los mismos nombres y rates de reposo que Android** (`xo 19,2 MHz`, PLLs apagados, `slow_ahb`…); `pm_genpd_summary` lista `cam_cc_titan_top_gdsc` **off**; 60 s sin cuelgue; `rmmod` en orden inverso y recarga ×2 limpias | **medio-bajo**: el probe escribe la config de las 10 PLL y enciende 4 cbcr críticos; un cuelgue exigiría reset físico (watchdog R-42). Sin SMMU | **orden del dueño** (carga de overlay y módulo). **Lista para autorizar** |
| **C3** rieles (kernel) — **HECHA 19-oct ~23:05 (ledger #668, orden del dueño «flashea»): ouke5 arranca, `boot_a` releído == `f3d3bc82…`, los 3 rieles presentes y deshabilitados; ver `CAMARAS-C3-20261019.md`.** Antes — PREPARADA (sin flashear): ouke5 construido, boot v5 `f3d3bc82…`, script `flash-senemos-v5-gated.sh` (solo `--check`) y fila de ledger lista; ver `CAMARAS-C3-20261019.md` y `docs/historia/revision/CAMARAS-C3-LEDGER-FILA-20261019.md`** | Parche 0045 (allowlist `ldob20`,`ldoe6`,`ldoc3`) → build ouke5 → flash | tras el arranque aparecen `pmxr2230_l20`, `pmr735a_l6`, `pm_v6c_l3` en `/sys/class/regulator` **deshabilitados** con 1,8/1,2/1,2 V; sin cambios en el resto de rieles ni en pantalla/WiFi/BT/audio; `verify` 19/19 | **medio** (flash): el kernel ouke4 sigue como red (slot a/b); el probe de un LDO no lo enciende | **dueño + fila en el ledger + fastboot a mano**; presupuesto de operación completo (≥3700 mV, ≤2 escrituras/día, consola armada). **Coordinar con audio**: mismo árbol, otros parches (aviso enviado a `local_11cb289d…`) |
| **C4** CCI + sensor trasero (**hito 1**) — **HECHO 20-oct ~12:25 (autorizado): `ov13b10 7-0010: chip id 0x560d42` leído por CCI0, 3 cargas seguidas; ver `docs/historia/revision/CAMARAS-C4-20261019.md` (ungate de gcc, `i2c-bus@0`, reset por pinctrl por gpiolib-shared, tensiones DOVDD/DVDD). Historial:** INTENTO 1 (19-oct 23:05, autorizado): NO PASA, se para en el GDSC `cam_cc_titan_top` «stuck at off» al probar `i2c-qcom-cci`; H1 (voter MMCX) refutada; sin llegar a encender el sensor; **C4-bis (solo lectura): causa = `gcc_camera_ahb_clk` y los dos `camera_*_xo` de GCC apagados (`0x80000000`); **C4-ter (autorizado, ejecutado 23:25): con `ungate=1` camcc responde (PLL0 1,2 GHz, GDSC sube); el CCI colgó la tablet por faltar `i2c-bus@0` en el overlay (corregido en PC); tablet pendiente de reinicio duro**; ver `docs/historia/revision/CAMARAS-C4-20261019.md`** | `push C4` + `uke_cam_rear.ko` + `uke_ov13b10.ko` (**el driver parcheado fija DOVDD 1,8 V y DVDD 1,2 V**: `l20` arranca a 1,62 V, medido en C3) | `dmesg`: `uke: chip id 0x560d42 leído por I2C` y `i2c-N` del CCI en `i2cdetect -l`; rieles vuelven a apagarse tras el probe; 3 ciclos de carga/descarga con el mismo id | **medio**: primer encendido real del sensor (avdd/dvdd/dovdd por separado; orden = el del driver: clk, regulators, reset) | orden del dueño; **exige C3** y C2 cargado |
| **C5** CAMSS + frame RAW (**hito 2**) — **C5a HECHO 20-oct** (CAMSS enlaza, grafo completo con `ov13b10→csiphy1`); **C5b BLOQUEADO por el SMMU: el driver rechaza el SID del IFE (`0x200800`, además con ACTLR `0x1` en el DT) → exige parche de kernel ouke6; parche **0046 revisado (`docs/historia/revision/CAMARAS-SMMU-0046-REVISION-20261020.md`) y CONSTRUIDO como boot v6 `a9641556…` (ouke5+0046, misma release, sin módulos que recompilar; NO flasheado; fila de ledger y script `flash-senemos-v6-gated.sh` listos: `docs/historia/revision/CAMARAS-C5-LEDGER-FILA-20261020.md`)**; ver `docs/historia/revision/CAMARAS-C5-20261020.md`** | `push C5` + `uke_cam_camss.ko` + `uke-camss.ko`; `media-ctl -d /dev/media0 -p`; `v4l2-ctl --stream-mmap --stream-count=1 --stream-to=f.raw` | topología `ov13b10 → csiphy1 → csid → vfe0 rdi0`; `CSIPHY 3PH HW Version` leída en el log; **un frame RAW10 4208×3120 con tamaño exacto** (`4208×3120×10/8` con stride de VFE), 0 `Unhandled context fault` en `dmesg` | **ALTO**: SMMU (R1), NoC sin votos ICC (R2), registros del PHY por revisión de silicio (R3), lane map (R4) | orden del dueño; **con cargador de pared**; el primer intento con `stream-count=1` y timeout; si aparece un fault de SMMU, parar (no instrumentar) |
| **C6** frontal | `push C6`; encender `i2c@880000`; `uke_ov08d10.ko uke_chip_id=…` | leer los regs `0x00/0x01` y fijar el id real (0x5608 o 0x5647); frame RAW 3264×2448 por csiphy4; reset por `gpio3` (R5) | medio (R5, `egpio`) | orden del dueño |
| **C7** libcamera | `libcamera` (pipeline `simple`, soft-ISP) en la tablet; `cam -l`, `cam -c1 --capture=1 -F` | imagen JPEG/PNG visible de la trasera; sin tuning ni helper: calidad modesta, AE/AWB por soft-IPA; documentar si hace falta un `camera_sensor_helper` | bajo (solo userspace) | instalación de paquetes = orden del dueño |
| **C8** extras | Linterna (`leds-qcom-flash`, `flash_led@ee00`: independiente del pipeline), EEPROM (solo calibración), AF CN3927V (necesita dirección I²C del `sensormodule.bin`/XML y un driver nuevo o `dw9714` parcheado) | linterna enciende/apaga con corriente acotada; el resto opcional | bajo-medio (corriente máx. del LED) | orden del dueño |

### Detalle operativo de C2 (la primera etapa a autorizar)

Orden de carga en la tablet (nada persiste tras reiniciar; descarga en orden inverso):
```bash
build/rootfs/deploy/camaras/deploy.sh --go --push C2        # copia a /root/uke-cam (ext4) y compara sha256; NO carga
ssh … 'dmesg -n 7; insmod /root/uke-cam/uke_cam_camcc.ko'   # overlay: reescribe clocks y #power-domain-cells del nodo vendor
ssh … 'insmod /root/uke-cam/camcc-cliffs-uke.ko'            # probe: votos vdd_*, PLL config, GDSC, 100+ relojes
ssh … 'grep cam_cc_ /sys/kernel/debug/clk/clk_summary | head -40; grep titan /sys/kernel/debug/pm_genpd/pm_genpd_summary'
ssh … 'rmmod camcc-cliffs-uke; rmmod uke_cam_camcc'
```
Criterio de abortar: cualquier `rcu stall`, `Unhandled`, pérdida del ssh > 30 s, o `dmesg` con `qcom_cc` en error. Un solo cambio por ciclo: C2 no incluye CCI ni sensor.

### Borrador de fila de ledger para C3 (el flash lo pre-registra la sesión gestora)
`#NNN | ouke5 = ouke4 + 0045-uke-rpmh-camera-rails | boot_X sha256 <de out/boot…> | par dtbo vigente | gates: mV ≥3700, retry a/b, consola ACM + vigía | objetivo: 3 rieles de cámara visibles y apagados | revertir: slot anterior (ouke4)`.

## 5. Material preparado (C0) — `CAM/`

| Fichero | Para |
|---|---|
| `dts/uke-cam-{camcc,rear,camss,front}.dtso` | 4 overlays **independientes y apilables** (cada uno reescribe en sitio nodos vendor y añade los suyos; se retiran en orden inverso). Phandles sin etiqueta salen de `out/uke-cam-ph.h` (generado de BASE por `build.sh`) |
| `module/uke_cam_*.c`, `Kbuild` | cargadores (reutilizan `uke-ovl.h` del BT) |
| `patches/gen-modules.py` | genera de KT, **solo lectura**, `camcc-cliffs-uke.c`, `uke_ov13b10.c`, `uke_ov08d10.c` y el `camss` parcheado; cada edición se exige 1 vez |
| `patches/0045-uke-rpmh-camera-rails.patch` | parche de kernel de C3 (sin aplicar) |
| `check-cam.py`, `build.sh`, `deploy.sh`, `c1-baseline.sh`, `dt-dump.py` | verificación en PC, build reproducible, push seguro, línea base, volcado de nodos del DT de Android |
| `out/` | `.dtbo`, `merged.dtb`, `.ko`, `check-cam.txt`, `c1-baseline-*.txt`; `MANIFEST.sha256` |

Binarios (`out/*.ko`, `*.dtbo`) y `odm-camera.tar` **no deben subirse a git** (los `.ko`/`.dtbo` son artefactos reproducibles; el `tar` es del fabricante y ya está en `.gitignore`). No se ha reproducido ningún contenido del fabricante: del `sensormodule.bin` solo se leyeron dos resoluciones y un registro de id.

## 6. Riesgos e hipótesis abiertas

| # | Riesgo / hipótesis | Etapa | Cómo se cierra |
|---|---|---|---|
| R1 | SMMU: `apps-smmu` es boot/usb con handoff; el SID `0x800` del IFE pasa por dominio nuevo. El audio ya vio `Unhandled context fault` con SIDs heredados | C5 | `iommus` como el GPU; un intento corto; **sin instrumentar**; si hay fault, parar y registrar |
| R2 | Sin votos ICC de CAMNOC: el NoC puede quedar a ancho de banda mínimo → underrun o hang del VFE | C5 | frame de prueba pequeño (modo binning 2104×1560 antes del 4208×3120); si cuelga, parche de ICC (L) |
| R3 | CSIPHY `v2.2.1(-n16t)` de cliffs vs `lane_regs_sm8650` | C5 | el log `CSIPHY 3PH HW Version` y errores de CSID; **hipótesis refutable**: si no hay datos tras 3 ciclos, anotarla como refutada |
| R4 | Lane map y nº de lanes de la trasera no cosechados | C5 | probar `1 2 3 4`; XML de Android (`/vendor/etc/camera` o el bin) si falla |
| R5 | `gpio3` es `egpio` (apps/remote) | C6 | leer su estado/función con debugfs antes de pedir el GPIO |
| R6 | `camcc-sm8650` escribe config de PLL de sm8650; las PLL de cliffs pueden tener otro `alpha/l` | C2 | las PLL arrancan apagadas; se compara `clk_summary` con Android; los valores OEM leídos por WebFetch (resumen de un modelo pequeño) **no se han verificado línea a línea** |
| R7 | Voto fijo `vdd_mm/mxc/mx` = nivel 128; los CSIPHY piden 400 MHz | C2/C5 | subir `vote_level` a 192/256 si el PHY no engancha |
| R8 | `uke_scope_qup_buses` y otras reescrituras de `uke-abl.c` pueden cambiar con ouke5 | C3 | `check-cam.py` contra el BASE del nuevo kernel antes de cada etapa |
| R9 | Rieles `l20/l6e/c3` con `qcom,init-mode`/`init-voltage` del DT: el probe podría votar | C3 | gate de C3: los tres salen `disabled`; el resto no cambia |
| R10 | `bobb1` queda fuera: si el sensor necesitase bob como padre del `vaf` (autofocus), habrá que admitirlo con cuidado (el display ya cuelga de él) | C8 | solo con AF |

## 7. Fase 2 — vibración (después de cámaras)

- **Evidencia del 19-oct para «sin motor»** [MEDIDO, `varios-20261019/`]: `dumpsys vibrator_manager`: `Vibrators:` vacío; todos los `performHapticFeedback` registrados salen `ignored_unsupported`; `ro.odm.mm.vibrator.motor_not_support=true`; `servicemanager` no encuentra `android.hardware.vibrator.IVibrator`; los módulos `aw8697/si_haptic/qcom_hv_haptics` no enlazan ningún dispositivo. El único rastro es el bloque LDO `qcom,vibrator@df00` en `pm7550ba` (mainline: `pm8xxx-vibrator`, `qcom,pmi632-vib`, `=m` en ouke4).
- **Paso 1 pendiente (decisión del dueño):** «¿la Xiaomi Pad 7 vibra en Android (por ejemplo al tocar el teclado o en una alarma)?». Si **no vibra** → cierre «**sin motor**» (sin trabajo de kernel).
- **Si vibra:** el actuador estaría en el LDO del PMIC; propuesta: overlay que cambie `compatible` de `qcom,vibrator@df00` a `qcom,pmi632-vib` + `modprobe pm8xxx-vibrator` → `/dev/input/eventN` con `FF_RUMBLE` (se prueba con `fftest`); el driver solo escribe `0x40/0x41/0x46` y acota a 3,5 V (el vendor pide 3,0 V). Hipótesis a verificar: que `qpnp-vibrator-ldo` use el mismo mapa de registros (módulo vendor no cosechado). No se trabajará `swr_haptics` (necesita LPASS/audio y no hay driver mainline).

## 8. Qué necesita decisión del dueño

1. **Autorizar C2** (carga en caliente de overlay + módulo camcc; sin flash; riesgo medio-bajo, un reset físico como peor caso).
2. **Kernel ouke5 (C3)**: ¿aprovechar el próximo build/flash de audio o ciclo aparte? **Respuesta de audio (19-oct):** no tiene ouke5 previsto ni parches pendientes, así que ouke5 sería solo nuestro. Coste de un ouke5: hay que recompilar y reinstalar los módulos de audio (vermagic ouke4; `build-module.sh`, `q6apm-port/build.sh` y `deploy-amps.sh` con `KREL` nuevo) y actualizar los gates de `uke-audio-up.sh` y `uke-audio-amps-up.sh`, que rechazan cualquier kernel que no sea `*ouke4*`; sin eso no habría audio tras el flash. Los módulos de BT y los de cámara también llevan vermagic ouke4. Avisar a audio cuando el dueño apruebe ouke5.
3. **Pregunta de la fase 2**: ¿vibra la Pad 7 en Android?
4. Para C5: cargador de pared y un momento sin otras sesiones usando la tablet.

## 9. Caducidad y lagunas
Medido el 19-oct-2026; las líneas de §2 (estado de mainline y libcamera) pasan a **caducado el 2-nov-2026**. Lagunas: lanes y lane map de la trasera; dirección I²C del CN3927V y de la EEPROM trasera; chip-id real del OV08D10 (se lee en C6); valores OEM de PLL de cliffs (solo offsets contrastados, y vía un resumen de WebFetch); estado de fusión de las series OV13B10/OV08D10 tras mar/jun-2026; helpers de libcamera.


---
## Adenda 20-oct (captura de Android con la trasera abierta): `docs/historia/revision/CAMARAS-ANDROID-20261020.md`
- **R4 cerrado:** 4 lanes D-PHY, `lane_assign 0x3210` (identidad), 1120 Mbps/lane (`CAM_START_PHYDEV`); trasera = CSIPHY1 → CSID2 → IFE2.
- Votos ICC de Android con la preview: CAMNOC HF ≈ 1,08 GB/s, IFE2 ≈ 0,74 GB/s (S2); en Android `cphy_rx` va a 19,2 MHz y el timer a 400 MHz (a vigilar si el PHY no engancha).
- **Fase 2 (vibración): cierre «SIN MOTOR»** con evidencia directa de Android (`cmd vibrator_manager list` = «No vibrator found», sin feature ni nodos sysfs). Sin trabajo de driver.

## Adenda 20-oct ~23:37 — kernel v6 FLASHEADO (ledger #674): PASA
Boot v6 `a9641556…` en `boot_a` (releído al tamaño exacto), banner `#6`, misma release ouke5 (módulos intactos), sin faults de SMMU, rieles de cámara presentes y deshabilitados, servicios activos. **Siguiente: C5b** (frame RAW con `uke-cam-camss` compilado con `CPPX=-DWITH_IOMMU`; plan de prueba en `docs/historia/revision/CAMARAS-SMMU-0046-REVISION-20261020.md` §6) — necesita tu orden, batería ≥ 30 % (hoy 64 %), un solo lector ACM y `dmesg -w` a fichero; empujar antes los `.ko` desde `out-ouke5/` con comprobación de sha (los de `/root/uke-cam` pueden ser antiguos tras la restauración).

## Adenda 20-oct ~23:45 — C5b: el SMMU ya no bloquea (v6 + overlay `-DWITH_IOMMU`), pero NO llega ni un frame
IOVAs traducidas (`0xffc00000…`), cero faults de SMMU, sensor transmitiendo (`mode_select=1`), VFE 3.2.1 / CSID 3.0.4 accesibles; **0 interrupciones de CSIPHY1/VFE y 0 bytes**: no llegan datos CSI-2 al CSID (PHY version = 0). Hipótesis abiertas H-PHY1/2/3 en `docs/historia/revision/CAMARAS-C5-20261020.md` (primer ciclo propuesto: csiphy a 19,2 MHz como Android). Sensor con `power-domains` y formato `pgAA` ya resueltos.

## Adenda 20-oct ~23:50 — C5b ciclo 2: H-PHY2 (cphy_rx a 19,2 MHz) REFUTADA
Igual que Android en reloj, mismo resultado (0 bytes, 0 IRQ de PHY/VFE, PHY version = 0, 0 faults). Quedan H-PHY1/H-PHY3 (registros/settle del PHY cliffs): exigen loguear lo que camss programa y compararlo con Android; ver `docs/historia/revision/CAMARAS-C5-20261020.md`. **Estado final de la fase 1:** hito 1 (chip-id por CCI) ✔; CAMSS enlazado ✔; SMMU del IFE ✔ (parche 0046, v6 flasheada); frame RAW ✘ (bloqueado en el PHY). Fase 2 (vibración): cerrada «sin motor».

## Adenda 20-oct ~23:55 — C5b ciclo 3: bug de lanes en el overlay corregido, PHY accesible, aún 0 bytes
`data-lanes` debe numerarse desde 0 (`<0 1 2 3>`): con `<1 2 3 4>` el PHY tenía `CTRL5=0xd4`; ahora `0xd5` = Android. Los registros del PHY responden (H-PHY1 descartada). Siguen sin llegar datos: H-SET (settle), H-LREG, H-CSID, H-SENS, H-RDI (ver `docs/historia/revision/CAMARAS-C5-20261020.md`).

## Adenda 20-oct ~23:58 — C5b ciclo 4: H-SET y H-CSID(config) refutadas
Settle 12/20/40/55 → 0 bytes; CSID bien configurado (`rx_cfg0=0x232103`, RAW10, START) pero todos los estados a 0. Siguiente más informativo: habilitar el IRQ del RX del CSID (H-RXIRQ). Detalle en `docs/historia/revision/CAMARAS-C5-20261020.md`.

## Adenda 21-oct — ciclo 5 PREPARADO (sin ejecutar): `docs/historia/revision/CAMARAS-C5-CICLO5-PLAN-20261021.md`
Módulos `out-rxirq/`, script `c5-ciclo5.sh` (`--check` OK) y criterios de lectura para el IRQ del RX/RDI del CSID + patrón de test del sensor. Espera: «libre» de audio + orden del dueño.

## Adenda 21-oct 01:45 — ciclo 5 ejecutado: el CSID RX ve actividad de las 4 lanes (`RX_IRQ=0x100f`, tormenta ≈25 kHz), pero 0 bytes y B quedó ciego
Ver `docs/historia/revision/CAMARAS-C5-20261020.md` (final). Siguiente: ciclo 6 = máscara `0xfffffff0` + presupuesto por prueba, B primero.
