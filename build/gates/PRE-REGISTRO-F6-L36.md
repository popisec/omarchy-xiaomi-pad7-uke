# PRE-REGISTRO F6/L36 — 13-oct · **no esperar VIDEO_DONE en el envío de comandos**

## La variable

Un early-return al principio de `dsi_wait4video_eng_busy()` (`dsi_host.c:1258`).
Nada más. La espera de `DMA_DONE` de 200 ms en `dsi_cmd_dma_tx()` **se conserva**
— es la que usa CAF.

## Por qué

CAF nunca espera `VIDEO_DONE` en el path de comandos: espera `DMA_DONE` 200 ms
(`dsi_ctrl_dma_cmd_wait_for_done`, `DSI_CTRL_TX_TO_MS=200`) y, además, manda los DCS
de encendido **con el motor de vídeo apagado**. Mainline enciende vídeo antes de los DCS
y **cada** comando bloquea 70 ms en `VIDEO_DONE`. Con el motor parado (nuestro caso:
`status=4` + `VIDEO_DONE` perdido) el primer DCS es muerte garantizada.

## Y el `TIMING_FLUSH` de L34 se retira

Medido: con flush los errores pasaron de **8 a 12** y la muerte se adelantó al reset del
panel. Hace que el motor arranque de verdad y por eso satura más el FIFO, pero el panel
no llega a estar listo. Además H1-fuerte está **refutada por contraejemplo**: `sheng`
(SM8550) enciende un panel bonded de vídeo+DSC con la secuencia mainline pura.

Mezclarlos habría roto la atribución. L36 = **solo** el early-return.

## Prueba en el binario (definitiva, no falseable)

El early-return deja `dsi_wait4video_done()` **inalcanzable**, así que el compilador la
elimina por código muerto y su cadena de error desaparece del binario:

| | L33/L34/L35 | **L36** |
|---|---|---|
| `wait for video done timed out` | x1 | **x0** |

No se puede falsear por comentario: los comentarios no se compilan.

## Artefacto

- **sha256**: `b541df0e18434b19f3b56ebaa3c13169feece03e426c770f6e1047b1cd68a360`
- Kernel: `0031c6de0eee21b87e499def46732cd6333408a6cd805f8aefa537c7e6eb4ec4`
- Cmdline: 585 B (igual que L35: `systemd.mask=sddm`, sin `video=`)

## Tabla de lectura

| Resultado | Lectura |
|---|---|
| **Sobrevive y el panel se enciende** | H2-era (orden/espera) era la causa. Pantalla |
| **Sigue muriendo pero YA no en `dsi_cmds2buf_tx`** | La espera era un síntoma, no la causa ⇒ el problema está en el **contenido** del DCS o en el panel |
| **Muere antes** | El DCS sale sin video-done y el panel no lo tolera |
| **Rebota solo** | `systemd.mask=sddm` funciona: ya no hace falta recuperación manual |
