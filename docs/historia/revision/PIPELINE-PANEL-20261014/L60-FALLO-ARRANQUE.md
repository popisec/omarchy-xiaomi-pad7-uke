# L60 no arranca: causa y fix — 14-oct-2026 (~23:3x)

## 0. Veredicto

**Sospechoso nº1: `BATTERY_QCOM_BATTMGR=y`.** El diff L59→L60 son exactamente
3 líneas (`diff` verificado) y el precedente medido del proyecto hermano
(ledger #404, `REFUTADO.md` R-32/R-33, `LECCIONES.md` ronda 30) dice que
`BATTERY_QCOM_BATTMGR` (y `QRTR_SMD`) **built-in wedgean el arranque con
consola muda y sin panic**, mientras `pmic_glink` solo/exonerado carga bien.
Nuestro `QRTR_SMD` ya era `=y` en L59 (arrancaba) ⇒ el delta apunta a battmgr.
`QCOM_PMIC_GLINK=y` es co-sospechoso (es lo que activa el probe del stack en
boot); `UCSI_PMIC_GLINK=y` es inerte sin ADSP (registro PDR-gated).

## 1. Hechos verificados hoy (solo lectura, PC)

- `diff k52L59.config k52L60.config` = 3 hunks: `BATTMGR m→y` (3856),
  `UCSI_PMIC_GLINK m→y` (6347), `QCOM_PMIC_GLINK m→y` (7294). Sin cascada Kconfig.
- Cmdline REAL extraída de `boot-uke-k52L60.img` (622 B, == L59): **NO trae**
  `panic_on_rcu_stall`, `block2mtd`, `mtdoops` ni `initcall_blacklist`;
  trae `hung_task_panic=1 … hung_task_panic=0` (**gana el último = 0**,
  semántica estándar `__setup`: solo warnings) y `printk.always_kmsg_dump=0`.
- Los 3 probes **no bloquean** (código): `pmic_glink_probe`
  (`pmic_glink.c:305-~395`, sin waits; `pmic_glink_send` :121-150 devuelve
  `-ECONNRESET` sin endpoint); `qcom_battmgr_probe` (`qcom_battmgr.c:1710-1815`,
  solo registros + `wait_for_completion_timeout(HZ)` en worker diferido);
  `pmic_glink_ucsi_probe` (`ucsi_glink.c:380-460`, gpio opcional + timeouts
  `5*HZ`). **El mecanismo "probe colgado ⇒ RCU-stall ⇒ panic" NO encaja**
  (y el stall tampoco panicaba: flag ausente).
- Guard anti-doble-nodo **compilado en L60** (string `ya registrado` en
  `k52L60-build/drivers/soc/qcom/pmic_glink.o`; fuente `pmic_glink.c:305-317`).
- **Nuevo: el dtbo vivo s287 trae DOS nodos** `compatible="qcom,pmic-glink"`
  (`/soc/qcom,pmic_glink` y `/soc/qcom,pmic_glink_log`; verificado con
  `fdtoverlay` base `s21/dtbo-gpu/base-dtb.img` + payload s287). El rename
  s196/s229 (`_log`→`-log`) **no está en la rama s28x**. Con el guard, el
  2º probe devuelve `-EBUSY` sin colisión de aux — cubierto, pero higiene pdte.
- ADSP en boot: `QCOM_Q6V5_PAS=y`/`ADSP=y`, pero el initramfs embebido
  (48 entradas) trae **solo firmware GPU**, 0 `.ko`, 0 `adsp.mdt` ⇒ el ADSP
  no sube en boot y el glink queda inerte (esperado; no cuelga por los
  timeouts). FW existe en `build/rootfs/staging/.../adsp.bNN` y
  `~/gpu-work/ramaa/s24/adsp-fw/`.

## 2. Corrección al ledger #639: "leer el oops en pstore/mtdoops" NO aplica

L60 no tenía backend de oops (cmdline sin `block2mtd/mtdoops`,
`always_kmsg_dump=0`; `docs/historia/revision/PIPELINE-PANEL-20261014/L49-PREP.md:88-92` ya midió pstore vacío sin `/proc/mtd`;
`ramoops` eliminado del DT por solape con `adspslpi`, `xiaomi-uke.dts:74`).
**No hay panic guardado que leer.** La captura válida sigue siendo doble:
lector ACM único + `ssh … 'dmesg -w'`, con `dmesg -n 7` antes de juzgar.

## 3. Fix recomendado (un cambio por ciclo)

1. **Ahora: quedarse en L58/L59** (pila `=m` ausente = inerte; la carga la lleva
   el PMIC en standalone). Rollback L58 `763d7869…` ya en curso (#639).
2. **Próximo kernel: `QCOM_PMIC_GLINK=y` + `UCSI_PMIC_GLINK=y` SIN battmgr**
   (R-32 exonera a pmic_glink solo; aisla al sospechoso). Si arranca ⇒
   culpable confirmado = battmgr; si wedgea ⇒ es pmic_glink+doble-nodo.
3. **Higiene DT**: portar el rename `_log`→`-log` a la rama s28x (s288).
4. **Carga con visibilidad** (vía probada 28-sep, `NOTAS-OMARCHY.md:1023-1036):
   `.ko` en rootfs + `insmod` topológico
   (`qcom_glink_smem→…→qcom_q6v5_pas→qrtr-smd→pmic_glink→qcom_pd_mapper`) +
   fw ADSP en `/lib/firmware` + servicio (ya existe `charge/uke-adsp-load.sh`).
   ADSP sube en ~0,5 s y aparecen 3 `power_supply`.
5. Si se quiere oops persistente algún día: reservar backend (ramoops sin
   solape o `oops` MTD real) — hoy no existe; no prometer lecturas pstore.

## 4. Comandos vivos (cuando haya tablet en L58)

```
ls /sys/class/power_supply/; dmesg | grep -iE 'glink|battmgr|ucsi|adsp|remoteproc|pdr'
ls /sys/fs/pstore/ 2>/dev/null; ls /proc/mtd 2>/dev/null || echo SIN-MTD
fdtget merged s287 /soc/qcom,pmic_glink_log compatible  # tras portar fix: debe dar -log
```

## ADDENDUM-CORRECCIÓN (crítica de hipótesis, 14-oct ~23:2x)

- **La cita «R-32/R-33» es ERRÓNEA**: `~/proyectos/ubuntu-permanente/REFUTADO.md:94-98` las declara
  FALSADAS. La evidencia real es el **ledger #404 (K1/K2)**: QRTR_SMD **y/o** BATTMGR `=y` (otro
  árbol) implicaba a **la pareja**, no solo a battmgr.
- **Confounds vivos del wedge L60**: (a) el guard anti-doble-nodo `pmic-glink` **sin boot-test**;
  (b) el 2º nodo `qcom,pmic-glink` del dtbo s287 ejecutándose por 1ª vez en L60.
- **Verificación propuesta (0 escrituras)**: `fastboot boot` del L60 + captura ACM para ver dónde
  wedgea (y de paso probar el techo del fastboot boot con 96 MB).

## CORRECCIÓN (crítica ronda 2, 15-oct)

- **CAE «ventana check-then-act del guard»**: check y asignación van bajo el MISMO mutex
  (`pmic_glink.c:312-317` / `369-371`).
- **CAE «wedge = triple nodo»**: los duplicados dan `-EBUSY` benigno; la causa real del wedge
  (`glink+ucsi=y`) es DESCONOCIDA. (Mismo para el addendum previo: revisar.)
- **CAE «DCS en HS»** (era el nº1 del ranking): falso — `mode_flags` lleva LPM (`panel:738`) y
  `device_transfer` auto-ORs `USE_LPM` (`drm_mipi_dsi.c:448-458`).
- **CAE «cold-path vendor funciona»**: nunca observado en vivo (el ABL siempre deja splash).
- Nuevo candidato fuerte: **byte clock propio jamás medido en vivo (118.9M vs 148.6M)**; firma
  exacta del negro-con-commit-OK ⇒ test 0-flash (`clk_summary`) en el L64 arrancado.
