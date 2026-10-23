# AUDITORÍA DEL STACK DE CARGA — 2026-10-16 (tablet en fastboot, batería en franja agotada)

Pregunta del dueño: **«¿la carga está?»** — auditoría de solo lectura del stack de carga
(`charge/`, ledger, NOTAS, ESTADO-VIVO) + lecturas `fastboot getvar battery-voltage`.

---

## VEREDICTO

**SÍ, CON CONDICIÓN.** El stack de carga está completo, verificado en el PC (módulos, firmware 56/56,
servicio, loader endurecido) y **probado en vivo en el MISMO rootfs que lleva la tablet** (incluido el
boot L71 `5e13addf…` que está ahora en `boot_a`: `Charging 1,098 A`), pero **la tablet NO puede
recuperarse desde fastboot con el USB del PC** (medido: no carga, descarga ~7 mV/min): la condición es
**cargador de pared ≥45 W, apagada, con `off-mode-charge=1` (ya puesto), HORAS, hasta ≥3700 mV**, y en
el primer contacto SSH ejecutar el ritual anti-corrupción (adsp.b40 se corrompió 2 veces en el rootfs).

---

## 1. Checklist del stack (pieza / estado / evidencia)

| Pieza | Estado | Evidencia |
|---|---|---|
| Módulos K5, variante **sin `+`** (`charge/mods-7.2.0-rc2-palawan/`, 10 .ko) | **VERIFICADO** | vermagic incrustado medido hoy con `strings`: `vermagic=7.2.0-rc2-palawan SMP preempt mod_unload aarch64`; shas spot-check 3/3 == INFORME §6 (`4bcad826…`, `18a5b236…`) |
| Módulos K5, variante **con `+`** (`charge/mods-7.2.0-rc2-palawan+/`, 10 .ko) | **VERIFICADO** | `strings`: `vermagic=7.2.0-rc2-palawan+ SMP preempt mod_unload aarch64`; sha `qcom_battmgr.ko` `8010b074…` == INFORME §6 |
| Nota modinfo | — | `modinfo` (kmod del host, x86) devuelve vermagic **vacío** en silencio sobre .ko aarch64: el gate de `uke-charge-run.sh:43-45` puede dar falso OK. Verificación independiente con `strings` = OK. Recomendación: cambiar el gate a `strings \|$ko \| grep -qx "vermagic=$REL …"` |
| `qcom_glink.ko` ausente en ambas variantes | **OK (esperado)** | loader lo tolera (`uke-adsp-load.sh:38` «AVISO: falta … sigo; quizá built-in»); built-in en kernels L (INFORME §5.1); demostrado en vivo (boots con carga verde) |
| Firmware ADSP staged (`charge/firmware/`, 57 ficheros = 56 adsp + SHA256SUMS) | **VERIFICADO** | `sha256sum -c adsp-fw.sha256` = **56/56 OK, RC 0** (ejecutado hoy en el PC); ídem `firmware/SHA256SUMS` (mismos 56 pares); `adsp.mdt` = `fd874a8d…` == INFORME §6 |
| `charge/uke-adsp.service` | **BIEN FORMADO** | `systemd-analyze verify` en el PC da RC 1 **solo** por «ExecStart no ejecutable» (el path `/usr/local/sbin/uke-adsp-load.sh` es de la tablet, no existe en el PC — esperado; con `--root` de staging dio RC 0 el 13-oct, INFORME §4). Unit: `Type=oneshot`, `RemainAfterExit`, `ConditionPathExists` mods+b41-fw (`uke-adsp.service:5-6`), `WantedBy=multi-user.target` |
| Loader endurecido (`charge/uke-adsp-load.sh`, 15-oct 01:31) | **VERIFICADO EN REPO; DESPLEGADO EN TABLET (por commit)** | sha-check del firmware `uke-adsp-load.sh:68-80` (fallo ⇒ exit 1, sin TZ -22 silencioso); exige `state=running` `:114-136`; veredicto VERDE/AMARILLO/ROJO con exit 0/2/3 `:184-198`; commit **`6d584f1`** «desplegado en tablet» + **`e46e7bf`** (15-oct 01:28); corroborado por ledger #646 (15-oct 02:1x): «rootfs intacto (adsp.b40 bueno + `uke-adsp-load.sh` con shas)» |
| **GAP-1 (hueco real)**: `uke-charge-run.sh:62-65` **NO copia `charge/adsp-fw.sha256` a `/lib/firmware/`** | **HUECO** | el scp del paso 3 lleva solo `adsp.mdt adsp_dtb.mdt adsp.b?? adsp_dtb.b??`. Si se re-despliega con el guion, el loader cae en modo «AVISO: sin adsp-fw.sha256 (no se verifica)» (`uke-adsp-load.sh:79`) = verificación INOPERANTE. Fix: `scp charge/adsp-fw.sha256 root@…:/lib/firmware/` (1 línea) en el próximo contacto |
| dtbo s288 en `dtbo_a` (no se toca en el flash L73) | **VERIFICADO** | `sha256sum` hoy = `02d403c5…` == #643/#651; hereda `gpr disabled` (`repack-s288-report.txt:16`, «paridad s287») ⇒ trampa `qcom,gpr` neutralizada en el DT vivo + red runtime del loader (`uke-adsp-load.sh:96-158`) |
| boot L71 en `boot_a` (el que está en la tablet, sin cambios) | **VERIFICADO** | `build/bootimg/boot-uke-k52L71.img` sha256 **`5e13addfe6c1…`** medido hoy == pre-registro #650 == ESTADO-VIVO 16-oct 00:4x («boot_a = L71 SIN CAMBIOS») |
| Cadena «la carga NO va en el boot.img» | **CONFIRMADA** | gate G3 de `repack-k52L71.py:594-602`: `pmic-glink/qcom,pmic-glink/ucsi_glink/battmgr` **x0** en el binario del kernel L71 («carga AUSENTE») ⇒ los drivers van como módulos del **rootfs** + `uke-adsp.service`. Boot.img L71 solo arranca; cargar depende del rootfs |
| Flash L73 armado (`docs/historia/gates-palawan/flash-l73-gated.sh`) | **VERIFICADO** | shas verificados hoy en disco: boot L73 `a671d293…` == #651, dtbo s288 `02d403c5…`; gate batería: **aborta <3300, avisa <3700** (`flash-l73-gated.sh:21-22`); UNA escritura `boot_a` + `set_active a`; verificación post-arranque de carga + guarda-flood (>1500 S4-DIAG ⇒ DPMS off, `:55-56`) |

