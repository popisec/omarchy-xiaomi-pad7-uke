# Escalera UKE-CM3: parche + prueba + procedimiento — 28-sep-2026

> Copia integrada en `build/cm3-ladder/` el 28-sep-2026 (original entregado en
> `/tmp/opencode/cm3-ladder/`, efímero). Subconjunto curado: se excluyen el
> binario `test-ladder` (compilado), `a6xx_gmu.c`/`a6xx_gmu.c.orig` (copias del
> fuente del kernel, base `d1c7ef2e0`; el diff basta) y `make-a6xx_gmu.log`
> (log de build, fuera de git por política). Ver NOTAS-OMARCHY.md 28-sep.

Ficheros (en `/tmp/opencode/cm3-ladder/`, sin commit, sin tocar la tablet):

| Fichero | Qué es | Estado |
|---|---|---|
| `uke-cm3-ladder.diff` | el parche (solo `drivers/gpu/drm/msm/adreno/a6xx_gmu.c`) | aplica `-p1` limpio, verificado por roundtrip byte-idéntico |
| `apply-and-build.sh` | copia el árbol (solo lectura del compartido), aplica, compila | **ejecutado: `CC a6xx_gmu.o` OK**, árbol intacto (md5 git-status idéntico) |
| `test-ladder.c` + `run-test.sh` | harness del método, 3 escenarios | **ejecutado: los 3 pasan** (ver §2) |
| `measure-cm3.sh` | procedimiento en caliente, sin flash | `bash -n` OK; pendiente de tablet |
| `a6xx_gmu.c` / `.orig` | copia de trabajo y original | base `palawan-linux@s150-postclk` (`d1c7ef2e0`) |

## 1. La escalera (qué cubre, en orden)

Camino CM3 instrumentado, cada acceso con `uke_poke()` pre/post y cada
lectura con `printk` PRE/POST incondicional (`DRM_DEV_INFO`, prefijo
`UKE-CM3:`), reutilizando los pokes existentes (S/F/P/H). Citas sobre el
fichero base:

- L00 `fw_load`: PRE/POST de `CORE_FW_VERSION` (`a6xx_gmu.c:935`, `readl`).
- L01 `fw_start`: `INIT_RESULT←0` + `BOOT_CONFIG←0x02` (`:1005-1006`, writes).
- L02: `HFI_QTBL_ADDR/INFO` (`:1010-1011`, writes).
- L03: ráfaga `FENCE_RANGE_0` (`:1025`), `CM3_CFG` (`:1034`), `GENERAL_10`
  + `GENERAL_8` (`:1057-1060`, rama a7xx = la de uke/Adreno 732) **imprimiendo
  el chipid** (`0x70b0000` del catálogo para `0x43030b00`).
- P3: PRE/POST de `power_config` (`:1079`; en a7xx solo escribe
  `SYS_BUS/ICACHE/DCACHE_CONFIG`, `:819-821`).
- L10: **primer `readl` del camino**: `DTCM_START+0xff8` (`:299`).
- L11: `SYSRESET←1` (`:315`, write). L12: log-wptr (`:321-326`, write).
- L13: `SYSRESET←0` (`:330`, write, release).
- L14 (**canario, nuevo**): un solo `readl` de `FW_INIT_RESULT` antes del
  sondeo. `FW_INIT_RESULT` es estado de solo-lectura: leerlo no cambia nada.
- L15: sondeo `FW_INIT_RESULT` (`:333-334`, `readl_poll_timeout`, timeout
  100 s) con POST de `ret` + último valor.
- L16: lo de después: `HFI_CTRL_INIT` + sondeo `HFI_CTRL_STATUS`.

Lógica del driver intacta: el único diff no-instrumental son 3 `if/else` a
bloques con llaves (misma condición, misma escritura). Cero borrados de
código (`diff | grep '^<'` solo muestra esas 3 líneas re-añadidas).

## 2. Prueba sin tablet (real, no razonada)

`run-test.sh` compila el harness y corre 3 escenarios sobre la misma
disciplina PRE→acceso→POST (log con fflush+fsync = printk a logbuf;
marcador con fsync = `uke_poke` síncrono). Salida medida 28-sep:

- **hang** (readl canario no vuelve): hijo sigue vivo; última kmsg =
  `UKE-CM3: PRE canary-init-result reg=0x1f81c`, último marcador =
  `L14-pre-canary`, cero `POST canary`. **La última línea señala el acceso.**
- **garbage** (`0xdeadbeef`): completa con rc=1, `POST canary val=0xdeadbeef`
  + `GMU firmware initialization timed out`. **Basura ≠ cuelgue.**
- **ok** (`0x100`): `POST poll ret=0`. **Sano completa.**

