# AUDIO — E2b ejecutado en caliente (kernel v4): el PD «audiopd» se crea, pero el APM sigue sin responder — 18-oct-2026 15:3x

Autorizado por el dueño. Gate: 3895 mV, Charging, ADSP/WPSS running, WiFi up; vigía + `ssh dmesg -w` a fichero + lector ACM único; `dmesg -n 7`. Logs: `build/logs/audio/e2b-20261018-*.log`.

## Secuencia y resultados (MEDIDO)
1. Reloj de la tablet en 1970 (chrony sin sincronizar) ⇒ `pacman -S libyaml` fallaba con «PGP signature». Se puso la hora desde el PC (`date -s`) y `libyaml` se instaló. **Aviso**: la tablet arranca con fecha 1970 (fake-hwclock `failed`, chronyd sin ref hasta que haya red) — afecta a pacman/TLS tras cada reinicio.
2. `fastrpc-uke-a56e9d4d.tar` instalado (adsprpcd, libs, unidad, grupo `fastrpc`). Sin libs Hexagon (`/usr/lib/rfsa`, `dsp_b` no usadas).
3. `insmod uke_audio_e2b.ko` → overlay aplicado (5 avisos «memory leak» benignos); `compatible` = `qcom,fastrpc`.
4. `modprobe fastrpc` → liga al canal `fastrpcglink-apps-dsp`; **los 5 compute-cb se unen a grupos IOMMU sin error (el parche SMMU 0004 funciona en el kernel real)**; aparece `/dev/fastrpc-adsp`. Desde ese momento el ADSP dispara `Handover signaled, but it already happened` cada ~1 s (nuevo; no ocurría antes).
5. `systemctl start adsprpcd_audiopd` → `remote_handle_open: Successfully opened handle 0x101 for createstaticpd:audiopd on domain 0` y el listener `adsp_default_listener` abierto (mismo patrón que Android, `logcat-30s.txt:2093`); `open_mod_table_handle_invoke … Error 0x2` igual que en Android. El demonio queda esperando.
6. `insmod uke_audio_e2.ko` + `modprobe apr` (≈40 s después del audiopd) → `gprsvc:service:2:1/2:2` registrados y de nuevo **`qcom-apm … CMD timeout for [1001021] opcode`** a los 5 s. **El APM no responde.**
7. Estabilidad: ADSP `running`, Charging, WiFi up, sin faults/SMMU/watchdog en dmesg en todo el ensayo.

