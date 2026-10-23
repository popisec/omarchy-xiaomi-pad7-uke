# INV-KGSL-RE (2026-10-08): ingeniería inversa del msm_kgsl.ko vendor (gen7/cliffs)

**Pregunta**: ¿qué secuencia EXACTA ejecuta el driver vendor (msm_kgsl.ko de la ROM
OS3.0.303.0.WOZEUXM) antes de soltar el reset del CM3 del GMU (S3-rst0), que nuestro
port mainline no ejecuta y que provoca el congelamiento del SoC?

**Método**: 100% offline. vendor_dlkm (29 MiB, **EROFS**, no ext4) extraído del
super.img sparse por rangos (parser python propio, /var/tmp/sparse_xtract.py; el raw
completo son 10,5 GiB y no cabía). msm_kgsl.ko (3.532.384 B, ELF aarch64 **con symtab
completa** y KCFI) desensamblado con llvm-objdump (el objdump de binutils de este
sistema no soporta aarch64). Las copias /var/tmp/{msm_kgsl.ko,kgsl.asm,kgsl-dr.asm}
existían ya de la sesión 15:48-15:52; la extracción se ha verificado de forma
independiente. No se ha tocado la tablet.

| fichero | md5 |
|---|---|
| msm_kgsl.ko (vendor_dlkm_a/lib/modules) | `e2b2828fcc9e7c4a7fa4daf69c98988b` |
| /var/tmp/parts/vendor_dlkm.img (EROFS, re-extraído) | partición `vendor_dlkm_a` 29 MiB @ super+0x1c3a00000 |

**Semántica de registros**: `kgsl_regmap_write(regmap, val, off)` termina en
`writel(val, virt + (off - window_start)*4)`; los offsets del vendor coinciden 1:1 con
los del XML de nuestro árbol (`registers/adreno/a6xx_gmu.xml`) en 4 anclas
(ITCM_START 0x1b400, DTCM_START 0x1c400, GMU_CM3_SYSRESET 0x1f800,
GMU_CM3_FW_INIT_RESULT 0x1f81c), así que las "direcciones" kgsl y las del XML son la
misma unidad. **Ojo**: el XML k52 pone SYSRESET en 0x1f800 (mapa gen7), no 0x1f770
(que era del mapa a6xx antiguo).

## 1. Cadena de arranque vendor (gen7)

`gen7_gmu_boot` @0x7c594 (llamado desde `gen7_gmu_first_open` y desde
`gen7_hwsched_gmu_boot` @0x815d8 para el path hwsched):

```
1. kgsl_pwrctrl_request_state(dev, 0x20)
2. kgsl_pwrctrl_enable_cx_gdsc(dev)            // regulator CX GDSC
3. gen7_gmu_enable_clks(dev, 0)                // clk_bulk prepare+enable (GXI+GMU)
4. gen7_enable_ahb_timeout_detection(dev)
5. gen7_cx_timer_init(dev)
6. gen7_rscc_wakeup_sequence(dev)              // wake RPMh RSC (ver §3)
7. gen7_gmu_load_fw(dev)                       // copia bloques fw (ver §2)
   error → clk_bulk_disable/unprepare + kgsl_pwrctrl_disable_cx_gdsc
           + gen7_rdpm_cx_freq_update(dev,0)
8. gen7_gmu_register_config(dev)               // §4: cfg GMU pre-reset
9. gen7_gmu_irq_enable(dev)
10. [dev+0x2f4c]=0 ; dmb ishst
11. gen7_gmu_device_start(dev)                 // §5: SYSRESET=0 + poll
12. gen7_gmu_hfi_start(dev) ; gen7_hfi_start(dev)
    error → gen7_gmu_irq_disable; si [dev+0x14f8]: gen7_gmu_suspend
13. kgsl_pwrctrl_set_state(dev, 0x20)
```

## 2. gen7_gmu_load_fw @0x775d0 — solo copia, SIN reset

Recorre la tabla de bloques del gmu.bin (mismo formato que `a6xx_gmu.c`:
`{u32 addr, size, type, value; u32 data[]}`) y despacha por rangos (7 rangos en una
tabla de 24 B/entrada). Rutas:

- rangos ITCM/DTCM (0 y 2): `kgsl_regmap_bulk_write(regmap, dst, datos, n)`,
  destino = **0x1b400 + (addr−base)>>2** para ITCM y **0x1b400+0x1000 + …** (=0x1c400,
  `GMU_CM3_DTCM_START`) para DTCM. Es decir: las palabras del fw van a las ventanas
  `GMU_CM3_ITCM_START`/`GMU_CM3_DTCM_START` (0x1b400/0x1c400), igual que
  `__a6xx_gmu_write_data` mainline.
