# R3 — VENDOR Android vs nuestro DT/arranque (eje PANTALLA + apps-SMMU)

**Fecha:** 29-sep-2026 madrugada · **proyecto omarchy-uke** · agente **R3** (`build/gates/revision/`)
**Modo:** 100 % offline. Sin tablet, sin adb/fastboot/ssh, sin abrir `/dev/ttyACM0`. `~/gpu-work` y
`~` en solo-lectura; lo único escrito por mí: `/var/tmp/R3/*` (dumps de trabajo) y este fichero.

Convención: **[DATO]** = fichero:línea o comando + salida literal · **[INFERENCIA]** = deducción
encadenada sobre datos · **[NO VERIFICADO]** = no medido y no medible sin la tablet.

---

## 0. Titulares (lo que hay que llevarse)

1. **El compatible vendor del apps-smmu es `qcom,qsmmu-v500`** (único, exacto) y **solo** ese
   —`vendor-base.dts:10984`—. Valida el `of_match` que añadió K1 (`k1-arm-smmu.diff:123`:
   `{ .compatible = "qcom,qsmmu-v500", .data = &arm_mmu500 }` + impl0 en `arm-smmu-qcom.c`).
   `qcom,adreno-smmu` **no** está en apps-smmu (sí en kgsl-smmu) ⇒ la rama adreno de
   `qcom_smmu_impl_init` no se dispara para el apps-smmu.
2. **Android hace el reset COMPLETO y SOBREVIVE**, con el mismo linaje de driver (`arm-smmu`, módulo
   `arm_smmu.ko`, `dmesg-android.txt:1337`), a los **0,543250 s** (`:1733`), **antes** de que el UFS
   del kernel exista (`ufshcd-qcom … Adding to iommu group 0` a los **0,550689 s**, `:1743`, 7,4 ms
   después). **El dwc3 (USB) no pide su grupo hasta los 9,659966 s** (`:9495`), 9,1 s después del reset.
3. **El hardware reporta NUMPAGENDXB=6 / tamaño de espacio de 1 MiB** — [DATO] nuestro kernel con
   s258 lo imprime: `SMMU address space size (0x100000) differs from mapped region size (0x200000)!`
   (`out/k6-migas.log:2189`; `k6b` idéntico, `:2277`) y el poke lo detalla:
   `cfg_probe ID1=0x60000047 pgshift=12 NUMPAGENDXB=6 CBs=71; CB base=0x80000` (`:2188`). El AS 1 MiB
   **es exactamente el `reg[0]` del vendor** ⇒ el vendor no imprime el aviso ⇒ **A′ («la ventana de
   1 MiB deja los CBs fuera del mapeo») queda refutada de raíz**: el CB base cae en `base+0x80000`,
   dentro de 1 MiB.
4. **SID clave**: UFS = **0x60/0** (`iommus = <&apps_smmu 0x60 0x00>`, `vendor-merged.dts:15279`),
   DPU/display = **0x1c00/0x2** (nodo `qcom,smmu_sde_unsec_cb`, `vendor-merged.dts:26667`) y secure
   **0x1c01/0x0**. Nuestro K6 mide en vivo `SMR[0] = 0x80000060` (sid 0x60, mask 0) = el SID que el
   ABL dejó programado ⇒ misma foto que el vendor.
5. **El vendor lee propiedades que mainline ignora**: `qcom,handoff-smrs = <0x1c00 0x02>` (el SID del
   display), `qcom,actlr` (31 tripletas) y los 8 hijos TBU (`qcom,qsmmuv500-tbu`), con maquinaria
   *halting* de TBU (`arm_smmu_handoff_cbs`, `Couldn't halt TBU!`, `qcom,opt-out-tbu-halting` en los
   strings del módulo vendor de la familia, `~/root_nothing2/vb/lib/modules/arm_smmu.ko`).
   Nosotros: **0 lectores** de todo eso y nuestro kernel no contiene ni la cadena
   `TBU failed probe` (grep en `palawan-linux/drivers/` = 0).
6. **El panel real es el O82 42 02 0b** (dual-DSI, 2×1600×2136, 30 bpp, DSC, `bl_ctrl_external`),
   confirmado en el dmesg vendor: `Successfully bind display panel
   'qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid'` (`dmesg-android.txt:4560`) y su `mi,panel-id =
   <0x004f3832 0x5042020b>` (= "O82"+"PB\x02\x0b", `dtbo_b-actual.dts:11527`). El `qcom,dsi-default-panel`
   del DT apunta al nodo *r66451* (`vendor-overlay.dts:12975`) — **no es el selector real**.
7. **La cadena display vendor no tiene `iommus` en el nodo del MDP**: el IOMMU del display lo hace un
   nodo aparte (`qcom,smmu_sde_unsec_cb`, componentes que `msm_drm` bindea: `:4573`) y el MDP enlaza con
   `qti,smmu-proxy-cb-id = <0x01>`. Nuestro kernel (msm mainline) **exige** que el device del DPU esté
   mapeado (`device_iommu_mapped(mdp_dev) || device_iommu_mapped(mdss_dev)`) — por eso nuestro overlay
   añade `iommus = <0x129 0x1c00 0x02>` al nodo nuevo `display-subsystem@ae00000` (`our-merged.dts:857`,
   `27135`). El SID es el mismo que el vendor.
8. **WiFi = WCN6750 por el camino `icnss2` (NO PCIe)**: `qcom,pcie@1c00000` está `status="disabled"`
   en el DT vendor y **no hay ni una línea de pci-msm en el dmesg dorado**; el wifi va por
   `qcom,wcn6750` + rproc `wpss` + `iommus = <&apps-smmu 0x1400 0x1>` (grupo 8 a los 2,839 s) con
   firmware `qca6750/bd_o82gl.elf`, `qca6750/regdb_xiaomi.bin`, `qca6750/qdss_trace_config.cfg`.
9. **Sensores: no hay I2C de sensores**. El sensor core va por QMI/ADSP (`qcom,qmi-sensors`,
   `adsprpc … msm/adsp/sensor_pd`, `dmesg-android.txt:3624`). Lo único I2C/SPI del aparato es táctil
   NVT (SPI), 4 amplificadores `foursemi,fs16xx` (I2C), NFC `fm,fm19511`, `nanosic,803` (teclado pogo),
   `qcom,wcd939x-i2c`.
10. **Contradicción operativa importante**: TODO nuestro instrumental (K1..K6) arranca con
    `fastboot reboot` (sesión USB del ABL viva) y el golden Android hace el reset del SMMU con el
    **dwc3 del kernel sin attach (grupo 47 a los 9,66 s) y sin USB de fastboot**. El DT vendor nombra
    explícitamente el SID del display en `qcom,handoff-smrs` para *conservarlo* a través del reset —
    nosotros lo borramos. Dos diferencias peligrosas, ambas medidas aquí (ver §7).

---

## 1. Fuentes, hashes y receta (reproducible)

### 1.1 Ficheros usados

| Rol | Ruta | sha256 / nota |
|---|---|---|
| dmesg Android dorado | `~/proyectos/ubuntu-permanente/criticas/ufs-referencia-android/dmesg-android.txt` | 12101 líneas; `Linux version 6.1.138-android14-11-g0c3d559bcd85-ab14529422`; `Machine model: Qualcomm Technologies, Inc. Uke based on SM8635` |
| Base vendor (cliffs) | `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img` | `3f973c78f7dc6a66f1acea363be27774c51ff174fbf71117ebe74c385547562e`; totalsize `0x74122` (475426 B); `model = "Qualcomm Technologies, Inc. Cliffs SoC"`, `compatible = "qcom,cliffs"`, `qcom,msm-id = <0x266 0x10000>` |
| Base vendor (2ª copia) | `~/proyectos/ubuntu-uke/stock/dtbase/vendor_boot-base.dtb` | `1cc54953544f9e34d959746bb9ce50ffc6692c20f1cb3646f349e48eaf779883`; **fdtdump idéntico** al anterior (diff = 0 líneas) |
| Overlay vendor stock | `~/proyectos/ubuntu-uke/stock/images/dtbo.img` → payload | payload 591733 B, `e8f991e3324048ee3915fe8342c0b599c630ee2baf8929d4670820b388ecbcfc`; `model = "Uke based on SM8635"`, `board-id 0x08`, `miboard-id 0x0b` |
| Overlay vendor REAL de la tablet (24-sep) | `~/gpu-work/ramaa/s21/dtbo-gpu/dtbo_b-actual.img` → payload | payload 593234 B, `80a795595e10aad2303213ac9f3175403c6c823e31661499ed9833d9b7186763`; sin marcadores nuestros |
| Nuestro overlay activo | `build/bootimg/s258-panel-gpio2.img` → payload | payload 608405 B, `ea6ac36ed395a6f117aa18e82eb382aa53f32fff96bfa6de5501a921c3c3253a` |
| **Fusionado vendor** (base+overlay stock) | `/var/tmp/R3/vendor-merged.dtb` | `593206322b67bcaad195e6e6ba04a2d1c7529442121dbcc0e9f6b078088b44df` |
| **Fusionado nuestro** (base+s258) | `/var/tmp/R3/our-merged.dtb` | `9efe07d57a98637d07ab02e3bc5f39d0b9aafa0b2fab1a5f045c2789c73ee1e7` |
| Nuestro kernel (solo lectura) | `~/gpu-work/palawan-linux` | `7.2.0-rc2-palawan`; parches en `build/kernel-pokes/drivers/iommu/...` vía `build/gates/patches/k1..k6` |
| Nuestro dmesg vivo | `~/proyectos/out/k6-migas.log`, `k6b-migas.log`, `k5-migas.log` | probes a 38,18 s (k6), 90,42 s (k6b), 38,50 s (k5) |

### 1.2 Receta (comandos exactos)

