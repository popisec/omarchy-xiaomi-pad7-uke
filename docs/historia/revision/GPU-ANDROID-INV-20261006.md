# GPU-ANDROID-INV #535 — Inventario GPU Android (Adreno 732 / gen71100) para el port uke

Fecha: 6-oct-2026. Investigador: subagente GPU-Android. 100% offline (cero adb; tablet en Arch).
Entradas: capturas `build/evidencia/android-full/` (FULL #527), `android-full-gaps/` (#529),
`android-snap/extracted-r15/` (r1.5/#526), vendor base DTB, `ubuntu-uke/vendor-src/cliffs/`,
ledger `FLASH-LEDGER.md` #526/#527 (enlazado, no repetido). Solo lecturas.

Complementa (no repite): `CAPTURA-FULL-20261005.md`, `docs/historia/revision/REV-GPU-DISPLAY-20261005.md`,
`docs/historia/revision/CAPTURA-GAPS-20261005.md`, `docs/historia/revision/U1-firmware-gpu.md`.

---

## (a) SECUENCIA de bring-up GPU reconstruida de dmesg

Fuente primaria: `evidencia/android-snap/extracted-r15/.../07-sys/dmesg-FULL.txt` (desde
boot completo); cruce con `evidencia/android-full/extracted-full/15-common/dmesg-full.txt`
(FULL #527). El vendor kernel **no loguea nada** de ACD/IFPC/GDSC — lo que sigue es todo lo
que hay. Nota clave: **msm_kgsl es MÓDULO** (`msm_kgsl.ko`, techpack) → el probe ocurre en
init.rc (~3 s), no en el arranque del kernel.

| t (s) | Evento |
|---|---|
| 0.236 | `init: Loading module gdsc-regulator.ko` (framework GDSC del techpack clk) |
| 0.484 | `init: Loading module gpucc-pineapple.ko` (en la misma ventana cargan gcc_cliffs, pinctrl_cliffs, clk_qcom…) |
| 2.344 | `gpu_cc-cliffs 3d90000.clock-controller: Registered GPU CC clocks` (gpucc enlaza, clocks registrados pero apagados) |
| 2.345 | `arm-smmu 3da0000.kgsl-smmu: probing hardware configuration` → SMMUv2, stage-1, walk coherente, 24 stream groups, **22 context banks (0 stage-2)**, páginas 0x61311000, **48-bit VA → 36-bit IPA** |
| 2.967 | boot_kpi `M - DRIVER KGSL Init` (core kgsl ya cargado como módulo) |
| 2.980 | boot_kpi `M - DRIVER KGSL Ready` |
| 2.982–2.984 | grupos IOMMU: `kgsl-iommu:gfx3d_user` → grupo 17, `:gfx3d_secure` → 18, `adreno-gen7-gmu` → 19 (los 3 comparten la kgsl-smmu interna) |
| 2.990 | boot_kpi `M - DRIVER GPU Init` |
| 3.015–3.020 | component binds: `kgsl-3d … bound 3da0000.qcom,kgsl-iommu`, `:gfx3d_user`, `:gfx3d_secure`, y `bound 3d68000.qcom,gmu (ops gen7_gmu_component_ops [msm_kgsl])` |
| 3.117 | boot_kpi `M - DRIVER GPU Ready` ← **probe completo del GPU en 150 ms, SIN firmware** |
| 3.142 | `gpu_cc-cliffs 3d90000.clock-controller: sync-state` (rpmh drenado) |
| ~4.4–6.0 | arranque de HALs de usuario; el primer open de `/dev/kgsl-3d0` dispara la carga de firmware |
| 6.131 | petición `gen71100_sqe.fw`: fallbacks `-13` (SELinux) por `/vendor/firmware_mnt/image/`, `/kiwi/`, `/vendor/firmware/`, `/wlan/qca_cld/kiwi_v2/`, directo `-2` → **ueventd** lo resuelve en `/vendor/firmware/gen71100_sqe.fw` (2 ms) |
| 6.162 | ídem `gen71100_gmu.bin` → `/vendor/firmware/gen71100_gmu.bin` (2 ms) |
| 6.297 | ídem `gen71100_zap.mbn` → **`/odm/firmware/gen71100_zap.mbn`** (20 ms) |
| 6.15 | `init: starting service 'gpu'` (pid 1851) |
| 8.688 | `init: processing action (vendor.gpu.available_frequencies=*)` (init.qcom.rc:1023) → sysfs listo para consumers |

Orden interno (no visible en log, inferido del flujo upstream gen7 + sysfs): enable `gpu_cc_cx_gdsc`
→ GMU micro-kernel cargado+boot (SQE lo carga el GMU; HFI handshake) → ACD negociado con AOP vía
QMP (estado final `acd=1`) → GX GDSC managed por GMU → IFPC activo (`ifpc=1`, hysteresis 5760 µs)
→ zap shader para los anillos seguros. **Cero líneas dmesg de ACD/IFPC/IRQ**: este build del
vendor va silencioso; la única IRQ GPU en `/proc/interrupts` es `GICv3 337 Level gmu` (contadores
a 0 en la captura; SPI 305 del DT = hwirq 337 en numeración GIC).

---

## (b) Estado POST-ARRANQUE medido (dos estados capturados)

### r1.5 idle (`android-snap/extracted-r15/.../01-gpu/kgsl-sysfs-valores.txt` + gaps h2/h3)
- `gpu_model` **Adreno732**; tabla **9 OPs**: `950 900 835 736 684 633 500 353 255 MHz`
- `gpuclk=255000000` (idle), `devfreq/cur_freq=255 MHz`, governor **`msm-adreno-tz`**,
  `devfreq/min_freq=255000000`, `devfreq/max_freq=950000000`
- `default_pwrlevel=8` (arranca al mínimo), `max_pwrlevel=0`, `min_pwrlevel=8`, `thermal/pwrlevel=8`
- `gpu_busy_percentage=0–7 %` (3 muestras), `gpubusy=0 0`, `active_cnt=0`

### FULL #527 en uso (`extracted-full/16-fixup/kgsl-3d0-sysfs/`)
- `gpuclk=950000000`, `clock_mhz=950`, `min_clock_mhz=max_clock_mhz=950`, `thermal_pwrlevel=0`,
  `gpu_busy_percentage=4 %`, `gpu_clock_stats=4427187 34343 3158 0 0 0 0 0 1551588`
- **ACD ON**: `acd=1` · **IFPC ON**: `ifpc=1`, `ifpc_count=0x18DE` (6366 entradas a power collapse),
  `ifpc_hyst=5760` (µs, debugfs) · `acd_calibrate=0` (knob de disparo, no estado — ver Q1 de REV-GPU-DISPLAY)
- Otros knobs: `idle_timer=80` (ms), `bus_split=1`, `hwcg=1`, `dms=1`, `gmu_ab=1`, `lm=0`, `clx=0`,
  force_* todos 0; preemption: `preempt_level=1`, `skipsaverestore=1`, `usesgmem=1`
- BCL: sid0/1/2=0, `bcl_throttle_time_us=0` (sin throttling)
- Reguladores (regulator_summary): `gpu_cc_cx_gdsc` y `gpu_cc_gx_gdsc` presentes (GX en count 1 —
  lo gobierna el GMU). GPU events: contadores de contexto avanzando (render activo).

---

## (c) Clock tree GPU del vendor (clk_summary FULL + `gpucc-cliffs.c`)

Captura con GPU idle → la mayoría en N; parents y tablas de frecuencia de la fuente
`~/proyectos/ubuntu-uke/vendor-src/cliffs/gpucc-cliffs.c` (GPL, 671 líneas).

| Reloj | Rate capturado | Padre(s) / tabla | Consumidor | Estado |
|---|---|---|---|---|
| gpu_cc_xo_clk_src | 19.2 MHz | bi_tcxo_ao (cmd_rcgr 0x9010) | — | Y |
| ├ gpu_cc_xo_div_clk_src | 4.8 MHz | /4 de xo | — | Y |
| │ └ gpu_cc_freq_measure_clk | 4.8 MHz | xo_div | measure-only | N |
| ├ gpu_cc_cx_accu_shift_clk | 19.2 MHz | xo | — | N |
| ├ gpu_cc_cxo_clk | 19.2 MHz | xo | `qcom,gmu@3d69000` | N |
| └ gpu_cc_demet_div_clk_src | 19.2 MHz | xo (div reg 0x902c) | — | Y |
| gpu_cc_ff_clk_src | 19.2→200 MHz | gpll0_out_main /3 (cmd 0x91b8), tabla {200 MHz} | — | N |
| └ gpu_cc_cx_ff_clk | 19.2 MHz | ff | — | N |
| gpu_cc_pll1 | 440 MHz | PLL (lucid_ole) | — | N |
| └ gpu_cc_gmu_clk_src | 220 MHz | pll1 /2 (cmd 0x9168), tabla {19.2, 220, 550 MHz} | — | N |
|   └ gpu_cc_cx_gmu_clk | 220 MHz | gmu_clk_src | `qcom,gmu@3d69000` | **Y** |
| gpu_cc_pll0 | 510 MHz | PLL | — | N |
| gpu_cc_hub_clk_src | 200 MHz | gpll0_out_main (o div /2) (cmd 0x919c), tabla {200 MHz} | — | **Y** |
| ├ gpu_cc_hub_cx_int_clk | 200 MHz | hub | GMU | **Y** |
| ├ gpu_cc_ahb_clk | 200 MHz | hub | `3d00000.qcom,kgsl-3d0`, `3da0000.kgsl-smmu` | N (idle) |
| ├ gpu_cc_crc_ahb_clk | 200 MHz | hub | — | N |
| └ gpu_cc_hub_aon_clk | 200 MHz | hub | — | **Y** |
| gpu_cc_memnoc_gfx_clk | — | gate | — | N |
| gpu_cc_hlos1_vote_gpu_smmu_clk | — | gate | `3da0000.kgsl-smmu` | N (idle) |
| gpu_cc_sleep_clk | — | gate sleep_clk | — | N |
| gpu_cc_mnd1x_{0,1}_gfx3d_clk | — | divisores MND del GX | — | N |
| gcc_gpu_memnoc_gfx | — | GCC | GMU, kgsl-3d0, kgsl-smmu | N |
| gcc_gpu_snoc_dvm_gfx | — | GCC | kgsl-3d0, kgsl-smmu | N |
| gcc_ddrss_gpu_axi_clk | — | GCC (DDR AXI del GMU) | `qcom,gmu@3d69000` | **Y** |
| gcc_qmip_gpu_ahb_clk | — | GCC | — | N |
| gpu_cc_debug_mux | — | debug | — | Y |
| **measure_only_***: gpu_cc_gx_gfx3d_clk, demet, cxo_aon, cx_gfx3d_slv, cx_gfx3d, gcc_gpu_cfg_ahb | (50 kHz placeholder) | dominio de medida DVM/GMU | — | — |

**Dato estructural**: `gpucc-cliffs.c` registra **22 clocks y NO hay `gx_gfx3d_clk_src`** — el
reloj del shader (GX) no es software-controllable desde el CPU: lo gestiona el **GMU** (con ACD),
el CPU solo lo mide (`measure_only_gpu_cc_gx_gfx3d_clk`). El port upstream hace lo mismo vía
gpucc-sm8550/gen7: `gpu_cc_gx_gfx3d_clk` también ausente. GDSCs DT: `gpu_cc_cx_gdsc` (hw-ctrl @
3d99168/3d9908c), `gpu_cc_gx_gdsc` (@3d99034), `gx_clkctl_gx_gdsc` (@3d68024, disabled —
alternativa del techpack kgsl).

---

## (d) Nodo DT vendor base (GPU + GMU) — `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img` (decompilado con dtc)

`compatible = "qcom,adreno-gpu-gen7-11-0","qcom,kgsl-3d0"` · **chipid `0x43030b00`** ·
`qcom,gpu-model="Adreno735"` (la board DTBO lo deja en Adreno732/950 MHz; el base genérico llega a 1.1 GHz).

```dts
msm_gpu: qcom,kgsl-3d0@3d00000 {
    qcom,initial-pwrlevel = <0x0a>;              // nivel 10 (base; la board usa 8 niveles)
    qcom,bus-table-ddr  = <0x00 0x209a8e 0x2dc6c0 0x5caf6a 0x65ce03
                           0x7cb163 0xa3140c 0xbdf5c2 0xdbb3e5 0xfbc520>;  // 10 AB kvotes
    qcom,bus-table-cnoc = <0x00 0x64>;
    interconnect-names = "gpu_icc_path";
    interconnects = <&mc_virt MASTER_GPUSS0 0 &config_noc SLAVE_GPUSS...>; // phandles 0x1a2/0x188
    qcom,tzone-names = "gpuss-0","gpuss-1","gpuss-2","gpuss-3";
    qcom,gpu-qdss-stm = <0x161c0000 0x40000>;
    qcom,ubwc-mode = <0x04>;  qcom,min-access-length = <0x20>;
    qcom,chipid = <0x43030b00>;  qcom,gpu-model = "Adreno735";
    clock-names = "gcc_gpu_memnoc_gfx","gcc_gpu_snoc_dvm_gfx","gpu_cc_ahb","apb_pclk";
    interrupts = <0 300 4>;   interrupt-names = "kgsl_3d0_irq";   // GIC SPI 300
    reg-names = "kgsl_3d0_reg_memory","rscc","cx_dbgc","cx_misc",
                "qdss_etr","qdss_gfx","qdss_tmc";
    reg = <0x3d00000 0x40000>, <0x3d50000 0x10000>, <0x3d61000 0x800>,
          <0x3d9e000 0x1000>, <0x10048000 0x8000>, <0x10900000 0x80000>, <0x10b05000 0x1000>;
    status = "ok";  #cooling-cells = <2>;
    zap-shader { memory-region = <&gpu_microcode_mem>; };   // 0x9899a000, 8 KiB, no-map
    qcom,gpu-mempools { // 6 pools: pages 4K/8K/64K/128K/256K/1M, reserved 0x800/0x400/0x100/0x80/0x50/0x20
        qcom,gpu-mempool@0 { qcom,mempool-reserved=<0x800>; qcom,mempool-page-size=<0x1000>; };
        ... @1 0x400/0x2000 · @2 0x100/0x10000 · @3 0x80/0x20000 · @4 0x50/0x40000 · @5 0x20/0x100000
    };
    qcom,gpu-pwrlevels {   // 11 niveles en el BASE (la DTBO de la board recorta a 9: 255–950)
        @0  gpu-freq=<1100000000> acd-level=<0xa02f5ffd> bus-freq/max/min=<9 9 9> level=<0x1b0>
        @1  gpu-freq=<1000000000> acd-level=<0xa02f5ffd> bus <9 9 9>     level=<0x1a0>
        @2  gpu-freq=< 950000000> acd-level=<0xa8285ffd> bus <9 9 9>     level=<0x190>
        @3  gpu-freq=< 900000000> acd-level=<0xa8285ffd> bus <9 9 7>     level=<0x180>
        @4  gpu-freq=< 835000000> acd-level=<0xa8285ffd> bus <9 7 8>     level=<0x140>
        @5  gpu-freq=< 736000000> acd-level=<0x88295ffd> bus <8 6 7>     level=<0x100>
        @6  gpu-freq=< 684000000> acd-level=<0x88295ffd> bus <8 6 7>     level=<0x0e0>
        @7  gpu-freq=< 633000000> acd-level=<0x88295ffd> bus <8 5 7>     level=<0x0c0>
        @8  gpu-freq=< 500000000> acd-level=<0xa8295ffd> bus <7 2 4>     level=<0x080>
        @9  gpu-freq=< 353000000> acd-level=<0x882c5ffd> bus <3 1 3>     level=<0x040>
        @10 gpu-freq=< 255000000> acd-level=<0x882f5ffd> bus <3 1 1>     level=<0x038>
    };
};
gmu: qcom,gmu@3d69000 {
    compatible = "qcom,gen7-gmu";
    reg-names = "gmu","gmu_pdc","gmu_ao_blk_dec0";
    reg = <0x3d68000 0x37000>, <0xb280000 0x10000>, <0x3d40000 0x10000>;
    interrupts = <0 304 4>, <0 305 4>;  interrupt-names = "hfi","gmu";
    clock-names = "gmu_clk","cxo_clk","axi_clk","memnoc_clk","ahb_clk","hub_clk";
    clocks = <&gpucc GPU_CC_CX_GMU_CLK>, <&gpucc GPU_CC_CXO_CLK>,
             <&gcc GCC_GPU_MEMNOC_GFX_CLK>, <&gcc GCC_GPU_DDRSS_GPU_AXI_CLK>,
             <&gpucc GPU_CC_AHB_CLK>, <&gpucc GPU_CC_HUB_CX_INT_CLK>;
    vdd-supply = <&gpu_cc_gx_gdsc>;  vddcx-supply = <&gpu_cc_cx_gdsc>;
    regulator-names = "vddcx","vdd";
    iommus = <&kgsl_smmu 5 0>;   // contexto 5 de la kgsl-smmu
    qcom,gmu-freq-table = <220000000 0x40 550000000 0x80>;  // niveles CX del GMU
    qcom,ipc-core = <0x400000 0x140000>;   mbox-names="aop"; mboxes=<&aop_qmp 0>;
    qcom,iommu-dma = "disabled";
};
kgsl_smmu: kgsl-smmu@3da0000 {   // SMMU PRIVADA del GPU
    compatible = "qcom,qsmmu-v500","qcom,adreno-smmu";
    reg = <0x3da0000 0x40000>, <0x3de6000 0x40>;  // base + tcu-base
    #iommu-cells=<2>; qcom,use-3-lvl-tables; #global-interrupts=<1>; dma-coherent;
    vdd-supply = <&gpu_cc_cx_gdsc>;
    clocks = <&gpucc GPU_CC_HLOS1_VOTE_GPU_SMMU_CLK>, <&gcc GCC_GPU_MEMNOC_GFX_CLK>,
             <&gcc GCC_GPU_SNOC_DVM_GFX_CLK>, <&gpucc GPU_CC_AHB_CLK>;
    qcom,actlr = <0x0 0x3ff 0x32b>;      // 22 interr. (global + 21 context); 24 stream groups
    gpu_qtb: gpu_qtb@3de8000 { compatible="qcom,qsmmuv500-tbu","qcom,qtb500";
        qcom,stream-id-range=<0x0 0x400>; qcom,iova-width=<0x31>; qcom,num-qtb-ports=<2>; };
};
gpucc: clock-controller@3d90000 {  compatible = "qcom,cliffs-gpucc","syscon";
    reg = <0x3d90000 0xa000>; vdd_cx/vdd_mx/vdd_mxc supplies;
    clocks = bi_tcxo, bi_tcxo_ao, gpll0_out_main, gpll0_out_main_div; };
// syscon de reset ACD/GX: gpu_cc_gx_domain_addr@3d99504, gpu_cc_gx_sw_reset@3d99058,
// gpu_cc_gx_acd_reset@3d99358, gpu_cc_gx_acd_iroot_reset@3d9958c
```

Notas: (1) el vivo (`evidencia/android-full/extracted-full/14-dt/dt-live.tar.gz`) difiere del base
solo en lo ya documentado en REV-GPU-DISPLAY (9 pwrlevels, acd-level por OP). (2) La **kgsl-smmu
es SMMUv2 no-TBU-del-APPS** (arm-smmu: stage-1, 22 ctx banks) — iova-width 49 (0x31) en el QTB.

---

## (e) Inventario de materia prima en disco

| Qué | ¿Hay? | Dónde |
|---|---|---|
| **FUENTES kgsl/techpack vendor** | **NO** | No existe ningún árbol techpack/`msm_kgsl` en disco (find kgsl/gen71100/techpack: solo fw y scripts propios). **Candidato a descargar** (drop kernel Xiaomi uke / CAF `vendor/qcom/opensource/` + `techpack/camera|display|gpu`) |
| FUENTES **gpucc-cliffs** (clock driver) | **SÍ** | `~/proyectos/ubuntu-uke/vendor-src/cliffs/` — `gpucc-cliffs.c`+`qcom,gpucc-cliffs.h` (671 l.), `gcc-cliffs.c`, `core-clk-*.{c,h}` (framework renombrado), `pinctrl-cliffs.c`, `rpmhpd.c`, `vdd-level.h`, `patches/` |
| `.ko` GPU de uke/cliffs | **NO toreado** | En el device: `vendor_dlkm/lib/modules/msm_kgsl.ko` (3.533.984 B), `msm_drm.ko` (6.105.320), `gpucc-cliffs.ko` (43.696), `gpucc-volcano.ko` (41.872), `gpu_dump_skip_cdev.ko` (14.224) — **solo listados** en `evidencia/android-full-gaps/h9-modules/ls-vendor_dlkm.txt`; el `topull/` trae táctil/BT/WiFi pero NO GPU |
| `msm_kgsl.ko` EN DISCO | Sí pero **inútil** | `~/root_nothing2/vb/lib/modules/msm_kgsl.ko` = Nothing Phone 2 (`gpucc-waipio/diwali`, SoC distinto) |
| Kernel Android | (binario) | GKI `6.1.138-android14-11-g0c3d559bcd85-ab14529422` (system_dlkm); módulos vendor vermagic `6.1.68-android14-11`; ROM en `/var/tmp/rom/uke_eea_global_images_OS3.0.303.0.WOZEUXM_16.0/images/` (super.img, vendor_boot.img) |
| Firmware gen71100 | SÍ | `~/gpu-work/fw-qrd8635/gen71100_{sqe.fw,gmu.bin,zap.mbn}` (+copias `ubuntu-uke/stock/firmware/`, `gpu-work/uke-staging/firmware/`) · En el device: sqe+gmu en `/vendor/firmware/`, zap en `/odm/firmware/` |
| DT vendor base | SÍ | `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img` (nodos extraídos arriba; DT vivo capturado en `14-dt/dt-live.tar.gz`) |
| Debugfs/sysfs kgsl | SÍ | FULL: `extracted-full/01-gpu/kgsl-debugfs/` (árbol kgsl-3d0 completo), `16-fixup/kgsl-3d0-sysfs/` (sysfs crudo), r1.5: `android-snap/.../01-gpu/*.txt` |
| Mesa con kgsl (nuestro) | SÍ | `~/gpu-work/noche-20260915/mesa-kgsl` (host, no vendor) |

---

## (f) Gap analysis — qué falta explotar de Android

1. **`msm_kgsl.ko` de cliffs sin torear** (3.5 MB): `modinfo`/`strings` darían versiones HFI,
   parms, features compiladas (ACD/IFPC/DMS/LM) y nombres de tracepoints. Acción si la tablet
   vuelve a Android (o desde super.img): extraer vendor_dlkm.
2. **GMU log / snapshot binario nunca capturado**: `h1-gmu/` quedó con 0 bytes (debugfs `gmu-log`
   binario no se pudo leer). Contendría versión exacta del micro-kernel GMU y log de HFI —
   valioso para depurar E RANGE/CM3.
3. **debugfs superior `/sys/kernel/debug/kgsl/`** (fuera de kgsl-3d0): `power.bin`, `qos`,
   `debug_*`, `hfi_queue`/gmu registers no capturados en ninguna ronda.
4. **clk_summary con GPU idle**: faltan rates en actividad (usar `gpu_cc_freq_measure_clk` /
   `measure_only_gpu_cc_gx_gfx3d_clk` con carga — la ruta de medición existe y no se leyó).
5. **devfreq trans_stat** y stats del governor tz (transiciones, tiempo por OP) sin capturar;
   solo 3 samples puntuales de busy%.
6. **Fuentes techpack**: sin el .c del kgsl vendor, el mapeo exacto de offsets/flags gen71100
   (DMS, gmu_ab, bus_split ya vistos en sysfs) se infiere de upstream 5.x/6.x + strings del .ko.
   Descarga futura: drop de Xiaomi (OS3.0.303) o CAF.
7. Confirmar **chipid de boot** (`0x43030b00` del DT vs catálogo de nuestro fork) — ya apuntado
   en REV-GPU-DISPLAY F4; solo verificable con el port vivo.
