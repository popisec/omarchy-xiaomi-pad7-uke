# VERIFICACIÓN-W2 — RE nocturno 20261017 (verificador independiente, solo lectura)

Fecha: 2026-10-17 ~04:00 UTC. Método: comandos + salida, copias en `/tmp/opencode/w2-verify/`
(`patchtest/`, `bt-frag-test*.dts*`, `qca-ref/`, `wifi/`, `omarchy-pkg/`, `upstream/`).
Nada escrito en el repo salvo este fichero (nuevo). Sin builds, sin flash, sin tablet.
Fuera de alcance (anti-colisión): PANEL/L75 + PERIF-*. NOTA: durante la verificación
apareció `RE-AUDIO-…-ADD2-FSM-DRIVER.md` (no estaba en el encargo de 7 informes): no auditado.

## 1. Tabla PASS/FAIL/NOTA

| # | Ítem | Veredicto | Evidencia / detalle |
|---|---|---|---|
| 1a | 0001-touch-nt36532.patch aplica | **PASS** | `git apply --check` y apply real en copia /tmp: limpio, 2 ficheros |
| 1b | delta-0002-touch-superres-pen.patch aplica | **FAIL (formato)** | No es parche máquina (cabeceras `--- 0001…`, sin `@@ -a,b +c,d @@`); `patch`/`git apply` lo rechazan. Contenido OK: las 5 líneas `-` existen verbatim en el 0001 (chequeo mecánico) |
| 1c | novatek-nt36xxx-spi-pen-draft.patch aplica | **FAIL (formato) / contenido OK con offsets** | Las 3 cabeceras traen cuentas mal (H1 dice +53/son 35, H2 +84/87, H3 +19/24; sin newline final): `git apply`+`patch` rechazan. Con cabeceras recalculadas (solo /tmp), GNU patch aplica los 3 hunks (offsets 8/5/3, fuzz 1 en H3); contexto existe en árbol (`pen_support` l.100/683) |
| 1d | Coherencia delta ↔ pen-draft | **FAIL (incompatibles tal cual)** | `pen_max=(prop.max_x+1)*10-1` da 21359/31999 solo con DTS SIN escalar (size 2136→max 2135; `touchscreen.c:85-123`: max=size-1). Con el delta (21360) daría 213599. Además el comentario del parche dice `(abs+1)*10-1 (21359/…)` pero 2136*10-1=21359 (el informe §1.2 trae la fórmula bien) |
| 2a | parse_msbtfw.py reproduce fw-tables.txt | **PASS** | Salida byte-idéntica (`diff` limpio); mbn 109248 B sha `3efbd7fa…` ✓; PH2 termina exacto a EOF ✓ |
| 2b | Riesgo [N] «walker no encadena» (RE-BT §2/riesgo 1) | **RESUELTO a favor (falsa alarma)** | El script usa stride 4 B, pero `struct tlv_type_nvm` son **12 B** (`btqca.h:134-140`). Con stride 12, msnv12.bin encadena 63 tags hasta `end_idx==length==6202`; igual que apnv11/cmnv12/crnv21/hmtnv20 de linux-firmware local (todos fallan con stride 4 y funcionan en producción). `qca_tlv_check_data` la acepta |
| 2c | Anatomía NVM en RE-BT §2 | **FAIL (contenido)** | Los «tags (0,0)@0x48/0x4c, blob desde 0x5a de 6116 B» son artefacto del stride erróneo. Real: tag BD_ADDR @0x50, datos @0x5c = `ad 5a 00 00 00 00` (NO ceros; el kernel los COPIA, no «rellena»); blob @0x62 (6108 B). Tag HCI=17 (`btqca.h:32-33` ✓), BD_ADDR=2 ✓ |
| 3a | wcn6750-bt-fragment.dtsi compila | **FAIL (tal cual)** | `vddrfa2p2-supply=<&vreg_s3e_2p4>` cuelga: el bloque `&apps_rsc` está DENTRO del comentario `/* 0)…*/` (l.14–28). `dtc` (con stubs): `Reference to non-existent node vreg_s3e_2p4`. Descomentado en /tmp: compila (solo warnings de stubs) |
| 3b | Fragmento vs binding yaml + hci_qca.c | **PASS con notas** | 9 supplies == `qca_soc_data_wcn6750` (nombres y cargas 5m/26m/126m/12.5m/102m/302m/257m/1700m/200µ idénticos); required del binding cubiertos; cero props inválidas. GPIOs 156/80/35+mpm80 confirmados en dump vendor (`0x16b 0x9c/0x50/0x23`) ✓; uart10:1344 + pinctrl 40/41/42/43 qup1_se2 ✓; ventanas xiaomi-uke.dts ✓; k37.config BT ✓ |
| 3c | «swctrl obligatorio / sin enable→pwrseq» (RE-BT §3) | **FAIL (inexacto ×2)** | `devm_gpiod_get_optional` + solo `IS_ERR` aborta (2492-2500): ausente=NULL se tolera. Sin `enable-gpios`, wcn6750 pone `power_ctrl_enabled=false`; `pwrseq "bluetooth"` solo existe en brazos QCA6390/default (2455/2512). Cita «lamma-qrd.dts:397 vreg_s3e_2p4 1.6-2.4V ✓» falsa: lamma:414-418 trae **3.008-3.96V** (los 1.6-2.4V del fragmento son del vendor, bien, pero no de lamma) |
| 4 | Payload WiFi v2 | **PASS todo** | `sha256sum -c` OK; 80 entradas (v1 81, único diff: fuera `amss.bin`); board.bin=`da424c03…` ✓ (== `board-o82gl-data58180.bin`); regdb=`fca5bbfa…` ✓; sin amss ✓; `preparar-wifi-payload.sh` sin modificar (git limpio) ✓. Citas ath11k ✓ (`hw.h:74-82` exactas, `core.c:582/630` bloque wcn6750, `mhi.c:357`, `qmi.c:2438-44/2600`, regdb no fatal §2987, poke UKE 2483) |
| 5 | Scripts omarchy (`bash -n` + lógica) | **PASS con notas** | Los 3 parsean OK; sin rutas peligrosas (solo pacman/marcadores en $HOME). Mecánica del problema verificada contra el tarball staged: `pkg-add:10-12,18` (`|| exit 1` + `pacman -Q`) ✓; bucle `vmlinuz` de `update-restart:12-25` idéntico al citado (bug real sin vmlinuz) ✓. Notas: `seal --dry-run` hace `mkdir -p $STATE_DIR` (efecto menor); `--verify` usa `ls *.sh` sin guarda (inocuo); `3<&-` sin justificar |
| 6a | RE-TOUCH (3 afirmaciones) | **PASS + 2 citas FAIL menor** | .ko 1063304/308600 B ✓; driver 657 lín + `EVENT_BUF 0x125800` en l.60 ✓; `0x2001`=ONESHOT+RISING ✓ (cosecha 13352 lín, `int_trigger_type=1` en probe:5351 ✓; `54 Edge xiaomi_tp` ✓); superres ×10 ✓ (getevent 21359/31999, dmesg 5530-37). Citas mal: irq-raw está en `dt-novatek-node.txt:6`, no :5; getevent en `live-verify.txt:~55-60`, no :31-38 |
| 6b | RE-STYLUS (3 afirmaciones) | **PASS + 1 NOTA** | FWs 245760 B + `NVT` en EOF-3 + tags `11ee/916e` suma 0xFF + md5: byte-verificado ✓. Ejes §1.2 == `getevent -p` exactos (M80p 21359/31999/8191/tilt±60/008f-0140-014a; P81c +BRAKE360/16383/0120) ✓✓. decomp/ 32 .c ✓, `0x1c`=BUS_SPI ✓. NOTA: decomp-full trae **230 .c** en disco vs «233/233» (el log Ghidra dice written=233): conciliar 3 |
| 6c | RE-BT (3 afirmaciones) | **PASS salvo §2/§3 (ver 2c/3c)** | btpower sha `fdbc8e3a…` + modinfo (desc/vermagic/depends) ✓; 8 compatibles en strings ✓; decomp 47 .c ✓; hci_qca.c 2841 lín ✓; `msbtfw12.mbn` vía `qca/msbtfw%02x.mbn` (~btqca.c:829-834) ✓; `qca_soc_data_wcn6750` 2171-2186 ✓; config BT ✓ |
| 6d | RE-AUDIO + ADD1 (3 afirmaciones) | **PASS** | fs19xx modinfo v4.0.7/depends/`foursemi:fs16xx` ✓; `fs19xx.fsm` 4828 B + `00 01 onlybsg 00 1` ✓; tinymix 310 lín + idle Scene0/Vol255/StopOn/AMP_OFF ✓; decomp 127 .c ✓ (+`fsm_i2c_probe.c` existe); `fs19xx_smartpa@{34-37}` en `i2c@88c000` ✓; `CHIPID_WCD9390=0x0/9395=0x5` ✓; gap fs210x (solo 2104/2105S) ✓; `cliffs-mtp-snd-card` en DT+proc-asound ✓ (no en strings del .ko: solo fuente DT/vivo) |
| 6e | RE-WIFI (3 afirmaciones) | **PASS** | `.data` en offset 0x400 tamaño 0xE344=58180 ✓; `cmp` o82 vs o82gl = **159 B exactos** ✓; amss v1=`c42e06f5…` ✓; `bdwlan.b01` difiere en byte 11 (0x49 vs 0x26) ✓; trío regdb documentado sin contradicción (237fc6 kiwi-pull ≠ fca5bbfa bueno en v2) ✓ |
| 6f | RE-FOLIO (3 afirmaciones) | **PASS + 1 FAIL menor** | nanosic 358128 B md5 `b97ec7f5…` ✓; HID 61/56/277/25 B + 4 shas exactos ✓; sensorservice 1370 lín + «Total 53 h/w sensors» literal ✓; lsm6dso en `st_lsm6dsx.h` ✓; qmc63/stk3b/sip1328/sx937/see vacíos ✓; hall DT + keyboard 69176 B («69 KB») ✓. FAIL: decomp-keyboard trae **36 .c** (todos no triviales), no «31» (hall 14 ✓) |
| 6g | ATAQUE-OMARCHY (3 afirmaciones) | **PASS + 1 NOTA** | Cadena update (free-space→prune→snapshot→dev→keyring→system-pkgs→migrate→aur→mise→restart) ✓ en tarball; `migrate` con `set -euo` + `bash -euo pipefail`+touch (aborto en 1er fallo real) ✓; 106 migraciones + 106 semillas ✓; killer 1781984677 (`needs_repair`→snapper.sh sin snapper) ✓; «106 pendientes» corroborado por NOTAS-OMARCHY:4827 ✓. NOTA: «ledger #634/#635-637» NO localizados (hermano termina en #614); A:63/128 coherente con la nota de deriva ✓ |
| 7 | Crudos + repo intacto | **PASS** | Todos los .ko citados existen con los tamaños citados; `git status --porcelain \| grep -v '^??'` vacío (19 untracked, 0 tracked modificados) |

