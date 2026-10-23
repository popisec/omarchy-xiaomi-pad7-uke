# WIFI-P4 GO/NO-GO — 2026-10-11

Revisión del payload `build/pkg/uke-wifi-payload.tar.gz`
(27999373 B · sha256 `dfca8884d4d40ef8262188623daa16cbeafa4880f077f831d7a393478b01c697` · 29-sep, era k1)
para el P4 (ath11k/WCN6750 sobre kernel `7.2.0-rc2-palawan`, L19/L20).

Verificación hecha en PC sobre `/var/tmp/uke-wifi-check/` (payload extraído), el build
`build/kernel-pokes/k52L19-build/`, el árbol `build/kernel-pokes/k52-L16-tree/`, el árbol de la
era k1 `/var/tmp/uke-k1/` y el dtbo `build/bootimg/s277-boot-dtbo-full.img` (decompilado y
re-fusionado con `fdtoverlay` sobre el base pinneado `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img`).

## Veredicto: **GO** (3/3 verdes)

| Punto | Veredicto |
|---|---|
| 1. Módulos payload vs L19 | **GO** |
| 2. Fuentes k1 vs k52-L16-tree | **GO** |
| 3. DT s277 (wifi frags) vs drivers | **GO** |

---

## 1. Módulos payload vs L19 — GO

- **L19/L20 no compilaron sus propios ath11k/pwrseq**: en `k52L19-build/` hay **0 .ko** en todo el
  árbol (`make modules` nunca corrió; `drivers/net/wireless/ath/ath11k/` vacío, `power/sequencing/`
  solo `core.o` built-in). El payload es pues el único artefacto de módulos y no hay nada que
  comparar byte a byte: no hay reempaquetado pendiente.
- **Vermagic** exacto `7.2.0-rc2-palawan SMP preempt mod_unload aarch64` (ya verificado).
- **Sin MODVERSIONS** en L19 (`CONFIG_MODVERSIONS` ausente) y **0 símbolos `__crc_`** en los .ko
  del payload ⇒ el riesgo "symbol CRCs cambiaron" es estructuralmente nulo: el loader no compara CRCs.
- **Resolución de símbolos (definitivo)**: los 234 símbolos UND de `ath11k.ko`, `ath11k_ahb.ko` y
  `pwrseq-qcom-wcn.ko` no cubiertos por los otros .ko del payload están **al 100 %** en
  `k52L19-build/System.map` (234/234) y **al 100 % exportados** (`__ksymtab_`) por el
  `vmlinux` de L19 (14838 exportaciones revisadas; faltantes: 0). Extendido a los 40 .ko del
  payload: solo quedan fuera `mhi_*` y `drm_dp_hpd_bridge*` (ver "conocido" abajo).
- **Cero drift de ABI**: `include/` completo es **byte a byte idéntico** entre `/var/tmp/uke-k1`
  (árbol que generó el .ko) y `k52-L16-tree` (base de L19/L20): 0 diffs, incluidos
  `netdevice.h`, `skbuff.h`, `device.h`, `mac80211.h`, `cfg80211.h`, `rpmsg.h`, `remoteproc.h`,
  `mhi.h`, `pwrseq/*`. Cadenas `depmod` del payload íntegras:
  `ath11k_ahb → ath11k → mac80211 → cfg80211 → rfkill` (todo dentro del payload);
  `pwrseq-qcom-wcn.ko` sin dependencias.
- **Configs relevantes idénticas** k1 vs L19 (`ATH11K/AHB/PCI=m`, `MAC80211=m`, `CFG80211=m`,
  `POWER_SEQUENCING=y`, `POWER_SEQUENCING_QCOM_WCN=m`). Diferencias inocuas: L19 promovió a `=y`
  `QCOM_Q6V5_PAS`, `QCOM_Q6V5_COMMON`, `QRTR_SMD`, `RPMSG_QCOM_GLINK_SMEM`, `QCOM_PD_MAPPER`
  (los .ko equivalentes del payload quedan inertes: esos dispositivos los lleva el built-in) y
  añadió `ATH11K_DEBUG=y` (solo afectaría un ath11k recompilado, no el del payload).
- **Integridad del tar**: sha256/tamaño/81 entradas exactos; **16/16 ficheros de firmware
  verifican contra `build/gates/firmware-wlan.sha256`**.

Conocido (no bloquea, documentado):
- El payload **no trae `mhi.ko`** ⇒ `ath11k_pci.ko` y `qrtr-mhi.ko` no cargarán (símbolos `mhi_*`
  sin resolver; `CONFIG_MHI_BUS=m` en L19). Irrelevante para P4: el WCN6750 en cliffs es **AHB**
  (`ath11k_ahb`), `ath11k_pci` además va blacklisted. Lo mismo `pmic_glink_altmode` (HPD bridge de
  USB-C), fuera de la cadena WiFi.
