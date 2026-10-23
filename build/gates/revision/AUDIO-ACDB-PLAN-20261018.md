# AUDIO — plan de lectura de `super`/`odm_b` para sacar el ACDB `Forte` (solo lectura, sin redistribuir) — 18-oct-2026

Objetivo: obtener del ACDB `Forte` (`/odm/etc/acdbdata/Forte/Forte_acdb_cal.acdb` + `Forte_workspaceFileXml.qwsp`, ACDB SW 1.36.0.0, 14-nov-2024) los **parámetros del módulo TDM** del backend `TDM-LPAIF_VA-RX-PRIMARY` (4 canales, 48 kHz, 32 bit, `speaker_protection_enabled=1`) y la **cadena del amplificador FS19xx** para escribir el subgrafo TDM de la topología y el soporte TDM en `audioreach.c` (E7). **No se ha leído nada de `super` todavía.**

## Lo que NO necesita la partición (ya medido en el repo)
`odm-resourcemanager_cliffs_mtp.xml`: speaker = `TDM-LPAIF_VA-RX-PRIMARY`, 4 ch, 48 kHz, 32 bit (`supported_bit_format S32_LE`), protección activa, `cps_mode 0`; `odm-mixer_paths…xml`: escenas `FSM_Scene`/`FSM_Volume`; TX = retorno V/I-sense (`vi-feedback`). Pines TDM1: LPI gpio6-9 función 2. Eso da el **contrato** (canales, tasa, ancho); lo que falta son los valores internos del módulo TDM de AudioReach (tipo de sincronía, máscara de slots, nslots, polaridad, alineación) y los IDs de módulos del grafo del speaker — solo en el ACDB.

## Hechos de la partición (medidos antes, solo lectura)
`/dev/disk/by-partlabel/super` = `sda31`, **11 274 289 152 B**; geometría LP (`67446c61` en el offset 4096). `odm_b` es una partición lógica de `super` (slot b, no se usa en el arranque actual: la tablet arranca de slot a con nuestro kernel, así que **nadie escribe en `odm_b`**). El kernel de la tablet (ouke4) y el PC solo tienen **ext4** en `/proc/filesystems` (no EROFS); el PC tiene `lpdump`, `lpunpack`, `simg2img`, `debugfs` y `7z 26.04` (lee ext4 y squashfs; **no EROFS**); `sudo` pide contraseña (no se puede `mount`).

## Plan (cada paso es de solo lectura sobre la tablet; escritura solo en `/var/tmp` del PC, ignorado por git)
1. **Metadatos LP** (≈1 MiB): `ssh … 'dd if=/dev/disk/by-partlabel/super bs=4096 count=256 iflag=direct 2>/dev/null' > /var/tmp/uke-super-head.img`; `lpdump` en el PC ⇒ lista de particiones lógicas, extensiones (sector inicial/longitud) de `odm_b` (y de `odm_a` por si el b estuviera vacío). Riesgo: nulo (1 MiB de lectura).
2. **Tipo de sistema de ficheros**: leer 2 KiB al inicio de la extensión de `odm_b` y mirar el magic (ext4 `0xEF53` en +1080; EROFS `0xE0F5E1E0` en +1024). Riesgo: nulo.
3. **Extraer solo `odm_b`**: `dd` de sus extensiones con `skip/count` calculados (tamaño típico de un `odm` Android: 50-300 MB), por SSH comprimido con `zstd`, a `/var/tmp/odm_b.img` en el PC. Lectura secuencial de UFS durante unos segundos-minutos por USB; la carga/ADSP/WiFi no se ven afectados (no se toca el ADSP; solo I/O de bloque). Riesgo: bajo (si se sobrecarga el USB, `ionice`/`bs` pequeño).
4. **Abrir `odm_b` en el PC sin root**:
   - si es **ext4**: `debugfs -R "rdump /etc/acdbdata/Forte /var/tmp/acdb-forte" /var/tmp/odm_b.img` (o `7z x`);
   - si es **EROFS**: hay que pedir al dueño `sudo pacman -S erofs-utils` (extra) y usar `fsck.erofs --extract=…`; alternativa sin root: un extractor EROFS en Python (formato simple; si el volumen va comprimido con LZ4 haría falta `lz4`). Lo decidimos al ver el tipo.
