# L65 — BTA readback del DDIC (primera lectura DCS) · 15-oct-2026 (prep, NO build)

## 1. Por qué (CRITICA-RONDA2-20261015 §2)
`err=0` (L62/L64) = `dsi_ctx.accum_err` ← `mipi_dsi_device_transfer`
(`drm_mipi_dsi.c:448-458`) = el host completó el DMA. **Un panel sordo, sin
vci o desconectado da el mismo `err=0`.** Jamás hemos LEÍDO nada del DDIC;
L65 es el instrumento que falta antes de tocar s6-noncontinuous o el motor
de vídeo (ronda 2, acción 2: "si el DDIC no responde, parar DSC e ir a
link/PHY/vci, no a s6").

## 2. Cambio (`/tmp/ukefix/l65-bta-read.diff`, dry-run + reverse OK)
En `o82_enable` (`panel-xiaomi-o82-dualdsi.c:606`), DESPUÉS del log `UKE-L63`
(variable PPS intacta): 10 lecturas LP con `mipi_dsi_dcs_read()` directo por
link — `0x0A/0x0B/0x0C/0x0D` (1 B) + `0x04` GET_DISPLAY_ID (3 B) × link0/1.
Corrección al encargo: **0x04 es Display ID, no "Get Error"** (ese es 0x05,
excluido por semántica ambigua; `video/mipi_display.h:83-93`). Sin
0xDA/0xDB/0xDC (redundantes con 0x04). Fail-safe: solo `pr_info`, el `return`
sigue decidido por el bloque PPS. Patrón `_multi` NO usado: `cmd_rx`
devuelve 0 ante ACK_ERR sin marcar `accum_err` (`dsi_host.c`) — el diagnóstico
necesita el `ret` por link, no el agregado.

## 3. Momento y riesgo
Con vídeo andando (el `enable` corre post-modeset): la pregunta es justo si
el DDIC escucha mientras nuestro stream corre (mitad vídeo de ronda 2 §3).
Riesgo BAJO: lecturas de 1–3 B caben en un BLLP (`dsi_cmds2buf_tx`), van en LP
(`MODE_LPM` en `:738`), el HW 6G puerta el DMA con `BLOCK_DMA`, y el vendor
lee en diagnóstico (lockdown benigno, cell_id rc=-22) sin colgar el link.
Reads no son sync (`dsi_manager.c:503`): van a su host, sin la asimetría DSI_0
de S4 §2.1. Fallback: si L65 wedgea sin líneas `UKE-L65`, mover a `prepare`
pre-vídeo o reducir a un solo 0x0A.

## 4. Gates
- Fuente: `UKE-L65` ×10 líneas (8 + 2 de 0x04). Binario:
  `strings Image | grep -c UKE-L65` ≥ 1.
- Vivo: `dmesg | grep UKE-L65` tras commit modetest.
- **Criterio prefijado**: `ret==len` y valor ∉ {0x00,0xFF} ⇒ panel RESPONDE
  (seguir a s6); `ret<=0` ⇒ NAK/sordo (parar DSC, ir a link/PHY/vci);
  `0x00/0xFF` ⇒ anómalo (eléctrico o DDIC en reset).

## 5. Runbook / rollback
Flash cold-boot del kernel L65 + commit modetest + `dmesg | grep -E
'UKE-L6|UKE-P82'`. Rollback: L64 `84bc0e44…` / L62 `d52f5967…`. NO build
(ejecutor). Respetar moratoria: ≥3700 mV, ≤2 escrituras/día, `getvar all`.
