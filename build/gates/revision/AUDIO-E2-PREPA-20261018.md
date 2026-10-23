# AUDIO — preparación de E2 (PC; la tablet solo se leyó) — 18-oct-2026

## Hecho
- **Cargador de overlays**: la sesión BT ya había escrito uno genérico (`deploy/bt/module/uke-ovl.h`). Copiado sin cambios a `deploy/audio/module/` y usado en `uke_audio_e2.c` (5 líneas).
  `deploy/audio/build-module.sh` → `out/uke_audio_e2.ko` sha256 `3c1f35341cd8810137afa3589c8798d5f59c8cb68bee6e421dca855d7a6cfa42`, 0 avisos, `depends:` vacío,
  vermagic `7.2.9-senemos.1.4054.3-ouke3 SMP preempt mod_unload aarch64` = `uname -r` de la tablet (MEDIDO por ssh, solo lectura). Árbol de build del kernel sin modificar (se compila con `M=` externo).
- **Vigía**: `deploy/audio/vigia-adsp.sh` (solo lectura, se lanza en la tablet con setsid): alarma si adsp≠running, recovery≠disabled, battmgr≠Charging o voltaje congelado 20 s, wpss≠running, wlan0≠up; filtra dmesg a `/root/vigia-adsp-dmesg.log`. `bash -n` OK; **no ejecutado todavía**.
- **Lecturas en la tablet** (sin escribir): `/proc/device-tree/__symbols__` existe (1430 símbolos, incluye `apps_smmu`, `pmxr2230_l7`, `pmxr2230_bob`) → los fixups del overlay resuelven; **ninguna de las 19 etiquetas `uke_*` del audio colisiona** con las de la tablet (`comm` de las dos listas, vacío). El gpr vivo tiene solo `audio-pkt`, `q6prm`(vendor), `spf_core`.
  `uke_bt_b` (overlay BT) está cargado ahora mismo: coexiste en el mismo DT; el cargador es independiente por módulo.

## Procedimiento E2 propuesto (NO ejecutado; requiere autorización explícita)
Gate: batería ≥3700 mV, ADSP running, consola ACM con un solo lector (ya hay un `cat` de `usuario`), `dmesg -n 7`, BT sin operación crítica en curso.
1. `scp` de `uke_audio_e2.ko` y `vigia-adsp.sh` a `/root`; lanzar el vigía y la captura `ssh dmesg -w > fichero` en el PC.  (sin riesgo)
2. `insmod /root/uke_audio_e2.ko` (aplica el overlay: solo crea nodos DT; esperados 19 avisos «memory leak … /__symbols__/uke_*», benignos). Aún no hay driver ligado.  (riesgo muy bajo)
3. **Paso con riesgo**: `modprobe apr q6core snd-q6apm q6prm q6prm-clocks` — `apr` abre `adsp_apps`, PDR de `avs/audio`, `q6apm` manda `APM_CMD_GET_SPF_STATE` al ADSP. Posible fallo: ADSP crashea ⇒ carga parada (recovery disabled) ⇒ reset físico.
   Éxito: `q6apm`/`q6prm` sondean sin error, ADSP running 30 min, battmgr vivo, WiFi/BT intactos.
4. Reversa: `rmmod q6prm_clocks q6prm snd_q6apm q6core apr; rmmod uke_audio_e2`; si el ADSP se degrada: `echo stop/start > remoteproc1/state` (E2' demostró que vuelve en ~2 s).
Techo: 3 ciclos por hipótesis.

## Pendiente / no verificado
Que `insmod` y el overlay se apliquen en el kernel real (ni siquiera en VM); nombres exactos de módulo (`q6prm_clocks`, `snd_q6apm`…) se verificarán con `modprobe -n -v` en la tablet (lectura) antes del paso 3.
