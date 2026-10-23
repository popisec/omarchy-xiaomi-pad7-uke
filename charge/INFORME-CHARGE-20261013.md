# INFORME — Stack de carga ADSP/battmgr listo (13-oct-2026, sin flash)

> Estado: **montado y listo para ejecutar en cuanto la tablet vuelva por RNDIS.**
> No se flasheó nada, no se reinició nada, no se tocó ninguna `CONFIG_*`
> versionada. Tablet caída: todo lo verificable en caliente queda como guion.

## 0. Respuesta corta (lo que pide la tarea)

1. **¿Queda montado y listo para un flash? — SÍ, con una reserva** (ver §5):
   módulos K5 staged, firmware staged, `uke-adsp.service` + loader escritos,
   dtbo s282 construido con los dos gates en verde y sha pre-registrado.
   Lo único que falta es tablet viva (reset físico del dueño) + ejecutar
   `charge/uke-charge-run.sh`.
2. Ficheros creados: ver §6 (con sha256).
3. Gates: ver §4.
4. Guion de un comando: `charge/uke-charge-run.sh` (§3).
5. Riesgos vivos: ver §5 (trampa `qcom,gpr` incluida).

## 1. Módulos K5 (conductor: `charge/build-mods.sh`)

Fuente: `build/kernel-pokes/k52L33-tree` (NO modificada; los 7 volteos `=y→=m`
viven SOLO en copias de `.config` en `/tmp/uke-mods-palawan{,-plus}`).

- Símbolos: `QCOM_Q6V5_PAS`, `QCOM_RPROC_COMMON`, `QCOM_Q6V5_COMMON`,
  `QCOM_PIL_INFO`, `RPMSG_QCOM_GLINK_SMEM`, `QCOM_PMIC_GLINK`,
  `UCSI_PMIC_GLINK`, `QRTR_SMD`, `BATTERY_QCOM_BATTMGR` = `m`
  (+ ayudantes `qcom_common/qcom_q6v5/qcom_pil_info/qcom_glink` cuando existen).
- Por qué este árbol: lleva el parche LOCATOR (`qcom,cliffs` →
  `sm8550_domains`, la raíz del DT vivo es `qcom,cliffs`) y los parches del
  dialecto battmgr (`0x50`, `complete(&ack)`); es byte-idéntico a k52L39-tree
  en `pd_mapper/battmgr/pmic_glink` (`diff -q`, §4).
- **Vermagic (la lección)**: se construyen DOS variantes desde la misma fuente
  (`charge/mods-7.2.0-rc2-palawan/` y `charge/mods-7.2.0-rc2-palawan+/`) porque
  los kernels L de este proyecto no llevan `+` y los del hermano sí, y la
  tablet no contesta para decir cuál corre. El `+` NO depende del git-dirty:
  se fija con `LOCALVERSION=` / `LOCALVERSION=+` (determinista;
  `scripts/setlocalversion:199-212` no consulta el scm si LOCALVERSION está
  seteada). Gates: `kernel.release` == `charge/VERMAGIC-PIN` antes de compilar
  y `modinfo -F vermagic` exacto por cada `.ko` después.
- Cómo no vuelve a pasar: (1) ninguna config versionada se escribe (gate
  G-CONFIG aborta si el diff trae un `=y` o un símbolo fuera de lista);
  (2) el release se pinnea en `VERMAGIC-PIN` y se verifica dos veces;
  (3) el guion de despliegue (`uke-charge-run.sh`) elige por `uname -r` y
  PARA si no hay variante exacta — nunca `--force`.

## 2. Firmware ADSP (`charge/firmware/`)

Origen (NO re-descargado): `~/gpu-work/ramaa/s24/adsp-fw/`
(extraído byte-a-byte del dump `modem_a`, verificado contra su MANIFEST).
Contenido: `adsp.mdt` + `adsp_dtb.mdt` + 51 `adsp.bNN` + 3 `adsp_dtb.bNN`
(56 ficheros) + `SHA256SUMS`. Destino en tablet: `/lib/firmware/`.

