# L50-INSTRUMENT — Subdivisión del wedge DSI_1 + F0 del dma_base (14-oct-2026)

> Preparador L50. Solo lectura (árbol `build/kernel-pokes/k52-L16-tree` intacto;
> diff sobre copia en /tmp, `patch -p1 --dry-run` OK; nada en la tablet).
> Base: `docs/historia/revision/PIPELINE-PANEL-20261014/L50-SMMU.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/L50-DCS-VENDOR.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/L50-PREP.md`, captura
> `out/CAPTURA-MUERTE-netconsole.log` (última línea `K47-host-xfer`, ledger #624).

## 1. Qué he leído (fichero:línea)

- `dsi_manager.c:497-541` (`msm_dsi_manager_cmd_xfer`): caso sync → DSI_0 retorna
  en `:514-515` sin transmitir; DSI_1 hace prepare h0 (`:517-524`) + prepare
  propio (`:525`) + `cmd_tx` (`:531-532`).
- `dsi_host.c:2180-2213` (`xfer_prepare`): `pm_get` → `link_clk_set_rate` (`:2197`)
  → `link_clk_enable` (`:2198`) → write `REG_DSI_CTRL` (`:2206-2209`).
- `dsi_host.c:1447-1490` (`dsi_cmd_dma_tx`): `dma_base_get` (`:1454`) → `wait4video`
  (`:1462`) → trigger (`:1464-1465`) → wait 200 ms + `S4-DIAG` (`:1475`).
- `dsi_host.c:2379-2389` (`commit`): writes `DMA_BASE/LEN/TRIG` + `wmb()`.
- `dsi_host.c:1791` (`K47-host-xfer` en `dsi_host_transfer`): punto de muerte #624.
- `dsi_host.c:7`, `dsi_manager.c:7`: ambos incluyen `linux/uke-poke.h` (pokes usables).
- `l49-capture.diff`: estilo (pokes inertes `uke_poke`, X9 s166/s167 los falsó asesinos).
- `docs/historia/gates-palawan/repack-k52L49.py`: base del repack (gates G0–G8, cmdline 580 B, FBDEV=n).

## 2. El diff: `l50-instrument.diff` (12 pokes K50-*, 0 funcional)

| Poke | Sitio | Qué imprime |
|---|---|---|
| `K50-mgr-enter` | manager `:509` | `id`, `need_sync` (¿caso sync? ¿DSI_1?) |
| `K50-prep0-before/after` | manager `:521/523` | bracket del prepare de DSI_0 |
| `K50-prep1-before/after` | manager `:528/530` | bracket del prepare propio (DSI_1) |
| `K50-clk-rate` | prepare `:2201` | antes de `link_clk_set_rate` (discrimina R1) |
| `K50-clk-en` | prepare `:2204` | tras `link_clk_enable` + `id` |
| `K50-ctrl-ok` | prepare `:2218` | tras el write `REG_DSI_CTRL` + `id` |
| `K50-dma-base` | dma_tx `:1460` | **F0: `dma_base=%llx` + `id`** (IOVA tablas RAM) |
| `K50-vid-ok` | dma_tx `:1465` | tras `wait4video_eng_busy` (discrimina R2) |
| `K50-trig-done` | dma_tx `:1469` | tras el trigger + `id`, `triggered` |
| `K50-commit` | commit `:2394` | entrada + `id`, `base`, `len` (¿llega a DSI_0/DSI_1?) |

Orden esperado (sync, id=1): mgr-enter → prep0-before → clk-rate → clk-en(0) →
ctrl-ok(0) → prep0-after → prep1-before → clk-rate → clk-en(1) → ctrl-ok(1) →
prep1-after → dma-base → vid-ok → commit(0) → commit(1) → trig-done.
(`K50-clk-rate` no lleva `id`: 1ª ocurrencia = DSI_0, 2ª = DSI_1.)

## 3. Tabla de lectura: última línea → veredicto

| Última línea | Veredicto |
|---|---|
| `K47-host-xfer` aún (sin ningún K50) | **Canal o entry/mutex**: wedge en `mutex_lock`/entrada del manager ANTES del primer poke, o el canal no vio la ráfaga (regla ±1, §5). No es A ni B: re-subdividir, no fix |
| `K50-mgr-enter` sin `prep0-before` | Muerte en entry del manager tras el poke (mutex/sync-dispatch; anotar) |
| `K50-prep0/1-before` sin su `clk-rate` | **Resume/F2**: wedge en `pm_runtime_get_sync` (resume GDSC) antes de clocks. Ni A ni B: veredicto "resume", el hueco más serio |
| `K50-clk-rate` (sin `clk-en`) | **B (R1)**: wedge en el re-voto de link-clocks |
| `K50-clk-en(id)` sin `ctrl-ok` | **B-variante**: colgado entre `link_clk_enable` y el write `REG_DSI_CTRL` — incluye `set_tx_power_mode` + `dsi_read`, NO solo el write (no sobreinterpretar) |
| `K50-prep0/1-after` sin `dma-base` | **iova-fail o retorno/entry**: wedge en el retorno del prepare / entrada de `cmd_tx`, o `dma_base_get` fallido (ese deja el `pr_err` preexistente "failed to get iova", visible pero sin casilla K50) |
| `K50-dma-base(+valor)` sin `vid-ok` | **B (R2)**: `wait4video`/interlock, fetch aún no emitido |
| `K50-vid-ok` sin `commit` | Inter-trigger (raro; anotar, no A ni B) |
| `K50-commit(0)` sin `commit(1)` | Trigger-MMIO de DSI_1 colgado (ni fetch ni clocks) |
| `K50-commit(1)`/`trig-done`, sin S4-DIAG | **A**: wedge tras el trigger = fetch cmd-DMA (SMMU/IOVA) |
| `S4-DIAG` visible | Timeout gracioso: ni A ni B en forma wedge (re-evaluar) |
| Última=`K47-host-xfer` CON ráfaga K50 perdida | **Canal mudo**: el wedge cayó <300 µs tras el último poke y la cola no flusheó. Aplicar regla ±1 poke (§5); si el canal sigue mudo tras el test, → Gate B sync-flush, no L51 |

Nota de fidelidad (crítica-L50 §4): la ráfaga K50 (~18 líneas en <1 ms junto al
wedge) puede ir 1 (raro: 2) pokes por detrás del punto real si el wedge cae
<300 µs tras el último poke. El par delicado es `vid-ok`/`commit` (R2 vs
inter-trigger). El dato F0 (`dma_base`) sale TEMPRANO (antes de wait+trigger),
casi seguro ya flusheado aunque se pierda la cola: el objetivo primario está
a salvo. `K50-clk-rate` sin `id`: 1ª ocurrencia = DSI_0, 2ª = DSI_1 (frágil
ante pérdida de cola; documentado, no cambiado).

`dma_base` ~0x1000/0x2000 (tablas RAM, cf. L50-SMMU §4) + muerte tras trigger ⇒ A.
Muerte en prepare/clocks ⇒ B. R1 débil en 1ª transferencia (matiz anotado):
si cae en `clk-rate/en`, R1 deja de ser débil.

## 4. Gates de build (`repack-k52L50.py` = clon de `repack-k52L49.py`)

- `OUT=boot-uke-k52L50.img`, `KERNEL=k52L50-build/.../Image.gz`; cmdline **sin
  cambios** (580 B display-ON + `iomem=relaxed`); `FBDEV=n` (gate `drmfb=0`).
- G3 nuevo: `raw.count(b"K50-")==18` (6 tags ×1 + 6 tags ×2 por su `pr_err`
  con valores) + los 6 formatos con valores ×1 (`K50-dma-base=`, `K50-commit: id=`,
  `K50-mgr-enter: id=`, `K50-clk-en: id=`, `K50-ctrl-ok: id=`, `K50-trig-done: id=`).
  Medido en el diff (18/6/6×1); `grep -c "UKE-POKE" l50-instrument.diff` = 0.
- Se mantiene: `UKE-POKE==115` (los `uke_poke()` no duplican el literal, F-INT-5),
  L49 ×5, **S4-DIAG ×4 en BINARIO** (en fuente sale 9× con comentarios; el gate
  cuenta en el binario como hizo L49 — medido L49 Image.gz: 4), resto de gates
  L11–L48 intactos.
- Publicar: `sha256` del `boot-uke-k52L50.img` para pre-registro en ledger.

## 5. Runbook L50 (1 escritura: `boot_a`; dtbo s287 se queda; sddm OFF)

Pre-vuelo estándar: `getvar all` (4 retries), mV ≥3700, semáforo inter-proyecto
(ESTADO-ACTUAL.md + ledger hermano), fila ledger **pre-registrada con sha ANTES
de flashear**, readback al tamaño exacto, cargador de pared.

1. PC: `ip link show enp0s20f0u3` → MAC vigente; armar `out/netconsole-recv.sh
   out/CAPTURA-L50-netconsole.log` (lección #624: MAC del gadget churna).
2. SSH: `echo "7 4 1 7" > /proc/sys/kernel/printk`; **verificación OBLIGATORIA**:
   `echo '<3>L50-PROBE-...' > /dev/kmsg` **DEBE llegar** al receptor (×3). Sin
   probe, no hay test.
3. Paralelo: `ssh ... 'dmesg -w' > out/CAPTURA-L50-dmesgw.log` (respaldo TCP);
   ACM **lector único** armado. Dumper v2 truncado: **no depender de él**.
4. Test: **1 intento** `modetest -M msm-kms -s 36@85:#0` (`:#0`, no `:0`).
5. Al cortarse: última línea del netconsole = el punto (§3) + valor `dma_base`.
   **Regla de lectura "±1 poke"** (crítica-L50 §4): la última línea observada
   puede ir 1 (raro: 2) pokes por detrás del punto real; el par delicado es
   `vid-ok`/`commit` (R2 vs inter-trigger) — ante duda, anotar ambas.
   Reset físico; recoger `out/CAPTURA-L50-*.log`; `ls /sys/fs/pstore` (0 coste).
6. Rollback: L49 `ccfdea9d…` / L48 `0b1d22c4…` (2ª escritura solo si procede).

Higiene de procesos (lección 14-oct, NOTAS:4289): `pkill`/`kill` del lector ACM
y del receptor **SIEMPRE por PID explícito** (guardar `$!` al armar), nunca por
patrón — el patrón se auto-mata.
Verificación del canal: en #624 los probes `<3>` llegaron 2/3 con MAC estable —
**aceptar 2 de 3 basta**, no exigir 3/3 ciego.
Ramas FALLA: (a) última = `K47-host-xfer` aún ⇒ wedge en entry/mutex o canal
mudo → re-subdividir / Gate B sync-flush, NO fix, NO L51; (b) muerte en
`prep-before` (sin `clk-rate`) ⇒ veredicto resume/F2 (GDSC), ni A ni B.

## 6. Criterio de éxito → L51

**Éxito** = nueva última línea K50-* + `dma_base` impreso → veredicto A vs B (§3).
**L51** = fix quirúrgico: A → `wmask=0x180` (F1) o F2-bypass discriminante;
B → guarda del re-voto (F-f) o VID-tras-DCS (F-b). Presupuesto L50: 1 escritura.

## 7. Qué NO hacer / no verificado

Nada de SMMU/GDSC/VBIF/OPP/sddm/DT; ni `msleep` en el path; ni 2 lectores ACM;
ni 2º `modetest` el mismo día. No verificado: valor de `dma_base` en el boot
mortal (lo trae este ciclo); SID emitido por el motor cmd-DMA (L50-SMMU §7).
