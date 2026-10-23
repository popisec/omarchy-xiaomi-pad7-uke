# U1 — FIRMWARE GPU: nombres exactos, formatos, entregable y riesgo CM3

> 30-sep-2026 noche. SIN tablet (prohibido fastboot/adb/ssh/ttyACM0). Árbol kernel:
> `/var/tmp/uke-k13-tree` (kernel #17, el de boot_b = #P40). Nada de memoria: todo file:line,
> medida local o captura (`/var/tmp/k14-cycle.log`). Escrito solo aquí y en
> `build/gates/prepara/gpu-fw-fix.sh` + `/var/tmp` (entregable probado).

## 0. Veredicto en una frase

El único bloqueo del arranque es el firmware del GPU **con el nombre exacto que pide el driver**
(ENOENT a 4,203 s, 2 ciclos idénticos en `k14-cycle.log`), pero **instalarlo solo en el rootfs NO
basta para el boot K15**: a 4,2 s el kernel lee contra el root INICIAL (el initramfs), aún antes del
switch_root del ukeinit. La pantalla queda a **un repack del boot img de distancia** — hecho y
verificado: `/var/tmp/u1-gpu-fw/boot-ukek13-fw.img` (sha `62192c26…`).

## 1. Lo que el driver pide (árbol K13), en orden de boot

Cadena: `msm_drm_bind` (kms init ✓, #P40) → card0 registrada → cliente fbdev en el mismo initcall
abre card0 → `msm_open` → `load_gpu` (`msm_drv.c:198-207`) → `adreno_load_gpu`
(`adreno_device.c:69`) → `adreno_load_fw` (`adreno_device.c:93`; bucle en `adreno_gpu.c:607-622`).

| # | Petición (ruta de búsqueda 1ª) | file:line de la petición | Mecanismo |
|---|---|---|---|
| 1 | `qcom/gen71100_sqe.fw` | `a6xx_catalog.c:1621` (`fw[ADRENO_FW_SQE]`, entrada chipid `0x43030b00` en `:1618`) | `adreno_request_fw()` `adreno_gpu.c:524-592`: `request_firmware_direct` "qcom/<n>" (`:545`) → legacy "<n>" (`:565`) → helper `request_firmware` (`:586`) |
| 2 | `qcom/gen71100_gmu.bin` | `a6xx_catalog.c:1622` (`fw[ADRENO_FW_GMU]`) | idem (2º del bucle `adreno_load_fw`) |
| 3 | `qcom/uke/gen71100_zap.mbn` | `xiaomi-uke.dts:555` (`firmware-name` de `&gpu_zap_shader`) | DIRECTA sin fallback: `request_firmware_direct` en `adreno_gpu.c:75-79` (si el DT no tuviera firmware-name iría el `.zapfw` del catálogo `qcom/gen71100_zap.mbn`, `a6xx_catalog.c:1630`) |

Orden temporal fino: 1) SQE y 2) GMU se *piden* en `adreno_load_fw`; después `hw_init`
(`a6xx_gpu.c:1174`) consume el GMU escribiendo bloques ITCM/DTCM (`a6xx_gmu.c:901-933`, pokes
F1/F2/F3/F4) y pide el zap (`a6xx_gpu.c:1493` → `a6xx_zap_shader_init:1124` →
`adreno_zap_shader_load` `adreno_gpu.c:174-184` → `zap_shader_load_mdt:30-160`) terminando en
`qcom_mdt_load` + `qcom_scm_pas_auth_and_reset` (`adreno_gpu.c:130-141`; `CONFIG_QCOM_SCM=y`).

**Dónde lee el kernel (hallazgo clave)**: `fw_get_filesystem_firmware`
(`drivers/base/firmware_loader/main.c:489-549`) abre vía `kernel_read_file_from_path_initns`
(`fs/kernel_read_file.c:147-172`) → `get_fs_root(init_task.fs)` = **root inicial del kernel = el
initramfs** (built-in s181 embebido en el Image de K13; `ramdisk_size@12 = 0` en boot-ukek13.img).
Cronología del boot #P40: arming K11 a 3,96 s → apps-smmu 3,97 s → UFS 4,18 s → open/fallo 4,203 s;
el `switch_root` del ukeinit (S123) va DETRÁS (monta userdata después de que UFS enumere). Por eso
el fw del rootfs (instalado 27-sep, `pacman -Qk` 14/0) no fue visto. En 27-sep (F1a, card0+renderD128
con s231) sí funcionó porque sin arming el open fue tardío, ya tras el switch_root (el overmount
cruza al rootfs real). Los paths de `firmware_class.path=` de la cmdline (`/vendor/firmware_mnt/…`)
no existen en el initramfs y se caen solos; `/lib/firmware` del initramfs decide.

