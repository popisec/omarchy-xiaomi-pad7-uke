# Captura solo lectura del kernel senemos (MCC45TR) en la tablet uke, 17-oct-2026 ~20:00 (hora de la tablet)

Kernel medido: `7.2.9-senemos.1.4054.3-ouke2` (boot_a `7848d68d`, dtbo_a stock), uptime ~6 min al empezar,
SSH por RNDIS `192.168.42.129`. El panel O82 muestra imagen. Método = `build/linux-l76r-20261017/drm/collect-remote.sh`
(solo `cat`/`ls`/`dmesg`), con estas diferencias, por las reglas duras de la sesión:

- **No** se leyó `dri/*/state`, `dri/*/kms`, `crtc-*/state`, `crtc-*/crc`, `hw_log_mask` ni `shrink`.
- **No** hay `devmem`, `/dev/mem` ni `regmap/*/registers`. Las únicas lecturas que tocan MMIO las hace el propio
  driver DPU al servir `debug/danger/*` y `debug/sspp/*/{csc,scaler,src}_blk` (debugfs del driver, ya usadas en L76R), y
  `sspp/*` solo se leyó en reposo.
- Además de la lista blanca del encargo se leyeron, como estado software (sin MMIO, sin WARN): `crtc-0/status`,
  `encoder-0/bridges`, `dri/bridges`, `clients`, `name`, `interconnect_graph`, `regulator/<rail>/*`, `opp/*display*`,
  `mailbox_summary` y estado de remoteproc.
- En este kernel `dri/0` es un symlink a `ae01000.display-controller` (no existe `dri/1`).
- Escrituras: ninguna en sysfs/debugfs. Solo `dmesg -n 7` (permitido) y los ficheros `/root/mt.txt` y `/root/mt2.txt`
  que crea `modetest` (receta del encargo).
- El script remoto es `collect-remote-senemos.sh` (secciones `icc icc-graph clk reg regdetail opp genpd irq iommu
  sysdrm dmesg rpmh sistema dri-reposo dri-plano`). Uso: `ssh … 'sh -s -- <seccion>' < collect-remote-senemos.sh`.

## reposo/ (fbcon activo, sin modetest; modo 3200x2136@120, vsync del INTF1 ~10 337 al capturar)

| Fichero | Contenido |
|---|---|
| `icc.txt` | `interconnect_summary` completo |
| `icc-graph.txt` | `interconnect_graph` (dot) con las aristas qnm_mdp→qns_mem_noc_hf→qnm_mnoc_hf→qns_llcc→llcc_mc→ebi y qsm_cfg→qhs_display_cfg |
| `clk.txt` | `clk_summary` completo |
| `reg.txt` | `regulator_summary` |
| `regdetail.txt` | por regulador (mmcx/mxa/mx/cx level, ldob2/4/8, vsp/vsn): `min_uV`/`max_uV`/`uA_load` de cada consumidor = votos de nivel |
| `opp.txt` | `/sys/kernel/debug/opp/*display*` (tabla OPP del DPU: 200/342/402/514/**600** MHz, todas `available`) |
| `genpd.txt` | `pm_genpd_summary` + ficheros por dominio |
| `irq.txt` | `/proc/interrupts` |
| `iommu.txt` | grupos IOMMU (`type=DMA` en todos, el display en el grupo 7) |
| `sysdrm.txt` | atributos de `/sys/class/drm` |
| `dri-reposo.txt` | `name`, `clients`, `encoder-0/status` y `bridges`, `crtc-0/status`, `DSI-1/*`, `debug/core_irq`, `core_perf/*`, `danger/*`, `vbif/*`, `sspp/*` |
| `rpmh.txt` | `cmd-db` (volcado completo), `mailbox_summary`, remoteproc, listados de debugfs (`opp`, `regulator`, `qcom_aoss`) |
| `sistema.txt` | uname, `/proc/cmdline`, `devices_deferred`, `lsmod` (vacío: todo built-in), backlight, platform devices, drivers enlazados |
| `dmesg.txt` | `dmesg` completo (1 698 líneas, con `dmesg -n 7`) |

## plano/ (plano XR24 3200x2136 sostenido por `modetest -M msm-kms -s 36@79:#0 -v`, page-flip a 120 Hz)

Dos ejecuciones de modetest (25 s de `sleep` con stdin abierto, `timeout 30`). Capturas a t≈+5 s y t≈+15 s.

| Fichero | Contenido |
|---|---|
| `00-t*.txt` | marcas de tiempo (epoch) de cada paso |
| `pre-dri-plano.txt` | `encoder status`, `crtc status`, `core_irq`, `core_perf`, `danger` ANTES de lanzar modetest (fbcon) |
| `dri-plano-t5.txt`, `dri-plano-t15.txt` | lo mismo con el plano activo, 1ª ejecución (t+5 s y t+15 s) |
| `dri-plano-post.txt` | tras terminar modetest (solo `underrun`/`vsync`/`IRQ` ya filtrado) |
| `dri-plano-t2.txt` | 2ª ejecución, t+5 s |
| `icc.txt`, `clk.txt`, `reg.txt`, `genpd.txt`, `irq.txt`, `iommu.txt`, `sysdrm.txt` | igual que en reposo, con el plano activo |
| `regdetail.txt`, `opp.txt` | votos de nivel y OPP con el plano activo (2ª ejecución) |
| `modetest-out.txt`, `modetest-mt.txt` | salida de modetest (`freq: 120.00Hz` en cada segundo; contenido de `/root/mt.txt`) |
| `dmesg.txt` | `dmesg` completo tras ambas ejecuciones (1 745 líneas) |

**Resultado**: `underrun: 0` en INTF1 e INTF2 y `IRQ [0,26]`/`[0,28]` = 0 con vsync 10 556 → 13 757 en la 1ª ejecución
(3 201 vsync) y 19 147 al llegar a la 2ª; `vblank fps:119`. `dmesg` sin ninguna línea nueva del kernel durante el plano
(solo `kauditd_printk_skb`). **ICC, relojes, reguladores, genpd, IOMMU, OPP y votos de nivel son idénticos en reposo y en
plano** (`diff` vacío salvo contadores de UFS y estado de cpu-pd).

## Otros ficheros

| Fichero | Contenido |
|---|---|
| `collect-remote-senemos.sh` | script remoto (solo lectura) |
| `tabla-relojes.py` / `tabla-relojes.txt` | tabla de relojes del display: L76R / senemos reposo / senemos plano / vendor |

El análisis comparativo está en `build/gates/revision/QUE-NOS-FALTABA-20261017.md`.
