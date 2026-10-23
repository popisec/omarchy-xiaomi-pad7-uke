# INFORME-K8-BUILD — kernel K8 = K7 + PORT DEL MECANISMO DE HANDOFF (vía H de R4) + `boot-ukek8.img`

Fecha: 2026-09-29 (mañana). Autor: agente K8. **Trabajo sin tablet** (prohibido fastboot/adb/ssh/ttyACM0).
Punto de partida: K7 = K6 (`build/bootimg/boot-ukek7.img`, sha `1c1a090b…`, kernel `ac878610…` = K6) con la
cmdline armada. Contexto decisor: **#P23** (arranque en frío de K7 a las 10:12) = muerte muda; el attach
armado con la semántica actual es **estructuralmente letal en cualquier ventana** y la preservación manual
de SMR(0)/S2CR(0) de K4-K7 no basta. K8 es la apuesta única de hoy: **no escribir ni leer jamás un registro
vivo del bootloader** porque el driver *sabe* cuáles son.

Arena: `/var/tmp/uke-k8` (scripts, refs, logs del build/reempaquetado), árbol de trabajo
`/var/tmp/uke-k8-tree`, build `O=/var/tmp/uke-k8-build`. `/var/tmp/uke-k1` y `/var/tmp/uke-k1-build` (K7) NO
se han tocado (verificado por mtime: nada modificado desde las 10:25; `vmlinux` de K7 sigue en 01:02).
No hay ningún `git commit` (lo hace el orquestador); `git status` solo muestra ficheros nuevos.

---

## 0. Entregables y shas

| fichero | bytes | sha256 |
|---|---|---|
| `build/bootimg/boot-ukek8.img` (imagen final) | 100663296 (96 MiB exactos) | **`5e34596a230d2d645ad8dcc68dcba5c23bc58bf2a6c6468a526a66bb687d54e2`** |
| `build/gates/patches/k8-handoff.diff` (546 líneas, 14 hunks, 2 ficheros) | 23917 | `ad869168ffad7a3b14bbd62970ef5d90d1d7599900ec6914b5620955e1d000fc` |
| `Image.gz` del build (`arch/arm64/boot/Image.gz`) | 16572290 | `fad9a1600d81ba6d63565fb19f36ba055019847f8450df4f916d7760ed592148` |
| `Image` crudo del build | 41355776 (= K1..K6, delta 0 B) | `ae4485dbf48016162665d33e038c91c477f55a9972b59df3bf6c8b17ecfc5ff1` |
| `arm-smmu.c` K8 | 126790 | `4c1beba1cfb232aa36ca87e187fec10f6911caa70a44c50843e5110d40159673` |
| `arm-smmu.h` K8 | 17918 | `d687b11f6793a64d913cdbfafb44a5abece96d0c3d1f4e9836cbab1323bb4ffd` |
| `arm-smmu-qcom.c` (NO tocado: idéntico a K7) | 34129 | `3ed87c75b708798027aa7b6c8e40441e47178e5cdca5d2e132a6688e6af55974` |
| cmdline de la imagen | 382 | == la de K7 **byte a byte** (ver §6) |
| variante pre-construida `uke_handoff=2` (arena) | 100663296 | `4833e03820aaa266a6a6609d351d67510dced38f4da3a9fd33edf6d6e1e11e2f` (`/var/tmp/uke-k8/boot-ukek8-h2.img`, ver §2.6) |
| árbol K8 / build dir | 1,8 G / 5,2 G | rsync de K1 + `cp -a` del `O=` (ver §5.1) |

## 1. Qué hace K8 distinto de K7 (las tres frases del encargo, cumplidas)

1. **Antes del reset, K8 LEE el banco entero de SMR (0..109) y marca `pinned` todo índice con VALID=1**:
   a partir de ahí ningún camino del driver puede escribir ni reasignar ese índice (guards en
   `arm_smmu_write_smr`, `arm_smmu_write_s2cr`, `arm_smmu_write_sme`, `arm_smmu_find_sme` por
   construcción, y el fix del bug ALTA de R1 en `arm_smmu_free_sme`).
2. **Parsea `qcom,handoff-smrs` del DT** (`<0x1c00 0x02>`, el SID del mdss/display): cualquier maestro
   cuyo fwpec sea subconjunto de un par declarado se pina y **no se le escribe ni SMR ni S2CR** — el
   maestro sigue con la traducción/bypass que dejó el BL y el dominio queda *sin traducir por ahora*.
