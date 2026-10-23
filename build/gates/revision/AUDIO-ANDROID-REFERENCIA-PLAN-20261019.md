# AUDIO — plan para comparar con Android funcionando (referencia de los FS19xx) — 19-oct-2026

**No se tocó la tablet.** Es un plan para decisión del dueño: **la vuelta a Android es DESTRUCTIVA para el Linux de `userdata`** (se borra) y deja la tablet fuera de Linux (BT, WiFi, táctil, escritorio… de las demás sesiones) durante la ventana.

## Por qué hace falta
Con Linux está medido que los 4 amps están vivos, ven el BCLK, aceptan el grafo y la cadena de Android, pero **no suena nada** y no hay referencia de cómo queda el estado de los FS19xx cuando SÍ suena (registros durante la reproducción, GPIO/pines/relojes, grafo AGM/PAL activo, logs del driver vendor). Con eso se contrasta lo que falta (configuración interna del amp, retorno V/I, protección, algún enable).

## Qué se volcaría (todo solo lectura; borrador `build/android/audio-ref-capture.sh`, sin ejecutar)
1. **Registros de los 4 FS19xx** por I²C-4 (0x34-0x37): volcado completo ANTES (silencio) y cada 0,5 s DURANTE la reproducción (por defecto 25 s), con `i2cdump -f -y 4 0xNN w` (busybox de Magisk) o un `i2cdump-ro` estático aarch64 propio (lo compilaría con el toolchain ya usado para fastrpc) usando `I2C_SLAVE_FORCE` en solo lectura (el driver vendor está ligado: sin escrituras).
2. **Mixer y rutas:** `tinymix` completo (FSM_Scene/Volume/Stop/AMP_ON, rutas TDM), `/proc/asound/{cards,pcm}`, `status`/`hw_params` de los PCM abiertos durante el sonido, DAPM de `debugfs/asoc`.
3. **Pines, relojes y alimentación:** `debugfs/gpio` (incluye LPI gpio6-9 y los reset/IRQ de los amps), `pinmux-pins`/`pinctrl-handles`, `clk_summary` (relojes IBIT del TDM y votos `lpass_audio_hw_vote`), `regulator_summary`, `interrupts`.
4. **Grafo y logs:** `dmesg` filtrado (`fsm_*`, `fs19xx_config_i2s/pll`, `fsm_speaker_onn`, tdm), `logcat -b all` filtrado (AGM/PAL: graph keys, módulos, formato del TDM), `lsmod`, DT vivo del nodo `sound` y de `i2c@88c000`.
5. Opcional: `adsp` del grafo en uso (si hay `debugfs/spf`/logs de AudioReach), y comparar con lo que enviamos (`TDM_INTF_CFG`, `HW_EP_MF_CFG`, `TDM_LANE_CFG`, `HW_INTF_CLK_CFG`, módulos MFC/SAL/SPLITTER).
Resultado esperado: las diferencias de registros y grafo entre «Android suena» y «Linux muda» señalan qué falta (la hipótesis más probable: algún registro/secuencia del amp o el retorno V/I/protección).

## Cómo se llega a Android (receta ya EJECUTADA dos veces, `docs/guias/LINUX-A-ANDROID-IDA-VUELTA.md`, `docs/historia/revision/ANDROID-HIST2-OMARCHY-20261016.md`)
Estado hoy: **Linux en slot a** (L76R), **slot b = Android HyperOS** (imágenes `build/android/flash-b/`: `boot-stock`, `init-boot-b-MAGISK`, `dtbo-b-stock`, `vendor-boot-stock`, dumps de vbmeta), con **userdata = rootfs Linux de 8 GiB**: Android **no arranca con ese userdata** (LV-R1) ⇒ hay que **borrar `userdata` y `metadata`**.
**Ida (manual del dueño en fastboot, filas LV-R10 pre-registradas en el ledger hermano):**
1. **Antes de nada: copia de seguridad de `userdata`** (rootfs 8 GiB) al PC por SSH/`dd` + sha256, y comprobar que se puede restaurar (`fastboot flash userdata <img>` ≈ 35 s). Sin esta copia **no se hace nada**. Comprobar el estado de los slots y la batería (≥ 3700 mV, cargador).
2. `fastboot erase userdata` + `erase metadata` + `flash boot_b/init_boot_b/dtbo_b` (si no están ya) + `set_active b` + `reboot` (LV-R1…R10: vbmeta no se toca, super jamás, slot a intocable, `misc` BCB limpio).
3. **Primer arranque de Android sobre userdata vacío**: asistente de HyperOS, activar opciones de desarrollador y ADB (autorización en pantalla), root por Magisk ya presente en `init_boot_b`, instalar el audio de prueba (`tone.wav`). Esto necesita **al dueño tocando la pantalla ~15-30 min**.
4. Captura con `audio-ref-capture.sh` mientras el dueño reproduce el tono (y también con un sonido del sistema), `adb pull`.
**Vuelta a Linux (receta D.2 del histórico):** `fastboot flash userdata <copia verificada>` → `boot_a` L76R/L73 (shas) con `set_active a` fresco (doble `set_active a/b`, LV-R7) → `reboot`; `misc` a ceros si Android dejó `bootonce-bootloader` (trampa BCB #241); ritual del `adsp.b40` en el primer SSH; comprobar `uke-audio`/`uke-bt`/`uke-wifi`.

## Riesgos
| # | Riesgo | Prob./impacto | Mitigación |
|---|---|---|---|
| 1 | **Pérdida del rootfs Linux** (`userdata` 8 GiB: paquetes, configuración, trabajo de todas las sesiones) | si falla la copia, cierta / **muy alto** | copia + sha + prueba de restauración ANTES; copia fuera de la tablet (PC); no borrar hasta verificarla |
| 2 | Tablet fuera de Linux 1-3 h: las demás sesiones (BT, WiFi, táctil, batería) no pueden trabajar | cierta / medio | avisar a las sesiones; hacerlo en ventana pactada |
| 3 | Trampa BCB / `slot-retry-count` / `set_active` mal (brick lógico) | baja / alto | reglas LV-R1..R10, `uke-slot-check.sh`, una escritura por ciclo, pre-registro en el ledger hermano |
| 4 | Android no arranca (userdata/metadata, vbmeta, AVB) | media / medio | receta ya validada dos veces; si falla, vuelta con la copia |
| 5 | El asistente exige cuenta/red: puede alargar | media / bajo | omitir; WiFi de casa |
| 6 | La referencia no aporta (el estado del amp con sonido no revela la diferencia) | media / bajo (coste en horas) | complementar con `logcat`/grafo AGM y con la comparación de GPIO/relojes |
| 7 | Batería: ABL/flash exigen ≥ 3450/3700 mV; en fastboot no carga | media / medio | cargador de pared, medir mV antes y después |

## Alternativa sin destruir nada
No hay una equivalente: no existe un volcado de Android con sonido real en el repo (las cosechas del 17-oct solo traen el estado en reposo, `tinymix` en idle y el `dmesg` de arranque con la inicialización del `fs19xx`, que ya replicamos). Una captura parcial sin sonido no resuelve la duda.

## Decisión que se pide al dueño
**(a)** ¿Se hace la ida a Android (con copia verificada de `userdata`, ventana pactada y manos del dueño en fastboot y en el asistente)? **(b)** Si sí: ¿cuándo, y qué se vuelca además (p. ej. captura de otros periféricos ya que Android estará vivo: cámara, vibración, sensores, que otras sesiones necesitan)?