- rangos 3..6 (SRAM GMU @0x100000/0x200000/0x300000 y otros): `memcpy` directo a
  buffers shadow ya mapeados (patch del puntero destino en el BO).
- rango 7 no cubierto → `_dev_err("...")` + -EINVAL.
- Al terminar TODOS los bloques: **`dsb st`** y return 0.

No toca SYSRESET, no enciende clocks: solo escribe memoria del GMU.

## 3. gen7_rscc_wakeup_sequence @0x7730c — el wake del RPMh RSC

```
si !([dev-0x2c0] & BIT(3)) → return 0        // flag "RSC dormía"
write(RSCC 0x02003B07 ← 0x2) ; dsb(st)
timed_poll_check(RSCC 0x02003B08, val 0x2, mask 0x2, 100 iter)  // ACK
  fail → dev_err + -ETIMEDOUT
espera activa (ktime, límite 0x05f5e100 ns = 100 ms) de que [dev-0x2b8]+0x404
  (gestor de clks/reguladores) dé "activo", con usleep_range(26,100)+yield
write(RSCC 0x02003B07 ← 0x0)                  // devolver RSC a estado normal
```

`0x02003B07/8` es el par CONTROL_REQ/ACK del espacio RSCC (RPMh RSC). **El vendor
despierta el RSC y espera su ACK antes de continuar**; además usa el mismo espacio
RSCC en register_config (§4, fila 7).

## 4. gen7_gmu_register_config @0x78324 — 17 escrituras pre-SYSRESET (ORDEN EXACTO)

(`regmap` = dev+0x1500; todas `kgsl_regmap_write`; la tabla de nombres es la del XML
k52; los registros sin nombre en el XML son vendor-only)

| # | registro | valor | nota |
|---|----------|-------|------|
| 1 | 0x1f8f1 | 1 | **sin nombre en XML mainline** |
| 2 | 0x1f8f0 | 1 | **sin nombre en XML mainline** |
| 3 | 0x1f81c GMU_CM3_FW_INIT_RESULT | 0 | limpia resultado anterior |
| 4 | 0x1f801 GMU_CM3_BOOT_CONFIG | 2 | |
| 5 | 0x1f985 | *(x+0xb8)* runtime | vendor-only (x = [dev-0x13f8]) |
| 6 | 0x1f984 | 1 | vendor-only |
| 7 | RSCC 0x02003b11 | 0x80c808a0 | espacio RSCC (RPMh), vendor-only |
| 8 | 0x1f82d GMU_CM3_CFG | 0x4052 | mainline: dinámico (gmu_pwrlevel…) |
| 9 | 0x00000000 (base GMU) | 0x3c45 | vendor-only |
| 10 | 0x1f9d0 | ([x+0xb8] & ~0xfff) \| 0xf | cond.: puntero válido (≠ NULL/err) |
| 11 | 0x1f9ce | [dev-0x2d0] | runtime (campo del kgsl_device padre) |
| 12 | 0x1f9cf | [dev+0x1920]→u32 << 8 | runtime |
| 13 | 0x1f9cd | ([x+0xb8] & ~0xfff) \| 0xf | vendor-only |
| 14 | 0x1f40f GMU_SYS_BUS_CONFIG | 1 | |
| 15 | 0x1f400 GMU_ICACHE_CONFIG | 1 | mainline igual (a6xx_gmu_resume) |
| 16 | 0x1f401 GMU_DCACHE_CONFIG | 1 | mainline igual |
| 17 | 0x1f841 CX_GMU_POWER_COUNTER_SELECT_0 | rmw: &=0xffffff00 \| 0x19171300 | cond. ACD ([dev+0x31a5]≠0), `kgsl_regmap_rmw` |

## 5. gen7_gmu_device_start @0x770fc — LA SUELTA DEL RESET

```
gmu_core_reset_trace_header(dev-0x1410)
(irq local save; trace gmu_ao_sync si preemptible)
write(GMU_CM3_SYSRESET = 0x1f800 ← 0)        // SUELTA DEL CM3
dsb(st)
timed_poll_check(0x1f81c GMU_CM3_FW_INIT_RESULT, val 0x100, mask 0x1ff, 100 iter)
  ok → return 0
  fail → dev_err + gmu_core_fault_snapshot + -ETIMEDOUT (-110)
```

**No hay SYSRESET=1 previo en el path de boot**: el CM3 sale de power-up ya en reset
(la GDSC/clocks lo aseguran) y el vendor simplemente escribe **0** una vez. Tampoco
hay escritura a `GMU_CM3_FW_BUSY` (0x1f81a) ni a `GMU_BOOT_SLUMBER_OPTION`.

---
*(bloque 1/2 — sigue: comparación con mainline a6xx_gmu.c, pm_resume y clks)*

