# R5 — Panel dual-DSI: por qué no enlaza y qué cambio mínimo lo arregla

**Solo-lectura 2-oct-2026. Árbol NO tocado (`build/kernel-pokes/` intacto). Único fichero escrito: este.**
Base de código: `build/kernel-pokes/k18-tree` (mainline, líneas verificadas por lectura directa).
DT base: `build/kernel-pokes/k18-tree/arch/arm64/boot/dts/qcom/palawan.dtsi` (=`BASE`).
Overlay vivo de display: `~/gpu-work/ramaa/s21/dtbo-gpu/fase4-display.dts` (=`OVL`, fuera de este repo).
DTS propio k18: `build/kernel-pokes/k18-tree/arch/arm64/boot/dts/qcom/xiaomi-uke.dts` (=`UKE-DTS`).
Docs previas: `docs/historia/revision/V4-panel-dpu.md` (=`V4`), `docs/historia/revision/PLAN-2OCT-pantalla-y-gpu.md` (=`PLAN`).

**Medido** = fichero:línea leídos en el árbol. **Hipótesis** = marcado como tal. §7 lista lo no verificable.

---

## 0. Veredicto (escéptico, primero)

**La hipótesis "basta poner `status = "okay"` en `phy@ae97000`" es INCORRECTA como explicación de lo medido, e insuficiente como fix.** Tres razones decisivas, cada una verificada en código:

1. **El síntoma `disconnected` + `modes` vacío lo explica por completo la cmdline `video=DSI-1:d`, sin mirar la PHY.** La `d` fuerza el conector a OFF (`drm_modes.c:2011`), el log `[drm] forcing DSI-1 connector off` sale de `drm_connector.c:173-175`, y con force=OFF el núcleo pone `disconnected` **sin llamar a detect** (`drm_probe_helper.c:589-596`) y sale **antes de pedir modos** (`drm_probe_helper.c:641-649`). Con `:d` presente, sysfs dirá `disconnected`+vacío **aunque el enlace DSI esté perfecto**.
2. **El error `dsi_get_phy: phy driver is not ready` es ruido transitorio de orden de probe, no un estado final.** Coexiste en el mismo dmesg con `bound ae96000.dsi` y con el backlight `ae94000.dsi.0` existente — y demuestro en §2 que el backlight **no puede existir** si la PHY de `ae96000` siguiera ausente. Fue un `-EPROBE_DEFER` de una ronda temprana que luego se resolvió.
3. **El `okay` que se propone ya existe donde importa.** El overlay vivo `OVL` ya trae `phy@ae97000` en `status = "okay"` (OVL:509), con su `vdds-supply`, sus relojes, y ambos DSI en bonded. El `disabled` citado está en el `BASE`, que es así **por diseño** (todo el display base está apagado; el enablement vive en overlay). Habilitar la PHY en `BASE` no cambia nada si el boot usa el overlay — y si el boot NO usa overlay, faltarían también DSI0, DPU, panel y relojes, no solo esta PHY.

Lo que sí falta (y sí es mínimo): quitar el confusor `:d` para medir de verdad, y verificar contra el **DT vivo** (`/proc/device-tree`, no el `BASE`) qué está realmente habilitado. Tabla de cambios candidatos en §8.

---

## 1. Origen exacto de `dsi_get_phy: phy driver is not ready`

Emisor: `drivers/gpu/drm/msm/dsi/dsi.c:25-56` (`dsi_get_phy`), llamado desde `dsi_init` (`dsi.c:102`), a su vez desde `dsi_dev_probe` (`dsi.c:169-184`).

```c
phy_node = of_parse_phandle(pdev->dev.of_node, "phys", 0);   // dsi.c:31
...
phy_pdev = of_find_device_by_node(phy_node);                  // dsi.c:37
if (phy_pdev) {
    msm_dsi->phy = platform_get_drvdata(phy_pdev);            // dsi.c:39
    msm_dsi->phy_dev = &phy_pdev->dev;                         // dsi.c:40
}
...
if (!phy_pdev) {  // dsi.c:45-48 → "phy driver is not ready", -EPROBE_DEFER
if (!msm_dsi->phy) {  // dsi.c:49-53 → MISMO mensaje, -EPROBE_DEFER
```

