# CRÍTICA adversarial FIX-A1 (reclaim SMMU display) — 14-oct-2026

## VEREDICTO: **NO-PASA** compilar+flashear L51 con `fix-smmu.diff` tal cual

Un bloqueante (B1) hace que el reclaim **no se ejecute nunca**: L51 quemaría
un flash probando `wmask=0x1C0` sin reclaim (= F1/A0, que el diseño
ya pronostica que falla). Tras corregir B1+B2: PASA condicionado.

## B1 (BLOQUEANTE): el reclaim no dispara — `count[2]==1` por qcedev

- El diff exige `smmu->s2crs[uke_r].count == 0` (`fix-smmu.diff:50-51`).
- Medido en `out/CAPTURA-L50-dmesgw.log:1831`: qcedev toma la rama
  K8-handoff sobre **idx=2 PINADO** 1 ms antes del display (`:1904`,
  `find_sme(display)→20`). Esa rama hace `count++` (`arm-smmu.c:2373`)
- Luego en el attach del display `count[2]≥1` ⇒ condición falsa ⇒ rama
  `else` ("sin entrada BL reutilizable") ⇒ **idx intacto (20)**. El fix
  es un no-op silencioso; solo quedan los 19 writes de B2.
- El error: la guarda confunde "reclamado en RAM" (qcedev, sid 0x481 que
  **nunca casó en HW** con SMR(2)=0x1c00) con "dueño legítimo". El criterio
  de propiedad ya lo da la LECTURA HW del SMR (sid+mask casan); el
  bookkeeping RAM está envenenado por el handoff espurio.
- **Corrección exigida**: eliminar `smmu->s2crs[uke_r].count == 0` (basta
  con param + apps + `sid==0x1c00 && mask==0x2` + match HW + `uke_r!=idx`).
  Re-hacer `patch -p1 --dry-run`. (A2 `docs/historia/revision/PIPELINE-PANEL-20261014/fix-bypass.diff:49-50` tiene el
  mismo bug: corregirlo igual si se usa.)
- Efecto colateral a vigilar tras corregir: qcedev queda con `smendx=2`
  apuntando a la entrada del display; su traducción HW no cambia (jamás
  casó), pero un futuro `free` suyo tocaría bookkeeping ajeno. En L51,
  grep `qcedev` en dmesg: no se espera ningún release (drivers fijos).

## B2 (BLOQUEANTE documental): `wmask=0x1C0` NO es "solo display"

- `FIX-SMMU-CLOCKS.md:18` dice "solo se toca la entrada de ESE sid". Falso
  para la componente wmask (solo el reclaim es scoped).
- Medido: con `0x0` hay **19 `wmask[attach_sme]: SILENCIADO`** (dmesgw: idx
  5–22: GENI×2, GPI-DMA, CAM×8, WCN, SDE×2, TMC×2, display) + 1 install +
  1 ctxbank. Con `0x1C0` esos **19 write_sme (SMR+S2CR) SE EJECUTAN**.
- Exigir al doc: reconocer los ~40 writes nuevos y que el modo de fallo
  cambia (ver R1). Opcional (no bloqueante): scoping por idx reclamado
  para no mover a CAM/WCN/GENI de contexto a mitad de boot.

## Verificado OK (no bloquea)

1. **Aplica limpio**: `patch -p1 --dry-run` sobre el árbol con K50 → OK.
   2 hunks donde dicen (param :435, reclaim tras `idx=ret;` :2342).
2. **Lectura SMR segura**: solo `arm_smmu_gr0_read(SMR)` en bucle 0–109,
   igual que el barrido K8 (medido seguro #P9); S2CR jamás se lee (#P13
   respetado); ocurre en boot ~4.08 s, no runtime (regla 3 OK).
