# CRITICA-W6-VIAS — lo NO intentado (2026-10-09, solo PC + SSH-lectura)

> Testbed VIVO verificado por SSH 9-oct ~02:34 (k52b2+s273, `7.2.0-rc2-palawan aarch64`, up 3 min).
> Tablet en fastboot; PROHIBIDO flashear/tocarla. Todo lo de abajo es 0 flashes salvo §2.
> Base: k65/k66/k67 en silencio idéntico (D3 y D2 exonerados), D1 sospechoso nº1,
> k68=D2-solo compilando (W5: `k68-build/Image` 41490944 B, 6× `UKE-K68`),
> plan-C = enables diferidos tras USB (solo diseñado, W4-K68 §4).

## 0. Dato nuevo que reordena todo (SSH de hoy, no estaba en ningún informe)

| Medida (solo lectura) | Valor | Qué significa |
|---|---|---|
| `clk_summary` GPU heredado XBL | `gpu_cc_gmu_clk_src=38.4M` (en=0), `gpu_cc_hub_clk_src=38.4M` (en=2, lo vota `kgsl-smmu`), `gpu_cc_pll1=880M` apagado, `gcc_gpll0=1200M` → `usb master=400M` | D1 (220M) y D2 (200M) son un salto **5×** sobre 38.4M, no sobre 19.2M. El hub_src ya lo sostiene la SMMU a 38.4M: D2 lo reprograma en vivo bajo los pies de otro consumidor |
| `regulator_summary` | **Sin `pmxr2230_s4`/`gfxlvl`**: el rail GX no existe en nuestro DT | El voto GX es huérfano por construcción; `gfx.mol=0x38` del cmd-db no tiene regulador que lo ejecute |
| DT vivo GMU (`/proc/device-tree/soc/qcom,gmu@3d69000/reg-names`) | `gmu gmu_pdc gmu_ao_blk_dec0 rscc` — **sin `rdpm_cx`/`rdpm_mx`** | El mailbox de voltaje del vendor no tiene dónde mapearse |
| Fuente k52 + Image k68 | `grep -rn rdpm drivers/gpu/drm/msm/` = vacío; `strings Image | grep rdpm_cx_virt|rdpm_cx_freq|gen7_rdpm` = vacío | El driver RDPM está **ausente** en fuente y binario (los únicos hits `qhs_*_rdpm` son nombres de nodos ICC del DT, no driver) |
| Vendor (clon OP, verificado) | `adreno_gen7.c:876 GEN7_RDPM_CX_OFFSET 0xf14`, `:893-894 writel(freq/1000, rdpm_cx_virt+0xf14)`; `adreno_gen7_gmu.c:1868 RDPM-primero, :1870 set gmu, :1878 set hub, :1885 enable`; `gen7_gmu_boot :2005 CX_GDSC → :2009 enable_clks → rscc → fw → register → device_start → hfi` | El voto CX real del vendor es el writel RDPM **antes** de set_rate+enable. Nuestro D3 (`opp_set_rate` sobre GDSC sin `set_performance_state`, W3-K66 §1a) era un no-op que ni siquiera imitaba esto |
| s269 GPU | `s269.dts:15146 interconnects;` (vacía) + `gfx-mem` fantasma; `interconnect_summary` vivo sin nodo gpu/gfx | Sin voto DDR/CNOC por diseño s269; el vendor lleva `gpu_icc_path` + bus-tables ddr/cnoc (`cliffs-gpu.dtsi:38-49`) |
| `msm_kgsl.ko` (símbolos, sin desensamblar aún) | `gen7_rdpm_cx_freq_update T 0x74660`, `gen7_gmu_enable_clks T 0x796a0`, `gen7_gmu_boot t 0x7c594`, `kgsl_icc_set_tag T`, `H2F_MSG_GX_BW_PERF_VOTE` en strings | La secuencia enable + votos GPU-device + ICC vive en el .ko y nadie la ha desensamblado |
| ramoops | `dmesg`: `ramoops 0x400000@0xa7000000`, `console [ramoops-1] enabled`, `pstore backend registered` — pero `/sys/fs/pstore/` **vacío**, `X9COLD: 0 ficheros`, `block2mtd: cannot open /dev/block/by-name/oops` (no existe `by-name` en este rootfs) | El backend funciona; el canal muere por (a) nadie monta pstore en el boot que muere, (b) power-cycle frío pisa 0xa7000000, (c) `mtdoops.boot_index=1007` en cmdline sin `/dev/mtd*` que lo consuma |
| `pm_genpd_summary` | No existe (sin `CONFIG_PM_DEBUG`) | Los GDSC no se leen por ahí; sí por suppliers sysfs (`3d99034 GX + 3d9908c CX` ya linkados al GMU) |
| gpio-leds | `grep gpio-leds stock2 = 0 hits` | Testigo LED por DT descartado; no hay LED reclamable sin parche DT |

