# AUDIO — E4a y E4b ejecutados: bedais y dais sondean y el SMMU del LPASS se asigna sin faults — 18-oct-2026 16:24

Autorizado por el dueño. Gate: 3854 mV, Charging, ADSP/WPSS running; E2d cargado; vigía + `ssh dmesg -w` + ACM. Logs `build/logs/audio/e4-20261018-tablet.log`.

## Resultado (MEDIDO) — **PASA**
- `boot/deploy.sh --go --module`: instaladas `uke_audio_e4a.ko`/`uke_audio_e4b.ko` (junto a e3 y e2d).
- **E4a** `insmod uke_audio_e4a.ko` → overlay aplicado (id 3, 395 B); se autocarga `q6apm_lpass_dais`; el dispositivo `…:service@3:bedais` queda ligado a su driver; sin errores.
- **E4b** `insmod uke_audio_e4b.ko` → overlay (id 4, 517 B); se autocarga `q6apm_dai`; **`…:service@3:dais: Adding to iommu group 10`**, driver `q6apm-dai` ligado. Es decir: **el SMMU admitió 0x801001 y 0x1061 y asignó un banco de contexto al cliente de audio del LPASS** (confirma en el kernel real la lista blanca del parche 0002).
- **0** `context fault`/`Unhandled`/errores de arm-smmu antes, durante y 10 s después; ADSP y WPSS running, Charging, wlan0 UP, vigía sin alarmas. Sin tarjeta no hay PCM, así que **no se movió ningún dato por DMA**.
- Reversa: `rmmod q6apm_dai`, `uke_audio_e4b`, `q6apm_lpass_dais`, `uke_audio_e4a` (overlays retirados); E2d queda cargado; 0 faults.

## Qué prueba / qué no
Prueba que los DAIs de q6apm y el cliente SMMU existen sin perturbar al ADSP. **No prueba** ninguna transferencia: la primera DMA del LPASS hacia memoria de Linux, la carga de la topología y los puertos GPR dinámicos de los grafos (≥0x10000000) son **E4c**.

## Siguiente: E4c (hay que preparar y autorizar; riesgo alto)
Tarjeta mínima (`qcom,sm8650-sndcard`, `model = "UKE"`): frontend MultiMedia1 ↔ backend `PRIMARY_MI2S_RX` (sin cableado conocido) con códec ficticio, `UKE-tplg.bin` en `/lib/firmware/qcom/sm8650/`, `snd_soc_sc8280xp`; `aplay` corto a −40 dBFS. Preparación en el PC (overlay de la tarjeta, instalación de la topología, procedimiento, verificación del parser con la topología), informe de riesgos y reversa. Sin los altavoces (TDM + FS19xx, E7) no suena nada audible aunque E4c funcione.
