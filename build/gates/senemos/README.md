# `build/gates/senemos/` — reproducir el kernel del port

El kernel que usa la tablet **no es un blob**: se reconstruye desde fuentes
públicas y verificadas. Aquí está la receta, y está **probada**: se ejecutó de
cero y el árbol resultante coincide con el que se usó para compilar.

## De dónde sale cada cosa

| Pieza | Origen | Verificación |
|---|---|---|
| Código base del kernel | `https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.9.tar.xz` | sha256 `b4c5dfbe51a364a6c7f03869200f88c8e1f77403539005f14b7fc6bc91b8d8ba`, **idéntico al oficial y firmado de kernel.org**, y el mismo que declara el manifiesto del upstream |
| Parches y fuentes del display | [MCC45TR/senemos-uke-kernel-mainline](https://github.com/MCC45TR/senemos-uke-kernel-mainline) (MIT), commit `43e4036e` | El script comprueba el sha256 de los **44 parches de la serie y 3 configs** contra `manifests/linux-7.2.9.json` del propio upstream. Los **34 parches de boot/display** que el upstream aplica después se aplican con `git apply --check` previo, pero **sin comprobación de sha** |
| Config del kernel | [`../../kernel-config/senemos-ouke5.config`](../../kernel-config/senemos-ouke5.config) | Su sha **cambia con cada edición** (la ruta del initramfs es relativa al repo); compruébalo con `sha256sum`. El `instalar-config.sh` lo dice al instalarlo |
| Parches propios del proyecto | este directorio y `build/rootfs/deploy/*/kernel/` | ver abajo |

## Cómo se reproduce

```sh
# 1) el árbol fuente (descarga el tarball oficial y clona el upstream)
bash build/gates/senemos/reproducir-arbol.sh --dest build/kernel-pokes/senemos-7.2.9

# 2) los parches PROPIOS del proyecto
bash build/gates/senemos/deltas-senemos.sh

# 3) poner la config publicada en el directorio de build
bash build/gates/senemos/instalar-config.sh build/kernel-pokes/senemos-build

# 4) compilar (ver build/rootfs/deploy/audio/kernel/build-senemos-v4.sh)
```

La config versionada lleva el initramfs con ruta **relativa** al repo
(`build/init/uke-k34-fw-k52b2-initramfs.cpio.gz`) para que el fichero sea el
mismo en cualquier máquina y no lleve la ruta de quien lo compiló;
`instalar-config.sh` la copia al directorio de build y la convierte en
absoluta, que es como la resuelve kbuild.

`reproducir-arbol.sh` **no ejecuta ningún script del upstream**: replica a mano
sus pasos de preparación (los del `%prep` del spec y los tres `prepare-*.sh`),
comprobando el sha de cada fichero contra el manifiesto del upstream. Es la
misma precaución que se tomó al inspeccionar el clon por primera vez.

## Estado de la reproducción (verificado el 23-oct-2026)

Ejecutado de cero sobre este repo, el árbol resultante se comparó con el árbol
local del port (`build/kernel-pokes/senemos-ouke5/linux-7.2.9`, que está en la
máquina del autor y **no se publica**):

| | |
|---|---|
| Ficheros del árbol que difieren | **11 de 94.889** |

> ⚠️ **Esta comparación no es verificable desde el repo**: el árbol de referencia nunca se
> publicó (son GB de árbol compilable, y el `.gitignore` lo excluye). Lo que **sí** es
> verificable por un tercero es lo de la tabla siguiente: que la reproducción aplica 78
> parches limpios y produce un `config` que `olddefconfig` no toca.
| `arch/arm64/kernel/uke-abl.c` | **idéntico** (con `patches/0001-uke-abl-verdict-panic.patch`) |
| `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c` | **idéntico** (con los parches de audio 0002+0004) |
| `drivers/regulator/qcom-rpmh-regulator-uke.c` | **idéntico** (con el parche de cámaras 0045) |
| `panel-xiaomi-o82.c`, `o82-data.h`, `dpu_10_1_sm7675.h`, `uke-display-smmu.c`, `cliffs-display-icc.h`, `qcom-uke-display.h`, `uke-abl-native.h`, `uke-native-display.h` | **idénticos** |
| Los 4 `.dts` generados | Difieren **solo en la ruta del clon** que aparece en sus comentarios |

Las 11 diferencias que quedan, y por qué:

1. `uke-abl-overlays.h` — 45 bytes del overlay **USB** (el `dtc` del autor era
   otra versión). El blob **UFS** coincide byte a byte.
2. `native-generated/display*.dts`, `ufs.dts`, `usb.dts` — solo la ruta del clon
   en los comentarios de `cpp`.
3. `native-generated/reproducir-SHA256SUMS` — las sumas, lógicamente.
4. `native-generated/ouke1/`, `native-generated-v2/` — iteraciones del autor que
   no se reconstruyen (historia).
5. `senemos-adaptation/patches/series` — el autor añadió el 0045 a la serie.
6. `senemos-adaptation/patches/0045-uke-rpmh-camera-rails.patch` — el parche de
   cámaras, que **ya está versionado** en
   `build/rootfs/deploy/camaras/patches/`; aquí solo se copia al árbol.

⚠️ **Un matiz sobre el 0046** (SMMU de la IFE de las cámaras): el árbol local
`senemos-ouke5` es **del 17-oct** y **no lo lleva** — el parche es del 20-oct y
se aplicó a un árbol posterior. Por eso el árbol reproducido, con el 0046
aplicado, tiene *más* código de cámara que el del autor. No es una discrepancia.

## Los parches propios del proyecto

| Parche | Qué es | Dónde |
|---|---|---|
| `0001-uke-abl-verdict-panic.patch` | **El cuelgue mudo del ABL**: si el bootloader entrega un device tree ajeno, el upstream se queda en `cpu_relax()` infinito antes de que exista consola (cuelgue mudo, solo sale con reset físico). Este parche registra el veredicto y hace `panic()` desde un `early_initcall`, con lo que la tablet reinicia y el contador del slot registra el fallo | `build/gates/senemos/patches/` |
| `0002` + `0004` | SIDs de LPASS y de los compute-cb de FastRPC del ADSP | `build/rootfs/deploy/audio/kernel/` |
| `0045` + `0046` | Rails de cámara y SMMU de la IFE | `build/rootfs/deploy/camaras/patches/` |

El `0001` estaba **solo en el árbol local** del port: nadie más podía reproducirlo
sin la tablet. Ahora está versionado y aplica limpio sobre el árbol reproducido.

## Lo que sigue fuera del repo

- El **`initramfs`** (`build/init/uke-*-initramfs.cpio.gz`): lo genera
  `build/gates/mkcpio-*.py`, que hoy **no** están versionados (el `mkcpio-k50` y
  el `mkcpio-k51` sí lo están, pero el `k52b2` no).
- La **imagen base del rootfs** (4 GB): **no se publica**. Lleva dentro el firmware del
  fabricante, el hash de la contraseña de root, las claves SSH de host y rutas del entorno
  de quien la construyó. Se publica la receta (`../../BUILD.md` §2.4).

## El `boot.img` base: cómo se saca, y por qué no está aquí

El `boot.img` es **material del fabricante**: la política del proyecto (README,
«Qué NO hay») es no redistribuirlo, y la CI lo bloquea. Lo que sí se publica es
**cómo sacarlo** y con qué sha comprobarlo:

```sh
# con la tablet en fastboot
bash build/gates/senemos/extraer-boot-base.sh --out build/bootimg/boot-base.img
```

El sha256 esperado (el de la base que usa el repack del port) es
`e3c60969269c0b36f23a37db5b1772128891232517c8d7979bd967b88acab206`, y el script
lo comprueba. Ojo: lo que sale de la tablet es el `boot` **original** de
Android; el intermedio del port (`boot-s240-mem2g.img`, con el kernel de
memoria ajustada) se genera con los scripts de repack.