- El payload trae `qcom_q6v5_pas.ko`/`qcom_q6v5.ko` de la era k1 **sin los pokes L18/L19**; en el
  kernel L19 son inertes (PAS built-in con pokes). No cargarlos a mano.

**Si algún día hiciera falta reempaquetar** (NO aplica hoy): reconstruir módulos del árbol elegido
(`make -C <arbol> O=<build> ARCH=arm64 LLVM=1 modules`) y ejecutar
`UKE_KBUILD=<build> sh build/gates/prepara/preparar-wifi-payload.sh --construir`
(todas las gates G0-G4 del script re-verifican vermagic y cadena).

## 2. Fuentes k1 vs k52-L16-tree — GO

- `drivers/net/wireless/ath/ath11k/` y `drivers/power/sequencing/`: **idénticos byte a byte**
  entre `/var/tmp/uke-k1` y `k52-L16-tree` (diff vacío). También idénticos `net/mac80211`,
  `net/wireless`, `net/qrtr`, `drivers/rpmsg`, `drivers/base/power`.
- Únicas diffs de código (2 ficheros + 1 irrelevante):
  - `drivers/remoteproc/qcom_q6v5_pas.c`: poke **L18** — `-EPROBE_DEFER` del `cx_supply` se trata
    como `-ENODEV` y sigue (los ARC vendor `lcx.lvl/lmx.lvl` no tendrán driver mainline nunca).
  - `drivers/remoteproc/qcom_q6v5.c`: poke **L19** — `interconnects` vendor sin proveedor ⇒
    `path = NULL` + guardas en los `icc_set_bw` (votos ICC desactivados, XBL defaults).
  - `drivers/soc/qcom/uke-panic-fb.c` (panic framebuffer; fuera de alcance WiFi).
  - Ambos pokes viven en código **built-in (=y) en L19** (símbolo `cliffs_wpss_resource` y
    `qcom_q6v5_init` presentes en `System.map` del vmlinux), de modo que el wpss se lleva con los
    pokes independientemente de los .ko viejos del payload.
- Nota operativa: **el P4 debe arrancar con el kernel L19/L20**. Con un kernel K de la era k1, el
  PAS del payload (sin poke L18) podría quedar en defer si el rail vendor de `cx-supply` no está
  listo; con L19 built-in el caso está cubierto por el poke.

## 3. DT s277 vs drivers — GO

Verificado sobre el dtbo real: `s277-boot-dtbo-full.img` → decompile + `fdtoverlay` contra el base
pinneado → merge limpio (advertencias `interrupts_property` ya conocidas, benignas).

- **Compatibles exactos** (además gateados por G6 del builder):
  - `/soc/qcom,wcn6750` → `qcom,wcn6750-wifi` = entrada exacta de `ath11k_ahb_of_match` (ahb.c).
  - `/soc/wifi-pmu` → `qcom,wcn6750-pmu` = entrada exacta de `pwrseq_qcom_wcn_of_match`
    (con `pwrseq_wcn6750_of_data` y targets `wlan`+`bluetooth`; ath11k pide target "wlan").
- **Cadena pwrseq provider↔consumer correcta**: el nodo wifi lleva
  `vddaon-supply = <&ldo_aon>` con `ldo_aon` hijo de `regulators` hijo de `wifi-pmu` — exactamente
  la jerarquía hijo→padre→abuelo que exige `pwrseq_qcom_wcn_match_regulator()` para emparejar el
  consumidor (poke uke documentado en ahb.c: `devm_pwrseq_get(dev, "wlan")`).
- **7/7 vregs literales**: `vddaon, vddasd, vddpmu, vddrfa0p8, vddrfa1p2, vddrfa1p7, vddrfa2p2`
  coinciden 1:1 con `pwrseq_wcn6750_vregs[]`. Rails reales: S3B/S2B/S1B (`smpb3`, phandles
  0x348/0x347/0x346) y `pmr735a_s3` (`smpe3`, 0x345); frags **1704-1706** añaden
  `qcom,regulator-type`/modos a `smpb1/smpb3/smpe3` y `CONFIG_REGULATOR_QCOM_RPMH=y` está en L19
  (el stack de display ya demuestra en tabla que estos nodos vendor rpmh se llevan bien).
- **GPIOs = vendor vivo**: `wlan-enable-gpios = <&tlmm(0x16b) 35 0>`, `bt-enable-gpios = <&tlmm 156 0>`
  — idénticos a la reconstrucción del DT de Android
  (`build/evidencia/2026-09-28/dt-reconstruido/dt-fusionado-s238.dts` líneas 822-833: mismos
  phandles, mismos GPIOs 0x23/0x9c, mismas vregs) y a los frags vendor de s269 (los frags se
  copiaron verbatim). Ninguno de los dos GPIOs está en `qcom,gpios-reserved`. El dmesg Android vivo
  (`ubuntu-uke/dump/p1-vivo-20260903`) confirma el dispositivo `17110040.qcom,wcn6750` y el dir
  `qca6750/` de firmware.
