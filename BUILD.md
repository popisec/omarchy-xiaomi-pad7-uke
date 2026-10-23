# Build

Qué se puede reconstruir desde este repo, qué no, y qué hace falta.

> El repo contiene el **código** y los **informes**, no los
> artefactos. Lo que se reproduce aquí es el **árbol de fuentes del kernel** (con
> su config y sus parches); lo que **no** se reproduce es el `boot.img`, la
> imagen base del rootfs, el initramfs y los paquetes de Omarchy, porque son
> material del fabricante o material que pesa demasiado y lleva datos que no
> deben publicarse (ver §2).

## 1. Lo que sí es reproducible

| Qué | Cómo | Notas |
|---|---|---|
| Rootfs de Arch ARM + Omarchy | `build/rootfs/mk-rootfs-l76.sh`, `build/rootfs/deploy/omarchy/deploy.sh` | Necesita el rootfs base y los blobs del fabricante (ver §4) |
| Módulos propios (táctil, lápiz, tapa, BT, audio, cámaras) | `build/gates/compilar-panel-o82.sh` y hermanos | Compilan contra el árbol de kernel; salen `.ko` fuera de git |
| Overlays DT (`dtbo`) | `charge/mkdtbo-s28*.py` | La **base** del overlay (un `dtbo` de Android) no se publica: ver §2 |
| `boot.img` | `build/gates/repack-*.py` | Parte de un `boot.img` **externo** (ver §2), no del repo |
| Plugin de la shell (teclado en pantalla, barra, cargador) | `build/rootfs/deploy/plugins-tablet/deploy.sh`, `.../touch-mode/deploy.sh` | QML + Python, sin dependencias del fabricante |

## 2. Lo que NO es reproducible (y por qué)

> **Resumen, para el que solo quiere saber si puede arrancar su tablet: casi, pero no.**
> El **árbol de fuentes del kernel ya es reproducible** (tarball oficial + upstream público +
> parches propios; 78 parches aplicados limpios, config válida con `olddefconfig`). Faltan
> **cuatro** cosas para llegar al escritorio:
>
> 1. el **`initramfs`** de la variante viva (su generador no está versionado),
> 2. un **script de build** de esa variante (el que hay compila la ouke4),
> 3. la **base del `boot.img`**, que es material del fabricante (se publica cómo sacarla),
> 4. los **.pkg de la capa Omarchy** (342) y el **firmware de carga** (56 blobs), que no se
>    publican por política.

### 2.1 El kernel: dos linajes

