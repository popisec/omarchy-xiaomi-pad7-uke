# Plan tras el ciclo K27 — dos pistas (2-oct-2026, tras #461)

> ## ⚠️ REESCRITO el 2-oct-2026 (2ª vez) — la versión anterior queda SUPERADA
> Incumple lo que `docs/historia/revision/R7-auditoria-2oct.md` marca como ERROR y lo que `docs/historia/revision/R8-repaso-android.md` y
> `docs/historia/revision/R6-gmu-erange.md` establecen. **No ejecutes su "Paso único" ni su orden propuesto.** Concretamente:
> - ❌ **Pista A**: la prescripción «basta `status="okay"` en `phy@ae97000` en `palawan.dtsi`» es
>   **ERROR por partida triple**: (a) el overlay vivo **ya** trae esa PHY en `okay`; (b) el
>   `disabled` del base es **por diseño** (todo el display base va apagado, el enablement vive en el
>   overlay); (c) el repack **no transporta** el `.dtb`, así que ni siquiera se probaría. Y la
>   palabra «basta» es falsa sin más. La observación dual-DSI sí es correcta. → `R5`, `R7` §A.6.
> - ❌ **Pista B**: la línea «`uke_gmu_shared=1` era un no-op» y el fix UKE-K27 se apoyaban en la
>   premisa **`gpu->vm` es NULL, que es FALSA** (`msm_gpu_init` crea el vm en `msm_gpu.c:974`
>   **antes** de `gmu_init`). El fix está **revertido**. → `R7` §A.1.
> - ❌ **Pista B, línea del volcado**: «no es el volcado SMMU (el ciclo K25 lo probó)» es **ERROR**.
>   K25 murió en `gmu_init` y **no llegó** a la escalera del CM3 ⇒ **no probó H2**; que no llegue
>   **invalida** el test. **H2 sigue abierta.** → `R7` §A.5.
> - ✅ **El `-ERANGE` ya tiene causa raíz** (`R6`): el **quirk TTBR1** del dominio de la GPU acepta
>   sólo la mitad alta del VA; el icache@`0x4000` cae en la baja. Ya no es "el nudo sin explicar".