## 3. Servicio (`charge/uke-adsp.service` + `charge/uke-adsp-load.sh`)

- Orden: ayudantes → `qcom_q6v5_pas qcom_glink_smem qrtr-smd qcom_pd_mapper
  pmic_glink ucsi_glink qcom_battmgr` → `echo start` al remoteproc `adsp`.
- Módulos en `/usr/local/share/uke/mods/` (fuera de udev/kmod).
- Idempotente: salta módulos presentes (`/sys/module`) y ADSP ya `running`.
- Red anti-gpr: `echo 0 > …/drivers_autoprobe` + `dmesg -n 1` ANTES del start.
- `systemd-analyze verify --root=<staging-con-layout-tablet>` => RC 0.

### Guion de un comando (cuando haya tablet)

```
charge/uke-charge-run.sh          # despliega + veredicto
charge/uke-charge-run.sh verdict  # solo re-sondea el veredicto
```

Imprime remoteproc, `/sys/class/power_supply` y la línea PDR `charger_pd`.
Verde = `status=Charging` + `current_now>0` + `charge_type=Fast` (cf. #406:
`+1191313 µA`, `Fast`).

## 4. Gates (todos verdes el 13-oct-2026)

Log completo del build: `build/logs/build-charge-mods.log` (corrida final
16:28–16:29, `== FIN OK ==`; 4 intentos previos abortados por gates, ver
lecciones en el propio log).

- **G-CONFIG** (no tocar la config): diff `k52L33-build/.config` vs scratch
  tras `olddefconfig` = SOLO los 7 volteos `=y→=m` + 2 líneas de fallout
  (`CONFIG_QCOM_Q6V5_ADSP=m`, `CONFIG_QRTR_MHI`→`n` en scratch). Cero `=y`
  nuevos; `build/gates/l39-config.config` y `k52L33-build/.config` intactos
  (`git diff --name-only` no los lista).
- **G-VERMAGIC**: `include/config/kernel.release` de cada scratch ==
  `charge/VERMAGIC-PIN` (`7.2.0-rc2-palawan` y `7.2.0-rc2-palawan+`).
- **G-MODINFO**: 10/10 `.ko` por variante con
  `modinfo -F vermagic` == `<release> SMP preempt mod_unload aarch64` y
  `readelf -h` (con `LC_ALL=C`: el del host habla español) == AArch64.
- **depmod**: `depmod -b charge/stage-<rel> <rel>` RC 0, `modules.dep` con
  10 líneas (un WARNING residual: falta `modules.order` en k52L33-build,
  no lo genera; irrelevante para insmod).
- **Carga en seco**: `modprobe -d charge/stage-<rel> -S <rel> -n
  --show-depends <m>` RC 0 para los 7 del K5 en ambas variantes
  (pas resuelve 5 insmod: +3 ayudantes; battmgr/ucsi arrastran pmic_glink).
  Nota honesta: `insmod --dry-run` NO existe en el kmod de Arch
  (`unrecognized option`); el show-depends es el equivalente real.
- **G-LIMPIO**: 110 ficheros generados eliminados de `k52L33-tree`,
  0 restos bajo los MDIRS (los 2 `.o` de `drivers/power/sequencing` son
  del 11-oct, de otro flujo, y no se tocaron).
- **DTBO s282** (`charge/repack-s282-report.txt`):
  `fdtoverlay -i base -o merged s282.dtbo` RC 0;
  `build/gates/uke-dtbo-check.py s282.img base` RC 0
  (`OK: el stack display existe…`); paridad s281 (OPP DSI
  {148648750,187500000,300000000,358000000}, iommus-DC, bootargs, touch,
  cx-supply ADSP); `gpr status=disabled`; roundtrip dt_table OK.
  sha256(s282) = `00c3410677eaa15d801024a2e9b0e0213cefd028a4372fee913b4d21eee168d0`
  (607458 B).
