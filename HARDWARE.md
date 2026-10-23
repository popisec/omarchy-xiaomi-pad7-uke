# Hardware

Referencia del aparato sobre el que se hizo el port. Todo lo de aquí está
**verificado** en el dispositivo; la fuente de cada dato se indica.

## Identidad

| | |
|---|---|
| Modelo | Xiaomi Pad 7 |
| Nombre en clave | `uke` (el del dispositivo y el de las particiones) |
| SoC | Qualcomm **SM7675** (Snapdragon 7+ Gen 3), aarch64 |
| GPU | Adreno 732 (Mesa/freedreno) |
| RAM | 8 GB nominales (medido `MemTotal` 7,2 GiB) |
| Almacenamiento | UFS (SK hynix) |
| Pantalla | 3200×2136 (vertical: 2136×3200), panel `o82` TDDI de doble DSI |
| Táctil | Novatek **NT36532** (SPI, QUP0 SE4) |
| Lápiz | Xiaomi Focus Pen (BLE, HID) |
| WiFi | Qualcomm **WCN6750** (ath11k) |
| Bluetooth | WCN6750 (uart) |
| Altavoces | amplificadores **FourSemi FS19xx** (TDM, SoundWire) |
| Cámaras | trasera **OV13B10** (13 MP, 4208×3120, chip-id `0x560d42`) con VCM `dw9714` y autofocus; frontal **OV08D10** (`0x5608`) |

## Particiones y arranque

El aparato **no arranca con UEFI ni U-Boot**: arranca con el `boot.img` de
Android en los slots A/B, y de ahí se encadena el rootfs de Arch.

```
ABL (bootloader de Qualcomm)
  └─ boot_a / boot_b        (Android boot.img; aquí va el kernel + initramfs)
       └─ initramfs         (init de Arch, cmdline rdinit=)
            └─ rootfs        (ext4 en userdata; el sistema Omarchy)
                 └─ Hyprland + Quickshell
```

| Partición | Para qué |
|---|---|
| `boot_a` / `boot_b` | Slots A/B. En cada uno va un `boot.img` con el kernel y el initramfs |
| `dtbo` | Overlays de device tree (panel, táctil, audio…). El proyecto los reempaqueta con `fdtoverlay` |
| `userdata` | Rootfs ext4 con Arch + Omarchy. Es lo que se restaura al flashear |
| `misc` | BCB (boot control block): el contador de slots y el flag de arranque |
| `vbmeta_boot` | Verificación de arranque (el proyecto trabaja con la imagen sin verificar) |

El proyecto **no reescribe el ABL**: usa el que trae la ROM y flashea solo
`boot`/`dtbo`/`userdata`. El `misc` en `reboot-bootloader` y el ext4 con ~908 errores
(medido el 26-sep, ver `docs/informes/B-arranque-arch-uke.md`) son la razón de las reglas de `REGLAS.md`.

## Slots

El `misc` (BCB) lleva el contador de reintentos por slot. La regla del proyecto:
**≤ 2 escrituras por día**, y si el contador del **slot activo** (no de uno concreto) baja de 3,
ese día es de solo lectura. El estado del slot se lee con `qbootctl` (`Successful N`), no leyendo
`slot-retry-count` a mano. Slot activo el 22-oct: **`_a`**, con `boot_b` como rollback.

## ROM base

La imagen de referencia del proyecto es la **fastboot ROM HyperOS** de la
variante `uke`, versión `OS3.0.303.0.WOZEUXM`. De ahí salen:

- `NON-HLOS.bin` (partición `modem`, FAT16) → WPSS (WiFi), ADSP, CDSP.
- `vendor`, `odm` y `/vendor/firmware_mnt` → ACDB de audio, `.fsm` de los
  amplificadores FS19xx, configs de cámara, calibración de sensores.

**Nada de eso se versiona en este repo.** Los scripts citan cada fichero por su
sha256 y su origen; ver la sección «Qué NO hay» del [README](README.md).

## Kernel

Hay **dos linajes**, y conviene no confundirlos:

| Linaje | Base | Cuándo | Estado |
|---|---|---|---|
| **palawan** | [palawan-mainline/linux](https://codeberg.org/palawan-mainline/linux), rama `palawan/v7.2-rc2` | 26-sep → 17-oct | **Histórico.** Sus parches están en `build/gates/patches/` y su receta en `build/gates/BUILD-RECIPE-DORADA.md` |
| **senemos** | [MCC45TR/senemos-uke-kernel-mainline](https://github.com/MCC45TR/senemos-uke-kernel-mainline) (MIT), commit `43e4036e`: Linux 7.2.9 + 78 parches, display DPU/DSI nativo para el panel o82 | 17-oct → hoy | **Vigente.** Se le suman los parches propios del proyecto |

En la tablet corría la variante `7.2.9-senemos.1.4054.3-ouke5` (v6). El estado exacto de cada
build está en [`docs/historia/ESTADO-VIVO.md`](docs/historia/ESTADO-VIVO.md) y en
[`build/gates/revision/`](build/gates/revision/).

⚠️ **7 unidades condicionan a `ConditionKernelVersion=*senemos*`** (`uke-wifi`, `uke-carga`,
`uke-bt`, `uke-audio`, `uke-audio-amps`, `uke-tapa` y `uke-usb-gadget-late`), y una octava
(`10-senemos-off.conf`) lo hace al revés: desactiva el `adsp` viejo en senemos. Con un kernel de
otro linaje **se omiten en silencio**: la tablet arranca, pero sin WiFi, BT, audio, carga ni tapa.

## Módulos

Los módulos propios (táctil, lápiz, tapa, BT, audio, cámaras) son **fuera del
kernel**: se compilan aparte y se cargan como `.ko` desde `extra/`. Sus fuentes
están en `build/rootfs/deploy/<tema>/`, sus scripts de compilación en
`build/gates/`, y los `.ko` **no se versionan**.

## Interfaces

| Interfaz | Para qué |
|---|---|
| `wlan0` | WiFi (ath11k) |
| `hci0` | Bluetooth (uart, con `hci_uart` parcheado) |
| `usb0` / RNDIS | SSH de respaldo sobre USB (`192.168.42.x`, rango estándar de Android) |
| Tailscale | Acceso remoto a la tablet (nodo `uke`) |
| `hw:UKE,2` | PCM de captura del micrófono interno (SoundWire WCD9395) |

## Fuentes de estos datos

- `docs/informes/A-port-omarchy-aarch64.md` — qué recompilar para aarch64.
- `docs/informes/B-arranque-arch-uke.md` — initramfs, cmdline, BCB, slots.
- `docs/informes/E-paquetes-aarch64-soc.md` — paquetes del SoC y sus fuentes.
- `build/gates/revision/` — informes por ciclo, con la evidencia de cada medida.
