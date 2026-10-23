# Estado

Qué funciona en la tablet, qué no, y qué se rompe. **Fecha: 22-oct-2026** (lo medido
en la tablet) · repo actualizado el 23-oct-2026.

El detalle de cada medida, con su fichero y su fecha, está en
[`docs/historia/ESTADO-VIVO.md`](docs/historia/ESTADO-VIVO.md) (bitácora del
port) y en los informes de [`build/gates/revision/`](build/gates/revision/).

## Funciona

| | |
|---|---|
| **Arranque** | Arch Linux ARM desde el slot `_a` (`boot_b` como rollback), con `qbootctl` marcando el slot como arrancable a los ~130 s |
| **Escritorio** | Hyprland 0.56.2 (configuración Lua) + shell Quickshell 0.3.2 + Omarchy 4.0.6, con autologin |
| **Panel y GPU** | `card0` + panel o82 **con imagen** (3200×2136); Mesa 26.2.4 con freedreno y GLES 3.2 |
| **Táctil y lápiz** | Driver propio para el Novatek NT36532; lápiz Xiaomi Focus Pen por BLE con HID, presión y inclinación |
| **Capa tablet** | Rotación automática, gestos (10/10 medidos), teclado en pantalla con sugerencias y autocorrección en español (11/11), lanzador propio, dictado offline (Parakeet v3, WER 2,4 %) |
| **WiFi** | `wlan0` con ath11k (WCN6750 + WPSS) |
| **Bluetooth** | `hci0` con el `hci_uart` parcheado; A2DP y auriculares |
| **Audio** | Altavoces internos (FS19xx, TDM) y micrófono (WCD9395), persistentes desde el arranque |
| **Batería y carga** | Perfiles de energía, carga rápida, `zram` de 4 GiB, `earlyoom` |
| **Cámaras** | Trasera OV13B10 (13 MP) con autofocus por software y frontal OV08D10, en Megapixels 1.8.3 parcheado |

## No funciona (o falta verificar)

| | |
|---|---|
| **`omarchy update`** | Nunca se ha ejecutado: hay **14 migraciones** marcadas a mano que reescriben `pacman.conf` y reconstruyen el initramfs. No se ejecutan sin revisarlas |
| **Recuperación de slot sin PC** | El 22-oct hizo falta `misc` a ceros + `set_active` por fastboot. No hay procedimiento desatendido |
| **`e2fsck` en frío** | **Rojo**: 15 errores y el ext4 sin journal. Cada corte corrompe un poco más. El gate `--pre` del kernel v8a aborta por esto |
| **Cámaras al arrancar** | La carga al arranque está implementada pero **no verificada tras un reinicio**; el vídeo no está soportado |
| **Llavero de GNOME** | El keyring se desbloquea por systemd, pero la creación la tiene que hacer el dueño a mano |
| **Kernel v8** | Construido en el PC (`-senemos.1.4054.3-ouke8`), **sin flashear**. En la tablet corre el v7 (`0f86cd77…`) |

## Lo que está a medias

- `qcom_stats` no engancha (el módulo está sin flashear).
- El **motor de fondos** de la barra (`serpantinum`) consume ~250 MB de GPU; hay decisión
  abierta sobre si se queda.
- La tanda de batería sin cable está aplazada y el drenaje en s2idle sin medir.
- Coste del micrófono abierto, canal L/R y térmica de los altavoces: sin medir.

## Referencia rápida

| | |
|---|---|
| El aparato | [`HARDWARE.md`](HARDWARE.md) |
| Qué se puede reconstruir y qué no | [`BUILD.md`](BUILD.md) |
| La cadena del botón a la sesión | [`docs/ARQUITECTURA-ARRANQUE.md`](docs/ARQUITECTURA-ARRANQUE.md) |
| El mapa de todo lo demás | [`INDICE-DOCUMENTACION.md`](INDICE-DOCUMENTACION.md) |
| Las reglas (backup, sha256, presupuesto de ciclos) | [`docs/historia/REGLAS.md`](docs/historia/REGLAS.md) |
| Cronología del port | [`CHANGELOG.md`](CHANGELOG.md) |
