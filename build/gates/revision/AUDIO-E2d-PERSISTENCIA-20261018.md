# AUDIO — E2d persistente al arranque: paquete preparado en el PC (SIN instalar) — 18-oct-2026

Orden del dueño: «haz persistente E2d al arranque (updates/snd-q6apm.ko, uke_audio_e2d, apr, con servicio y uke-bootguard tras uke-carga), sin flashear; antes de instalar, preparas el paquete en el PC y me avisas». **No se tocó la tablet.**

## Paquete (`build/rootfs/deploy/audio/boot/` + `out/`)
| Pieza | Qué hace |
|---|---|
| `boot/root/usr/local/sbin/uke-audio-up.sh` | espera ADSP running (≤60 s), `modprobe uke_audio_e2d` (overlay) y `modprobe apr` (autocarga `snd_q6apm` parcheado de `updates/`, `q6prm`, `q6prm_clocks`), espera `uke: estado APM (async) = 1` y `q6prm_clocks`. exit 0 VERDE · 2 AMARILLO · 3 ROJO (CMD timeout / apr falla: retira el overlay) · 1 requisito (kernel ouke4, snd-q6apm de `updates/`, vermagic, sin overlay alternativo e2, ADSP). `--down` descarga en orden inverso; `--status` solo lectura. No escribe en remoteproc ni toca slots. |
| `boot/root/etc/systemd/system/uke-audio.service` | oneshot tras `uke-carga.service`; `ConditionPathExists=!/etc/uke/no-audio` y `!safe-mode`; `ExecCondition=uke-bootguard begin audio`, `ExecStartPost/StopPost=uke-bootguard ok audio`; `SuccessExitStatus=2`; sin `ExecStop`. |
| `boot/root/etc/modprobe.d/uke-audio.conf` | `options snd_q6apm uke_trace=0` (sin traza por paquete). |
| `boot/deploy.sh` | `--module` (`uke_audio_e2d.ko`→`extra/`, `snd-q6apm-uke.ko`→`updates/snd-q6apm.ko`, conf, depmod), `--service` (servicio SIN habilitar + script + `uke-bootguard` + LEEME), `--arm` (enable + reset de la guarda), `--revert`, `--check` (lectura). Nada de lo que instala se carga. Sin `--go` ni `--check` solo verifica en el PC y no abre conexión. |
| Guarda | `deploy/arranque/uke-bootguard` conoce ahora `audio` (`KNOWN="wifi desktop bt audio"`), LEEME con `no-audio`, `test-bootguard.sh` con bloque audio, MANIFEST regenerado. Tests: **TODO OK**; `arranque/deploy.sh check` OK. |

## Verificado (PC)
`boot/deploy.sh` (sin `--go`): vermagic de ambos `.ko` = `7.2.9-senemos.1.4054.3-ouke4`; `harness/test-audio-up.sh` con mocks: **20 ok / 0 fallos** (requisitos, VERDE, AMARILLO×2, ROJO×2, retirada del overlay si apr falla, doble ejecución, `--down`, `--status`, el script no toca remoteproc); `test-bootguard.sh`, `arranque/deploy.sh check`. `systemd-analyze verify` en la tablet queda para `--service` (en el PC solo avisa de rutas ausentes).

## Qué haría el siguiente paso en la tablet (con tu orden)
1. `boot/deploy.sh --go --module --service` (escribe ficheros, **no carga ni habilita**): `.ko` en `extra/` y `updates/`, `/etc/modprobe.d/uke-audio.conf`, servicio + script + `uke-bootguard` nuevo (conoce `audio`) + LEEME, `depmod`, `daemon-reload`. Riesgo: nulo para el ADSP (no carga); el `snd-q6apm` de `updates/` pasa a ser el que cargue cualquiera que haga `modprobe snd-q6apm` (hoy nadie: `apr` está en la blacklist). 
2. Prueba a mano `ssh … uke-audio-up.sh` (como ya hecho en caliente: APM estado 1). Riesgo: el medido en E2d (un comando de estado + probe de q6prm); reversa `uke-audio-up.sh --down`.
3. `--arm` (enable). Riesgo: es un **arranque en frío sin probar**: carga `apr`/q6apm justo tras `uke-carga`. La guarda lo omite tras 2 arranques fallidos seguidos; `touch /etc/uke/no-audio` o `safe-mode` lo apagan; un cuelgue exigiría reset físico (el ADSP lleva `recovery=disabled`).
Revertir todo: `boot/deploy.sh --go --revert` (deshabilita y borra; si estaba arriba, antes `uke-audio-up.sh --down`).

## Nota
Esto solo hace que **q6apm/q6prm queden levantados al arrancar**; no suena nada todavía (faltan E3 pinctrl/relojes, E4 DAIs/DMA, TDM + driver FS19xx de los altavoces).

---
# Resultado de la prueba a mano de `uke-audio-up.sh --service` (18-oct 16:08) — **VERDE**
Orden del dueño. Gate: 3871 mV, Charging, ADSP/WPSS running, vigía + ACM. Log `build/logs/audio/up-20261018-tablet.log`.
- `uke-audio-up.sh --service` (tablet en ouke4, `fastrpc.ko` cargado sin uso): `ADSP running… cargo el overlay e2d y apr` → **`VERDE: APM estado 1 y q6prm_clocks cargado`** en <1 s, exit 0. Cargados: `uke_audio_e2d`, `apr`, `snd_q6apm` (el de `updates/`), `q6prm`, `q6prm_clocks`.
- Estado tras la prueba (se **deja cargado**, orden del dueño): ADSP/WPSS running, `Charging`, wlan0 UP, sin faults.
- Dos observaciones ajenas al audio: (1) el vigía registró `wlan0` down→dormant→up entre 16:08:24 y :32 (≈6 s) — coincide con actividad de otras sesiones (WiFi); no hay errores de ath11k/ADSP, y no se pudo atribuir con certeza; (2) un ciclo de **suspensión s2idle de 0,7 s** (`PM: suspend entry/exit` a 2150 s) **con audio cargado**: la tablet resumió sin problema y el ADSP siguió running (primer dato de suspensión con la pila AudioReach arriba).
- Pendiente: `--arm` (habilitar al arranque; arranque en frío sin probar) y comprobar el reinicio en frío; el siguiente paso técnico real es E3/E4.