```bash
# payloads de las imágenes dtbo (contenedor dt_table, magic 0xd7b7ab1e)
python3 build/bootimg/dtbo-extract.py ~/proyectos/ubuntu-uke/stock/images/dtbo.img /var/tmp/R3/vendor-overlay.dtb
python3 build/bootimg/dtbo-extract.py ~/gpu-work/ramaa/s21/dtbo-gpu/dtbo_b-actual.img /var/tmp/R3/dtbo_b-actual.payload.dtb
python3 build/bootimg/dtbo-extract.py build/bootimg/s258-panel-gpio2.img /var/tmp/R3/payload-s258.dtb
# fusiones (idéntico a lo que hace el ABL: base + overlay)
fdtoverlay -i ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img -o /var/tmp/R3/vendor-merged.dtb /var/tmp/R3/vendor-overlay.dtb
fdtoverlay -i ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img -o /var/tmp/R3/our-merged.dtb    /var/tmp/R3/payload-s258.dtb
dtc -I dtb -O dts -o /var/tmp/R3/vendor-merged.dts /var/tmp/R3/vendor-merged.dtb   # + fdtdump → vendor-base.dts
fdtdump ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img > /var/tmp/R3/vendor-base.dts
```

`vendor-base.dts` = fdtdump de la base (formato `0x%08x`, el que uso para los dumps literales del
nodo apps-smmu); `vendor-merged.dts`/`our-merged.dts` = `dtc -I dtb -O dts` de los fusionados (formato
corto `0x…`, con etiquetas conservadas). Los anexos citan el fichero y la línea.

---

## 2. Q1 — `apps-smmu@15000000` del vendor vs el nuestro

### 2.1 Nodo VENDOR, literal (`vendor-base.dts:10983-11005`, hijos en `:11006-11032`)

```dts
apps-smmu@15000000 {
    compatible = "qcom,qsmmu-v500";
    reg = <0x15000000 0x00100000 0x151fe000 0x00000040>;
    reg-names = "base", "tcu-base";
    #iommu-cells = <0x00000002>;
    qcom,use-3-lvl-tables;
    qcom,handoff-smrs = <0x00001c00 0x00000002>;
    #global-interrupts = <0x00000001>;
    #size-cells = <0x00000001>;
    #address-cells = <0x00000001>;
    ranges;
    dma-coherent;
    status = "ok";
    interrupts = <0x00 0x41 0x04  0x00 0x61 0x04 0x00 0x62 0x04 … 0x00 0x2b8 0x04>;
    qcom,actlr = <0x00000800 0x00000020 0x00000001  0x00001800 0x00000000 0x00000001
                  0x00001820 0x00000000 0x00000001  … 0x00001947 0x00000000 0x00000103>;
    phandle = <0x00000129>;
};
```

**Medidas exactas de esas dos listas** (parseadas de `vend-apps-smmu.dts`):

| Propiedad | Celdas | Contenido |
|---|---|---|
| `interrupts` | 291 = **97 IRQ** | 1 global (`<0x00 0x41 0x04>` = SPI 0x41 ⇒ virq 97) + **96 de contexto**: `0x61-0x76` (22), `0xb5-0xc0` (12), `0x13b-0x159` (31), `0x18b-0x199` (15), `0x1a2,0x1a3,0x19c,0x1a5,0x2c2,0x1a7,0x1a8,0x1a9` (8), `0x2b1-0x2b8` (8) |
| `#global-interrupts` | 1 | coincide con mainline sm8550 (`sm8550.dtsi:5545-5549` según INFORME-SMMU-CLK) |
| `qcom,actlr` | 93 = **31 tripletas** (sid, mask, actlr) | incluye `0x1c00 0x02 0x01` (display) y familias 0x1800/0xc00/0x1920/0x1940 |
| `clocks` / `clock-names` | — | **AUSENTES** (coincide con INFORME-SMMU-CLK: no hay relojes de apps-smmu en el vendor) |
| `power-domains` | — | **AUSENTE** |
| `iommus` | — | **AUSENTE** (no es un maestro, es el IOMMU) |

Hijos (8, exactos) — `vendor-base.dts:11006-11032`:

| Hijo | reg | `qcom,stream-id-range` | iova-width | ports | extra |
|---|---|---|---|---|---|
| `anoc_1_qtb@16f1000` | `0x16f1000+0x1000 0x16e1100+0x1000` | `<0x000 0x400>` | 0x24 | 1 | — |
| `anoc_2_qtb@171a000` | `0x171a000+0x1000 0x1701000+0x1000` | `<0x400 0x400>` | 0x24 | 1 | — |
| `cam_hf_qtb@14d2000` | `0x14d2000+0x1000 0x1482000+0x1000` | `<0x800 0x400>` | 0x24 | 2 | — |
| `nsp_qtb@7d3000` | `0x7d3000+0x1000 0x7df000+0x1000` | `<0xc00 0x400>` | 0x22 | 2 | — |
| `lpass_qtb@7b3000` | `0x7b3000+0x1000 0x7be000+0x1000` | `<0x1000 0x400>` | 0x20 | 1 | — |
| `pcie_qtb@16cd000` | `0x16cd000+0x1000 0x16c2000+0x1000` | `<0x1400 0x400>` | 0x24 | 1 | **`qcom,opt-out-tbu-halting`** |
| `sf_qtb@1451000` | `0x1451000+0x1000 0x1403000+0x1000` | `<0x1800 0x400>` | 0x24 | 2 | — |
| `mdp_hf_qtb@14d0000` | `0x14d0000+0x1000 0x1482000+0x1000` | `<0x1c00 0x400>` | 0x20 | 2 | — |

> Ojo: `mdp_hf_qtb` cubre el rango `0x1c00+0x400` ⇒ los SIDs del display (0x1c00/0x1c01) pertenecen al
> TBU `mdp_hf`. [INFERENCIA] Es el único hijo TBU cuyo rango cubre el IOMMU domain del MDP.

### 2.2 Nuestro nodo, literal (`our-merged.dts:16359-16465`)

```dts
apps_smmu: apps-smmu@15000000 {
    uke,canary-smmu = <0x01>;                       /* ← solo nuestro (s255, "canarias") */
    compatible = "qcom,qsmmu-v500";
    reg = <0x15000000 0x200000>;                     /* ← única diferencia de contenido */
    reg-names = "base";
    #iommu-cells = <0x02>;
    qcom,use-3-lvl-tables;
    qcom,handoff-smrs = <0x1c00 0x02>;
    #global-interrupts = <0x01>;
    #size-cells = <0x01>;
    #address-cells = <0x01>;
    ranges;
    dma-coherent;
    status = "ok";
    interrupts = <…291 celdas, idénticas al vendor…>;
    qcom,actlr = <…93 celdas, idénticas…>;
    phandle = <0x129>;
    /* 8 hijos TBU idénticos */
};
```

### 2.3 Diff exacto vendor → nuestro (`diff` de los dos nodos, §Anexo A)

```
2d1
<  (nada)                                   → nuestro añade: uke,canary-smmu = <0x01>;
4,5c3,4
<  reg = <0x15000000 0x100000 0x151fe000 0x40>;
<  reg-names = "base", "tcu-base";
---
>  reg = <0x15000000 0x200000>;
>  reg-names = "base";
```

**No hay más diferencias**: ni clocks, ni power-domains, ni resets, ni niveles de tabla, ni IRQs, ni
actlr, ni phandle (0x129 en los dos) ni hijos. Es decir: **el nodo vendor se conserva entero y lo único
que cambiamos es la ventana** (2 MiB en un solo `reg`).

### 2.4 Validación del `of_match` de K1

| Dato | Evidencia |
|---|---|
| Compatible vendor | `qcom,qsmmu-v500` (único) — `vendor-base.dts:10984` |
| of_match de nuestro kernel | `palawan-linux/drivers/iommu/arm/arm-smmu/arm-smmu.c` NO tiene `qsmmu-v500` (grep = 0); el binario K1 sí, vía parche: `build/gates/patches/k1-arm-smmu.diff:123` → `{ .compatible = "qcom,qsmmu-v500", .data = &arm_mmu500 }` y `:212` → `{ .compatible = "qcom,qsmmu-v500", .data = &qcom_smmu_500_impl0_data }` |
| Evidencia de familia de que el nombre es el correcto | strings del `arm_smmu.ko` vendor (`~/root_nothing2/vb/lib/modules/arm_smmu.ko`, vermagic 5.10.237-gki, **de otro aparato cape-v2, no de uke**): `alias=of:N*T*Cqcom,qsmmu-v500`, símbolos `qsmmuv500_cfg_probe`, `qsmmuv500_impl_init`, `qcom_smmu_write_s2cr`, `arm_smmu_handoff_cbs`, `qcom,handoff-smrs`, `qcom,adreno-smmu`, `Invalid actlr setting` |
| Evidencia directa (uke) del linaje del driver | dmesg Android: `arm-smmu 15000000.apps-smmu: probing hardware configuration...` (`:1733`), `SMMUv2 with:` (`:1734`), `preserved 0 boot mappings` (`:1742`) — las tres cadenas están en `palawan-linux/drivers/iommu/arm/arm-smmu/arm-smmu.c` (`:2116` es el `dev_notice`), y el módulo se carga como `arm_smmu.ko` (`:1337`) |
| `qcom,adreno-smmu` en apps-smmu | **no** (sí en kgsl-smmu: `vendor-base.dts:10954`) ⇒ nuestro `qcom_smmu_impl_init` elige impl0 (no adreno) para apps-smmu [DATO] |
| `tcu-base` | reg[1] = `0x151fe000+0x40`; mainline no lo lee (0 lectores) — queda **cubierto** por el `reg` de 2 MiB del s258 |

---

## 3. Q2 — Dispositivos con `iommus` apuntando al apps-smmu (vendor)