Límite honesto de la prueba: demuestra la disciplina de logging, no el
timing de flush de printk bajo un stall AXI real. Por eso el parche empareja
cada printk con `uke_poke` (pinta la fila él mismo, síncrono, falla cerrado;
`uke-poke.h` + `uke-panic-fb.c:240-253`, tags de hasta 43 car.; origen del
canal: ronda 9). La lección de ronda 38 (kprobe ve la entrada, kretprobe el
retorno) es la misma idea en banda: PRE = intentó, POST = completó.

## 3. Lo que hay que medir (sin gastar un flash)

**H1 (CM3 depende de apps-smmu, SID 5) está archivada por R-57** (tres
premisas falsadas por código: `IOMMU_PRIV` es un bit AP de PTE
`a6xx_gmu.c:1611`→`msm_gem.c:464-465`; el ACTLR se programa también para el
cliente `qcom,adreno-gmu`, `arm-smmu-qcom.c:351-408`; y el dominio GMU lleva
`CFCFG=0`, o sea sus faults dan error, no wedge). **No re-proponerla.**
Lo que queda por distinguir —y la escalera lo distingue— es:

- **Bloque GMU sin decode/power/reloj** vs **CM3 que no contesta**:
  última línea `PRE dtcm-magic` (L10) = el primer readl ya muere (mirar la
  línea `UKE-CM3DBG: clks` del mismo arranque); `POST poll` + `timed out` =
  el bus funciona y el CM3 no contestó (dos categorías distintas, R-57).
- **Muerte síncrona con el release** (fetch del CM3 mata el bus) vs
  **CM3 muerto en el poll**: `PRE canary` (L14) último = lo primero;
  canario OK + poll colgado = lo segundo (firma dependiente del fw vivo).
- **¿Leer estado del CM3 en caliente? No.** Ronda 33: prohibido volcar
  MMIO/regmap en runtime (cuelga). La única lectura en caliente admitida es
  la que ya va dentro del camino (canario L14). Instrumentar en arranque.
- **Arranque vs resume**: la escalera lo separa por fases — F (bytes a
  TCM + versión), P (config + chipid), L (reset + poll), H (HFI) — y el
  resume ya trae H1–H5. Regla: `F4-verOK` presente + L10 ausente = el gating
  está entre carga y arranque (power/reloj del CX), no en el fw.
- **El otro cuelgue (sin legacy)**: `adreno_request_fw` (`adreno_gpu.c:535-601`)
  cae al helper `request_firmware()` cuando faltan new+legacy: atasco de
  ~60 s/fichero ANTES de F1, firma distinta del CM3 (DESPUÉS de F4). Ya
  excluido sin flash: paquete `uke-gpu-firmware` instalado y verificado
  (R-57: 14 ficheros, 8 sha) + gate G1 de `measure-cm3.sh` (`ls`
  `/lib/firmware/{,qcom/}gen71100_gmu.bin` + `dmesg | grep legacy location`).
- **H1 viva que sí imprime la escalera**: chipid `0x70b0000` del catálogo
  (`a6xx_catalog.c`, entrada `0x43030b00`, familia `ADRENO_7XX_GEN2`) nunca
  validado en el GMU (reencuadre R-57, punto 1). La línea `cfg-chipid` lo deja
  en el log del intento, gratis.

## 4. Qué dirá el intento y qué NO (límites antes de gastar)

**Dirá**: el acceso exacto wedged dentro de la lista del §1 (último
PRE sin POST, en dmesg-w y/o poke en pantalla); si el bus decodifica
(canario OK) o no (L10 último); si el CM3 contestó tarde/mal (timeout con
valor) o nunca; el chipid y los relojes reales de ese arranque.

**NO dirá**: a nivel AXI, "registro no decodificado" y "dispositivo que no
responde" son indistinguibles —ambos presentan `readl` que no vuelve—.
La desambiguación es por contexto (clks, chipid, fase F vs L), no por la
línea sola. Tampoco cuenta iteraciones dentro del poll (el canario solo acota
primera-vs-resto) y la cola serie puede perderse al reset (por eso la doble
captura: ACM + `dmesg -w` a fichero, ledger #428→#429).

## 5. Reglas del procedimiento (`measure-cm3.sh`, sin flash)

`dmesg -n 7` primero; doble captura ABIERTA y con marcador verificado ANTES
del trigger; trigger en caliente T1 (runtime PM `control=on`) o T2
(unbind/bind); `sync` antes de cualquier reboot; el script **no reinicia**:
R-42 (watchdog del s229 no arreglado) ⇒ reset físico del dueño.
Refutados respetados: R-57 (H1 no se re-propone), R-42, ronda 33 (nada de
MMIO en runtime), R-12 (irrelevante: no hay flash), techo de 3 ciclos por
hipótesis (este intento decide: si L15 da timeout, el bus vive; si L10/L14
son lo último, el wedge es del bloque GMU).