- **Service**: `systemd-analyze verify --root=<staging-con-layout-tablet>
  etc/systemd/system/uke-adsp.service` => RC 0 (el fallo sin `--root` es
  solo la ausencia del path en el PC, esperado).
- **Firmware**: 4/4 shas contra el MANIFEST del proyecto hermano
  (`adsp.mdt fd874a8d…`, `adsp.b00 f1e6f7ee…`, `adsp.b52 43489ee8…`,
  `adsp_dtb.b01 ad20a9d5…`) + `SHA256SUMS` de los 56 ficheros.

## 5. Riesgos vivos e incertidumbres explícitas

1. **Kernel que correrá (incertidumbre)**: si es L33/L39 (`-palawan`, QRTR/PAS
   built-in) solo entran `pmic_glink/ucsi_glink/battmgr` y el resto se salta
   solo — la carga funciona igual (el transporte ya vive built-in). Si es un
   kernel hermano (`+`), entra todo. Si es OTRO release, el guion para.
2. **Trampa `qcom,gpr` (riesgo principal)**: el s281 flasheado la deja VIVA
   (verificado: 0 ocurrencias de `qcom,gpr` en su payload). Red triple:
   s282 con `disabled` (pre-registrado, §4) + `drivers_autoprobe=0` en el
   loader + chequeo post-flash (`Domain ID not specified` = 0). Sin el flash
   del s282, el bucle vuelve al primer `echo start`.
3. **L39 flasheado con BATTMGR=y**: si la tablet arranca el L39 pre-revert,
   el wedge es el documentado (consola muda, sin pstore) y NADA de esto
   aplica hasta reflashear un kernel sano — fuera del alcance (no flash).
4. **Batería ~3439 mV < gate 3700**: el primer ciclo debe ser SOLO el
   despliegue de carga (0 flashes), con cargador de pared.
