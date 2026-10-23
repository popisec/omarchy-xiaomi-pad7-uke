# AUDIO — E4c pasos 1-3 ejecutados: la topología carga y el PCM se crea, pero **oops** en `q6apm_dai_pcm_new` — 18-oct-2026 16:29

Autorizado por el dueño (pasos 1-3, sin `aplay`). Gate: 3857 mV, Charging; vigía + `dmesg -w` + ACM. Logs `build/logs/audio/e4c-20261018-tablet.log`.

## Resultado
1. `e4c/deploy.sh --go` (topología + `uke_audio_e4c.ko` + WAV) y `pacman -S alsa-utils` (la hora de la tablet ya era la correcta): OK.
2. `insmod uke_audio_e4a.ko` y `e4b.ko` sobre E2d: OK (como antes; `dais` en iommu group 10, sin faults).
3. `insmod uke_audio_e4c.ko` → overlay aplicado; `snd_soc_sc8280xp` (autocarga) hace probe de la tarjeta, **carga la topología y llega a crear el PCM de MultiMedia1**; entonces:
   `Unable to handle kernel NULL pointer dereference at virtual address 0xa8` en `idr_find ← q6apm_is_graph_in_push_pull_mode_from_id+0x30 [snd_q6apm] ← q6apm_dai_pcm_new+0x58 [q6apm_dai] ← snd_soc_pcm_component_new ← …snd_soc_register_card ← sc8280xp_platform_probe (udev-worker)`.
   Ningún comando de grafo ni DMA llegó al ADSP (el fallo es en el lado Linux, antes de abrir ningún stream).

## Causa raíz (lectura de `q6apm.c:684` + `of_platform_notify`; coherente con el oops)
`q6apm_is_graph_in_push_pull_mode_from_id(dev, …)` hace `apm = dev_get_drvdata(dev->parent)`: espera que el padre del dispositivo `dais` sea el dispositivo GPR de q6apm (así lo crea `of_platform_populate(dev->of_node, NULL, NULL, dev)` en el probe de q6apm). Pero `dais`/`bedais` los creó **el notificador de overlays** (`of_platform_notify`), que busca el padre con `of_find_device_by_node(service@3)` — y `service@3` es un dispositivo del **bus apr**, no de plataforma ⇒ padre NULL ⇒ `dev->parent` = `platform_bus` ⇒ `drvdata` NULL ⇒ oops. (E4a/E4b «funcionaron» porque sin tarjeta nadie desreferencia el padre.)
**Arreglo (a preparar en el PC)**: que `bedais` y `dais` ya estén en el overlay **E2d** (antes de cargar `apr`), de modo que los cree el `of_platform_populate` del probe de q6apm con el padre correcto. Efecto colateral a decidir con el dueño: el probe de `q6apm_dai` y la asignación del banco de contexto SMMU pasarían a ocurrir en cada arranque con `uke-audio.service` (ya medido OK en E4b).

## ESTADO ACTUAL DE LA TABLET (importante)
- El oops mató al `udev-worker` **dentro de `snd_soc_register_card`**, es decir con `client_mutex` (global de ASoC) **y** el mutex de la tarjeta tomados: **no se liberan**. Cualquier operación ASoC posterior (rmmod de `q6apm_dai`/`q6apm_lpass_dais`/`snd_soc_sc8280xp`, retirar el overlay `e4c`, registrar otra tarjeta) **quedaría colgada en estado D** para siempre. Por eso **NO he revertido con `rmmod`** (un `rmmod` colgado además retendría el mutex de overlays y bloquearía cambios de DT).
- Medido tras el oops: ADSP y WPSS running, Charging, WiFi up, BT conectado; sin tareas en D, sin hung-task/lockup. `/proc/asound/cards`: «no soundcards» (existe un `card0` a medio crear). Cargados: E2d, `e4a`, `e4b`, `e4c`, `snd_soc_sc8280xp`, `snd_soc_spdif_tx`, alsa-utils instalado. **Nada de esto afecta a carga/WiFi/BT**, pero la pila ASoC queda inutilizable hasta reiniciar.
- **Recomendación**: **reinicio de la tablet** (decisión del dueño; corta BT/WiFi unos minutos y prueba además el arranque en frío de `uke-audio.service`, que solo carga E2d: ni `e4*` ni tarjeta). `sync` antes (regla 5). Los `.ko`/topología/WAV instalados no estorban; los overlays e4/e3 son de RAM y desaparecen.

## Siguiente (sin tocar la tablet hasta que el dueño decida)
1. Preparar en el PC `e2e`: E2d + `bedais` + `dais` bajo `service@3` (etiquetas `uke_q6apmbedai`/`uke_q6apmdai`), retargetear e4c/e5 a esa cadena, reconstruir módulos, tests.
2. Tras el reinicio, repetir E4c pasos 1-3 con ese overlay (sin e4a/e4b aparte) y revisar dmesg antes del `aplay` (paso 4, primera DMA, solo con autorización).