## 1. Experimento más barato (0 flashes) con más información: E0 "el voto que falta"

Hipótesis a matar: D1/D2 suben relojes 5× **sin el voto de voltaje que el vendor hace primero**,
porque ese voto (RDPM) no existe en nuestro mundo. Si se confirma, el asesino no es
"qué rate" (K64) sino "rate sin voltaje" (enable-path), y k68/plan-C se reinterpretan (ver §2).

Tres comandos, todos lectura, ~10 min totales:

```bash
# E0a (SSH, DT vivo): ¿existe la región rdpm donde mapear el voto?
SSH="ssh -i build/rootfs/uke-arch-root -o StrictHostKeyChecking=no root@192.168.42.129"
$SSH "cat /proc/device-tree/soc/qcom,gmu@3d69000/reg-names | tr '\0' ' '; echo; grep -E 'gpu_cc_(cx_gmu|hub)' /sys/kernel/debug/clk/clk_summary"
# Esperado (ya medido hoy): "gmu gmu_pdc gmu_ao_blk_dec0 rscc" + 38.4M/38.4M. Cierra: sin región no hay RDPM posible sin parche DT.

# E0b (PC, fuente): ¿el driver sabe votar por RDPM?
grep -rn "rdpm\|RDPM" build/kernel-pokes/k52-tree/drivers/gpu/drm/msm/ | head
# Esperado (ya medido): vacío. Cierra: mainline-palawan no tiene el concepto.

# E0c (PC, binario k68 ya compilado): ¿el experimento que va a volar lleva el voto?
strings build/kernel-pokes/k68-build/arch/arm64/boot/Image | grep -E "rdpm_cx_virt|rdpm_cx_freq|gen7_rdpm" | head
# Esperado (ya medido): vacío. Cierra: k68 repite D1/D2 "a pelo", igual que k65/k66/k67.
```

Veredicto E0 (anticipado por las medidas de hoy, pendiente solo de dejarlo protocolizado):
**RDPM ausente en DT + fuente + k68**. Entonces el orden vendor
(`RDPM(freq/1000)` → `set_rate` → `enable`, `adreno_gen7_gmu.c:1868-1885`)
es imposible en k65/k66/k67/k68: todos hacen `set_rate` → `enable` sin voto previo.
El silencio idéntico al quitar D3 (no-op) y D2 deja de ser misterio:
**quitar un no-op o una de dos subidas sin voltaje no cambia el resultado**.
K64 (enable-path) pasa a sospechoso nº1 por encima de D1.

Segundo barato gratis (E0d, SSH, 2 min): dejar constancia del suelo XBL —
`gpu_cc_gmu_clk_src/hub_clk_src = 38.4M` ya capturado — para que el futuro
plan-C sepa desde dónde salta (5.2× a 200M, 5.7× a 220M).

## 2. Un solo flash mañana: k68, no plan-C

Recomendación: **flashear k68 (D2-solo)**. No porque D2 importe (exonerado por k67),
sino porque es el discriminador que decide si plan-C es necesario, con el diff más
pequeño y ya compilado.

Lectura del árbol tras k67-silencio:

- k68 **habla** (USB/H3/S3) ⇒ D1-solo mata, D2-solo vive ⇒ **D1 condenado**
  (PLL1 dedicado / core 220M sin voltaje). El fix es D1-pequeño (voto RDPM + PLL1),
  plan-C sobra.
- k68 **calla igual** ⇒ ningún rate por separado mata ⇒ el asesino es el
  **enable-path común** (`clk_bulk_prepare_enable` levantando padres XBL a 38.4M
  + AHB/GMU a 200/220M sin CX, con el hub_src sostenido por kgsl-smmu) o la
  combinación. Plan-C queda **justificado con evidencia**, no por intuición.

Coste de estar equivocado en cada rama:

| Rama | Si sale mal (sigue el silencio) | Qué se aprende | Deuda que deja |
|---|---|---|---|
| **k68** (diff = 1 variable vs k67: D1 fuera; build listo W5) | 1 flash + 1 revival k52b2 | Prueba de eliminación completa: ni D1 ni D2 por separado ⇒ enable-path. Plan-C pasa de hipótesis a necesidad | Mínima: el revival es receta conocida (`boot-uke-k52b2-bateria.img` `18c749ea…`), slot B intacto retry 6 |
| **plan-C primero** (diff grande y sin compilar: workqueue tras USB/ACM + rates + poll; depende de que USB viva para diferir) | 1 flash + 1 revival igual, pero el silencio es **ambiguo**: ¿falló el rate o falló la lógica de diferido (race HFI/poll, GDSC dormido, ACM que nunca llega porque el enable temprano ya mató)? | Poco: habría que correr k68 de todos modos para desambiguar | Máxima: un path async nuevo sin test, más variables, y si habla tampoco dice qué rate era el problema (el fix mínimo se pierde) |