## 2. Acciones correctivas (ordenadas)

1. **BT §2**: reescribir anatomía NVM con stride 12 (BD_ADDR datos `ad5a…` @0x5c, blob @0x62) y cerrar el [N] como resuelto (este informe aporta la prueba + testigos linux-firmware). Avisar al dueño: el riesgo pasa a NO-riesgo.
2. **Parches**: regenerar `pen-draft` con cabeceras correctas + newline final y decidir escala única (recomendado: DTS escalado del delta + quitar `*10` del driver, o viceversa); convertir el delta en parche aplicable o plegarlo a 0001/fase4-touch.
3. **Fragmento BT**: descomentar bloque 0 antes de usar; corregir citas (swctrl/pwrseq/lamma 3.0-3.96V); marcar `vddasd` [N] eléctrico como bloqueante de horneado.
4. **Citas menores**: touch (`:5`→`:6`, `:31-38`→`:~55-60`), folio («31»→36 .c), stylus (conciliar 233 vs 230 .c).
5. **Omarchy**: localizar o corregir la ref «ledger #634» (¿ledger propio?); `seal --dry-run` sin `mkdir`.

## 3. Resumen (≤50 líneas)

- De 7 frentes: WiFi-v2, audio, stylus-ejes/FW, folio-sensores y mecánica omarchy, PASS.
- Hallazgo principal (a favor): el «riesgo» del NVM de BT queda RESUELTO —
- msnv12.bin encadena perfecto con el stride real de 12 B del kernel (63 tags,
- end==length), igual que 4 firmwares stock que funcionan en producción.
- Pero el §2 del informe BT describe mal la anatomía (stride 4) y el §3 exagera
- (swctrl/pwrseq) y cita mal lamma (3.0-3.96V, no 1.6-2.4V). Corregir antes de usar.
- Parches: 0001 aplica limpio; delta y pen-draft NO aplican tal cual (formato).
- El contenido del pen-draft es coherente (offsets 8/5/3) pero incompatible con el
- delta: ambos a la vez escalan ×100 el lápiz. Decidir escala única.
- Fragmento BT no compila tal cual (bloque 0 comentado, phandle colgando);
- con el bloque activo compila y cuadra con binding yaml + hci_qca.c.
- Payload WiFi v2 impecable (sha, 80 ficheros, board/regdb buenos, sin amss,
- script intacto). Scripts omarchy sanos y problema upstream confirmado.
- Citas de informes: casi todas exactas; 4 off-by-one/conteos menores.
- Repo intacto (0 tracked modificados). ADD2 aparecido a mitad: no auditado.