## 2. Tabla pedido ↔ existente ↔ sha ↔ acción

| Driver pide (ruta 1ª / legacy) | Fuente en el PC (verificada hoy) | sha256 (manifiesto `firmware-gpu.sha256`) | En rootfs imagen / en tablet viva | Acción |
|---|---|---|---|---|
| `qcom/gen71100_sqe.fw` / `gen71100_sqe.fw` | `build/pkg/uke-gpu-firmware/gen71100_sqe.fw` (66 036 B; idéntico a `~/gpu-work/uke-staging/firmware/qcom/` y a `proyectos/ubuntu-uke/stock/firmware/`) | `b6df660d…08c401` | AUSENTE en arch-rootfs.img (debugfs: `File not found`) / instalado 27-sep | **copiar tal cual** (sin renombrar ni convertir) a initramfs + rootfs |
| `qcom/gen71100_gmu.bin` / `gen71100_gmu.bin` | `build/pkg/uke-gpu-firmware/gen71100_gmu.bin` (80 680 B; idéntico en staging/stock) | `435c7bac…bb864` | idem | **copiar tal cual** |
| `qcom/uke/gen71100_zap.mbn` (+ `qcom/palawan/`, `qcom/`, legacy por paridad con PKGBUILD) | `build/pkg/uke-gpu-firmware/gen71100_zap.mbn` (12 088 B, volcado vendor de ESTA tablet) | `0c86e4ae…5ea8e6` | idem | **copiar tal cual**. PROHIBIDO el del QRD `~/gpu-work/fw-qrd8635/gen71100_zap.mbn` = `a6a4265b…` (otra firma de SKU, `uke-staging/firmware/README.md`) |

Es **solo copiar/renombrar**: los 3 blobs ya llevan el nombre base que el catálogo/DT piden; nada
que convertir, nada que stripear.

## 3. Formatos: ¿crudo o mbn? (cita de código)

- **SQE**: microcode **crudo** — `a6xx_ucode_load` (`a6xx_gpu.c:1045-1062`) mete `fw[ADRENO_FW_SQE]`
  en un BO con `adreno_fw_create_bo` (memcpy del `fw->data` completo); sin parseo de cabecera.
- **GMU**: imagen con **block headers** `{u32 addr; u32 size; u32 type; u32 value; u32 data[]}`
  (`a6xx_gmu.c:855-860`); el bucle de `a6xx_gmu_fw_load` (`:901-933`) enruta cada bloque a
  ITCM/DTCM/icache/dcache. Nuestro dump vendor ya va en ese formato (el hermano lo usa en mainline
  desde 11-sep; SHA256SUMS publicado).
- **ZAP**: **mbn/MDT** (ELF con segmentos firmados) — `qcom_mdt_get_size`/`qcom_mdt_load`
  (`adreno_gpu.c:118-141`) + `qcom_scm_pas_auth_and_reset(GPU_PAS_ID)`; va firmado por SKU →
  imprescindible el de uke, no el del QRD.
- **Upstream linux-firmware**: NO tiene `gen71100_*` (G1 §2.4 lo verificó hoy por web: hay
  gen70500/70900/71500/71700; WHENCE sin menciones; `qcom/a730/`, `qcom/a740/` no existen). La única
  fuente es el volcado vendor, ya staged y paquetizado. **Conclusión: no hay conversión posible ni
  necesaria; solo colocación.**

## 4. Entregable: `build/gates/prepara/gpu-fw-fix.sh` (PROBADO, no flashea)

Tres modos, `bash -n` OK y ejecutado:

- `--check` (default, solo lectura): gate de los 3 shas contra el manifiesto, rechazo explícito del
  zap QRD, estado de arch-rootfs.img vía debugfs. **Ejecutado: 6 ok, 0 fallos.**
