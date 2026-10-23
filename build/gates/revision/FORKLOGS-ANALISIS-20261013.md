# FORKLOGS de rescate — análisis (13-oct-2026, 100 % en PC)

26 ficheros de `out/rescue/` (25 numerados `forklog-<uptime>.txt` + `forklog.txt`
rolling). Volcados del ukeinit a la partición rescue, un snapshot de `dmesg` cada
~15 s + secciones USB/particiones/reguladores. Todos con nomenclatura LEGACY
(`forklog-<t>.txt`, sin `boot-id`): los escribió el ukeinit pre-L33; el
`dump-log.sh` con namespacing por boot (`build/init/dump-log.sh:15-19`) no
generó ninguno de estos.

**Método de atribución** (triple candado por fichero): banner
`Linux version … #N … DATE` + rutas de árbol embebidas en los `WARNING`
(`../<tree>/drivers/…`, visibles solo cuando el boot emite WARNs) + cmdline
uke comparada byte a byte contra los `boot-uke-*.img` de `build/bootimg/`
(verificado por sha contra el ledger cuando aplica). Ojo: todos los kernels
k52L12+ llevan la fecha **congelada** (`SOURCE_DATE_EPOCH` → `Fri Oct 10
12:00:00`); solo `#N` (contador `.version`) y el árbol distinguen.

## 1. Tabla

