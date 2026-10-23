# PLAN DE TRABAJO — omarchy-uke (v2 FINAL, 30-sep-2026)

> v2 integra las críticas de 3 subagentes (método/riesgo, técnico kernel/SMMU, prioridades).
> Sustituye a `docs/historia/PLAN-SIGUIENTE-v1.md` (se conserva como historial de la crítica).
>
> **Restricciones del dueño:** el git no se toca (local-only: sin remotos, sin reescritura de
> historial, sin tocar blobs ya trackeados; solo commits rutinarios selectivos). **Esta sesión
> de planificación no toca la tablet.**
>
> **Corrección de hipótesis que ordena todo el plan (crítica técnica):** con la cmdline de K13
> (`uke_write_mask=0`, verificado byte a byte) **K16 no programa nada nuevo en el HW del SMMU**:
> los hosts DSI no llevan `iommus` en el DTB fusionado (no son masters IOMMU: sin fwspec, sin
> grupo, sin "dominio identity" que arrastrar), y un split de grupos *kernel* no cambia la
> traducción *HW* de la banda (un SMR con máscara `0x2` cubre 0x1c00+0x1c01). El diagnóstico
> de `K16-DISENO.md` (elevado a hecho desde la "hipótesis nueva" de #P43) **no resiste el
> contraste con el código y el DT**. K16 sigue siendo legítimo como **control experimental
> barato** (1 flash, ~15 líneas), pero se pre-registra como tal, y el peldaño siguiente
> (rung `uke_write_mask`) y el diseño K17 a nivel SMR/fwspec se preparan ANTES del flash.

## P0 — Red de seguridad y saneamiento (0 tablet, ~45 min)

1. **¿Tablet viva?** (Paso 0 permanente de toda sesión): ping/SSH a 192.168.42.129 o ACM. Si
   no está viva → fastboot físico por teclas → verificar par → decidir; no continuar el plan
   asumiendo SSH.
2. **Contradicciones vivas a resolver** (P0 doc):
   - OBJETIVOS fila 3: «boot_b lleva K7 #P17» → K13-dsid.
   - ESTADO-VIVO:43 «F9 resuelto» vs OBJETIVOS fila 2 «BLOQUEO» → unificar en: *causa
     identificada (cadena A incompleta: `vendor_boot_a`+`init_boot_a` borradas 24-sep, GPT
     reconstruida #P31); verificación end-to-end pendiente; coste real = 3 flashes (E1), no 1*.
   - Contradicción misc «partición 12» (ESTADO-VIVO regla 9) vs «entrada 13/sda13» (#P39) vs
     `DECISION-misc-BCB.md` (sda12) → fijar regla operativa: **misc SIEMPRE por
     `/dev/disk/by-partlabel`, nunca por número** (la LUN reordena sda/sdb).
   - Banner SUPERSEDED en `docs/historia/RUNBOOK-MAÑANA.md` → apunta a `docs/historia/RUNBOOK-SIGUIENTE.md`.
   - docs/historia/AGENTS.md: banner «par vigente y estado del aparato: SOLO docs/historia/ESTADO-VIVO.md»; corregir
     `bin/…` → `~/proyectos/ubuntu-permanente/bin/…`; el vigía apunta al par ACTUAL.
3. **Sanear `build/backup-par-bueno/`**: mover `boot_b-lee.img` (par del 28-sep) a
   `historico/`; añadir con **nombres exactos** `boot-ukek13-dsid.img` y
   `s260-boot-dtbo-dpu-iommus.img`; gate: sha256 de cada fichero == sha de la fila del flash
   (#P42 / #P33). Anotar en `SHA-BUENOS.txt` que es copia de artefacto de flash, no read-back
   del dispositivo. Añadir sección «par vigente 30-sep» a `build/gates/SHA-BUENOS.txt`
   (verificar que está trackeado en git — es lo único de P0 que el commit protege).
4. **Preservar árbol kernel**: `df` gate (≥5 GB libres) y `rsync -a /var/tmp/uke-k13-tree →
   build/kernel-pokes/k13-tree` (systemd-tmpfiles limpia /var/tmp por antigüedad).
5. **Staging 0-flash para post-pantalla**: verificar si `mesa libdrm mesa-utils`/`eglinfo`
   están en la tablet (SSH) o stagearlos para instalar por USB (vía A1-auditoria-instalador.md
   §4, WiFi muerto).
6. **Repaso 10 min** de `REFUTADO.md` + `LECCIONES.md` del hermano (tocamos `arm-smmu.c`: las
   rondas 33/35.7/36.2 se pagaron ahí).
7. Commit selectivo local (nada de `git add -A` sobre `build/`).

## P1 — Construir K16 (0 tablet, ~60 min)

1. **Higiene de build (crítico: NO heredar el build dir K13)**: `/var/tmp/uke-k13-build/source`
   es symlink absoluto → árbol K13 y los `.cmd` referencian rutas absolutas K12/K13; un
   `cp -a` del build produciría "K16" = K13 sin parche. Patrón: `cp -a uke-k13-tree →
   uke-k16-tree` + build dir NUEVO `O=/var/tmp/uke-k16-build` con `source` repuntado al árbol
   K16 (patrón mv+symlinks de INFORME-K13 §3).
2. Parche per K16-DISENO **con TODAS las condiciones**: banda 0x1c00/0x1c01, param
   `uke_disp_split` (default 1; 0 = K13), **gating `uke_smmu_es_apps(smmu) &&
   uke_handoff_activo(smmu)`** (sin ella el split tocaría también el kgsl-smmu), insertar
   tras `mutex_lock(&stream_map_mutex)`, unlock antes del return, no reutilizar `idx`.
3. Build desprendido completo: `setsid nohup make -C /var/tmp/uke-k16-tree
   O=/var/tmp/uke-k16-build ARCH=arm64 LLVM=1 MAKE=/usr/bin/make -j16 Image.gz &`.
4. **Repack portado (`repack-k16.py`)** con gates mecánicos:
   - Cmdline: 356 B, campo [44..1584) idéntico a `boot-ukek13.img` byte a byte, substring
     `video=` ausente, 4 tokens `uke_`, sin dobles espacios, loglevel ≥ 7 (para que las migas
     UKE-K16 salgan por ACM — sin esto una muerte muda se lee como "no llegó a armar").
   - Marcadores binarios: UKE-POKE=113, UKE-K12=1, UKE-K13=11 intactos, **UKE-K16 ≥ 1 y
     `uke_disp_split` presentes** (este gate habría cazado el error del build dir).
   - Cpio embebido == cpio K12 (el arming horneado dispara el probe a ~4 s).
   - kernel@4096 + size@8, fin de kernel ≤ AVB0_OFF, total 96 MiB, zonas restantes intactas,
     sha256 de lectura de vuelta, gate de frescura fuente-Image.
5. `INFORME-K16-BUILD.md` (patrón K13). Preparar TAMBIÉN: variante de cmdline con
   `arm_smmu.uke_write_mask=0x1c0` (repack 30 s, sin recompilar — peldaño c') y esbozo K17
   (SMR exacto mask=0 para el dpu a nivel fwspec) por si el wedge es de traducción.

## P2 — Ciclo K16 (1 flash) con todas las redes

**Paso 0**: tablet viva + **semáforo hermano**: `~/proyectos/ubuntu-permanente/docs/ESTADO-ACTUAL.md`
+ últimas filas de `docs/FLASH-LEDGER.md` (su cola define a quién le toca; hoy dice «vuestra
última entrada aquí es la #443»).

**Gates pre-flash** (todos): batería ≥ 3750 mV con cargador de pared, **mV inicial y final
registrados**; portátil enchufado; `fastboot getvar all` (4 retry-counts) antes y después;
≤ 2 escrituras/día; **fila #P44 pre-registrada en AMBOS registros** (PRE-REGISTRO local +
FLASH-LEDGER del hermano, con el matiz de que K16 = **dos cambios juntos** vs el par vigente:
kernel nuevo + retirar `video=DSI-1:d`, justificado en la fila); **estado del par verificado
por SSH** (`boot_b` == `e0ee47dc…`, `dtbo_b` == s260 `6fbb5173…`, misc limpia por partlabel);
lector único de consola armado ANTES **cubriendo la ventana 4,0–4,2 s** (las capturas K13 no
la cubrían); **vigía fastboot retargeteado a K13-dsid+s260, armado ANTES del flash**, con
protocolo pause/resume explícito: `touch /tmp/uke-fastboot-watch.pause` durante flashes Y
mientras se observa un desenlace de muerte (para que no "rescate" y destruya la captura);
`rm -f` tras leer resultados. Fastboot SOLO por teclas físicas.

**Precondición de validez del experimento**: las 3 migas `UKE-K16: display sid=… -> grupo
PROPIO` en consola a ~4,1 s + lectura del volcado SMR del BL (`uke_attach_log=2` ya armado:
¿PINADOS=N?) — sin migas, el experimento es inválido (param/cmdline no aplicados).

**Desenlaces**:
- (a) fbcon pinta → **FOTO** + captura de `status`/`modes` del o82 (la foto sola no cierra el
  objetivo 6) → cierre real exige persistencia: power-cycle **en frío** + 2ª foto.
- (b) VIVE sin pintar → por SSH: `status` del conector + `modetest` BAJO CONTROL, sabiendo que
  en K13 `modetest -c` mató 2× (#P43) y que es diagnóstico, no cierre (los cambios de runtime
  no persisten); sistema desechable, captura armada.
- (c) Wedge → **grep `context fault|global fault|smmu` en consola+dmesg ANTES** de concluir
  rails/reset → peldaño **(c')**: repack `uke_write_mask=0x1c0` (ya preparado en P1.5) →
  si sigue, rails/reset SOLO con GO explícito del dueño. Tras cualquier wedge: power-cycle
  físico (el wedge persiste entre reboots suaves, #P34-bis/#P38).
- (d) Muerte nueva → migas + consola; **techo: 1 retry**; luego restaurar par.

**Escalera de rescate (escrita ANTES del flash)**: wedge/muerte → power-cycle físico (el
watchdog no está arreglado: no contar con recuperación automática) → teclas a fastboot →
verificar mV ≥ umbral (en fastboot NO carga) → `fastboot flash boot_b
build/backup-par-bueno/boot-ukek13-dsid.img` → chequeo BCB/misc por partlabel → reboot. Si el
rescate usara `fastboot boot`: recuerda que usa el dtbo del slot activo (REFUTADO R-12).

**Criterio de parada**: techo de 3 ciclos para la hipótesis K16 (disciplina heredada);
superado → restaurar K13-dsid, documentar, **pivote al clúster 0-flash (P3)**. Éxito mínimo
de sesión: K16 flasheado + desenlace documentado + par bueno restaurado + fila #P44 cerrada
en ambos registros + ESTADO-VIVO/NOTAS/commit.

## P3 — Clúster post-ciclo sobre base estable (NO condicionado a la pantalla)

Renombrado: se ejecuta **con o sin panel**, sobre K13-dsid restaurado si hizo falta. Cada
escritura con su propia fila pre-registrada, gate y rollback. Orden corregido:

1. **e2fsck** (prepara/P7-fsck-f9.md §A) — ANTES de instalar nada y ANTES del test GPU (el fs
   está podrido y creciendo; el test GPU es el punto de riesgo CM3; instalar paquetes antes
   violaría la regla 10).
2. **F1a GPU**: `eglinfo -B` = freedreno + GLES 3.2 sobre `renderD128` (staging del P0.5).
   Matiz: el primer load REAL del fw es el primer open post-switch_root; si el driver no
   reintenta en open, hornear fw vía `CONFIG_INITRAMFS_SOURCE` (vía K17; el ramdisk externo
   está descartado por medición #P30). Escalera `build/cm3-ladder/` como red.
3. **F9 vía E1** (la única parte con flashes, y son **3**: `vendor_boot_a` + `init_boot_a` +
   `boot_a` — un `boot_a` solo dará otro mudo): condicionado a GPT restaurada byte-exacta y
   sin pánicos entre flash y test. Cierra el objetivo 2.
4. **WiFi F3** (payload preparado; ojo regla 9: scripts que borran sin restaurar — caso
   exacto blacklist ath11k de `uke-wifi-trace.sh`).
5. **Omarchy F6**: `install-omarchy-uke.sh` (dry-run; gate EXT4; internet por USB).
6. **F4/F7**: táctil (gate `modinfo vermagic` == `uname -r` del K16 ANTES de cargar los .ko),
   rotación. BT/batería estrictamente DETRÁS de F7/F8 (no son objetivos de la tabla).

**Objetivo 6 completo** = card0 + `modes` del o82 + foto + persistencia (reinicio limpio).

## Criterio global (OBJETIVOS, sin cambios)

Tablet que arranca Omarchy sola, se recupera de un slot roto sin PC, actualiza sin abortar,
y en la que se puede escribir con el lápiz y usar el dedo con la pantalla rotada.