---

## 2. Evidencia de carga EN VIVO (tablas)

| Fila/fuente | Fecha | Corriente medida | Tensión | Fuente |
|---|---|---|---|---|
| #406 (en frío, tras flash s205, AMBOS slots) | 25-sep | **+1 191 313 µA (1,19 A), Fast** | 3,761 V | puerto del PC 5,19 V |
| #644 (test 0-flash: adsp.b40 bueno + `echo start`) | 15-oct ~01:5x | **1,04 A, Charging** | 3,244 V (cap 1 %) | no anotada (sesión PC) |
| NOTAS 13-oct ~22:0x (boot L19 + `uke-charge-run.sh`) | 13-oct 22:0x | **3 219 073 µA (3,22 A), Fast** | 3,354 V (cap 1 %) | USB del PC (NCM, SSH) |
| NOTAS 13-oct 22:4x (tras recopiar adsp.b40) | 13-oct 22:4x | ~0,24 A, Charging | 3,708 V | USB del PC (limitado) |
| ESTADO-VIVO 15-oct / NOTAS 15-oct 02:3x (boot L66) | 15-oct | **~1,4 A** carga gestionada | — | **pared ≥45 W** |
| **#650 Resultado (boot L71, el de la tablet HOY)** | 15-oct ~11:3x | **Charging 1,098 A** | — | sesión del día |

Lectura: la carga gestionada por ADSP/battmgr está demostrada en **cinco boots distintos** y en el
mismo rootfs actual; rango medido **0,24–3,22 A** según fuente (pared ≈ **1,0–1,4 A** típico; el USB
del PC entre 0,24 y 3,22 A según puerto).

---

## 3. Riesgo de corrupción + ritual mínimo