Tabla completa del vendor fusionado (`vendor-merged.dts`; **70 entradas con `iommus` apuntando al
apps-smmu** —incluidas las 5 de `iommu_test_device`— y 5 más al kgsl-smmu; volcado literal en
`/var/tmp/R3/vm-iommus.txt`, 76 líneas). SID en decimal y hex, `mask` tal cual (2 celdas por maestro).

### 3.1 Los que importan para pantalla/SMMU/arranque

| Dispositivo (path) | compatible | SID | mask | Nota |
|---|---|---|---|---|
| `soc/qcom,smmu_sde_unsec_cb` | `qcom,smmu_sde_unsec` | **7168 = 0x1c00** | **2** | **el IOMMU del display** (el MDP no lleva iommus) |
| `soc/qcom,smmu_sde_sec_cb` | `qcom,smmu_sde_sec` | **7169 = 0x1c01** | 0 | secure (con `qcom,iommu-vmid = <0x0a>`) |
| `soc/ufshc@1d84000` | `qcom,ufshc` | **96 = 0x60** | 0 | **UFS** (el `SMR[0]=0x80000060` vivo que mide K6); `vendor-merged.dts:15279` |
| `soc/sdhci@8804000` | `qcom,sdhci-msm-v5` | 320 = 0x140 | 0 | microSD |
| `soc/ssusb@a600000/dwc3@a600000` | `snps,dwc3` | 64 = 0x40 | 0 | USB (attach a los 9,66 s en Android) |
| `soc/qcom,qupv3_0_geni_se@ac0000` | `qcom,geni-se-qup` | 163 = 0xa3 | 0 | QUPv3 SE0 |
| `soc/qcom,qupv3_1_geni_se@8c0000` | `qcom,geni-se-qup` | 1059 = 0x423 | 0 | QUPv3 SE1 |
| `soc/qcom,gpi-dma@a00000` | `qcom,gpi-dma` | 182 = 0xb6 | 0 | GPI DMA 0 |
| `soc/qcom,gpi-dma@800000` | `qcom,gpi-dma` | 1078 = 0x436 | 0 | GPI DMA 1 |
| `soc/qcom,wcn6750` | `qcom,wcn6750` | 5120 = **0x1400** | **1** | **WiFi** (reg `0x17110040`, `smmu_iova_ipa`); `vendor-merged.dts:1195` |
| `soc/qcom,vidc@aa00000/non_secure_cb` | `qcom,vidc,cb-ns` | 6464 = 0x1940 | 0 | vídeo |
| `soc/qcom,cam_smmu/msm_cam_smmu_ife` | `qcom,msm-cam-smmu-cb` | 2048 = 0x800 | 32 | cámara |
| `soc/spf_core_platform/qcom,msm-audio-ion` | `qcom,msm-audio-ion` | 4097 = 0x1001, 4193 = 0x1061 | 128 / 0 | audio ADSP |
| `soc/qcom,ipa@3e00000/ipa_smmu_ap` | `qcom,ipa-smmu-ap-cb` | 1184 = 0x4a0 | 0 | IPA |
| `soc/qcedev@1de0000` | `qcom,qcedev` | 1152 = 0x480 (+1153/0x481, 1155/0x483 en hijos) | 0 | crypto |
| `soc/tmc@10048000` | `arm,primecell` | 1216=0x4c0, 1248=0x4e0 | 32 | coresight |
| `soc/tmc@1004f000` | `arm,primecell` | 1280 = 0x500 | 0 | coresight |
| `soc/usb_audio_qmi_dev` | `qcom,usb-audio-qmi-dev` | 4107 = 0x100b | 0 | audio USB |
| `soc/qcom,msm_fastrpc/qcom,msm_fastrpc_compute_cb1..17` | `qcom,msm-fastrpc-compute-cb` | 3073..3086 (0xc01-0xc0e), 4099..4166, 4199, 4231 | varias | ADSP/CDSP |

Análogos en nuestro árbol (mismo vendor base, los `iommus` no cambian salvo lo que añade el overlay):
**la única diferencia vendor→nosotros en la tabla de iommus es**
`diff vm-iommus.txt om-iommus.txt`:

```
> apps-smmu@15000000  soc/display-subsystem@ae00000  lbl=mdss_ml  sid=[7168,2] comp="qcom,palawan-mdss"
> kgsl-smmu@3da0000   qcom,kgsl-3d0@3d00000          lbl=msm_gpu  sid=[0,0]   comp="qcom,adreno-..."
```

Es decir: **nuestro overlay añade el `iommus` 0x1c00/0x2 al nodo del mdss** (K1/s250) y un `iommus`
al 3d0 para kgsl; nada más cambia.

**Quiénes usan `<&apps_smmu N 0>` (máscara 0) y quiénes no**: de las 70 entradas del apps-smmu, llevan
máscara ≠ 0 **solo** `qcom,smmu_sde_unsec_cb` (sid 7168, mask **2**), `qcom,wcn6750` (5120, mask **1**),
`qcom,cam_smmu:msm_cam_smmu_ife` (2048, mask **32**), los dos `tmc` de coresight (1216/1248, mask
**32**), `qcom,vidc@aa00000/secure_bitstream_cb` (6465, mask **4**), `qcom,msm-audio-ion` (4097, mask
**128**) y los `msm_fastrpc_compute_cb10..14` (4099-4103 con mask **128**, 4163-4166 con **32**, 4103 con
**64**). **El resto —incluido el UFS (0x60/0), los QUP/GPIO-DMA, IPA, vidc no-secure, cvp, qcedev,
sdhci y dwc3— usa `<&apps_smmu N 0x0>`.**

### 3.2 Orden REAL de la tormenta de attach en Android (medido)

`grep "Adding to iommu group" dmesg-android.txt` — **50 líneas, grupos 0..47** (algunos dispositivos
comparten grupo); los tres primeros y los relevantes:

| Grupo | t (s) | device | Comentario |
|---|---|---|---|
| 0 | 0,550689 | `ufshcd-qcom 1d84000.ufshc` | **+7,4 ms del bind del SMMU** |
| 1 | 0,606680 | `geni_se_qup ac0000…` | |
| 2 | 0,627985 | `geni_se_qup 8c0000…` | |
| 3 / 4 | 2,182968 / 2,504633 | `gpi_dma a00000` / `800000` | |
| 5 | 2,808144 | `qce 1de0000.qcedev` | |
| 8 | 2,839144 | `icnss2 17110040.qcom,wcn6750` | **WiFi** |
| 12/14/15 | 2,8604-2,8619 | `kgsl-iommu gfx3d_user/secure`, `gmu` | |
| 34 / 35 | 3,556829 / 3,596464 | `msm_smmu_sde_unsec_cb` / `_sec_cb` | **display** |
| 36/37 | 3,602857 / 3,610235 | `coresight-tmc` | |
| 41-45 | 3,647-3,649 | `cam_smmu_ife/jpeg/icp/cdm/cre` | |
| 46 | 7,032642 | `msm-audio-ion` | |
| 47 | **9,659966** | `dwc3 a600000.dwc3` | **USB, 9,1 s después del reset del SMMU** |

[INFERENCIA] Predicción para nuestro kernel si el bind se consigue: el orden será
`ufshc (0x60) → QUPv3/GPIO-DMA → display (0x1c00 vía mdss)`, con el attach del DPU **después** del
reset del SMMU (en Android tarda 3,0 s más). Como nuestro mdss ya está vivo (panel probado) en el
momento del bind, el attach del DPU será **el primer maestro del display** que entre en el SMMU de
nuestro kernel — y ese es el punto donde el reset con `handoff-smrs` no aplicado puede doler (§7).

---

## 4. Q3 — Cadena display: vendor vs nuestra

### 4.1 Estructura (quién es dueño de cada nodo)

| Nodo | Vendor | Nosotros |
|---|---|---|
| `qcom,mdss_mdp@ae00000` (compatible `qcom,sde-kms`) | **dueño del display**; el MDP enlaza sus componentes por `connectors = <0x6b4 0x491 0x6b6 0x6b7 0x490 0x489>` | **`status = "disabled"`** (puesto por nuestro overlay; `our-merged.dts:22007+`) |
| `display-subsystem@ae00000` | **no existe** | **nuestro nodo nuevo**, compatible `qcom,palawan-mdss` (`our-merged.dts:849`) con los dsi/phy como hijos |
| `qcom,dsi-display-primary` (`sde_dsi`) | sí (`vendor-merged.dts:971`): conectores, TE-gpio, supplies vci/vddio/vddil8b/vsp/vsn, `qcom,dsi-default-panel` | no lo usamos (el panel cuelga del `dsi@ae94000` como `panel@0`) |
| `qcom,dsi-display-secondary` | sí (`:951`, `status="disabled"`) | no |
| `qcom,mdss_dsi_ctrl0/1@ae94000/ae96000` | `qcom,dsi-ctrl-hw-v2.8` (base, `vendor-base.dts:13356/13382`; en el fusionado `vendor-merged.dts:26411/26440`) | conviven con nuestro `dsi@ae94000`/`ae96000` (`qcom,palawan-dsi-ctrl`) |
| `qcom,mdss_dsi_phy0/1@ae95500/ae97500` | `qcom,dsi-phy-v5.2` (base, `vendor-base.dts:13408/13438`; fusionado `vendor-merged.dts:26469/26503`) | conviven con nuestros `phy@ae95000/ae97000` (`qcom,palawan-dsi-phy-4nm`) |
| `smmu_sde_unsec/sec_cb` | sí (nodos componentes del MDP) | sí (heredados del base; siguen ahí, sin driver) |
| `clock-controller@af00000` (dispcc) | `qcom,cliffs-dispcc` | `qcom,palawan-dispcc` (mismo `reg`, `phandle 0x154`) |

