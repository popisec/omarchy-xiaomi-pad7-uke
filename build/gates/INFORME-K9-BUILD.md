# INFORME-K9-BUILD — kernel K9 = K8 + `uke_write_mask` (silencio de escrituras por defecto) + migas delante de CADA escritura + guardas de CB + `boot-ukek9.img`

Fecha: 2026-09-29 (tarde). Autor: agente constructor K9. **Trabajo sin tablet** (prohibido fastboot/adb/ssh/ttyACM0).
Pliego de cargas: `build/gates/revision/C2-critica-k8.md` (huecos H1/H2/H4/H7) + `#P25` (K8 murió mudo a los 0,44 s, igual que K7)
+ `revision/R1-smmu-kseries.md` (§2.2 escrituras incondicionales, §6.a plan B1, §7.2 CB_ACTLR sin miga) + `PRE-REGISTRO-PANTALLA.md` (#P8-#P25).

Arena: `/var/tmp/uke-k9` (scripts, diff, logs, rungs), árbol `/var/tmp/uke-k9-tree` (copia de `uke-k8-tree`, **no se toca el de K8**),
build `O=/var/tmp/uke-k9-build` (copia de `uke-k8-build` con las rutas relocalizadas: build INCREMENTAL, no rebuild completo).
No hay ningún `git commit`.

---

## 0. Entregables y shas

| fichero | bytes | sha256 |
|---|---|---|
| **`build/bootimg/boot-ukek9.img`** (imagen final) | 100663296 (96 MiB) | **`f21cc35f8c64d7e71ddaf7f0fd4282b09e452e5d5f2293df786c1bfad4f14fe3`** |
| `build/gates/patches/k9-escrituras.diff` (721 líneas, 16 hunks, 4 ficheros; +497/−42) | 32513 | `48a268ab8b8962698c32dcf8495e4de01a463f103aceb08530fb7bffb03494ea` |
| `Image.gz` del build (K9) | 16576161 | `03ed849b51f0728c8ac65d0848925d370f6c73bfa5a2b82305fbede4932294be` |
| `Image` crudo del build (delta **0 B** vs K1..K8) | 41355776 | `7bb94e8629c9e3f994f8b7e4dd4b2bdc330da237ba987235e12ff001c3ed7e2b` |
| `arm-smmu.c` K9 | 144015 | `ae9f2d3402a7422a2e935a6421e332048e5d084c2fc999037209769fb5705a2c` |
| `arm-smmu.h` K9 | 20528 | `6a91d9336fc3e46b0703b7a984a3d170991bb1b7732f65e4b0306b9f59cbcc9f` |
| `arm-smmu-impl.c` K9 (K8 era idéntico a K7) | 8272 | `480063ed2a035cdcf5440b1f4e6fb322fa0495bfc200c14a9e4dd8aaeac12095` |
| `arm-smmu-qcom.c` K9 (K8 NO lo tocaba) | 36760 | `152a5b3e150ad1739512b060f282b80d39a977105dd62a0227d0ddd8ec1d5b8e` |
| cmdline de la imagen | 382 B | **== la de K7/K8 byte a byte** (leída de `boot-ukek8.img` @44) |
| base del repack (shell) | 100663296 | `e3c60969269c0b36f23a37db5b1772128891232517c8d7979bd967b88acab206` (`boot-s240-mem2g.img`) |
| referencias (`boot-ukek8.img`) | — | `5e34596a230d2d645ad8dcc68dcba5c23bc58bf2a6c6468a526a66bb687d54e2` |

**Rungs pre-empaquetados** (repack de cmdline, SIN recompilar; `repack-k9.py --wmask N --out …`). Todos: 100663296 B, kernel_size@8 = 16576161, AVB0/AVBf intactos, delta vs K8 solo kernel+cmdline.

| rung | token añadido | sha256 | dónde |
|---|---|---|---|
| **silencio total (rung 0)** | `arm_smmu.uke_write_mask=0` | `9e0ee119a9d5307cad6dea536acfb3e6b25415408c6abe8ab30cab97da3e4b07` | /var/tmp/uke-k9/ |
| **todo (control ≈ K8+migas)** | `…uke_write_mask=0xfff` | `a167aee56412a220e44cf2878d07a13c33814ed4d2bfd5155068a1b6d988ac5a` | build/bootimg/ + arena |
| reset (F4+F5+F6+F7) | `…uke_write_mask=0xf` | `fec1de325702405fd650b67c3144bbe2f9ed7ec8c200aa7857b9e5826fede4bd` | arena |
| quirk | `…uke_write_mask=0x10` | `bf68945fd96499dbfa0156950036f3ca162b869a2c12d990a256c4b9ee623b7a` | arena |
| rmr CLIENTPD | `…uke_write_mask=0x20` | `88dece0e6e0eff86c15cc087e1a665f747bc566a41ae105a979852e2f4390737` | arena |
| attach (SME+S2CR+CB) | `…uke_write_mask=0x1c0` | `c74c124416064967d5f0d0a81b706a18595b749bd627f0a74d124c4e9ebca6f2` | arena |
| A/B sin barrido | `…uke_handoff=2` | `52dff4833d131e76464995d60873082e2933322ddc9c815dc7194d6f88d5e8d2` | build/bootimg/ + arena |

Nota: el **default compilado es `uke_write_mask = 0` (silencio total)** ⇒ `boot-ukek9.img` tal cual (cmdline idéntica a K8) **ES la rung 0**.
Las rungs con token son repacks de 30 s (`python3 /var/tmp/uke-k9/repack-k9.py --wmask N --out …`), no tocan el kernel.

---

## 1. Qué hace K9 distinto de K8 (tres frases)

1. **`uke_write_mask`**: máscara de 9 GRUPOS de escritura del camino armado. **bit a 1 = el grupo se ejecuta; bit a 0 = se silencia** (miga `UKE-POKE: wmask[...]` + `pr_flush` y **no se toca el registro**). Default **0 = silencio total** (rung 0); `0xfff` es alias de "todo" (bits 9-11 no existen ⇒ `0xfff` ≡ `0x1ff`). Una sola imagen recorre toda la escalera por cmdline.
2. **Migas delante de CADA escritura del camino armado + `pr_flush` ANTES**: F4 TLBI, F5 (sCR0 leído/calculado), F6 (sACR + bucle `CB_ACTLR` con muestras CB0/CB22/CB70 y cada 16), F7 (tlb_sync + write sCR0), quirk (S2CR(109)/CB70/CBAR70), rmr (CLIENTPD) y cada `write_sme`/`install_s2cr`/`write_context_bank` del attach. Además F1 sGFSR. **Solo imprimen con el instrumento armado y el apps-smmu** (macro `UKE_K9_LOG`/`UKE_K9_FLUSH`): el arranque normal y el kgsl-smmu no ven ni una línea nueva.
3. **Guardas de CB (C2 H2)**: (a) el CB 70 (bypass del quirk/BL) **no se escribe por NINGÚN camino** mientras el apps-smmu esté armado (miga con `cfg`); (b) un `write_context_bank` con `cfg` (dominio NUEVO) solo se programa si su índice salió del reparto **desde arriba** (`uke_alloc_cb_arriba`, bitmap nuevo `uke_cb_reservados_arriba`), con miga del índice; (c) el quirk completo (escritura S2CR(109) + **relectura** + CB70/CBAR70) se silencia con bit4 y, al silenciarse, el CB 70 se reserva igualmente para que el reparto no lo entregue.

### 1.1 Decisión de polaridad y default (documentada por ser punto ambiguo del encargo)

El encargo dice las dos cosas siguientes: "mask de GRUPOS de escritura **que se OMITEN**" y "default 0xfff — **todo**", pero el ejemplo operativo dice "**mask=0 = cero escrituras nuevas**".
Son incompatibles entre sí; K9 fija la polaridad por el **ejemplo operativo** (es el que sostiene el diagnóstico) y lo hace explícito en cada miga y en el `MODULE_PARM_DESC`:

* **bit a 1 = ESCRIBIR**, bit a 0 = silenciar ⇒ `mask=0` = cero escrituras nuevas ✔ (lo que el encargo pide en el ejemplo).
* **default compilado = 0 = SILENCIO TOTAL** (así "silencio de escrituras por defecto" es literal y **la imagen tal cual es la rung diagnóstica**, no un clon de K8).
* `0xfff` (valor "todo" del encargo) se acepta y equivale a `0x1ff` = todos los grupos activos = K8 con migas (rung de control).

Si el dueño prefiere la polaridad contraria, es un cambio de 3 líneas + repack; **ningún rung depende de la polaridad porque la tabla de valores es explícita** (§3).

---

## 2. El mecanismo, punto por punto (con `file:line` del árbol K9)

### 2.1 Mapa `uke_write_mask` — qué bit silencia qué

`arm-smmu.h:608-621` (defines), `arm-smmu.c:817-919` (param, helpers, bitmap de CB):

| bit | grupo (`#define`) | qué escritura(s) silencia | dónde se aplica (`file:line`) | miga de silencio (literal) |
|---|---|---|---|---|
| 0 (1) | `UKE_WMASK_F4_TLBI` | `TLBIALLH(0x6c)=0xffffffff` + `TLBIALLNSNH(0x68)=0xffffffff` | `arm-smmu.c:3053` (rama F4 del reset) | `wmask[F4 TLBI]: SILENCIADA …` (`:3060`) |
| 1 (2) | `UKE_WMASK_F5_SCR0` | F5: **leer** sCR0 + calcular el valor final (F5 no escribe HW) | `arm-smmu.c:3081,3112` | `wmask[F5 sCR0]: SILENCIADA … F7 se omitira tambien` (`:3120`) |
| 2 (4) | `UKE_WMASK_F6_ACTLR` | `impl->reset`: RMW de **sACR** + bucle **CB_ACTLR ×71** (CPRE errata) | `arm-smmu.c:3128` (llamada) + `arm-smmu-impl.c:140-180` (sACR `:144`, bucle `:166-179`) | `wmask[F6 ACTLR]: SILENCIADA …` (`:3133`) / `wmask[F6 sACR]: SILENCIADA` (`impl:150`) / `wmask[F6 CB_ACTLR]: SILENCIADO el bucle` (`impl:161`) |
| 3 (8) | `UKE_WMASK_F7_SCR0` | F7: `arm_smmu_tlb_sync_global` (sTLBGSYNC + poll) + **write sCR0** | `arm-smmu.c:3146` | `wmask[F7 sCR0]: SILENCIADA …` (`:3153`); si bit1=0 ⇒ `OMITIDA porque F5 …` (`:3143`) |
| 4 (16) | `UKE_WMASK_QUIRK` | quirk qcom: **write S2CR(109)=0x000100ff**, su **relectura** y **CB_SCTLR(70)=0 + CBAR(70)** | `arm-smmu-qcom.c:549` (guard), bloque original `:526-580` | `wmask[quirk]: SILENCIADA … quirk qcom NO detectado (bypass_quirk=false) y el CB 70 queda reservado igualmente` (`:552`) |
| 5 (32) | `UKE_WMASK_RMR` | `arm_smmu_rmr_install_bypass_smr`: **write sCR0 |= CLIENTPD** (y con bit5=0 **tampoco lee** sCR0) | `arm-smmu.c:3603-3617` | `wmask[rmr]: SILENCIADA … NO se lee ni se escribe sCR0` (`:3614`) |
| 6 (64) | `UKE_WMASK_ATT_SME` | attach: `write_sme` de mapeos **NUEVOS** (2º bucle de `master_alloc_smes` y release de `master_free_smes`) | `arm-smmu.c:2362` (alloc) y `:2401` (release) | `wmask[attach_sme]: SILENCIADO write_sme idx=%d dev=%s …` (`:2362`) / `… del release idx=%d` (`:2401`) |
| 7 (128) | `UKE_WMASK_INST_S2CR` | attach del dominio: `install_s2cr` (escritura S2CR TRANS→CB) | `arm-smmu.c:2484` | `wmask[install_s2cr]: SILENCIADO el S2CR idx=%d …` (`:2484`) |
| 8 (256) | `UKE_WMASK_CTXBANK` | `arm_smmu_write_context_bank`: (i) con `cfg` (CB de dominio nuevo: CBAR/CBA2R/TCR/TTBR/MAIR/SCTLR) y (ii) sin `cfg` el **release/destroy de un CB nuestro** (CB_SCTLR=0; el mismo sitio que usa la fase3, que queda fuera por índice) | `arm-smmu.c:1540` (i) y `:1531` (ii) | `wmask[ctxbank]: SILENCIADA la programacion del CB idx=%d …` (`:1541`) / `… SILENCIADO CB_SCTLR=0 del CB idx=%d sin cfg (release/destroy …)` (`:1531`) |

Guardas de CB **independientes de la máscara** (`arm-smmu.c:1489-1506`): `wmask[CB70]` (`:1495`, idx == num_context_banks−1, cualquier `cfg`) y `wmask[CB]` (`:1500-1501`, cfg + índice no reservado desde arriba). Las tres escrituras del reset que NO están en la máscara se documentan en §4.

Helpers: `uke_wmask_activo()` (`arm-smmu.c:850`, exige `uke_smmu_armado` + apps-smmu), `uke_wmask_on()` (`:860`, fuera del experimento devuelve **true** = escribir ⇒ mainline intacto), `uke_wmask_valor()` (`:868`, para las migas de `arm-smmu-qcom.c`), `uke_wmask_preparar()` (`:900`, imprime la máscara efectiva en cada probe armado, llamada en `:3844`).

### 2.2 Migas nuevas del camino armado (además de las heredadas de K4/K5/K8)

* **F1** (`:3007`): `wmask[fase1]: sGFSR leido=0x… -> reescritura RMW incondicional (F1 no esta en uke_write_mask)`. F1 sigue siendo incondicional (no tiene bit; ver §4).
* **F4** (`:3053`): registros y valor `0xffffffff`.
* **F5** (`:3081` y `:3112`): `sCR0 leido=0x… (CLIENTPD=… USFCFG=…)` y `calculado sCR0 final=0x… (CLIENTPD=… USFCFG=…) — F5 solo calcula, no escribe HW`. **El "después con valor" está cubierto**: la segunda línea lleva el valor calculado exacto.
* **F6** (`arm-smmu.c:3128` + `impl:144`, `:166`, `:173`): `sACR` con ID7/major y el valor nuevo; el bucle imprime **una línea por muestra** (idx 0, 22, 70/último) **y cada 16**, con la dirección `0x…` del `CB_ACTLR` (antes era el agujero de R1 §7.2: sin miga por CB).
* **F7** (`:3146`): `sTLBGSYNC(0x70)=0xffffffff + sCR0=0x… (CLIENTPD=…)`.
* **quirk** (`arm-smmu-qcom.c:535` heredada + `:552`/`:573`): la de "VOY a ESCRIBIR S2CR(0xdb4)" se conserva y ahora va seguida de `pr_flush` antes del acceso; la rama de CB70/CBAR70 tiene su miga.
* **rmr** (`:3611`): `sCR0=0x… (CLIENTPD=1; leido sin CLIENTPD=0x…)`.
* **attach** (`:2362`, `:2401`, `:2484`, `:1531/1540`): una línea por cada write_sme/install_s2cr/write_context_bank, con `idx` y `dev`, y `pr_flush` **incondicional** (ya no depende de `uke_attach_log`).

### 2.3 Estado de la escalera de anillo/consola

Con el sistema **vivo** (≥3,57 s) `dmesg | grep UKE-POKE` recupera TODO el ring (las migas del 0,44 s incluidas). Con **muerte muda** (&lt;3,57 s) no hay consola ni ring recuperable — por eso el instrumento que sobrevive es **la máscara**: un boot que muere con `mask=0` y vive con `mask=N` localiza el grupo por diferencia. (C2 C3 pedía además pintar el FB de forma síncrona; el encargo no lo incluyó y K9 no lo hace: queda como siguiente instrumento si la escalera por máscara no basta.)

---

## 3. ESCALERA COMPLETA para mañana (un boot por rung; repack sin recompilar)

**Precondiciones de cada ciclo**: fila pre-registrada con el sha del rung (borrador §7), batería ≥3,7 V, captura de consola viva (`uke-console-viva.log`), watcher USB (`journalctl -kf` → `uke-usb-watch.log`), rescate armado, `boot_b` = `boot_b-lee.img` (`ffff8c51…`), `dtbo_b` = s258 (`f4663ff8…`), **portátil enchufado a la corriente** (regla #P25), y **NUNCA `unbind` del apps-smmu**.

**Clasificación por firma (C1/#P25)**: VIVO = `1d6b:0104` + `cdc_acm` 9-12 s; FASTBOOT = `18d1:d00d` 4-5 s; **MUERTO = full-speed + `-71`** (splash congelado).

**Rung 0 — `boot-ukek9.img` tal cual (mask=0, cmdline == K8).** *Boot recomendado nº1.*
Qué queda vivo en el HW: lecturas de `IDR0/1/2`+`PIDR` (medidas seguras ×5), **barrido de SMR(0..109)** (la apuesta de K8, única lectura no medida a 0,44 s), la **relectura de SMR(0)** del volcado BL (`uke_dump_bl_state`), y **F1 sGFSR** (RMW incondicional). Cero escrituras nuevas: ni quirk, ni rmr, ni F4/F5/F6/F7, ni un solo write del attach.

| desenlace | lectura (predicción) | siguiente jugada |
|---|---|---|
| **VIVE** (SSH ≥3,6 s, `EXT4-fs (sda32): mounted` ~15,6 s, groups creados) | el asesino de K7/K8 es **una de las escrituras silenciadas** (C2 ranking #1/#3); las lecturas quedan exoneradas de facto | subir por la escalera: **0x1** → luego **0xf** → luego bloques (ver abajo). Con el rung vivo, `dmesg` da además el primer volcado real de las fases a 0,44 s |
| **MUERE MUDA ~0,44 s** | el asesino es de **LECTURA o del resto incondicional** (C2 ranking #2): sospechoso nº1 el **barrido de SMR(0..109)**, nº2 F1, nº3 la relectura de SMR(0) | **`boot-ukek9-h2.img`** (handoff=2 + mask=0: **sin barrido**, sin escrituras). Si h2 VIVE ⇒ barrido letal confirmado (K2 por fin resuelto). Si h2 muere ⇒ el asesino es F1 sGFSR o una lectura de cfg_probe (IDR/PIDR); el siguiente rung ya no es un repack sino un K10: trocear el barrido (1 índice por boot, con un `uke_handoff=4`) y/o hacer F1 silenciable |

**Subida por grupos (tras un rung que VIVE)** — predicción de la miga/lectura de cada muerte parcial:

| rung (mask) | grupo(s) que se activan | si MUERE ahí: conclusión | miga que delimita (consola viva) |
|---|---|---|---|
| `0x1` | F4 TLBI | `TLBIALLH/NSNH` sobre el estado del BL es letal | `wmask[F4 TLBI]: ESCRIBO TLBIALLH(0x6c)=0xffffffff …` |
| `0x2` | F5 (solo LEE sCR0) | (imposible por escritura; si muere, es la lectura de sCR0) | `wmask[F5 sCR0]: sCR0 leido=0x…` |
| `0xa` (2+8) | F5+F7 (sCR0 final) | **materializar sCR0 (CLIENTPD 1→0 = "encender" la SMMU heredada) es letal** | `wmask[F7 sCR0]: ESCRIBO sTLBGSYNC… + sCR0=0x… (CLIENTPD=0)` |
| `0x4` | F6 (sACR + CB_ACTLR×71) | hay un **CB vivo** del BL con `ACTLR` tocado (C2 H1); el índice lo dice la muestra/every-16 | `wmask[F6 CB_ACTLR]: idx=%d/%u (muestra)` (0, 22, 70 o el múltiplo de 16) |
| `0x10` | quirk (S2CR(109)+CB70/CBAR70) | las escrituras del quirk **antes del barrido** matan (C2 H7/H2) | `wmask[quirk]: ESCRIBO CB_SCTLR(70)=0 y CBAR(70)=…` / la de "VOY a ESCRIBIR S2CR(0xdb4)" + relectura |
| `0x20` | rmr (sCR0 \|= CLIENTPD) | **apagar la SMMU** (CLIENTPD=1) con el BL/USB vivo es letal | `wmask[rmr]: ESCRIBO sCR0=0x… (CLIENTPD=1; leido sin CLIENTPD=0x…)` |
| `0x40` | attach write_sme nuevos | el storm de SME (lo que mató a K4c) sigue letal pese al pineo; el `dev`/`idx` exacto sale en la miga | `wmask[attach_sme]: ESCRIBO el SME idx=%d dev=%s` (precedida de `attach: ESCRIBIR SME idx=…`) |
| `0x80` | attach install_s2cr | el S2CR del attach de dominio mata | `wmask[install_s2cr]: ESCRIBO el S2CR idx=%d` |
| `0x100` | write_context_bank nuevos | programar el CB de un dominio nuevo mata (aunque venga "desde arriba", `idx` en la miga) | `wmask[ctxbank]: ESCRIBO el CB idx=%d (reservado desde arriba…)` |
| `0xfff` (o `0x1ff`) | **todos** | **control**: debe reproducir la muerte muda de K8; si NO muere, K8 murió por algo que K9 ya no hace (quirk sin relectura, CB70 protegido, etc.) y hay que revisar la lista | (ninguna: reproduce K8) |

**Bloques útiles** (menos boots): `0xf` = solo el reset (F4+F5+F6+F7) · `0x1c0` = solo el attach (SME+S2CR+CB) · `0x30` = quirk+rmr (las dos escrituras incondicionales de sCR0/S2CR) · `0x1ff`/`0xfff` = todo.

**Reglas de la escalera**:
1. Cada rung es **un boot** (los params se leen en el probe; con el probe ya bindeado no hay re-probe sin `unbind`, que está PROHIBIDO). Repack + flash + boot en frío.
2. **Bisección hacia arriba desde 0** es más informativa que bajar desde 0x1ff: con `mask=0` vivo, cada bit añadido es una hipótesis aislada.
3. Si un rung muere con consola viva (≥3,6 s), la última miga `wmask[...]` (flush-eada) es el punto exacto; si muere muda, la conclusión es por diferencia entre rungs.
4. **El rung que VIVE es también el rung que funciona**: si `0xf` vive pero `0x10` muere, la receta final es `0x1f0&~0x10`… es decir, se queda silenciado el grupo letal y la tablet arranca con todo lo demás (con las degradaciones conocidas: quirk no detectado ⇒ S2CR BYPASS sin traducir a FAULT; CB70 sin programar).
5. Recordatorio de R1 §6.c: `echo N > /sys/module/arm_smmu/parameters/uke_write_mask` **sí** funciona en caliente, pero solo tendrá efecto en un probe nuevo ⇒ util para preparar un `bind` desprendido, **no** para iterar la escalera sin reboot (el nodo ya está bindeado).

---

## 4. Lo que NO cubre la máscara (honestidad, para que nadie lo lea como descuido)

1. **F1 sGFSR** (`arm-smmu.c:2988-2994`): RMW incondicional (lee y reescribe el mismo valor). No tiene bit (el encargo fija 9 grupos). Queda medido en K1/K2/K3 y es el candidato residual si `mask=0` muere mudo (junto con las lecturas).
2. **F2/F3** siguen bajo `uke_reset_mask` (bit0/bit1; la cmdline trae `12` ⇒ ambas omitidas). No se duplican en la máscara.
3. **Lecturas**: `IDR0/1/2+PIDR`, el barrido de SMR(0..109) y la relectura de SMR(0) del volcado no están en la máscara (no son escrituras). Con `mask=0` **sí** se lee sCR0 en ningún sitio (bit5=0 ⇒ ni rmr lo lee; bit1=0 ⇒ F5 no lo lee) — la única lectura de un registro de traducción que queda es SMR(0).
4. **Dependencia F7→F5**: si bit1=0, bit3 no puede materializarse (no hay valor) ⇒ F7 se omite con miga explícita (`:3126`). Para probar F7 solo, usa `0xa`.
5. **El quirk silenciado no se detecta** (`bypass_quirk=false`): con bit4=0 no hay S2CR BYPASS→FAULT ni CB70 programado; es coherente con "no tocar nada" y el CB 70 sigue reservado para el reparto desde arriba.
6. **CB70 con bit4=1** (quirk habilitado): es el **único** camino que puede escribir CB70/CBAR70, y lo hace como parte de su grupo; la guarda incondicional `wmask[CB70]` protege CB70 de todos los demás caminos (fase3, attach).
7. **La divergencia RAM↔HW del attach** (C2 H6/H10): con bits 6/7 a 0 el HW no se toca pero la RAM sí se actualiza (`s2crs[].type/cbndx`); es deliberado para el diagnóstico (los grupos se crean y el boot sigue), documentado aquí para que no se lea como bug.
8. **`-EINVAL` por solape de máscaras** de los SMR vivos (efecto colateral mainline, no letal): sigue igual que en K8.
9. **Mantenimiento de TLB y release de dominios**: las escrituras de invalidación de TLB de un dominio (`arm_smmu_tlb_inv_range`/`tlb_inv_context`: `CB_TLBIALL*`) y el resto del `arm_smmu_destroy_domain_context` (liberación de tablas, bitmap) NO están en los 9 grupos del encargo; durante la ventana temprana del probe no se ejecutan (los mapas no se deshacen). El único punto del destroy que sí se silencia con bit8 es el `CB_SCTLR=0` de un CB **nuestro** (`:1531`); contrapartida asumida: si un dominio traducido se liberase en la sesión armada, el CB quedaría habilitado en HW con tablas liberadas en vez de apagarse (preferimos "no escribir" en la rung de diagnóstico; con la escalera completa el dueño decide).

---

## 5. Compilación y empaquetado (gates)

### 5.1 Árbol y build (INCREMENTAL, decisión documentada)

`rsync -a /var/tmp/uke-k8-tree/ /var/tmp/uke-k9-tree/` (1,8 G, mtimes preservados) y `cp -a /var/tmp/uke-k8-build /var/tmp/uke-k9-build` (5,2 G).
**Diferencia con K8**: en el build copiado se **relocalizaron las rutas** de los 10 438 `.cmd` + `.d` + `include/config/auto.conf.cmd` (`s|uke-k8-tree|uke-k9-tree|`) y se borraron `Makefile`/`source` (kbuild los regenera apuntando a `uke-k9-tree`). K8 no lo hizo y pagó un rebuild completo de 3538 objetos (28 min); K9 compiló **solo 5 objetos + relink** (90 s) sin tocar `/var/tmp/uke-k8-tree` ni `/var/tmp/uke-k1*`.

```
$ setsid nohup env MAKE=/usr/bin/make /usr/bin/make -C /var/tmp/uke-k9-tree O=/var/tmp/uke-k9-build \
      ARCH=arm64 LLVM=1 MAKE=/usr/bin/make -j16 Image.gz > /var/tmp/uke-k9/build.log 2>&1 &
   … CC qcom_iommu.o arm-smmu.o arm-smmu-impl.o arm-smmu-nvidia.o arm-smmu-qcom.o, LD vmlinux.o,
     KSYMS/AS/LD vmlinux, OBJCOPY Image, GZIP Image.gz  (≈90 s, 13 pasos)
```

| gate | comando | salida |
|---|---|---|
| rc=0 (idempotente) | `/usr/bin/make -C … O=… Image.gz; echo RC=$?` | **RC=0**, `grep -cE "^  (CC\|LD\|GZIP\|AR\|OBJCOPY)"` = **0** (nada que rehacer), `sha256sum -c sha-before.txt` = coincide |
| sin warnings en lo tocado | `grep -iE "error\|warning" build.log` | **0** (ni error ni warning; los de K8 en otros drivers no aparecen porque no se recompilaron) |
| config intacta | `md5sum .config` | `2c9f3a391d161aeb84a3d813c09eab9b` **idéntico** a K1..K8 |
| toolchain/arch | `file Image` | `Linux kernel ARM64 boot executable Image, little-endian, 4K pages` |
| magic ARM64 | bytes @56 | `41 52 4d 64` |
| banner | `strings Image \| grep "Linux version"` | `Linux version 7.2.0-rc2-palawan (usuario@pc-build) (clang version 22.1.8, LLD 22.1.8) #14 SMP PREEMPT Tue Sep 29 15:26:19 CEST 2026` |
| tamaño | `ls -la` | Image.gz **16576161 B** (K8 16572290 ⇒ **+3871 B**), Image crudo **41355776 B** (**delta 0** vs K1..K8) |
| strings | `Image.count(b"UKE-POKE")` | **114** (K8: 82) |
| param nuevo | `count(...)` | `uke_write_mask`=16, `arm_smmu.uke_write_mask`=1 |
| migas K9 | `count(...)` | los **13** prefijos `wmask[...]` (14 literales: `wmask[ctxbank]` tiene 3 variantes) presentes (ver `repack-k9-report.txt` G4) + `cero escrituras nuevas`=1 + `K9 uke_write_mask=0x%x (efectivo 0x%x)`=1 + `arm_smmu.uke_write_mask`=1 |
| heredados | idem | las 35 cadenas K1..K8 siguen presentes (`handoff: INICIO barrido…`, `PINADOS=%u de %u grupos`, `ESCRITURA BLOQUEADA write_sme`, `PRESERVADO (BL vivo)`, `NO LEIDO (letal #P13)`, …) |
| tabla `__param` | `strings` | los **9** params UKE: `arm_smmu.{uke_smmu_probe,uke_smr_max,uke_keep_boot,uke_reset_mask,uke_attach_log,uke_protect_smr0,uke_stream_match,uke_handoff,uke_write_mask}` |
| objetos | `ls -la` | `arm-smmu.o`, `arm-smmu-impl.o`, `arm-smmu-qcom.o` recompilados (antes/después en `build.log`) |

### 5.2 `repack-k9.py` (patrón K8, gates G0-G8) → gates verdes

```
G0 base s240-mem2g e3c60969… (100663296 B) OK · kernel K9 Image.gz e54aa2c4… (16576113 B) OK · frescura OK
G1 ANDROID!, kernel_size@8 (base)=16560041, gzip @4096 OK
G2 cmdline K8 = cmdline(s244,255 B) + 5 tokens = 382 B byte a byte OK; tokens únicos OK
G3 Image.gz K9 16576161 B (K8: 16572290, +3871 = +0,023%)
G4 UKE-POKE=114; 35 cadenas heredadas K1..K8; 19 cadenas K9; 9 params en __param; PRIVCFG=0   TODO OK
G5 kernel @4096..16580257; kernel_size@8=16576161; cmdline @44..426; resto del campo a cero
G6 96 MiB, ANDROID!, kernel_size=16576113, AVB0@35438592, AVBf@100663232, cmdline NUL-terminada OK
G7 payload del output == Image.gz del build; descomprimido == Image crudo (41355776 B, 7bb94e86…);
   cabecera 0..4096 intacta salvo kernel_size@8 y cmdline[44..1580); cola 16580257..100663296 idéntica byte a byte;
   delta vs K8 = 16505819 B TODOS dentro de kernel_size + ventana kernel + cmdline · cmdline K9 == cmdline K8: SI
G8 build/bootimg/boot-ukek9.img · 100663296 B · sha256 f21cc35f… · kernel_size=16576161
```

### 5.3 Verificación independiente (`verify-k9.py`, 38 gates) — TODOS VERDES

```
1 forma: 96 MiB, ANDROID!, gzip @4096, AVB0 @35438592, AVBf @100663232                     OK
2 kernel: kernel_size@8=16576161 == len(payload); payload descomprimido == Image del build
          (41355776 B, sha 7bb94e86…); Image.gz sha 03ed849b…                              OK
3 cmdline: K9 (382 B) == K8 (382 B) byte a byte; campo NUL-terminado; SIN token uke_write_mask
          (⇒ el default compilado 0 = silencio total es el que manda)                       OK
4 delta vs K8: 16505819 B, 0 fuera de kernel_size/kernel/cmdline                            OK
5 marcadores: UKE-POKE=114; uke_write_mask y los 13 prefijos wmask[...]; los 9 params en __param OK
6 unpack_bootimg rc=0 (magic, kernel_size 16576161, cmdline, header v4) · avbtool info_image rc=0
          (Footer 1.0, Image size 100663296, VBMeta offset 35454976, size 1728)              OK
```

Nota AVB (idéntica a K1..K8): la estructura es parseable pero el *digest* del hash descriptor es el del contenido anterior
(cualquier cambio de kernel/cmdline lo cambia); `avbtool verify_image` no es utilizable sobre este artefacto y falla igual con `boot-ukek7.img` (que arrancó). El gate real sigue siendo magias + estructura + `fastboot flash`.

---

## 6. Anti-regresión (por qué nada de K9 puede romper el arranque desarmado)

1. **`uke_wmask_activo()` exige `uke_smmu_armado`** (`arm-smmu.c:850`) — el mismo bool del gate del probe de K2. Sin token (`uke_smmu_probe=1`), el probe devuelve `-EPROBE_DEFER` antes de `devm_kzalloc`/`cfg_probe`/`uke_handoff_preparar` y **no se ejecuta ni una línea de K9** (`uke_wmask_on` devuelve true, las guardas no entran, las migas no imprimen).
2. **`uke_wmask_on()` devuelve true fuera del experimento** (`:860`) ⇒ para el **kgsl-smmu** (0x3da0000) todos los caminos quedan literalmente como mainline/K8: las guardas no saltan, la máscara no silencia, y las migas nuevas no imprimen (`UKE_K9_LOG`/`UKE_K9_FLUSH` y `uke_k9` en `arm-smmu-impl.c:141`). El kgsl no gana ni una línea de log ni un `pr_flush`.
3. **A/B limpio**: `uke_handoff=0` desactiva todo K8; `uke_write_mask` sigue aplicando (silencio/ejecución) porque es ortogonal: es la palanca para "K7 sin escrituras" si hiciera falta.
4. **`arm-smmu-qcom.c`**: el quirk solo cambia de comportamiento con `uke_wmask_on(...)==false`, que solo ocurre con apps-smmu **armado** y bit4=0; en cualquier otro caso ejecuta el código original palabra por palabra (con la miga ya existente de K3).
5. **Coste estructural**: un `int` + un bitmap de 128 bits + 2 helpers; `.config` idéntico, `Image` crudo del mismo tamaño que K1..K8 (41355776 B), cero cambios de ABI/Kconfig.

---

## 7. Fila de pre-registro propuesta (#P26) y cierre

> **#P26 — K9 (máscara de escrituras; primer boot = silencio total)** · artefacto `build/bootimg/boot-ukek9.img`
> sha256 `5042f977b8e3a5bb61afdffc27033cc711d179f3c6c6e2f4cef2d8139cab2561` (100663296 B; `kernel_size`@8 = 16576113;
> cmdline = la de K7/K8 byte a byte, 382 B ⇒ **efectivo `uke_write_mask=0` = cero escrituras nuevas**) · kernel `#13`
> (Tue Sep 29 15:26:19 CEST 2026), Image.gz `e54aa2c4…`, Image crudo `a55d9a05…` (delta 0) · diff `k9-escrituras.diff`
> `76905de6…` · **canal**: `fastboot flash boot_b` (dtbo_b s258 sin tocar) + arranque en frío · **predicción
> pre-registrada**: (a) VIVE ⇒ las escrituras matan; siguiente rung `--wmask 0x1` (repack) y `dmesg` da el volcado real de
> las fases a 0,44 s; (b) MUERE MUDA ⇒ el asesino es lectura/incondicional (nº1 el barrido SMR(0..109)) ⇒ siguiente
> **`build/bootimg/boot-ukek9-h2.img`** `fc48e82a…` (`uke_handoff=2` + mask 0: sin barrido y sin escrituras); (c) VIVE
> pero sin UFS/mount ⇒ mirar `wmask[rmr]/[F7]` en dmesg y subir por `0x30`; **evidencia de muerte temprana**: USB roto
> full-speed/`-71` + splash congelado (firma #P25) · **rollback**: `boot_b-lee.img` (`ffff8c51…`) + baile de slots ·
> **gates**: los de §5 · **recordatorio**: NUNCA `unbind` del apps-smmu; portátil enchufado a la corriente.

Cierre: K9 es **K8 + un instrumento que sobrevive a la muerte muda**. K8 murió mudo y no dejó nada; K9, en la
configuración en la que se flashéa, **no escribe nada** en el camino armado, y eso convierte el próximo silencio en una
respuesta binaria: si muere igual, el asesino son las **lecturas** (y el siguiente boot lo aísla con `handoff=2`); si vive,
el asesino es una **escritura** y la escalera de bits lo nombra con una serie de boots de repack (30 s cada uno, sin
recompilar). Todo lo demás (K8 intacto, cmdline intacta, arranque desarmado intacto, kgsl intacto) está verificado gate a gate.