Añadido: plan-C sin E0 es disparar a ciegas; plan-C **con** E0 se diseña mejor
(diferir no solo el enable sino precederlo del voto que falta, §3-L2).
Orden: k68 → (si calla) plan-C con RDPM incluido. Saltarse k68 no ahorra un flash,
lo encarece: convierte 1 flash discriminante en 2–3 flashes ambiguos.

## 3. Vía lateral ignorada (todo 0 flashes, PC + SSH-lectura)

Nada de esto se ha mirado y todo vive ya en disco:

- **L1 — el .ko aún no está exprimido** (solo se sacó la secuencia register_config).
  Símbolos con dirección conocida: `gen7_gmu_enable_clks 0x796a0`,
  `gen7_rdpm_cx_freq_update 0x74660`, `gen7_gmu_boot 0x7c594`,
  `kgsl_icc_set_tag`, `build_rpmh_bw_votes`, `H2F_MSG_GX_BW_PERF_VOTE`.
  Lo no mirado: desensamblar `enable_clks` (orden RDPM→rates→enable en binario),
  `build_rpmh_bw_votes` (tablas ddr/cnoc que s269 dejó vacías) y el origen
  runtime de `0x1f985/0x1f9cd-d0` (filas INV-KGSL-RE §4 que k64 puso a `0xf`).
  Comando: `objdump -d --disassemble-symbols=gen7_gmu_enable_clks,gen7_rdpm_cx_freq_update
  build/evidencia/kgsl-vendor/msm_kgsl.ko` + `strings -t x` para los pools.
  6–16 h PC, 0 tablet. Prioridad ALTA: dice **qué escribir** antes del enable,
  no solo qué rate pedir.
- **L2 — clones vendor a medio leer.** Leídos: freq-table (220M/550M),
  pwrlevels (9 niveles idénticos), `enable_clks`/`boot`/`rdpm_probe`
  (`gen7_gmu_rdpm_probe :2411-2425` mapea resources `rdpm_cx`/`rdpm_mx` del DT).
  NO leídos: `adreno_gen7_rpmh.c` (cómo se construye el voto CX desde freqs),
  `cliffs-gpu.dtsi:38-49` (bus-tables ddr/cnoc + `gpu_icc_path`, huérfanas en s269),
  `gpucc-cliffs.c:446-457` (`hlos1_vote_gpu_smmu`, encendido en probe `:627-628`),
  votos del device GPU (`gen7_hfi_send_gpu_perf_table`, msg 30 GX_BW_PERF_VOTE —
  el `beginVoteGxOn (0,3)/(0,5)` del fw necesita su contraparte host y nadie la ha
  comparado). Todo 0 flashes; el RDPM es el delta D4-bis que FASE2 §5 no tabuló.
- **L3 — Android vivo / super.img.** El slot con Android no es accesible hoy
  (B = imagen vieja retry 6, no tocar). Pero `super.img` **sí es legible sin
  flashear** desde el Linux vivo por GPT, solo que nadie lo ha intentado porque
  este rootfs no trae `by-name`: lectura pura
  `ls /dev/sd*; gdisk -l /dev/sda` → localizar `super` → `dd if=/dev/sdaN bs=1M
  count=1 | file -` → volcado por trozos a `build/evidencia/` con shas al ledger.
  De ahí saldrían el `msm_kgsl.ko` de esta build exacta y las tablas ICC reales.
  0 flashes, riesgo ~0 (solo `dd` lectura). El golden-state que falta
  (rates+corners con GPU viva) sigue pendiente de ventana con dueño, pero el
  volcado frío no la necesita.

## 4. Atajo para ver la consola pre-USB sin USB

Estado real del canal (SSH hoy): el hardware del canal **funciona**
(ramoops `0x400000@0xa7000000` + `console [ramoops-1] enabled` + backend
registrado), pero la cadena de custodia está rota en tres puntos, todos
arreglables sin hardware:

- **A1 — pstore con boot_index (0 flashes, hoy mismo).** En el testbed vivo:
  `mount -t pstore pstore /sys/fs/pstore; ls -la /sys/fs/pstore/; tail -c 40000
  /sys/fs/pstore/*`. Si sale vacío confirma lo esperado (power-cycle frío de
  k67 pisó `0xa7000000`, INV-PERSIST): el valor no es rescatar k67 sino
  **validar el lector** para el próximo flash. Coste 0, 5 min.