- `--initramfs` (PC): reconstruye el boot **cambiando SOLO `ramdisk_size@12` + añadiendo un initrd
  externo** (cpio newc, `gzip -9n`, 180 314 B) con las 8 rutas del paquete. Base con gate duro
  `sha == d71ea2b5…` (el boot-ukek13.img de #P40), delta confinado a @12 + región ramdisk, fin del
  ramdisk (16 765 018) muy por debajo de AVB0 (35 438 592), kernel byte a byte intacto, `/ukeinit`
  built-in (armado K11) NO se toca. Verificación triple: parser propio + `unpack_bootimg` (header v4,
  cmdline intacta) + `cpio -t` del sistema (12 entradas exactas). **Ejecutado hoy: rc=0.**
  Salida: `/var/tmp/u1-gpu-fw/boot-ukek13-fw.img`, sha `62192c2608ac5ce21144f1650314a6ad4cfc16c67b7f6e698b4db6767492a0fc`
  (100 663 296 B). El DUENO la flashea: `fastboot flash boot_b /var/tmp/u1-gpu-fw/boot-ukek13-fw.img`
  (rollback: `boot_b-lee.img` `ffff8c51…`). Precedente del initrd externo en esta ABL: K10 (boot
  verificado, INFORME-K10-BUILD.md G5/G8).
- `--ssh` (PC→tablet viva por USB NCM 192.168.42.129, key `build/rootfs/uke-arch-root`): gate
  ping+ssh+`uname -r` palawan → push de los 3 blobs a `/tmp` → instalación de las 8 rutas en
  `/usr/lib/firmware` → `sha256sum` de cada una contra el manifiesto → `sync` → limpieza. No
  reinicia ni toca servicios. (Pendiente de tablet, como toda la vía SSH.)

Predicción para el boot con la imagen nueva: misma consola pero `loaded qcom/gen71100_sqe.fw from
new location` (`adreno_gpu.c:547`), GMU `F1-fwloop→F4-verOK` + `Loaded GMU firmware v…`
(`a6xx_gmu.c:937`), `UKE-CM3DBG: dtcm-magic=…` (`:308-312`), `Z2-zapOK` (`a6xx_gpu.c:1494`) y
Arranque vivo → fbcon + SSH.

## 5. Riesgo: ¿cambia el desenlace tras la carga? (CM3)

Sí puede cambiar — y ese es el riesgo declarado de G1 §4, no uno nuevo: con el SQE cargado el CP
arranca, y el arranque del CM3 del GMU (`S1-rst1→S3-rst0→S4-poll` de
`REG_A6XX_GMU_CM3_FW_INIT_RESULT`, `a6xx_gmu.c:316-335`) queda expuesto: el hermano midió (24-sep)
wedge de bus en el **primer readl del sondeo** (`S3-rst0` sin `S4-poll`, sin watchdog ⇒ reset
físico). Si el `dtcm-magic` sale 0/basura, la imagen no llegó a la RAM que el CM3 fetcha (SMMU SID 5)
⇒ otro camino (escalera), no firmware.

Escalera ya a bordo del kernel K13: pokes `G1-bind/G2-initOK/G3-icc` (`adreno_device.c:241-251`),
`F1-F4` + `UKE-CM3DBG` (`a6xx_gmu.c:906-935, 308-312`), `S1-S4` (`:316-335`), `Z2-zapOK/FAIL`
(`a6xx_gpu.c:1494-1495`). Migas a mirar en el próximo boot, por orden: (1) que la línea de carga
SQE/GMU diga `from new location`; (2) `F4-verOK` + versión GMU; (3) `dtcm-magic` ≠ 0; (4) última
marca antes de cualquier muerte: `S3-rst0` sin `S4-poll` ⇒ wedge CM3 real ⇒ escalera fina
(`build/cm3-ladder/uke-cm3-ladder.diff`, canario L14) con `measure-cm3.sh` (su gate G1 de firmware ya
no debería dispararse). Distinción clave que sigue valiendo: atasco del helper (~60 s/fichero, firma
de fw ausente) ≠ wedge (muerte instantánea tras `S3-rst0`).

## 6. Gaps que quedan fuera de U1

- La tablet está EN FASTBOOT (orden del dueño, #P40): flashear `boot-ukek13-fw.img` es decisión del
  dueño (gate batería ≥3750, captura de consola activa, rollback a `boot_b-lee`).
- El rootfs de la imagen (arch-rootfs.img) sigue sin el paquete: si algún día se re-flashea el
  rootfs, correr `--ssh` (o `pacman -U` del paquete `uke-gpu-firmware-1-1-any.pkg.tar.zst`).
- El wrapper `--ssh` no se ha ejercitado contra tablet real (no hay tablet); la lógica remota es la
  del PKGBUILD verificado 27-sep y todos los shas van gateados.
