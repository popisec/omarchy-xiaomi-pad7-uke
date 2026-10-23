# L57 — quitar el tope `mem=2048M` (D16) · 14-oct-2026

## Cambio
- `boot-uke-k52L57.img` = MISMO kernel L56 (`k52L56-build`, sin rebuild) + cmdline
  622 B = cmdline L56 (632 B) MENOS el prefijo `mem=2048M ` (10 B, token #0).
- D16 (dueño): el escritorio omarchy muere por OOM con `MemTotal` 1,6 GB; el banco
  >4 GB aparece y arranca (NOTAS-OMARCHY.md ~20:4x/20:5x), así que el tope cae.

## Mecanismo exacto de la edición (medido, no memoria)
- El token vive en el byte 0 del campo cmdline de cabecera (offset 44, 1536 B) de
  k64 (580 B) y L56 (632 B: `mem=2048M rdinit=...`). NO hay sección bootconfig
  separada (ramdisk 0, hueco tras kernel = ceros, 0x `bootconfig` en 96 MiB).
- Cirugía en `docs/historia/gates-palawan/repack-k52L57.py` (clon L56): valida 632 B == artefacto
  L56 byte a byte, luego corta EXACTAMENTE `b"mem=2048M "` (con su espacio).
- `memmap=0x1A12800$...` y `memmap=0x2B00000$...` NO tocados (gate x2 antes/después).

## Gates (todos verdes, repack ejecutado 14-oct ~20:4x)
| gate | resultado |
|---|---|
| `mem=2048M` ausente | x0 en campo cmdline y x0 en los 96 MiB (barrido total; kernel gz/crudo tampoco lo trae) |
| resto cmdline intacto | 622 B == L56[10:] byte a byte; regulator/reclaim/iomem/memmap x2 OK; sin video/loglevel/wmask |
| kernel == L56 | UKE-L56=1, UKE-L45=1, FIX-A1b=6, UKE-POKE=121, K50-=18, S4-DIAG=4; kernel extraído == Image.gz |
| forma | 100663296 B, v4/1584, AVB0/AVBf, diffs L56-vs-L57 solo en [44,676) |
- sha256: `ebe9409340db2ad5499ced7ac2f3db088e1558a0c74f46fd1b5f559d068c2b82`
- Discrepancia honesta: el encargo pedía «632 B idénticos a L56» Y «mem ausente» —
  incompatible (quitar 10 B deja 622 B). Se implementó «L56 menos el prefijo, resto idéntico».

## Runbook (NO flashear hasta verificado L56; cold boot)
1. Pre-registrar sha `ebe94093…` en el ledger (fila L57) ANTES de flashear.
2. Flash + cold boot; verificar `MemTotal` ≈ RAM física − carveouts (≈7,x GB si 8 GB).
3. Criterio: arranque OK + sddm/escritorio omarchy sin OOM.
4. Riesgo: DMA de periféricos (wifi ath11k) si swiotlb no cubre la RAM alta — vigilar
   en el primer arranque (`dmesg -n 7`, doble captura consola + `dmesg -w`).
5. Rollback = L56 `3e68abe88223ed11974024ce4278e5c127c49ef5d1127365893d7075b482728f`.