5. **`pmic_glink_altmode.ko` no se distribuye** (símbolos DRM-DP ausentes;
   irrelevante para carga, como en #404).
6. **Módulos =m sobre kernel con símbolos distintos**: con MODVERSIONS=n no
   hay CRC que proteja; la defensa es fuente idéntica (L33≡L39) + vermagic
   exacto + orden de carga. Riesgo residual bajo, declarado.

## 6. Ficheros creados (sha256 medidos 13-oct-2026)

`charge/` (39 M, casi todo firmware) + `build/gates/uke-dtbo-check.py`
(copia del hermano + ajuste documentado del perfil táctil a `novatek@0`):

| Fichero | sha256 |
|---|---|
| `charge/VERMAGIC-PIN` | `11987f1569d558f20ca5da881424b7577da0a1ccedce24770d55e70c27807880` |
| `charge/build-mods.sh` | `7783a117745d2b8a1e084305a0a1ef84929db63f6a2defca00f5a088bbd6d32e` |
| `charge/mkdtbo-s282.py` | `53e62c4120069665745ddcf12d71f3e072ddc3ffe86a5b144708e3e93b205749` |
| `charge/uke-adsp-load.sh` | `8f928fbfdc4a1c7df225ecb9b337b3f7523efb536606c196b9ac004561c22` |
| `charge/uke-adsp.service` | `6146bda75232145118332669a658792e786569c276285ae4da9d3d1f22a14d7c` |
| `charge/uke-charge-run.sh` | `1fcc2d23c1655138a6ce37662dfa3a81fa88a11c2378c974029c880ff3f06728` |
| `charge/PRE-REGISTRO-S282.md` | `7daa3d0da127048d6e74a27220d8320bfb17d196cdcf60c14196fc19438c3785` |
| `charge/repack-s282-report.txt` | `50fe48e724de306962dbdeb8f8bd2af31054c4b7b02da2aa374246a706b9133a` |
| `charge/INFORME-CHARGE-20261013.md` | (este fichero; ver commit) |
| `charge/firmware/` (56 ficheros) | ver `charge/firmware/SHA256SUMS` |
| `charge/firmware/adsp.mdt` | `fd874a8d7520e8363b6345b0d5b0676161b30b4c3a0d6e5561f426bcfed6a622` |
| `charge/mods-7.2.0-rc2-palawan/pmic_glink.ko` | `4bcad826d28476c30438e066974eb6a994e5731511d796ab71b5112cc7dfb9c2` |
| `…/qcom_battmgr.ko` | `18a5b23661216b6443ba6550afc6d3b483dae161b31322c6d06b9fda13451da0` |
| `…/qcom_common.ko` | `b88826765f6c5610177c628324a45efd28dac364ca9b3fa4c9c35992c4c2c520` |
| `…/qcom_glink_smem.ko` | `d01fd2f5f2a08409107ce47b94fef4be093d17db12fbc26c0b7220d80121da01` |
| `…/qcom_pd_mapper.ko` | `f85977502ba1f847d866ad25c8212c42bb64ef739fb414e067d4ae79a4921747` |
| `…/qcom_pil_info.ko` | `2e4683d0bdf258f8d0efdc9c0e9bd7d9c7a1163e00ab035df2286fc6eeaa467c` |
| `…/qcom_q6v5.ko` | `a16b5c4f2ee9614feed89dc0b47f86a1019b44bbc6ef4e4a63e079c70aec06df` |
| `…/qcom_q6v5_pas.ko` | `9e96d5eacd4c6318e5e5d115199675d2d6d50822ce56f691f47ca4ffebc88606` |
| `…/qrtr-smd.ko` | `b34b142752d34bb28f960b0775407f739afe0adcb5918e88fe1dadfae60f86bf` |
| `…/ucsi_glink.ko` | `52b8849a6f1341e9537ad3fcefd0d4ada45e99e69d1e02088c4a8e0ee11418aa` |
| `charge/mods-7.2.0-rc2-palawan+/pmic_glink.ko` | `036d719bfac0ddf6aa8d9fc536eb4084bb7f913447c3775e8655316bc9cb4e3e` |
| `…+/qcom_battmgr.ko` | `8010b07490f38208844d500daa35de7a40a9ba543f25eee4f3ac4dd564a04044` |
| `…+/qcom_common.ko` | `13381cef9f02fd77d9a091f36923fc96324352a58124eef1af21ba9fc7752277` |
| `…+/qcom_glink_smem.ko` | `549fcc12491ca95c19967601a93ab57f85eb1afb087aef9c2cc9f38d75499297` |
| `…+/qcom_pd_mapper.ko` | `0c3d4237cf40937ac05904f8defd5cfb4d2f99ab06ad24a2b6d881762a098e49` |
| `…+/qcom_pil_info.ko` | `6ad8a3b75016490a4489c252337358a612ac8eb7a37c966e2dcf3f4ac66dfce8` |
| `…+/qcom_q6v5.ko` | `0c23516b84edeaf08fa97f9de1039f00e2ef8b18516f946cd61529a903200006` |
| `…+/qcom_q6v5_pas.ko` | `50d19403e8e8c7bdc254967e6db62abaf956657cf66671c23a38c260dfe90bbd` |
| `…+/qrtr-smd.ko` | `c918322b8fe97d6496dd24ac9533063c043e2d2f352811004af5d12d2054bff9` |
| `…+/ucsi_glink.ko` | `1633ce980ed0fac1ac333524bac2cbdb7912a068b1ec0a63d150f288e7071b9d` |
| `charge/stage-*/…/modules.dep` (ambos) | `999bd0145965835cb5c14d2163ebe7c870e740cac0873fe3c78a044d341095ca` |
| `build/bootimg/s282-…-nogpr.img` (NO en git, `.gitignore`) | `00c3410677eaa15d801024a2e9b0e0213cefd028a4372fee913b4d21eee168d0` |
| `build/gates/uke-dtbo-check.py` | (copia hermano + hunk táctil; ver diff en commit) |