| Linaje | Qué es | Estado |
|---|---|---|
| **palawan** (26-sep → 17-oct) | Rama `palawan/v7.2-rc2` de [palawan-mainline](https://codeberg.org/palawan-mainline/linux) + los parches de `build/gates/patches/`. Sus scripts de build son los `build/gates/build-k*.sh` y su receta forense, `BUILD-RECIPE-DORADA.md` | **Histórico** |
| **senemos** (17-oct → hoy) | [MCC45TR/senemos-uke-kernel-mainline](https://github.com/MCC45TR/senemos-uke-kernel-mainline) (MIT) @ `43e4036e`: Linux 7.2.9 + 78 parches, con **display DPU/DSI nativo** para el panel o82. Los scripts son los `build/gates/flash-senemos-v*.sh` | **Vigente** |

El kernel que arrancaba el 22-oct-2026 era `7.2.9-senemos.1.4054.3-ouke5` (v6), en el slot `_a`.

**Del linaje vigente sí se publica**: su `.config` (`build/kernel-config/senemos-ouke5.config`),
sus **parches propios** sobre ese árbol (`build/gates/senemos/patches/0001-*`,
`build/rootfs/deploy/camaras/patches/0045-*`, `0046-*`, y los de audio en
`build/rootfs/deploy/audio/kernel/`) y la **receta para reconstruir el árbol**:
[`build/gates/senemos/reproducir-arbol.sh`](build/gates/senemos/reproducir-arbol.sh).

⚠️ **Lo que NO llega hasta el final**: el árbol se reconstruye, pero **compilarlo** y
**empaquetarlo** todavía necesita el `initramfs` de la variante viva y un script de build de
esa variante (el `build-senemos-v4.sh` que hay compila la ouke4 y pide configs que no se
publican). Ver §2.4.

**El linaje palawan tampoco era reproducible desde el repo**, y su análisis forense lo explica:
la build «dorada» salía de `build/kernel-pokes/k18-tree/`, un árbol **gitignored** sin `.git` propio
con el acumulado de pokes K18→K49, y `palawan-mainline` **no** es el mismo código (diff de 23
ficheros). El banner `7.2.0-rc2-palawan+` tampoco era una diferencia de configuración: el `+` lo
añadía `scripts/setlocalversion` porque el árbol era un repo git **sucio**. Está en
[`build/gates/BUILD-RECIPE-DORADA.md`](build/gates/BUILD-RECIPE-DORADA.md) y en
`build/gates/revision/FORENSE-BUILD-20261006.md`.

### 2.2 Las otras tres entradas que faltan

| Falta | De dónde sale hoy | Por qué no está en el repo |
|---|---|---|
| Árbol de fuentes del kernel | ✅ **ya es reproducible**: `build/gates/senemos/reproducir-arbol.sh` (tarball oficial de kernel.org + upstream público + parches propios) |
| `.config` del kernel vigente | ✅ **ya está versionado**: `build/kernel-config/senemos-ouke5.config` (pasa `olddefconfig` sin cambiar una línea) | — |
| **Compilar el kernel** | ✅ `build/gates/senemos/build-ouke5.sh` produce un `Image.gz` con el vermagic `7.2.9-senemos.1.4054.3-ouke5` | hace falta el initramfs, o compilar con `--sin-initramfs` |
| Imagen base del rootfs | ❌ **no se publica**: lleva dentro el firmware del fabricante (adsp, cdsp, wpss), el hash de la contraseña de root, las claves SSH de host y rutas del entorno de quien la construyó — justo lo que la política de este repo declara no redistribuir. Se publica **la receta** (§2.4) | — |
| `boot.img` de arranque | `~/gpu-work/ramaa/s21/avb/boot-s240-mem2g.img` (proyecto hermano) | Artefacto de otro proyecto |

### 2.3 Lo que sí está y sí funciona

- Los **parches** del kernel, con su contexto y su historia.
- Los **overlays DT** (`charge/mkdtbo-*.py`), salvo la imagen base.
- Todos los **despliegues** sobre la tablet (audio, bt, táctil, lápiz, cámaras, batería, carga,
  suspensión, tapa, wifi, omarchy, plugins), con sus `deploy.sh` y sus manifiestos de sha256.
- Los **servicios** y el `bootguard`, que son lo que hace que la sesión Omarchy levante sola.
- La **documentación** de cada ciclo, con la evidencia.

### 2.4 Qué haría falta para que un tercero lo reprodujera

1. ✅ **Hecho**: el árbol de fuentes del kernel se reproduce con
   [`build/gates/senemos/reproducir-arbol.sh`](build/gates/senemos/reproducir-arbol.sh)
   (tarball oficial de kernel.org + upstream público + parches propios), y el `.config`
   está versionado. Verificado: 11 diferencias de ~80.000 ficheros.
2. La **imagen base del rootfs**: se *construye*, no se publica. Publicar la imagen lleva dentro
   el firmware del fabricante, el hash de la contraseña de root, las claves SSH de host y rutas
   del entorno de quien la hizo. Lo que se publica es la receta (§2.4).
3. El `boot.img` base **tampoco se publica** (material del fabricante; la CI lo bloquea). Se publica
   `build/gates/senemos/extraer-boot-base.sh`, que lo saca de la tablet con `fastboot fetch boot`.
4. Fijar la toolchain (ver §3) con su procedencia. ⚠️ La config del kernel lleva
   `CONFIG_CC_VERSION_TEXT="clang version 23.1.3"`, pero la build de referencia se hizo con
   **23.1.1**: el banner (y con él los sha que comparan los gates de flasheo) cambia.
5. Versionar el generador del initramfs de la variante viva (`mkcpio-k52b2`) y un script de
   build para la ouke5 (el que hay, `build-senemos-v4.sh`, compila la ouke4 y pide configs que no
   se publican).

## 3. Requisitos del host

Para los builds de kernel (el host de referencia es un x86_64 con Arch):

| Herramienta | Versión | Para qué |
|---|---|---|
| `clang` + `lld` | **23.1.1** (la de referencia) | Compilar el kernel. ⚠️ La versión **cambia el banner** (`CONFIG_CC_VERSION_TEXT`) y con ella los gates que comparan sha. En Arch actual ya viene 23.1.3: o se instala 23.1.1 aparte, o se ajustan los gates |
| `make`, `bc`, `flex`, `bison`, `libelf`, `openssl` | — | Kbuild |
| `dtc`, `fdtoverlay` | — | Device trees y overlays |
| `abootimg`, `mkbootimg` | — | Empaquetar `boot.img` |
| `e2fsprogs` (`debugfs`, `e2fsck`) | — | Montar y reparar el rootfs |
| `python3` | 3.11+ | Los scripts de análisis y de despliegue |
| `qemu-user-static` (aarch64) | — | Ejecutar herramientas ARM en el host |

Regla del proyecto: **los builds se lanzan siempre desprendidos**
(`setsid nohup … &`) con `MAKE=/usr/bin/make` y `ARCH=` explícitos, porque en
primer plano el `make` puede ser un no-op silencioso y un «build OK» vacío es
indistinguible de uno bueno.

## 4. Los blobs que hay que traer de fuera

Ninguno se versiona. Cada script que los necesita cita **sha256 y origen**:

| Qué | De dónde |
|---|---|
| Firmware WPSS / ADSP / CDSP | `NON-HLOS.bin` de la fastboot ROM HyperOS `OS3.0.303.0.WOZEUXM` (partición `modem`, FAT16, se abre con `7z`) |
| ACDB de audio, `.fsm` de los FS19xx, configs de cámara, calibración de sensores | `vendor`, `odm` y `/vendor/firmware_mnt` de la tablet |
| `qca/msbtfw11.mbn`, `ath11k/WCN6750/hw1.0/board-2.bin` | `linux-firmware` de Arch (ya es libre) |
| `boot.img`, `dtbo.img`, `vendor_boot` | La propia tablet o su ROM |

Ver la sección «Qué NO hay» del [README](README.md) y los `PKGBUILD` de
`build/pkg/`, que llevan el sha256 de cada blob.

## 5. Verificar el clon sin la tablet

```sh
make check        # referencias a ficheros, duplicados y sintaxis de los scripts
make help         # todos los atajos
```

Y la CI (`.github/workflows/ci.yml`) comprueba en cada push que no entren secretos, que no se
versionen blobs del fabricante, que el árbol respete el `.gitignore`, que ninguna referencia a un
fichero del repo se rompa y que no haya ficheros duplicados.

## 5-bis. Lo que un tercero SÍ puede hacer hoy

- **Leer y entender el port**: los 7 informes de partida, el plan por fases, la bitácora y los
  informes por ciclo.
- **Auditar los parches** del kernel y los overlays DT.
- **Revisar y reejecutar los despliegues** sobre una tablet que ya tenga Arch instalado: los
  `deploy.sh` llevan sus gates (sha256 de lo que instalan, vermagic del módulo, firmware presente).
- **Montar su propio entorno de compilación**: los scripts compilan y emiten sus `.ko`; lo que no
  está es el árbol de fuentes y el `.config` (ver §2).

Lo que **no** puede es arrancar la tablet desde cero con lo que hay aquí: faltan el `initramfs` de
la variante viva, un script de build para esa variante, la base del `boot.img`, los 342 `.pkg` de la
capa de Omarchy y los 56 blobs de firmware de carga (§2).

## 6. Fases del port

El plan ejecutable, con el orden y los criterios de «hecho» medibles, está en
[`F-plan-por-fases.md`](F-plan-por-fases.md) (F0–F8, 32 riesgos, 20 decisiones (D1–D20)
del dueño) y su índice en [`docs/historia/G-auditoria-documental.md`](docs/historia/G-auditoria-documental.md).
