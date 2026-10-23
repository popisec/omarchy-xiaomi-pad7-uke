# BUILD-RECIPE-DORADA — receta exacta del kernel K49 que ARRANCA (forense #532, 6-oct-2026)

Objetivo: que el PRÓXIMO rebuild sea equivalente a la dorada
`boot-ukek49-esd-plyoff.img` (sha256 `6988dc7b4f94383503e655fe41c8a7096591d1813690fa56e98b791c41aeea67`,
banner `Linux version 7.2.0-rc2-palawan (uke@palawan) (clang version 23.1.1, LLD 23.1.1) #1 SMP PREEMPT Sat Oct  3 15:16:02 CEST 2026`).

Base de la receta: docs/historia/gates-palawan/build-k49.sh (el wrapper real que produjo la dorada),
build/logs/build-k49.log, y el análisis forense de build/gates/revision/FORENSE-BUILD-20261006.md.

## 0. Verdad incómoda (leer antes de "reconstruir")

1. **La dorada NO sale del repo git del kernel (`~/gpu-work/palawan-linux`).** Sale de
   `build/kernel-pokes/k18-tree/` — un árbol **gitignored** (omarchy-uke/.gitignore:28
   `build/kernel-pokes/`), SIN `.git` propio, con el ACUMULADO K18→K49 de pokes/fixes
   (SMMU diferido, printk tope consola, DPU/DSI/GMU, ESD…). `palawan-linux` NO es el
   mismo código: diff de 23 ficheros (arm-smmu.{c,h,-impl.c,-qcom.c,.h},
   gpucc-palawan.c, a6xx_gmu.c, dpu_*, dsi_*, panel, novatek, qcom_pd_mapper.c,
   uke-panic-fb.c, printk.c, xiaomi-uke.dts…). Compilar `palawan-linux` con la config
   de k49 NO reproduce la dorada ni de cerca.
2. **`uke@palawan` NO es otra máquina.** Lo falsifica el wrapper:
   `export KBUILD_BUILD_USER=uke` / `export KBUILD_BUILD_HOST=palawan`
   (build-k49.sh:62-63). El host real entonces y ahora es `pc-build`, mismo
   clang/LLD 23.1.1 (el comentario de cabecera del script "clang 22.1.8" es
   previo al upgrade del 2-oct: obsoleto).
3. **El `+` del banner (`7.2.0-rc2-palawan+`) NO es una dif de config.** Es
   scripts/setlocalversion: `palawan-linux` es repo git SUCIO → añade `+`;
   `k18-tree` no tiene `.git` → jamás añade `+`. Con
   `CONFIG_LOCALVERSION="-palawan"` y `# CONFIG_LOCALVERSION_AUTO is not set`,
   esa es toda la diferencia de release string.
4. **La dorada no lleva MÓDULOS.** `build-k49.sh` compila SOLO `Image.gz`
   (`make O=… -j4 Image.gz`). En el rootfs v8 no existe
   `/lib/modules/7.2.0-rc2-palawan` — prueba: en el boot dorado
   `modprobe@fuse.service` corre y NO aparece `fuse: init` (no cargó nada);
   los rebuilds que murieron sí cargaron módulos (`fuse: init` 16.37s,
   `cs_system_cfg` 17.056s). **Instalar `847 módulos palawan+` en la tablet es la
   diferencia OPERATIVA que mata en ~17 s** (coresight `=m` sondea y el SoC muere
   sin panic). Ver FORENSE-BUILD-20261006.md §4.

## 1. Entradas (pinadas)

| Entrada | Valor | Verificación |
|---|---|---|
| Fuente | `build/kernel-pokes/k18-tree/` EXACTO como está (no tocar, no regenerar) | `sha256sum` manifiesto (§5) |
| Config | `build/kernel-config/k49-pantalla.config` | copiada a `$O/.config` por el wrapper |
| Initramfs | `build/init/uke-k34-fw-initramfs.cpio.gz` | sha256 `ebc2de46ea89a4512be06b87e92d5dbb2f8aca8fe9a07304b697566551bf48bc` (1104021 B) |
| Toolchain | clang/LLD 23.1.1 (`clang --version`) | `CONFIG_CC_VERSION_TEXT` debe quedar `clang version 23.1.1` |
| Salida O= | `build/kernel-pokes/k49-build` | el wrapper la recrea |
| Base repack | `build/bootimg/boot-ukek13-dsid.img` (línea K18-dsid) | repack-k18.py G1: v4/1584, ramdisk 0 |
| Repack | `docs/historia/gates-palawan/repack-k18.py --kernel <Image.gz> --out …` | G3 gates de marcadores |

## 2. Comando (el wrapper es la receta; NO llamar a make a mano)

```bash
bash ~/proyectos/omarchy-uke/docs/historia/gates-palawan/build-k49.sh
# desprendido: re-lanza a sí mismo con UKE_BUILD_DETACHED=1 y log en
# build/logs/build-k49.log; espera ~14 min
```

Equivale EXACTO (lo que el wrapper ejecuta, verificado en build-k49.sh y en los
`.cmd` del build):

```bash
cd ~/proyectos/omarchy-uke/build/kernel-pokes/k18-tree
export MAKE=/usr/bin/make ARCH=arm64 LLVM=1
export KBUILD_BUILD_USER=uke KBUILD_BUILD_HOST=palawan
O=~/proyectos/omarchy-uke/build/kernel-pokes/k49-build
cp -f ~/proyectos/omarchy-uke/build/kernel-config/k49-pantalla.config "$O/.config"
make O="$O" olddefconfig
make O="$O" -j4 Image.gz        # -j4 como la dorada; NUNCA -j16 "por rapidez"
```

