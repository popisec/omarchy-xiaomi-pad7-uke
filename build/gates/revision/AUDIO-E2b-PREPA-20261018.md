# AUDIO — E2b: preparación en el PC (parche SMMU, overlay fastrpc, adsprpcd) — 18-oct-2026

Solo PC. **No se flasheó ni se tocó la tablet** (sin ssh en esta fase). Investigación previa: `AUDIO-E2b-INVESTIGACION-20261018.md`. Paquete: `build/rootfs/deploy/audio/`.

## Entregado (todo VERIFICADO-PC salvo lo marcado)
| Pieza | Fichero | Verificación |
|---|---|---|
| Parche SMMU (flash) | `kernel/0004-uke-arm-smmu-qcom-fastrpc-adsp-sids.patch` (se aplica **tras** 0002) | `patch --dry-run` OK tras 0002; test C del predicado de la lista blanca (`out/smmu-0004-predicate.txt`): `bad=0` (20 SIDs admitidos con compat boot-smmu, 8 rechazados, y sin compat boot-smmu se rechaza). Contra la tabla `qcom,actlr` vivo (31 entradas) ninguno casa. **No compilado como kernel** (no hay toolchain aarch64 completa/`.config` para ese objeto). |
| Overlay fastrpc | `dts/uke-audio-e2b-fastrpc.dtso` → `out/uke-audio-e2b-fastrpc.dtbo` (sha `c7ff7c47…`) | `dtc -@` sin avisos; `fdtoverlay` sobre el DT vivo: compatible `qcom,msm-fastrpc-rpmsg`→`qcom,fastrpc`, `compute-cb@3..7` con `iommus`; **sin `qcom,vmids` ni `memory-region`** (comprobado en `build.sh`). |
| Cargadores | `module/uke_audio_e2b.c` → `out/uke_audio_e2b.ko` (sha `ffb51c2a…`); `uke_audio_e2.ko` reproducible (`3c1f3534…`, igual que el cargado en E2) | vermagic = `uname -r` de la tablet, `depends` vacío, 0 avisos. |
| Userspace | `fastrpc/build-fastrpc.sh` → `out/fastrpc-uke-a56e9d4d.tar` (sha `c9dc6a7c…`, 460 KB) | quic/fastrpc `a56e9d4d` (9-oct-2026, BSD-3), cross-compilado (clang + sysroot aarch64 del rootfs + gcc/libyaml/libbsd/libmd de ALARM con sha comprobado). Contiene `usr/bin/adsprpcd`, `libadsp_default_listener.so.1`, `libadsprpc.so.1`, `adsprpcd_audiopd.service`, `sysusers.d/fastrpc.conf`. ELF aarch64 (readelf). `adsprpcd` pide libyaml, libbsd, libmd: en la tablet **falta `libyaml`** (`pacman -S libyaml`; bsd/md ya están). Sin udev rule a propósito: solo el servicio `audiopd`, manual. **No ejecutado.** |
| Confirmación upstream | `adsp_default_listener.c:191-244` | `adsprpcd audiopd` hace `createstaticpd:audiopd&dom=adsp`, igual que Android. |

## Notas
- `make install` de libtool relinka con destino equivocado (x86-64): el script toma los `.libs` ya enlazados.
- Los .dtbo/.ko se versionan con su sha; el tar de fastrpc también (460 KB).
- La lista de `build.sh` ahora incluye e2b en la comprobación; `RESULTADO: OK`.

## Plan de ejecución de E2b (cada paso con riesgo pide autorización)
1. **Flash** (un ciclo): kernel nuevo = ouke3 + 0002 + 0004 (+ regenerar `Image`/`boot`); fila de ledger **pre-registrada** en `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`, sha256 del boot, gates (≥3700 mV, ≤2 escrituras/día, `slot-retry-count` ≥3, consola+vigía), el dueño pone fastboot. **Pendiente de preparar**: construir ese kernel (build-senemos-v4) — es un siguiente paso del PC; y comprobar el semáforo con `ubuntu-permanente`.
2. En caliente: `pacman -S libyaml`, instalar el tar, `insmod uke_audio_e2b.ko`, `modprobe fastrpc` (misc `fastrpc-adsp`), `insmod uke_audio_e2.ko`, y `systemctl start adsprpcd_audiopd`; vigía + doble captura.
   Éxito: `q6apm` responde (`apm is up`), WiFi/carga intactos. Reversa: `systemctl stop`, `rmmod`, `stop/start` del ADSP.
3. Si el ADSP exige el heap protegido: ciclo 2 con `memory-region`+`qcom,vmids=<22 37>` (delicado). Techo 3 ciclos.

## Pendiente / no verificado
Que `fastrpc` ligue al canal con el `compatible` cambiado en caliente; que sin vmids el ADSP acepte el heap; que `adsprpcd` sin libs Hexagon baste; que 0004 compile.
