# PORT WiFi WCN6750/ath11k ← senemos rev 1.39 (15-oct-2026)

Fuentes (medido 15-oct-2026): `github.com/MCC45TR/senemos-uke-kernel-mainline@fe53eb0`
(README: "7.2.9 rev 1.39 … reaches … Wi-Fi SSH"; HW table en `MCC45TR/uke-linux`).
Donantes: `linuxgamer/uke-fedora` (WiFi "Not working" — solo confirma rails s3b/s2b/s1b/s3e
y fw desde NON-HLOS), `codeberg.org/palawan-mainline/linux` (base ya nuestra),
`MCC45TR/uke-linux-hardware-support/xiaomi-uke-firmware` (manifiesto OEM WiFi
`oem-wifi-source.json`: wpss.b00 sha `2f0b37ad…` = idéntico al nuestro → misma fuente).

## 1. Qué hace senemos (todo en `patches/7.2.10/`)

| Pieza | Contenido | Procedencia |
|---|---|---|
| `0015` ahb.c/ahb.h | 3 supplies en el nodo wifi (`vdd-cx-mx/-1.8-xo/-1.3-rfa`), exigidos los 3, enable antes de `rproc_boot`, unwind al fallar | senemos, rev 1.39 |
| `0016` ahb.c/ahb.h | Orden OEM ICNSS (CX/MX→XO→RFA), apagado inverso, conserva prefijo ante fallo (no re-vota) | senemos, rev 1.39 |
| `0014` qcom_q6v5_pas.c | WPSS `cliffs-wpss-pas`: fw `qca6750/wpss.mdt`, PAS 6, `auto_boot=false`, votos proxy CX/MX a nivel TURBO + QMP/AOP obligatorio | senemos, rev 1.39 |
| `uke-abl.c:381` + `sm7675-uke-ufs.dtso:120` | wifi `xiaomi,uke-wcn6750-wifi`+`qcom,wcn6750-wifi`; rails→`smpb3/smpb1/smpb2` @984000/1856000/1256000 uV; SMMU SID `0x1400` mask 1; MSA `a6400000/0xc00000` no-map | senemos (ABL admission) |
| `0002` (rpmh-uke) | Solo su driver propio: admite smpb1/smpb3… | NO portable (fichero suyo) |
| `0015` hunk SMMU | Solo su `boot-smmu` propio: admite SID 0x1400 | NO portable (driver suyo) |
| `0003` tlmm / `0017` | `HOST2WLAN_SOL` gpio132 (solo def. de función) | NO portable (sin consumidor wifi) |
| Firmware | Ellos NO empaquetan: Fedora `linux-firmware` (ath11k `board-2.bin`) + OEM modem (`qca6750/*`, sin redistribuir) | — |

## 2. Tenemos / falta (nuestro lado)

| Ítem | Estado |
|---|---|
| `ATH11K/AHB/PCI=m`, `PWRSEQ_QCOM_WCN=m`, `QCOM_PAS=y`, `RPMH=y`, `GENI_SE=y` (k52L69.config) | TENEMOS |
| Pokes L18 (cx defer→sigue) / L19 (ICC NULL) / L21 (bt-gpio156) | TENEMOS (built-in) |
| `cliffs-wpss-pas` en of_match (línea 1632) | TENEMOS (recurso sc7280-like, fw `wpss.mdt`) |
| wifi `iommus 0x1400/1`, MSA `a6400000`, 32 IRQ 768-799 (palawan.dtsi) | TENEMOS (= OEM) |
| Rails s3b 968-1040 / s1b 1856-2040 / s2b 1256-1408 mV (xiaomi-uke.dts:165-183) | TENEMOS (contienen 984/1856/1256 uV OEM) |
| Payload `uke-wifi-payload.tar.gz` 16/16 vs `firmware-wlan.sha256` | TENEMOS (amss/board/regdb vendor + wpss.mdt+bXX) |
| Rails directos en driver / orden OEM / votos proxy TURBO | FALTA → parches 0002/0003 |
| `mx-supply` del wpss en DT (base vendor + frag 1707 solo dan cx) | FALTA → gate del 0003 |

## 3. Parches (aplican limpio: `patch -p1 --dry-run` OK 15-oct sobre k52-L16-tree)

`docs/historia/revision/PIPELINE-PANEL-20261014/ports/0002-wifi-wcn6750.patch` (7 hunks, SEGURO: sin el compatible nuevo no cambia nada):
DTS `&wifi` (referencia, disabled): compatible `xiaomi,uke-wcn6750-wifi`, 3 supplies;
`&remoteproc_wpss`: cliffs + `qca6750/wpss.mdt` + cx-supply (frag 1707). ahb.h: include
regulator + `uke_regs[3]/uke_supplies/num_enabled` (convive con `pwrseq`). ahb.c:
`uke_regulators()` (probe, exige los 3, `-EINVAL` si falta), enable ordenado en
`power_up` + unwind si falla `rproc_boot`, `…_off()` inverso en `power_down`.
`docs/historia/revision/PIPELINE-PANEL-20261014/ports/0003-wpss-proxy-regulators.patch` (12+1 hunks, SOLO con `mx-supply` en DT):
proxy_enable/disable (votos TURBO cx/mx, resto de placas intacto), init_regulator
(cx+mx obligatorios si level), QMP obligatorio tras `q6v5_init`, recurso cliffs-wpss
(fw `qca6750/wpss.mdt`, TURBO), + header nuevo `qcom,rpmh-regulator-levels.h`.

## 4. Firmware (despliegue: reinstalar payload + `depmod`; NO va en el parche)

`/lib/firmware/ath11k/WCN6750/hw1.0/{amss.bin,board.bin,regdb.bin}` (vendor, payload 29-sep)
+ `board-2.bin` (linux-firmware, staging) + `/lib/firmware/qca6750/wpss.{mdt,b00-b10,b12}`
(sin b11, así en ROM). Ruta `qca6750/` = `firmware-name` del DT vivo y del parche.

## 5. Test (tras pantalla cerrada; blacklist vigente, `modprobe` manual, 1 variable/ciclo)

`modprobe pwrseq-qcom-wcn; time modprobe ath11k_ahb` → `dmesg -n 7 | grep -iE
'wpss|ath11k|wcn6750|pwrseq|board|CE.*EIO'` → `ip link` (wlan0) → `iw dev scan` →
asociación → criterio: **SSH por wlan + uptime>300 s** (como ellos) + `sync` antes de reboot.

## 6. Riesgos / wedge #601

R1 (top): frags 1701-07 wedgean a 4,1-4,2 s pre-userspace. El port lo evita por diseño:
sin nodo `wifi-pmu` en boot (los 3 rails cuelgan del wifi, que sigue `disabled`),
sin reguladores virtuales que probar en arranque, módulos en blacklist + `modprobe`
manual → cero código wifi antes de userspace. R2: **0003 sin `mx-supply` rompe el
wpss que hoy SÍ levanta** (#441): NO aplicar 0003 hasta frag con cx+mx. R3: quitar
`mem=2048M` (L57) reabre `-EIO` de CE/MSI (swiotlb+bounce es la mitigación, sin medir).
Rollback: revert de parches (DT vuelve a `qcom,wcn6750-wifi` solo) + dtbo s275-r2 sin
wifi + payload/blacklist intactos. Hipótesis: `board.bin` vendor trae el id de uke
(lo dirá `ath11k_dbg`); MSI de anillos, pendiente tras primer QMI OK.