### 4.2 MDP / DPU

| Prop | VENDOR (`vendor-merged.dts:21550+`) | NUESTRO (`our-merged.dts:849`) |
|---|---|---|
| compatible | `qcom,sde-kms` (base `:21722`) | `qcom,palawan-mdss` |
| `reg` | `<0xae00000 0x84000 0xaeb0000 0x2008 0xaf80000 0x7000 0x400000 0x2000>` | `<0xae00000 0x1000>` |
| `reg-names` | `"mdp_phys","vbif_phys","regdma_phys","ipcc_reg"` | `"mdss"` |
| `interrupts` | `<0x00 0x53 0x04>` | `<0x00 0x53 0x04>` (igual) |
| `interrupt-controller` / `#interrupt-cells` | sí / 1 | sí / 1 (igual) |
| `clocks` / `clock-names` | `<0x16e 0x15 0x154 0x02 0x154 0x3d 0x154 0x3e 0x154 0x49 0x154 0x40>` / `"gcc_bus","iface_clk","branch_clk","core_clk","vsync_clk","lut_clk"` (**6**) | `<0x154 0x02 0x16e 0x15 0x154 0x3d>` / (sin names) (**3**) |
| `power-domains` / `resets` | **AUSENTES** | `<0x154 0x00>` / `<0x154 0x00>` |
| `interconnects` | 3 buses (`qcom,sde-data-bus0`,`ebi`,`reg`) | 1 (`mdp0-mem`) |
| `iommus` | **AUSENTE** (usa `qti,smmu-proxy-cb-id = <0x01>` + nodo `smmu_sde_unsec_cb`) | **`<0x129 0x1c00 0x02>`** |
| `mmcx-supply` | `<0x149>` + `qcom,platform-supply-entries` (mmcx) | **AUSENTE** |
| `qcom,sde-secure-sid-mask` | `<0x1c01>` | AUSENTE (mainline lo deduce del domain secure) |
| `connectors` | 6 phandles (dsi-display-primary, smmu_sde_unsec, wb1, wb2, rscc, dp) | AUSENTE (mainline usa `of_graph`) |
| props `qcom,sde-*` | ~200 (líneas 21554-21720: `qcom,sde-has-idle-pc`, `-has-cdp`, `-has-qspll`, `-ubwc-version`, `-mixer-off`, `-vig-*`, `-scale-*`, `-qos-*`, `-vbif-*`, …) | **AUSENTE** (nuestro driver no las lee) |

[HECHO] **De las ~200 `qcom,sde-*` del vendor, mainline no lee ninguna** (su driver tiene las suyas
fijas por revisión HW; en nuestra consola el `sde hardware revision:0xa0010000` del vendor
(`:4599`) es lo que el mainline también lee del registro REV). [INFERENCIA] No son portables ni
necesarias; sirven solo como inventario de features (7 mixers, 4 dram-channels, WB1/WB2, dest-scaler,
CDP, idle-pc, regdma 0x30000, ubwc 0x40030001, LTM/SPR/DEMURA).

### 4.3 DSI ctrl + PHY

| Prop | VENDOR `qcom,mdss_dsi_ctrl0@ae94000` (base, `vendor-base.dts:13356`) | NUESTRO `dsi@ae94000` (`our-merged.dts:938`) |
|---|---|---|
| compatible | `qcom,dsi-ctrl-hw-v2.8` | `qcom,palawan-dsi-ctrl`, `qcom,mdss-dsi-ctrl` |
| reg / reg-names | `<0xae94000 0x1000 0xaf0f000 0x04 0xae36000 0x300>` / `"dsi_ctrl","disp_cc_base","mdp_intf_base"` | `<0xae94000 0x400>` / `"dsi_ctrl"` |
| clocks / names | 7: `<0x154 0x04 0x154 0x05 0x154 0x07 0x154 0x42 0x154 0x43 0x154 0x38 0x16c 0x00>` / `byte_clk,byte_clk_rcg,byte_intf_clk,pixel_clk,pixel_clk_rcg,esc_clk,xo` | 6: `<0x154 0x04 0x154 0x07 0x154 0x42 0x154 0x38 0x154 0x02 0x16e 0x15>` / `byte,byte_intf,pixel,core,iface,bus` |
| interrupts | `interrupts = <0x04 0x00>; interrupt-parent = <&mdss_mdp>` | `interrupts-extended = <0x6f7 0x04>` (mdss nuestro como interrupt-controller) |
| supply | `vdda-1p2-supply = <0x14e>` + `qcom,ctrl-supply-entry@0` (1.2 V, load 0x40d8) | `vdda-supply = <0x14e>` |
| otros | `frame-threshold-time-us = <0x320>`, `cell-index`, `label` | `assigned-clocks/parents` (los PLL parents), `qcom,master-dsi`, `qcom,dual-dsi-mode`, `qcom,sync-dual-dsi`, `phys`, `phy-names`, `operating-points-v2` (opp 187.5/300/358 MHz) |

| Prop | VENDOR `qcom,mdss_dsi_phy0@ae95500` (base, `vendor-base.dts:13408`) | NUESTRO `phy@ae95000` (`our-merged.dts:925`) |
|---|---|---|
| compatible | `qcom,dsi-phy-v5.2` | `qcom,palawan-dsi-phy-4nm`, `qcom,sm8650-dsi-phy-4nm` |
| reg / reg-names | `<0xae95000 0xa00 0xae95500 0x400 0xae94200 0xa0>` / `"dsi_phy","pll_base","dyn_refresh_base"` | `<0xae95000 0x200 0xae95200 0x280 0xae95500 0x400>` / `"dsi_phy","dsi_phy_lane","dsi_pll"` |
| supply | `vdda-0p9-supply = <0x14d>` + supply-entry (0.9 V) | `vdds-supply = <0x14d>` |
| clocks | (implícitos vía `#clock-cells` y `pll-label`) | `<0x154 0x02 0x16c 0x00>` / `"iface","ref"` |
| **props que NO tenemos** | `qcom,dsi-pll-ssc-disable`, `qcom,dsi-pll-ssc-en`, `qcom,dsi-pll-ssc-mode = "down-spread"`, `qcom,panel-allow-phy-poweroff`, `qcom,platform-lane-config = [a0a a0a a0a a0a 8a8a]`, `qcom,platform-strength-ctrl = [55 03 ×4 55 00]`, `qcom,platform-regulator-settings = [1d ×5]`, `pll-label = "dsi_pll_4nm"`, `pll_codes_region = <0x487>`, `cell-index`, `label` | — |

[INFERENCIA] De todas ellas, **el driver mainline `dsi_phy_4nm` no lee ninguna** (no hay
`of_property_read_*` para `platform-lane-config`, `platform-strength-ctrl`,
`platform-regulator-settings`, `pll_codes_region` ni `panel-allow-phy-poweroff` en
`palawan-linux/drivers/gpu/drm/msm/dsi/phy/`; solo `vdds-supply`, `clocks`, `reg`). Las lane-config
del vendor son *los mismos valores que el driver mainline escribe por hardware* (tabla de
`dsi_phy_4nm`), así que no faltan datos: mainline los tiene horneados. `pll_codes_region` sí es un
mecanismo vendor (códigos de PLL en una reserved-memory, nodo `dsi_pll_codes_data`
`vendor-merged.dts:6854`) que mainline sustituye por constantes.

### 4.4 Panel (el dato que más importa): VENDOR O82 42 02 0b vs nuestro `panel@0`

Panel vendor (fragment@95 del dtbo real de la tablet, `dtbo_b-actual.dts:11517-11747`):

```dts
qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid {
    qcom,mdss-dsi-panel-name = "xiaomi o82 42 02 0b vid mode dualdsi dsc panel";
    qcom,mdss-dsi-panel-type = "dsi_video_mode";
    qcom,dsi-ctrl-num = <0x00 0x01>;      qcom,dsi-phy-num = <0x00 0x01>;   /* dual DSI */
    qcom,panel-supply-entries = <0x18b>;              /* vddil8b 1.9V + vsp/vsn 5.8V */
    qcom,mdss-dsi-bl-pmic-control-type = "bl_ctrl_external";   /* LCD: sin brillo por DCS */
    qcom,mdss-dsi-bl-min-level = <0x04>;  qcom,mdss-dsi-bl-max-level = <0xfff>;
    qcom,mdss-brightness-max-level = <0xfff>;  qcom,mdss-brightness-init-level = <0x133>;
    qcom,platform-reset-gpio = <&tlmm 0x02 0x00>;             /* TLMM gpio 2, ACTIVE_HIGH */
    mi,esd-err-irq-gpio = <&tlmm 0xa8 0x2004>;  mi,esd-err-irq-gpio-second = <&tlmm 0xa9 0x2004>;
    mi,panel-id = <0x004f3832 0x5042020b>;
    qcom,mdss-dsi-panel-width = <0x640>;  qcom,mdss-dsi-panel-height = <0x858>;   /* 1600×2136 por DSI */
    qcom,mdss-dsi-panel-framerate = <0x78>;                    /* 120 Hz por defecto */
    qcom,mdss-dsi-bpp = <0x1e>;                                /* 30 bpp */
    qcom,mdss-dsi-panel-clockrate = <0x46e19970>;
    qcom,mdss-dsi-reset-sequence = <0 10 1 3 0 3 1 15>;        /* ms */
    qcom,compression-mode = "dsc";
    qcom,mdss-dsi-traffic-mode = "non_burst_sync_event";
    /* 3 timings: @120 (hfp 0x71) / @144 (hfp 0x12) / @90 (hfp 0x130); 4 lanes (lane-0..3-state) */
    /* + HDR: primaries, peak 0x401640, blackness 0xc9e */
    /* + commands on/off (los binarios), status check reg_read 0x0a → 0x1c */
};
```

