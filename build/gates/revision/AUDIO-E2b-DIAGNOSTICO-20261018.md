# AUDIO — diagnóstico en el PC (solo lectura): ¿por qué el APM no responde? — 18-oct-2026

Alcance: lectura de fuentes del kernel senemos, DT/capturas de Android, firmware JSON y logs de los ciclos; la tablet NO se tocó (además, durante esta fase dejó de responder por SSH: probablemente suspendida por hypridle). Se escribió y compiló una sonda (no cargada).

## 1. CORRECCIÓN de mi informe anterior (importante)
En `AUDIO-E2-20261018.md` y `AUDIO-E2b-RESULTADO-20261018.md` dije que el «UP» de `msm/adsp/audio_pd` «sale del pd-mapper del kernel (estático)» y que «nunca llegó un PDR real». **Es erróneo.**
- `qcom_pd_mapper` (instancia 74 para audio/charger/ois/root) solo es el **localizador** (devuelve la lista de dominios). El estado lo pregunta `apr` por QMI al **servreg notifier del ADSP**: `pdr_register_listener()` guarda `pds->state = resp.curr_state` (`drivers/soc/qcom/pdr_interface.c:154`) y `pdr_notifier_work()` lo pasa a `apr_pd_status()` (`:185`). Ese camino **no imprime** «PDR: Indication received» (solo lo hacen las indicaciones asíncronas, `:321`).
- Por tanto, que `apr` registrase `gprsvc:service:2:1/2:2` a los 12 ms de cargar `apr` (E2, E2b y E2c) significa que **el ADSP contestó curr_state = UP para audio_pd** (0x1fffffff) incluso sin FastRPC (E2). La falta de una *indicación* nueva tras crear el PD es coherente con que ya estaba UP.
- Consecuencia: la hipótesis «el PD de audio no existe hasta que `audioadsprpcd` lo crea» **no explica** el silencio del APM (y los tres ciclos lo confirman). Los ciclos no dañaron nada y dejaron demostrado el camino FastRPC, pero su premisa era débil.
- Sí es cierto (MEDIDO en Android): `adspua.jsn` (`~/gpu-work/ramaa/s24/adsp-fw/extra/`) define `audio_pd` como **user PD** (`sr_domain subdomain audio_pd`, `qmi_instance_id 74`, servicios `tms/servreg` y `avs/audio`), coherente con el pd-mapper de senemos.

## 2. Comparación Linux mainline vs Android (todo LECTURA)
| Aspecto | Android (vendor gpr-lite, `01-dmesg.txt:8155-8205`) | Linux senemos (E2/E2b/E2c) | ¿Explica el silencio? |
|---|---|---|---|
| Opcode GET_SPF_STATE / respuesta | respuesta `Payload 2001007` | `audioreach.h:40-41`: `0x01001021` / `0x02001007`, `apm_callback` lo trata (`q6apm.c:930`) | no (iguales) |
| Dominios GPR | `gprsvc:spf_core:2:3` | `GPR_DOMAIN_ID_ADSP=2`, `APPS=3` (`dt-bindings/soc/qcom,gpr.h`), nombre `gprsvc:service:2:1` | no (misma convención) |
| **Puerto origen del primer comando** | **spf_core = puerto 3** (la respuesta se recibe en `spf_core_callback`) | **q6apm = puerto 1** (`GPR_APM_MODULE_IID`, `audioreach.c:290`, fijo) | **candidato nuevo (H-GPR-src)**: el SPF de Xiaomi quizá solo enruta respuestas a los puertos que su gpr-lite registra (3 spf_core, 7 prm, 0x17 audio-pkt), o la respuesta a 1 se pierde |
| Cabecera del comando | ? | q6apm añade `apm_cmd_header` de 16 B (`has_cmd_hdr=true`) | desconocido |
| Envío | vendor: bloquea con «q6 state is down» hasta PDR UP | `rpmsg_trysend` (`apr.c:118`): errores de TX saldrían como rc<0 antes del timeout; no salieron | no |
| Recepción | callback del vendor | errores de rx serían `dev_err` (`apr.c:280-300`); **no hubo ninguno** ⇒ o no llegó nada, o llegó a un puerto sin callback | **ver abajo** |
- Un paquete dirigido al puerto 3 llegaría hoy a `gprsvc:spf_core:2:3` (existe en el idr, vendor, **sin driver ⇒ `svc->callback` NULL ⇒ descarte silencioso**, `apr.c:300-310`). Es decir: aunque el ADSP respondiera a puerto 3, no lo veríamos.

## 3. La sonda (entregada, NO cargada): `deploy/audio/probe/uke_spfcore_probe.c`
`out/uke_spfcore_probe.ko` (sha `2106bff6…`, vermagic ouke4, depende de `apr`). Se liga al servicio vendor `spf_core` (compat `qcom,spf_core`, id 3), envía **un** `APM_CMD_GET_SPF_STATE` con `src_port=3` (parámetro `cmdhdr=1|0`) y **registra en dmesg cualquier paquete que llegue a ese puerto** (src/dest/opcode/token/payload). Discrimina:
- Si responde ⇒ H-GPR-src confirmada: el arreglo es un parche de `q6apm`/`audioreach` (src_port configurable) o registrar nuestros servicios en puertos que el firmware reconozca.
- Si no llega NADA a puerto 3 con ambos `cmdhdr` ⇒ el ADSP no contesta al GPR por `adsp_apps` en absoluto; la causa está más abajo (GLINK intents/canal, o el SPF no arrancado) y habría que mirar el lado ADSP (no accesible).
Riesgo: el mismo que E2 (un comando de estado por el canal ya usado), sin overlay, sin fastrpc, sin DMA/relojes. Procedimiento: vigía + doble captura; `modprobe apr` (sin `uke_audio_e2`, para no registrar q6apm/q6prm); `insmod uke_spfcore_probe.ko` (y `cmdhdr=0` en un segundo intento); `rmmod` en orden inverso. **Es una hipótesis NUEVA**: techo de 3 ciclos propio.

## 4. Otras observaciones (sin explicar)
- El `Handover signaled, but it already happened` a 1 Hz aparece solo cuando `fastrpc` liga el canal `fastrpcglink-apps-dsp`, no depende del heap ni de adsprpcd, y cesa al reiniciar el ADSP.
- `fastrpc.ko` conserva refcount tras unbind/retirar overlay (queda cargado hasta reiniciar).
- Estado de la tablet: v4 (ouke4), `fastrpc.ko` cargado sin uso; la última verificación (15:41) ADSP/WPSS running, Charging, wlan0 UP. Tras ello dejó de responder por SSH (no investigado: probable suspensión por inactividad de hypridle).
