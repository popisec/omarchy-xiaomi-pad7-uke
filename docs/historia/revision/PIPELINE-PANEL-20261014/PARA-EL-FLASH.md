# PARA-EL-FLASH — Runbook L46 + s287 (14-oct-2026)

Ciclo: primer DISPLAY ENCENDIDO desde L39. Decisión y justificación en
`docs/historia/revision/PIPELINE-PANEL-20261014/FINAL-INTEGRACION.md` §0–§2. **2 escrituras** (`boot_a` + `dtbo_a`).

## 0. Pre-vuelo (gates, en fastboot; tablet YA en fastboot)

```
fastboot getvar battery-voltage   # EXIGIR ≥3700; hoy 3666 ⇒ EXCEPCIÓN DEL DUEÑO por escrito en el ledger
fastboot getvar all               # registrar slot-retry-count:a/b + unbootable (hoy a=6/b=6 esperado)
# PC: grep -c vci build/kernel-pokes/k52-L16-tree/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c  # ≥5 tras aplicar S1
```

Lector ACM **único** armado ANTES del reboot + vigía al par bueno. `touch`
pause del watch durante los flashes. SSH: `ssh -i build/rootfs/uke-arch-root
-o BatchMode=yes root@192.168.42.129`. No dejar la tablet en fastboot (no carga).

## 1. Build del kernel L46 (solo PC)

```
# 1a. Aplicar (raíces distintas — FINAL-INTEGRACION §2.3):
patch -p1 --dry-run < docs/historia/revision/PIPELINE-PANEL-20261014/s1-vci.diff   # desde RAÍZ del repo
patch -p1            < docs/historia/revision/PIPELINE-PANEL-20261014/s1-vci.diff   # desde RAÍZ del repo
cd build/kernel-pokes/k52-L16-tree
patch -p1 --dry-run < ../../gates/revision/PIPELINE-PANEL-20261014/s4-instrumentacion.diff
patch -p1           < ../../gates/revision/PIPELINE-PANEL-20261014/s4-instrumentacion.diff
cd ~/proyectos/omarchy-uke
git add -A && git commit -m "L46: vci (S1 driver) + S4-DIAG harness; DT vci en s287 (FINAL-INTEGRACION 14-oct)"
# 1b. s3a NO se aplica (parked). s2/s5a/s6 NO se aplican.
# 1c. Build (gates de build-fast.sh sin cambios — no tiene gate POKE-count):
build/gates/build-fast.sh --src build/kernel-pokes/k52-L16-tree --cfg build/kernel-pokes/k52L45-build/.config --out build/kernel-pokes/k52L46-build --tag k52L46
# Esperar DONE k52L46-BUILD-OK (desprendido; log build/logs/build-k52L46.log).
```

Gates nuevos esperados en el binario: `L27-vci-ok` ×1, `L27-vci-absent` ×1,
`UKE-P82: power_on: vci` ×1, `S4-DIAG` ×4, `UKE-POKE` = **115** (113+2; S4 aporta 0).

## 2. Repack L46-display-ON (clon, solo PC)

Clonar `docs/historia/gates-palawan/repack-k52L45.py` → `docs/historia/gates-palawan/repack-k52L46.py` con
**4 cambios exactos** (F-INT-4/5; el script L45 fuerza display-off):

1. `KERNEL = .../k52L46-build/arch/arm64/boot/Image.gz`; `OUT = .../boot-uke-k52L46.img`.
2. G2: sustituir `if b"video=DSI-1:d" not in cmd: die` por
   `if b"video=" in cmd: die("G2 FALLO: display-ON sin video=")`; invocar con
   `--cmdline-append=-video=DSI-1:d` (el mécanisme `-token` borra el token intermedio).
3. G6: la cmdline esperada = k64 **menos** ` video=DSI-1:d` (566 B); exigir
   byte-idéntica a esa (no a k64).
4. G3: `UKE-POKE != 115` (era 113); resto de testigos idénticos (L11/L43/L44/L45/KTZ).

```
python3 docs/historia/gates-palawan/repack-k52L46.py --cmdline-append=-video=DSI-1:d
# → sha256 del OUT; PRE-REGISTRARLO en el ledger ANTES de flashear (fila L46).
```

## 3. DTBO s287 (clon, solo PC)

Clonar `charge/mkdtbo-s286.py` → `charge/mkdtbo-s287.py`: entrada s286
(`33d153f2…`), injerto `fragment@2302 { target-path = PANEL_PATH;
__overlay__ { vci-supply = <&L19B>; }; }` (patrón s283: `dtc -@` genera el
fixup; `L19B` existe en la base — F-INT-1), G-gates: `fdtoverlay` verde +
`fdtget merged panel vci-supply == phandle(L19)` + paridad s286 (gpr disabled,
OPP, backlight, KTZ). `s6-ktz-undup` NO entra (s287 = solo vci).
Pre-registrar sha en el ledger.

## 4. Flash (dueño presente; ≤2 escrituras)

```
fastboot flash dtbo_a build/bootimg/<s287>.img   # (1)
fastboot flash boot_a build/bootimg/boot-uke-k52L46.img   # (2)
fastboot set_active a && fastboot reboot
# Doble captura: ACM (lector único, ya armado) + ssh 'dmesg -w' > out/diag-L46/dmesg.log
# Antes de juzgar: dmesg -n 7 (UKE-P82/K47 son KERN_INFO). sync antes de cualquier reset.
```

## 5. Criterio pasa/falla prefijado

Precondición de lectura: `P82-inh-prep` **ausente** (si presente → inherit
activo → prepare saltado → ciclo NO atribuye a vci; parar, diagnosticar
cmdline). `L27-vci-absent` presente ⇒ build/DT incompleto (no refutación).

- **PASA** si: `L27-vci-ok` + `vci(L19,2.6V) ENABLED` + `pmxr2230_l19 use 1`,
  **y** (`cmd#0` con ACK/respuesta o imagen, **o** firma desplazada en
  **secuencia/punto-de-parada** vs L33/L40 — nunca solo conteos; manda
  **dmesg-SSH**, ACM corrobora — REVIEW-S5 N7).
- **FALLA** (refuta «sin vci el TDDI no escucha», sin reintentos) si: vci
  votado + muerte idéntica (video-done timeout en `cmd#0` / stall host-xfer
  con crudos S4 que lo confirmen) → siguiente ciclo **S3a**.
- **Tercer brazo** si: muerte antes de `K47-pre-rstOK` con vci votado →
  acoplamiento power/reset (no refuta vci); S3a con cautela.
- **Parada**: `vci: enable FALLO` → parar la línea, diagnosticar
  `regulator_summary` en frío. 0 B con batería <gate → INCONCLUYENTE (E3), no evidencia.
- Lectura S4 (tabla E1, cautela N5 — valen los prints IRQ de origen sobre el
  snapshot-DMA): TX-only+underflows→H-S4-1; TIMEOUT=0/BTA-en-write→H-S4-2
  (dueño H4); STATUS0 sin BUSY→H-S4-3 (dueño H1); `cmd#0` avanza→panel escucha.

## 6. Rollback

`fastboot flash boot_a` L45 `83647c45…` + `flash dtbo_a` s286 `33d153f2…` +
`set_active a` + reboot. (Ambos intactos; shas en ledger #618/#619.)
