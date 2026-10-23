# Bluetooth de la uke (WCN6750) — material de la etapa B0

Fecha: 18-oct-2026. Plan: [`build/gates/revision/BT-SENEMOS-20261018.md`](../../../gates/revision/BT-SENEMOS-20261018.md).
Informe de esta etapa (qué está verificado y qué no): [`build/gates/revision/BT-B0-20261018.md`](../../../gates/revision/BT-B0-20261018.md).

> **Nada de esto se ha aplicado a la tablet ni se ha cargado en ella.** Todo se generó y comprobó en el PC (sin
> ssh/adb/fastboot). Cargar los módulos y encender el chip (B2 en adelante) necesita orden expresa del dueño.

## Reproducir y verificar

```bash
build/rootfs/deploy/bt/build.sh          # ~1 min: overlays, fdtoverlay, arnés, módulos (2 builds), guarda, tests, manifiesto
build/rootfs/deploy/bt/build.sh --quick  # sin compilar los módulos
build/rootfs/deploy/bt/deploy.sh         # verifica todo el árbol y muestra el plan; NO abre ninguna conexión
```
`build.sh` termina en `RESULTADO: OK` o falla. Usa `make -C <senemos-build> M=<stage> LLVM=1 ARCH=arm64` con `MAKE` explícito y el
entorno de make limpio; **no modifica el árbol de build del kernel** (lo huella antes y después). Lánzalo desprendido si quieres:
`setsid nohup build/rootfs/deploy/bt/build.sh > /tmp/uke-bt-build.log 2>&1 &`.

## Contenido

| Ruta | Qué es |
|---|---|
| `dts/uke-bt.dtso` | Overlay único con tres variantes (`-DUART_ONLY` = U/B3, sin `-D` = B/B4+B7, `-DWITH_PA_RAIL` = A, exige kernel v4). `local-bd-address` lleva un **marcador** (`UKEBT!`), nunca una dirección real |
| `module/uke-ovl.h` | **Cargador genérico** de un overlay embebido (`.incbin` + `of_overlay_fdt_apply` en init / `of_overlay_remove` en exit). Lo reutiliza el audio (ver abajo) |
| `module/uke-ovl-patch.h` | Parte pura: parseo de la dirección BD y sustitución del marcador (la prueba `harness/test-patch.c` con ASan/UBSan) |
| `module/uke_bt_{uart,b,a}.c` + `Kbuild` | Los tres módulos: 5 líneas cada uno. `uke_bt_b`/`uke_bt_a` admiten `bdaddr=AA:BB:CC:DD:EE:FF` |
| `out/*.dtbo`, `out/*.ko` | Artefactos (reproducibles: mismo sha256 compilando en rutas distintas) y salidas de los chequeos (`out/*.txt`) |
| `check-bt.py` | Compara DT base y DT fusionado: nada fuera de la UART, propiedades cambiadas, phandles resueltos a sus etiquetas, rails, nombres de supply contra `hci_qca.c` |
| `root/` | `uke-bt.service` (After=uke-wifi, `/etc/uke/no-bt`, `ExecCondition=uke-bootguard begin bt`), `uke-bt-up.sh` y `uke-bt-fw.sha256` |
| `deploy.sh` | Despliegue por `tar \| ssh` por **partes**: `--fw` `--pkgs` `--module` `--service` `--bdaddr` `--arm` `--revert`; `--check` = solo lectura |
| `harness/` | `test-patch.c` (dirección BD), `test-bt-up.sh` (flujo de `uke-bt-up.sh` con mocks), `test-deploy-sim.sh` (`deploy.sh` contra un ssh simulado) |
| `MANIFEST.sha256` | shas de fuentes, `root/`, `.dtbo` y `.ko`; `deploy.sh` lo verifica antes de cualquier cosa |

## Etapas del plan ↔ comandos (todo con orden del dueño; ninguno enciende el chip salvo B4)

| Etapa | Qué | Comando |
|---|---|---|
| B1 | firmware rev 12 + bluez (ficheros inertes) | `deploy.sh --go --fw --pkgs` |
| B2–B4 prep | `.ko` en `extra/` + `depmod` (no se carga nada) | `deploy.sh --go --module` |
| B4 prep | dirección BD (confirmación interactiva en terminal) | `deploy.sh --go --bdaddr random` (o `AA:BB:..` / `--bdaddr-file`) |
| B7 prep | servicio sin habilitar + guarda con `bt` | `deploy.sh --go --service` |
| B3 / B4 | a mano, con ACM + `ssh dmesg -w` | `UKE_BT_VARIANT=u uke-bt-up.sh` / `uke-bt-up.sh` (`--down` descarga) |
| B7 | arrancar en cada arranque (solo tras B4 verde) | `deploy.sh --go --arm` |

El firmware (`msbtfw12.mbn`, `msnv12.bin`) **no se copia al repo**: `deploy.sh` lo lee de `build/android/` y exige sus sha256.
La dirección BD **no se versiona**: va de `deploy.sh` a `/etc/modprobe.d/uke-bt.conf` (modo 600) de la tablet. La blacklist de
`hci_uart` **se queda** (el servicio hace `modprobe` por nombre; ningún script de aquí la toca).

## Reutilizar el cargador para el audio (E0-f)

La sesión de audio no dejó cargador (solo lo menciona). Este vale tal cual: cada overlay es un `.c` de 4 líneas
(`UKE_OVL_NAME`, `UKE_OVL_DESC`, `#include "uke-ovl.h"`) más `CFLAGS_x.o := -DUKE_OVL_BLOB=\"/ruta/al.dtbo\"` en su `Kbuild`
(copiar `uke-ovl.h` y `uke-ovl-patch.h`, o `-I` a esta carpeta; sin `UKE_OVL_BDADDR` el patch no se usa y el módulo **rechaza**
un overlay con marcador). `rmmod` retira el overlay: **en orden inverso** al de carga (`of_overlay_remove` exige que sea el
último). Los `.dtbo` del audio llevan `/__symbols__` nuevos: `of_overlay_fdt_apply()` avisará de fuga de memoria al retirarlos
(benigno; ver `deploy/audio/README.md`). Este directorio no toca nada de `deploy/audio/`.