3. **Los CB de dominios nuevos se reservan DESDE ARRIBA** (70→0) en vez de 0→71, para no pisar los CB
   vivos del BL (su `cbndx` es ilegible porque leerlo mata, #P13; el CB22 se midió vivo en #P14).

Todo ello **solo para el apps-smmu** (`uke_smmu_es_apps()`), **solo con `uke_handoff != 0`**, con migas
`UKE-POKE` + `pr_flush` antes de cada escritura nueva, y **sin tocar** la cmdline, las fases del reset ni
el arranque desarmado (que sigue siendo idéntico a K6/K7 ⇒ boot sano garantizado).

## 2. El mecanismo, punto por punto, con el código de referencia

Referencia descargada y leída en esta sesión (**no de memoria**), en `/var/tmp/uke-k8/ref/`:

| fichero | origen | sha256 |
|---|---|---|
| `ref/xiaomi-arm-smmu.c` (113581 B) | `https://raw.githubusercontent.com/Xiaomi-Pad-7-Pro-Resources/android_kernel_xiaomi_sm8635/lineage-23.0/drivers/iommu/arm/arm-smmu/arm-smmu.c` (kernel Android del MISMO SoC: SM8635/cliffs, lineage-23.0) | `fd6704ab92ea4d3d…` |
| `ref/xiaomi-arm-smmu.h` (22231 B) | ídem `arm-smmu.h` | `ad504868b094ccaf…` |
| `ref/commit-8fa3cecff06e….diff` | `https://github.com/CodeLinaro-mirror/le_kernel_msm-5.15/commit/8fa3cecff06e7aeba00e0f463714c4ad09dcca30.diff` ("arm-smmu: use smr match for handoff-smrs") | — |
| `ref/commit-18d1a0b7a412….diff` | ídem `…/18d1a0b7a412ee821aa92f0dc2e54ced8bb79611.diff` ("arm-smmu: Correct the index for handoff smrs") | — |

Los dos ficheros que el encargo pedía (`arm_smmu_handoff_cbs()`, `s2cr[].pinned`, `__arm_smmu_alloc_cb()`)
se descargaron sin problema ⇒ **no se usó el fallback "implementar desde cero"**.

### 2.1 Pineo de SMR vivos (barrido de LECTURAS) — `uke_handoff_pin_sweep()`

Cita del lineage (`ref/xiaomi-arm-smmu.c:3047-3106`, `arm_smmu_handoff_cbs()`, llamado desde el probe en
`:3671`):

```c
	for (i = 0; i < smmu->num_mapping_groups; ++i) {
		smr = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_SMR(i));
		...
		smrs.valid = FIELD_GET(ARM_SMMU_SMR_VALID, smr);
		if (!smrs.valid)
			continue;
		...
			smmu->smrs[i] = smrs;
			smmu->s2crs[i].group = NULL;
			smmu->s2crs[i].count = 0;
			smmu->s2crs[i].type = FIELD_GET(ARM_SMMU_S2CR_TYPE, s2cr);
			smmu->s2crs[i].privcfg = FIELD_GET(ARM_SMMU_S2CR_PRIVCFG, s2cr);
			smmu->s2crs[i].cbndx = FIELD_GET(ARM_SMMU_S2CR_CBNDX, s2cr);
			smmu->s2crs[i].pinned = true;
			bitmap_set(smmu->context_map, smmu->s2crs[i].cbndx, 1);
```

y `struct arm_smmu_s2cr { … bool pinned; }` (`ref/xiaomi-arm-smmu.h:339-346`).

Qué se porta y qué NO:

* **Se porta**: leer SMR(i) de TODO el banco, y el bit `pinned` como único estado que decide "no escribir".
* **NO se porta** (decisión de vida o muerte, R1 #P13): la lectura de `S2CR(i)` para copiar
  `type/privcfg/cbndx` del BL. En esta tablet leer el S2CR de un índice vivo mata (#P13), así que
  `cbndx` del BL queda **desconocido a propósito** y ningún camino de K8 lo necesita (de ese índice no se
  escribe nada). Es la desviación explícita que pide R4 §2.1 ("portar la lógica pero **sin leer S2CR**").
* **Sí se copia** la parte de `smrs[i] = smrs` en RAM: K8 deja la copia RAM del SMR **como está** (la del
  BL) y no la sobrescribe con la del maestro que herede el índice.

Efecto colateral deliberado (el mismo que mainline cuando el barrido completa): `find_sme()` no reparte
índices válidos como "libres" ⇒ **el storm del attach ya no puede pisar un mapeo vivo** (el asesino medido
de K4c: `write_sme idx=1`, R1 §4.2).

### 2.2 `qcom,handoff-smrs` del DT — `uke_handoff_parse_dt()` + `uke_handoff_es_dt()`

Test de subconjunto **literal del vendor** (`ref/xiaomi-arm-smmu.c:3082-3083`; el commmit CodeLinaro
`8fa3cef` lo introdujo para no depender del índice, "the index could mismatch between ABL and HLOS"):

```c
			/* smrs is subset of handoff_smrs */
			if ((handoff_smrs[index].mask & smrs.mask) == smrs.mask &&
			    !((handoff_smrs[index].id ^ smrs.id) & ~handoff_smrs[index].mask)) {
```

y el parseo del DT (`:3025-3044`):

```c
	cell = of_get_property(smmu->dev->of_node, "qcom,handoff-smrs", NULL);
	num_handoff_smrs = of_property_count_elems_of_size(…, "qcom,handoff-smrs", sizeof(u32) * 2);
	…
		handoff_smrs[i].id = of_read_number(cell++, 1);
		handoff_smrs[i].mask = of_read_number(cell++, 1);
```

K8 lo aplica en dos sitios: (a) al clavar el barrido, si un SMR vivo es subconjunto de un par declarado
se pina con la nota `[declarado en qcom,handoff-smrs]`; (b) en el attach, si el fwpec del maestro es
subconjunto de un par, el índice elegido se pina (aunque no estuviera vivo) y **no se escribe**: miga
`... es qcom,handoff-smrs del DT; idx=N PINADO sin estar vivo` y luego
`... -> idx=N PINADO (handoff-smrs del DT): NO se escribe SMR/S2CR; el maestro sigue con el mapeo del BL y
el dominio queda SIN traducir por ahora`. Cómo lo resuelve el lineage: reutiliza el CB del BL (el maestro
sigue traduciendo con el CB del firmware, `__arm_smmu_alloc_cb()` ⇒ `s2cr[].cbndx`), y
`arm_smmu_domain_add_master()` hace `continue` cuando `type`/`cbndx` coinciden
(`ref/xiaomi-arm-smmu.c:1901-1909`). Aquí, sin poder leer el `cbndx`, el equivalente es "no escribir el
S2CR y dejar el dominio marcado como no traducido".

Nuestro DT efectivo (`base-dtb` + s258 con fdtoverlay, medido #P21 en `/var/tmp/k8-check/merged.dtb`)
declara `qcom,handoff-smrs = <0x1c00 0x2>`, y el maestro del display
(`qcom,smmu_sde_unsec_cb`) usa exactamente `iommus = <&apps_smmu 0x1c00 0x02>` ⇒ el match es exacto.

### 2.3 CB desde arriba — `uke_alloc_cb_arriba()`

El lineage **sí puede** reutilizar el CB del BL porque lee su `cbndx` del S2CR
(`__arm_smmu_alloc_cb()`, `ref/xiaomi-arm-smmu.c:390-406`):

```c
	for_each_cfg_sme(cfg, fwspec, i, idx) {
		if (smmu->s2crs[idx].pinned)
			return smmu->s2crs[idx].cbndx;
	}
	return __arm_smmu_alloc_bitmap(map, start, end);
```

Aquí ese `cbndx` es ilegible (leerlo mata), así que la protección equivalente es **no repartir los CB
bajos**: `arm_smmu_alloc_context_bank()` llama a `uke_alloc_cb_arriba(smmu, start)` (70→0) cuando el
handoff está activo. El BL llena desde abajo (su único SMR visto en 7 runs es el idx 0 = ufshc; su CB vivo
medido es el 22), y el CB 70 ya está reservado por el quirk del bypass (`set_bit` en
`qcom_smmu_cfg_probe`) ⇒ el primer dominio nuevo (el wifi, único `def_domain_type == 0`) cae en el **69**,
con miga `UKE-POKE: handoff: CB 69 reservado DESDE ARRIBA`.

### 2.4 Nunca leer S2CR (regla de vida o muerte)

* El barrido de K8 solo lee SMR. **Cero lecturas de S2CR nuevas.**
* Los dos únicos sitios que ya leían `S2CR(0)` en el camino de escritura de idx 0
  (`master_alloc_smes`, `install_s2crs`) pasan a estar condicionados a `!uke_pinado(smmu, idx)`: con
  handoff activo el idx 0 (el SMR vivo del ufshc) nunca se alcanza, y la condición lo deja explícito.
* `uke_dump_bl_state()` (K6) sigue sin leer S2CR y ahora re-imprime los SMR que el barrido ya leyó.

### 2.5 Tabla de guards (el bug ALTA de R1 incluido)

| punto | antes (K7) | K8 | cita |
|---|---|---|---|
| `arm_smmu_write_smr()` | escribía siempre | si `uke_pinado(idx)` ⇒ miga `ESCRITURA BLOQUEADA write_smr` y `return` | medida #P14/#P15 |
| `arm_smmu_write_s2cr()` | escribía siempre | ídem (`ESCRITURA BLOQUEADA write_s2cr`) ⇒ cubre también el quirk `qcom_smmu_write_s2cr` (se llama desde aquí) | K4c (write_sme idx=1) |
| `arm_smmu_write_sme()` | migas + escritura | corta antes de las migas si está pinado (`ESCRITURA BLOQUEADA write_sme`) | — |
| `arm_smmu_free_sme()` | reseteaba la entrada y devolvía `true` ⇒ el llamante **escribía** BYPASS/FAULT | si pinado: no libera, no invalida, **devuelve `false`** (el llamante no escribe) | **BUG ALTA R1 §7.1** (`arm-smmu.c:1752-1765`); el lineage conserva `pinned`/`cbndx` en `arm_smmu_free_sme()` (`ref/…:1778-1796`) pero sigue devolviendo `true` ⇒ aquí somos más estrictos |
| `arm_smmu_master_alloc_smes()` (1er bucle) | repartía índices "libres" a ciegas | si el idx es pinado o el SID es handoff-DT: reclama en RAM (`count++`/`smendx`) y **no escribe**; si el SMR ya estaba vivo, la copia RAM **no se sobrescribe** | asesino medido de K4c |
| `arm_smmu_master_alloc_smes()` (2º bucle, el que "poca el HW") | escribía el SME | guard explícito con miga `attach: SME idx=N PINADO (dev)`: se omite `write_sme` | #P17/#P22/#P23 |
| `arm_smmu_master_install_s2crs()` (attach del dominio) | escribía el S2CR (TRANS→CB) | guard con miga `attach: install_s2cr idx=N PINADO: NO se escribe el S2CR` | R1 §5.2 |
| `arm_smmu_test_smr_masks()` | con `uke_keep_boot` omitido | omitido también con handoff activo (no toca SMR ni con `uke_keep_boot=0`) | R1 §7.8 |
| `arm_smmu_alloc_context_bank()` | 0→71 | 70→`start` con handoff | §2.3 |
| `arm_smmu_find_sme()` | — | sin cambios: un índice `valid` no es "libre" (y ahora todos los vivos son `valid` con su id/mask reales) ⇒ "no reasignar" por construcción | K3 §1.2.2 |

### 2.6 Parámetro nuevo `uke_handoff` y variante pre-construida

```
uke_handoff = 0 : APAGADO. Todo el código K8 se comporta como K7 (A/B limpio; comprobado guard a guard).
uke_handoff = 1 : COMPLETO (default). Barrido 0..109 + DT + CB desde arriba.
uke_handoff = 2 : SIN BARRIDO. No lee ningún SMR nuevo; pina solo lo que la RAM ya sabe vivo (el barrido
                  acotado de K3 con uke_smr_max) + el DT + CB desde arriba.
```

`uke_handoff=2` existe como **escalera de rescate sin recompilar** para el único punto que no está medido
(§3): ya hay una imagen lista para flashear con esa cmdline en la arena,
`/var/tmp/uke-k8/boot-ukek8-h2.img` (sha `4833e038…`, cmdline de 405 B = la de K7 + ` arm_smmu.uke_handoff=2`,
producida con `repack-k8.py --handoff 2 --out …`; los gates G0-G8 del repack pasan igual).

## 3. El punto NO medido (honestidad brutal): el barrido completo de LECTURAS de SMR

El diseño manda leer `SMR(0..109)` y el encargo lo da por seguro ("medido #P9/#P13"). Lo que hay en el
disco, leído entero para este informe, es esto:

* **SMR(0) leído sin morir**: 5 runs (K3 `smr_max=0`, K4b, K4c ×2, K5b, K6/K6b: `SMR loop OK (leidos=1
  validos=1)` en `build/gates/k4c-consola-trail.txt:27835` y `:48960`). **Indiscutible.**
* **Barrido completo (0..109)**: se intentó UNA vez, en K2 (`build/evidencia/2026-09-28/k2-migas.log:2583`):
  última línea `[171.464254] UKE-POKE: qcom_cfg_probe: leyendo SMR(0..109)` y cuelgue duro. La atribución
  de entonces fue "muere en el barrido de lecturas", pero el análisis de K3 y R1 deja la alternativa
  abierta: en K2 **no** existía `uke_keep_boot`, así que tras el barrido el reset ejecutó la **fase2**
  (escritura de SMR/S2CR ×110, incluidos los vivos) — que es letal por sí misma y está medida como tal en
  #P9/#P10. La línea `SMR loop OK` que K2 debería haber impreso no llegó al stream ssh, y eso es lo único
  que apunta al bucle (la alternativa exige que se perdieran 5 líneas seguidas por el buffer del stream;
  con un `dmesg -w` por ssh eso es perfectamente posible en la ventana de µs en que ocurre la muerte).
  **No hay ninguna corrida del barrido completo con consola robusta** (grep exhaustivo en
  `~/proyectos/out/*.log`, `build/gates/*`, `/var/tmp/*`: la cadena `leyendo SMR(0..109)` solo existe en
  el log de K2).
* Riesgo físico a favor de que sea seguro: el bloque de registros del SMMU está alimentado y funcionando
  (el UFS traduce por él durante todo el arranque) y los 110 SMR son registros architectados implementados
  (NUMSMRG=110, ID0=0x4c017e6e). Las lecturas de SMR(0) y de SMR(i) caen en la misma página (`0x800+4i`).
  Contra: el S2CR(0) también es un registro de esa zona y su lectura es letal (#P13), o sea que el bloque
  no se comporta de forma uniforme y no se puede descartar nada por argumento.

**Decisión**: se implementa el barrido completo como default (es lo que hace útil el mecanismo: sin él,
los índices 1..109 seguirían repartidos "a ciegas" y el asesino de K4c seguiría armado), con estas tres
redes: (1) miga de progreso cada 16 índices + miga por cada PIN (si el sistema queda atascado en blando,
como #P10, el anillo dice dónde); (2) `uke_handoff=2` compilado y pre-empaquetado (repack, sin rebuild);
(3) el desenlace "muerte muda a 0,44 s" es informativo por sí mismo: **separaría por fin** "lectura del
banco letal" de "escritura de registro vivo letal" (K2 la dejó ambigua). Queda escrito aquí para que nadie
lo lea como un descuido: es un riesgo asumido y documentado, con escalera.

## 4. Compilación (gates)

### 4.1 Árbol y build dir (decisión: rebuild completo, documentada)

`rsync -a /var/tmp/uke-k1/ /var/tmp/uke-k8-tree/` (1,8 G) y `cp -a /var/tmp/uke-k1-build /var/tmp/uke-k8-build`
(5,2 G). El build dir copiado quedó **atado al árbol viejo** (`source -> /var/tmp/uke-k1`, `Makefile` con
`include /var/tmp/uke-k1/Makefile`, y los `.cmd` con rutas absolutas a `uke-k1`); construir así habría
compilado **el árbol de K7 y no K8** (trampa silenciosa). Se borraron `Makefile` y `source` del `O=` copiado
y el primer make los regeneró apuntando a `/var/tmp/uke-k8-tree` (verificado:
`source -> /var/tmp/uke-k8-tree`). Consecuencia: los `.cmd` invalidados ⇒ **rebuild completo** (3538 objetos
CC) en vez de incremental de 2 ficheros. Es el precio de tener arena propia; se asume y se documenta.
`/var/tmp/uke-k1` y `/var/tmp/uke-k1-build` (K7) quedaron intactos (mtime).

```
$ setsid nohup env MAKE=/usr/bin/make /usr/bin/make -C /var/tmp/uke-k8-tree O=/var/tmp/uke-k8-build \
      ARCH=arm64 LLVM=1 MAKE=/usr/bin/make -j16 Image.gz > /var/tmp/uke-k8/build.log 2>&1 &
   … 10:31:50 → 11:00 (≈28 min, 3538 objetos)
$ tail -2 /var/tmp/uke-k8/build.log
  OBJCOPY arch/arm64/boot/Image
  GZIP    arch/arm64/boot/Image.gz
```

| gate | comando | salida |
|---|---|---|
| rc=0 (idempotente) | `/usr/bin/make -C … O=… ARCH=arm64 LLVM=1 MAKE=/usr/bin/make -j16 Image.gz; echo RC=$?` | **RC=0**, `grep -cE "^  (CC\|GZIP\|LD)"` = **0** (nada que rehacer) y `sha256sum -c sha-before.txt` = las dos sumas coinciden (`gate-rc.log`) |
| sin warning en lo tocado | `grep warning build.log` | 0 warnings de `arm-smmu.c`/`arm-smmu.h` (los de `pinctrl-msm`, `uke-panic-fb`, `rpmh-regulator`, `spmi-pmic` son preexistentes del fork) |
| config intacta | `md5sum .config` antes/después | `2c9f3a391d161aeb84a3d813c09eab9b` **idéntico** (la misma config del #82 y de K1..K7) |
| toolchain/arch | `file Image` | `Linux kernel ARM64 boot executable Image, little-endian, 4K pages` |
| magic ARM64 | bytes @56 | `41 52 4d 64` (0x644d5241 LE) |
| banner | `strings -n8 Image \| grep "Linux version"` | `Linux version 7.2.0-rc2-palawan (usuario@pc-build) (clang version 22.1.8, LLD 22.1.8) #10 SMP PREEMPT Tue Sep 29 10:59:39 CEST 2026` (K7: `#…`/K6) |
| tamaño | `ls -la` | Image.gz **16572290 B** (K6/K7 16567869 ⇒ **+4421 B**), Image crudo **41355776 B** (**delta 0** vs K1..K6) |
| strings | `raw.count(b"UKE-POKE")` | **82** (K7: 60; K6: 30 con la métrica antigua) |
| param nuevo | `raw.count(...)` | `uke_handoff`=3, `arm_smmu.uke_handoff`=1 |
| migas K8 | `raw.count(...)` | `handoff: INICIO barrido de pineo`=1, `handoff: PIN SMR(`=2, `NO ESCRIBIBLE`=2, `handoff: CB %d reservado DESDE ARRIBA`=1, `ESCRITURA BLOQUEADA write_smr/s2cr/sme`=1+1+1, `free_sme idx=%d PINADO`=1, `handoff: FIN barrido`=1, `PINADOS=%u de %u grupos`=1, `handoff: PREPARAR modo=%d`=1, `handoff: DT qcom,handoff-smrs[%u]`=1, `PINADO sin estar vivo`=1 |
| heredados | idem | las 21 cadenas de K1..K7 siguen presentes (`reset fase2 OMITIDA`, `fases5-7 OMITIDAS`, `NO LEIDO (letal #P13)`, `PRESERVADO (BL vivo)`, …) y `PRIVCFG` sigue en 0 (no se reintroduce el formato viejo del volcado) |
| tabla `__param` | `strings` | los **8** params UKE: `arm_smmu.{uke_smmu_probe,uke_smr_max,uke_keep_boot,uke_reset_mask,uke_attach_log,uke_protect_smr0,uke_stream_match,uke_handoff}` |
| objetos | `ls -la *.o` | `arm-smmu.o` 469624 B (K7: 439408), `arm-smmu-qcom.o` 263776 B (recompilado por el `.h`, **fuente idéntica a K7**) |

Diff completo en `build/gates/patches/k8-handoff.diff` y en el Anexo B (546 líneas, 14 hunks: 13 en
`arm-smmu.c` + 1 en `arm-smmu.h`; **+440/−4** en total = +420/−4 en el `.c` y +20/−0 en el `.h`). Del
añadido, 199 líneas son comentario (45%) y 210 son código (el resto, líneas en blanco); el mecanismo
nuevo en sí (sin migas ni comentarios) son ~90 líneas.

## 5. Empaquetado

### 5.1 `repack-k8.py` (patrón K6/K7, gates G0-G8)

```
$ python3 /var/tmp/uke-k8/repack-k8.py
G0 base s240-mem2g e3c60969… (100663296 B) OK · kernel K8 Image.gz fad9a1600d81ba6d (16572290 B) OK ·
   frescura (fuentes < Image.gz) OK
G1 ANDROID!, kernel_size@8 (base) = 16560041, gzip @4096 OK
G2 cmdline K7 = cmdline(s244, 255 B) + 5 tokens = 382 B byte a byte OK; tokens únicos OK
G3 Image.gz K8 16572290 B (K6/K7: 16567869, +4421 = +0,027%)
G4 UKE-POKE=82; 21 cadenas heredadas; 19 cadenas K8; 8 params en __param; PRIVCFG=0   TODO OK
G5 kernel @4096..16576386; kernel_size@8=16572290; cmdline @44..426; resto del campo a cero
G6 96 MiB, ANDROID!, kernel_size=16572290, AVB0@35438592, AVBf@100663232, cmdline NUL-terminada OK
G7 payload del output == Image.gz del build; descomprimido == Image crudo (41355776 B, ae4485dbf4801616);
   cabecera 0..4096 intacta salvo kernel_size@8 y cmdline[44..1580); cola 16576386..100663296 idéntica
   byte a byte (extra_cmdline/dtb/second/AVB intactos); delta vs K7 = 16501532 B TODOS dentro de
   kernel_size + ventana kernel + cmdline · cmdline K8 == cmdline K7: SI
G8 ~/proyectos/omarchy-uke/build/bootimg/boot-ukek8.img · 100663296 B ·
   sha256 = 5e34596a230d2d645ad8dcc68dcba5c23bc58bf2a6c6468a526a66bb687d54e2 · kernel_size=16572290
```

La base es la misma que K6/K7 (`boot-s240-mem2g.img`, sha `e3c60969…`), el kernel es el nuevo y la
**cmdline es la de K7 byte a byte** (382 B, mismos 5 tokens `arm_smmu.uke_*`) ⇒ el delta K7→K8 es
*exclusivamente el kernel* y cualquier diferencia de comportamiento es atribuible al código nuevo.

### 5.2 Verificación independiente (`verify-k8.py` + `unpack_bootimg` + `avbtool`)

```
$ python3 /var/tmp/uke-k8/verify-k8.py            # código independiente del repack
  1 forma: 100663296 B, ANDROID!, gzip @4096, AVB0 @35438592, AVBf @100663232            OK
  2 kernel: kernel_size@8 = 16572290; payload descomprimido == Image del build
            (41355776 B, sha ae4485dbf4801616); Image.gz payload sha fad9a1600d81ba6d     OK
  3 cmdline: K8 (382 B) == K7 (382 B) byte a byte; resto del campo a cero                OK
  4 delta vs K7: 16501532 B, 0 fuera de kernel_size/kernel/cmdline                       OK
  TODOS LOS GATES VERDES

$ unpack_bootimg --boot_img build/bootimg/boot-ukek8.img --out …
  boot magic: ANDROID! · kernel_size: 16572290 · ramdisk size: 0 · header version: 4
  command line args: mem=2048M rdinit=/ukeinit panic=10 memmap=0x1A12800$0xE3940000 console=tty0
  fbcon=map:0 hung_task_timeout_secs=20 hung_task_panic=1 watchdog_thresh=10 console=ttyGS0,115200
  fw_devlink=permissive clk_ignore_unused pd_ignore_unused arm-smmu.disable_bypass=0
  arm_smmu.uke_smr_max=0 arm_smmu.uke_keep_boot=1 arm_smmu.uke_attach_log=2
  arm_smmu.uke_smmu_probe=1 arm_smmu.uke_reset_mask=12

$ avbtool info_image --image build/bootimg/boot-ukek8.img
  Footer version 1.0 · Image size 100663296 · Original image size 35454976 · VBMeta offset 35454976 ·
  VBMeta size 1728 · Algorithm SHA256_RSA2048 · Rollback Index 1769904000 ·
  Hash descriptor: Partition "boot", Image Size 35454976, Digest ba30b5f7…
```

Nota honesta sobre AVB: `avbtool info_image` parsea el pie sin problema (estructura intacta, igual que en
K6/K7) pero el *digest* del hash descriptor es el del contenido anterior — como en **todas** las imágenes
K1..K7 (cualquier cambio de kernel o de cmdline lo cambia). `avbtool verify_image` no es utilizable sobre
este artefacto (busca `boot.img`/vbmeta y falla **idénticamente** con `boot-ukek7.img`, que arrancó): el
gate real del proyecto sigue siendo magias + estructura + `fastboot flash` correcto, y depende de que el
dispositivo esté desbloqueado, como hasta ahora.

## 6. Escalera de disparo para hoy

**Paso 0 (antes de tocar nada, lo ejecuta el orquestador):** pre-registrar la fila **#P24** (borrador en
§9), batería ≥ 3,7 V, captura robusta viva (ttyACM0), rescate armado, `boot_b` backup `ffff8c51…` en disco,
`dtbo_b` NO se toca (s258).

**Paso 1:** `fastboot flash boot_b build/bootimg/boot-ukek8.img` + relectura del sha (2,1 s en K7).
**Paso 2:** arranque **en frío** (power físico; el #P23 ya demostró que el fastboot idle no era el
confundidor, pero el frío es el protocolo limpio).
**Paso 3:** leer consola + `dmesg | grep UKE-POKE` (si hay SSH) y clasificar con la tabla de abajo.

Migas esperadas, **en este orden** (probe real a los ~0,4449 s, sin consola todavía ⇒ todo vive en el
anillo hasta los 3,57 s):

| # | miga (literal) | cuándo |
|---|---|---|
| 1 | `UKE-POKE: uke_keep_boot=1 … / uke_attach_log=2 … / arming … uke_smmu_probe=1 / uke_reset_mask=12 …` y **`UKE-POKE: uke_handoff=1 (solo apps-smmu): 0=APAGADO…`** | parseo, 0,0x s |
| 2 | `arm_smmu_device_probe ENTRANDO` + `primer probe DIFFERIDO` | ~0,33 s |
| 3 | `apps-smmu: REINTENTO del probe` + `cfg_probe ID0/ID1/ID2` + quirk `S2CR(0xdb4)…relectura=0x000200ff` + `leyendo SMR(0..0) [uke_smr_max=0]` + `SMR loop OK (leidos=1 validos=1)` | ~0,4449 s |
| 4 | `Supported page sizes` / `Stage-1: 36-bit` / `preserved 0 boot mappings` | ídem |
| 5 | **`UKE-POKE: handoff: PREPARAR modo=1 smrs=si grupos=110 CBs=71`** | ídem |
| 6 | **`UKE-POKE: handoff: DT qcom,handoff-smrs[0] = <0x1c00 0x2>: ese SID/mask es del BL y no se escribira`** | ídem |
| 7 | **`UKE-POKE: handoff: INICIO barrido de pineo SMR(0..109) (110 grupos)…`** + `barrido SMR 0/110`, `16/110`, `32/110`… (cada 16) | ídem |
| 8 | **`UKE-POKE: handoff: PIN SMR(i) HW=0x… id=0x.. mask=0x.. [vivo del BL\|declarado en qcom,handoff-smrs] -> idx i NO ESCRIBIBLE`** (una por vivo; el idx 0 = ufshc `id=0x60` tiene que salir sí o sí) | ídem |
| 9 | **`UKE-POKE: handoff: FIN barrido: leidos=110 PINADOS=N (110 grupos)`** | ídem |
| 10 | `UKE-POKE: BL estado idx=0: SMR(0) HW=0x80000060 … S2CR(0) HW=<NO LEIDO (letal #P13)>` | ídem |
| 11 | reset: `fase1`, `fase2 OMITIDA`, `fase3 OMITIDA`, `fase4 TLBIALLH/TLBIALLNSNH`, `fase5 RMW de sCR0`, `fase6 impl->reset`, `fase7 tlb_sync_global + write sCR0` | ídem |
| 12 | `test_smr_masks OMITIDO (uke_keep_boot=1, uke_handoff=1)` | ídem |
| 13 | storm: `attach: find_sme(dev=… sid=0x… mask=0x…) -> idx` ×~57; por cada pinado **`handoff: attach: dev=… -> idx=N PINADO (vivo del BL\|handoff-smrs del DT): NO se escribe SMR/S2CR…`** y **`handoff: attach: SME idx=N PINADO (dev): se omite write_sme`**; por cada no pinado las de K5 (`attach: ESCRIBIR SME idx=…`, `write_sme idx=…`, `install_s2cr idx=…`) | 0,45→1 s |
| 14 | **`UKE-POKE: handoff: CB 69 reservado DESDE ARRIBA (start=0 num_cb=71…)`** (dominio traducido del wifi) | storm |
| 15 | `platform …: Adding to iommu group N` (≈57 + ufshc) y **desaparición** de `no IOMMU, bailing out` en el master del display | ídem |
| 16 | `Run /ukeinit as init process` (3,560963 s) + `printk: legacy console [ttyGS0] enabled` (3,572048 s) ⇒ SSH | ≥3,6 s |
| 17 | `ufshcd-qcom 1d84000.ufshc: deferred probe timeout…` (13,7998 s) + `EXT4-fs (sda32): mounted filesystem …` (15,6 s) | ≥13,8 s |

Tabla desenlace → siguiente jugada:

| desenlace observado | lectura | siguiente jugada (coste) |
|---|---|---|
| **Muerte muda ~0,44 s** (gadget USB roto full-speed/`-71`, sin ttyGS0, splash del ABL congelado, bucle de panic ~30 s) SIN ninguna miga nueva por consola | el barrido de **LECTURAS** del banco de SMR es letal (hipótesis que K2 dejó abierta, §3); el diseño "pineo por lectura" no es viable tal cual | flashear **`/var/tmp/uke-k8/boot-ukek8-h2.img`** (`uke_handoff=2`: sin barrido; pina SMR(0) + DT + CB arriba + guards). Es **repack, sin recompilar**. Si eso también muere, el asesino no es el barrido ⇒ siguiente imagen: partir `F567` en F5/F6/F7 (plan B de R1) con handoff |
| Muere **después** de `FIN barrido` y antes de `Reset`/`Adding to iommu group` (o muere mudo con la imagen h2) | el barrido de lecturas queda **exonerado**; el asesino está en el reset (fases 4-7 / sCR0) o en las escrituras del storm | (a) si hay migas: el último `write_sme`/`install_s2cr`/`CB` impreso dice el punto exacto ⇒ añadir ese punto a los guards; (b) repack con `arm_smmu.uke_reset_mask=4` (solo F4, sin RMW ni escritura de sCR0) — **repack, sin recompilar** — aislando la fase5-7 |
| Sobrevive el probe pero el UFS no llega (faltan 13,7998 s / 15,6 s, errores UFS/EXT4, o `mount` no ocurre) | el mapeo del BL preservado no es compatible con el `sCR0` reescrito (R1 §5.3) | repack con `arm_smmu.uke_reset_mask=4` (F4 solo) o `0` — **repack**; y si eso arregla el UFS pero no deja bindear, el camino es NO tocar sCR0 en absoluto (F567 off de diseño) |
| Arranca, SSH, rootfs montado, `Adding to iommu group` del mdss/dpu, sin `no IOMMU, bailing out` | **ÉXITO de K8**: la semántica "no escribir nada vivo" basta para bindear el apps-smmu | bind del DPU por sysfs **desprendido en la tablet** (`nohup sh -c 'echo … > /sys/bus/platform/drivers/msm/bind' &`, REGLA de #P12: nunca con timeout del lado del PC) → `card0` → `modetest` → foto. OJO: el SID del display está pinado (handoff), así que su traducción sigue siendo la del BL; si el DPU bindea pero el panel no pinta o hay faults del mdss, el paso siguiente es dejar que el display sea dueño de su SMR (ya sabremos su idx exacto por la miga #8) ⇒ K9 |
| Arranca pero con `SIN HUECO / CONFLICTO` (-EINVAL) en algunos maestros | el barrido reveló SMR vivos con máscaras amplias que solapan SIDs del DT (semántica mainline de `find_sme`) | es un efecto colateral esperado y **no** letal (el maestro no se attacha); se decide con la lista de PINs de la miga #8 si conviene pinear solo el handoff-DT y dejar el resto al driver (K9) |

Recordatorio operativo (R1 §6c): **NUNCA `unbind` del apps-smmu** con este kernel para "deshacer"; el
remedio es reiniciar. Los params son 0644 en caliente, pero **el barrido solo corre en un probe** ⇒ para
repetir hay que re-bindear (desprendido) o reiniciar.

## 7. Anti-regresión: por qué un arranque sin armar sigue siendo seguro

1. **El camino desarmado no ejecuta NI UNA línea de K8**: con `uke_smmu_probe=0` (o sin el token, que es el
   arranque normal de la tablet) `arm_smmu_device_probe()` devuelve `-EPROBE_DEFER` en el primer intento
   (bloque `ya_diferido`) y en los siguientes imprime "desarmado" (rate-limited) y difiere otra vez: todo
   K8 vive **después** de ese punto (en `qcom_smmu_cfg_probe` / tras `platform_set_drvdata`) o está detrás
   de `uke_pinado()`/`uke_handoff_activo()`, que con el probe nunca llegado valen `false`.
2. **Doble guarda de ámbito**: `uke_handoff != 0` **y** `uke_smmu_es_apps()` (reg = `0x15000000`). El
   kgsl-smmu (3da0000) no entra en ningún camino nuevo; `arm-smmu-qcom.c` es **byte a byte** el de K7 y su
   barrido sigue acotado por `uke_smr_max` como en K3-K7.
3. **A/B limpio**: `uke_handoff=0` deja el driver en el comportamiento K7 verificado guard a guard
   (barrido, pin, DT, CB-arriba y los 4 guards se desactivan; el único cambio observable es el print del
   `.set` del param). Sirve para descartar el código nuevo en un solo repack de cmdline.
4. **Casos límite cubiertos**: `uke_stream_match=0` ⇒ `smrs == NULL` ⇒ el barrido se salta con miga (no
   hay banco que leer) y el resto queda inerte; `uke_smr_max=-2` ⇒ el barrido de K3 se salta pero el de K8
   corre igual (es independiente a propósito: la cmdline congelada de K7 trae `uke_smr_max=0`, y atar el
   pineo a ese parámetro habría dejado el mecanismo a medias — decisión documentada aquí).
5. **Coste estructural**: `struct arm_smmu_s2cr` crece 1 byte (`bool pinned`) ⇒ 110 B por SMMU, cero
   cambios de ABI/Kconfig, `.config` idéntico y `Image` crudo del mismo tamaño que K1..K6 (41355776 B).
6. **Sin efectos en el arranque que sí usa el SMMU hoy**: `arm_smmu_rmr_install_bypass_smr()` (escritura de
   sCR0 con CLIENTPD), el quirk de qcom y `test_smr_masks` quedan como estaban (el último, omitido con
   handoff, que es *menos* acceso al HW que K7 con `uke_keep_boot`).

## 8. Riesgos residuales y siguientes pasos (honestos)

1. **El barrido completo de SMR (§3)**: único punto no medido; mitigado con la variante h2 pre-construida.
2. **CB 69**: el dominio traducido del wifi programa un CB nuevo en el índice 69. Si el BL tuviera vivo
   justo ése (no medido; el único viniente visto es el 22), podría morir ahí. Mitigación natural: el
   barrido **no** puede leer los CB (leer S2CR mata), así que "desde arriba" es la mejor aproximación
   disponible; si el desenlace fuera "muere tras CB 69 reservado", el paso siguiente es reservar además
   los CB altos como *bypass* (plan I de R4) o no crear dominio traducido para el wifi.
3. **El display queda "sin traducir por ahora"** (su SMR pinado): el bind del mdss/DPU debería ocurrir
   (el grupo se crea), pero su DMA seguirá con el mapeo del BL. Es el precio de la primera fase; el idx
   exacto que la miga #8 revele es la información que faltaba para el K9 (reescritura dirigida de ESE SMR
   cuando ya no haya tráfico del BL).
4. **`-EINVAL` por solape de máscaras** en maestros no-display (efecto colateral mainline, no letal).
5. **Queda pendiente del proyecto** (no lo resuelve K8): `e2fsck` en frío del ext4 podrido, y la regla de
   no unbind. La geometría del DT (`tcu-base` perdido en el overlay A′, #P21) no la toca K8.

---

## 9. Fila de pre-registro propuesta (#P24) y cierre

> **#P24 — K8 (handoff: pineo de SMR vivos + `qcom,handoff-smrs` + CB desde arriba)** · artefacto
> `build/bootimg/boot-ukek8.img` · sha256 `5e34596a230d2d645ad8dcc68dcba5c23bc58bf2a6c6468a526a66bb687d54e2`
> (100663296 B; `kernel_size`@8 = 16572290; cmdline = la de K7 byte a byte, 382 B) · kernel `#10`
> (Tue Sep 29 10:59:39 CEST 2026), Image.gz `fad9a160…`, Image crudo `ae4485db…` (41355776 B, delta 0 vs K6)
> · **canal**: `fastboot flash boot_b` (dtbo_b NO se toca: s258) + **arranque en frío** · **evidencia de
> éxito**: sobrevive + consola/SSH ≥3,6 s con la traza de §6 (en especial `handoff: FIN barrido: leidos=110
> PINADOS=N`, los `PINADO` del attach, `Adding to iommu group` del ufshc y ausencia de `no IOMMU, bailing
> out`), `EXT4-fs (sda32): mounted` ~15,6 s y `card0` tras el bind del DPU · **evidencia de muerte temprana**:
> USB roto full-speed/`-71`, sin ttyGS0, splash congelado, bucle de panic ~30 s (firma de #P17/#P22/#P23) ⇒
> leer foto del panel (LAST-POKE) · **rollback**: `fastboot flash boot_b build/backup-par-bueno/boot_b-lee.img`
> (`ffff8c51…`) + baile de slots · **alternativas ya empaquetadas**: `uke_handoff=2` (imagen
> `4833e038…` en `/var/tmp/uke-k8/boot-ukek8-h2.img`) y repacks de `uke_reset_mask=4`/`0` (§6) ·
> **gates**: los de §4/§5 (rc=0 idempotente, 8 params en `__param`, payload verificado, AVB parseable) ·
> **recordatorio**: NO hacer `unbind` del apps-smmu (bug ALTA cerrado en K8, pero el estado del HW no se
> puede restaurar por software).

Cierre: K8 es **K7 + el port del handoff** (vía H de R4), compilado desde cero en arena propia, con la
cmdline de K7 intacta. Es la primera imagen del proyecto que (a) conoce los mapeos vivos del bootloader
en vez de adivinarlos, (b) tiene prohibido por código escribir o liberar un índice vivo, y (c) reparte los
CB al revés para no pisar los del firmware. Si el desenlace es la muerte muda a 0,44 s, el propio
experimento contesta la única pregunta que quedaba abierta desde K2 (¿es la *lectura* del banco o la
*escritura* de un registro vivo?) y la siguiente jugada ya está en disco, sin recompilar.

## Anexo A — Fragmentos del lineage citados (URLs verificadas hoy)

1. **Kernel Android del SoC (SM8635/cliffs, lineage-23.0)** —
   `https://github.com/Xiaomi-Pad-7-Pro-Resources/android_kernel_xiaomi_sm8635` →
   `drivers/iommu/arm/arm-smmu/arm-smmu.c` (raw lineage-23.0, descargado: `/var/tmp/uke-k8/ref/xiaomi-arm-smmu.c`).
   * `arm_smmu_handoff_cbs()` en `:3016-3119` (DT, subset test `:3082-3083`, `pinned` + reserva de CB
     `:3091-3100`), llamado desde `arm_smmu_device_probe()` en `:3671`.
   * `__arm_smmu_alloc_cb()` en `:390-406` (devuelve el `cbndx` del SMR pinado).
   * `arm_smmu_free_sme()` en `:1778-1796` y `arm_smmu_destroy_domain_context()` en `:1568-1614`
     (respetan `pinned`).
   * `arm_smmu_domain_add_master()` en `:1885-1913` (`continue` si tipo y `cbndx` coinciden ⇒ no reescribe
     el S2CR del BL).
   * `struct arm_smmu_s2cr { … bool pinned; }` en `arm-smmu.h:339-346`; `ARM_SMMU_OPT_MULTI_MATCH_HANDOFF_SMR`
     y su propiedad (`qcom,multi-match-handoff-smr`) en `:100` / `arm-smmu.h:384`.
2. **CodeLinaro le_kernel_msm-5.15** (espejo BSP; historia del parche):
   `…/commit/8fa3cecff06e7aeba00e0f463714c4ad09dcca30` ("use smr match for handoff-smrs") y
   `…/commit/18d1a0b7a412ee821aa92f0dc2e54ced8bb79611` ("Correct the index for handoff smrs").
3. **DT del aparato**: `qcom,handoff-smrs = <0x1c00 0x02>` verificado en el DT efectivo (#P21,
   `/var/tmp/k8-check/merged.dtb`) y en el stock (`~/gpu-work/w15-dt/stockuke.dts:13186`).

## Anexo B — Diff completo (`k8-handoff.diff`, contra el árbol K7)

```diff
--- a/drivers/iommu/arm/arm-smmu/arm-smmu.h
+++ b/drivers/iommu/arm/arm-smmu/arm-smmu.h
@@ -277,6 +277,26 @@
 	enum arm_smmu_s2cr_type		type;
 	enum arm_smmu_s2cr_privcfg	privcfg;
 	u8				cbndx;
+	/*
+	 * UKE-SMMU-K8 (K8): mapeo de stream DEL BOOTLOADER que Linux no debe
+	 * tocar NUNCA (ni SMR ni S2CR ni su CB). Portado del kernel Android del
+	 * SM8635/cliffs (lineage-23.0; CodeLinaro le_kernel_msm-5.15 @8fa3cef):
+	 * `struct arm_smmu_s2cr { ... bool pinned; }` (arm-smmu.h:339-346), que
+	 * solo pone a true arm_smmu_handoff_cbs() (arm-smmu.c:3099) y que
+	 * respetan arm_smmu_free_sme() (:1787) y
+	 * arm_smmu_destroy_domain_context() (:1604-1611).
+	 *
+	 * Aqui es el UNICO estado que decide "no escribir": lo consultan los
+	 * guards de arm_smmu_write_smr/write_s2cr/write_sme y arm_smmu_free_sme.
+	 *
+	 * Diferencia deliberada con el lineage (R1 #P13 / R4 §2.1): el vendor, al
+	 * pinear, LEE S2CR(i) para copiar type/privcfg/cbndx del bootloader. En
+	 * esta tablet leer el S2CR de un indice vivo MATA (medido #P13), asi que
+	 * cbndx queda DESCONOCIDO a proposito y el CB del BL no se reutiliza:
+	 * los CB de dominios nuevos se reservan desde ARRIBA
+	 * (uke_alloc_cb_arriba) para no pisarlos.
+	 */
+	bool				pinned;
 };
 
 struct arm_smmu_smr {
--- a/drivers/iommu/arm/arm-smmu/arm-smmu.c
+++ b/drivers/iommu/arm/arm-smmu/arm-smmu.c
@@ -511,6 +511,282 @@
 	pr_flush(500, false);
 }
 
+/*
+ * ==========================================================================
+ * UKE-SMMU-K8 (29-sep-2026): PORT DEL MECANISMO DE HANDOFF (via H de R4).
+ * ==========================================================================
+ *
+ * POR QUE. El mapa de minas medido (#P8-#P23) dice, sin excepcion, una cosa:
+ * el probe del apps-smmu sobrevive a TODO (IDR0/1/2, quirk del bypass, reset
+ * con las fases 4-7) mientras no toque un registro VIVO del bootloader; y
+ * muere (wedge duro, mudo, sin panic) en cuanto LEE el S2CR de un indice vivo
+ * (#P13) o ESCRIBE un SMR/S2CR/CB que el BL tiene en uso (#P14 CB22, #P15
+ * fase3, K4c write_sme idx=1). K7 (armado por cmdline, ventana de 0,4449 s)
+ * murio igual: #P17/#P22/#P23 refutan la hipotesis temporal ⇒ el asesino es
+ * ESTRUCTURAL. La preservacion manual de K4-K7 solo cubria el idx 0
+ * (uke_smr_max=0 deja ciegos los idx 1..109, que find_sme reparte como
+ * "libres" y el attach del storm PISA).
+ *
+ * QUE HACE K8 (diseno consolidado en #P21; codigo de referencia: kernel
+ * Android del SM8635/cliffs lineage-23.0 y CodeLinaro le_kernel_msm-5.15
+ * @8fa3cef, descargado y leido en /var/tmp/uke-k8/ref/):
+ *
+ *   1. BARRIDO DE PINEO (uke_handoff_pin_sweep): tras cfg_probe y ANTES del
+ *      reset, LEE SMR(0..num_mapping_groups-1) (lectura medida segura: #P9 y
+ *      cuatro runs mas leyeron SMR(0) sin morir; la lectura letal es la del
+ *      S2CR, #P13) y marca `s2crs[i].pinned = true` en toda entrada con
+ *      VALID=1. A partir de ahi NINGUN codigo puede escribir ni reasignar ese
+ *      idx: los guards viven en los tres puntos de escritura
+ *      (arm_smmu_write_smr, arm_smmu_write_s2cr y arm_smmu_write_sme), en el
+ *      reparto de indices (arm_smmu_find_sme no reutiliza lo valido) y en el
+ *      liberador (arm_smmu_free_sme), que es el bug ALTA de R1 §7.1
+ *      (arm-smmu.c:1752-1765: arm_smmu_master_free_smes escribia el SME
+ *      liberado SIN guarda ⇒ un unbind del ufshc pisaba S2CR(0)).
+ *
+ *   2. qcom,handoff-smrs DEL DT (uke_handoff_parse_dt): pares <id mask> que el
+ *      DT declara como mapeos del firmware. Nuestro DT efectivo lo trae
+ *      (<0x1c00 0x02>, el SID del mdss/display; verificado #P21 sobre
+ *      /var/tmp/k8-check/merged.dtb). Un maestro cuyo fwpec es subconjunto de
+ *      un par (mismo test que el lineage: ver uke_handoff_es_dt) se PINa y no
+ *      se le escribe ni SMR ni S2CR: el maestro sigue con lo que dejo el BL y
+ *      el dominio queda "sin traducir por ahora" (miga explicita). Es el
+ *      handoff dirigido por DT del vendor, sin necesidad de leer S2CR.
+ *
+ *   3. CB DESDE ARRIBA (uke_alloc_cb_arriba): el lineage reutiliza el CB del
+ *      BL porque puede leer su cbndx del S2CR; aqui ese cbndx es ilegible
+ *      (leerlo mata), asi que los CB de dominios NUEVOS se reservan desde
+ *      num_context_banks-1 hacia abajo (70→0). El BL llena desde abajo (su
+ *      unico SMR visto en 7 runs es el idx 0 = ufshc; #P14 midio su CB vivo en
+ *      el 22), de modo que repartir desde arriba es la mejor aproximacion a
+ *      "no pisar lo vivo" sin poder leerlo. El CB 70 ya lo reserva el quirk
+ *      bypass (set_bit en qcom_smmu_cfg_probe), asi que el primer dominio
+ *      nuevo cae en el 69.
+ *
+ *   4. NUNCA SE LEE S2CR (ni en el barrido ni en el attach): type/privcfg/
+ *      cbndx de un indice pinado quedan DESCONOCIDOS a proposito y ningun
+ *      camino de K8 los necesita, porque de ese idx no se escribe nada.
+ *
+ * QUE NO CAMBIA: la cmdline (uke_smr_max=0, uke_keep_boot=1, uke_attach_log=2,
+ * uke_smmu_probe=1, uke_reset_mask=12), las fases del reset, el arranque
+ * DESARMADO (uke_smmu_probe=0 ⇒ -EPROBE_DEFER antes de tocar nada, identico a
+ * K6/K7) y el comportamiento de cualquier otro SMMU (kgsl): todo K8 esta tras
+ * uke_smmu_es_apps() + uke_handoff.
+ *
+ * PARAMETRO NUEVO `uke_handoff` (solo apps-smmu; default 1):
+ *   0 = APAGADO: todo el codigo K8 se comporta como K7 (A/B limpio).
+ *   1 = COMPLETO (default): barrido de pineo 0..109 + DT + CB desde arriba.
+ *   2 = SIN BARRIDO: no lee NINGUN SMR nuevo; solo pina lo que la RAM ya sabe
+ *       vivo (el barrido acotado de K3 con uke_smr_max) + el DT + CB desde
+ *       arriba. Es la escalera de rescate SIN recompilar: si el barrido
+ *       completo resultase letal en la tablet (K2 murio dentro del barrido de
+ *       LECTURAS y ese punto nunca se aclaro con consola), la siguiente imagen
+ *       es un repack de cmdline con `arm_smmu.uke_handoff=2`.
+ */
+static int uke_handoff = 1;
+
+static int uke_handoff_set(const char *val, const struct kernel_param *kp)
+{
+	int ret = param_set_int(val, kp);
+
+	if (ret)
+		return ret;
+	pr_info("UKE-POKE: uke_handoff=%d (solo apps-smmu): 0=APAGADO (comportamiento K7); 1=BARRIDO COMPLETO de SMR vivos + qcom,handoff-smrs del DT + CB desde arriba + nada pinado se escribe; 2=SIN BARRIDO (solo lo que la RAM ya sabe vivo + DT)\n",
+		uke_handoff);
+	return 0;
+}
+
+static const struct kernel_param_ops uke_handoff_ops = {
+	.set	= uke_handoff_set,
+	.get	= param_get_int,
+};
+
+module_param_cb(uke_handoff, &uke_handoff_ops, &uke_handoff, 0644);
+MODULE_PARM_DESC(uke_handoff,
+	"UKE (K8): 0=apagado (K7); 1 (defecto)=handoff completo (barrido de SMR vivos + qcom,handoff-smrs + CB desde arriba); 2=sin barrido de SMR (solo lo que la RAM ya sabe vivo + el DT). Solo apps-smmu (0x15000000).");
+
+/* Pares <id, mask> de qcom,handoff-smrs del DT (el vendor declara 1; 8 sobra). */
+static struct {
+	u16	id;
+	u16	mask;
+} uke_handoff_dt[8];
+static unsigned int uke_handoff_dt_n;
+
+/* ¿Aplica el mecanismo K8 a este SMMU? (solo apps-smmu y con uke_handoff != 0) */
+static bool uke_handoff_activo(struct arm_smmu_device *smmu)
+{
+	return uke_handoff != 0 && smmu->dev && smmu->dev->of_node &&
+	       uke_smmu_es_apps(smmu);
+}
+
+/* ¿Este idx es un mapeo del firmware que NUNCA se puede escribir ni liberar? */
+static bool uke_pinado(struct arm_smmu_device *smmu, int idx)
+{
+	if (!uke_handoff_activo(smmu))
+		return false;
+	if (idx < 0 || (unsigned int)idx >= smmu->num_mapping_groups)
+		return false;
+	return smmu->s2crs[idx].pinned;
+}
+
+/*
+ * Test de subconjunto del vendor (literal de arm_smmu_handoff_cbs(),
+ * ref/xiaomi-arm-smmu.c:3082-3083 y commit CodeLinaro 8fa3cef "arm-smmu: use
+ * smr match for handoff-smrs"): un SMR/fwpec es "handoff" si TODO lo que exige
+ * cabe dentro del par declarado en el DT.
+ *   (hand.mask & x.mask) == x.mask   -> la mascara del DT cubre la del SMR
+ *   !((hand.id ^ x.id) & ~hand.mask) -> los bits fijos del ID coinciden
+ * El commit cambio de comparar por INDICE de SMR a comparar por id/mask
+ * justamente porque el indice "could mismatch between ABL and HLOS".
+ */
+static bool uke_handoff_es_dt(u16 id, u16 mask)
+{
+	unsigned int i;
+
+	for (i = 0; i < uke_handoff_dt_n; i++) {
+		u16 hid = uke_handoff_dt[i].id;
+		u16 hmask = uke_handoff_dt[i].mask;
+
+		if ((hmask & mask) == mask && !((hid ^ id) & ~hmask))
+			return true;
+	}
+	return false;
+}
+
+static void uke_handoff_parse_dt(struct arm_smmu_device *smmu)
+{
+	struct device_node *np = smmu->dev->of_node;
+	u32 id, mask;
+	int n, i;
+
+	uke_handoff_dt_n = 0;
+	if (!np)
+		return;
+
+	n = of_property_count_elems_of_size(np, "qcom,handoff-smrs",
+					    sizeof(u32) * 2);
+	if (n <= 0) {
+		pr_info("UKE-POKE: handoff: DT sin qcom,handoff-smrs (o mal formada): 0 pares; el pineo queda solo en manos del barrido\n");
+		return;
+	}
+	if (n > (int)ARRAY_SIZE(uke_handoff_dt))
+		n = (int)ARRAY_SIZE(uke_handoff_dt);
+
+	for (i = 0; i < n; i++) {
+		if (of_property_read_u32_index(np, "qcom,handoff-smrs", 2 * i, &id) ||
+		    of_property_read_u32_index(np, "qcom,handoff-smrs", 2 * i + 1, &mask)) {
+			pr_warn("UKE-POKE: handoff: no se pudo leer el par %d de qcom,handoff-smrs; se corta\n",
+				i);
+			break;
+		}
+		uke_handoff_dt[i].id = (u16)id;
+		uke_handoff_dt[i].mask = (u16)mask;
+		uke_handoff_dt_n = i + 1;
+		pr_info("UKE-POKE: handoff: DT qcom,handoff-smrs[%u] = <0x%x 0x%x>: ese SID/mask es del BL y no se escribira\n",
+			uke_handoff_dt_n - 1, id, mask);
+	}
+}
+
+/*
+ * BARRIDO DE PINEO. Es el corazon de K8 y la unica lectura nueva que hace:
+ * SMR(0..num_mapping_groups-1) con una miga por cada entrada VIVA (las
+ * decisiones) y una miga de progreso cada 16 indices (para poder localizar un
+ * atasco blando, como el de #P10, si lo hubiera).
+ *
+ * Lo que NO se hace: leer S2CR (letal #P13), escribir nada, ni tocar
+ * smmu->smrs[]/s2crs[] mas alla del bit `pinned` (la copia RAM del SMR se deja
+ * tal cual, que es la del BL).
+ */
+static void uke_handoff_pin_sweep(struct arm_smmu_device *smmu)
+{
+	unsigned int n_pin = 0, n_leidos = 0;
+	int i;
+
+	if (!smmu->smrs) {
+		pr_info("UKE-POKE: handoff: smrs==NULL (stream indexing forzado): sin banco de SMR que pinear; solo actuara el DT y el CB desde arriba\n");
+		return;
+	}
+
+	if (uke_handoff >= 2) {
+		for (i = 0; i < (int)smmu->num_mapping_groups; i++) {
+			if (!smmu->smrs[i].valid)
+				continue;
+			smmu->s2crs[i].pinned = true;
+			n_pin++;
+			pr_info("UKE-POKE: handoff: PIN SMR(%d) id=0x%x mask=0x%x (vivo segun la RAM; modo 2 SIN barrido) -> idx NO ESCRIBIBLE\n",
+				i, smmu->smrs[i].id, smmu->smrs[i].mask);
+		}
+		pr_info("UKE-POKE: handoff: modo 2 (sin barrido): PINADOS=%u de %u grupos; no se leyo ningun SMR nuevo\n",
+			n_pin, smmu->num_mapping_groups);
+		pr_flush(500, false);
+		return;
+	}
+
+	pr_info("UKE-POKE: handoff: INICIO barrido de pineo SMR(0..%u) (%u grupos). Solo LECTURAS de SMR (medidas seguras, #P9); el S2CR de un indice vivo NO se lee (letal #P13)\n",
+		smmu->num_mapping_groups - 1, smmu->num_mapping_groups);
+	for (i = 0; i < (int)smmu->num_mapping_groups; i++) {
+		u32 smr;
+
+		if (!(i & 15))
+			pr_info("UKE-POKE: handoff: barrido SMR %d/%u ...\n",
+				i, smmu->num_mapping_groups);
+		smr = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_SMR(i));
+		n_leidos++;
+		if (!FIELD_GET(ARM_SMMU_SMR_VALID, smr))
+			continue;
+
+		smmu->s2crs[i].pinned = true;
+		n_pin++;
+		pr_info("UKE-POKE: handoff: PIN SMR(%d) HW=0x%08x id=0x%x mask=0x%x%s -> idx %d NO ESCRIBIBLE (ni SMR ni S2CR ni CB)\n",
+			i, smr, (unsigned int)FIELD_GET(ARM_SMMU_SMR_ID, smr),
+			(unsigned int)uke_smr_mask_leido(smr),
+			uke_handoff_es_dt((u16)FIELD_GET(ARM_SMMU_SMR_ID, smr),
+					  (u16)uke_smr_mask_leido(smr)) ?
+				" [declarado en qcom,handoff-smrs]" : " [vivo del BL]",
+			i);
+	}
+	pr_info("UKE-POKE: handoff: FIN barrido: leidos=%u PINADOS=%u (%u grupos). Desde aqui ni el reset ni el attach escriben esos indices\n",
+		n_leidos, n_pin, smmu->num_mapping_groups);
+	pr_flush(500, false);
+}
+
+static void uke_handoff_preparar(struct arm_smmu_device *smmu)
+{
+	if (!uke_handoff_activo(smmu))
+		return;
+	pr_info("UKE-POKE: handoff: PREPARAR modo=%d smrs=%s grupos=%u CBs=%u (K8: nada pinado se escribe; los CB nuevos se reparten desde arriba)\n",
+		uke_handoff, smmu->smrs ? "si" : "NULL",
+		smmu->num_mapping_groups, smmu->num_context_banks);
+	uke_handoff_parse_dt(smmu);
+	uke_handoff_pin_sweep(smmu);
+}
+
+/*
+ * Reserva de CB DESDE ARRIBA (num_context_banks-1 → start). Equivalente
+ * invertido de __arm_smmu_alloc_bitmap() y sustituto del truco del lineage
+ * (__arm_smmu_alloc_cb(), ref/xiaomi-arm-smmu.c:390-406: devuelve el cbndx del
+ * S2CR del BL porque puede leerlo; y arm_smmu_handoff_cbs() reserva ese CB con
+ * `bitmap_set(smmu->context_map, smmu->s2crs[i].cbndx, 1)`, :3100). Aqui el
+ * cbndx del BL es ilegible, asi que la proteccion es "no repartir nunca los
+ * CBs bajos, que son los que el BL usa" (#P14: CB22 vivo; el unico SMR vivo
+ * del BL esta en el idx 0, o sea que el BL llena desde abajo).
+ */
+static int uke_alloc_cb_arriba(struct arm_smmu_device *smmu, unsigned int start)
+{
+	int idx;
+
+	for (idx = (int)smmu->num_context_banks - 1; idx >= (int)start; idx--) {
+		if (test_and_set_bit(idx, smmu->context_map))
+			continue;	/* ya reservado (p. ej. bypass_cbndx=70) */
+		pr_info("UKE-POKE: handoff: CB %d reservado DESDE ARRIBA (start=%u num_cb=%u; evita los CB vivos del BL, cbndx ilegible)\n",
+			idx, start, smmu->num_context_banks);
+		pr_flush(500, false);
+		return idx;
+	}
+	pr_warn("UKE-POKE: handoff: NO hay CB libre desde arriba (start=%u num_cb=%u): -ENOSPC como mainline\n",
+		start, smmu->num_context_banks);
+	return -ENOSPC;
+}
+
 static inline int arm_smmu_rpm_get(struct arm_smmu_device *smmu)
 {
 	if (pm_runtime_enabled(smmu->dev))
@@ -1132,6 +1408,18 @@
 	if (smmu->impl && smmu->impl->alloc_context_bank)
 		return smmu->impl->alloc_context_bank(smmu_domain, smmu, dev, start);
 
+	/*
+	 * UKE-SMMU-K8: con handoff, los CB de dominios NUEVOS se reparten desde
+	 * ARRIBA (70 -> start) en vez de 0 -> 71, para no pisar los CB que el BL
+	 * tiene vivos (su cbndx es ilegible: leer el S2CR de un indice vivo
+	 * MATA, #P13; el CB22 se midio vivo en #P14). El CB 70 ya esta reservado
+	 * por el quirk del bypass. Contrapartida del lineage: alli se puede
+	 * reutilizar el CB del BL porque __arm_smmu_alloc_cb() LEE su cbndx
+	 * (ref/xiaomi-arm-smmu.c:390-406); aqui no se puede.
+	 */
+	if (uke_handoff_activo(smmu))
+		return uke_alloc_cb_arriba(smmu, start);
+
 	return __arm_smmu_alloc_bitmap(smmu->context_map, start, smmu->num_context_banks);
 }
 
@@ -1419,6 +1707,18 @@
 	u32 reg = FIELD_PREP(ARM_SMMU_SMR_ID, smr->id) |
 		  FIELD_PREP(ARM_SMMU_SMR_MASK, smr->mask);
 
+	/*
+	 * UKE-SMMU-K8: un indice PINADO es un mapeo del bootloader y no se
+	 * escribe JAMAS. Guard de ultimo recurso: cubre el reset fase2, el
+	 * attach, el liberador y cualquier llamante futuro. Escribir un SMR
+	 * vivo mata (medido #P14/#P15/#P17).
+	 */
+	if (uke_pinado(smmu, idx)) {
+		pr_info("UKE-POKE: handoff: ESCRITURA BLOQUEADA write_smr idx=%d: el SMR es de un mapeo del BL (pinado) y no se toca\n",
+			idx);
+		return;
+	}
+
 	if (!(smmu->features & ARM_SMMU_FEAT_EXIDS) && smr->valid)
 		reg |= ARM_SMMU_SMR_VALID;
 	arm_smmu_gr0_write(smmu, ARM_SMMU_GR0_SMR(idx), reg);
@@ -1429,6 +1729,17 @@
 	struct arm_smmu_s2cr *s2cr = smmu->s2crs + idx;
 	u32 reg;
 
+	/*
+	 * UKE-SMMU-K8: el S2CR de un indice pinado es la traduccion VIVA del
+	 * bootloader: no se escribe nunca (aqui es donde el storm del attach
+	 * mataba a K4c, write_sme idx=1).
+	 */
+	if (uke_pinado(smmu, idx)) {
+		pr_info("UKE-POKE: handoff: ESCRITURA BLOQUEADA write_s2cr idx=%d: el S2CR es de un mapeo del BL (pinado) y no se toca\n",
+			idx);
+		return;
+	}
+
 	if (smmu->impl && smmu->impl->write_s2cr) {
 		smmu->impl->write_s2cr(smmu, idx);
 		return;
@@ -1447,6 +1758,17 @@
 static void arm_smmu_write_sme(struct arm_smmu_device *smmu, int idx)
 {
 	/*
+	 * UKE-SMMU-K8: si el idx esta PINADO no se escribe ni SMR ni S2CR. Se
+	 * corta aqui (antes de las migas de K4/K5) para que la ultima linea del
+	 * log sea la causa y no los valores que se iban a escribir.
+	 */
+	if (uke_pinado(smmu, idx)) {
+		pr_info("UKE-POKE: handoff: ESCRITURA BLOQUEADA write_sme idx=%d: SMR+S2CR pinados (del BL); no se escribe ninguno\n",
+			idx);
+		return;
+	}
+
+	/*
 	 * UKE-SMMU-CLK (K4): miga ANTES de escribir el SME, solo para el apps-smmu.
 	 * Si la consola enmudece durante el reset fase2 o durante el attach del
 	 * display (arm_smmu_master_alloc_smes), esta linea dice el indice exacto, el
@@ -1491,8 +1813,9 @@
 	 * el mdss (mask 0x02) se rechazaria con -EINVAL y no habria attach que
 	 * medir. streamid_mask se queda con el valor derivado de ID0 (0x7fff).
 	 */
-	if (uke_keep_boot && uke_smmu_es_apps(smmu)) {
-		pr_info("UKE-POKE: test_smr_masks OMITIDO (uke_keep_boot=1): sin leer ni escribir SMR; streamid_mask=0x%x smr_mask_mask=0x%x (campo completo, no medido)\n",
+	if ((uke_keep_boot || uke_handoff_activo(smmu)) && uke_smmu_es_apps(smmu)) {
+		pr_info("UKE-POKE: test_smr_masks OMITIDO (uke_keep_boot=%d, uke_handoff=%d): sin leer ni escribir SMR; streamid_mask=0x%x smr_mask_mask=0x%x (campo completo, no medido)\n",
+			uke_keep_boot ? 1 : 0, uke_handoff,
 			smmu->streamid_mask,
 			(unsigned int)FIELD_GET(ARM_SMMU_SMR_MASK, (u32)~0));
 		smmu->smr_mask_mask = FIELD_GET(ARM_SMMU_SMR_MASK, (u32)~0);
@@ -1577,6 +1900,27 @@
 
 static bool arm_smmu_free_sme(struct arm_smmu_device *smmu, int idx)
 {
+	/*
+	 * UKE-SMMU-K8: CIERRA EL BUG ALTA de R1 §7.1. Mainline (y K1..K7)
+	 * reseteaba aqui la entrada y devolvia true, y el llamante
+	 * arm_smmu_master_free_smes() ESCRIBIA el SME con BYPASS/FAULT: un
+	 * release/unbind de un maestro cuyo SME es del BL PISABA el mapeo vivo
+	 * (p. ej. el del UFS) y podia matar la tablet. Con K8 el idx pinado no
+	 * se libera, no se invalida en RAM y no se escribe: devolver false hace
+	 * que el llamante NO llame a arm_smmu_write_sme.
+	 * Cita del lineage: arm_smmu_free_sme(), ref/xiaomi-arm-smmu.c:1778-1796
+	 * (`bool pinned = smmu->s2crs[idx].pinned; ... if (pinned) { ... }`);
+	 * aqui es mas estricto (el lineage conserva pinned/cbndx pero sigue
+	 * devolviendo true y reescribiendo el SME).
+	 */
+	if (uke_pinado(smmu, idx)) {
+		if (--smmu->s2crs[idx].count < 0)
+			smmu->s2crs[idx].count = 0;
+		pr_info("UKE-POKE: handoff: free_sme idx=%d PINADO: no se libera ni se invalida ni se escribe (mapeo del BL intacto)\n",
+			idx);
+		return false;
+	}
+
 	if (--smmu->s2crs[idx].count)
 		return false;
 
@@ -1634,6 +1978,42 @@
 		idx = ret;
 
 		/*
+		 * UKE-SMMU-K8: HANDOFF por indice y por DT. Si find_sme ha
+		 * devuelto un indice PINADO, este maestro hereda el mapeo del
+		 * bootloader: se reclama en RAM (count++/smendx) pero NO se le
+		 * escribe ni SMR ni S2CR, y el dominio queda "SIN traducir por
+		 * ahora" (el HW sigue como lo dejo el BL). Si ademas el fwpec del
+		 * maestro es un handoff declarado en el DT, el indice se pina
+		 * aunque el BL no lo tuviera vivo: esa banda de SIDs es del
+		 * firmware y Linux no la escribe (misma semantica que
+		 * arm_smmu_handoff_cbs() del lineage, pero sin leer S2CR).
+		 */
+		if (uke_handoff_activo(smmu)) {
+			if (uke_handoff_es_dt(sid, mask) && !uke_pinado(smmu, idx)) {
+				smmu->s2crs[idx].pinned = true;
+				pr_info("UKE-POKE: handoff: attach: dev=%s sid=0x%x mask=0x%x es qcom,handoff-smrs del DT; idx=%d PINADO sin estar vivo (no se escribira)\n",
+					dev_name(dev), sid, mask, idx);
+			}
+			if (uke_pinado(smmu, idx)) {
+				if (smrs && !smmu->smrs[idx].valid) {
+					/* reserva logica: idx ocupado en RAM, HW intacto */
+					smrs[idx].id = sid;
+					smrs[idx].mask = mask;
+					smrs[idx].valid = true;
+				}
+				/* OJO: si ya estaba vivo, la copia RAM del SMR es la del
+				 * BL y NO se sobrescribe (se deja COMO ESTA). */
+				smmu->s2crs[idx].count++;
+				cfg->smendx[i] = (s16)idx;
+				pr_info("UKE-POKE: handoff: attach: dev=%s sid=0x%x mask=0x%x -> idx=%d PINADO (%s): NO se escribe SMR/S2CR; el maestro sigue con el mapeo del BL y el dominio queda SIN traducir por ahora\n",
+					dev_name(dev), sid, mask, idx,
+					uke_handoff_es_dt(sid, mask) ? "handoff-smrs del DT" : "vivo del BL");
+				pr_flush(500, false);
+				continue;
+			}
+		}
+
+		/*
 		 * UKE-SMMU-CLK (K5): ¿este idx es un SME VIVO del bootloader? Solo el
 		 * apps-smmu, y solo si el barrido lo dejo en RAM (smrs[idx].valid) y
 		 * ningun maestro lo ha reclamado (count==0). Con uke_smr_max=0 eso es
@@ -1684,6 +2064,15 @@
 	/* It worked! Now, poke the actual hardware */
 	for_each_cfg_sme(cfg, fwspec, i, idx) {
 		/*
+		 * UKE-SMMU-K8: si el idx esta PINADO (mapeo vivo del BL o SID
+		 * declarado en qcom,handoff-smrs) no se toca el HW.
+		 */
+		if (uke_pinado(smmu, idx)) {
+			pr_info("UKE-POKE: handoff: attach: SME idx=%d PINADO (%s): se omite write_sme (SMR/S2CR del BL intactos)\n",
+				idx, dev_name(dev));
+			continue;
+		}
+		/*
 		 * UKE-SMMU-CLK (K5): si este SME se PRESERVO (uke_attach_log=2) no se
 		 * toca el HW: el mapeo del bootloader sigue siendo el que traduce.
 		 */
@@ -1720,7 +2109,14 @@
 				pr_info("UKE-POKE: attach: ESCRIBIR SME idx=%d dev=%s -> S2CR nominal=0x%08x (type=%u cbndx=%u) (smrs==NULL)\n",
 					idx, dev_name(dev), uke_s2cr_val(smmu, idx),
 					smmu->s2crs[idx].type, smmu->s2crs[idx].cbndx);
-			if (idx == 0) {
+			/*
+			 * UKE-SMMU-K8: S2CR(0) solo se lee si el idx 0 NO esta
+			 * pinado. Con handoff el idx 0 es el SMR vivo del ufshc y
+			 * este bloque no se alcanza (el guard de arriba ya ha
+			 * saltado), pero la condicion lo hace explicito: leer el
+			 * S2CR de un mapeo vivo MATA (#P13).
+			 */
+			if (idx == 0 && !uke_pinado(smmu, idx)) {
 				u32 hw_smr = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_SMR(0));
 				u32 hw_s2cr = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_S2CR(0));
 
@@ -1774,6 +2170,17 @@
 
 	for_each_cfg_sme(cfg, fwspec, i, idx) {
 		/*
+		 * UKE-SMMU-K8: el attach del dominio escribe S2CR para pasar al
+		 * maestro a TRANS->CB; sobre un idx pinado eso destruiria la
+		 * traduccion del BL (es el mismo asesino que en master_alloc_smes,
+		 * pero en la fase de iommu_setup_default_domain). No se escribe.
+		 */
+		if (uke_pinado(smmu, idx)) {
+			pr_info("UKE-POKE: handoff: attach: install_s2cr idx=%d PINADO: NO se escribe el S2CR (el HW sigue con el mapeo del BL; dominio SIN traducir por ahora)\n",
+				idx);
+			continue;
+		}
+		/*
 		 * UKE-SMMU-CLK (K5): un indice PRESERVADO (uke_attach_log=2) no se
 		 * toca NI en install_s2crs: el attach del dominio escribe S2CR para
 		 * pasar el maestro a TRANS->CB, y eso destruiria el mapeo del BL
@@ -1805,7 +2212,7 @@
 				(unsigned int)(FIELD_PREP(ARM_SMMU_S2CR_TYPE, type) |
 				FIELD_PREP(ARM_SMMU_S2CR_CBNDX, cbndx) |
 				FIELD_PREP(ARM_SMMU_S2CR_PRIVCFG, S2CR_PRIVCFG_DEFAULT)));
-			if (idx == 0) {	/* unica lectura de S2CR medida como segura */
+			if (idx == 0 && !uke_pinado(smmu, idx)) {	/* unica lectura de S2CR medida como segura; nunca sobre un idx pinado (#P13) */
 				u32 hw = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_S2CR(0));
 
 				pr_info("UKE-POKE: attach: install_s2cr idx=0 S2CR(0) HW AHORA=0x%08x (TYPE=%u CBNDX=%u)\n",
@@ -3068,6 +3475,15 @@
 
 	platform_set_drvdata(pdev, smmu);
 
+	/*
+	 * UKE-SMMU-K8: HANDOFF. Se hace AQUI y no antes: cfg_probe ya ha leido
+	 * IDR0/1/2, ha hecho el quirk y ha repartido smrs[]/s2crs[]; y se hace
+	 * ANTES del primer acceso que escribe algo (rmr_install_bypass_smr
+	 * escribe sCR0 con CLIENTPD=1). Con uke_handoff=0, o para cualquier otro
+	 * SMMU, esto es un no-op.
+	 */
+	uke_handoff_preparar(smmu);
+
 	/* Check for RMRs and install bypass SMRs if any */
 	arm_smmu_rmr_install_bypass_smr(smmu);
 
```

Fin del informe (diff completo arriba).