| Fichero(s) | Atribución | Firma de muerte | Novedad |
|---|---|---|---|
| `forklog-1342.txt` | **k56** (`boot-uke-k56-cm3dbg.img`, `#7 Wed Oct 7 02:30:57`, verificado por banner en imagen de disco). Boot `mtdoops.boot_index=979`. Sesión 7-oct, ledger hermano #539 | **NO hay muerte**: snapshot en vivo (t=1342, dmesg hasta 1330.25). Cola = spam `X9UFS-CLK …_phy_clk=1000` (reloj UFS, sistema vivo). Contiene el Oops no-fatal de `uke_k19_dump_kgsl+0x3f4` (`synchronous external abort 0x96000010` @4.06 s, el probe del GMU muere pero el kernel sigue) + 3 WARN benignos (clk-rcg2 `disp_cc_mdss_mdp_clk_src`, `iommu_set_fault_handler` ×2) | NO (réplica de #539; ese ledger ya cosechó este mismo Oops) |
| `forklog-1345…1601.txt` (18 ficheros) + `forklog-1631…1691.txt` (5 ficheros) | **k56**, mismo banner/cmdline (`msm.uke_smmu_dump=1` + `video=DSI-1:d` + `UKE-K56` + `fw-map icache` + `hub=200000000` + `boot=COLD`, todo como en #539). Boot `boot_index=978`, `pureason=0x80110`. **Mismo arranque los 23**: el dmesg crece monótono (2318→2901 líneas, last_ts = t−2…13 s) | Idem: **cero muertes**, 23 snapshots de un boot en shell initramfs que vivió ≥1691 s (~28 min). Últimas líneas siempre el spam UFS. Sin `panic`, sin `Call trace` terminal, sin hung | NO |
| `forklog-1616.txt` | **L40** — candado triple: (1) banner `#2` congelado; el único `#2` del árbol k52L39-tree en disco es `boot-uke-k52L40.img`; (2) rutas `../k52L39-tree/` en sus WARNINGs; (3) cmdline uke **567 B byte-idéntica** a la imagen (`…s3_stage=3 …rescue=1 …probe_hold_ms=5000 …skip_mdss_reset=1`, sin `video=`, sin `systemd.mask`; sha imagen `100fe160…` = ledger #R4). L35 excluido (`systemd.mask`), L31/L32 excluidos (`video=:e`), L39/L39b/L39d excluidos (`#1`), L41/L42 excluidos (`#3/#4`) | **Muerte no observada / congelamiento**: vive hasta 1616.46 s y se corta en `EXT4-fs error (sda32): group 13/9/6, block bitmap and bg descriptor inconsistent` + `UKE-DIAG: vigilante lanzado (pid 8502)` + `X9S123-SWITCH t=1616 raiz=/dev/sda32` (switch_root sobre un rootfs corrupto). Sin pánico ni Oops al final. **Nunca hubo modeset**: cero líneas `K47-*-mset/crtc-en/host-xfer/cmd#0` en 1616 s (solo `K47-pan-probe` @0.5 s); `/dev/dri/card*` jamás existió (`dpu_kms_mmu_init failed: -19` @56.84 s, ver §2) | **SÍ** (ver §2: Oops @56 s + boot-L40-longevo-sin-card contrasta con HALLAZGO) |
| `forklog.txt` (rolling, t=254) | **L17-chipidB** — banner `#1` congelado + árbol `../k52-L16-tree/` en sus WARNINGs + cmdline uke **580 B byte-idéntica** a `boot-uke-k52L17-chipidB.img` (`video=DSI-1:d` + k64 completa con `s3_stage=3/rescue/probe_hold`, sin `skip_mdss`). Ledger #586 (11-oct). Excluidos: L16 (cmdline 370 B en imagen), L15 (árbol k52-L15-tree), L18/L19 (tienen `card1` viva según #588/#589; aquí no hay card), L21 (cero líneas wifi/ath11k/pwrseq) | Snapshot en vivo (dmesg hasta 242.05 s, spam UFS). Sin muerte | **SÍ parcial** (mismo Oops @56 s que 1616, en otro árbol) |

Notas de atribución:
- `1342` vs `1345…`: distinto boot (`boot_index` 979 vs 978, `build_adc` 51239 vs
  51244, `pureason` 0x80011 vs 0x80110). El rescate conserva 25 ficheros por el
  podado legacy (los 25 uptimes más altos): 24 del k56 (el boot 978 llegó a 1691 s
  y tapa casi todo) + 1 del L40 (1616) + el rolling. Ningún boot posterior a L40
  escribió aquí (L19 del 13-oct monta `sda30`, pero el rescue real es `sdb30` —
  ledger #615; por eso `forklog.txt` sigue siendo L17B del 11-oct).
- `android-kmsg.txt` (2 MB, era Android/Xiaomi) **NO existe en este repo**
  (`find` exhaustivo en `out/` y en todo el árbol, 13-oct). El ledger #615 dice
  haberlo copiado, pero en la misma entrada documenta que el enlace NCM
  **se clavó durante un scp lento** — la copia probablemente no llegó o cayó en
  otro path. **No se puede hacer el grep `dsi/sde/o82` pedido**: queda como
  re-cosecha pendiente, no como análisis.

## 2. Lo que SÍ aportan (nuevo)

1. **Oops @~56 s `dpu_kms_mmu_init failed: -19` → `drm_atomic_private_obj_fini+0x2c`
   poison-deref (`0xdead…`, `FSC level 0 translation fault`, `pc` idéntico en
   ambos ficheros: `forklog.txt:2027`, `forklog-1616.txt:2038-2065`).** Secuencia:
   `msm_drm_bind` @0.32 s → `dpu_kms_hw_init` @56.8 s → mmu_init −ENODEV → el
   unwind `dpu_kms_destroy` pisa memoria poison → Oops no-fatal en kworker, el
   sistema vive. Aparece en **dos árboles distintos** (k52-L16-tree y
   k52L39-tree): el path de error de `msm_drm_init` está roto en ambos y el
   dominio display nunca se attacha en estos boots. **No está en ningún ACM**
   (`acm-L40b/L41b/L42`: 0 Oops; `acm-L19`: 1 Oops distinto @493 s,
   permission-fault `8600000f`) **ni en ningún HALLAZGO/VEREDICTO** (grep
   `Oops` vacío en los 5): los boots de octubre-13 documentados mueren a
   ~20 s y **no podían llegar a 56 s**. Hallazgo menor pero genuinamente nuevo.
2. **L40 longevo sin card (1616) vs L40 muerto en el commit (HALLAZGO-MUERTE-DSI,
   7× @~20 s `host-xfer`).** Mismo kernel, dos destinos: si `card*` no nace
   (mmu_init −19 sin reintento con éxito), no hay quien haga modeset y el
   sistema vive 27 min en userspace (NCM `S119` @3.6 s, UFS, reguladores);
   si la card nace, el primer DCS (`cmd#0`) lo mata. Delimita la muerte de L40
   al **path de commit**, no al kernel en abstracto. El dtbo o el orden de
   probe (s275-r2 vs s283) decide qué rama toca — pista para el peldaño 6.
3. **Cierre arqueológico del k56**: los 24 ficheros confirman #539 con dmesg
   completo (tablas SME/S2CR del dump, `UKE-K32/K38/K39`, `uke_smmu_dump`),
   y `1342` documenta un **segundo boot k56** (979) con la misma firma. Nada
   nuevo, pero deja el inventario sin huecos.

## 3. Lo que NO aportan

- **Nada de L39.** L39 murió a <3,5 s con ACM 0 B (`L39-RESULTADO §2`); el
  volcador escribe desde ~15 s. Ningún forklog es L39 (todos los banners son
  k56/L17B/L40). El peldaño 0 para L39 sigue vacío por este canal — como ya
  predice el ledger hermano (`#539b`: «el forklog de 15 s jamás pudo volcar
  un boot muerto a 4,1 s»).
- **Nada de la fase sin log** (`w4-done` → muerte). El k56 es anterior a la
  instrumentación K47-DSI; el L40-1616 nunca hizo commit; el L17B lleva
  `video=DSI-1:d` (force-off). Ninguno cubre reset→DCS→corte.
- **pstore/X9PREV vacíos en los 27 ficheros**: `X9PREV: zona no valida
  (PREV:sig=140039da sz=0 …)` en todos (p. ej. `1616:312`, `1345:312`,
  `forklog.txt:313`). El power-cycle borra la DRAM, como ya sentenció
  `INV-PERSIST-20261008`. Cero pánicos persistidos.
- **Sin pánicos terminales en ningún fichero**: las únicas trazas son WARNs
  benignos ya conocidos (clk-rcg2 `mdss_mdp_clk_src`, `iommu_set_fault_handler`
  ×2 en el bind) y los dos Oops no-fatales de arriba.
- **`android-kmsg.txt` ausente** (ver §1): sin comparativa display Android
  (`dsi/sde/o82`) posible.

## 4. Conclusiones (5 líneas)

1. Los 25 numerados son 24 snapshots del **k56** (7-oct, boots 978/979, vivos,
   firma K19 ya cosechada en #539) + 1 del **L40** (1616 s, veredicto abajo).
2. `forklog.txt` es el **L17-chipidB** (11-oct, cmdline 580 B byte-idéntica);
   sobrevive porque L19 (13-oct) monta el rescue equivocado (`sda30` vs `sdb30`).
3. Lo único nuevo: el **Oops @~56 s del unwind de `msm_drm_init`** (poison-deref
   tras `dpu_kms_mmu_init −19`), en dos árboles, ausente de todos los ACM.
4. El L40-1616 vivió 27 min **porque jamás tuvo card** (sin modeset posible),
   acotando su muerte documentada al path de commit — el dtbo/probe decide.
5. **Ni L39 ni la ventana `w4-done`→muerte están aquí ni pueden estar** (muerte
   <15 s < período del volcador); `android-kmsg.txt` no llegó al PC (re-cosechar).