- **ath11k_ahb ↔ wpss**: `qcom,rproc = <0x3be>` → `wpss_pas: remoteproc-wpss@9bb00000` con
  `compatible = "qcom,cliffs-wpss-pas"` — entrada presente en la tabla PAS de **ambos** árboles
  (k1:1628, L16:1632) y **built-in en el vmlinux L19** (`auto_boot=false`, `pas_id=6`,
  `firmware_name="wpss.mdt"`). El wpss arranca por `rproc_boot()` cuando `modprobe ath11k_ahb`
  hace power-up; `cx-supply` (frag **1707**) = 0x348 (S3B/smpb3) correcto.
- **Firmware**: `firmware-name = "qca6750/wpss.mdt"` + `ath11k/WCN6750/hw1.0/{amss,board,regdb}.bin`
  — los 16 ficheros del payload cuadran (manifest verificado 16/16).
- **MSA/CE regions (falsa alarma descartada)**: el binding mainline pediría 2 `memory-region`
  (msa+ce) y el nodo solo trae `wlan_msa_mem`. Pero `ath11k_ahb_setup_msa_resources()` solo corre
  si `fixed_fw_mem=true` **y** existe nodo hijo `wifi-firmware` (no existe) ⇒ rama `use_tz=true`
  y return 0; además `fixed_mem_region=false` ⇒ QMI usa memoria dinámica. **No requiere fix.**
  (Si algún día se añade `wifi-firmware`, habrá que añadir también la región CE.)
- **smp2p**: el nodo wifi trae `qcom,smem-states/-names` con `wlan-smp2p-out` etc. y los nodos
  `qcom,smp2p_map_wlan_{1,2}_in` con sus `interrupts-extended` — conforme a
  `ath11k_ahb_setup_smp2p_handle()`.
- Frag **1703** (BT `wcn6750-bt` en uart8) se salta a propósito: P4 es solo WiFi.

---

## Secuencia exacta del P4 (tablet encendida, root por SSH/UART)

```bash
# --- 0) instalar payload (copiarlo antes a /tmp de la tablet por adb push/scp) ---
cd / && tar xzf /tmp/uke-wifi-payload.tar.gz -C /
depmod -a 7.2.0-rc2-palawan

# --- 1) precondiciones (paradas si algo falla) ---
uname -r                                                  # = 7.2.0-rc2-palawan
cat /sys/firmware/devicetree/base/soc/wifi-pmu/compatible      # qcom,wcn6750-pmu
cat /sys/firmware/devicetree/base/soc/qcom,wcn6750/compatible  # qcom,wcn6750-wifi
grep -l wpss /sys/kernel/debug/remoteproc/remoteproc*/name     # PAS registró el wpss (L19)
# NOTA: el blacklist de etc/modprobe.d solo bloquea el autoload por modalias;
# el modprobe manual de abajo funciona igual.

# --- 2) cronómetro (otra terminal: dmesg -w) ---
T0=$(date +%s)
dmesg -C
modprobe pwrseq-qcom-wcn            # SIN dependencias; debe ir ANTES (no hay softdep)
time modprobe ath11k_ahb            # arrastra rfkill<-cfg80211<-mac80211<-ath11k; rproc_boot(wpss)
dmesg | grep -iE 'wpss|ath11k|wcn6750|pwrseq' | tail -60
ip link show wlan0 && rfkill list all && nmcli device status

# --- 3) conectar ---
nmcli device wifi rescan && nmcli device wifi list
nmcli device wifi connect 'TU_SSID' password 'TU_PASS'

# --- 4) criterio de éxito del proyecto ---
nmcli -t -f DEVICE,STATE device | grep -q '^wlan0:connected' && echo CONECTADO
sleep 300; awk '{print $1}' /proc/uptime          # > 300 s sin wedge/crash
dmesg | grep -iE 'wedge|rcu|panic|ath11k.*err' | tail
```

Triage rápido si algo falla: (a) `ath11k_ahb` en deferred con `vddaon-supply` presente ⇒
`pwrseq-qcom-wcn` no cargó (cargarlo primero); (b) wifi-pmu "Failed to get all regulators" ⇒
rails smpb1/smpb3/smpe3 (revisar frags 1704-1706 en el dtbo booteado); (c) wpss no arranca ⇒
revisar `qcom_pas` (poke cx/ICC), `firmware_class.path` y que `qca6750/wpss.mdt` esté en
`/usr/lib/firmware`; (d) QMI sin respuesta ⇒ revisar glink IPCRTR (`qcom,wpss_qrtr`) y pd-mapper
userspace si hiciera falta.

Última actualización: 2026-10-11 (revisión estática en PC; tablet apagada).
