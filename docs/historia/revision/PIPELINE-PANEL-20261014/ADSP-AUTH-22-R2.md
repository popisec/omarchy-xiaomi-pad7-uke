# ADSP-AUTH-22-R2 — causa: `adsp.b40` corrupto en `/lib/firmware` (icc refutado)

Fecha: 2026-10-15. Base: `ADSP-AUTH-22.md` + `L66-ADSP-ICC.md`. Todo MEDIDO hoy
(SSH solo-lectura a `192.168.42.129` + diff local). Cero escrituras en la tablet.

## 1. El icc queda REFUTADO (MEDIDO en L66 vivo)

DT vivo: `interconnects = 0x188/3/0x188/512` (mc_virt MASTER_LLCC→SLAVE_EBI1, el
fix s288 aplicado) + `cx-supply` vacía + `qcom,qmp = 0x23`. El probe adquiere los
paths (`remoteproc1: adsp is available`, `Booting fw image adsp.mdt, size 8044`)
y el auth del dtb (`pas_id 0x24`) PASA. El auth del main (`pas_id 1`) falla igual:
`failed to authenticate image and release reset` → `-22` a los ~320 ms de carga.
Con votos DDR activos y el mismo resultado, los votos NO eran la causa.

## 2. Hallazgo (MEDIDO): un segmento difiere byte a byte del ground truth

`sha256sum` de los 56 ficheros `adsp*` vivos vs `~/gpu-work/ramaa/s24/adsp-fw/`
(staging verificado contra el dump FAT16 de `modem_a`, `MANIFEST.txt`, "0
diferencias", el fw que Android arrancó): **55/56 idénticos, 1 distinto**:

| fichero | tablet `/lib/firmware` | staging + MANIFEST | tamaño |
|---|---|---|---|
| `adsp.b40` | `a2057b8c…837b73a34` | `42c86837…8bf5882b352` | 2368 B ambos |

Releído 2× (estable en disco, no flake). `adsp.mdt` (`fd874a8d…`) y
`adsp_dtb.*` (`909cf117…`) intactos en ambos lados — por eso el auth `0x24` pasa.

## 3. Por qué encaja con el código (fichero:línea)

`qcom_pas_start()` (`qcom_q6v5_pas.c:280-334`): `qcom_mdt_pas_load()` hace `memcpy`
de los segmentos a la carveout **sin verificar**; el que verifica es el TZ en
`AUTH_AND_RESET(1)` vía `qcom_scm_pas_auth_and_reset()` (`qcom_scm.c:955-984`,
`return ret ? : res.result[0]`). Un segmento corrupto (mismo tamaño, distinto
contenido) ⇒ carga OK + hash PIL del TZ FAIL ⇒ `-EINVAL`. `qcom_scm.c` y
`mdt_loader.c` son **byte-idénticos** entre `~/gpu-work/palawan-linux` y nuestro
`k52-L16-tree`; `qcom_q6v5_pas.c` difiere SOLO en L18 (moot: con `cx-supply`
vacía ambos dan `-ENODEV`→ausente); `qcom_q6v5.c` SOLO en el marker `UKE-L66`.
Mismo TZ (nunca reflasheado), mismo driver, mismo DT ⇒ solo los bytes explican
que al hermano le pase y a nosotros no. Precedente: ledger #404 tuvo su propio
bug de copia (`adsp.b10` ausente → `-2`).

## 4. Exonerados con evidencia

- DT: vivo = diseñado (§1). `mx-supply = 0x186` intacta (el driver nunca la pide).
- `pas_id`/`dtb_pas_id` (`1`/`0x24`): idénticos en ambos árboles; el `0x24` pasa
  por el mismo SMC ⇒ transporte SCM/TZ sano.
- `use_tzmem=false` en ambos (sin `iommus`); `qcom,signal-aop` presente; WPSS no
  requerido (el hermano arrancó el ADSP solo, ledger #404).
- `regulator_summary` vivo: sin fila ADSP-CX (solo `kgsl-3d0-vddcx`) ⇒ coherente
  con `cx-supply` vacía; el fragmento s288 debe CONSERVARLA vacía (punto 3 del
  encargo: la base `0x185` sin driver daría defer eterno; vacía es lo correcto).
- K5 `=m` vs nuestro `=y`: secundario — el código ejecutado es el mismo.

## 5. Origen + siguiente test (0 flash, 0 escrituras de slot)

Origen: nuestro staging `charge/firmware/adsp.b40` = `42c86837…` CORRECTO ⇒ la
corrupción entró en el **despliegue del 25-sep** (`-rw-… Sep 25 20:47`, 1 de 56).
El guard de `uke-adsp-load.sh:62` (`n >= 49`) no detecta corrupción a igual tamaño.
Test: copiar el bueno (`charge/firmware/adsp.b40`) a `/lib/firmware`, `echo stop`,
`echo start > …/remoteproc1/state`, `dmesg -n 7` + doble captura (regla #4).
**PASA** = `adsp is now up` + `PDR … charger_pd`. **FALLA** (mismo `-22`) = refuta
esta R2 ⇒ sospechar estado TZ/carveout y reabrir. Tras el PASA: endurecer el
guion con check `sha256sum -c` contra el MANIFEST.