Qué es "el phy driver": **el `platform_driver` `msm_dsi_phy`** registrado en `dsi.c:222` (`msm_dsi_phy_driver_register`), cuyo probe es `dsi_phy_driver_probe` (`drivers/gpu/drm/msm/dsi/phy/dsi_phy.c:613`) con tabla `dsi_phy_dt_match` (`dsi_phy.c:516-590`). NO es un `devm_phy`/`generic-PHY`: es un drvdata propio (`struct msm_dsi_phy`, `platform_set_drvdata` en `dsi_phy.c`, probe ~:690).

Condición exacta: hay **DOS ramas con el mismo mensaje** y el dmesg no las distingue:

- **Rama A (`dsi.c:45-48`, `!phy_pdev`)**: el nodo PHY no tiene `platform_device` = ausente del DT vivo o `status = "disabled"`. Causa DT, no de driver.
- **Rama B (`dsi.c:49-53`, `!msm_dsi->phy`)**: el dispositivo existe pero su driver aún no hizo probe/bind (transitorio normal de orden de probe) **o** el probe de la PHY falló (falta `vdds-supply`, relojes `iface`/`ref`, `reg` sin mapear, sin match de compatible → `-ENODEV` en `dsi_phy.c:613-660`).

Cómo distinguirlas en vivo (0 flashes): `ls /sys/bus/platform/devices | grep ae97` (¿existe el dispositivo? No = rama A; sí sin enlace `driver` = rama B) + `cat /sys/kernel/debug/devices_deferred` + **contar repeticiones** del mensaje: una sola aparición temprana seguida de `bound` = deferral resuelto, ruido. Si se repite en cada re-probe sin `bound` posterior = bloqueo real.

## 2. Qué hace el driver con el fallo, y por qué `bound` coexiste con el error

- `dsi_init` falla → `dsi_destroy` + `ERR_PTR(ret)` (`dsi.c:113-115`); `dsi_dev_probe` propaga el error **salvo `-ENODEV`** (`dsi.c:175-181`, "Don't fail the bind if the dsi port is not connected"). `-EPROBE_DEFER` ⇒ reintento posterior. **No hay estado "DSI a medio gas"**: o se registra en el manager o no existe.
- El `bound ae96000.dsi` lo imprime el framework genérico de componentes (`drivers/base/component.c:672`, `bound %s`), cuyo `component_add` para DSI ocurre **mucho después**, en `dsi_host_attach` (`dsi_host.c:1744`, `dsi_dev_attach`) cuando el panel hace `mipi_dsi_attach`. Cadena: ambos DSI registrados (`msm_dsi_manager_register`, `dsi_manager.c:554-590`) → hosts registrados esclavo-primero (`dsi_manager.c:106-118`) → panel encuentra el host secundario (`o82_probe`, `panel-xiaomi-o82-dualdsi.c:628-638`; si falta → `-EPROBE_DEFER` en :637-638) → crea backlight (`o82:655-658`) → attach de ambos (`o82:662-674`) → `component_add` → `bound`.
- **Prueba lógica**: el backlight `ae94000.dsi.0` existe ⇒ `o82_probe` superó la línea :638 (host secundario presente y registrado) ⇒ en ese momento **ambos DSI tenían PHY** (sin `dsi_get_phy` OK no hay `msm_dsi_manager_register`, `dsi.c:101-109`). Luego el `not ready` medido fue una ronda de probe anterior, resuelta después. **Hipótesis de PHY persistentemente ausente: refutada por el propio backlight.**
- Corolario bonded: con `qcom,dual-dsi-mode`, si solo un DSI se registra, `dsi_mgr_setup_components` **no registra ningún host** (`dsi_manager.c:87` exige `other_dsi`); el panel nunca puede atascarse "a medias": o todo el par llega, o nada llega. El estado vivo (backlight sí) = el par llegó.

