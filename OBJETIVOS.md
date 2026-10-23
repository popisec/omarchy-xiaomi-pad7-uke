# OBJETIVOS — Omarchy en la Xiaomi Pad 7 «uke»

**Objetivo principal, en una frase:** una tablet que arranca Omarchy sola, se recupera de un
slot roto sin PC, actualiza sin abortar, y en la que se puede escribir con el lápiz y usar el
dedo con la pantalla rotada (criterio global de `F-plan-por-fases.md:1532-1534`).

Detalle y plan en `F-plan-por-fases.md`; estado de hoy en `docs/historia/ESTADO-VIVO.md`; histórico en
`NOTAS-OMARCHY.md`; índice en `docs/historia/G-auditoria-documental.md`. Aquí solo el qué y el cómo se mide.

## Objetivos medibles (cada uno con su «hecho»)

| # | Objetivo | Hecho = (medible) | Estado (actualizado 22-oct-2026) |
|---|---|---|---|
| 1 | No perder nada (F0) | `git status` limpio · par bueno verificado por sha256 **y reconstruible desde el repo** · `e2fsck` 2 pasadas rc=0 | 🔴 **PEOR que lo que se escribia**: el `e2fsck` en frio esta **rojo** (15 errores) y el ext4 va **sin journal**, con lo que cada corte corrompe un poco mas; el initramfs vivo **no es reproducible** (su generador consume un cpio base con firmware del fabricante). El backup del par y su sha si estan verificados |
| 2 | **F9: el slot A arranca imágenes nuevas** | Un `boot_a` nuevo llega a `Linux version` en consola | ✅ **HECHO 30-sep (#P45)**: cadena de B restaurada en A → boot completo hasta systemd; el slot A queda como slot experimental con fallback a B |
| 3 | Arch arranca y queda en SSH (F5) | `uname -m` = aarch64 · `/etc/os-release` = Arch · `ssh` desde el PC | ✅ Hecho (27-sep; hoy boot_b lleva K13-dsid `e0ee47dc…` estable — ver ESTADO-VIVO) |
| 4 | WiFi que sobrevive (F3) | `nmcli dev status` = connected + `uptime` > 300 s (no basta `ip link`) | ✅ **HECHO 18-oct**: `wlan0` con ath11k (WCN6750 + WPSS), conectado y estable. Informe `build/gates/revision/ARRANQUE-WIFI-ESCRITORIO-20261018.md` |
| 5 | GPU render + GLES sin display (F1a) | `eglinfo -B` = `freedreno` + GLES 3.2 (el nodo solo no vale) | ✅ **HECHO 17-oct**: `renderD128` + `eglinfo -B` freedreno/GLES 3.2 con el árbol «senemos» v2 (#658). El camino de depuración (CM3/GMU, dominios del SMMU) está documentado en `build/gates/revision/INVEST-WEB-PAD*.md` |
| 6 | Panel con KMS (F1b) | `card0` + `modes` del o82 + **foto** (el vfb no cuenta) | ✅ **HECHO 17-oct**: `card0` + panel o82 **con imagen** (senemos v2, #658). El 14-oct hubo luz (KTZ8866) pero imagen negra; la imagen llegó con el cambio de linaje de kernel |
| 7 | Táctil + lápiz en `/dev/input` (F4) | `libinput list-devices` lista el Novatek · `properties` bit 1 · `evtest` con presión ≠ 0 | ✅ **HECHO**: táctil Novatek NT36532 y lápiz Xiaomi Focus Pen (BLE/HID) funcionando, con presión y inclinación. Informes en `build/gates/revision/LAPIZ-20261018.md` y `build/rootfs/deploy/lapiz/` |
| 8 | Sesión Omarchy (F6) | `hyprctl version` 0.56.x · `pgrep quickshell` vivo · `Configuration Loaded` | ✅ **HECHO 18-oct**: Hyprland 0.56 (config Lua) + shell Quickshell + sesión Omarchy. Informe `docs/informes/C-hyprland-quickshell-aarch64.md` |
| 9 | Capa tablet usable (F7) | `texp-touch selftest` verde · 4 rotaciones con toques no espejados · OSK + trazo con presión | ✅ **HECHO 22-oct**: rotación automática, gestos, teclado en pantalla con predicción y autocorrección en español (11/11 con toques reales) y escritorio táctil. Informes `build/gates/revision/ESCRITORIO-TACTIL-20261022.md` |
| 10 | Producto (F8) | 3 reinicios limpios con retry 7 · `omarchy update` sin abortar · recuperación ejercida 1 vez | 🟡 **Parcial**: la tablet arranca en frío y sus módulos persisten (audio, BT, cámaras), pero la recuperación por fastboot/brick está documentada y **sin ejercitar**; hay un oops de slab de cámaras abierto (21-oct). Ver `build/gates/revision/PENDIENTES-INDICE-20261022.md` |

## Orden de prioridad (y por qué)

> **Reescrito el 1-oct-2026** con la orden del dueño: «pantalla + GPU del todo; el resto
> después». La versión anterior ponía K16 y WiFi por delante del panel, lo que ya no aplica.

1. **F1a (GPU) + F1b (panel) — JUNTOS.** Reescrito 9-oct: el muro S3-rst0 es el estado del dominio GMU (7 experimentos refutan las teorías software; INV-KGSL-RE da la secuencia vendor exacta). Pendiente: flash k64 (register_config vendor replicado) → si el CM3 vive, HFI→card0; si muere, diff de estados Android-vs-k64. Pantalla: encendido por SSH sin reflashear (PLAN-PANTALLA #547). Todo el trabajo
   reciente (#P44–#P49) es la rama del CM3 del GMU: el fetch del icache al liberar el CM3
   wedgea la máquina, y ese es el asesino **unificado** de pantalla y GPU. Objetivo del ciclo
   en curso: que la escalera del GMU pase de `S3-rst0` a `S4-pollOK` y, con eso, pintar el
   panel. Plan histórico de referencia: `docs/historia/PLAN-SIGUIENTE-v4.md` (1-oct). Los vigentes son `F` (fases) y
   `build/gates/revision/PENDIENTES-INDICE-20261022.md` (lo vivo).
2. **F3 (WiFi)** — solo cuando haya red de otra forma. La conexión por USB/NCM
   (`192.168.42.129`, `build/gates/uke-ssh.sh`) cubre el diagnóstico; el WiFi se intenta
   después porque resetear a ~7,3 s y ahora mismo no bloquea nada.
3. **F4 (táctil/lápiz) → F7 (capa tablet) → F6 (sesión Omarchy)** — en ese orden sobre lo
   anterior. El instalador está listo (`prepara/install-omarchy-uke.sh`) pero **no se ejecuta
   hasta que haya `e2fsck` verde** (particiona el disco si se deja correr).
4. **F8 (producto)** — 3 reinicios limpios con retry, `omarchy update` sin abortar y
   recuperación de slot ejercida. Depende de todo lo anterior.

**K16 ya no está aquí**: se ejecutó y quedó **refutado** (ledger #445: la familia SMMU no era
la asesina del modeset). K13/K16 quedan como historia en `NOTAS-OMARCHY.md`.

## Descartados (con su porqué: no volver a proponerlos)

| Descartado | Por qué (fecha / refutación) |
|---|---|
| Construir el repo Omarchy aarch64 (E R7) | `edge/aarch64` ya trae 148 paquetes con `omarchy-4.0.4-1` (26-sep, G §3.1) |
| Parche de Mesa para el a732 (F R3) | El kernel reporta `0x43030b00` (parsea el DT, no el silicio); retirado 27-sep (F2) |
| `pd-mapper` desde AUR (plan A) | Ya es in-kernel (`=m`); degradado a plan B 27-sep (F3) |
| Reorden MSI / MSI como gatillo del reset WiFi | Refutado por s247 (#437) y rematado por s248 (#441); queda temporizador firmware-TZ |
| «Espacio dtbo cerrado» / s251 culpable | Reabierto 28-sep: el aislamiento sin s251 también queda mudo (F9) |
| `bootctl` para los slots | Sin EFI (`Not booted with EFI`); la vía es `qbootctl` (27-sep) |
| Ejecutar `omarchy-install` | Particiona el disco: borraría el rootfs (27-sep) |
| DT propio antes de Omarchy (D2) | Diferido a después: con el `dtbo` vendor es optimización, no prerrequisito |
| Variante `wpss.mbn` por decidir | Cerrada empíricamente: `qmi firmware ready` (#434) |
| Pool swiotlb como plan B | Cerrado: pool de 64 MB funcionando, cero `-EIO` (#433) |

## Fuera de alcance (para no perder tiempo)

Cámara (sus GPIO 74/75 se reclaman para VSP/VSN) · OCR en el panel (panel sin OCR, D7c) ·
cifrado LUKS · Plymouth/splash · snapshots con arranque por menú (sin Limine) · dictado
(`voxtype`, x86-only) · ~13 entradas x86 del menú Install permanentemente muertas (F8) ·
publicar el port (D12: decisión, no objetivo).