- **A2 — mtdoops/block2mtd roto (diseño en PC, viaja en el próximo flash).**
  `block2mtd: cannot open /dev/block/by-name/oops` (3.62 s) porque no existe
  `by-name`; `mtdoops.boot_index=1007` va en cmdline pero no hay `/dev/mtd*`.
  Fix: resolver la partición `oops` por GPT (`gdisk -l`, lectura) y enseñarle a
  `ukeinit` el `/dev/sdaN` real + `mount -t pstore` temprano + volcador cada 5 s.
  Nada de esto requiere tocar la tablet hoy; el parche viaja gratis dentro del
  próximo bootimg (k68 o plan-C).
- **A3 — ramoops en zona no pisada: solo sobrevive al reset caliente.**
  Power-cycle (botones) = XBL pisa la zona, fin. Reset por WDT (`qcom_wdt` a 12 s,
  ya en k62b) = caliente, preserva. El WDT no resucitó en k62b porque el freeze
  es APSS-global (refutado como *rescate*), pero sigue válido como *preservador*:
  el próximo flash debe morder por WDT, no por botones, y el revival leer pstore
  **antes** de cualquier power-cycle. Procedimiento, no parche.
- **A4 — LED/gpio como testigo: descartado.** Sin `gpio-leds` en stock (grep 0
  hits); un poke TLMM directo por ioremap es MMIO en dominio vivo con DT que no
  lo reclama — riesgo sin beneficio frente a A1–A3. No gastar un flash en esto.
- **A5 — ftrace a eMMC: viable solo con plan-C.** El volcador pierde hoy por
  150 ms (GPU-on 4.03 s vs UFS 4.15 s, #549). Con enables diferidos tras USB/ACM
  la carrera desaparece (UFS ya publicó cuando el enable muere) y `uke_poke` +
  `H3-clkFAIL` + `CM3DBG` llegan a `sda30`. Sin plan-C no hay ftrace que valga;
  con plan-C sale gratis.

## 5. Ranking por información / euro-flash

1. **E0 (RDPM ausente)** — 0 flashes, ~10 min. Decide si el marco D1/D2 sigue
   vivo o si el asesino es el enable-path sin voltaje. Multiplica el valor de
   todos los flashes siguientes.
2. **L1 (desensamblar enable_clks + votos del .ko)** — 0 flashes, 6–16 h PC.
   Dice qué escribir (RDPM offset `0xf14`, bus-tables, GX_BW vote), no qué rate.
3. **k68 (único flash)** — 1 flash + revival conocido. Discriminador D1 vs
   enable-path (§2). Sin sustituto.
4. **A1+A2 (pstore/mtdoops operativos)** — 0 flashes hoy + viajan en el próximo
   bootimg. Convierten el próximo silencio en autopsia en vez de misterio.
5. **L2 (rpmh tables + ICC + hlos1 del vendor)** — 0 flashes. Diseño del voto
   que plan-C deberá llevar.
6. **L3 (volcado frío de super.img por GPT-lectura)** — 0 flashes. Tablas y .ko
   de la build exacta; el golden-state con GPU viva sigue necesitando dueño.
7. **plan-C (enables diferidos + voto RDPM)** — 1 flash, solo si k68 calla.
   Sin k68 previo es ambiguo y más caro (§2).
8. **A5 (ftrace a eMMC)** — gratis dentro de plan-C; inútil sin él.
9. **A4 (LED/gpio), emulación AOP, Trace32** — descartados (sin DT / 300–1000 h /
   10–25 k€ con DAP bloqueado; #552 sigue vigente).

## 6. Bitácora de esta crítica (solo lectura)

- SSH testbed (`uke-arch-root`, `192.168.42.129`): `clk_summary` (38.4M/38.4M,
  pll1 880M off, gpll0 1200M→usb 400M), `regulator_summary` (sin s4),
  `/proc/device-tree/.../reg-names` (sin rdpm), `/sys/kernel/debug/cmd-db`
  (fichero, `gfx.mol=0x38`), `interconnect_summary` (sin gpu), `dmesg`
  (ramoops ok, pstore vacío, block2mtd falla, boot_index=1007). Cero escrituras,
  cero reboots.
- PC: `grep rdpm k52-tree` vacío; `strings k68-Image` sin driver RDPM;
  `s269.dts:15146 interconnects;` vacía; vendor `adreno_gen7.c:875-894`,
  `adreno_gen7_gmu.c:1862-1894/1997-2060/2411-2425`, `nm msm_kgsl.ko`
  (`rdpm_cx 0x74660`, `enable_clks 0x796a0`). Tablet no tocada.