**El riesgo es real y recurrente**: `adsp.b40` se corrompió **DOS veces** en el rootfs de la tablet
con la misma firma (misma talla, contenido distinto, mtime viejo = corrupción silenciosa en disco):
1. 13-oct 22:4x — sha `8276dec8…` vs bueno `42c86837…`; 55/56 ficheros OK; ligado a errores EXT4
   (`lost file I/O error`, `deleted inode referenced`); `e2fsck` en frío sigue PENDIENTE.
2. 15-oct ~11:1x — de nuevo corrupto; además el flood DSI llenó el root de 4G al 100 % y tumbó
   `uke-adsp` (ledger #649-resultado, ESTADO-VIVO 16-oct «adsp.b40 recorrupto — 2ª vez»).

**Qué pasa hoy si arranca con adsp.b40 corrupto**: el loader endurecido **detecta** (sha mismatch ⇒
`exit 1`, servicio FAILED) en vez del fallo silencioso viejo (TZ `AUTH_AND_RESET -22`), pero **no
autorepara**: sin SSH no hay forma de recopiarlo ⇒ sin power_supply ⇒ sin carga gestionada. Salvaguarda
estructural: **la carga en off-mode (ABL/LPM) no depende de Linux**, así que enchufada a pared siempre
recupera aunque el rootfs esté podrido.

**Ritual mínimo al abrir CADA sesión (0 flashes, <2 min):**
1. PC: `cd charge && (cd firmware && sha256sum -c ../adsp-fw.sha256 --quiet)` → RC 0 (verificado hoy).
2. Primer SSH: `sha256sum /lib/firmware/adsp.b40` ⇒ debe ser `42c86837570fabc9cf1504…5882b352`
   (o `-c /lib/firmware/adsp-fw.sha256` completo si hay tiempo).
3. `ls -la /lib/firmware/adsp.b40` (mtime viejo = sospecha) + `df -h /` (root ≈100 % = veneno de uke-adsp).
4. `systemctl is-active uke-adsp; systemctl is-failed uke-adsp` + veredicto power_supply.
5. **Si falta `/lib/firmware/adsp-fw.sha256`** (GAP-1): `scp charge/adsp-fw.sha256 root@…:/lib/firmware/`.
6. Si adsp.b40 corrupto: `scp charge/firmware/adsp.b40 root@…:/lib/firmware/` + `sync` +
   `systemctl restart uke-adsp.service` + re-veredicto.

---

## 4. Plan de recuperación desde la franja agotada (~500 mV)

Fuentes: ledger #399/#400/#423, NOTAS 13-oct 21:0x / 21:27 / 22:0x, ESTADO-VIVO 16-oct 00:4x.

1. **Enchufar cargador de pared ≥45 W.** El USB del PC **NO carga en fastboot** (medido #399:
   3473→3452 mV en 3 min; #400: puertos PC 100 mA/0,5 W). La tablet puede quedarse en fastboot o
   apagarse (Power ~15 s; `oem poweroff` responde OKAY pero no apaga, #399).
2. **`off-mode-charge=1` ya está puesto y persiste** (26-sep, #399): enchufada apagada, el ABL se queda
   en **LPM cargando sin arrancar Linux**. No se espera auto-arranque (ese era el comportamiento con `=0`,
   revertido el 18-sep).
3. **Esperar HORAS** (mejor toda la noche). Precedente favorable: 13-oct la tablet subió de ~376 mV
   (21:1x) a 3386 mV estables (21:27) en ~20-25 min con pared — pero el plan conservador desde ~500 mV
   es horas (así lo documentan NOTAS 13-oct 21:0x y ESTADO-VIVO 16-oct).
4. **Vigilancia pasiva**: si arrancara sola (no debería con `=1`), no pasa nada grave: vuelve a fastboot
   con Power+Vol− o deja que L71 cargue (ver §5, con reservas).
5. **Al volver al PC**: `timeout 15 fastboot getvar battery-voltage` (2-3 lecturas). Umbrales medidos:
   **no arrancar <3150 mV** (corte documentado, NOTAS 13-oct 20:2x); boots a 3,42-3,48 V mueren en
   segundos (#400); el guard del ABL puede negarse por debajo de **~3400** (NOTAS 13-oct 21:27).
   Objetivo: **≥3700 mV estable** (gate del proyecto; también exige `battery-soc-ok:yes`).
6. **Flash único L73**: `bash docs/historia/gates-palawan/flash-l73-gated.sh` — verifica shas de boot L73 y s288, mide
   batería (aborta <3300, avisa <3700), **1 escritura** `boot_a` + `set_active a` + reboot, espera ~75 s,
   entra por SSH, captura kmsg, gates L73, **verifica la carga** (remoteproc/PDR `charger_pd`/
   `power_supply`) y aplica guarda-flood (DPMS off si >1500 líneas S4-DIAG). Rollback: L71 `5e13addf…`.
7. **Qué NO hacer**: ningún `fastboot flash/boot/reboot/oem` con `battery-soc-ok:no` o <3300; no
   arrancar <3150-3400; no usar el USB del PC como fuente de carga; no encadenar más flashes aunque el
   primero fuera bien (orden del dueño: UN flash).

### Vía alternativa evaluada (arrancar L71 a ~3400-3470 y dejar que la carga gestionada termine)

**Viable pero NO recomendada como plan A.** A favor: está probada (13-oct, boot L19 con 3470 mV → SSH →
3,22 A; el ABL arranca a ~3470 y la carga gestionada sostiene). En contra, medida: **L71 lleva el toggle
L68** ⇒ flood DSI (143k líneas/20 s) que el 15-oct 11:1x **llenó el root al 100 % y tumbó uke-adsp**
(= se quedó sin carga estando booteada, justo el modo de fallo que hay que evitar); el boot L71 del
escritorio arranca sddm ⇒ commit ⇒ riesgo de flood en un boot «normal». Si se usara igual: solo con
pared puesta, vigilando `df -h /` y el servicio por SSH, y con `≥3400` (bajo ese valor el guard puede
rechazar el arranque).

---

## 5. Lecturas `battery-voltage` tomadas (solo comando fastboot permitido)

| # | Timestamp (PC) | Comando | Resultado |
|---|---|---|---|
| 1 | 2026-10-16 12:15:49 +0200 | `timeout 15 fastboot getvar battery-voltage` | **`< waiting for any device >`** (timeout 124) |
| 2 | 2026-10-16 12:25:02 +0200 | ídem | **`< waiting for any device >`**; `lsusb` sin `18d1:d00d`/Xiaomi |
| 3 | 2026-10-16 12:26:57 +0200 | ídem | **`< waiting for any device >`** |

**Conclusión de las lecturas**: la tablet **no está visible por USB ahora mismo** (12:15-12:27):
o está desconectada del PC, o no enumera en fastboot. **No se puede confirmar desde aquí si está
cargando.** Última evidencia fiable: 16-oct 00:2x, 4 lecturas **475-557 mV, `battery-soc-ok:no`**
(ESTADO-VIVO), tras el desplome desde 3681 mV (15-oct 20:23, ~9 h en fastboot sin carga). Sin cargador
de pared puesto, seguirá descendiendo; con pared (`off-mode-charge=1`) recupera aunque siga en fastboot
(no, en fastboot no carga: hay que dejarla APAGADA/en LPM).

---

## Resumen de verificación ejecutada hoy (PC)

- `sha256sum -c adsp-fw.sha256` y `firmware/SHA256SUMS`: **56/56 OK** (RC 0 ambos).
- vermagic de los 20 .ko (2 variantes × 10) leído con `strings`: exacto en ambos releases.
- Spot-check shas de .ko contra INFORME §6: 3/3 coinciden.
- `boot-uke-k52L71.img` = `5e13addf…`, `boot-uke-k52L73.img` = `a671d293…`, s288 = `02d403c5…`: los
  tres == pre-registros del ledger.
- `systemd-analyze verify uke-adsp.service`: solo falla por path de tablet ausente en PC (esperado).
- Commits `e46e7bf`/`6d584f1` (15-oct 01:28/01:31): endurecido + «desplegado en tablet»; corroborado
  por ledger #646. Hueco residual: GAP-1 (`uke-charge-run.sh` no copia `adsp-fw.sha256`).
