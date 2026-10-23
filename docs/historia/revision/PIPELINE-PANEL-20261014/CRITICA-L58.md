# CRÍTICA L58 — consolidación (PWM + zram + sin-mem) · 14-oct-2026 ~20:50

Veredicto: **PASA flashear L58, CONDICIONADO a DONE + re-gate** (build en vuelo
20:49, ver §1). Sin bloqueantes de diseño.

## 1. ⛔ BUILD AÚN EN VUELO + ARTEFACTO STALE (medido, no memoria)

- `build/logs/build-k52L58.log` (1855 lín): arranca 20:43 (`olddefconfig` lín.3,
  `make Image.gz -j12` lín.29), cola aún en `CC` (acpi/ethtool/tcp), **0× DONE**,
  0 errores (el único "error" es `fs/fserror.o`). 4 procs `k52L58-build` vivos.
- `Image`/`vmlinux` = 20:33:58, pero `.config` = 20:43:26 ⇒ el Image actual es de
  un intento anterior (log rotado) y **NO corresponde al `.config` vigente**:
  `strings Image | grep -ci zram` = **0** con `CONFIG_ZRAM=y` en `.config`.
- Corrección exacta: NO repackear hasta DONE; el repack debe exigir
  `mtime(Image.gz) > mtime(.config)` ADEMÁS del G0 existente, y gate nuevo §3.
## 2. Config: 5 líneas correctas, `.config` resuelto bien, fuente con pelusa

- `.config` del build (lín.2255-2268): `ZRAM=y`, `ZSMALLOC=y`,
  `BACKEND_LZ4=y` (+ZSTD sigue, `MULTI_COMP=y`), `DEF_COMP_LZ4=y`,
  `DEF_COMP="lz4"` ⇒ olddefconfig resolvió perfecto (dependencias OK en 7.2).
- Pero `k52L58.config` fuente (lín.2262-2263 vs 9473): conserva
  `# DEF_COMP_ZSTD is not set` + `DEF_COMP="zstd"` y el `DEF_COMP_LZ4=y`
  apendizado al final (edición a mano inconsistente). Corrección: dejar 2262-2263
  como el `.config` resuelto (`DEF_COMP_LZ4=y`, `DEF_COMP="lz4"`) y borrar la 9473.
- Riesgo arranque con zram=y builtin: NULO apreciable (+~90 KB, sin init, sin
  device hasta que userspace lo configure; auditor B lo cifra igual).

## 3. Repack (clon L57) + gates nuevos de zram

- Clonar `repack-k52L57.py` SÍ basta, con 3 sustituciones exactas:
  `KERNEL → k52L58-build/.../Image.gz`, `OUT → boot-uke-k52L58.img`,
  `LOG → repack-k52L58-report.txt`. Mecanismo del corte (632→622 B, barrido 96 MiB
  ×0, ledger #633) se hereda intacto; el gate "632 B == L56" debe pasar a validar
  contra la cmdline extraída del L57 (`ebe94093…`), no reconstruir el corte.
- Gates existentes siguen válidos (fuente kernel idéntica salvo `.config`):
  UKE-L56=1 (árbol: `grep -c` = 1 hoy), UKE-L45=1, FIX-A1b=6, UKE-POKE=121,
  K50-×18, S4-DIAG=4, mem ×0.
- Gates NUEVOS (método: `strings` sobre Image CRUDO, baseline L57=0 medido hoy:
  `comp_algorithm`/`zsmalloc_init`/`zram_maj`/`ZRAM:` todos ×0 en k52L56-build):
  exigir los mismos >0 en el Image L58 + `Image.gz` posterior a DONE (§1). `ZRAM_WRITEBACK`
  `is not set` = correcto (sin backing device no hace falta).

## 4. Activación zram (CONFIG=y no crea el device): unit manual, sin generator

- Medido: staging trae `zramctl+mkswap+swapon` (`usr/bin`, util-linux) pero
  **NO `zram-generator`** (0 ficheros) ⇒ única vía: unit oneshot propia
  (hornear en overlay o aplicar por SSH; OJO: verificar persistencia tras reboot).
- Tamaño: **4G** (`min(ram/2,4G)`, default upstream; RAM esperada ~8 GB). Prioridad
  100. `swappiness`: dejar default 60 (medible, tunable); NO tocar.
- Unit literal (`/etc/systemd/system/zram-swap.service`):
  `[Unit] Description=Swap on zram (L58)` ·
  `[Service] Type=oneshot; RemainAfterExit=yes;`
  `ExecStart=zramctl --find --size 4G --algorithm lz4 + mkswap/swapon -p 100 /dev/zram0`
  (`/usr/bin/`); `ExecStop=swapoff + zramctl --reset` ·
  `[Install] WantedBy=swap.target` → `enable` + verificación
  `cat /proc/swaps`, `zramctl`, `/sys/block/zram0/comp_algorithm` → `[lz4]`.
- Riesgos: `systemd-oomd` SÍ está en staging — con swap la presión baja (favorable);
  vigilar `dmesg | grep -i oom` tras sddm.

## 5. Riesgos/rollback/criterio

- Consolidar de golpe = decisión explícita del dueño (ledger #633: L56/L57 no se
  flashean sueltos) y es lo barato en escrituras (≤2/día): ningún motivo para
  separarlo; si L58 falla, el culpable se aisla por gates (luz⇒PWM, MemTotal⇒mem,
  zram⇒config), no por más flashes.
- Rollback = **L54 `1d641e63…`** (última flasheada+probada). L56/L57 se conservan
  como piezas, NO son rollback (nunca flasheadas, ledger #633).
- PASA = luz ~5 s + `MemTotal` ≈7,x GB + `dmesg | grep UKE-L56` ×2 +
  `/sys/block/zram0/comp_algorithm` = `[lz4]` + quickshell pinta fondo+barra.
  FALLA con luz pero sin RAM ⇒ repack; sin luz ⇒ reabre PWM (no zram).
