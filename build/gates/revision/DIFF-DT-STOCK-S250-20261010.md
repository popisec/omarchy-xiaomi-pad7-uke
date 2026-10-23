> ⛔ **SUPERADO por docs/historia/revision/CRITICA-A2-20261010.md (17:2x)**: la RECETA 1 está RETIRADA —
> es DESTRUCTIVA tal cual (path_count=0 + opp-peak-kBps = -EINVAL = tabla OPP entera
> fuera en el probe; y con interconnects del stock también muere: wedge #286 desactivó
> el nodo icc del GPU a propósito). Los votos bw van por HFI (post-release) donde NO
> están las muertes. La RECETA 2 sigue en pie (0x23 verificado en L11) pero POSPUESTA
> hasta que el release viva. La receta que sustituye a la 1 es el dtbo SMMU-CX
> (power-domains del kgsl-smmu al gpucc) — ver CRITICA-A2 §1c/§2.

# DIFF-DT-STOCK-S250 (10-oct-2026, RONDA-A2, agente DT): recetas fila 6 y fila 7

> Fuente: agente DT (solo-PC). Base que ARRANCA: `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img`
> (≈ stock2-Cliffs7P-uke.dts). s250-efectivo = `~/gpu-work/ramaa/s21/dtbo-gpu/s250-dtbo-build.py`
> (frags 902–910). OJO: `build/bootimg/mkdtbo-s250.py` es OTRO s250 (REFUTADO en su cabecera,
> no es el de la tablet). Vendor: `~/.hermes/profiles/coder/cache/scratch/vendor/op-sm7675/.../cliffs-gpu.dtsi`.

## Veredicto general
El bloque GPU/GMU/SMMU de s250 es correcto salvo 2 deltas (confirmadas contra driver k52-L15):
1. **Fila 6**: `gpu_opp_uke` (frag 908) SIN `opp-peak-kBps` → `nr_gpu_bws=1` →
   `a6xx_gmu_rpmh_bw_votes_init` NO corre (a6xx_gmu.c:2533) → **GMU sin votos SH0/MC0/ACV
   al boot del CM3** (equivalente vendor: `icc_set_bw(ddr_table[bus_min])` pre-release,
   adreno_gen7.c:1938-40). `interconnects;` vacía = INERTE para este driver (el gen7 del
   port no hace of_icc_get en GPU): dejarla como está.
2. **Fila 7**: GMU sin `qcom,qmp` → `qmp_get` -ENODEV (qcom_aoss.c:457) → `qmp_send(ACD)`
   jamás sale (a6xx_gmu.c:2716). OJO: s271 lo puso en el nodo GPU (BUG); el driver lo lee
   del nodo **GMU**. El `mboxes=<0x3b3 0>` (qmp_aop) que sobrevive del stock es inerte:
   `qcom,qmp-mbox` sin driver mainline → NO apuntar ahí (EPROBE_DEFER eterno).

## Receta 1 (fila 6) — en frag 908, bloque `gpu_opp_uke` (build.py:227-239)
Añadir a cada OPP `opp-peak-kBps` (valores verbatim de palawan.dtsi:2405-2465 ≡
qcom,bus-table-ddr del stock):
255M→2136718 · 353M→6074218 · 500M→6671875 · 633M/684M/736M→12449218 · 835M→14398437 ·
900M/950M→16500000. Literales (sin phandle → sin fixups nuevos). Efecto: votos BCM
SH0/MC0/ACV en el HFI del boot del CM3 (bcms en a6xx_catalog.c:1639-1646).
Requiere `CONFIG_QCOM_COMMAND_DB=y` (presente).

## Receta 2 (fila 7) — fragmento NUEVO (911)
```
fragment@911 { target-path = "/soc/qcom,gmu@3d69000";
  __overlay__ { qcom,qmp = <0x23>; }; };
```
`0x23` = phandle de aoss_qmp `/soc/power-controller@c300000` (base:11606-11614) — el que
sí bindea el port (`qcom,aoss-qmp`, CONFIG_QCOM_AOSS_QMP=y). Literal → sin fixups. Gate
nuevo del build: `props(b,"/soc/power-controller@c300000")["phandle"] == 0x23`.

## ACOPLAMIENTO CRÍTICO (ACD completo)
`qcom,opp-acd-level` por OPP (valores del base: 950/900/835M=0xa8285ffd, 736/684/633M=
0x88295ffd, 500M=0xa8295ffd, 353M=0x882c5ffd, 255M=0x882f5ffd) SOLO junto con frag 911:
con acd-level y sin qmp, `acd_probe` → -EINVAL y **el probe del GMU muere** (a6xx_gmu.c:2702-2706).

## Nota cruzada con el hallazgo #581
`msm.uke_gmu_shared` default = **1 en L15** (a6xx_gmu.c:2222); k52b2 viaja con =0 en cmdline.
El no-nacimiento de card0 en boot caliente de k52b2 (#581: `gpu_cc_hlos1_vote_gpu_smmu_clk`
stuck) es ortogonal a estas recetas (es probe de SMMU/clocks, no HFI/bw).