## 6. Comparación con nuestro mainline (k52-tree a6xx_gmu.c)

Flujo mainline: `a6xx_gmu_resume` (rpm_get, gxpd_get, clk_set_rate core/hub,
clk_bulk_prepare_enable, secure_init, set_initial_bw, AO_IRQ clr/mask, cold/warm) →
`a6xx_gmu_fw_start` (CX_FAL[ NEXT_]INTF=1, CX_MISC_TCM_RET_CNTL=1 vía secure,
`a6xx_rpmh_start`, fw_load, FW_INIT_RESULT=0, BOOT_CONFIG=0x2, HFI_QTBL,
AHB_FENCE_RANGE_0, CM3_CFG=0x4052, chipid, GBIF_CX, power_config) →
`a6xx_gmu_start` (lecturas K44/K58/K63, SYSRESET=1 ×2+wmb, …, SYSRESET=0, poll).

**Lo que AMBOS hacen** (la columna común está bien):
CX-GDSC on; clocks bulk on; fw a ventanas ITCM 0x1b400 / DTCM 0x1c400 (con `dsb`);
FW_INIT_RESULT=0; BOOT_CONFIG=0x2; CM3_CFG=0x4052; ICACHE/DCACHE/SYS_BUS_CONFIG=1;
wake RSCC (REQ=BIT(1)→poll ACK→REQ=0); SYSRESET=0 único + dsb + poll FW_INIT_RESULT.

**Diferencias TOP (vendor hace, nuestro árbol NO):**

| # | Vendor (gen7) | Nuestro k52 | Riesgo |
|---|---|---|---|
| 1 | `register_config` escribe **8 registros que mainline no nombra ni toca**: 0x1f8f0=1, 0x1f8f1=1 (lo PRIMERO), 0x1f984=1, 0x1f985=runtime, 0x1f9cd/d0=(x&~0xfff)\|0xf, 0x1f9ce=[kgsl_dev], 0x1f9cf=[dev+0x1920]<<8, y **base GMU+0 ← 0x3c45** | nada (no existen en a6xx_gmu.xml) | alto: config del anillo de reloj/pwr del GMU que el fw puede exigir |
| 2 | **RSCC aperture secreta**: RSCC 0x02003b11 ← 0x80c808a0 dentro de register_config (antes del reset) | `a6xx_rpmh_start`/`rpmh_init` solo tocan GMU_RSCC_CONTROL_REQ/ACK (0x23b07/8) y RSCC_SEQ; sin desbloqueo de aperture | medio-alto: sin el unlock, las escrituras RSCC/RPMh del vendor path no equivalentes |
| 3 | **Ningún SYSRESET=1 en el boot path** y **cero lecturas MMIO entre cfg y rst0**: BOOT on→clks→RSCC wake→fw bulk→17 writes→IRQ en→[dev+0x2f4c]=0, dmb ishst→SYSRESET=0 | `a6xx_gmu_start` aserta SYSRESET=1 DOS veces + wmb, y entre medias hace ~20 lecturas (DTCM+0xff7/f8 stale, ITCM, K44 A–E, fence) y una lectura **secure CX_MISC (TCM_RET_CNTL)** — todo con el GMU entre relojes | alto: las lecturas K44/K63 previas al rst0 (y el cx_misc_read) tocan ventanas GMU justo antes del reset; el vendor no lee NADA |

Notas adicionales: (a) el criterio de éxito del poll difiere: vendor `FW_INIT_RESULT &
0x1ff == 0x100` (bit 8), mainline stock `== 0xbabeface` (k52 fija mask 0xffffffff);
(b) el vendor programa HFI_QTBL/fences DESPUÉS de que el CM3 corre
(`gen7_gmu_hfi_start`), mainline ANTES de soltar el reset; (c) el vendor repite el
wake RSCC en cada boot con flag-guard ([dev-0x2c0] bit3), mainline lo hace en
fw_start cada vez también (a6xx_rpmh_start) pero con poll adicional de
RSCC_SEQ_BUSY_DRV0; (d) vendor usa `usleep_range(26,100)`+yield en espera activa
acotada a 100 ms (ktime) sobre el estado del gestor de clks/reguladores.

## 7. Secuencia vendor pre-SYSRESET, condensada (10 líneas)

