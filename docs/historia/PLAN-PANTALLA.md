# PLAN-PANTALLA — que la pantalla funcione DEL TODO (28-sep-2026, tarde)

> Sesión orquestador (ZCode). El trabajo lo hacen subagentes; los flashes los ejecuta SOLO el
> orquestador con pre-registro. Serie de artefactos: **s253+** (desde s250 son de este repo).

## Objetivo medible (cierre, sin apaños)

La pantalla funciona del todo ⇔ TODOS, **persistentes** (sobreviven a
`sync; sync; echo b > /proc/sysrq-trigger`):

1. `/dev/dri/card0` con conector del panel O82 y `modes` 3200×2136 (`drm_info`/`modetest`).
2. **Foto** de la tablet mostrando contenido (fbcon o Hyprland).
3. GPU en el camino: `eglinfo -B` = `freedreno` + GLES 3.2 sobre esa card.
4. Sesión Omarchy (Hyprland + quickshell) visible en el panel — **foto final**.

**NO son cierre**: el vfb de la cmdline, `separate_gpu_kms=1` sin conectores, nada que no
sobreviva un reinicio, nada que viva sólo en runtime de un boot.

## Cadena y huecos (REVISADO 28-sep tarde, con evidencia de los subagentes)

```
apps-smmu ─→ msm_dpu(master) ─→ mdss ─→ dsi@ae94000 ─→ dsi-phy ─→ panel O82 ─→ backlight
   ❌ compatible+reg    ❌ -19 sin IOMMU    (ligado)    ✅ YA LIGA    ⚠️ GPIO2   ✅ existe
      (A′ = s253)                                          (s238 lo     (probe difiere:
                                                             renombró    "failed to get
                                                             a 4nm)      reset gpio")
```

