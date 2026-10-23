# KERNEL ESTABLE — auditoría del último kernel probado y verde (11-oct, solo lectura)

> Auditoría de reconstrucción. Cero flashes, cero escrituras. Fuentes: FLASH-LEDGER.md
> (#533–#602), SHA-BUENOS.txt, build/backup-par-bueno/, docs/historia/ESTADO-VIVO.md (05:0x),
> docs/historia/revision/BASE-ESTABLE-20261011.md, repacks y shas medidos HOY en disco con sha256sum.

## 0. Las tres clases (distinguidas en toda la tabla)

- **(a) ARRANCA** — el kernel llega a Linux (consola/perfiles UKE visibles).
- **(b) SSH/ESTABLE** — SSH arriba y uptime demostrado (>300 s continuo = criterio del proyecto).
- **(c) GPU VIVA** — escalera GMU completa (CM3→HFI→zap rc=0), no solo nodos card0/renderD128.

## 1. Tabla cronológica de la era K52 (6–11 oct)

| Fecha | Kernel (boot img, sha 8) | dtbo en la tablet | Clase demostrada | Evidencia (ledger) |
|---|---|---|---|---|
| 6-oct | **k52b2** `boot-uke-k52b2-bateria.img` `18c749ea` | s268→s269 `8893fe37` | a+b (sin c: GPU dormida por diseño) | #534: cadena batería (99% Charging, 4,42 V), SSH OK |
| 6-oct | k53 `673d6468` / k54 `e3f70607` / k55 `312b284e` | s270/s271 | a (k55: primer boot que sobrevive GPU-on con fallo gracioso; sshd refused por fs) | #535/#536 |
| 7–8 oct | k56–k64 (GPU diagnostics) | s270/s272/s273 | a (freezes GPU-on; k61/k62/k64 no estables) | #537–#552 |
| 8-oct | **k52b2 testbed** (restore) | s269 | a+b: **18+ min uptime**, SSH, 98% Charging, ADSP running, card0+renderD128 | #542-adj (`LEDGER:10600`) |
| 9-oct | k52b2 (restore #554) | s273 `0bfe074b` | a+b (SSH `aarch64` up 1 min; card0 nace en frío) | #554 04:3x |
| 9-oct | **L0** `boot-uke-k52L0.img` | s273 | a+b — **L0 == k52b2 validado por comportamiento** | #561-resultado |
| 9–10 oct | L1–L15 (escalera bisect GPU) | s250 `f0dc934d` | a (llegan al muro GMU; L15 llegó a opens #579) | #562–#579 |
| 10-oct | k52b2 (restore #581, orden del dueño) | s273 | a+b (SSH vivo ~40 s; card0 NO nace en boot caliente — herencia GPUCC, no del kernel) | #581 |
| 10-oct | **L11** `78295439` | s250 → **s274 `1c60fc38`** | a+b+**c: PRIMERA GPU VIVA** (secuencia completa, zap, 118 funcs ftrace; OPEN-2/3 estables) | #583; re-test frío #585 |
| 10–11 oct | L16-chipid `d243c3ab` | s274 | ✗ (-ERANGE; causa: cmdline clonada sin `msm.uke_gmu_shared=0`, #586) | #584 |
| 11-oct 00:xx | **L17-chipidB** `cb240ca3` | s274, luego s275-r1 | a+b+**c (F1a: eglinfo OpenGL ES 3.2 freedreno FD735)** | #586, #587 |
| 11-oct 01:0x | L18 `d3dcf944` | **s275-r2 `67a65bc1`** | a+b+c (panel card1-DSI-1+Writeback nace; ADSP defer por ICC) | #588 |
| **11-oct 01:3x** | **L19 `71d89ca6`** | **s275-r2 `67a65bc1`** | **a+b+c: ADSP running, PDR charger_pd, Charging real, GPU 0 fallos, panel nacido, SSH productivo (scp 612 MB), uptime demostrado 3773 s (~63 min), wpss running >5 min en boot hermano** | **#589, #591, BASE-ESTABLE fila 6 (P), #595, #597** |
| 11-oct 01:4x | L19P `7b6ec7e9` (sin `:d`) | s275-r2 / s276 `ef01ed56` | ✗ wedge ~20–40 s — EXPERIMENTO pre-registrado (encendido del panel en boot = ventana #505); predicción cumplida, no es regresión del kernel | #590, #591 |
| 11-oct 04:0x | L20 `71765b16` | s277 `4a8a7a51` (ROTO: DSI -2) | a+b (SSH OK, escalera GMU completa) pero **nunca probado con dtbo bueno** | #593, #596 |
| 11-oct 15:2x | L21 `7d178b01` | s278-nostrip `5fcfbc84` | ✗ wedge 4,1 s (frags WiFi del dtbo; también mata a L19 y L21E1b — #600/#601) | #599, #600 |
| 11-oct 15:4x | L21E1b `7b50adf6` | s278-nostrip | ✗ bucle de reboots | #599-ter |
| 11-oct 18:2x | L19fsck `1b82de86` (kernel L19 + cpio k51 con e2fsck) | (dtbo indiferente) | SIN FLASHEAR aún — rescate #602 en marcha | #602 |

**Nota dtbo**: s276 (rail 1896) y s278-* (todas las variantes) quedaron **refutados como inestables** (#601: L19+s276 crawl 43 s y wedge a 47 s). El ÚNICO dtbo display vivo y estable es **s275-r2 `67a65bc1`**.

## 2. Las 5 preguntas

**1. Kernel MÁS NUEVO con estabilidad demostrada:** **L19 (`71d89ca6e875941b…`, boot-uke-k52L19.img)**, demostrado el **11-oct entre 01:3x y 04:0x** con **dtbo s275-r2 (`67a65bc161b645d8…`)**. Es el último de la cadena L17→L18→L19 y cubre las tres clases a la vez (SSH + uptime + GPU viva + carga + panel nacido). L20 y L21 son más nuevos pero **jamás se flashearon con el dtbo bueno** (L20 fue con s277 roto; L21 con s278-nostrip que wedgea). Ojo: L19 es del **11-oct**, no del 10-oct (creado 01:06, escrito como nº39 ~01:3x).

**2. k52b2:** SÍ era estable, en sentido **(b)**: SSH + cadena de batería (6-oct, #534), testbed con **18+ min de uptime** y 98% Charging (8-oct), re-validado por SSH otras 3 veces (9-oct #554 "up 1 min"; 10-oct #581 "SSH vivo ~40 s"). Su GPU **no** era clase (c): GPU dormida por diseño (solo card0/renderD128 DPU-solo). **SÍ hay algo más nuevo con SSH demostrado**: L0 (== k52b2 por comportamiento), L11, L17, L18, L19 y L20 — todos con SSH en algún boot. La memoria del dueño es correcta pero **desactualizada**: L19 le pisa con más uptime demostrado (3773 s vs 18+ min).

**3. L19 `71d89ca6`:** demostró **SSH/estabilidad REAL**, no solo "arrancó y GPU viva". Con **s275-r2**: ADSP running + Charging real (#589); sesión SSH productiva con **scp de 612 MB** de staging del escritorio (#591); el boot de la madrugada llegó a **uptime 3773 s** y lo cortó el disparador DELIBERADO `echo on > card1-DSI-1/status` (repro del wedge del panel #595 — diseñado para matar, no inestabilidad espontánea); WiFi: wpss running >5 min (#597). Con s277 también dio SSH (#596). Matiz importante (BASE-ESTABLE §1): el par L19+s275-r2 solo estuvo en slots de **02:2x a 04:0x** (y re-flasheado 17:1x–17:3x, cuando el rootfs ya estaba corrupto: pid1 ABRT — daño ext4 on-disk probado, NO del kernel).

**4. build/backup-par-bueno/:** contiene el par **K13+s260 del 30-sep** (`boot-ukek13-dsid.img` `e0ee47dc…` + `s260-boot-dtbo-dpu-iommus.img` `6fbb5173…`, "ESTABLE por SSH" según SHA-BUENOS 30-sep 22:10) y en historico/ el s244-bounce `ffff8c51…` del 28-sep. **Es el par verificado más reciente DEL DIRECTORIO, pero está desactualizado 11 días**: nada de la era k52 fue respaldado ahí. El par bueno actual (L19+s275-r2) existe solo en build/bootimg/ — **gap: copiarlo hoy**. (Verificado: ambos shas del backup coinciden con SHA-BUENOS.)

**5. RECOMENDACIÓN (par exacto + criterios):**
- **Par a flashear**: `build/bootimg/boot-uke-k52L19.img` sha256 `71d89ca6e875941b75af012ac24d20fb7690de407fa341923f2d896557ee51a9` + `build/bootimg/s275-boot-dtbo-gpu-display.img` (= **s275-r2**) sha256 `67a65bc161b645d8664c4ba3fd1bfeaa9a92637bc52a1669feab9784fa7e01df`. Ambos verificados en disco hoy contra el ledger (#589/#587).
- **Paso previo OBLIGATORIO (F-A de #602)**: el rootfs tiene corrupción ext4 on-disk probada (10 grupos, pid1 ABRT 5/5 boots de tarde). Flash UNA vez `boot-uke-k52L19fsck.img` `1b82de861807273cb9212822ad175c585e1ccb4df6787ba15ece8a280fd8a9f1` para que corra `e2fsck -fy /dev/userdata` en frío; después F-B: flash L19 + s275-r2. `fastboot set_active a` SIEMPRE antes de reboot (#596).
- **Antes**: cargador de pared ≥1 h (confounder batería: 2% → 10,5 h en negro → solo USB de PC toda la tarde).
- **Criterios de aceptación** (los 6 de BASE-ESTABLE §4, en UN mismo boot): (1) pid1 sin `Caught <ABRT>`, (2) **SSH por NCM + uptime > 300 s continuo**, (3) GPU viva (escalera → zap rc=0), (4) cero `EXT4-fs error` nuevos, (5) una sola enumeración USB, (6) `status=Charging` con `bateria.sh` legible.
- **Escalera de discriminación si falla**: si L19+s275-r2 no pasa los criterios con fs limpio y batería llena → bajar a **k52b2+s269** (`18c749ea…` + `8893fe37…`, testbed 6-oct). Si TAMPOCO → ahí sí apunta a degradación del aparato (y el fallo sería pre-kernel). Si k52b2 pasa y L19 no, el problema sería del cpio/initramfs o del árbol L-chain, no del hardware.

## 3. Huellas verificadas hoy en disco (sha256sum, 11-oct)

```
18c749ea28a81aef1cc99a7824ea702cc6f739d9c89bcbd83ceaca6ef03e6aea  boot-uke-k52b2-bateria.img  (#534/#581)
8893fe37d76df53a0634506c5f9cb57f9f1bbb4b9a92c0985cfeb96e6cbcd3e6  s269-boot-dtbo-touch.img    (#533)
0bfe074be4e562b8e3a0d3a52e12c31ce3d3ecd9bf59fa7b0e8f20da8077b2c5  s273-boot-dtbo-gmu-map.img  (#581)
782954393c0252f0c86206b7d2db9c98d1f20810063a64c316e3a441ddcc42b8  boot-uke-k52L11.img         (#582)
1c60fc388f5387cf7ddaba6381024a6fbd32098df380db1f0b3380ce3d9501dc  s274-boot-dtbo-gpu-serie.img(#583)
71d89ca6e875941b75af012ac24d20fb7690de407fa341923f2d896557ee51a9  boot-uke-k52L19.img         (#589)  ← RECOMENDADO
67a65bc161b645d8664c4ba3fd1bfeaa9a92637bc52a1669feab9784fa7e01df  s275-boot-dtbo-gpu-display.img (= r2) ← RECOMENDADO
71765b16d5200092dcfcf5c6fbfb72fc40ab8f4ff07e4258a55eb8da41d3ae1c  boot-uke-k52L20.img         (#593)
7d178b019d25e5e071843ae9a50a2683209774eb577af91fb146d3270df7e131  boot-uke-k52L21.img         (#599)
1b82de861807273cb9212822ad175c585e1ccb4df6787ba15ece8a280fd8a9f1  boot-uke-k52L19fsck.img     (#602, sin flashear)
e0ee47dc4044e9cccbcf177ab36cc8efd005ee9ef4d7cff370741578707c5c57  backup-par-bueno/boot-ukek13-dsid.img (30-sep)
6fbb5173b8af5add34e90dcff9d3dce742f7fa9fe76182eda2db123b39685ad7  backup-par-bueno/s260-…iommus.img     (30-sep)
```

## 4. Riesgos y notas de auditoría

- `repack-s275-report.txt` fue **sobrescrito por el builder s277** (clon que heredó la ruta del report; lección ya registrada en #586) — el gate del r2 vive solo en el ledger #587 + el sha del fichero en disco. Re-construir el report si se regenera el dtbo.
- `repack-k52L19.py` y su report no están en build/bootimg/ (sí los de E1/E1b/L20/L21). La procedencia de L19 queda cubierta por: sha del .img == ledger #589, y el report E1 (#594) que pinea por sha el kernel embebido de L19P (`5582dcc2…`) como idéntico al de L19, con initramfs byte-idéntico al de k52b2.
- La tarde del 11-oct (pid1 ABRT 6,6–16,6 s en 5/5 boots con 4 dtbos distintos, incluido el par bueno re-flasheado) es **ruido de rootfs (H4 probada)**, no regresión de kernel: no invalida la estabilidad de L19 demostrada de mañana.
- La tablet quedó SIN USB desde ~04:50 (ESTADO-VIVO); este informe es 100% de PC.