```
1. kgsl_pwrctrl_enable_cx_gdsc              (regulador CX)
2. gen7_gmu_enable_clks(0)                  (clk_bulk prepare+enable)
3. gen7_enable_ahb_timeout_detection + gen7_cx_timer_init
4. gen7_rscc_wakeup_sequence: RSCC 0x02003b07←2, dsb, poll 0x02003b08&2,
   espera activa ≤100 ms, RSCC 0x02003b07←0
5. gen7_gmu_load_fw: bloques del gmu.bin → ITCM(0x1b400)/DTCM(0x1c400), dsb st
6. register_config: 0x1f8f0=1, 0x1f8f1=1, FW_INIT_RESULT(0x1f81c)=0,
   BOOT_CONFIG(0x1f801)=2, 0x1f985/0x1f984=rt/1, RSCC 0x02003b11←0x80c808a0,
   CM3_CFG(0x1f82d)=0x4052, base←0x3c45, 0x1f9cd..d0=rt, SYS_BUS(0x1f40f)=1,
   ICACHE(0x1f400)=1, DCACHE(0x1f401)=1, [ACD] 0x1f841 rmw ←0x191713xx
7. gen7_gmu_irq_enable
8. [dev+0x2f4c]=0 ; dmb ishst
9. GMU_CM3_SYSRESET (0x1f800) ← 0          // SUELTA, sin asertar antes
10. dsb st ; poll FW_INIT_RESULT (0x1f81c) hasta (val&0x1ff)==0x100, 100 iter;
    fail → dev_err + gmu_core_fault_snapshot + -ETIMEDOUT
```

**Hipótesis accionable para el port**: entre nuestras sondas K44/K63 (lecturas DTCM/
ITCM/fence/cx_misc secure) y el double-assert SYSRESET=1 existe una ventana MMIO que
el vendor no tiene; y el vendor configura 8 registros vendor-only (0x1f8f0/f1,
0x1f984/5, 0x1f9cd–d0, base=0x3c45) + el unlock RSCC 0x3b11←0x80c808a0 que nosotros
no escribimos nunca. Siguiente experimento natural: réplica exacta de register_config
(sin lecturas intermedias, sin rst1) con el stub K63 como discriminador.

*fuentes: /var/tmp/kgsl.asm (llvm-objdump completo), symtab de msm_kgsl.ko,
 funciones @0x7c594 (boot), 0x775d0 (load_fw), 0x7730c (rscc), 0x78324 (register_config),
 0x770fc (device_start), 0x796a0 (enable_clks); relocations en /var/tmp/kgsl.rela.*

## 8. Respuesta final: la ventana rst1→rst0 y los vendor-only

**Rectificación (importante)**: la fila 7 de §4 NO es vendor-only. El XML define
GMU_AO_AHB_FENCE_CTRL=0x23b10, luego **0x02003b11 ≡ GMU_AO_AHB_FENCE_RANGE_0**, y
0x80c808a0 = BIT(31)|0x32<<18|0x8a0 — exactamente el valor que nuestro fw_start
escribe en REG_A6XX_GMU_AHB_FENCE_RANGE_0 para A7xx. Ambos lo escriben pre-reset;
esa diferencia desaparece. Vendor-only reales: 0x1f8f0/f1, 0x1f984/5, 0x1f9cd–d0
(8) y base GMU+0←0x3c45.

**¿Matan las ~20 lecturas de la ventana rst1→rst0? No como causa primaria, por la
propia evidencia del port**: la baliza K63 (0x01141516) dice que el CM3 ARRANCA,
pasa los polls de cache-ops y muere DESPUÉS, en el fetch SMMU de 0x4000; todas las
lecturas K44/K63 completaron e imprimieron (la máquina vivió hasta S3-rst0), y con
rst1=1 (que XBL ya trae asertado en cold boot; nuestro rst1 extra es no-op) el CM3
no puede fetch-ear mientras leemos — las ventanas ITCM/DTCM responden en reset (el
propio vendor las ESCRIBE ahí). Sí son riesgo real en dos casos que no es éste:
re-probes donde un rst0 previo dejó al CM3 fetch-eando (para eso existe el re-assert
K56 B) y lecturas fuera de la ventana concedida (precedente K57: abort 96000010).
La muerte en el fetch SMMU apunta a lo que el CM3 encuentra al despertar (mapeo
SMMU SID/fitzas del icache), no al ruido de lectura previo.

**¿Qué vendor-only replicar primero? 0x1f8f0=1 y 0x1f8f1=1**, por tres razones:
son las dos PRIMERAS escrituras del register_config (posición prominente = config
de wake/keep que el fw asume heredada), son constantes (no dependen de los campos
runtime del kgsl_device que alimentan 0x1f984/5 y 0x1f9cd–d0, inreplicables sin
medir un boot vendor), y su coste es una línea en fw_start antes de
FW_INIT_RESULT=0. Segundo experimento natural si 0x1f8f0/f1 no bastan: capturar los
valores runtime de 0x1f9cd–d0 (patrón (x&~0xfff)|0xf = base|0xf, parece una base de
rango AHB) con un print nuestro en el mismo punto, y replicar 0x1f984/5 con el
0x1f985 enlazado al campo [x+0xb8] que aun no hemos identificado.