Nuestro `panel@0` (`our-merged.dts:976-1009`) — **todo lo que declaramos**:

```dts
panel@0 {
    pinctrl-1 = <0x701>;  pinctrl-0 = <0x700>;  pinctrl-names = "sleep";   /* s258: sin "default" */
    reset-gpios = <0x16b 0x02 0x01>;      /* TLMM 2, ACTIVE_LOW (el driver lo sube/baja a mano) */
    vsn-supply = <0x6ff>;   vsp-supply = <0x6fe>;   vddil8b-supply = <0x14f>;
    reg = <0x00>;
    compatible = "xiaomi,uke-o82-4202-0b";
    ports { port@0 { panel_in_0: endpoint { remote-endpoint = <0x702>; }; };
            port@1 { panel_in_1: endpoint { remote-endpoint = <0x703>; }; }; };
};
```

Con `uke_panel_vsp/vsn` = `regulator-fixed` con `gpio = <&tlmm 0x4a/0x4b 0>` (74/75), 5.8 V,
`regulator-boot-on`, `enable-active-high`, ramp 0xe9 (`our-merged.dts:1093-1109`). El vendor tiene los
mismos GPIOs en `display_gpio_regulator_vsp/vsn` (`vendor-merged.dts:864/876`) **pero con
`status = "disabled"`** (nuestro overlay no: son otros nodos nuestros, los vendor quedan disabled).

**Props vendor que NO tenemos y veredicto del driver mainline** (leído en
`palawan-linux/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`):

| Prop vendor | ¿La necesita el driver mainline? | Evidencia |
|---|---|---|
| `vddil8b-supply`, `vsp-supply`, `vsn-supply` | **SÍ** (obligatorias: `devm_regulator_bulk_get_const` con `o82_supplies[]`, `panel-xiaomi-o82-dualdsi.c:78-81,586-589`) | las tenemos |
| `reset-gpios` | **SÍ** (`devm_gpiod_get(dev,"reset",…)`, `:591`) | la tenemos |
| `qcom,mdss-dsi-panel-width/height`, framerate, timings | **NO** (van horneadas: `o82_modes[3]`, `:485`) | — |
| `qcom,mdss-dsi-reset-sequence` | **NO** (el driver tiene su propia secuencia, `:254-260`) | — |
| `qcom,mdss-dsi-on-command/off` | **NO** (los 998 B del vendor están en `o82_init_cmds[]`, `:88+`) | — |
| `qcom,mdss-dsi-bl-pmic-control-type = "bl_ctrl_external"`, bl-min/max, brightness-init | **NO** (registra su propio `backlight_device`, `:458-469`) | — |
| `qcom,panel-supply-entries` (con sus voltajes/loads) | **NO** (mainline usa `*-supply` + el regulador; los voltajes 1.9/5.8 V los fija el regulador) | — |
| `qcom,dsi-ctrl-num`/`qcom,dsi-phy-num` = `<0 1>` | **NO** (mainline descubre el segundo DSI por el `ports`/`phys`) | — |
| `mi,panel-id`, `mi,esd-err-irq-gpio*`, `qcom,mdss-dsi-panel-status-*`, `qcom,demura-panel-id`, `qcom,dsi-select-clocks`, `qcom,spr-pack-type`, HDR primaries | **NO** (mecanismos MI/vendor) | — |
| `qcom,platform-te-gpio` (TLMM 0x4d=77 primary / 0x4e=78 secondary) + pinctrl `panel_active/panel_suspend` | **NO en el panel**; en mainline el TE se declara en el DSI ctrl si se usa (`qcom,te-gpio`) — hoy no lo usamos | — |
| `qcom,mdss-dsi-panel-physical-type`, `mi,panel-3840pwm-dbv-threshold`, `mi,panel-on-dimming-delay`, etc. | **NO** | — |
| `disp_rdump_region@e3940000` (14 MB de reserved-memory para volcado del display) | **NO** (es del `dump_display` vendor); **ojo**: nuestra cmdline ya reserva `memmap=0x1A12800$0xE3940000` (K5) | — |

⚠️ **Un faltante real**: el nodo `panel@0` **no declara `qcom,dsi-lane-*`/lanes ni los regulators del
connector** (`vci`/`vddio` = L19B/L8B en el vendor, `vendor-merged.dts:983-987`). El driver mainline no
los pide, pero conviene saber que el vendor sí los usa para el "connector" (dos raíles de 1.8/3.0 V que
en mainline el propio panel maneja vía `vddil8b`). [NO VERIFICADO] si la ausencia de `vci` cambia algo
en runtime.

### 4.5 dispcc

| Prop | VENDOR (`vendor-merged.dts:14038`) | NUESTRO (`our-merged.dts:14384`) |
|---|---|---|
| compatible | `qcom,cliffs-dispcc`, `syscon` | `qcom,palawan-dispcc` |
| reg | `<0xaf00000 0x20000>` | igual |
| clocks / names | `<0x16c 0x00 0x16c 0x01 0x16d 0x16e 0x14>` / `bi_tcxo,bi_tcxo_ao,sleep_clk,iface` (**4**) | `bi_tcxo,bi_tcxo_ao,sleep_clk,iface` + los **4** parents de los bytes/pixel de los dos PHY (`0x6f5 0x00/0x01`, `0x6f6 0x00/0x01` y ceros) |
| `#power-domain-cells` | **AUSENTE** | `<0x01>` (mainline lo exige) |
| `#clock-cells` / `#reset-cells` | 1 / 1 | 1 / 1 |
| `protected-clocks` | AUSENTE | AUSENTE |

[INFERENCIA] El vendor no necesita los parents del PHY en dispcc porque su driver de phy registra los
clocks por otra vía; en mainline los `assigned-clock-parents`/`clocks` del `dsi@ae94000` apuntan a
`&phy` y el DT **debe** declarar esos parents en el clock controller. Ya lo tenemos resuelto (s253+
`mkdtbo-s253.py` lo documenta).

### 4.6 Dato de contexto: el splash lo dibuja el ABL y el vendor tampoco lo rompe

- Vendor: `sde_rsc` probe 2,9257 s (`:3943`), msm_drm `Initialized msm_drm 1.4.0 … minor 0` 3,6876 s
  (`:4634`), y **primer DPMS a los 10,4983 s** (`:9685`, `power mode 1->2, fps 0->120`) ⇒ la pantalla
  está encendida desde el ABL (splash continuo) y Android no la toca hasta el UI.
- Nuestro `s258` está en el mismo punto (panel vivo, ABL splash) — coherente.

---

## 5. Q4 — Timeline del dmesg Android (pantalla + SMMU)

### 5.1 Tabla de eventos (todo literal, `dmesg-android.txt`)

| t (s) | Línea | Evento |
|---|---|---|
| 0,094035 | 868 | `iommu: Default domain type: Translated` |
| 0,410972 | 1337 | `init: Loading module /lib/modules/arm_smmu.ko` |
| 0,415184 → 0,542321 | 1361…1731 | **19×** `platform 16f1000.anoc_1_qtb: TBU failed probe, QSMMUV500 cannot continue!` |
| 0,485983 / 0,487986 | 1458 / 1478 | carga `dispcc-pineapple.ko` / `dispcc-volcano.ko` (0,487907 / 0,489381 "Loaded") |
| 0,520368-0,520480 | 1573-1575 | `spmi spmi-0: pmic_arb_wait_for_done: 0xd 0x104: transaction failed (0x3)` + `WARNING … spmi-pmic-arb.c:308` (único WARN del arranque dorado) |
| 0,540668-0,542801 | 1717-1732 | los 8 TBU: `qsmmuv500-tbu <addr>.<qtb>: Unable to get the transactiontracker-base` |
| **0,543250** | **1733** | **`arm-smmu 15000000.apps-smmu: probing hardware configuration...`** |
| 0,543252-0,543383 | 1734-1740 | `SMMUv2 with:` / `stage 1 translation` / `coherent table walk` / `stream matching with 110 register groups` / **`71 context banks (0 stage-2 only)`** / `Supported page sizes: 0x61311000` / `Stage-1: 36-bit VA -> 36-bit IPA` |
| 0,545726 | 1742 | `preserved 0 boot mappings` (fin del camino de reset; ver §5.3) |
| **0,550689** | **1743** | **`ufshcd-qcom 1d84000.ufshc: Adding to iommu group 0`** (+7,4 ms) |
| 0,552777-0,553564 | 1744-1748 | ufshcd vregs (`unable to find vdd-hba-max-microamp`, `Unable to find vccq2-supply regulator, assuming enabled`), `Found QC Inline Crypto Engine (ICE) v4.0.2` |
| 0,606680 / 0,627985 | 1775 / 1777 | geni_se_qup grupos 1 y 2 |
| 1,291107-1,291110 | 1955-1959 | `ufs_ffu firmware is already the newest now` (×3) + `match vendor:SKhynix , product id:HN8T05DEHKX073` |
| 2,182968 / 2,504633 | 3017 / 3160 | gpi_dma grupos 3/4 |
| 2,925735 | 3943 | `[sde_rsc_hw:rsc_hw_init_v3:545]: sde rsc init successfully done` |
| 3,556829 / 3,596464 | 4324 / 4341 | **`msmdrm_smmu soc:qcom,smmu_sde_unsec_cb: Adding to iommu group 34`** / `…_sec_cb … group 35` |
| 3,596133 / 3,596151 | 4339-4340 | `[drm] probing device qcom,smmu_sde_unsec` / `[drm] Created domain mdp_ns, secure=0` |
| 3,626799 | 4374 | `spi_geni a90000.spi: Failed to create device link (0x180) with ae00000.qcom,mdss_mdp` |
| 3,631167 / 3,632346 | 4403 / 4414 | `dsi_phy ae95000.qcom,mdss_dsi_phy0: supply gdsc not found, using dummy regulator` → `DSI_0: Probe successful` |
| 3,632948 / 3,633927 | 4424 / 4432 | phy1 (`ae97000`) → `DSI_1: Probe successful` |
| 3,637276 / 3,637896 | 4437 / 4439 | `dsi-ctrl-0: Probe successful` / `dsi-ctrl-1: Probe successful` |
| 3,639844 | 4444 | `OF: graph: no port node found in /soc/qcom,dsi-display-primary` |
| 3,639883-3,641 | 4445+ | `[xiaomi o82 42 02 0b vid mode dualdsi dsc panel] fallback to default te-pin-select` / `clk_strength = 255` / `mi-video-mode-multi-timing: 1` / `num_video_modes:3` |
| **3,662008** | **4560** | **`dsi_display_bind: Successfully bind display panel 'qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid'`** |
| 3,664769-3,665801 | 4572-4599 | `msm_drm ae00000.qcom,mdss_mdp: bound soc:qcom,dsi-display-primary (ops dsi_display_comp_ops)` / `… bound soc:qcom,smmu_sde_unsec_cb` / wb1 / wb2 / rscc / dp_display |
| 3,667127 | 4599 | `sde hardware revision:0xa0010000` |
| 3,687583 | 4634 | `[drm] Initialized msm_drm 1.4.0 20130625 for ae00000.qcom,mdss_mdp on minor 0` |
| **10,498275** | **9685** | **primer DPMS (`conn67 early_trigger:1 (power mode 1->2, fps 0->120)`)** = primer frame del UI |
| 10,536165 / 11,808 / 19,675 / 20,818 … | 9715+ | cambios de refresh 144/120/50 (uso normal) |
| 26,102584 | 11362 | `project o81/o82 panel is LCD, skip mipi_dsi_dcs_set_display_brightness` |

