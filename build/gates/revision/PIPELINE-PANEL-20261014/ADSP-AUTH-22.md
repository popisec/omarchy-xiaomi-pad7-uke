# ADSP: `failed to authenticate image and release reset` (-22) — por qué en uke sí y en Ubuntu no

Fecha: 2026-10-14. L64 vivo (`7.2.0-rc2-palawan #12`). Todo lo marcado MEDIDO se leyó hoy
por SSH solo-lectura (`-i build/rootfs/uke-arch-root root@192.168.42.129`) o por diff local.

## 1. Hechos MEDIDOS (idénticos en ambos arranques)

- Firmware vivo = el bueno de modem_a: `adsp.mdt` sha `fd874a8d…`, `adsp_dtb.mdt` sha
  `909cf117…`, 56 ficheros (faltan `b24`/`b51` porque el MDT los declara `p_filesz=0`).
  Fuente: `~/proyectos/ubuntu-permanente/criticas/ronda-29/ADSP-FIRMWARE.md` §0-§2.
- Driver idéntico: `diff palawan-linux/.../qcom_q6v5_pas.c k52-L16-tree/...` solo difiere en
  el hunk L18 (`qcom_q6v5_pas.c:550-554`); `qcom_scm.c` y `mdt_loader.c` byte-idénticos.
  Recurso: `cliffs_adsp_resource` (`qcom_q6v5_pas.c:1411-1424`): `pas_id=1`, `dtb_pas_id=0x24`,
  sin `proxy_pd_names`, `auto_boot=false`. Config: `QCOM_Q6V5_PAS=y`, `QRTR=y`,
  `GLINK_SMEM=y`, `PD_MAPPER=y`, `SCM=y`, `AOSS_QMP=y` (igual que el punto 3 del ledger #398).
- Carveouts vivos correctos: `adspslpi@9d400000` = `0x9d400000+0x4500000`,
  `q6_adsp_dtb@a1900000` = `0xa1900000+0x80000`; `memory-region = <0x18a 0x18b>` resuelve a
  esos dos nodos. El único `OVERLAP DETECTED` del dmesg es `splash_region` vs `s19fb`
  (display, irrelevante).
- El error sale de `qcom_pas_start()` (`qcom_q6v5_pas.c:329-334`): el auth del **dtb**
  (`pas_id 0x24`, línea 310) PASA (sin mensaje de error) y falla solo el auth del **main**
  (`pas_id 1`) con `-22`. Entre medias hay ~340 ms de carga MDT correcta.

## 2. La ÚNICA diferencia funcional: votos de bus/rail en el momento del auth (MEDIDO)

| | Hermano (Ubuntu 25-sep, OK) | Nosotros (L64, -22) |
|---|---|---|
| `interconnects` DT | @1301: `<&mc_virt 3 &mc_virt 512>` (ledger #398) | vendor original: tuplas a `0x187/0x188/0x189` |
| proveedores vivos | — | `0x188 mc_virt` → bound a `qnoc-palawan`; `0x187 lpass_lpicx_noc` y `0x189 aggre2_noc` SIN driver (nuestro `palawan.c` solo porta aggre1/mc_virt/gem/cnoc) |
| efecto en driver | `icc_get` resuelve, vota DDR | `icc_get` falla → **L19 lo convierte en `path=NULL`** (`qcom_q6v5.c:349-358`): cero votos DDR |
| `cx-supply` | vacía por DT (→ NULL) | phandle ARC sin driver → **L18 lo convierte en NULL** (`:548-555`): cero voto CX por regulador |
| votos restantes | QMP `load_state "adsp"` + ICC mc_virt + AOP | **solo QMP/AOP** |

El comentario de L19 ("esquema validado era Ubuntu") es incorrecto: Ubuntu-25sep
(`docs/FLASH-LEDGER.md` #404) arrancó el ADSP **con** @1301, es decir, **con** votos mc_virt.

## 3. Causa más probable (HIPÓTESIS, coherente con toda la evidencia)

El TZ acepta `AUTH_AND_RESET(0x24)` sobre la región DTB de 512 KiB pero devuelve `-EINVAL`
al `AUTH_AND_RESET(1)` sobre los 72 MB de DDR con los buses sin votar: sin `icc_set_bw`
el dominio DDR del ADSP sigue en defaults del XBL y la liberación del reset falla.
Descartados por medición: firmware (shas OK), carveouts (sin solape), `pas_id` (el dtb-0x24
pasa por el mismo SMC), `use_tzmem` (falso en ambos: el nodo no tiene `iommus`,
`qcom_q6v5_pas.c:857-858`), ramas de código SCM/MDT (idénticas).

## 4. FIX mínimo (dos piezas inseparables)

1. **DTBO**: fragmento estilo @1301 al nodo `/soc/remoteproc-adsp@03000000`:
   `interconnects = <&mc_virt 3 &mc_virt 512>` (+ `cx-supply` vacía; con L18 es redundante
   pero fiel al @1301). `mc_virt` = `interconnect@1` existe y está bound en el L64.
2. **Kernel**: revertir el hunk L19 (volver a propagar el error de `devm_of_icc_get`).
   Sin (2), L19 anula cualquier DT; sin (1), el revert deja el probe en defer eterno
   (0x187/0x189 no tienen driver). L18 se conserva.
3. Gate previo offline: `fdtoverlay` + `bin/uke-dtbo-check.py` del hermano (solo lectura).

## 5. Cómo probarlo SIN flashear (0 escrituras) y riesgo

- Paso 0 (coste cero, runtime): `echo stop` + `echo start` a `remoteproc1` + `dmesg`;
  si repite `-22`, descarta estado intermedio del TZ.
- Prueba real: `fastboot boot` con `boot.img` (Image L actual + revert L19) + dtbo con el
  fragmento. **No escribe flash**; si no levanta, reset físico y arranca el slot bueno.
  Éxito = `remoteproc1: adsp is now up` + PDR `charger_pd` + fin del `-EAGAIN` de battmgr.
- Coste: 1 ciclo de arranque, 0 escrituras, sin tocar `slot-retry-count` (se conserva;
  conserva; el semáforo inter-proyecto sigue aplicando: mirar ESTADO del hermano antes).
