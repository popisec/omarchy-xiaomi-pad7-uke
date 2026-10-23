# ANDROID stock y su GPU viva — recopilación (10-oct-2026)

Solo lectura, tablet intacta. Síntesis de tres barridos paralelos sobre
`omarchy-uke` + `ubuntu-permanente/docs`. Lo vigente manda: ledger #553–#580,
ESTADO-VIVO 10-oct (#580: release muere 6/6 en puntos distintos).

## 1. Qué deja ABL/XBL al arrancar

- Cadena: XBL (`xbl_a/b` en sdb1/sdc1) → ABL (`abl_a`=sde8, `abl_b`=sde36, 8 MiB
  **intocable**, UEFI Qualcomm) → lee `misc` sda12 (BCB `reboot-bootloader`;
  limpiar con 8192 B de ceros) → attrs de slot en GPT → `boot_b` + concatena
  `vendor_boot_b` (sde49) stock. (`docs/informes/B-arranque-arch-uke.md §4`)
- 22 comandos `oem` leídos del `abl.elf` descomprimido: `off-mode-charge`,
  `enable/disable-charger-screen`, `poweroff`, `edl`, `allow-wipe-userdata`,
  `device-info`, `fbreason`, `getguid`, `hwid`, `ramdump`, `lkmsg`, `lpmsg`,
  `uefilog`, `dm-verity-enforcing`, `uart-enable`, `set-hw-fence-value`,
  `set-gpu-preemption`… **NO** hay `charge/powerdown/soc/current`.
  `oem poweroff` es diferido ("Will power off after USB out", handler 0xab85c).
  (FLASH-LEDGER #230-nota-técnica)
- Slots: `unlocked=yes`; a los ~7 intentos el ABL cae a fastboot; `set_active a`
  + `set_active b` resetea a 7; `qbootctl -m` marca success. Tras #384/#385
  `vendor_boot_a/init_boot_a/super` quedaron en ceros (solo `boot_a/dtbo_a`
  reescritos #406/#409).
- Splash/memmap: misma base `0xE3940000` con tres tamaños: vendor splash 43 MB
  (`0x2B00000`, s260 frag@89) / rdump 20 MB (`0x1400000`, frag@88) / nuestro
  `memmap=0x1A12800` 26 MB → **17 MB de framebuffer del ABL desprotegidos**.
  Acción abierta: probar `memmap=0x2B00000$0xE3940000`. (R8 §2, §6.3)

## 2. Cmdline: qué es imagen y qué compone el ABL en vivo

- Stock viva (`build/evidencia/android-full/extracted-full/00-meta/cmdline.txt`,
  1623 B): `console=ttynull … kpti=0 … swiotlb=noforce … disable_dma32=on …
  kernel.panic_on_rcu_stall=1 fw_devlink.strict=1 … pci-msm-drv.pcie_sm_regs=…
  video=vfb:640x400… swinfo/mtdoops.fingerprint=… bootconfig bootinfo.pureason=…
  hwid.* msm_drm.dsi_display0=qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid:
  msm_drm.oled_wp=… rootwait ro init=/init … block2mtd…/mtdoops…`.
- `build/bootimg/cmdline-orig.txt` es la **nuestra** (Ubuntu: `mem=2048M
  rdinit=/ukeinit panic=10 memmap=… console=tty0 fbcon=map:0 …
  console=ttyGS0,115200 …`), no stock.
- Reparto medido (R8 §1): header `vendor_boot` v4 solo trae
  `video=vfb… + 2×fingerprint + bootconfig`; `chosen/bootargs` de los 4 DTB solo
  684 B; `bootconfig` solo 6 líneas `androidboot.*` (205 B, nada de display/GPU).
  **Toda la cola** (`bootinfo/hwid/msm_drm.dsi_display0/mtdoops/block2mtd`, y en
  lo nuestro `mem/rdinit/memmap/panic/console`) **la compone el ABL en vivo**.
- `video=DSI-1:d` = discriminador nuestro #P42: 0 ocurrencias en imágenes de
  fábrica (R8 §0.4). Nombre correcto del panel: **`o82_42_02_0b`** (con `02`,
  `:` final vacío), no `o82_42_0b` (R8 §6.2).
- **Trampa #409**: con el stack era-s209 (`boot s209-ubwc f6946f35…` + `dtbo s208
  27e8939a…`), `separate_gpu_kms=1` por cmdline no arrancó (2 intentos, 0 líneas
  de consola). En era s134 el mismo param SÍ arrancó (#282). **Cerrada en #569**:
  s250 arranca, probe G1→G9 + `Initialized msm`, card0+renderD128 → era del
  stack s209, no del param. (REVISTA-PROYECTO-HERMANO §1.2/#409; S250 §Riesgos;
  NOTAS-OMARCHY :2587)

## 3. DTBO: stock, s229, s250

- Stock: `vendor_boot` trae **4 DTB SKU** (offsets 0x0/0x74122/0xe801d/0x15a307),
  no panel. El de uke es **stock2 = Cliffs7P, msm-id 0x283 (643), Adreno732,
  9 pwrlevels 950…255 MHz, initial-pwrlevel 8** — coincide con `xiaomi-uke.dts`
  (`0x283 0x10000`). El panel vive en `dtbo` (sin backup); referencia de fábrica
  vía s260 (payload vendor, 1450 fragmentos): dual-DSI real, clockrate
  **1190788720**, 1600×2136/link, DSC 800×24, porches h-front 113/18/304 por fps,
  reset `<0 10 1 3 0 3 1 15>`, L8B 1,9 V + vsp/vsn 5,8 V. Base trae SSC on
  (`down-spread`); el vendor lo apaga (`ssc-disable` frag@103/104) — **nuestro
  OVL no documenta SSC: candidato a "todo bindea, pantalla negra"**. (R8 §§1–3, 7)
- GPU de fábrica (stock2, R8 §4; GPU-ANDROID-INV §d): `qcom,kgsl-3d0@3d00000`,
  `chipid 0x43030b00`, `status ok`; **GMU por SID 5** (`iommus = <0x1c1 5 0>`),
  tabla GMU **2 OPP 220/550 MHz**; zap-shader reservado `0x9899a000/0x2000`
  (`gpu_microcode_mem`, 8 KiB, no-map, sin `firmware-name`).
- **s229** (`s229-boot-dtbo-wifi-wpss.img`, `d2a29ea5…`, par bueno WiFi):
  arreglo de rieles s228 + `cx-supply` del WPSS a `pmxr2230_s3` (#424);
  display hermano (frag 86/98/1105) + endgame GPU frag@1450 (compatible
  adreno-43030b00, `iommus <0x1c1 0 0>`, `qcom,gmu <0x482>`, clocks vacíos).
- **s250** (`revision/S250-DTBO-GPU-SERIE.md`): payload `dtbo_b-actual.img`
  (593234 B) = frags 0–130 + 900–901 (s134 UFS); + 902–910: 902 kgsl-smmu
  palawan / 903 `cx_mem` / 904 gpucc palawan / 905 `delete iommus` / 906
  reg+rscc+7 clocks fork+cx/gx / 907 OPP GMU 2 por etiqueta / 908 endgame
  (9 OPP por etiqueta + `status okay`) / 909 `qcom,lamma` en raíz / 910
  `/chosen bootargs = "msm.separate_gpu_kms=1 <base 684 B verbatim>"` al
  principio (el overlay solo reemplaza, no extiende). Img `f0dc934d…`
  (598016 B); variante `--sin-cmdline` `78ea1760…`.

## 4. La GPU viva en Android: secuencia medida

Fuente primaria: `android-snap/extracted-r15/…/07-sys/dmesg-FULL.txt`
(boot completo); cruce `android-full/extracted-full/15-common/dmesg-full.txt`.
Detalle: `docs/historia/revision/GPU-ANDROID-INV-20261006.md §a`.

| t (s) | Evento |
|---|---|
| 0.236 | `Loading module gdsc-regulator.ko` |
| 0.484 | `Loading module gpucc-pineapple.ko` (+gcc_cliffs, pinctrl, clk_qcom…) |
| 2.344 | `gpu_cc-cliffs: Registered GPU CC clocks` (registrados, apagados) |
| 2.345 | `arm-smmu 3da0000.kgsl-smmu: probing…` SMMUv2 stage-1, 24 stream groups, **22 ctx banks**, 48-bit VA→36-bit IPA, `preserved 0 boot mappings` |
| 2.967–3.117 | `KGSL Init → KGSL Ready → GPU Init → GPU Ready`: **probe completo en ~150 ms, SIN firmware** |
| 2.982–3.020 | grupos IOMMU 17/18/19 (`gfx3d_user/secure`, `adreno-gen7-gmu`); binds `kgsl-3d→kgsl-iommu`, `:gfx3d_user`, `:gfx3d_secure`, `→3d68000.qcom,gmu (gen7_gmu_component_ops)` |
| 3.142 | `gpu_cc-cliffs sync-state` (rpmh drenado) |
| ~5.9–6.3 | **firmware al primer open de `/dev/kgsl-3d0`**: `gen71100_sqe.fw` (6.131, 2 ms → `/vendor/firmware/`) → `gen71100_gmu.bin` (6.162, 2 ms → `/vendor/firmware/`) → `gen71100_zap.mbn` (6.297, 20 ms → **`/odm/firmware/`**). Patrón por fw: 4 fallbacks `-13` + direct `-2` → ueventd resuelve. **No existe `qcom/uke/`** en el vendor |
| 6.15 / 8.688 | `starting service 'gpu'`; `vendor.gpu.available_frequencies=*` listo |

Orden interno (inferido upstream gen7 + sysfs, sin dmesg — el vendor va
silencioso en ACD/IFPC/GDSC): enable `gpu_cc_cx_gdsc` → GMU micro-kernel + HFI
→ ACD negociado con AOP vía QMP → GX GDSC bajo GMU → IFPC activo.

Estado post-arranque (FULL en carga / r1.5 idle): `Adreno732`, 9 OPs
950…255 MHz, `gpuclk` 255 idle / 950 en carga; governor **`msm-adreno-tz`**;
`default_pwrlevel=8`, `idle_timer=80`; **ACD=1, IFPC=1** (`ifpc_count=0x18DE`,
`hyst=5760`); `bus_split=1 hwcg=1 dms=1 gmu_ab=1 lm=0 clx=0`; BCL sin throttle.
Clocks Y en idle: `xo 19.2M`, `xo_div 4.8M`, `demet_div 19.2M`, **`cx_gmu 220M`
(de pll1 440M)`, `hub_src/hub_cx_int/hub_aon 200M`, `ddrss_axi`, debug_mux.
N: `ahb`, `hlos1_vote_smmu`, `memnoc`, `sleep`, `mnd1x_*`, `ff/cx_ff/cx_accu/cxo`,
`pll0`. **GX `gfx3d` no existe como clk SW** (solo `measure_only…`) — lo gobierna
el GMU. `gpucc-cliffs.c` (22 clks, GPL en `ubuntu-uke/vendor-src/cliffs/`):
`ftbl_ff {200M}`, `ftbl_gmu {19.2/220/550M}`. GDSCs: `cx_gdsc` + `gx_gdsc`
(GX count 1 = bajo GMU). IRQs: solo `GICv3 337 gmu` + `332 kgsl_3d0`
(DT SPI 304/305 y 300), contadores a 0 en captura.

## 5. Path del kernel Android para el release del GMU (fuente: RE del .ko + DT)

Driver: **`msm_kgsl.ko` techpack (gen7)**, no DRM/MSM. (INV-KGSL-RE-20261008 §1)

- Quién vota: la CPU solo pone `CX GDSC` + bulk de clocks; **GX lo vota el fw
  GMU una vez vivo** (`regulator_summary`: `cx_gdsc` 3 votantes
  gmu/kgsl-iommu/smmu; `gx_gdsc` count 1 = `gmu-vdd`). (INV-GMU-ESTADO §§1–2)
- Orden vendor (`gen7_gmu_boot`, INV-KGSL §§1/3/4/5/7): `pwrctrl_request_state
  (0x20)` → `enable_cx_gdsc` → `enable_clks bulk` → `ahb_timeout+cx_timer` →
  `rscc_wakeup (0x02003B07←2 / poll ACK / ←0, ≤100 ms)` → `load_fw
  (ITCM 0x1b400 / DTCM 0x1c400, dsb)` → **`register_config` 17 writes** →
  `irq_enable` → **`SYSRESET=0` único** → `poll FW_INIT_RESULT&0x1ff==0x100` →
  `hfi_start` después.
- `register_config`: `0x1f8f0/f1=1` primero, `INIT_RESULT=0`, `BOOT_CONFIG=2`,
  `0x1f984/5`, `FENCE_R0 0x3b11←0x80c808a0`, `CM3_CFG=0x4052`, `base+0←0x3c45`,
  `0x1f9cd-d0=rt`, `SYS_BUS/ICACHE/DCACHE=1`, opt `0x1f841`. **Sin `SYSRESET=1`,
  cero lecturas entre cfg y rst0.** (INV-KGSL §§4/8)
- **Primer voto GX es post-HFI, no pre-reset**: `beginVoteGxOn` CM3
  `0x10e78..0xec0` → `(0,3)` + `[0x100658]←3` + `(0,5)` vía leaf
  `0x1ab4→0x1eb4`; `GmuPwrGxBwVote/RequestPowerOn/QueryGx` por dispatch runtime.
  (BARRIDO-W2-RE-VOTOGX §§2a/2b/2d/2e/4)
- Primer voto RSCC: `EnableIsense 0x8e80` → `RSCC 0x2306a←2` + polls bloqueantes
  `GPUCC 0x22c00+0x104/0x11c` + `ISENSE 0x1f95d←1` (**exige GPUCC vivo**).
  `IpcCore/Mem` vía evento `0x2f` tras `START` de HFI. (W2 §§2f/2g/3c)
- RSC/AOP/QMP: `mboxes <aop_qmp>`; ACD negociado por mbox; `sync_state` rpmh a
  3.142 **antes** del boot del CM3; `RSCC SEQ_MEM/PDC` lo escribe el AOP (la CPU
  no toca en cold boot). Timing: probe ~3 s en sistema casi quieto; fw perezoso
  al primer open ~6.1 s.

## 6. TrustZone / hypervisor / SCM y la GPU

- `hypervisor.protected_vm.supported=false`: solo en bootconfig del
  `vendor_boot` (6 líneas `androidboot.*`), no en cmdline. (R8 §1)
- `qcom,iommu-dma="disabled"`: idéntico vendor/port en el GMU y en los hijos
  `qcom,kgsl-iommu` SID 0/2. (CONFRONTA §1.1; INV-GMU-ESTADO §2.3/§4.2)
- Contextos: `gfx3d_user` SID 0, `gfx3d_secure` SID 2 (hijos de la kgsl-smmu),
  **GMU SID 5**; el port solo usa SID 0. `qcom,actlr = <0 0x3ff 0x32b>`,
  TBU `0..0x3ff`, `iova-width` 49: idéntico. (CONFRONTA §§1.1–1.3)
- Zap: región segura `0x9899a000/0x2000` no-map, cargado por
  `adreno_load_fw`/`request_firmware` — **sin SCM explícito evidenciado**.
  No hay `qcom_scm`/QSEE/PIL toreado: hueco, no hecho.
- Display como contraste: DPU por `apps-smmu` **SID 0x1c00**,
  `handoff-smrs = <0x1c00 0x02>`, `sde-secure-sid-mask = 0x1c01`,
  `smmu_sde_unsec` con `iommu-dma-addr-pool` + `earlymap`. (R8 §2)
- Dumps #554 (`build/evidencia/aop-dump-20261009/`, gitignored, shas en ledger):
  `aop_a = aop_b 3353ea91…` 512 KiB **ELF32 RISC-V** + `aop_config/xbl/tz/hyp/
  abl_a`. Antes (#552): "xbl/tz/aop nunca dumpeados". Triaje pendiente:
  correlación `cmd-db gfx/cx/mmcx` + `beginVoteGxOn` vs `RSCC unlock`
  (plantilla en BARRIDO-FASE3 §3).
- Regla: **no tocar bootloader** (`abl/xbl/tz/hyp/aop…` = brick). (#232)

## 7. Diferencias Android-vs-nuestro-arranque candidatas al release racy

(Contexto: #580 — la misma L11 muere 6/6 en puntos distintos, `gbif` vs
`pre-rst`; L11–L15 con 54 insns idénticos. RE-GBIF §§0–4.)

1. **Módulo diferido vs built-in en serie**: Android trae ~300 `.ko`
   (`load_modules_parallel=true`); kgsl probea a ~3 s en sistema casi quieto.
   Nuestro `built-in` probea en serie (`arm-smmu` 0.319, `fw_start` en resume
   4.12 con subsistemas aún probeando). (R8 §1; CONFRONTA §2; K31 #470)
2. **Firmware perezoso vs temprano**: Android probea SIN fw (150 ms) y carga
   sqe/gmu/zap al primer open ~6 s, con ueventd y reintentos. Nosotros cargamos
   en el path del resume, sin fallback. (GPU-ANDROID §a; INV-GMU-ESTADO §5.4)
3. **Governor TZ vs nada**: Android `msm-adreno-tz` 255–950 (9 OPs, default 8,
   idle 80 ms). El port no tiene TZ. (GPU-ANDROID §b)
4. **ACD/IFPC**: Android `acd-level` por OP + `qmp` en el GMU + GX no gobernable
   por CPU. Port: sin `acd-level`, `qcom,qmp` en el nodo GPU (no GMU) →
   `qmp_send` nunca sale; ACD prohibido en k61. (CONFRONTA §§1.1/3E/5)
5. **Interconnects**: Android reales (`bus-table-ddr` 10 votos + `bus-freq` por
   OP). Port vacíos + OPP sin `peak-kBps` (vaciado adrede, wedge #286; s274
   aplazado). (CONFRONTA §§1.3/5; BARRIDO-FASE3 §2b)
6. **SMMU**: Android SMMU privada `qsmmu-v500` con votos correctos
   (`hlos1/memnoc/snoc/ahb`), `tcu-base`, `use-3-lvl-tables`. Port `arm-smmu` +
   `rscc`/`demet` extra + `power-domains` CX/GX (vs reguladores), SMMU sin voto
   CX, `qmp` mal, solo SID 0. (CONFRONTA §§1.1/1.2/5; INV-GMU-ESTADO §4)
7. **Votos que XBL/AOP dejan puestos** (Android los hereda, nosotros
   reprogramamos): `cx_gmu 220 ON`, `hub_cx_int+aon 200 ON`, `ddrss_axi ON`,
   `hlos1/ahb/memnoc` N (IFPC), `initial-pwrlevel 8`, `gx_clkctl_gdsc`
   disabled en stock. El port escribía `SEQ_MEM+PDC_ENABLE` sobre el AOP
   (neutro desde k60) y GBIF C1 copió secuencia vendor sin contexto GX → racy.
   (INV-GMU-ESTADO §§1/2.1/8; CONFRONTA §2; RE-GBIF §1 F4)
8. **Entorno**: splash 43 MB vs nuestro memmap 26 MB; SSC-disable vendor no
   heredado; `splash_region` vivo mientras el kernel pisa memoria.

## 8. Mediciones pendientes (huecos lado Android, nadie los midió)

1. `msm_kgsl.ko` de cliffs (3.5 MB, en `vendor_dlkm`, solo listado en
   `android-full-gaps/h9-modules/`): `modinfo`/`strings` (versión HFI, parms,
   features ACD/IFPC/DMS/LM, tracepoints). Sacar de `vendor_dlkm` o `super.img`.
2. `gmu-log`/snapshot binario: 0 bytes en ambas rondas. Ir por tracing
   (`gmu_event`, `kgsl_gmu_*`) en vez del debugfs.
3. `/sys/kernel/debug/kgsl/` superior (`power.bin`, `qos`, `hfi_queue`, regs
   GMU): nunca capturado.
4. Clocks **con carga** (`freq_measure` / `measure_only_gx_gfx3d`) +
   `devfreq trans_stat` / tiempo por OP (solo hay 3 samples idle).
5. Fuentes techpack (drop Xiaomi OS3.0.303 / CAF / OnePlus SM7675 / uke-v-oss):
   comparar pwrlevels (`LOW_SVS 220 vs SVS 550` = sospechoso nº1).
6. `chipid` de boot `0x43030b00` verificado en port vivo (solo consta por DT).
7. Golden-state vivo: `clk + genpd + regulator` con 3D corriendo + `ftrace`.
8. Tras una muerte: leer `/sys/fs/pstore/` en el boot siguiente + batería alta +
   ver si el watchdog ladra (L16/R0; RE-GBIF §§6–7; #580).
9. Triaje del dump AOP #554 (cmd-db gfx/cx/mmcx vs `beginVoteGxOn`/`RSCC unlock`).
10. RE abierto: `QTBL_ADDR` sin literal (vía SRAM `0x3240b8`), setter
    `[0x102610+#0xc]`, valores runtime `0x1f9cd-d0/0x1f984-5`, formato
    `GENERAL_10` del fw (k64 `0xf` falla `0x14520`), poll `&0x1ff==0x100`.
    (W2 §4; INV-KGSL §8)
11. Lado captura (CAPTURA-GAPS §1/§4): H1 GMU-log FAIL, H5 BT OFF (recapturar con
    BT ON), PD inactivo (recapturar con cargador PD 45 W), `boot_stats` vacío,
    FW BT en `firmware_mnt/image` sin listar, 416 ficheros vacíos (~403 stubs
    devlink kgsl + write-only), 76 unbound (útil: `qpnp-vibrator-ldo`).

## Fuentes

- `docs/historia/revision/GPU-ANDROID-INV-20261006.md` (inventario GPU Android)
- `docs/historia/revision/R8-repaso-android.md` (+ `build/evidencia/stock-dt/`)
- `docs/historia/revision/REV-GPU-DISPLAY-20261005.md` (Q1 ACD-knob, F1 zap-path, Q2 fw)
- `build/gates/revision/R3-vendor-diff.md`, `docs/historia/revision/CONFRONTA-GPU-20261007.md`
- `docs/historia/revision/INV-KGSL-RE-20261008.md`, `docs/historia/revision/INV-GMU-ESTADO-20261008.md`,
  `docs/historia/revision/INV-GMU-BIN-20261008.md`, `docs/historia/revision/INV-PERSIST-20261008.md`
- `build/gates/revision/BARRIDO-W2-RE-VOTOGX-20261009.md`,
  `docs/historia/revision/BARRIDO-FASE3-RE-20261009.md`, `docs/historia/revision/RE-GBIF-20261010.md`,
  `docs/historia/revision/K31-causa-raiz-erange.md`
- `build/gates/revision/CAPTURA-FULL-20261005.md`, `docs/historia/revision/CAPTURA-GAPS-20261005.md`
- `revision/S250-DTBO-GPU-SERIE.md`; `build/bootimg/cmdline-orig.txt`
- `ubuntu-permanente/docs/SESION-24SEP-GPU.md` (CM3/SID5),
  `ESTADO-ACTUAL.md`, `FLASH-LEDGER.md` (#424/#425/#428/#429, #553–#580)
- `docs/historia/ESTADO-VIVO.md` (10-oct, #580); `NOTAS-OMARCHY.md` :2433–2711
- Evidencia: `build/evidencia/android-full/extracted-full/`,
  `build/evidencia/android-snap/extracted-r15/`, `build/evidencia/aop-dump-20261009/`