3. **CB69 se programa en el ATTACH, no en el reset**: `attach_dev` llama
   `init_domain_context→write_context_bank(69)` y DESPUÉS `install_s2crs`
   (orden correcto: CB válido antes de que el S2CR apunte). `reset_mask=12`
   omite F2/F3 pero el attach no depende del reset; dmesgw:2810-2811
   prueba que el camino se alcanza (hoy silenciado por bit8=0). Con bit8=1
   + CB69 "desde arriba" (:2809) → escribe. `0x1C0`=bits 6+7+8 confirmado
   en `arm-smmu.h:622-624`; el aviso del doc de que `0x180` era insuficiente
   es correcto (`:2507` gatea el SMR).
4. **Defaults/reversión exactos**: `uke_disp_reclaim` (bool, 0) + wmask (0)
   ⇒ reclaim saltado + todo silenciado = K8/K12 bit a bit. Sin conflictos
   con `keep_boot=1/smr_max=0/attach_log=2/reset_mask=12` (el reset sigue
   ~inerte: F4–F7 silenciados por bits 0–3=0).
5. **Sin neutralización**: tras des-pinear, ni `uke_pinado` (:2362) ni
   `uke_sme_es_bl` (:2420, `smrs[2].valid` RAM=false — el barrido solo toca
   `pinned`) ni `uke_preservar` (local por llamada, :2311) bloquean el write.
   Sin B1, write_sme(2) + install(2,TRANS→69) + CB69 llegan a HW.
6. **Handler**: K39/disp se registra tras programar el CB ⇒ un fault en CB69
   al attach; la ventana alloc→install hereda el silencio del CB del BL).

## Riesgos rankeados (tras corregir B1)

- **R1**: muerte de BOOT a ~4.08 s (pre-ssh) si alguno de los 19 writes es
  letal. Peor modo que hoy (muerte a 1389 s con ssh vivo). Recuperación:
  reset físico (watchdog R-42 sin arreglar) + fastboot al par bueno.
  Mitigan los guards K8/`uke_pinado` (muerte-modo-K3 estructuralmente
  imposible en idx pineado) y que los 19 van a idx HW-inválidos.
- **R2**: el SID del cmd-DMA no es 0x1c00/0x2 (asumido, L50-SMMU §7) ⇒
  reclaim bien ejecutado pero la muerte sigue igual. Es el FALLA informativo.
- **R3**: scanout del splash en la ventana alloc→install (S2CR(2) con valores
  RAM transitorios) ⇒ basura/fault silencioso pre-modeset. No fatal esperado.
- **R4**: cambio de contexto de WCN/CAM/GENI (B2) ⇒ periféricos degradados
  sin colgar el boot; ssh (RNDIS/USB, fuera de los 19) sobrevive.
- **R5**: bookkeeping idx2 compartido con qcedev (B1) ⇒ observar, no actuar.

## Gates `repack-k52L50.py → repack-k52L51.py`

- Cmdline: `580 + 30 + 28 = 638 B` (` arm_smmu.uke_write_mask=0x1C0` +
  ` arm_smmu.uke_disp_reclaim=1`; son 58 B, no ~59). Ajustar el `!= 580` (G2)
  a `!= 638` + añadir ambos tokens a append/require.
- Strings: `UKE-POKE 115 → 117` (2 literales nuevos del fix), `K50-` sigue
  en 18, `S4-DIAG` en 4; añadir `FIX-A1==2` y `arm_smmu.uke_disp_reclaim==1`
  (nombre vía KBUILD_MODNAME, igual que los params existentes).

## Criterio L51 (endurecido)

- **PASA** = dmesg trae `FIX-A1: reclaim display: SMR(2)… lo reutiliza`
  (sin esta miga el test es NULO, no FALLA) + netconsole supera
  `K47-host-xfer` (DCS completa / S4-DIAG / muerte movida).
- **FALLA** = misma muerte con miga de reclaim presente (no era traducción,
  o R2) o muerte de boot ~4 s (R1 → rollback L49/L48). Menor: la rama `else`
  imprime sin `pr_flush` — añadirlo o la miga NULO puede perderse.
