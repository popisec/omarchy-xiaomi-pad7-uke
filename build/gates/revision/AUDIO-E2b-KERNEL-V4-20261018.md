# AUDIO — E2b: kernel senemos v4 (ouke4) construido, SIN flashear — 18-oct-2026

Orden del dueño (vía sesión principal): construir v4 = ouke3 + parches 0002+0004, dejar la fila de ledger y el script gated, avisar a BT. **La tablet no se tocó** (ni lecturas en esta fase). **No se flasheó.**

## Resultado
| Cosa | Valor |
|---|---|
| Release | `7.2.9-senemos.1.4054.3-ouke4` (cambia el vermagic) |
| Cambio | solo `arm-smmu-qcom.c` con 0002+0004 (`deltas-omarchy-v4.sh`, copia en `deploy/audio/kernel/`); `config-senemos-ouke4` == `config-senemos-ouke3` (cmp) |
| Build | `build-senemos-v4.sh` desprendido (setsid nohup, MAKE/ARCH/LLVM explícitos): **0 errores**; `arm-smmu-qcom.o` compila (cierra el «no compilado como kernel» del parche 0004) |
| Image.gz | 15993774 B, sha `098520ba9d08fbb3016553b42ac18357d572ee6140e2f57858392e40477e4080` |
| **boot v4** | `build/bootimg/boot-uke-senemos-7.2.9-v4.img`, 100663296 B, sha256 **`fc9309a3953e8c423b30647b27a151aa740e6473757642ae922ec9cc0aaab88f`**; `repack-senemos.py --v4` (necesita `HOME=~`): G0–G8 verdes (config, cmdline, initramfs, overlays, AVB, deltas confinados, unpack_bootimg) |
| **Módulos ouke4** | `senemos-build/modules-7.2.9-senemos.1.4054.3-ouke4.tar.zst`, sha256 **`57ef06f6ea92deec5972444d433b1cf0c6211067a76c2b9214f86d20afbdb240`** (13,7 MB) |
| `uke_audio_e2/e2b.ko` | recompilados contra ouke4: vermagic ouke4, shas `2cba880c…` / `837062e0…` |
| Script | `build/gates/flash-senemos-v4-gated.sh`: `--check` OK (gates de PC), `--pre`, `--post` (G1–G6 de v3 + G7 nuevo: release, sin faults SMMU, wlan0/wifi/desktop/touch, ADSP running), `--rollback v3|v2|v1|l77ba|l76r` |
| Ledger | fila **#661 PENDIENTE** en `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` (sin commit allí) |

## Para flashear (todo con orden expresa del dueño; el dueño pone fastboot a mano)
1. Semáforo: el reinicio corta BT, WiFi, escritorio y táctil unos minutos; avisar a la sesión BT. Tablet cargando, `fastboot getvar battery-voltage` ≥3700 mV, ≤2 escrituras/día, `slot-retry-count:b` ≥3.
2. Sesión BT: recompilar `uke_bt_*.ko` contra el árbol ouke4 (`deploy/bt/build.sh`; el árbol `senemos-build` ya es ouke4).
3. `--pre` (tablet en v3 por SSH): instala módulos ouke4 (+ `uke_audio_*.ko`) junto a los ouke3 y depmod; luego BT instala los suyos (`deploy.sh`, por KREL).
4. Lector ACM único armado (`build/gates/uke-consola-lector.sh`) y vigía `uke-fastboot-watch` al par bueno; dueño en fastboot (Power+Vol−).
5. `bash build/gates/flash-senemos-v4-gated.sh` (1 escritura: `boot_a`) → `--post` automático. Rollback: `--rollback v3`.

## Notas / no verificado
- El árbol de build `senemos-build` es ahora ouke4: los módulos ouke3 de la tablet no se ven afectados, pero **nadie puede recompilar módulos ouke3** sin reconstruir (el tarball ouke3 y el boot v3 están intactos).
- Fuente modificada: `arm-smmu-qcom.c` en el árbol (copia previa `…c.pre-v4`). `kernel-pokes/` está en .gitignore: por eso los scripts se copian a `deploy/audio/kernel/`.
- NO verificado: que el v4 arranque (es un cambio de lista blanca, no toca el camino de display/USB; riesgo bajo pero real) y todo lo de E2b en caliente.