Estado: tablet **operativa** en el par bueno (K13-dsid + s260) hasta el 2-oct; ahora **en fastboot**
con el experimento K30 preparado (ledger #465). El objetivo sigue siendo **GPU + PANTALLA**. Se
separan en dos pistas porque **la pantalla no depende del CM3**: el DPU/DSI son bloques distintos del
GMU, así que una puede avanzar sin la otra.

---

## Pista A — PANTALLA

**Diagnóstico cerrado (medido):**
- El panel es **dual-DSI** (`o82_42_02_0b_dualdsi_dsc_vid`; ojo con el **`02`**, el contexto lo
  escribió mal y la cmdline viva lo confirma).
- El DPU hace bind de los **dos** DSI, pero `msm_dsi ae96000.dsi: dsi_get_phy: phy driver is not
  ready` aparece. **R5 lo matiza**: ese error es **transitorio** (dos ramas, mismo mensaje,
  `dsi.c:45-53`), compatible con **deferral**, no sólo con `disabled`.
- Consecuencia medida: `card0-DSI-1` = `disconnected`, `modes` vacío. Hay writeback
  (`card0-Writeback-1`) y backlight, pero **no** salta al cuelgue del CM3: el writeback **no**
  lo evita.
- ⚠️ **La premisa se ha dado la vuelta** (`R8` §6.1): **`video=DSI-1:d` NO lo impone el ABL**. No
  aparece en `vendor_boot-stock`, ni en `init_boot-stock`, ni en la cmdline viva. **Es nuestro
  discriminador #P42.** `:d` ⇒ `DRM_FORCE_OFF` (`drm_modes.c:2007-2011`) ⇒ sin modos.
  **Quitarlo hace que el cuelgue esté en el camino de DETECCIÓN del connector, no en el flag.**
- El panel vive en el **dtbo**, que **no tiene backup de fábrica** ⇒ la única referencia es el s260
  (payload vendor). `vendor_boot-stock` **no tiene nodos de panel**.

**Paso 0 — OBLIGATORIO y de 0 flashes: leer el DT VIVO**, no el base:
`/sys/firmware/devicetree/base/soc/…/phy@ae97000/status`. Si ya dice `okay`, la hipótesis de la PHY
está muerta y **no hay nada que flashear** (`R5`, `R7` §A.6).

**Candidatos reales, por coste (los tres de `R8` §7 — ninguno es aún un ciclo):**
1. **Apagar el SSC en ambas PHY** (`qcom,dsi-pll-ssc-disable`, que es lo que hace el vendor en s260
   fragment@103/104; la base lo trae con `down-spread`). Si arrancamos con SSC **on** contra un panel
   que de fábrica va con SSC **off**, el link DSI puede no enganchar **aunque todo bindee** —
   exactamente el síntoma "todo OK, pantalla negra". Es el más barato: sólo DT de overlay.
2. **Alinear `memmap` al splash de fábrica**: `memmap=0x2B00000$0xE3940000` (**43 MB**) en vez de
   `0x1A12800` (26 MB). El vendor reserva 43 MB de cont-splash en esa base y 20 MB de rdump; nuestra
   reserva intermedia deja **17 MB de framebuffer del ABL desprotegidos**. Si el cuelgue al detectar
   es pisada de memoria y no del link, **este es el candidato más barato** (sólo cmdline, sin DT).
3. **Auditar el driver `o82` contra los 6 números de fábrica** (`R8` §3): clockrate
   **1.190.788.720**, porches por fps (h-front variable **113@120 / 18@144 / 304@90**), reset-sequence
   `0 10 1 3 0 3 1 15`, 5,8 V/1,9 V, topología dual `2-2-2`, y el nombre `o82_42_02_0b`. El driver
   propio **sólo expone 120 Hz estático** (`R5`): si el modeset programa el porch del timing
   equivocado, el panel no engancha **aunque los comandos on vayan bien**.

⚠️ **No tratar las ediciones de cmdline `video=` como de bajo riesgo**: `:d` mantiene el arranque
estable; **quitarlo cuelga la máquina**. El artefacto `boot-ukek13-dsid-vid.img` (sha `990fbd6f…`,
parche de 2 bytes quitando `:d`) **YA FALLÓ — no reutilizarlo**.

---

## Pista B — GPU

**Lo que está cerrado (medido):**
- El icache@`0x4000` del GMU no se consigue mapear en **ninguna** de las 6 configuraciones probadas:
  | # | config | síntoma |
  |---|---|---|
  | 1 | **s260 + `shared=1`** (default de K25) | `-ERANGE` (-34), bajo el quirk **TTBR1** del dominio **compartido** |
  | 2 | s263 + dominio propio | `-EBUSY` (-16), en el GMU |
  | 3 | s263 + fix K27 | `-EBUSY` (-16), en la GPU |
  | 4 | s260 + `shared=0` | el GPU ni probean (**sin diagnóstico**: K24) |
  | 5 | **s263 + `shared=0`** | **NO PROBADA NUNCA** (ledger #464) — la única casilla vacía |
  | 6 | s263 + `shared=1` (= K26) | `-EBUSY` |
- **Causa raíz del `-ERANGE` (`R6`)**: quirk **TTBR1** del dominio de la GPU (vía `iaext` en
  `io-pgtable-arm.c:599`); acepta sólo la mitad alta del VA. La primera víctima es
  `debug@0x60400000`, **no** el icache; el icache@`0x4000` **mapea bien** en un dominio normal.
- **s263 es lo que usa fábrica** (`R8` §4): el DT de stock declara GMU con **SID 5**. No cambiar.
  Pero ojo (`R7` §A.4): "obligatorio **para esta vía**", **no** "solución" — con s263 el grupo
  compartido impide el doble attach, que es justo el `-EBUSY`.
- **Hallazgo de coste cero (2-oct)**: bajo **s260, GPU y GMU están en grupos IOMMU DISTINTOS**
  (grupo **0** y grupo **1**) ⇒ no pueden chocar ⇒ por eso **s260 nunca da `-EBUSY`**. El
  `uke_attach_log=2` funciona y para apps-smmu deja el dominio **sin traducir** por el handoff del
  bootloader.

**El nudo que queda** (reformulado por `R10` E3; mi versión anterior era **falsa en la mitad "sin"**):
el rechazo del iova `0x4000` es propiedad **exclusiva** del dominio **TTBR1-compartido** — en
dominio **plano** el `0x4000` **sí mapea** (`fw-map icache iova=0x4000`, `R6` §3). Lo único **sin
diagnosticar** es **K24** (s260 + `shared=0`), que es justo lo que K30 re-mide. Sigue siendo lectura
de `msm_mmu`/`msm_gem` (geometría/apertura), no del dtbo ni de la cmdline.

**Ciclo en marcha (ledger #465, predicciones P20–P22 antes de medir)**: `boot-ukek30.img`
(sha `d1c24835…`) = k18-tree con **K27 revertido** + `uke_gmu_shared=0` sobre **s260**. Es la
**config #4**, la única ya probada y fallida **sin diagnóstico**. Se elige s260 a propósito: bajo s260
la tablet **arranca con red aunque el GMU falle** (medido en K25) ⇒ el error se lee **por SSH**,
no por una consola ACM que pierde líneas justo en el momento crítico.
- **P20**: `gmu init ret=0` ⇒ el `-ERANGE` **era** el TTBR1 y el GPU probean.
- **P21**: `gmu init ret=-34` ⇒ el dominio propio también lo tiene ⇒ otra causa.
- **P22**: GMU mapea y GPU probean ⇒ abrir DRM **una vez** con `uke_smmu_dump=1` = **el test H2
  de verdad** (el que K25 **no** pudo hacer).

---

## Orden propuesto (corregido)

1. **Pista B, ciclo K30** (1 escritura): es el único experimento **pre-registrado y con predicciones**,
   y ataca el diagnóstico que falta. No requiere tocar el DT ni la cmdline.
2. **Pista A, paso 0 sin flashes**: leer el DT **vivo** de las dos PHY + volcar el DT vivo del panel y
   **diff contra s260 fragment@95**. Con R8 ya tenemos los 6 números de fábrica contra los que diffear.
3. **Pista A, primer ciclo real**: el candidato **más barato** de los tres de `R8` §7 (SSC), no el
   `status="okay"` que proponía este documento antes de ser reescrito.

**Rollback**: par bueno en `build/backup-par-bueno/` (`boot-ukek13-dsid.img` sha `e0ee47dc…` +
`s260` sha `6fbb5173…`). ⚠️ **1 escritura**: sólo se sustituye `boot_a`; el `dtbo` se queda.
⚠️ **`slot b` sigue `unbootable`: no hay rollback arrancable.**
**Escrituras hoy**: 7 el 1-oct (con la exención ilimitada del dueño); 0 la noche del 1→2-oct hasta el
flash de K30.