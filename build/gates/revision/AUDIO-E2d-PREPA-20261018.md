# AUDIO — E2d: q6apm/q6prm en los puertos GPR que el ADSP reconoce — preparado en el PC (sin cargar nada) — 18-oct-2026

Autorizado por el dueño: preparar el parche de `snd-q6apm`/`q6prm` (src_port = id del servicio) como módulos y el overlay con reg 3 y 7 retirando los vendor. **No se tocó la tablet.**

## Entregado (VERIFICADO-PC; no probado en la tablet)
| Pieza | Fichero | Verificación |
|---|---|---|
| Parche `snd-q6apm` | `kernel/0005-q6apm-src-port-from-svc-id.patch` (audioreach.c/.h, q6apm.c): `audioreach_apm_src_port` (por defecto `GPR_APM_MODULE_IID`) se fija en `apm_probe` a `gdev->svc.id` (o al parámetro `uke_src_port=N`) y lo usa `audioreach_alloc_apm_cmd_pkt()` | aplica a una COPIA de las fuentes (el árbol no se modifica) |
| Módulo | `q6apm-port/build.sh` → `out/snd-q6apm-uke.ko` (sha `64dacd3b…`, vermagic ouke4, depende de `apr,snd-soc-core`) | compila sin avisos; símbolos globales idénticos al `snd-q6apm.ko` del árbol salvo `audioreach_apm_src_port`; **modversions idénticos** (los dependientes `q6apm-dai`, `q6apm-lpass-dais`, `q6prm` siguen cargando) |
| q6prm | sin parche: `q6prm.c:75,116,148` ya usa `gdev->svc.id` como src_port ⇒ basta `reg = 7` | lectura |
| Overlay | `dts/uke-audio-e2d-gpr-ports.dtso` → `out/uke-audio-e2d-gpr-ports.dtbo` (sha `b801e329…`), módulo `out/uke_audio_e2d.ko` (sha `cd88eeb8…`) | `dtc -@` sin avisos (el único tolerado: `unit_address_vs_reg` de los fragmentos que solo cambian `reg`); `fdtoverlay` sobre el DT vivo: `service@3` y `service@7` nuevos, vendor `spf_core` reg 3→0x40, vendor `q6prm` reg 7→0x41, `audio-pkt` 0x17 intacto; `build.sh` completo `RESULTADO: OK` |
- **No se pueden «retirar» los nodos vendor deshabilitándolos**: `apr.c` itera con `for_each_child_of_node` (incluye `status=disabled`); por eso se les cambia el `reg` (solo afecta al id con que `apr` los registra; no tienen driver).
- E2d es **alternativa** a E2 (no cargar `uke_audio_e2` a la vez). Los overlays e3–e5 apuntan a `service@1`; habrá que retargetearlos a `service@3` cuando E2d funcione.
- Limitación consciente: los **puertos dinámicos** de los grafos (`gpr_alloc_port`, desde 0x10000000, `apr.c:26`) pueden tener el mismo problema que el puerto 1 (que el firmware no enrute las respuestas); no se sabe hasta E4. E2d solo resuelve los comandos APM de nivel de servicio (estado, mapeo de memoria compartida, configuración).

## Procedimiento de carga propuesto (NO ejecutado; requiere autorización expresa)
Gate: ≥3700 mV, vigía + doble captura + ACM, `dmesg -n 7`, tablet en ouke4 (sin `fastrpc`/overlays cargados; `fastrpc.ko` aún cargado de antes: sin uso).
1. `scp out/snd-q6apm-uke.ko` → `/lib/modules/7.2.9-senemos.1.4054.3-ouke4/updates/snd-q6apm.ko` (el original queda en `kernel/`), `depmod -a`; comprobar `modinfo -n snd-q6apm` = updates/. (sin riesgo)
2. `insmod uke_audio_e2d.ko` (solo nodos DT) y `modprobe apr` (autocarga q6prm, clocks y el `snd-q6apm` parcheado).
   Éxito: `uke: src_port de los comandos APM = 3` y `q6apm`/`q6prm` sondean **sin** `CMD timeout`; ADSP running, Charging, WiFi.
3. Reversa: `rmmod q6prm_clocks q6prm snd_q6apm apr`, `rmmod uke_audio_e2d`, quitar `updates/snd-q6apm.ko` + `depmod`; si el ADSP se degrada: stop/start (~1 s).
Riesgo: el mismo comando de estado que la sonda (ya probado) + el probe de q6prm; sin DMA ni relojes.
