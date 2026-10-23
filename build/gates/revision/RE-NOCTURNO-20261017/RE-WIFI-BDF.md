# RE-WIFI-BDF — RE del board data + payload v2 (noche 17-oct-2026)

Leyenda: HECHO = medido aquí con comando+salida · INFERIDO = deducción marcada · NO VERIFICADO = pendiente.
Nada flasheado, nada escrito en la tablet (`adb` solo lectura; sin tocar `/dev/ttyACM0`).
Artefactos nuevos: `artifacts/wifi/` (esta revisión) + `build/pkg/uke-wifi-payload-v2.tar.gz` (+ `.sha256`).

## 1. RE de bd_o82gl.elf — offset 1024 verificado, con matiz

- HECHO (`file` + `readelf -h/-S/-l`): ELF32 LE ARM, EXEC, entry 0x8000, 1 PT_LOAD, 6 secciones.
  `.data` PROGBITS en **file offset 0x400 = 1024, tamaño 0xE344 = 58180 B** (vaddr 0x1000).
  Tras `.data` vienen symtab/strtab/shstrtab + cabeceras (724 B).
- HECHO (`readelf -s`): símbolos `_binary_tempDir_O82GL_bin_{start,size,end}` → wrapper de
  `objcopy -I binary` renombrado; `.noinit` tamaño 0. Por eso hay ceros del offset 0x52 al 0x400.
- HECHO: `dd skip=1024` a secas da 58904 B (arrastra tablas ELF, sha a0fb4c8f… — NO usar).
  Extracción correcta: `dd bs=1 skip=1024 count=58180` → sha
  `da424c03ef32bc4f…` = el esperado por PERIF-WIFI (`artifacts/wifi/board-o82gl-data58180.bin`).
- HECHO (cabecera BDF, `xxd`): `01 00 04 04 00… 38 6e 26 92 …` — sin magic ASCII; se pasa crudo
  por QMI en api-1. INFERIDO: u16 en offset 10 (`0x9226` o82gl vs `0xA6DD` o82, ver abajo) =
  campo de variante; significado exacto del resto NO VERIFICADO (sin parser qcacld; api-1 lo ignora).

## 2. Variantes en la tablet — v1 llevaba la equivocada

- HECHO (`ls /vendor/firmware_mnt/image/qca6750/`): 8 `bd_*.elf` (o82, o82gl, o82in, n9, n9in,
  n16t, n16tgl, n16tin) + `bdwlan.b{01..20}`/`bdwlan.e{01..20}`/`bdwlan.bin` (58180 B crudos) + `Data.msc`.
- HECHO (pull + `dd` + sha): payload de `bd_o82.elf` = `2a63af3f…` **== `board.bin` del payload v1
  byte a byte** (`cmp` limpio) → v1 = variante o82, NO la del uke. `bd_o82.elf` también 58180 B de `.data`.
- HECHO (`cmp -l` o82 vs o82gl): solo **159 bytes difieren de 58180** (cabecera ID + zonas de
  calibración ~6K/12K/44K). Misma estructura, distinta calibración → usar BDF ajeno = riesgo real.
- HECHO: `bdwlan.b01` (58180) difiere de AMBOS en byte 11 → tercera variante (ficheros por-placa
  del vendor; mainline api-1 no los usa). `amss.bin` de kiwi en tablet == `amss.bin` de v1
  (`c42e06f5…`, pull 7 MB verificado) → v1.amss era kiwi, no qca6750.

## 3. regdb — tres blobs distintos de 24278 B, el bueno es el qca6750-xiaomi

- HECHO (`xxd`): sin magic/firma ELF; blob regulatorio crudo: entradas país (`41 46 41 46`="AF AF"…)
  con reglas; 14 B de ceros al final. Primeros u16 distinguen build: v1-staged `c68d`, tablet
  `qca6750/regdb.bin` `c66d`, **`qca6750/regdb_xiaomi.bin` `f836` = nuestro `fca5bbfa…`**.
- HECHO (`cmp -l`): v1-regdb vs tablet-genérico = 684 B difieren; tablet-genérico vs xiaomi = 624 B;
  **kiwi/regdb_xiaomi.bin (`237fc609…`, pull) vs qca6750/regdb_xiaomi.bin = 905 B** → ni siquiera los
  dos "xiaomi" son iguales. El que pide el Android vivo (`qca6750/regdb_xiaomi.bin`, kmsg 6,33 s
  según PERIF) es `fca5bbfa…` → ese va en v2. Destino mainline: `ath11k/WCN6750/hw1.0/regdb.bin`.

## 4. Nombres que pide mainline (árbol k52-L16, medido con grep)

- HECHO (`hw.h:74-82`): `ATH11K_FW_DIR="ath11k"`, `board-2.bin` (api-2), `board.bin` (api-1),
  `amss.bin`, `m3.bin`, `regdb.bin`. (`core.h:1342-1359`): ruta = `ath11k/<fw.dir>/<fichero>`
  (`board*` nunca lleva subdir de usecase); para WCN6750 `fw.dir="WCN6750/hw1.0"` (`core.c:579-585`,
  `board_size=256 KiB` — caben .elf 59928 y BDF 58180).
- HECHO (`core.c:630` bloque wcn6750): `supports_regdb=true`, **`m3_fw_support=false`**,
  `fixed_fw_mem=true`. `qmi.c:2600`: `ath11k_qmi_m3_load` solo si `m3_fw_support` → **m3.bin NO se
  pide**; `mhi.c:357`: `amss.bin` solo lo pide el camino MHI/PCI → **en AHB no se pide**.
