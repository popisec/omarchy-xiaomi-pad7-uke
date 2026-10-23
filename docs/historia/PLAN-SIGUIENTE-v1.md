# PLAN DE TRABAJO — omarchy-uke (v1, borrador para crítica, 30-sep-2026)

> Restricciones del dueño: **el git no se toca** (local-only; sin remotos, sin reescritura de
> historial, sin tocar blobs ya trackeados). Los commits rutinarios del protocolo se pueden
> hacer, pero nada de reestructurar el repo. **No se ejecuta nada en la tablet en esta sesión
> de planificación**: el plan es para las próximas sesiones.

## Estado de partida (ESTADO-VIVO 30-sep 21:00)

Tablet **VIVA y ESTABLE en Arch**: `boot_b` = K13-dsid (`e0ee47dc…`), `dtbo_b` = s260
(`6fbb5173…`), misc limpia, SSH OK (192.168.42.129), batería ~60%. KMS completo: `card0`
+ `renderD128` nacidos, pero **abrir card0 wedgea el bus** (HOST DSI arrastrado al dominio
paging por grupo iommu compartido). Único bloqueo de pantalla. Fix diseñado: **K16**
(`build/gates/K16-DISENO.md`, completo y ejecutable). Firmwares GPU verificados en rootfs.
Fuente de los parches K en git (`patches/k13-grupo-iommu.diff`, `build-pokes.sh`, informes).

## P0 — Cierre documental y red de seguridad (0 tablet, ~30 min)

1. **Contradicciones**: OBJETIVOS fila 2 (F9: «causa resuelta, GPT reconstruida #P31;
   verificación end-to-end pendiente») y fila 3 (K7 → K13-dsid). Banner SUPERSEDED en
   `docs/historia/RUNBOOK-MAÑANA.md` (apunta a RUNBOOK-SIGUIENTE).
2. **docs/historia/AGENTS.md**: banner arriba — «par vigente y estado del aparato: SOLO docs/historia/ESTADO-VIVO.md» +
   corregir `bin/…` → `~/proyectos/ubuntu-permanente/bin/…`.
3. **Backup del par actual**: `cp` de `boot-ukek13-dsid.img` + `s260-…img` a
   `build/backup-par-bueno/`; shas añadidos a `SHA-BUENOS.txt`.
4. **Preservar el árbol kernel**: rsync `/var/tmp/uke-k13-tree` → `build/kernel-pokes/k13-tree`
   (/var/tmp lo limpia systemd-tmpfiles por antigüedad).
5. Commit local de lo anterior (protocolo; git structure intacta).

## P1 — Construir K16 (0 tablet, ~45 min; per K16-DISENO.md)

1. `cp -a /var/tmp/uke-k13-tree → /var/tmp/uke-k16-tree` (+ directorio build).
2. Parche ~15 líneas en `arm_smmu_device_group`: split de grupos para banda display
   0x1c00/0x1c01, param `uke_disp_split` (default 1; 0 = comportamiento K13), migas UKE-K16.
   Respetar las notas del diseño (mutex antes del check, unlock antes del return, NO reutilizar
   `idx` del bucle de abajo).
3. `make Image.gz` DESPRENDIDO (setsid nohup, `MAKE=/usr/bin/make`, `LLVM=1`).
4. Repack patrón k13: cmdline de `boot-ukek13.img` BYTE A BYTE (356 B, offset 44) — **SIN
   `video=DSI-1:d`** (el panel DEBE modesetear en el boot). Gates de repack + sha256.
5. Informe `INFORME-K16-BUILD.md` (patrón K13).

## P2 — Flash K16 y prueba de pantalla (1 flash, ~30 min)

**Gates pre-flash** (todos obligatorios): batería ≥ 3750 mV con cargador de pared; portátil
enchufado; fila **#P44** pre-registrada (sha256, predicciones, rollback = K13-dsid); lector
único de consola armado ANTES; fastboot SOLO por teclas físicas; comprobar semáforo del
proyecto hermano (su ESTADO-ACTUAL + últimas filas del ledger) antes de tocar.

Desenlaces per K16-DISENO: (a) VIVE + fbcon pinta = **PANTALLA** → FOTO; (b) VIVE sin pintar →
SSH: status del conector + modetest bajo control; (c) wedge igual → rails/reset del panel
(INFORME-GPIO-*, AUDITORIA-REGULADORES); (d) muerte nueva → migas UKE-K16 + consola.

## P3 — Tras la pantalla (orden de OBJETIVOS)

1. FOTO como evidencia de cierre del objetivo 6.
2. **F1a GPU**: `eglinfo -B` = freedreno + GLES 3.2 (renderD128 ya existe; fw verificado). Si
   cuelga el CM3 → escalera `build/cm3-ladder/` (measure-cm3.sh antes de abrir nada).
3. **e2fsck** (prepara/P7-fsck-f9.md) ANTES de instalar nada grande.
4. **F9 verificación**: un `boot_a` nuevo llega a `Linux version` en consola (cierra objetivo 2).
5. **WiFi F3** (payload preparado; discriminador D1 en P3-wifi.md).
6. **Omarchy F6**: `install-omarchy-uke.sh` (dry-run primero; gate EXT4; internet por USB per
   A1 §4).
7. **F4/F7**: táctil (novatek .ko), rotación (libssc+ADSP), BT, batería (scripts + módulos).
8. **F8 producto**: 3 reinicios limpios con retry 7 · `omarchy update` sin abortar ·
   recuperación ejercida 1 vez.

## Disciplina transversal (no negociable, heredada)

Un cambio por ciclo con fila pre-registrada · doble captura (consola + ssh dmesg -w) ·
`sync` antes de reinicios · nunca unbind del apps-smmu · techo de 3 ciclos por hipótesis ·
hallazgos con evidencia (comando+salida o URL) · al cierre de cada sesión: ESTADO-VIVO +
entrada en NOTAS + commit local.

## Criterio global de éxito (OBJETIVOS)

Tablet que arranca Omarchy sola, se recupera de un slot roto sin PC, actualiza sin abortar,
y en la que se puede escribir con el lápiz y usar el dedo con la pantalla rotada.