Notas de entorno:
- Si tu shell inyecta `MAKE`/`MAKEFLAGS` (env envenenado): `env -u MAKE -u MAKEFLAGS bash …`
  (el wrapper exporta MAKE=/usr/bin/make y eso basta dentro del script).
- Sin `CROSS_COMPILE` (LLVM=1, target nativo aarch64 vía `--target=aarch64-linux-gnu`).
- Sin `LOCALVERSION=` en el entorno (engordaría el release string).

## 3. Gates de build (los del wrapper; no saltarse ninguno)

1. `CONFIG_ARCH_QCOM=y` en `$O/.config` tras olddefconfig.
2. `CONFIG_INITRAMFS_SOURCE="…/uke-k34-fw-initramfs.cpio.gz"` (con fw GPU dentro:
   `gen71100_sqe.fw gen71100_gmu.bin gen71100_zap.mbn` listables en el cpio).
3. `CONFIG_INITRAMFS_COMPRESSION_GZIP=y`.
4. `[ Image -nt .config ]` (el build reconstruyó; la dorada abortó AQUÍ en un
   re-run a las 15:17 — abort benigno, la Image 15:16 era ya la buena).
5. Gates de marcadores sobre el Image crudo (UKE-K19…K49: GEO, CBbase, S2CR,
   SMMU dump, K38 attach, K41 tope consola, `\x013UKE-POKE:` presente y
   `\x014UKE-POKE:` ausente, ESD K49, migas `K47-*`…). OJO errata histórica: el
   run de 15:16 falló porque el script exigía `K49-crtc-en/K49-7nm-en/K49-pll-prep`
   y el árbol lleva los nombres `K47-*` (versión actual del script = correcta).

## 4. Repack (boot img dorado)

```bash
python3 ~/proyectos/omarchy-uke/docs/historia/gates-palawan/repack-k18.py \
  --kernel ~/proyectos/omarchy-uke/build/kernel-pokes/k49-build/arch/arm64/boot/Image.gz \
  --out boot-ukek49-esd-plyoff.img
# + los 7 tokens del append esd/plyoff (video=DSI-1:d, memmap, loglevel=4,
#   msm.uke_gmu_shared=0, arm_smmu.uke_kgsl_keep=0, hung_task_panic=0,
#   printk.always_kmsg_dump=0, plymouth.enable=0) → cmdline 517 B
```

Referencia del repack dorado: build/bootimg/repack-boot-ukek49-esd-plyoff-report.txt
(G0: Image.gz 16688015 B sha256 `d353356e30d4665b…`; G3: crudo 41421312 B,
initramfs @35336040; G7: 100663296 B, sha `6988dc7b…`).
El DTB/DTBO **no** se tocan: vienen de la base K13-dsid (byte a byte).
El Image.gz dorado SIGUE en el árbol: sha256 completo
`d353356e30d4665b63ec2a561c5505f719628580` (prefijo 40 hex del reporte).

## 5. Verificación de equivalencia (obligatoria tras cada rebuild)

```bash
O=~/proyectos/omarchy-uke/build/kernel-pokes/k49-build
# (a) config embebida == config de disco == la de la dorada
~/proyectos/omarchy-uke/build/kernel-pokes/k18-tree/scripts/extract-ikconfig \
  "$O/vmlinux" > /tmp/ik-nuevo.txt
diff /tmp/ik-nuevo.txt "$O/.config"            # vacío
# (b) tamaños: Image == 41421312 B exacto; Image.gz ~16.6-16.7 MB
stat -c%s "$O/arch/arm64/boot/Image"           # 41421312
# (c) banner: SIN '+', usuario/host falsificados, #1
strings "$O/vmlinux" | grep -m1 'Linux version'
#   → "7.2.0-rc2-palawan (uke@palawan) (clang version 23.1.1, LLD 23.1.1) #1 …"
# (d) initramfs embebido idéntico al pinado
llvm-objcopy -O binary --only-section=.init.ramfs "$O/usr/initramfs_data.o" /tmp/ir.bin
cmp /tmp/ir.bin <(cat ~/proyectos/omarchy-uke/build/init/uke-k34-fw-initramfs.cpio.gz)
# (e) flags: .cmd normalizando rutas == los de la dorada (ver forense §2)
# (f) repack: gates G0-G7 del reporte + sha PRE-registrado en gates/SHA-BUENOS.txt
```

Binario-idéntico NO es posible (compile.h/utsrelease llevan fecha/hora: la dorada
dice `#1 Sat Oct  3 15:16:02`); equivalente = (a)-(f) verdes y SOLO difieren
utsrelease/build-id.

## 6. Reglas operativas del flasheo/boot (parte de la receta)

- **NUNCA instalar `/lib/modules/7.2.0-rc2-palawan*` en la tablet.** La dorada es
  solo-Image; con módulos presentes, el coldplug de systemd carga CORESIGHT
  (`CONFIG_CORESIGHT=m`, CTI/TMC/STM) y la muerte a ~17 s vuelve.
- Rootfs v8 + cmdline dorada 517 B + dtbo s268: la combinación medida estable 2h12m.
- Arranque esperado: switch_root ~6 s, systemd ~6.5 s, en el timeout diferido
  (~13.8 s) SOLO re-sondean `arm-scmi.0.auto` y `soc:gpio_key`; dmesg SIN líneas
  `fuse:`/`coresight`/`CTI initialized`. Si aparece `fuse: init`, hay módulos
  instalados: PARAR y limpiar `/lib/modules`.