Correcciones importantes contra la foto previa (con fuente en `EVIDENCIA-PANTALLA-28sep.md` e
`INFORME-PHY-PANEL.md`):
- **El DSI PHY ya está resuelto**: el payload del `s238` (fragment@1105) ya renombró los PHY a
  `qcom,sm8650-dsi-phy-4nm` y el hermano midió los dos PHY ligando (#410). **No hay ciclo de
  PHY** — el fragmento propio es un no-op (+0/-0 verificado).
- **El driver del panel ya va integrado** en el kernel en marcha (`CONFIG_DRM_PANEL_XIAOMI_O82_
  DUALDSI=y` en build-s122 #82) y su probe corre: difiere por `failed to get reset gpio` (GPIO2
  del tlmm compartido con refs vendor). El `.ko` compilado (`build/pkg/panel-o82/`, sha
  `98902587…`) solo hace falta para el kernel-pokes, que lo trae apagado.
- **Hueco 1 (EL muro, sigue)**: el nodo apps-smmu vivo YA tiene forma vendor (2 `reg` + 8 hijos
  `qcom,qsmmuv500-tbu`); no bindea por el **compatible** (`qcom,qsmmu-v500` fuera de los
  of_match del driver sin LEGACY_DT_BINDINGS). Y el wedge del s251 tiene mecanismo candidato
  con lector de código: el driver deriva la base de los context banks del **tamaño de reg[0]**
  — con 1 MiB, los CB caían fuera del mapeo ⇒ oops mudo. **s253** = compatible triple mainline
  + `reg` única de 2 MiB + `reg-names`. Gates verdes (`INFORME-A-PRIMA.md`).
- **Hueco 2 (nuevo)**: GPIO2 reset del panel (SG-GPIO investigando; fragmento para s254).
- Resuelto ya: reguladores L8/vddil8b (`s238`), vsp/vsn por proxy (`gpio-shared-proxy.ko`
  cargado), backlight (`/sys/class/backlight/ae94000.dsi.0`), cmdline sin `separate_gpu_kms`.
- **GPU (post-panel)**: abrir `card0` resume la GPU ⇒ cuelgue conocido del CM3 (R-57). Antes de
  abrir: escalera `measure-cm3.sh`. Sin `/dev/watchdog` hoy ⇒ cada cuelgue = reset físico.

## Fases

### F0 — Evidencia viva + base de conocimiento (SG-EVIDENCIA) — 0 escrituras en tablet
DT vivo de toda la cadena display (nombres, phandles, compatibles, `driver` symlinks),
`iommu_groups`, `drivers_deferred`, dmesg completo, configuración exacta del nodo apps-smmu
vivo. → `build/gates/EVIDENCIA-PANTALLA-28sep.md` + dumps en `build/evidencia/2026-09-28/`.

### F1 — Construcción offline (3 subagentes en paralelo) — 0 flashes
- **SG-SMMU (A′)**: informe + constructor `mkdtbo-s253.py` (= `s238` + fragmento A′) con TODOS
  los gates (fdtoverlay contra DT base real, `uke-dtbo-check.py`, aserciones de FORMA contra el
  nodo vendor, phandles). Postmortem de por qué `s251`/#431 wedgearon y en qué difiere A′.
  Árbol de decisión de consola para el ciclo 1. **SIN FLASHEAR.**
- **SG-PHY-PANEL**: (a) mapear `qcom,dsi-phy-v5.2` → compatible mainline (leer
  `dsi_phy_dt_match`, comparar `reg`/props contra stock-fdt2); (b) compilar
  `panel-xiaomi-o82-dualdsi.c` como **módulo** en copia `/tmp` del árbol (patrón
  `aplicar-parche-msi.sh`), con sha; (c) auditar config del kernel (DRM_MSM, DSI, DSC);
  (d) fragmento de overlay del nodo panel si hace falta. **SIN FLASHEAR.**
- La escalera CM3 ya existe (`build/cm3-ladder/`, harness 3/3) — se usa tal cual en F2.4.

### F2 — Escalera de bring-up EN LA TABLET (solo el orquestador) — 1 cambio por ciclo
Canal: `scp` de la imagen a `/root` + `dd of=/dev/disk/by-partlabel/dtbo_b` + `sync` +
verificación por relectura sha256 + reinicio `sysrq-b`. Consola ya capturada por
`bin/uke-console-cap.sh` (PID 77586, único lector — NO tocar `/dev/ttyACM0`).

| Ciclo | Artefacto | Cambio único | Evidencia de éxito | Rollback |
|---|---|---|---|---|
| 1 (#P1) | `s253` = s238 + **A′** | apps-smmu: compatible mainline + reg 2 MiB | `arm-smmu 15000000…probing` + dpu sin `no IOMMU` | rescate (s238) |
| 2 (#P2) | `s254` = s253 + **GPIO2** | refs vendor del pin 2 neutralizadas | probe del panel pasa del reset gpio; (con #P1) `card0` + modes → **FOTO** | rescate (s238) |
| 3 | — (0 flashes) | verificación: modetest/backlight/fbcon | `modetest` pinta en panel → **FOTO** | — |
| 4 | GPU: escalera CM3 → GLES | (sin flash; .ko panel solo si kernel-pokes) | `eglinfo -B` freedreno; Hyprland en panel → **FOTO FINAL** | — |

**Gates de cada ciclo**: batería ≥ 3700 mV (hoy 3432 y cargando a ~100 mA por USB del PC —
esperar o cargador de pared), fila pre-registrada en `build/gates/PRE-REGISTRO-PANTALLA.md`
con sha256 antes/después + evidencia esperada + rollback, vigía de fastboot armado ANTES del
primer flash (rescue: restaurar par bueno del `build/backup-par-bueno/`), doble captura
(consola + `ssh dmesg -w`).

### F2-bis — La vía apps-smmu por kernel (28-29 sep noche, serie K1-K7)
La vía DT murió (#P6: el compatible wedgea). Serie de kernels instrumentados (ver
PRE-REGISTRO #P8-#P16): el probe completo SOBREVIVE con `uke_keep_boot=1` + `uke_reset_mask=0xc`
(fase2/3 omitidas — no tocar el handoff del bootloader). Muertes restantes localizadas: lectura
de S2CR(0), CB vivo del UFS (carrera con DMA), y una post-fase7 sin cerrar.
**K7 (EJECUTADO 29-sep 01:40, #P17)**: cmdline armada (`1c1a090b…`, K6 sin recompilar) flasheada
en boot_b (único flash de la noche) → **muerte muda a ~1 s**: sin consola/NCM/SSH, USB colgado
full-speed con error -71, sin bucle de pánico. **Confundidor descubierto**: todos nuestros boots
experimentales vienen de `fastboot reboot` ⇒ la sesión USB/dwc3 del ABL está VIVA en el handoff
(sus DMA cuelgan del apps-smmu), cosa que el Android dorado nunca tiene. **La repetición LIMPIA
es gratis**: K7 ya está en boot_b y armada por cmdline — un power-cycle físico en frío arranca el
mismo experimento sin fastboot-USB vivo. Si vive: grupos → bind DPU → **card0 + modetest + FOTO**
(runbook R2). Si muere muda otra vez: el attach es estructuralmente letal → planes B/C de R1
(mask=0 sin reset, protect_smr0, parche handoff estilo ChromeOS — ver R4).

### F3 — Permanencia y cierre
Driver del panel auto-cargado (`modules.alias` + depmod en el rootfs) o integrado en el árbol;
watchdog arreglado plegado al dtbo final (con su ciclo propio si no se validó antes); F9 slot A
si el camino GPU exige kernel instrumentado; documentar en ESTADO-VIVO/NOTAS + commits.

## Reglas duras (heredadas, se aplican a TODOS los subagentes)

1. **Nadie toca la tablet** salvo el orquestador en F2. Ni writes, ni modprobe, ni reboot.
   `/dev/ttyACM0` NADIE lo lee (hay captura única corriendo).
2. `~/gpu-work/palawan-linux`: **SOLO LECTURA** (hay otras sesiones vivas). Para compilar,
   copia rsync a `/tmp` como hace `build/gates/aplicar-parche-msi.sh`.
3. Repo hermano `~/proyectos/ubuntu-permanente`: solo lectura.
4. En este repo: SOLO ficheros nuevos; nada de editar lo existente; NO commitear (integra y
   commitea el orquestador). Series: `s253+` nuestras.
5. Evidencia con `fichero:línea` o comando+salida; DATO vs INFERENCIA; lo no comprobado,
   NO VERIFICADO. Nada de memoria.
6. SMMU nunca en runtime; nunca volcar rangos de registros; un flash = una fila pre-registrada.

### Cierre 30-sep (#P40-#P43)
K13+s260: **kms init PASA y card0 NACE** (`Initialized msm 1.13.0` a 4,06 s; card0-DSI-1 +
Writeback + renderD128). El asesino final (medido con modetest bajo control): el fallback
attach_group metió al HOST DSI (identity, funcionaba) en el dominio paging del KMS → comandos
DSI faultean → wedge. **K16 = split de grupos display** (diseño completo y ejecutable en
`build/gates/K16-DISENO.md`): cada master su grupo; dpu con su paging, DSI host de vuelta a
identity (como la era s258). Tras K16: fw GPU (ya en rootfs) para render → e2fsck → Omarchy.