5. **Ingeniería inversa del ACDB** (en `/var/tmp`, **no se copia al repo**): el `.acdb` es un contenedor binario de pares (IDs de subgrafo/módulo/parámetro → blobs); el `.qwsp` es el XML del workspace (más legible). Buscar: subgrafo del speaker (`TDM-LPAIF_VA-RX-PRIMARY`), módulo `TDM`/`HW_EP` (IDs de módulo, `PARAM_ID_TDM_INTF_CFG`), y los módulos `FSADSP`/protección. Herramientas: `strings`, `xmllint`, scripts Python propios; ayuda: los IDs de `audioreach-topology` (`include/uapi` de `audioreach.h`/`q6dsp-common.h` en el kernel).
6. **Qué se commitea**: solo **valores derivados mínimos** que haga falta citar (p. ej. «slot_mask = 0xF, nslots = 4, sync…») y los scripts de análisis, **nunca** `Forte_acdb_cal.acdb`, `Forte_workspaceFileXml.qwsp` ni volcados completos; los ficheros extraídos se borran de `/var/tmp` al terminar o se dejan fuera de git (regla del dueño: no redistribuir firmware/ACDB).
7. **Salida**: informe `AUDIO-ACDB-<fecha>.md` con los parámetros TDM y la cadena del amplificador, y el diseño del subgrafo TDM + parche de `audioreach.c`/`q6apm-lpass-dais.c` (y el driver FS19xx) para E7.

## Riesgos y límites
Lectura de bloque por USB: bajo. La partición `super` contiene datos propietarios del dueño/Xiaomi: solo se leen los metadatos y `odm_b`, no se tocan `system`/`vendor`/`product`/`userdata`. Si `odm_b` estuviera cifrado/vacío o el `Forte` no estuviese ahí (el camino lo vimos en un logcat de Android: `/odm/etc/acdbdata/Forte/…`), se prueba `odm_a`. Aunque saquemos el TDM, **E7 sigue necesitando el driver FS19xx (el `fs19xx_dlkm.ko` v4.0.7 vendor, fuente no disponible) y topes de volumen seguros** (sin `FSADSP` del vendor hay riesgo de dañar los altavoces).

## Pide OK
Pasos 1-2 (≈1 MiB + 2 KiB, riesgo nulo) y luego 3 (lectura de `odm_b`). Confirmación antes del paso 3 si el tamaño de `odm_b` supera 500 MB.

---
# Resultado de los pasos 1 y 2 (16:56, solo lectura; 1 MiB + 8 KiB leídos)
- `lpdump` (metadatos LP v10.2, 3 slots, `virtual_ab_device`): **solo existen particiones lógicas `_b`** (grupo `qti_dynamic_partitions_b`): `odm_b`, `product_b`, `system_b`, `system_dlkm_b`, `system_ext_b`, `vendor_b`, `vendor_dlkm_b`, `mi_ext_b` (no hay `_a`: la tablet se flasheó con el slot b de Android).
- **`odm_b`**: 1 extensión lineal, **sectores 2048..2338496 de `super` (2 336 448 sectores = 1 196 261 376 B = 1,11 GiB)**, desplazamiento 1 MiB.
- **Sistema de ficheros: EROFS** (magic `0xE0F5E1E2` en +1024 de la partición; los primeros 1024 B son ceros, como en EROFS). No es ext4 ⇒ **`debugfs`/`7z` no sirven**; el PC y la tablet no tienen soporte EROFS en userspace/kernel (tablet: solo ext4).
- Ficheros locales (no commiteados, `/var/tmp`): `uke-super-head.img` (1 MiB), `uke-odm_b-head.bin` (8 KiB).

## Propuesta para el paso 3-4 (necesita tu OK: odm_b pesa 1,11 GiB > 500 MB)
- 3: `dd` de las extensiones de `odm_b` (1,11 GiB) por SSH con `zstd` a `/var/tmp/odm_b.img` (disco del PC: 114 GB libres; la lectura por USB dura ~1-3 min; solo lectura).
- 4 sin sudo: **construir `erofs-utils` desde las fuentes** (kernel.org, en un directorio propio, autotools + liblz4/libuuid del PC) para usar `fsck.erofs --extract` (o `dump.erofs`) sobre la imagen; o, si prefieres, `sudo pacman -S erofs-utils` (extra) tú. Alternativa: lector EROFS propio en Python (más trabajo, depende de la compresión).
- 5-7: como en el plan (análisis en `/var/tmp`, nada del ACDB al repo).