## 3. ¿Bastaría `status = "okay"` en `phy@ae97000`? (a)(b)(c)

**(a) Registro del driver: SÍ está cubierto si el nodo está habilitado.** `CONFIG_DRM_MSM_DSI_7NM_PHY=y` en las configs del proyecto (`build/kernel-config/k24.config:4982`, k25 igual). La entrada `qcom,sm8650-dsi-phy-4nm` existe en la tabla (`dsi_phy.c:578`, bajo `CONFIG_DRM_MSM_DSI_7NM_PHY`) y casa por **segundo compatible** del nodo (`palawan-dsi-phy-4nm` no tiene entrada propia; el fallback a `sm8650` sí). La config ligada es `dsi_phy_4nm_8650_cfgs` (`dsi_phy_7nm.c:1485-1508`): `io_start = {0xae95000, 0xae97000}`, `num_dsi_phy = 2` ⇒ `dsi_phy_get_id` identifica ambas PHY por su `reg "dsi_phy"` (`dsi_phy.c:591-611`). `dsi_phy_driver_probe` exige además mapear `dsi_phy`+`dsi_pll`+`dsi_phy_lane` (`dsi_phy.c:660-690`), regulador `vdds` (98000 µA, `dsi_phy_7nm.c:1251-1253`) y `pll_init` + proveedor de relojes (`dsi_phy.c:~700-727). El `OVL` ya da `vdds-supply = <&L2B>` (OVL:505) y relojes `iface`+`ref` (OVL:498-503) a **ambas** PHY, ambas `okay` (OVL:424, OVL:509).

**(b) PLL/reloj/calibración: el esclavo NO usa su PLL.** `OVL:450-451` pone los `assigned-clock-parents` de `dsi1` al **PLL de dsi0** (bonded, como en elish); el manager marca usecase MASTER/SLAVE (`dsi_manager.c:99-102`) y enciende ambas PHY en `power_on` (`dsi_manager.c:223-241`) y ambos hosts en `pre_enable` desde el master (`dsi_manager.c:290-310`). Poner `okay` en la PHY sin este cableado de relojes no bastaría; con el `OVL` ya viene hecho.

**(c) ¿Single-DSI posible? No para este panel.** El driver lo exige: sin nodo remoto al host secundario → `-ENODEV` (`o82:628-632`); sin host secundario → `-EPROBE_DEFER` (`o82:637-638`); atacha **los dos** (`o82:662-674`) y emite comandos duales (`o82:344-356`, `mipi_dsi_dual_dcs_write_buffer_multi`). En DT mainline no existe `qcom,dsi-dual-link` (nombre downstream); el bonded se declara con `qcom,dual-dsi-mode` (+`qcom,master-dsi` en dsi0, +`qcom,sync-dual-dsi`), leído en `dsi_manager.c:54-63`. El `BASE` **no trae ninguna** de estas tres propiedades en sus nodos DSI (`BASE:3471-3644` verificado: ni `dual-dsi-mode` ni panel ni supplies); el `OVL` sí (`dual-dsi-mode` OVL:314+460, `master-dsi` OVL:315, `sync` OVL:318, panel@0 OVL:352-389 con ports a ambos DSI). Conclusión: el bonded entero vive en el overlay; el `BASE` es solo silicio apagado.

## 4. Qué pone el conector en `connected` (y qué lo deja en `disconnected`)

- El conector DSI se crea vía `drm_bridge_connector_init` (`dsi_manager.c:456-488`, :482). Su `detect` **no mide el link**: sin bridge de detección, DSI/LVDS/eDP/DPI devuelven siempre `connector_status_connected` (`drm_bridge_connector.c:212-240`, caso DSI en :231). **Un DSI sin fallo nunca muestra `disconnected` por causa eléctrica.**
- El único camino a `disconnected`+`modes` vacío sin tocar hardware es el force: `video=DSI-1:d` → `mode->force = DRM_FORCE_OFF` (`drm_modes.c:2007-2011`, caso `'d'`) → `DRM_INFO("forcing %s connector %s")` (`drm_connector.c:173-175`, el log medido) → `connector->force` (`drm_connector.c:175`) → probe pone `disconnected` sin llamar a detect (`drm_probe_helper.c:589-596`) → `goto exit` **antes** de `drm_helper_probe_get_modes` (`drm_probe_helper.c:641-649`). **Esto reproduce al 100 % lo medido.**
- Con el force quitado, los modos salen del panel sin usar el link: `o82_get_modes` duplica modos estáticos (`o82:411-443`), 1 modo 3200×2136@120 (`o82_modes:508-520`, `num_modes = 1` en :578; 144/90 Hz existen en tabla pero apagados a propósito, :572-577). Validez del modo: techo de OPP por byte-clock + chequeo DSC (`dsi_manager.c:405-435`).
- Bloqueos reales de link/modeset (solo observables SIN `:d`, en orden): supplies del panel (`vddil8b`/`vsp`/`vsn`, `o82:78-82`, `o82:279-293`); `vdda` del ctrl (sm8650: solo `vdda` 16.6 mA, `dsi_cfg.c:193-200`) habilitado en `msm_dsi_host_power_on` (`dsi_host.c:2499-2507` + `pm_runtime_get_sync` :2507); `vdds`+relojes de PHY (§3a); `prepare_prev_first` (panel prepara antes que el host, `o82:653`, ya documentado en V4). Reguladores del `OVL`: `vdda-supply = <&L4B>` en ambos DSI, `vdds = <&L2B>` en ambas PHY, `L8B`+`vsp`+`vsn` al panel (OVL:314-389/405-509).

## 5. Prioridad: ¿el segundo DSI o el primero?

**Ninguno de los dos es el problema-probe.** El log citado dice que `ae94000` probeó y el DPU bindeó ambos; el §2 demuestra que el backlight existente implica par DSI+PHY completo y funcional a nivel de probe/attach. La pregunta "¿ae94000 está OK para link?" **no es respondible con `status`/`modes` mientras `:d` esté puesto** (§4) — hay que quitar el force y medir (tabla §8). Si tras quitar `:d` el conector pasa a `connected` + 1 modo, ambos DSI/PHY/attach están OK y el problema restante es solo de modeset (relojes, panel power, DSC/DPU: territorio V4 §1). Si tras quitar `:d` sigue sin conector/modos, el problema es de cadena DT/driver — y ahí sí mirar el **DT vivo**, no el `BASE`.

Aviso de capa: `UKE-DTS:517-538` deja TODO el display como **TODO sin implementar** (nodos display comentados, "enchufar aquí = copiar ese árbol"). Si el kernel medido se compiló solo con `UKE-DTS`, la pila de display viva **no sale de k18** sino de un dtbo serie-s (linaje `s193/s208/s210/s211-display`, `fase4-display.dtbo`) o del DT vendor. Verificar qué dtbo está en slot antes de atribuir culpas al `BASE`.

## 6. Writeback sin panel: sí existe, pero NO es seguro todavía

- Existe: `dpu_writeback_init` (`dpu_writeback.c:123`), llamado por `dpu_kms` (`dpu_kms.c:742`) ⇒ el `card0-Writeback-1` medido puede recibir un commit atómico con `FB_ID` y ejercitar DPU+DMA+scanout a memoria sin panel, sin PHY y sin DSI (V4 §3b ya lo propone como discriminador DPU-vs-panel).
- **Pero NO esquiva al asesino conocido**: #P43 (V4 §0) muestra que el wedge ocurre en el `open()`/listado (`modetest -M msm -c` cuelga→panic), **igual sin fw de GPU** — el killer vive en el camino de apertura DRM, que el test de writeback también recorre. Orden obligado: primero P2-ctrl/`S4-pollOK` (apertura segura), y solo después el commit a Writeback. Hacer el WB antes es quemar un ciclo y arriesgar otro pánico con `hung_task_panic=1` (ver V4 §4: quitarlo del repack).

## 7. No verificable con lo disponible (explícito)

1. A qué rama (A/B de §1) pertenece el `not ready` medido: el dmesg citado no trae las líneas vecinas ni repetición. Decisorio en vivo: §1.
2. Qué kernel/DT arrancó la medida: la cmdline trae `msm_drm.dsi_display0=qcom,mdss_dsi_o82_…`, parámetro que **no existe en k18** (grep en `drivers/` vacío; no hay `dsi_display.c`/`dsi_panel.c` en `msm/dsi/` — solo `dsi.c/dsi_cfg*.c/dsi_host.c/dsi_manager.c/phy/`). Si el kernel vivo lo consume, es base downstream y las citas de este informe son analógicas. Verificar con `uname -a` + `/sys/module/msm_drm/parameters/` (ausente en mainline) + dtbo en slot.
3. `X9WAVE-poked ae94000.dsi`: sin ocurrencias en `msm/` de k18 (grep vacío) — instrumentación de otro árbol o apodo del log; no afecta a las conclusiones.
4. Timings eléctricos del link (tasa por lane, calibración 4 nm, `dsi_phy_enable` runtime): código presente pero resultado solo medible con migas V4 §1 + `dsi_mgr_phy_enable` (`dsi_manager.c:124-131`).
5. `catalog->dsc_count` del DPU SM7675 (sospechoso V4 §6.2): pendiente del grep/catálogo, no bloquea este informe.

## 8. Cambios candidatos (de menos a más invasivo)

| # | Cambio (uno por ciclo) | Predicción medible | Cómo distingue |
|---|---|---|---|
| C0 | **0 flashes.** Con `:d` aún puesto: `cat /sys/firmware/devicetree/base/soc/phy@ae97000/status` (DT vivo, no BASE); `ls /sys/bus/platform/devices \| grep ae97` + su enlace `driver`; `cat /sys/kernel/debug/devices_deferred`; `dmesg \| grep -c "phy driver is not ready"` (1 = transitorio resuelto; N>1 sin bound posterior = bloqueo) | Si el vivo dice `okay` + driver presente + 1 sola línea de error: la PHY **ya está bien** y C1/C2 sobran. Si `disabled`/ausente: ir a C1. Si deferred persistente: ir a C3 |
| C1 | Habilitar `phy@ae97000` **en la capa que realmente arranca** (overlay serie-s / `fase4-display.dts:490-509`, NO el `BASE`): `status="okay"` + `vdds-supply` + `iface`/`ref` | Desaparece la rama A (§1); si el error persiste idéntico, era rama B (driver) y el `okay` no era el problema |
| C2 | Quitar `video=DSI-1:d` de la cmdline (repack solo-cmdline, sin tocar DT; sin `hung_task_panic`, V4 §4) | **Conector `connected` + `modes` = `3200x2136` aunque el link esté muerto** (§4: detect hardwired + modos estáticos sin HW). Si sale así: cadena DT/driver/panel OK, el fallo restante es de modeset (V4 §1). Si sigue sin conector: cadena rota (volver a C0/C1) |
| C3 | Si el defer persiste tras C1: revisar `vdds` (L2 0.88–0.95 V) e `iface`/`ref` de `phy@ae97000` en el DT vivo + `CONFIG_DRM_MSM_DSI_7NM_PHY` del `.config` del kernel que arranca | `devices_deferred` nombra al culpable (reloj/rail concreto); el error pasa de rama B a bound |
| C4 | Commit de prueba a `Writeback-1` (**solo tras apertura segura P2-ctrl**) | WB completa ⇒ DPU+DMA vivos, asesino en lado panel/DSI. WB wedgea ⇒ asesino DPU/DMA, panel excluido (V4 §3b) |
| C5 | **NO hacer**: parche single-DSI (el panel lo prohíbe por diseño, §3c) ni tocar el `BASE` esperando efecto en un boot por overlay | — (fila negativa: evita quemar ciclos refutados) |
