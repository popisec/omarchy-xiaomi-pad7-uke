# AUDIO — E4 preparado en el PC: DAIs de q6apm (bedais + dais) con el SMMU del LPASS — 18-oct-2026

Orden del dueño: preparar E4 (`q6apm-dai` y `bedais` con SMMU 0x801001/0x1061), con informe de qué hará en la tablet, riesgo y reversa. **No se tocó la tablet.**

## Entregado (VERIFICADO-PC; nada probado en la tablet)
- `dts/uke-audio-e4-dais.dtso` **dividido** en dos overlays de riesgo distinto (el combinado queda de referencia; su cabecera se actualizó: ya **no hace falta flash**, el kernel v4 admite `0x801001` y `0x1061`):
  - `uke-audio-e4a-bedais.dtso` → `bedais` (`qcom,q6apm-lpass-dais`, etiqueta `uke_q6apmbedai`): solo registra los DAIs de backend; sin hardware ni SMMU.
  - `uke-audio-e4b-dais.dtso` → `dais` (`qcom,q6apm-dais`, etiqueta `uke_q6apmdai`) con `iommus = <&apps_smmu 0x1001 0x80>, <&apps_smmu 0x1061 0>`.
- Cadena de `build.sh`: `e2d → e3 → e4a → e4b → e5-codec → e5-card`: aplica en cascada y de una vez (idénticas), `e4b` sin `e2d` se rechaza, `check-overlays.py` OK. Cargadores `out/uke_audio_e4a.ko` (`a61aebec…`) y `out/uke_audio_e4b.ko` (`a8498569…`), vermagic ouke4; `boot/deploy.sh --module` los instala (sin cargar). Los drivers `q6apm-lpass-dais.ko` y `q6apm-dai.ko` existen en los módulos ouke4 y enlazan con el `snd-q6apm` parcheado (modversions idénticos).

## Qué hará cada paso en la tablet (lectura de los drivers; NO medido)
| Paso | Acción | Qué ocurre | Riesgo | Éxito | Reversa |
|---|---|---|---|---|---|
| **E4a** | con E2d cargado (`uke-audio-up.sh` VERDE): `boot/deploy.sh --go --module` (copia los `.ko`), `insmod uke_audio_e4a.ko` | se crea el platform device `bedais`; `q6apm_lpass_dais` se autocarga y registra el componente con los DAIs (`q6apm_lpass_dai_dev_probe`, sin acceso a hardware) | **nulo-bajo** para ADSP/SMMU | dispositivo ligado, sin errores | `rmmod q6apm_lpass_dais uke_audio_e4a` |
| **E4b** | `insmod uke_audio_e4b.ko` (el overlay crea el device `dais`; `q6apm_dai` se autocarga) | al hacer *probe*, el núcleo llama a `dma_configure → of_iommu_configure`: arm-smmu programa SMR/S2CR para **0x801001** (cubre 0x1001 y 0x1081 por la máscara 0x80) y **0x1061**, y asigna un banco de contexto (`qcom_uke_smmu_alloc_context_bank`, ya admitido). `q6apm_dai_probe` solo lee el SID (0x1001) para componer `dma_addr \| (sid << 32)` en los comandos al ADSP (`q6apm-dai.c:1032-1036`). **No hay DMA**: no existe tarjeta que abra un PCM | **medio**: si el ADSP ya usara esos SIDs con configuración heredada (bypass), sus accesos pasarían a fallar (`arm-smmu … Unhandled context fault`) y con `recovery=disabled` podría tumbar ADSP/carga (escenario §5(a) del plan). Es el primer cambio de SMMU en caliente (no es instrumentación) | `Adding to iommu group N` para `dais`, sin faults, ADSP running, Charging | `rmmod q6apm_dai uke_audio_e4b`; si hay faults o el ADSP se degrada: `stop/start` (E2'; ~2 s) |
| **E4c** (NO preparado) | tarjeta mínima: `/lib/firmware/qcom/sm8650/UKE-tplg.bin` (ya generada en `firmware/`), overlay de `sound` (`qcom,sm8650-sndcard`) con frontend MultiMedia1 ↔ backend `PRIMARY_MI2S_RX` sin códec (códec ficticio), `snd_soc_sc8280xp`; `aplay` a ese dispositivo | primera **DMA real del LPASS hacia memoria de Linux** + carga de la topología en el ADSP + **puertos GPR dinámicos** (≥0x10000000) de los grafos | **alto** | puntero PCM avanzando sin faults | rmmod en orden inverso; stop/start; reset físico si cuelga |
Mi recomendación: E4a y E4b con vigía y doble captura (con un `dmesg -w` a fichero y el ACM); **E4c solo después de revisar sus resultados** y con su propia preparación.

## Qué falta saber (E4c)
- Si el firmware de Xiaomi enruta las respuestas a los puertos dinámicos de los grafos (el problema que tuvo el puerto 1): si no, habrá que fijar puertos (3/7/0x17 o los que acepte) como se hizo con q6apm/q6prm.
- Que el parser de topología de `q6apm` acepte `UKE-tplg.bin` y el ADSP el grafo (nada medido).
- Para los altavoces reales siguen faltando TDM en AudioReach y el driver FS19xx (E7).
