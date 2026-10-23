# K16 — DISEÑO EJECUTABLE (display split: cada master su grupo)

Estado: **DISEÑADO, no compilado** (30-sep-2026 noche). El parche es de ~15 líneas; este doc
contiene todo lo necesario para construirlo sin volver a investigar.

## El diagnóstico que lo motiva (#P43 + lectura de código)

1. `qcom_smmu_def_domain_type` (arm-smmu-qcom.c:740-758) **YA devuelve IOMMU_DOMAIN_IDENTITY
   para todos los masters salvo el WLAN** — el dominio por defecto NO es el problema.
2. El problema: dpu (`ae01000.display-controller`) + mdss (`ae00000.display-subsystem`) +
   `soc:qcom,smmu_sde_unsec_cb` comparten el SID 0x1c00 (iommus `<0x129 0x1c00 0x2>`) →
   `arm_smmu_device_group` (arm-smmu.c:2912, fusión por `smmu->s2crs[idx].group` compartido +
   `generic_device_group`) los funde en UN grupo.
3. El fallback de K13 (`iommu_attach_group`, msm_iommu.c) attachó ese grupo ENTERO al dominio
   PAGING que el KMS crea con `iommu_paging_domain_alloc` → **el HOST DSI (ae94000/ae96000.dsi,
   que iba en identity y funcionaba) quedó arrastrado al dominio paging sin tablas → sus
   comandos DSI al panel faultean → wedge del bus** (medido: abrir card0 con `modetest -c`
   mata, incluso con el fw sqe oculto ⇒ no es el GPU).
4. En la era s258 (SMMU sin bindear) el panel probaba BIEN (backlight 307, reset OK) — el DSI
   host sin iommu = bypass = lo mismo que identity.

## El parche (en /var/tmp/uke-k16-tree, copia de uke-k13-tree)

En `drivers/iommu/arm/arm-smmu/arm-smmu.c`, función `arm_smmu_device_group` (:2912), tras
obtener cfg/fwspec/smmu y ANTES del bucle de fusión por SME:

```c
	/* UKE-K16 (#P43): banda display (0x1c00/0x1c01) con grupos INDIVIDUALES.
	 * La fusión por SME compartido arrastraba al HOST DSI (identity, funcionaba)
	 * al dominio paging del KMS → comandos DSI faulteaban → wedge del bus.
	 * Con split: dpu solo en su grupo (attach_device pasa sin fallback), DSI host
	 * y mdss quedan en identity (como en la era s258). */
	if (uke_disp_split && uke_smmu_es_apps(smmu) && uke_handoff_activo(smmu)) {
		int j;
		for_each_cfg_sme(cfg, fwspec, j, idx) {  /* NO: idx/i ya usados abajo — usar sid directo */
		}
	}
```

Implementación limpia (la de arriba es el esquema; la real): iterar `fwspec->ids[]` buscando
`0x1c00` o `0x1c01`; si hay match:

```c
	struct iommu_group *g = generic_single_device_group(dev);
	if (!IS_ERR(g)) {
		pr_info("UKE-K16: display sid=0x%04x -> grupo PROPIO (split)\n",
			(u32)fwspec->ids[0]);
		mutex_unlock(&smmu->stream_map_mutex);
		return g;   /* sin grabar s2crs[idx].group: cada quien el suyo */
	}
```

- Param nuevo `uke_disp_split` (int, default 1, module_param; 0 = comportamiento K13) al lado
  de `uke_handoff` (:585).
- `generic_single_device_group` está exportada (include/linux/iommu.h:1126) — la usan otros
  drivers de iommu.
- CUIDADO: coger el mutex ANTES del check (la función ya lo coge al entrar — insertar el
  bloque justo después del `mutex_lock(&smmu->stream_map_mutex);`), y el return con unlock.
- Los SME pineados del UFS (idx 0) no se tocan (los display tienen sus propios idx ≥ 1).

## Cmdline y empaquetado

- Cmdline K16 = la de `boot-ukek13.img` BYTE A BYTE (356 B, offset 44) — **SIN `video=DSI-1:d`**
  (el panel DEBE modesetear en el boot).
- Repack patrón k13 (base s240 `e3c60969…`, kernel@4096+size, AVB, 96 MiB, gates completos).

## Escalera de disparo (con desenlaces)

boot → arming ~4 s → SMMU (split: 3 migas `grupo PROPIO`) → dpu attach paging (grupo de 1,
sin fallback) → modeset → panel enable (DSI host en identity) → **fbcon pinta** → FOTO.

- (a) VIVE + texto en pantalla = **PANTALLA CONSEGUIDA** → Fase 2 (fw GPU para render).
- (b) VIVE sin texto → por SSH: `cat /sys/class/drm/card0-DSI-1/status` + `modetest` BAJO
  CONTROL (abrir card0 ya no debería wedgear: DSI host en identity).
- (c) WEDGE igual → el DMA NO era: sospechar enable de rails/reset del panel
  (`INFORME-GPIO-*.md`, `AUDITORIA-REGULADORES-Y-GPIO.md`).
- (d) muerte nueva → las migas UKE-K16 + consola (lector de ciclos ya probado).

## Estado de la tablet al cierre

VIVA y ESTABLE con **K13+DSI-1:d** (`boot-ukek13-dsid.img` e0ee47dc… en boot_b, s260 en
dtbo_b, misc limpia): SSH funciona, card0+renderD128 presentes. NO tocar card0 desde esa
sesión (abrirlo wedgea — es el bug que K16 arregla). Firmwares GPU verificados en el rootfs.
Batería ~60%.

> ⚠️ **RESULTADO #P44 (30-sep noche) — el diagnóstico §"El diagnóstico que lo motiva" quedó
> REFUTADO por el experimento**: K16 y K16-wm se flashearon (7 ciclos cada uno) y mueren
> IGUAL que K13 sin `:d`. El split eliminó el -22 del core y el kms pasó (adreno_request_fw
> 4,15 s), pero el modeset del panel mata en las tres configuraciones SMMU ⇒ el asesino está
> en el CAMINO DEL PANEL (rails/reset/GPIO/DSI), no en dominios/grupos/traducción. Además,
> la implementación corrigió este diseño: `generic_single_device_group()` NO sirve (singleton
> por IOMMU); se usó `iommu_group_alloc()` — ver INFORME-K16-BUILD.md §Corrección de diseño.
> Este fichero queda como historial del diseño; el estado manda en docs/historia/ESTADO-VIVO.md.