- HECHO (`qmi.c:2414-2445`): si el BDF empieza por `\x7fELF` → `BDF_TYPE_ELF`, si no → `BIN`;
  regdb → `BDF_TYPE_REGDB` (no fatal, `qmi.c:2987`). Con BDF BIN crudo sigue a caldata:
  `cal-ahb-*.bin`/`caldata.bin` → **OJO: este árbol lleva poke local** (`qmi.c:2484-2502`,
  comentario "UKE (kiwi/uke, 26-sep)") que devuelve 0 sin cal en vez de -ENOENT. Sin ese poke,
  el probe abortaría. El poke existe en el árbol k52-L16: verificar que el kernel del próximo
  test lo incluye (NO VERIFICADO en imagen de boot).
- Veredicto v1 fichero a fichero (`tar -tzf` + shas §2-3): `board.bin` MAL (o82),
  `regdb.bin` MAL (genérico de otro build), `amss.bin` SOBRA (7,4 MB muertos, era kiwi),
  no hay `board-2.bin`/`m3.bin` (bien — no añadir `board-2.bin` de linux-firmware: colisión
  de calibración ajena). WPSS `qca6750/*`: ver §6.

## 5. Extra vendor .ko (techo 10 min, `strings` sobre copias PC en `build/android/vendor-modules-20261017/`)

- HECHO `xiaomi_wifi_gpio.ko` (65 KB, vermagic 6.1.68-android14): driver GPIO de test/SAR
  (`xiaomi,xiaomi-wifi`, autor USUARIO@example.invalid): GPIO+debounce+IRQ wakeup, netlink
  `sar_event`/`wifi_sar`, `get_hw_country_version`, bypass en dispositivos no-CN. Nada que
  mainline necesite para wlan0 (INFERIDO: SAR/CN = fuera de P4).
- HECHO `wlan_firmware_service.ko` (98 KB): cliente QMI WLFW (`qcom,wlan`, `wlfw_*_req/resp`:
  `bdf_download`, `cal_download/report`, `m3_info`, `mac_addr`, `qdss_trace`, `respond_mem`) =
  el homólogo vendor de `ath11k_qmi.c`. Confirma el protocolo que mainline debe hablar (INFERIDO).

## 6. Hallazgo lateral (HECHO, pull `wpss.mdt` 4844 B): el WPSS de v1 NO es el del vendor vivo

`wpss.mdt` tablet = `b3451c51…` == `build/pkg/uke-fw-radio/wpss.mdt` ≠ v1 (`e2d14e4f…`);
tamaños de los 13 segmentos idénticos en los tres lados. El `.mdt` porta los hashes de los
segmentos → el set v1 es otro build (stage s21). NO se mezcla: v2 conserva el set v1 intacto
(autoconsistente; "levanta" según #441). Gate propuesto v3: pull de los 13 `wpss.b*` del vendor,
comparar shas, y decidir swap del SET COMPLETO (nunca solo el .mdt).

## 7. Payload v2 — construido y verificado

Método: `preparar-wifi-payload.sh` no acepta sustituciones (lee FWSTAGE+manifiesto+KBUILD y
reconstruye todo) → reconstrucción manual con idéntica estructura que v1:
`tar xzf v1`, sustituir `WCN6750/hw1.0/board.bin` (da424c03) y `regdb.bin` (fca5bbfa),
borrar `amss.bin`, reempaquetar mismos top-dirs, reverificar por extracción.
- Salida: `build/pkg/uke-wifi-payload-v2.tar.gz` (24.646.368 B),
  sha `2b0dd75a7db86e0889a53d91830a2138a9651d14f31f59321f0924ead49f4c4c`
  (`build/pkg/uke-wifi-payload-v2.sha256`). v1 sha `dfca8884…` (28 MB).
- Diff v1→v2 (`diff` de listados): **solo** `- usr/lib/firmware/ath11k/WCN6750/hw1.0/amss.bin`;
  `board.bin`/`regdb.bin` mismo path, contenido sustituido (shas §4 verificados post-extracción).
  Módulos (7.2.0-rc2-palawan, blacklist incluida) y WPSS intactos de v1.
- Uso en tablet: `tar xzf uke-wifi-payload-v2.tar.gz -C / && depmod -a` (igual que v1).

## 8. Qué cambia para el próximo test WiFi + gate

Cambios: BDF correcto o82gl (antes calibración de otra variante), regdb Xiaomi del path vivo
(antes genérico de otro build), −7,4 MB muertos; el resto idéntico a v1 (módulos, WPSS, blacklist).
Gate en nuestro Linux (tras modprobe manual con wifi en blacklist, DT solo-wifi según PERIF):
`dmesg` debe mostrar `using board api 1` + `bdf_type 0`(BIN, NUESTRO BDF CRUDO — no 2/ELF salvo
que se sirva el .elf) + `fetched regdb` + `qmi-chip-id/qmi-board-id` + `fw_ready` + `wlan0`
+ `iw scan` OK + SSH con uptime > 300 s. Avisos: (a) el kernel del test debe llevar el poke
  caldata de `qmi.c` (si no, aun con BDF bueno el probe muere en -ENOENT); (b) WPSS v1≠vendor
  (§6) — si el wpss no levanta, el siguiente paso es el set vendor, no reintentar BDF.
