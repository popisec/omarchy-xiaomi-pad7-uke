# Carga: cadena del hermano vs la nuestra — 14-oct-2026 (solo lectura)

## (a) Diferencias exactas

| Eje | Hermano (`ubuntu-permanente`, Ubuntu, ledger #398–#406) | Nosotros (L59/L60/L63) |
|---|---|---|
| Símbolos | K5 final: `Q6V5_PAS/RPROC_COMMON/Q6V5_COMMON/PIL_INFO/GLINK_SMEM/**PMIC_GLINK/UCSI/QRTR_SMD/BATTMGR**`=m`, `SYSMON=y` (#404:3920-3922). `=y` (QRTR y/o BATTMGR) wedgea (#404:3914-3918) | L59: `QRTR_SMD=y`(:1604), `PAS/GLINK_SMEM/SYSMON/PIL_INFO/PD_MAPPER=y`, glink+ucsi+battmgr=`m` → **arranca**. L60: 3→`y` → wedge. L63: glink+ucsi=`y`, battmgr=`m` → wedge otra vez |
| DT/nodos | dtbo s196 `fragment@1300`: compatible `_log`→`qcom,pmic-glink-log` (#398:3691-3696; REVISION-CARGA-DTBO-FW.md:15-17). s207 suma `qcom,gpr disabled` (#406:4033-4037) | s287 **sin rename**: base vendor trae DOS `qcom,pmic-glink` (`pmic_glink`@0x352d8, `pmic_glink_log`@0x354d4, medido en `ramaa/s21/dtbo-gpu/base-dtb.img`); s287 no añade ninguno (0 strings); `xiaomi-uke.dts:89-92` suma UN TERCER nodo propio |
| Drivers | Guard anti-doble-nodo + battmgr parcheado dialecto 0x50 (`ramaa/s24/qcom_battmgr.ko`, BATTMGR-DIALECTO.md:1-21) + **pd_mapper parcheado** con `qcom,cliffs[-mtp]` (#406:4002-4007) | Mismo guard en `pmic_glink.c:305-317`, **sin boot-test**; battmgr **sin parche** 0x50; pd_mapper **ya trae** `cliffs` (`qcom_pd_mapper.c:605-606`) → locator OK de serie |
| Firmware | 49 segmentos en `ramaa/s24/adsp-fw/` (#398:3714-3718; `*.b??`, no `*.b0*` — #402:3836-3838) | Mismo FW compartido: `~/gpu-work/ramaa/s24/adsp-fw/` + copia en `build/rootfs/staging/.../firmware/adsp.mdt`; initramfs de boot solo trae FW de GPU (L60:36-40) |
| Orden/script | `bin/uke-adsp-load.sh`: `qcom_q6v5_pas` → `qcom_glink_smem` → `echo start` (ADSP running) → `qrtr_smd` → `qcom_pd_mapper` → `pmic_glink` → `qcom_battmgr` (#406:4051-4055); servicio `uke-adsp.service` | `charge/uke-adsp-load.sh` existe pero nunca ejecutado en vivo; `.ko` disponibles (`k52L62-build/.../pmic_glink.ko`, `qcom_battmgr.ko`, `staging/.../uke/mods/`) |
| Cmdline | Sin `initcall_blacklist=pmic_glink_init` desde s196 (#398:3726-3728) | L60 real medida: **sin** `panic_on_rcu_stall/blacklist/block2mtd`, `always_kmsg_dump=0` → sin backend de oops (L60:18-21,44-48) |
| Base | `7.2.0-rc2-palawan+`, config K5 | `7.2-rc2-palawan` (`LOCALVERSION=-palawan`), mismo árbol de época |

## (b) ¿El mismo wedge o dos distintos? DOS DISTINTOS con la misma firma

- Hermano: bisecta K1/K2 (#404:3914-3918) implica a la **pareja QRTR_SMD y/o BATTMGR** `=y`, por camino de **init (no probe**: con ADSP y los 4 remoteproc deshabilitados seguía colgando, D4/D6). Nunca aisló cuál de los dos.
- Nuestro: `QRTR_SMD=y` **exonerado** (L59 arranca con él); L63 wedgea con **glink+ucsi=`y`, battmgr=`m`** → el trigger mínimo está en **glink y/o ucsi**, que el hermano nunca probó solos (R-32 solo exonera `pmic_glink` **como módulo**, REFUTADO.md:94-95).
- Firma común (wedge mudo temprano, pstore vacío, sin consola) ≠ misma causa. Confound propio extra: el doble nodo + guard sin test (§c).

## (c) Doble nodo + guard: SÍ es candidato, y el guard NO BASTA

- Con `=y`, los dos nodos vendor probean. El guard comprueba `__pmic_glink` a la **entrada** (`pmic_glink.c:312-317`) pero lo asigna al **final** (`:369-371`), DESPUÉS de crear los 3 aux (`:343-355`). Ventana check-then-act: dos probes (async/concurrentes) pasan el check y colisionan en el aux `ucsi` igual que el panic #344 (0,3 s) que motivó el guard.
- Además: `return -EBUSY` deja al 2º device sin driver pero no lo desregistra; y nuestro tercer nodo (`xiaomi-uke.dts:89-92`) ni siquiera está contemplado. Secuencial funcionaría; en paralelo, no. Nunca boot-testeado (solo `strings`, L60:29-30).

## (d) Vía más corta y segura (slot a=3: cada flash cuesta 1 retry, H5/H6)

**Recomendada: (ii) módulos + insmod, 0 flashes.** `QRTR/PD_MAPPER(y)` ya activos; por SSH: `insmod pmic_glink.ko` → `dmesg -n 7` + `dmesg -w` (doble captura obligatoria) → si vive, `insmod qcom_battmgr.ko` (+ el parche 0x50 si hay ruido) → `echo start` al ADSP con FW en `/lib/firmware` → verificar `qcom-battmgr-{bat,usb,wls}` y PDR `charger_pd`. Riesgo: el doble nodo puede dar oops/panic **en runtime** (recuperable con reboot, −1 retry), NO wedge mudo: la consola está viva y el orden es reversible (`rmmod`). Si el insmod colisiona → entonces sí (i): portar el rename `_log`→`-log` a s288 + re-probar insmod antes de ningún `=y`.
- (i) sin (ii) exige flashear dtbo+boot a ciegas (`fastboot boot` NO sirve para probar DT: usa el dtbo del slot, R-12) y gasta 2 ciclos con a=3.
- (iii) Endurecer el guard (asignar `__pmic_glink` ANTES de crear aux, o sufijar aux por nodo) es complemento, no alternativa: 1 rebuild + mismo coste de test que (i).
- Verificaciones: `ls /sys/class/power_supply`, `PDR: ... charger_pd ... 0x1fffffff` (= mensaje de Android, #406:4021), `status=Charging + current_now>0`; abortar si `alive()` falla tras cualquier `modprobe` (patrón `uke-adsp-load.sh`).