(SMMU del GPU, aparte: `qsmmuv500-tbu 3de8000.gpu_qtb: Unable to get…` 2,221651 y
`arm-smmu 3da0000.kgsl-smmu: … 22 context banks … 48-bit VA` 2,222449-2,222849, `:3042-3052`.)

### 5.2 TODO lo que el dmesg Android dice del apps-smmu (literal)

```
[    0.543250] arm-smmu 15000000.apps-smmu: probing hardware configuration...
[    0.543252] arm-smmu 15000000.apps-smmu: SMMUv2 with:
[    0.543281] arm-smmu 15000000.apps-smmu: 	stage 1 translation
[    0.543282] arm-smmu 15000000.apps-smmu: 	coherent table walk
[    0.543284] arm-smmu 15000000.apps-smmu: 	stream matching with 110 register groups
[    0.543304] arm-smmu 15000000.apps-smmu: 	71 context banks (0 stage-2 only)
[    0.543382] arm-smmu 15000000.apps-smmu: 	Supported page sizes: 0x61311000
[    0.543383] arm-smmu 15000000.apps-smmu: 	Stage-1: 36-bit VA -> 36-bit IPA
[    0.545726] arm-smmu 15000000.apps-smmu: 	preserved 0 boot mappings
```
No hay **ninguna otra** línea `arm-smmu …apps-smmu` en todo el dmesg (18 ocurrencias de `arm-smmu` =
9 de apps-smmu + 9 de kgsl). **No hay aviso de "address space size differs"** (ver §5.3).
### 5.3 ¿Android resetea el SMMU o lo hereda? — [DATO] + [INFERENCIA]

- **[DATO]** El mensaje `preserved N boot mappings` **solo lo emite `arm_smmu_rmr_install_bypass_smr()`
  (`palawan-linux/arm-smmu.c:2073-2117`)**, que cuenta los SIDs de los *IORT RMR* (no lee SMRs del
  hardware) y que en nuestra kernel-pokes se llama inmediatamente **antes** de
  `arm_smmu_device_reset(smmu)` (`arm-smmu.c:2279-2281`). Que el dmesg del vendor lo imprima significa
  que el driver vendor comparte ese camino ⇒ **a los 0,5457 s corrió el reset completo**
  (SMR/S2CR ×110, CBAR/SCTLR/FSR ×71, TLBIALLH, RMW de sCR0, `arm_mmu500_reset`).
- **[DATO]** **No aparece el aviso** `SMMU address space size (…) differs from mapped region size (…)`
  (que mainline emite en `cfg_probe`, `arm-smmu.c:1853-1856`) entre `stream matching…` (`:1737`) y
  `71 context banks` (`:1738`). Con el `reg[0]` del vendor = `0x100000`, la igualdad
  `numpage == 2*size<<pgshift` ⇒ **`size = 0x80000` (128 páginas de 4 KiB), NUMPAGENDXB=6**.
  **[DATO] Confirmado en nuestro lado**: `out/k6-migas.log:2188`
  `cfg_probe ID1=0x60000047 pgshift=12 NUMPAGENDXB=6 CBs=71; CB base=0x80000 (mmio=2097152 B)` y
  `:2189` el aviso (porque nuestro s258 mapea 2 MiB).
