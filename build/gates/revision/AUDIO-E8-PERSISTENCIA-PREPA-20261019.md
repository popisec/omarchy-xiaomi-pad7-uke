# AUDIO E8 — persistencia de los altavoces al arranque: preparación y riesgos (19-oct-2026)

Preparado SOLO en el PC; la tablet no se ha tocado (solo un `--check` de lectura: los 4 `.ko` y el preset ya están en `extra/` con shas idénticos a los locales).

## Qué se añade (`build/rootfs/deploy/audio/boot/`)
| Fichero | Función |
|---|---|
| `root/usr/local/sbin/uke-audio-amps-up.sh` | Etapa 2: `modprobe` e7i2c → e3 → pinctrl-sm8650-lpass-lpi → uke_fs19xx → (espera probe) → e8b; espera la tarjeta `UKE` y activa `PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1`. Exit 0 VERDE / 2 AMARILLO / 3 ROJO / 1 requisito. `--down`, `--status`. |
| `root/etc/systemd/system/uke-audio-amps.service` | `Requires=uke-audio.service`; mismos interruptores (`/etc/uke/no-audio-amps`, `no-audio`, `safe-mode`) y misma guarda `uke-bootguard begin/ok audio` (comparte el contador 'audio'). Sin ExecStop. |
| `root/etc/modprobe.d/uke-audio-amps.conf` | `uke_fs19xx uke_fs_play=1 uke_fs_vol=224 uke_fs_volmax=224` (0xE0 = nivel del tono que el dueño oyó; Android usa 235-243). |
| `harness/test-audio-amps-up.sh` | 18 pruebas con mocks (requisitos, orden de carga, VERDE/AMARILLO/ROJO, `--down`): 18 ok, 0 fallos. |
| `deploy-amps.sh` | `--module` (copia .ko+preset+conf, depmod), `--service` (sin enable), `--arm` (enable + reset guarda), `--revert`; sin `--go` solo verifica. No carga ni reinicia nada. |

## Procedimiento propuesto (cada paso con tu autorización)
1. `deploy-amps.sh --go --module --service` (solo ficheros). 2. En caliente: `uke-audio-amps-up.sh` a mano con vigía y doble captura; tono corto a 0xE0; `--down` no (reiniciar si hay oops).
3. `deploy-amps.sh --go --arm` y un reinicio en frío (sync, aviso a la sesión BT) con consola ACM armada. 4. Confirmación auditiva tras el arranque.

## Riesgos
- **Primer arranque en frío sin verificar** (la carga en caliente sí está medida). Un cuelgue exige reset físico; la guarda cuenta el fallo y con 2 seguidos omite audio. Corte rápido por SSH: `touch /etc/uke/no-audio-amps`.
- **Sin protección FSADSP** (excursión/térmica de Android): `uke_fs_volmax` es el único tope. Defecto 0xE0; subirlo solo con medidas. Por eso `uke_fs_play=1` se limita a quedar habilitado mientras suena un PCM; al parar, los amps se paran.
- **Pila ASoC/ADSP frágil**: un fallo de `audio_process` es fatal (recovery desactivado); S24 está prohibido (solo S16). Nada abre el PCM al arrancar salvo un cliente de audio.
- **Orden/e3**: el overlay e3 (pines LPI) se carga ahora en cada arranque; si falla, no se carga la tarjeta (ROJO). Un overlay que no es el último no se puede retirar (`--down` en orden inverso).
- **BT/WiFi**: los módulos no tocan WL_EN/BT_EN, pero la sesión BT investiga el mismo arranque; coordinar el reinicio.
- **Escritorio**: no hay perfil PipeWire/UCM; el sonido solo llegará por ALSA directo (`hw:UKE,0`, S16, 48 kHz) hasta una etapa posterior. Solo la fila 6,144 MHz de la tabla PLL está verificada contra Android.

## Reversa
`deploy-amps.sh --go --revert` (deshabilita y borra servicio, script y conf; los `.ko`/preset son inocuos sin carga) o `touch /etc/uke/no-audio-amps`.

## Resultado de la prueba en caliente (19-oct-2026 10:22, `--service` a mano)
`--service` en caliente: VERDE en ~22 s (e8b tarda ~20 s en registrar), tarjeta `UKE`, mezclador activado, 4 amps DEVID 0x2900, `uke_fs_play=1 vol=0xe0 tope=0xe0`.
Tono 1 kHz −24 dBFS, 2 s, vol 0xE0: **el dueño lo oye**. Vigía sin oops (solo `wlan0=down`, preexistente). Capturas: `build/logs/audio/e13-20261019-dmesg.log`.
Siguiente: `--arm` + reinicio en frío (autorización aparte, aviso a la sesión BT).