## Reversa
`rmmod` de q6prm_clocks/q6prm/snd_q6apm/apr, `uke_audio_e2`, stop de adsprpcd, `uke_audio_e2b` (overlay retirado) y de los `snd*`. `fastrpc` quedó **«in use» (refcnt 1 sin usuarios; fuga de refcount del driver al retirar el overlay con el módulo ligado)**: se hizo stop/start del ADSP (como E2': vuelve en ~1 s, Charging, wlan0 up) y los «Handover» cesaron, pero `fastrpc.ko` sigue cargado hasta el próximo reinicio (inofensivo: sin nodo ni overlay). Lección: descargar `fastrpc` **antes** de retirar el overlay.

## Diagnóstico y siguiente paso (hipótesis, no verificadas)
- H-E2a («falta crear el PD por FastRPC») **no basta**: el PD se pide con éxito y el APM sigue mudo. Ciclos gastados en la línea APM: **2 de 3** (E2, E2b).
- Candidata H-E2c: el audiopd necesita su **heap protegido**. Mainline (`fastrpc.c:1385`) solo pasa el heap al ADSP si hay `qcom,vmids` (aquí `pageslen=0`); Android usa `adsp_heap_region` (12 MiB) con `qcom,adsp-remoteheap-vmid=<22 37>`. El `Handover` cada 1 s encaja con un PD que se reintenta sin heap (INFERIDO).
  Ciclo 3 sería overlay con `memory-region`+`qcom,vmids=<22 37>`: **delicado** (`qcom_scm_assign_mem` a VMIDs seguros; un error = violación XPU/cuelgue ⇒ reset físico). Requiere autorización expresa.
- Alternativa más barata antes del ciclo 3: observar el ADSP desde el lado Linux (¿llega algún `PDR:` real de `audio_pd`? en Android el UP real llegó 20 ms antes del APM; aquí no hubo ningún `PDR` de audio_pd en dmesg, solo el de `charger_pd`).
- Si el ciclo 3 también falla: nota «refutada», A2DP (línea BT) sigue siendo la salida de sonido.

---
# CICLO 3 (misma tarde, ~15:38-15:41): heap protegido — también SIN respuesta del APM → H-E2a/H-E2c REFUTADAS (techo de 3 ciclos)

Autorizado por el dueño («overlay e2b con memory-region y qcom,vmids=<22 37>»). Overlay `dts/uke-audio-e2c-fastrpc-heap.dtso` (= e2b + `memory-region=<&adsp_mem_heap>` + `qcom,vmids=<22 37>`), módulo `uke_audio_e2c.ko`.
Dato nuevo de código (corrige mi lectura del ciclo 2): `fastrpc_remote_heap_alloc()` (`fastrpc.c:481`) reserva el heap del PD estático del **rpmsg device**, y `fastrpc_rpmsg_probe()` le asigna el `memory-region` ⇒ el reserved-mem **sí** es el heap (en el ciclo 2 no se pasó heap).
Medido: `assigned reserved memory node adsp_heap_region`; los 5 compute-cb enlazan; `adsprpcd audiopd` → `createstaticpd:audiopd` handle 0x101 + listener (mismo log que Android); **sin error de `qcom_scm_assign_mem`, sin faults, ADSP running, Charging, WiFi up**;
`insmod uke_audio_e2` + `modprobe apr` → **`qcom-apm … CMD timeout for [1001021] opcode`** otra vez. Logs `build/logs/audio/e2c-20261018-*.log`.
Detalles: el `Handover signaled, but it already happened` a 1 Hz aparece solo al ligar `fastrpc` al canal (no depende del heap ni de adsprpcd). Reversa: rmmod apr/q6*, `uke_audio_e2`, stop adsprpcd, unbind, overlay retirado y stop/start del ADSP (vuelve en ~1 s; cesan los Handover). `fastrpc.ko` sigue cargado (refcnt 2 colgado hasta reiniciar): bug de refcount de `fastrpc` al retirar nodos/unbind (no investigado).

## Conclusión del bloque de hipótesis «el APM espera al PD de audio/FastRPC»
3 ciclos (E2, E2b sin heap, E2b con heap) sin movimiento del APM ⇒ **refutada como causa suficiente** (regla 11). Lo que SÍ queda demostrado y reutilizable: overlays en caliente, SMMU 0002/0004 en el kernel v4 real, fastrpc mainline funcionando, `adsprpcd audiopd` operativo, y que ninguno de los pasos daña ADSP/carga/WiFi.
Observaciones sin explicar (para una futura línea, NO ciclos de flash): (a) **ningún `PDR:` real de `audio_pd`** llegó nunca (solo `charger_pd`), mientras en Android el UP real precedió 20 ms al APM; el «UP» que ve `apr` sale del pd-mapper del kernel; (b) Android usa un GPR propio «gpr-lite»/`spf_core` (reg 3) para el primer comando, no el q6apm mainline; (c) el ADSP podría necesitar un servicio previo (`audio-pkt`/`spf_core`) o un PDR genuino.
Siguiente paso razonable sin tocar el ADSP: leer en el PC `audiopd`/PDR en el firmware (strings del `adsp.b*`, `adspua.jsn`) y el driver Android `gpr-lite`; o dar por buena la salida **A2DP por Bluetooth** (ya funciona en la línea BT).

> **CORRECCIÓN (18-oct, diagnóstico en el PC):** la afirmación «el UP de audio_pd sale del pd-mapper / nunca hubo PDR real» de esta sección y de `AUDIO-E2-20261018.md` es errónea: `apr` recibió el estado UP del servreg notifier del **ADSP** en la respuesta de registro (que no imprime «Indication»). El PD de audio ya estaba UP sin FastRPC. Ver `AUDIO-E2b-DIAGNOSTICO-20261018.md` §1; allí se plantea una hipótesis nueva (puerto origen del GPR: Android usa spf_core=3, q6apm usa 1) y la sonda para probarla.