- **[INFERENCIA]** ⇒ **el reset del ABL no es el problema** (Android lo hace, con el `SMR[0]=0x60` del
  UFS escrito por el ABL todavía vivo, y sobrevive) y **la hipótesis A′ de la ventana de `reg` está
  muerta**: CB base = `base+0x80000` cae dentro del mapeo de 1 MiB y de 2 MiB; el aviso que A′ usaba de
  discriminador **ya lo tenemos respondido** (NUMPAGENDXB=6 ⇒ 1 MiB es la ventana *correcta*, 2 MiB es
  sobre-dimensionada). Lo que queda en pie es la **ventana temporal** (#P16) y el estado del USB/dwc3
  del bootloader (§7).

### 5.4 Qué driver es (nombre exacto)

| Pregunta | Respuesta con evidencia |
|---|---|
| Nombre del driver | **`arm-smmu`** (módulo `arm_smmu.ko`) — prefijo de log `arm-smmu` y carga `init: Loading module /lib/modules/arm_smmu.ko` (`:1337`) |
| ¿es `arm-smmu-qcom`? | Sí en cuanto a impl: el módulo vendor contiene `drivers/iommu/arm/arm-smmu/arm-smmu.c`, `…/arm-smmu-qcom.c`, `…/arm-smmu-qcom-pm.c`, símbolos `qsmmuv500_cfg_probe/impl_init/def_domain_type`, `qcom_smmu_write_s2cr`, `qcom_adreno_smmu_*` (strings de `~/root_nothing2/vb/lib/modules/arm_smmu.ko`) [familia; el .ko de uke no está en disco] |
| ¿`qcom-adreno-smmu`? | Solo para kgsl (`kgsl-smmu@3da0000` = `qcom,qsmmu-v500`,`qcom,adreno-smmu`); apps-smmu **no** lleva `qcom,adreno-smmu` |
| Params del módulo (vendor) | `force_stage`, `disable_bypass` (mismos que mainline: `parm=…`, `parmtype=…` en los strings) |
| Diferencia funcional con mainline que **sí** vemos en uke | El vendor tiene driver para los hijos TBU (`qsmmuv500-tbu`: `TBU failed probe, QSMMUV500 cannot continue!`, `Unable to get the transactiontracker-base`) — **nuestro kernel no tiene ni la cadena** (grep 0) ⇒ el vendor tiene mecanismos extra (TBU halting, `qcom,opt-out-tbu-halting`, `handoff-smrs`) que nosotros no |

[INFERENCIA] En uke el driver TBU **falla** (los 8 hijos: `Unable to get the transactiontracker-base`)
y aun así el apps-smmu bindea y Android funciona ⇒ los TBU son **inertes en la práctica** (confirma la
decisión R-27 de no borrarlos) y el *halting* de TBU no parece ser requisito para el bind.

---

## 6. Q5 — Extras del vendor para el resto del proyecto

### 6.1 Batería / carga (`dtbo_b-actual.dts`/`vendor-merged.dts:15778-15845`)

| Nodo | compatible | Evidencia / props clave |
|---|---|---|
| `qcom,pmic_glink` | `qcom,pmic-glink` | `qcom,pmic-glink-channel = "PMIC_RTR_ADSP_APPS"`, `qcom,protection-domain = "tms/servreg","msm/adsp/charger_pd"` |
| `qcom,battery_charger` (hijo) | `qcom,battery-charger` | `mi,thermal = "8200,7200,6800,6400,6000,5600,5200,4800,4400,3300,2600,2200,1900,1500,500,300"`, `mi,temp_term_curr = "15,35,3390,35,48,4820,"`, `mi,temp_term_curr_cn_sunwoda`, `mi,temp_term_curr_cn_nvt`, `mi,cycle_step_curr`, `mi,cycle_volt`, `mi,support-ut-test`, `mi,support-shutdown-delay`, `qcom,shutdown-voltage = <0xc4e>` (3150 mV), `qcom,thermal-mitigation-step = <0x7a120>` |
| `charger_partition` | `xiaomi,charger_partition` | nodo hijo del pmic_glink |
| `qcom,battery_debug` | `qcom,battery-debug` | en `qcom,pmic_glink_log` |
| `qcom,charger_ulog_glink` | `qcom,charger-ulog-glink` | idem |
| `smb1393@34/@35` | `qcom,i2c-pmic` | en `pmic_glink_debug/i2c@101` → cargadores de carga rápida (CP) |
| Driver / módulos Android | `qti_battery_charger` (`dmesg:8550` `battery_chg probe start`, `:8587` done a los 8,7 s), `charger-ulog-glink.ko`, `charger_partition.ko`, `bcl_soc.ko` (radios) | `BATTERY_CHG:` uevents con `soc:57`, `v=3936`, `pen_hall3/4`, `pen_soc`, `quick_charge_type`, `shutdown_delay` (`:8592-8626`) |

Ficheros de firmware: **ninguno** (todo por QMI/ADSP + `pm7550ba`).

### 6.2 Sensores

**No hay nodos I2C de accel/gyro/luz.** El sensor core es del ADSP:
`qmi-ts-sensors` (`compatible = "qcom,qmi-sensors"`, `vendor-merged.dts:18321`) + `fastrpc` con
`pdr_add_lookup … msm/adsp/sensor_pd` (`dmesg:3624`, `:3679` `sensors_pdr_adsprpc`).
[INFERENCIA] Para mainline no hay "sensors DT" que portar: haría falta el stack SLPI/SEE (fuera de
alcance). Lo único relacionado: el **táctil NVT** lee el `lcd_id` (`novatek,lcd_id-gpio`) y el driver
MI usa `mi,panel-id` para elegir panel.

### 6.3 WiFi WCN6750 (sin PCIe)

| Dato | Valor | Evidencia |
|---|---|---|
| Nodo | `soc/qcom,wcn6750` (label `icnss2`) | `vendor-merged.dts:1190` |
| compatible | `qcom,wcn6750` | idem |
| reg / reg-names | `<0x17110040 0x00 0xc0000000 0x10000>` / `msi_addr`, `smmu_iova_ipa` | idem |
| iommus | `<0x129 0x1400 0x01>` (**SID 0x1400/1**) | idem |
| rproc | `qcom,rproc-handle = <&wpss>` (0x3be) → `9bb00000.remoteproc-wpss` (`dmesg:3552`, `wpss_region@9bb00000` 25600 KiB) | idem |
| supplies | `vdd-cx-mx`, `vdd-1.8-xo`, `vdd-1.3-rfa` (+ configs) | idem |
| FW que carga Android | `qca6750/bd_o82gl.elf`, `qca6750/regdb_xiaomi.bin`, `qca6750/qdss_trace_config.cfg`; rutas buscadas en orden: `/vendor/firmware_mnt/image`, `…/image/kiwi`, `/vendor/firmware`, `/vendor/firmware/wlan/qca_cld/kiwi_v2` (`dmesg:160`, `:7618-7716`) | WLAN FW init OK a los 6,404 s (`:7712`) |
| PCIe | **`qcom,pcie@1c00000` = `status="disabled"`** y `qcom,pcie0_msi@0x17110040` también; **0 líneas `pci-msm`** en el dmesg. Aun así el nodo (deshabilitado) trae `iommu-map = <0x00 0x129 0x1400 0x01 0x100 0x129 0x1401 0x01>` (`vendor-merged.dts:17812`): RID PCIe 0→SID **0x1400**, RID 0x100→**0x1401** | `vendor-merged.dts` (nodos), `grep pci dmesg` = 2 matches, ambos de cmdline/rproc |
| Módulos | `icnss2.ko`(+`cnss2.ko` en el ODM), `qmi_helpers`, `cfg80211` | `dmesg:3697-3754`, `INDEX-vendor_dlkm_ko.txt` |

### 6.4 Bluetooth

| Dato | Valor | Evidencia |
|---|---|---|
| Nodo | `bluetooth: bt_wcn6750` | `vendor-merged.dts:26910` |
| compatible | `qcom,wcn6750-bt` | idem |
| GPIOs | `qcom,bt-reset-gpio = <&tlmm 0x9c 0>` (156), `qcom,bt-sw-ctrl-gpio = <&tlmm 0x50 0>` (80), `qcom,wl-reset-gpio = <&tlmm 0x23 0>` (35), `mpm_wake_set_gpios = <0x50>` | idem |
| Sufijo FW | `bt_wcn6750` está en el overlay → FW en partición `bluetooth_a` montada en `/vendor/bt_firmware` (`dmesg:4186-4190`) | — |
| Transporte | SLIMbus (`slim@6C40000/ngd@1/btfmslim-driver`, `slim217,221`, `vendor-merged.dts:6873/6892/6898`) + `btpower.ko`/`bt_fm_slim.ko` | `vendor-merged.dts:26910`, `INDEX-vendor_dlkm_ko.txt` |
| Ficheros concretos | `hci_qca`/BT QCA **no aparecen** en el dmesg (el stack BT se levanta en userspace: `bluetooth.ko`, `btbcm.ko`, `hci` `dmesg:2805-2843`) | [NO VERIFICADO] los `.bin` de BT no se dejan ver en kmsg |

### 6.5 Audio

| Dato | Valor | Evidencia |
|---|---|---|
| Sound card | nodo `sound` (label `pineapple_snd`), `compatible = "qcom,pineapple-asoc-snd"`, `qcom,model = "cliffs-mtp-snd-card"` | `vendor-merged.dts:21383`, `dtbo_b-actual.dts:6491` |
| Codecs | `wcd939x-codec` (`qcom,wcd939x-codec`) y `wcd937x-codec`; slaves SWR `wcd939x-tx/rx-slave`, `wcd937x-*` | `vendor-merged.dts` (lpass-cdc) |
| Amps | **4× `foursemi,fs16xx`** en `i2c@88c000` (addrs 0x34-0x37) + `wsa884x`/`wsa883x` en WSA SWR (`swr0`) + `qcom,pm8550b-swr-haptics` | idem |
| Módulos de audio (stock/modules) | `aw882xx_dlkm.ko`, `cs35l41_dlkm.ko`, `fs19xx_dlkm.ko`, `adsp_loader_dlkm.ko`, `q6_pdr_dlkm.ko` | `~/proyectos/ubuntu-uke/stock/modules/` (ojo: vermagic **6.1.68**, distinto del Android 6.1.138 del dmesg) |
| Firmware ADSP | `adsp.mdt` (rproc0, `dmesg:6568`), `cdsp.mdt` (rproc1), `wpss` (rproc2) — rutas `firmware_class.path` | `dmesg:160`, `:6567-6585` |
| Nodo I2C USB-C | `wcd939x_i2c@e` (`qcom,wcd939x-i2c`) en `i2c@a80000` | `vendor-merged.dts` |

### 6.6 Periféricos I2C/SPI (mapa para otros agentes)

| Bus | Nodo | compatible | Nota |
|---|---|---|---|
| `spi@a90000` (QUP 0.9) | `novatek@0` | `novatek,NVT-ts-spi` | **táctil**; `novatek,irq-gpio`, `novatek,lcd_id-gpio`; fichero FW `novatek_nt36532_o82_fw_csot.bin` (`dmesg:10704-10733`) |
| `i2c@88c000` (QUP 1.x) | `fs19xx_smartpa@34..37` | `foursemi,fs16xx` | amplificadores |
| `i2c@890000` | `ntag@57` | `fm,fm19511` | NFC |
| `i2c@a8c000` | `nanosic@4c` | `nanosic,803` | teclado pogo (hall) |
| `i2c@a80000` | `wcd939x_i2c@e` | `qcom,wcd939x-i2c` | USB-C SBU/audio |
| varios | `xiaomi_fingerprint` | `xiaomi,xiaomi-fp` | huella |
| varios | `xiaomi_touch` / `xiaomi_hall` | `xiaomi-touch` / `xiaomi-hall` | wrappers MI |
| PMIC I2C | `qcom,smb1393@34/35` | `qcom,i2c-pmic` | carga rápida |

### 6.7 Módulos y FW: tabla resumen

| Subsistema | Driver Android | Firmware que carga |
|---|---|---|
| SMMU apps+kgsl | `arm_smmu.ko` (impl qcom) | — |
| UFS | `ufs_qcom` + `phy_qcom_ufs*` + `cqhci` | `ufs_ffu` (dice "already the newest") |
| Display | `dispcc-pineapple.ko`, `dispcc-volcano.ko`, `msm_drm.ko` (GKI vendor_dlkm) + `panel_event_notifier.ko` | — (los `on-command` van en DT) |
| Táctil | `nt36532_touch.ko` / `xiaomi_touch.ko` | `novatek_nt36532_o82_fw_csot.bin` (en `/odm/firmware`) |
| WiFi | `icnss2`/`cnss2` | `qca6750/bd_o82gl.elf`, `qca6750/regdb_xiaomi.bin`, `qca6750/qdss_trace_config.cfg` |
| Audio | `adsp_loader_dlkm`, `fs19xx_dlkm`, `aw882xx_dlkm`, `cs35l41_dlkm`, `q6_pdr_dlkm` | `adsp.mdt`, `cdsp.mdt`, `vpu30_2v.mbn` (venc), `cpusys_vm.mdt` (Gunyah) |
| Carga | `qti_battery_charger` (built-in), `charger-ulog-glink.ko`, `charger_partition.ko`, `bcl_soc.ko` | — |
| Vídeo | `msm_vidc` | `vpu30_2v.mbn` |

---

## 7. Q6 — Contradicciones explícitas con lo que creíamos

| # | Lo que decíamos (fuente) | Lo que dice el vendor (evidencia) | Consecuencia |
|---|---|---|---|
| 1 | «`qcom,handoff-smrs` … **0 lectores (en mainline y en vendor)**» (`INFORME-SMMU-CLK.md:136`; `INFORME-A-PRIMA.md:246`) | El módulo vendor de la familia contiene **la cadena `qcom,handoff-smrs` y el símbolo `arm_smmu_handoff_cbs`** (`~/root_nothing2/vb/lib/modules/arm_smmu.ko`, vermagic 5.10.237-gki, otro aparato QC con el mismo fork); el dmesg de uke prueba que **su** kernel trae la maquinaria qsmmuv500 (`TBU failed probe, QSMMUV500 cannot continue!`, cadena ausente en `palawan-linux`) | La afirmación «0 lectores **en vendor**» es **falsa**. Implementar `handoff-smrs` en nuestro kernel deja de ser especulación: es replicar comportamiento observado. El SID `<0x1c00 0x02>` es **exactamente el del display** (`smmu_sde_unsec_cb`) |
| 2 | «Si el hardware reporta `size=0x100000`, el CB base cae **fuera** del mapeo de 1 MiB ⇒ wedge» (hipótesis A′ de `mkdtbo-s253.py`, `INFORME-A-PRIMA`) | [DATO] nuestro propio kernel: `NUMPAGENDXB=6 … CB base=0x80000` (`k6-migas.log:2188`) y el aviso `address space size (0x100000) differs from mapped region size (0x200000)` (`:2189`). [DATO] el vendor usa `reg[0]=0x100000` (=2·size) y no imprime aviso | **Hipótesis A′ refutada**: con 1 MiB los CBs entran (0x80000 < 0x100000). El `reg` **no** explica el wedge del s251. El aviso de `arm-smmu.c:1855` ya no es discriminador: está resuelto (NUMPAGENDXB=6) |
| 3 | «Android hace el reset completo … ANTES de que el UFS del kernel arranque DMA» (`ESTADO-VIVO`, #P16) | **Confirmado y ampliado**: reset a 0,543250, UFS a 0,550689, dwc3 a **9,659966** (grupo 47) | Correcto, pero añade el matiz del USB: en Android el reset ocurre con dwc3 **sin attach** |
| 4 | «el driver **kws** de Android difiere del arm-smmu del fork» (`ESTADO-VIVO`, contrapunto #P16) | No hay «kws»: es **`arm-smmu`** (`arm_smmu.ko`) del mismo linaje mainline (mismas cadenas de log, `preserved 0 boot mappings`, `Stage-1: 36-bit VA -> 36-bit IPA`) | La diferencia no es la identidad del driver. Sí hay **parches vendor** (TBU driver + `handoff-smrs` + `actlr`) y, sobre todo, **el momento** y el estado del USB del bootloader |
| 5 | «Los hijos TBU son inertes» (`INFORME-SMMU-CLK` #3, R-27) | **Confirmado por el vendor**: los 8 TBU fallan (`Unable to get the transactiontracker-base`) y el SMMU bindea igual; Android funciona | Mantener los hijos (no se pueden borrar) sigue siendo lo correcto |
| 6 | «qcom,actlr = 31 tripletas, 0 lectores en este árbol ⇒ inerte» (`INFORME-A-PRIMA:245`) | Cierto para **mainline** (0 lectores), pero el vendor **sí lo lee** (`Invalid actlr setting`, `qcom,actlr` en los strings del arm_smmu vendor) | No es "propiedad muerta del DT": es funcionalidad vendor no portada. Sobre todo `0x1c00 0x02 0x01` (display) |
| 7 | «El panel: s258 … compatible `xiaomi,uke-o82-4202-0b`» y se asumía que el nodo elegido por el vendor era el O82 por `qcom,dsi-default-panel` | El `qcom,dsi-default-panel` del vendor apunta al nodo **r66451** (1080×2340, `vendor-overlay.dts:12975`); el panel que Android **bindea** es el **O82 42 02 0b** (`dmesg:4560`) porque tiene `mi,panel-id = <0x004f3832 0x5042020b>` y el driver MI lo selecciona por id | Nuestro compatible/driver apuntan al panel correcto (O82), pero **no** por `qcom,dsi-default-panel`; si algún agente "porta" ese phandle del vendor, portará el panel equivocado |
| 8 | «El vendor no tiene clocks en apps-smmu ⇒ la hipótesis clocks/power está descartada» (`INFORME-SMMU-CLK` #1) | **Confirmado** (el nodo no tiene `clocks`/`power-domains`, ni en el dtbo real de la tablet) | Nada que cambiar; la vía sigue siendo kernel |
| 9 | «El ABL dibuja su splash y el panel queda vivo» | **Confirmado e igual en Android**: primer DPMS a los 10,5 s (`dmesg:9685`), o sea el panel no lo toca el kernel hasta el UI | Nuestro s258 está en la misma fase; el siguiente hito es el attach del DPU, no el panel |
| 10 | Presunción operativa: «la ventana Android es replicable con `fastboot reboot`» (`PRE-REGISTRO-PANTALLA.md:187`) | **[REFUERZA la sospecha]**: en el dorado el dwc3 del kernel pide su grupo a los **9,66 s**, con el reset del SMMU a los **0,543 s**; en nuestros experimentos el USB de *fastboot* del ABL está vivo al entrar al kernel (invisible al SMMU driver pero con DMA en vuelo) | El golden boot **no** tiene USB de fastboot; los nuestros sí. Es la variable de confusión #1 y el vendor la refuerza |

---

## Anexo A — Dumps literales usados (para trazabilidad)

### A.1 `fdtget -p` del nodo vendor (lista de propiedades, sin valores)

```
$ fdtget -p ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img /soc/apps-smmu@15000000
compatible reg reg-names #iommu-cells qcom,use-3-lvl-tables qcom,handoff-smrs
#global-interrupts #size-cells #address-cells ranges dma-coherent status
interrupts qcom,actlr phandle
```
(No aparecen `clocks`, `clock-names`, `power-domains`, `resets`, `interconnects`, `iommus`,
`vdd-supply`.)

### A.2 Nodos `smmu_sde_*` del vendor (literales)

```dts
smmu_sde_unsec: qcom,smmu_sde_unsec_cb {
    phandle = <0x491>;
    clock-names = "mdp_core_clk";
    clocks = <0x154 0x3d>;
    dma-coherent;
    qcom,iommu-earlymap;
    qcom,iommu-faults = "non-fatal";
    qcom,iommu-dma-addr-pool = <0x60000 0xe38e0000 0xe6440000 0x19bc0000>;
    iommus = <0x129 0x1c00 0x02>;
    compatible = "qcom,smmu_sde_unsec";
};
smmu_sde_sec: qcom,smmu_sde_sec_cb {
    phandle = <0x492>;
    qcom,iommu-vmid = <0x0a>;
    qcom,iommu-faults = "non-fatal";
    qcom,iommu-dma-addr-pool = <0x20000 0xfffe0000>;
    iommus = <0x129 0x1c01 0x00>;
    compatible = "qcom,smmu_sde_sec";
};
```

### A.3 Tabla iommus completa del vendor (70 entradas al apps-smmu + 5 al kgsl, orden de fichero)

`/var/tmp/R3/vm-iommus.txt` (generado por el parser; formato `smmu path lbl=… sid=[…] comp=…`).
Resumen por SID (hex) — los mismos que la tabla §3.1 más: 0x800(32) cam_ife, 0x140(0) sdhci,
0x400(0) iommu_test, 0x480/0x481/0x483 qcedev, 0x4a0-0x4a4 ipa, 0x4c0+0x4e0 tmc, 0x500 tmc,
0x800 cam, 0x1001/0x1061 audio-ion, 0x1003/0x1043 fastrpc, 0x100b usb-audio, 0x1087 fastrpc,
0x1800-0x18e0 cam_smmu_icp/cre/jpeg/cdm, 0x1920-0x1947 cvp+vidc, 0x1c00/0x1c01 display,
0xc01-0xc0e fastrpc, 0x400/0x403… y los `iommus` dobles de `msm_fastrpc_compute_cb10..14`.
(La lista literal completa está en `/var/tmp/R3/vm-iommus.txt`, 76 líneas; y la del base en
`/var/tmp/R3/vend-iommus.txt`, 75 líneas.)

### A.4 Comandos de verificación de los datos críticos

```bash
# 1) compatible exacto y ausencia de clocks
fdtget ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img /soc/apps-smmu@15000000 compatible   # qcom,qsmmu-v500
fdtget -p ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img /soc/apps-smmu@15000000           # (ver A.1)

# 2) NUMPAGENDXB del silicio, medido por nosotros
grep -n "cfg_probe ID1\|differs from mapped" ~/proyectos/out/k6-migas.log
#   2188: cfg_probe ID1=0x60000047 pgshift=12 NUMPAGENDXB=6 CBs=71; CB base=0x80000 (mmio=2097152 B)
#   2189: SMMU address space size (0x100000) differs from mapped region size (0x200000)!

# 3) SMR vivo del ABL (UFS) medido por nosotros
grep -n "SMR\[0\]" ~/proyectos/out/k6-migas.log
#   2196: SMR[0] = 0x80000060 (valid=1 id=0x60 mask=0x0 [mask sin el bit VALID])

# 4) el vendor sí resetea y no avisa
grep -n "probing hardware\|context banks\|preserved" \
  ~/proyectos/ubuntu-permanente/criticas/ufs-referencia-android/dmesg-android.txt | sed -n '1,12p'

# 5) el vendor lee handoff-smrs/actlr (módulo de familia, NO uke)
strings ~/root_nothing2/vb/lib/modules/arm_smmu.ko | grep -E "handoff-smrs|actlr|qsmmuv500"

# 6) nuestro árbol no tiene nada de eso
grep -rn "handoff-smrs\|qsmmuv500-tbu\|TBU failed probe" ~/gpu-work/palawan-linux/drivers/ | wc -l   # 0
```

### A.5 Artefactos creados (todos fuera del repo salvo el informe)

`/var/tmp/R3/`: `vendor-base.dts` (fdtdump base), `vendor-merged.{dtb,dts}`, `our-merged.{dtb,dts}`,
`our-apps-smmu.dts`, `vend-apps-smmu.dts`, `vend-iommus.txt`, `vm-iommus.txt`, `om-iommus.txt`,
`vendor-overlay.{dtb,dts}`, `dtbo_b-actual.{dts,payload.dtb}`, `payload-s258.dtb`, `getnode.py`,
`iommus.py`, `byph.py`.

**Este informe**: `build/gates/revision/R3-vendor-diff.md` (único fichero escrito en el repo).
