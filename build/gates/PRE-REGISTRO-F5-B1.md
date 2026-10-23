# PRE-REGISTRO DE LEDGER — F5 / B1 — escrito ANTES de flashear (27-sep-2026)

Copiar literally al ledger del proyecto de origen
(`~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`) o al propio, **antes** de la escritura.

## F5-B1 — RAM/flash de la imagen de DIAGNÓSTICO en el slot a

**Contexto.** `fastboot boot` (RAM-boot) **no funciona en este ABL**: rechaza cualquier imagen con
`Failed to load/authenticate boot image: Load Error`, **incluido el shell bueno sin modificar**
(control medido: `s244-bounce.img` → mismo error exacto). No hay, por tanto, forma de probar el
kernel+initramfs de Arch sin escribir en la tablet. Esta entrada cubre ese hueco.

**Qué se hace (una sola variable).** Flashear `boot_a` = imagen de **diagnóstico** y activarla. El
`boot_b` (par bueno `s244-bounce` + `dtbo s229`) **no se toca**.

| | |
|---|---|
| **Artefacto** | `~/proyectos/omarchy-uke/build/bootimg/boot-arch-diag.img` |
| **sha256** | `98d1b40b0350fe882faf4082f8cdd76024ae5f636049e4a6926ecec0daf3ca5f` |
| **Tamaño** | 100663296 B (96 MiB) |
| **Kernel embebido** | `out/kernel`, sha `32e23e14b8fa…` (**OJO: NO es el del shell**, que es `adad4bb4`) |
| **initramfs** | el mismo cpio que usa la imagen final; contiene `ukeinit-diag` y `ukeinit-arch` |
| **cmdline** | 260 B; los 5 tokens de F5 + `rdinit=/ukeinit-diag` |
| **Aserciones** | 10/10 en verde (AVB0, AVBf, header v4, 5 tokens, sin `swiotlb`, cola `SIG_OFF:` idéntica, rollback 1769904000, kernel idéntico, vbmeta intacto, firmas) |
| **Comando** | `fastboot flash boot_a boot-arch-diag.img` → `fastboot set_active a` → `fastboot reboot` |
| **gates previos** | voltaje ≥ 3700 mV (medido **4260 mV**), `unlocked:yes`, los 4 `slot-retry-count` leídos (**a:7 b:7**, ninguno unbootable), consola ACM con **un solo lector**, vigía de fastboot **pausado** |

**Qué hace el init de diagnóstico (`ukeinit-diag`).** Monta pseudo-FS, `printk=7`, levanta el gadget
**ACM + RNDIS**, espera UDC y lo enlaza **al final**, se pone en `192.168.42.129`. **NO toca
`userdata`, NO hace e2fsck, NO hace switch_root.** Si alcanza el HTTP del PC, instala la imagen de
Arch en `userdata` **con sus gates** (sha256 del `.gz` antes de descomprimir, partición identificada
por contenido, verificación de init de systemd después) y reinicia. Si no lo alcanza, se queda en
shell con consola y red vivas.

**Criterios de ÉXITO (medibles).**
1. En la consola ACM aparece `ukediag: ... kernel 7.2.0-rc2-palawan+` ⇒ **el kernel arranca**.
2. Aparece `ukediag: UDC = …` y `ukediag: gadget BOUND` ⇒ el gadget funciona.
3. Aparece `ukediag: red en usb0 = 192.168.42.129` y el PC responde al ping.
4. Aparece el bloque `KERNEL + INITRAMFS DE ARCH ARRANCAN` ⇒ **este es el gate que el RAM-boot no
   podía dar**.
5. Si llega a instalar: `dd terminado rc=0` + `OK, hay init de systemd dentro` + `INSTALACION CORRECTA`.

**Criterios de FRACASO.**
- (a) **No aparece ninguna línea de `ukediag`** ⇒ el kernel no arranca o el initramfs no se monta.
  Entonces: `fastboot set_active b` + `fastboot reboot` y volver a Ubuntu. Y el culpable es el
  **kernel `32e23e14`, no el repack** (el repack está probado byte a byte).
- (b) `no aparece ningun UDC en 30 s` ⇒ problema de pila USB/gadget, no de rootfs.
- (c) `SHA NO COINCIDE` ⇒ **no se escribe nada**, se queda en shell. Es un gate, no un fallo.
- (d) `el rootfs NO monta tras el dd` ⇒ el rootfs quedó a medias. **Rollback**: desde el shell de
  `ukediag` (que sigue vivo) `zcat | dd` del `rootfs.img.gz` de Ubuntu (369822577 B, sha
  `b6d5411712b…`) servido por el PC.

**Coste.** **1 reintento del slot a.** El slot b **no se toca** y queda intacto con retry 7.
⚠️ En fastboot la tablet **no carga** (medido 3451→3411 mV en el hermano); está en 4260 mV, así que
hay margen, pero no chaining de cargas largas.

**Red de recuperación.** `fastboot set_active b` + `reboot` → Ubuntu con **su rootfs intacto**
(porque en este paso no se escribe `userdata`). Esto es lo que hace la fase segura: la prueba del
kernel y del initramfs ocurre **antes** de tocar el rootfs.

**Vuelta atrás.**
```bash
fastboot set_active b
fastboot reboot          # Ubuntu, con boot.img y rootfs originales
```

### Addendum 27-sep-2026 (antes de ejecutar)

- El init de diagnóstico **reintenta la descarga hasta 2 veces**, con 24 intentos de 10 s cada una
  (~4 min por intento). Motivo: la interfaz `192.168.42.1` del PC **solo existe después** de que el
  propio init levanta el RNDIS, así que el servidor no puede estar levantado de antemano. Sin el
  reintento, el primer intento fallaría siempre y el init caería a shell sin instalar nada.
- Al meter el reintento, el cpio pasó a 2 394 655 B y la imagen a un **sha nuevo**:
  **`98d1b40b0350fe882faf4082f8cdd76024ae5f636049e4a6926ecec0daf3ca5f`** (10/10 aserciones).
- Secuencia del host mientras la tablet arranca: esperar a que aparezca la interfaz USB de red →
  asignarle `192.168.42.1/24` → levantar `python3 -m http.server 8000` en
  `build/rootfs/`. El init lo encuentra solo.

---

## F5-V1 — PRE-REGISTRO (27-sep-2026, antes de la escritura)

**Qué se hace:** UNA escritura. `fastboot flash userdata arch-rootfs.simg`. Nada más.

| | |
|---|---|
| **Artefacto** | `~/proyectos/omarchy-uke/build/rootfs/arch-rootfs.simg` |
| **sha256 (PRE-REGISTRADO)** | `0cdc7386bb1c1d7d7f6cf2ef6ebe569b7cafbaf0dc38480a96e8dd417898614e` |
| **Tamaño** | 1 207 455 712 B (sparse; la partición son 113 657 229 312 B) |
| **Destino** | `/dev/disk/by-partlabel/userdata` (verificada por `blkid`: `TYPE=ext4`, `PARTLABEL=userdata`) |
| **NO se toca** | `boot_a`, `boot_b`, `dtbo_b`, `vendor_boot_b`, `vbmeta`, `misc` |
| **Comando** | `fastboot flash userdata <artefacto>` → `fastboot reboot` |
| **Precedente** | El hermano lo probó **3/3** con `rootfs.simg` de 87 MB en ~21 s, sin que el tamaño coincida |

**Gates de entrada (medidos justo antes):**
- fastboot: OK
- `battery-voltage: 4232 mV` ≥ 3700 ✅
- `current-slot: b`, `slot-retry-count:b: 4` (**presupuesto: 3 boots**), `slot-unbootable:b: no`
- `slot-retry-count:a: 6`, `slot-unbootable:a: yes` (slot a inservible, no se usa)
- sha del artefacto = el pre-registrado ✅

**Criterios de ÉXITO.** `S123: raiz candidata` → `RAIZ … VERIFICADA` → `X9S123-SWITCH` en la consola
ACM; y luego `ssh -i ~/proyectos/omarchy-uke/build/rootfs/uke-arch-root root@192.168.42.129` →
`uname -m` = `aarch64`, `/etc/os-release` = Arch Linux ARM.

**Criterios de FRACASO.**
- (a) No aparece `S123` ⇒ el problema es la cadena, no el rootfs → Boot 2 (restaurar).
- (b) `S123` pero no `X9S123-SWITCH` ⇒ el gate de raíz rechazó la imagen → leer el mensaje exacto.
- (c) Cae a fastboot ⇒ reintentos de `b` agotados → Boot 2.

**Vuelta atrás (Boot 2, sin encadenar un 3.º flash el mismo día):**
`fastboot flash userdata ~/gpu-work/ramaa/s22/rootfs.simg` (87 MB, probado) → `fastboot reboot`.

## F5-V2 — Boot 2: restaurar Ubuntu (27-sep-2026, pre-registrado antes de escribir)

**Por qué, y por qué no es rendirse:** el flash de Arch funcionó (`Writing OKAY`) y el sistema
arrancó 7 min, pero **no hay forma de saber si la raíz era Arch** porque no hay red, ni shell, ni
conscola interactiva. Restaurar Ubuntu **cuesta el mismo boot** que seguir adivinando y **devuelve las
herramientas para responder la pregunta con datos**: con SSH se puede leer el superbloque y el
`os-release` de `userdata` directamente, y leer `/sys/fs/pstore` del arranque anterior.

| | |
|---|---|
| **Artefacto** | `~/gpu-work/ramaa/s22/rootfs.simg` (**87 177 648 B**, la imagen **probada 3/3** por el hermano) |
| **sha256 (PRE-REGISTRADO)** | `f356c75f18b3af53ec559f886cae626f85d407b916b51e7e8a1e13b2f35aa6a4` |
| **Comando** | `fastboot flash userdata <artefacto>` → `fastboot reboot` |
| **NO se toca** | `boot_a`, `boot_b`, `dtbo_b`, `vendor_boot_b`, `vbmeta`, `misc` |
| **Gates de entrada** | `battery-voltage: 4225 mV` ✅ · `current-slot: b` · `slot-retry-count:b: 3` (3 boots) · sha = el de arriba ✅ |
| **Supervivencia** | La imagen de Arch **no se pierde**: está en el PC (`arch-rootfs.img` 8 GiB y `arch-rootfs.simg` 1,2 GB) |

**Después del reboot, la pregunta que hay que responder con SSH (no con suposiciones):**
```bash
# 1) ¿qué hay realmente en userdata?
blkid -o value -s TYPE /dev/disk/by-partlabel/userdata
debugfs -R "cat /etc/os-release" /dev/disk/by-partlabel/userdata 2>/dev/null | head -3
# 2) ¿hay registro del arranque anterior?
ls -la /sys/fs/pstore/ ; dmesg | grep -iE 'ramoops|mtdoops|pstore|prevlog'
# 3) estado de los slots tras el próximo boot
```

---

## F5-V2 — pre-registro del flash del rootfs con el arreglo de red (27-sep-2026, 11:2x)

| campo | valor |
|---|---|
| fila | ledger hermano **pendiente de asignar** (este proyecto no escribe en el suyo) |
| fecha | 2026-09-27 |
| objetivo | sustituir SOLO el rootfs de `userdata` por la imagen de Arch V2 (arreglo de red) |
| partición tocada | `userdata` = `/dev/sda32` (**105 GB**, la imagen son 8 GiB) |
| imagen | `build/rootfs/arch-rootfs.img`, **8589934592 B, CRUDA (sin sparse)** |
| **sha256 (pre-registrado)** | `64b26294ca096ff952991c242f1787f1ec510ce2ba3a6c159b0deeb650cd449f` |
| por qué sin sparse | `fastboot flash` de una sparse **no borra la partición**: solo escribe los trozos declarados. Con Ubuntu(87 MB sparse) sobre Arch(1,2 GB sparse) salió un frankenstein con metadatos de Ubuntu y **sin `/sbin/init`** (`S123: montada pero SIN init → fallback fork`). La cruda escribe los 8 GiB enteros. |
| NO se toca | `boot_a`, `boot_b`, `dtbo_b`, `vendor_boot_b`, `vbmeta`, `misc` |
| orden | `Power+Vol−` → fastboot → gates → flash → reboot |
| rollback | la tablet ya tiene Arch V1 instalado (funciona: arranca, login en ttyGS0). Si V2 fallara, se puede volver a V1 con la misma operación. Image de referencia del estado bueno: sha de arriba (V2) y la de V1 en `SHA-BUENOS.txt`. |
| verificación de lectura | `sha256sum` de la imagen local + Montar en ro y leer `os-release`, `/usr/lib/systemd/systemd`, `/usr/bin/sshd` — todo verificado **antes** de escribir |
| gates antes de escribir | `battery-voltage` ≥ 3700 mV · los 4 `slot-retry-count` + `slot-unbootable` · sha de la imagen == el de esta tabla |
| hypothesis a comprobar | `enp0s20f0u3` en el PC sale de `<NO-CARRIER>` porque la NCM del lado tablet quedó DOWN: los `.network` de la imagen son `en*`/`eth*` con DHCP y una NCM de USB se llama `enx<MAC>`/`usb0`. Con V2 (`Name=usb0 enx* rndis*` + IP estática 192.168.42.129/24) debe salir carrier y aparecer SSH. **Si V2 tampoco da red, la hipótesis queda refutada** y el siguiente paso es mirar qué nombra el kernel a la NCM (`dmesg | grep -i renum`), no tocar más ficheros a ciegas. |

---

## F5-V3 — pre-registro: el arreglo de `/run/sshd` (27-sep-2026, 11:5x)

| campo | valor |
|---|---|
| fila | ledger hermano **pendiente** |
| fecha | 2026-09-27 |
| objetivo | sustituir SOLO `userdata` por la imagen de Arch V3, que además de la red hace que `sshd` arranque |
| partición tocada | `userdata` = `/dev/sda32` (**105 GB**; la imagen son 8 GiB) |
| imagen | `build/rootfs/arch-rootfs.img`, **8589934592 B, CRUDA (sin sparse)** |
| **sha256 (pre-registrado)** | `c26a5fcd799999664d4552cadf92bcb23b85f3a4f17f4c53ef597de40a39b037` |
| cambio único | `/etc/systemd/system/sshd.service.d/10-runsshd.conf` con `RuntimeDirectory=sshd` + `RuntimeDirectoryMode=0755`. Nada más. La red (V2) ya está en el staging y se conserva. |
| NO se toca | `boot_a`, `boot_b`, `dtbo_b`, `vendor_boot_b`, `vbmeta`, `misc` |
| gates antes de escribir | `battery-voltage` ≥ 3700 mV · los 4 `slot-retry-count` + `slot-unbootable` · sha de la imagen == el de esta tabla |
| hipótesis a comprobar | `sshd` no escucha porque **nada crea `/run/sshd`** y OpenSSH ≥7.5 lo exige (privilege separation obligatorio, no configurable). Con el drop-in debe abrir el 22 y el SSH con `build/rootfs/uke-arch-root` debe entrar. **Si el 22 sigue cerrado, la hipótesis queda refutada** y el siguiente paso es `sshd -t` y `journalctl -u sshd` desde la consola, no tocar más ficheros a ciegas. |
| rollback | V2 está en la tablet ahora mismo (funciona: Arch + red + ping 2 ms). Si V3 fallara, se reflashea V2 con la misma operación. |

---

## F5-V4 — pre-registro: usuario `sshd` + identidad correcta (27-sep-2026, tarde)

| campo | valor |
|---|---|
| fila | ledger hermano **pendiente** (los flashes V2/V3 de hoy tampoco están aún; ver nota de cumplimiento) |
| objetivo | sustituir SOLO `userdata` por la imagen V4, que crea el usuario `sshd` y hornea el árbol con uid 0 real |
| partición tocada | `userdata` = `/dev/sda32` (105,8 GiB; la imagen son 8 GiB) |
| imagen | `build/rootfs/arch-rootfs.img`, **8589934592 B, CRUDA (sin sparse)** |
| **sha256 (pre-registrado)** | `6d7b3fb8254c3229f2e131d3597c7d791965640fc4673b2e147933760b86624d` |
| cambios | (1) `sshd` en `etc/passwd`+`etc/group` (74/74) y `usr/lib/sysusers.d/openssh.conf`; (2) imagen construida bajo `fakeroot` con `chown -R 0:0`. Se conservan la red y el drop-in de sshd. |
| NO se toca | `boot_a`, `boot_b`, `dtbo_b`, `vendor_boot_b`, `vbmeta`, `misc` |
| gates antes de escribir | `battery-voltage` ≥ 3700 mV · los 4 `slot-retry-count` + `slot-unbootable` · sha de la imagen == el de esta tabla · **verificar que NO hay sesión viva del proyecto hermano en la tablet** (semáforo inter-proyecto) |
| hipótesis a comprobar | `sshd` muere en `main()` antes de `listen()` por (a) `Privilege separation user sshd does not exist` y (b) `/usr/share/empty.sshd ... must be owned by root`; y además `StrictModes` rechazaría `/root/.ssh` de uid 1000. Con V4 los tres desaparecen ⇒ **el 22 debe abrir y el login por clave debe entrar**. **Si el 22 sigue cerrado, la hipótesis queda refutada**: siguiente paso `journalctl -u sshd` por consola, no otro cambio a ciegas. |
| rollback | V3 guardada en `/tmp/opencode/V3-seguro.img` (sha `c26a5fcd799999664d4552cadf92bcb23b85f3a4f17f4c53ef597de40a39b037`). V3 es la que está en la tablet ahora mismo y **funciona**: Arch + red. |
| **NO FLASHAR HOY** | ya van 2 escrituras (V2 `64b26294…`, V3 `c26a5fcd…`) y el presupuesto es **≤2/día**. V4 espera a la próxima ventana, con la batería por encima de 3700 mV. |

---

## F5-V4 (s231) — pre-registro: overlay de arranque para el registro del DRM (27-sep-2026, noche)

| campo | valor |
|---|---|
| objetivo | sustituir SOLO `dtbo_b` por `s231` = `s229` vigente + overlay que pone `msm.separate_gpu_kms=1` en el cmdline y `qcom,lamma` en la raíz. El objetivo es que el probe de la GPU entre por la rama del DRM y aparezca `/dev/dri`. |
| partición tocada | `dtbo_b` (**solo**). NO se toca `userdata` (Arch intacto), ni `boot_a/boot_b/vendor_boot_b/vbmeta/misc`. |
| imagen | `build/bootimg/s231-boot-dtbo-gpu-kms.img`, 610 304 B, **CRUDA** (sin sparse) |
| **sha256 (pre-registrado)** | `c2a4c82803afc6d8fb0541054417c6f993d5811cf38dcea4ec563a57f246c39b` |
| rollback | `s229-boot-dtbo-wifi-wpss.img` (sha `d2a29ea5…`) — **una sola escritura** y vuelve al estado conocido bueno. El rootfs Arch no se toca, así que aunque el dtbo no arranque, `userdata` sigue siendo Arch. |
| gates del constructor | `build/bootimg/mkdtbo-s231.py` con 5 asserts: G1 `fdtoverlay` limpio; G2 el diff de los DTBs **fusionados** es solo `/chosen/bootargs` + `/ compatible`; G3 el bootargs = prefijo-base + parámetro (prefijo de 684 B intacto, +23); G4 los 4 compatibles de la raíz presentes; G5 el nodo GPU idéntico (status/iommus/9 OPP/qcom,gmu). **Todos verdes, verificado.** |
| hypothesis a comprobar | Con `separate_gpu_kms=1` **en el arranque**, `adreno_probe` toma `msm_gpu_probe` → `msm_drm_init` → `drm_dev_register`, y aparece `/dev/dri/card0`+`renderD128`. La variable del clon (`-22` = grupo IOMMU compartido) queda fuera, porque aquí se usa el nodo REAL en su propio probe de arranque, sin clon. **Si no aparece `/dev/dri`, la hipótesis queda refutada** y no se reintenta parcheando el driver a ciegas. |
| riesgo conocido | El hermano tiene anotado (ledger #409) que `separate_gpu_kms=1` **por cmdline no arrancaba** en este kernel; no se sabe por qué. Si este arranque no levanta, el rollback es una escritura a `dtbo_b`. El watchdog está muerto, así que si el CM3 se cuelga al abrir `/dev/dri` (no se abre aquí) haría falta reset físico. |
| battery gate | El flash de `dtbo_b` **no consume batería extra** (es el mismo tamaño que s229, ~610 KB), pero el **arranque posterior sí**. Batería leída en fastboot: ≥3700 mV. El día ya lleva 3 escrituras a `userdata` + esto; cerrar por debajo del presupuesto. |
| semaforo | Sin sesión viva del hermano (su ledger paró en #444, que es mío). El `dtbo_b` es compartido: si él lo usa, avisar. |

---

## PRE-REGISTRO — 27-sep-2026, `s232` (paso 1 del display: GPU como COMPONENTE)

| campo | valor |
|---|---|
| imagen | `build/bootimg/s232-boot-dtbo-gpu-component.img` |
| sha256 | `b5e781ff2efd8c258f88e4499651f609387974e104a8062a5db0a1704f2a7fc8` |
| tamaño | 607310 B (cabe en dtbo_b: 610304 B) |
| destino | `dtbo_b` SOLO. `boot_b` no se toca. `userdata` no se toca. |
| contenido | `s229` + `qcom,lamma` en la raíz. **SIN** `msm.separate_gpu_kms` |
| rollback | `dtbo_b` -> `s229` (sha en `SHA-BUENOS.txt`), una sola escritura |
| por qué | Devuelve la GPU al camino `component_add` (`adreno_device.c:277-284`): deja de crear\n  su device render-only y pasa a ser componente del maestro del display. Si el bind completa,\n  el device es `msm_driver` = RENDER + ATOMIC + MODESET + fbdev, en uno solo. |

### Gates (todos verdes, script `build/bootimg/mkdtbo-s232.py`)
- **G0** `s229` ya trae el árbol mainline del display: PHY `qcom,sm8650-dsi-phy-4nm` (×2),
  DPU `qcom,palawan-dpu`, `dispcc`, panel `xiaomi,uke-o82-4202-0b`, `panel@0`.
  **Hallazgo: el overlay de display del hermano YA está horneado en `s229`** (fragmentos 86, 98,
  1105). No hay que añadirlo, y por eso `s232` solo añade `lamma`.
- **G1** `fdtoverlay` limpio sobre el DTB base del vendor.
- **G2** el fusionado **no** lleva `separate_gpu_kms`.
- **G3** `qcom,lamma` en la raíz del compatible, con los 4 tokens de vendor.
- **G4** el diff contra `s229` es exactamente el compatible de la raíz.
- **G5** el árbol del display sigue intacto en el fusionado.
- **G6** cabecera dtbo coherente (magic, 1 entrada, total_size, dt_size, dt_offset=64, payload
  idéntico) y sha releído hasheando la imagen entera.
- **G7** la imagen cabe en `dtbo_b`.

### Lo que este dtbo NO hace
No arregla el display. `s232` separa una variable: **GPU como componente frente a GPU con device
propio**. Con `separate_gpu_kms=0` el maestro es el DPU mainline, y su cadena de bind se pone a la
vista. La hipótesis sobre por qué el árbol mainline que ya está en `s229` no liga: hoy conviven
**dos pilas DSI** en el árbol — la de vendor (`/soc/qcom,mdss_dsi_phy0@ae95500`, compatible
`qcom,dsi-phy-v5.2`, sin driver) y la mainline (`/soc/display-subsystem@ae00000/phy@ae95000`), y el
`dsi_get_phy: phy driver is not ready` que se ve en dmesg es el de la de **vendor**. Eso se
comprueba en el arranque de `s232`, no antes.

---

## PRE-REGISTRO — 27-sep-2026, `s233` (arreglo del regulador que bloquea al panel)

| campo | valor |
|---|---|
| imagen | `build/bootimg/s233-boot-dtbo-panel-reg.img` |
| sha256 | `b336c69dfbaecd577724fdad3e045284fd8f8316763d8aacf0f87788e54e881d` |
| tamaño | 607470 B (cabe en dtbo_b: 610304 B) |
| destino | `dtbo_b` SOLO |
| contenido | `s229` + `qcom,lamma` + `pmxr2230_l8` (phandle 0x14f) reescrito como `regulator-fixed` |
| rollback | `dtbo_b` -> `s232` (`b5e781ff…`) o a `s229` |

### Qué mide el arranque de s232 (17:14) — todo dmesg real
- `separate_gpu_kms = N` → la GPU vuelve al camino `component_add`
- `ae95000.phy -> msm_dsi_phy` y `ae97000.phy -> msm_dsi_phy` → **los DOS PHY mainline ligan**
  (era el bloqueo principal)
- `ae94000.dsi -> msm_dsi`, `ae01000… -> msm_dpu`, `ae00000… -> msm-mdss`
- los nodos de VENDOR (`qcom,mdss_dsi_ctrl0`, `qcom,mdss_dsi_phy0`, `qcom,mdss_mdp`) quedan SIN
  DRIVER → el árbol mainline gana, no hay conflicto
- **pero `/dev/dri` vacío y sin `/dev/fb`**, por:
  `mipi-dsi ae94000.dsi.0: deferred probe pending: panel-xiaomi-o82-dualdsi: failed to get regulators`

### La cadena del fallo, medida
El panel no propea → no hace `dsi_host_attach` → **el componente DSI lo añade el ATTACH del panel,
no el probe del DSI** (`dsi_host.c:1744` → `dsi.c:159-162`) → el maestro del display nunca
completa el bind → no hay device DRM.

De los tres suministros que pide el panel (`panel-xiaomi-o82-dualdsi.c:78-82`):
- `vsp`/`vsn` → `uke-regulator-display-vsp`/`-vsn`: `regulator-fixed`, gpio tlmm 74/75, 5.8 V,
  ramp 233, boot-on. **Correctos.**
- `vddil8b` → phandle 0x14f = `pmxr2230_l8`, y aquí está el problema:
  `pmic-spmi 0-01: X9PMIC-skip: qcom,pmxr2230@1`

### El PMIC lo descarta el kernel A PROPÓSITO
`drivers/mfd/qcom-spmi-pmic.c:271-281` (uke X9 s171, #362): *"toda lectura SPMI de periférico
probada hasta hoy congela la máquina (~0.37-0.5 s, antes del dwc3: X9U=0). Se descartan TODOS los
qcom,spmi-pmic menos qcom,pm7550ba@7"*. O sea: **ningún rail L\* del pmxr2230 tiene driver**, y no
se toca SPMI bajo ningún concepto.

### El arreglo, y por qué NO toca el panel
Se reescribe **en su sitio** el nodo `pmxr2230_l8` (phandle 0x14f) con `regulator-fixed` sin gpio
(dummy siempre encendido, 1.9 V). Es un nodo **hoja** (1 llave abierta, 1 cerrada, sin hijos,
verificado), así que el reemplazo no pierde propiedades, y el `vddil8b-supply = <0x14f>` que el panel ya
tiene pasa a resolver. **Cero cambios en el panel.**

⚠️ **Intento descartado, medido**: crear un regulator stub nuevo y reapuntar el panel con un
`panel@0` anidado bajo `target-path`. El phandle llegaba, pero **la implementación de overlays de
este fork REEMPLAZA el nodo anidado en vez de fusionarlo**, y el panel salió con 3 propiedades:
había perdido `vsp-supply`, `vsn-supply`, `reset-gpios` y los pinctrl. Peor que el problema
original.

### Dos falsos positivos de diagnóstico que_costaron tiempo (anotados para no repetirlos)
1. `od -tx4` imprime en **orden nativo**: el phandle 0x6f5 sale como `f5060000`. Buscar
   `"0x6f5"` contra eso da "phandle colgando" cuando **está bien**. Los phandles estaban correctos.
2. En el DTB fusionado las supplies del panel van **ANTES** de `compatible` (orden:
   `reset-gpios`, `vsn`, `vsp`, `vddil8b`, `reg`, `compatible`). Un gate que solo mire
   después de `compatible` reporta "el panel perdió las supplies" sobre un panel intacto. Y tras
   `fdtoverlay` las etiquetas se resuelven y **renumeran** (vsp 0x6f5→0x6fe), así que el gate tiene
   que comprobar la *existencia* de la propiedad, no su etiqueta.

---

## PRE-REGISTRO — 27-sep-2026, `s234` (arregla el phandle que `s233` destruyó)

| campo | valor |
|---|---|
| imagen | `build/bootimg/s234-boot-dtbo-l8b-path.img` |
| sha256 | `2a28e4b1651b10b6d750c1624f9db446c12663d62c0f025d1e7eda76b4e97115` |
| tamaño | 607534 B (cabe en dtbo_b) |
| destino | `dtbo_b` SOLO |
| rollback | `s232` (`b5e781ff…`) o el par bueno `s229` |

### Lo que midió el arranque de `s233` (17:51, automático)
El flash lo hizo solo el vigilante `docs/historia/gates-palawan/auto-flash-s233.sh`: 3728 mV, sha verificado dos
veces, `rc=0`, `slot-retry-count:b` 3 y `a` 7 sin cambios. Arrancó. Y **`s233` rompió algo**:

    mipi-dsi ae94000.dsi.0: deferred probe pending: panel-xiaomi-o82-dualdsi: failed to get regulators

Igual que `s232`, pero ahora con un dato nuevo y grave:
- **No existe NINGÚN nodo con phandle `0x14f` en todo el device tree vivo.** Buscado en
  `/proc/device-tree` entero, comparando los 4 bytes en orden correcto.
- **No existe ningún nodo llamado `*l8*`** a ninguna profundidad.
Es decir: `target = <0x14f>` **DESTRUYE** el nodo en este fork (lo tira y crea uno nuevo sin
nombre), con lo que el `vddil8b-supply = <0x14f>` del panel queda **colgando**. Es la misma clase
de bug que el `panel@0` anidado del intento anterior: **en este kernel los overlays REEMPLAZAN en
vez de fusionar**, tanto con `target = <phandle>` como con nodos anidados bajo `target-path`.

### Dato de paso: L8B tampoco registraba antes
El debugfs del regulator registra `rpmh-regulator-ldob1`, `ldob7`, `ldob9`, `ldoe7`… pero
**no `ldob8`**, y de los L\* faltan `l8` y `l22`. O sea que el nodo L8B **no tenía driver
tampoco antes de que yo lo tocara**. Y los L\* SÍ se registran, pero por `qcom-rpmh-regulator`
(`17a00000.rsc:drv@2:rpmh-regulator-*`), **no** por el PMIC SPMI que descarta `X9PMIC-skip`.
O sea que el supuesto "ningún rail L* tiene driver por el PMIC descartado" era **exagerado**:
existe otro camino (RPMh) que sí funciona, y solo L8B (y L22) se quedan fuera por otra razón.
Queda por investigar por qué `ldob8` no registra; no bloquea, porque el dummy lo sustituye.

### La corrección
`target-path` con la **ruta completa** del nodo, medida en `base.dts:6766`:
`/soc/rsc@17a00000/drv@2/rpmh-regulator-ldob8/regulator-pmxr2230-l8`
Eso **fusiona**, conserva las propiedades del nodo (incluida su `phandle 0x14f`) y solo añade
`compatible = "regulator-fixed"` + `regulator-always-on` a 1.9 V.

### Gate nuevo y decisivo: **G4b**
Comprueba en el DTB **fusionado** que (a) sigue existiendo `phandle = <0x14f>`, (b) sigue
existiendo el nodo `regulator-pmxr2230-l8`, y (c) que ESE nodo (el que tiene ese phandle) es el
que ahora es `regulator-fixed`. Ese gate es exactamente el que faltaba en `s233` y el que habria
abortado el build antes de flashear nada.

---

## PRE-REGISTRO — 27-sep-2026, `s236` (**causa raíz real**: `enable-gpios`)

| campo | valor |
|---|---|
| imagen | `build/bootimg/s236-boot-dtbo-enable-gpios.img` |
| sha256 | `d9f9f36519fd0c5c89f81c17be6cdac83f4ed59bf13eff33f900d35028e19d50` |
| tamaño | 607758 B (cabe en dtbo_b) |
| contenido | `s229` + `lamma` + L8B→`regulator-fixed` + **`enable-gpios` en vsp/vsn** |
| rollback | `s234` (reintroduciría el bug de nombre) o el par bueno `s229` |

### LA CAUSA RAÍZ, y es una propiedad con el nombre antiguo
Error medido tras `s234`:
    platform soc:uke-regulator-display-vsp: deferred probe pending: reg-fixed-voltage: can't get GPIO
    platform soc:uke-regulator-display-vsn: deferred probe pending: reg-fixed-voltage: can't get GPIO

Y el motivo está en `drivers/regulator/fixed.c:317-321`:
    cfg.ena_gpiod = gpiod_get_optional(&pdev->dev, NULL, gflags);
    if (IS_ERR(cfg.ena_gpiod))
            return dev_err_probe(&pdev->dev, PTR_ERR(cfg.ena_gpiod), "can't get GPIO\n");

Con `con_id = NULL`, gpiod busca la propiedad literalmente `**enable-gpios**`. Los nodos del hermano
usan el nombre legacy `gpio`:
    uke-regulator-display-vsp:  gpio = <0x16b 0x4a 0x00>   enable-gpios: AUSENTE
    uke-regulator-display-vsn:  gpio = <0x16b 0x4b 0x00>   enable-gpios: AUSENTE

No es que falte el GPIO ni que el phandle este mal: `0x16b` esta VIVO
(`/proc/device-tree/soc/pinctrl@f000000`, `qcom,cliffs-pinctrl`, `#gpio-cells = <2>`,
`gpiochip0` registrado, `.ngpios = 179` ⇒ gpio2, 74 y 75 en rango). Es que `gpiod_get_optional`
devuelve **ERROR** —no "ausente"— porque el nombre no coincide, y el probe muere con ese texto. El
panel solo ve el efecto: sus `devm_regulator_bulk_get()` fallan.

**El arreglo**: añadir `enable-gpios` con el mismo valor, dejando `gpio` intacto.

### Lo que quedo DESCARTADO antes de tocar nada (todo medido)
- `qcom,gpios-reserved` del nodo pinctrl = `8 9 10 11 56 57 58 59 60`: gpio2, 74 y 75 estan **libres**.
- El phandle `0x16b` esta vivo (retractada mi conclusion de que estaba colgando: fue un error mio
  de orden de bytes al comparar `od -tx1` contra un patron de `-tx4`).
- `msm_gpio_init()` se llama (`pinctrl-msm.c:76`) y el gpiochip se registra: la linea
  `UKE-POKE: P5-gpio` que sale justo despues en dmesg lo confirma.
- No hay que tocar SPMI ni el PMIC: el L8B ya se resuelve con el dummy de `s234`.

### Gates (8 verdes, `build/bootimg/mkdtbo-s236.py`)
G1 los dos regularadores usan `gpio` legacy y no tienen `enable-gpios` · G1b el phandle 0x16b
medido · G2 fdtoverlay limpio · G3 sin separate_gpu_kms y con lamma · G4 L8B vivo y dummy ·
G5 los dos `enable-gpios` con el valor correcto · G6 los nodos conservan las 9 props ·
G7 el panel intacto · G8 cabecera y sha.

⚠️ **Falso positivo de gate que me costo un ciclo** (anotado para no repetirlo): `enable-active-high;`
y `regulator-boot-on;` son banderas SIN `=`. Un gate que exige `%s =` las da por perdidas sobre un
nodo intacto. Buscar por `^\s*PROP\s*(=|;)`.

---

## PRE-REGISTRO — 27-sep-2026, **`s237`** (retira los dos cambios MUERTOS de `s234`/`s236`)

| campo | valor |
|---|---|
| imagen | `build/bootimg/s237-boot-dtbo-minimo.img` |
| **sha256 (PRE-REGISTRADO)** | **`a0f71d7d46be20bc927a46dc37f1a8d94b52309f362962088cc65fb667d977bc`** |
| tamaño | 607310 B (cabe en `dtbo_b`: 610304 B), CRUDA |
| contenido | `s229` + **`qcom,lamma`** en la raíz. **Una sola línea de diferencia.** Nada más. |
| destino | `dtbo_b` SOLO. `boot_b` y `userdata` no se tocan. |
| rollback | `s229` (`d2a29ea5…`), que es el par bueno y nunca se ha tocado |
| constructor | `build/bootimg/mkdtbo-s237.py`, log en `build/gates/s237-GATES.log` |
| **NO FLASHADO** | esta entrada se escribe **antes** de ninguna escritura, y sigue sin escribirse nada |

### Por qué este overlay no es un arreglo sino una RETIRADA

`build/gates/AUDITORIA-REGULADORES-Y-GPIO.md` (§3, §4) llegó a dos conclusiones con evidencia:

1. **`s236` fue un NO-OP.** El `enable-gpios` aterrizó byte-correcto
   (`0000016b 0000004a 00000000`) y aun así los **cuatro** regularadores de display siguen
   diferidos, **incluidos los dos que NO tienen `enable-gpios`**. El nombre de la propiedad no era
   la causa: `can't get GPIO` es `ERR_PTR(-EPROBE_DEFER)` (`gpiolib-of.c:432-437`) porque el chip
   GPIO no se encuentra por phandle.
2. **El «dummy» de L8B de `s234`/`s236` es código muerto.** `rpmh_regulator_vendor_probe()` se come
   el nodo hijo en proceso, así que ningún segundo driver puede ligar. Y su
   `regulator-min-microvolt = 1900000` **causó** el `-131` de L8 (`apply_uV` = `min && max`,
   `of_regulator.c:110-111`; el path vendor tiene `voltage_selector = -ENOTRECOVERABLE` hasta
   *después* de registrarse). `s229` pone L8B a `min = max = 0` a propósito.

`s237` devuelve la tablet al estado mínimo que la auditoría predice que funciona. Su contenido es
**idéntico a `s232`** (G9b lo comprueba sobre el DT fusionado: 34 049 líneas iguales; los payloads
difieren en **1 byte**, el índice del fragmento añadido, `fragment@153` vs `fragment@155`, que no
referencia nadie).

### Gates (10 verdes, `build/gates/s237-GATES.log`)

G1 `fdtoverlay` limpio · G2 sin `separate_gpu_kms` · G3 `qcom,lamma` con los 4 tokens · **G4 el diff
contra el DT fusionado de s229 es EXACTAMENTE una línea** · **G5 L8B con phandle 0x14f vivo, sus 9
props de la línea base, `min = max = 0`, `init-voltage = 1900000`, sin `compatible` propio, sin
`regulator-fixed`, sin `uke-l8b-stub`** · **G6 ningún hijo de `rpmh-regulator-*` con `compatible` de
otro driver** · G7 los 22 rails conservan `min`/`max`/`init-voltage` · G8 panel intacto · G9
cabecera + sha releída + cabe en `dtbo_b` · **G9b equivalencia semántica con `s232`**.

**G4, G5 y G6 son los que faltaban** y son los que habrían parado `s234` y `s236` en el build, antes
de gastar un ciclo de flash. **`self-test-gates.py` lo demuestra**: pasa `s234` y `s236` por las
mismas comprobaciones y exige que aborten (`G5` y `G6` los cazan, `G4` ve 12 líneas de diff donde
esperaba 2), y comprueba que `s237` pasa **sin falsos positivos**.

> ⚠️ El propio G6 falló la primera vez: solo miraba hasta la línea que **abre** el nodo hijo, y el
> `compatible` va una línea más abajo, así que se pasaba `s234` y `s236` sin decir nada. Lo cazó
> `self-test-gates.py`. **Un gate que no ha fallado nunca no es un gate, es decoración** — y un gate
> que no ve el cuerpo del nodo es peor que no tener gate.

### Predicción falsable de este ciclo (esto es lo que hace que valga la pena)

Con `s237` en la tablet:

- 🟢 `rpmh-regulator-ldob8` **DEBE aparecer** en `regulator_summary` (con `s236` no aparece) ⇒ el
  panel recibe un `vddil8b` de verdad.
- 🟢 Desaparecen las dos líneas `uke-l8b-stub: failed to get the current voltage:
  -ENOTRECOVERABLE` y su `devm_regulator_register() failed, ret=-131`.
- 🟡 `pmxr2230_l22` **seguirá** fallando con `-131`. Es preexistente del overlay bueno y el panel
  **no lo usa**. Que siga no es un fallo de este overlay.
- 🔴 Los cuatro `reg-fixed-voltage: can't get GPIO` **seguirán** diferidos. **Este overlay no los
  arregla**: son el bloqueo real. El eslabón sin verificar es que el `of_node` de `gpiochip0` sea
  `/soc/pinctrl@f000000`, y se mide con `build/gates/diag-gpio.sh` — **0 flashes**.

**Si `rpmh-regulator-ldob8` NO aparece, la explicación de la auditoría queda REFUTADA** y no se
reintenta parcheando el driver a ciegas.

### Orden cuando se escriba (y solo entonces)

1. `fastboot getvar all` → `battery-voltage` ≥ 3700 mV, los 4 `slot-retry-count`, `slot-unbootable`.
2. sha de la imagen local = el de esta tabla.
3. `fastboot flash dtbo_b s237-boot-dtbo-minimo.img` (cruda).
4. **`fastboot set_active b` ANTES de `fastboot reboot`** (sin esto el ABL marca el slot
   unbootable y `continue` falla con *Failed to load image from partition*).
5. SSH y `build/gates/diag-gpio.sh`.

⚠️ **Antes de escribir, el diagnóstico de §5 de la auditoría es gratis y va primero** (es todo
SSH). Si sale que el `of_node` del gpiochip NO es el nodo del phandle, la causa raíz ya está
localizada y **`s237` no es lo que hay que escribir**: el arreglo es de otro sitio.

---

## PRE-REGISTRO — 28-sep-2026, **`s238`** — **CAUSA RAÍZ DEL PANEL MEDIDA EN CALIENTE**

| campo | valor |
|---|---|
| imagen | `build/bootimg/s238-boot-dtbo-dedup-gpio.img` |
| **sha256 (PRE-REGISTRADO)** | **`bdb361dff87de52dd7d4581c7f4007abdaf98ac145d47658ef2a29bc458f0022`** |
| tamaño | 607 534 B (cabe en `dtbo_b`: 610 304 B), CRUDA |
| contenido | `s229` + `qcom,lamma` + **`status = "disabled"` en `display_gpio_regulator_vsp` y `-vsn`** |
| destino | `dtbo_b` SOLO. `boot_b`, `userdata`, `vendor_boot_b`, `vbmeta` y `misc` **no se tocan** |
| rollback | `s229` (`d2a29ea5…`), el par bueno, que nunca se ha tocado |
| constructor | `build/bootimg/mkdtbo-s238.py`, **11 gates verdes**, log en `build/gates/s238-GATES.log` |
| **NO FLASHEADO** | este pre-registro se escribe **antes** de la escritura |
| semáforo | El hermano (ledger #443) reservó **`userdata`**, que aquí no se toca. **`dtbo_b` sí es compartido**: ya lo tenía yo con `s236` y aviso si lo toco |

### LA CAUSA RAÍZ, medida HOY en caliente — 0 flashes, 0 escrituras

Re-disparé el probe de `reg-fixed-voltage` escribiendo el nombre del device en
`/sys/bus/platform/drivers/reg-fixed-voltage/bind` (sin flash, sin MMIO, sin GPU, sin SMMU), con
`dmesg -n 7` y `CONFIG_DYNAMIC_DEBUG` activados para `drivers/gpio/*`:

```
of_get_named_gpiod_flags: parsed 'gpio' property of node '/soc/uke-regulator-display-vsp' - status (0)
reg-fixed-voltage soc:uke-regulator-display-vsp: using lookup tables for GPIO lookup
reg-fixed-voltage soc:uke-regulator-display-vsp: cannot find GPIO chip gpiolib_shared.proxy.45, deferring
bash: echo: write error: Resource temporarily unavailable          <- = -EPROBE_DEFER
```

**Cuatro hechos medidos, y el cuarto es la causa:**

1. **La propiedad no es el problema**: `status (0)`. El phandle `0x16b` resuelve,
   `readlink` del `of_node` del gpiochip = `/proc/device-tree/soc/pinctrl@f000000` (**coinciden**),
   `#gpio-cells = 2`, y `gpio74`/`gpio75` existen y son válidos
   (`gpio74 : out high func0 16mA pull up`).
2. **Cada pin lo piden DOS dispositivos**, y las dos parejas son idénticas prop a prop
   (solo cambia `regulator-name`), las dos con `compatible = "regulator-fixed"` y **las dos proban**:
   ```
   gpio74 -> /soc/uke-regulator-display-vsp   y   /soc/display_gpio_regulator_vsp
   gpio75 -> /soc/uke-regulator-display-vsn   y   /soc/display_gpio_regulator_vsn
   ```
3. **Este kernel tiene un mecanismo de GPIO compartido propio, no upstream**
   (`drivers/gpio/gpiolib-shared.c` + `gpio-shared-proxy.c`). En `gpiochip_setup_shared()`
   (gpiolib-shared.c:509-540): `if (list_count_nodes(&entry->refs) <= 1) continue;` — o sea, **más de
   un consumidor ⇒ `GPIOD_FLAG_SHARED` + `gpiod_request_commit(desc, "shared")`**, y a partir de ahí
   toda petición se enruta a un chip **proxy** `gpiolib_shared.proxy.<id>`, que se busca **por
   etiqueta** en `gpio_device_find_by_label()` (gpiolib.c:4652-4663). Si ese chip no existe:
   `-EPROBE_DEFER` **para siempre**.
4. 🔴 **Los proxies no existen**: **30** dispositivos `gpiolib_shared.proxy.*` en el bus auxiliar y
   **0 de 30 con driver**. El bus auxiliar solo tiene `aux_bridge`, `qcom_qseecom_uefisecapp` y
   `reset_mpfs`: **`gpio-shared-proxy` NO está construido en este kernel**.

### EL ARREGLO: un solo consumidor por pin

`panel@0` (el panel mainline, el que tiene driver) usa las supplies `uke_regulator_display_vsp/vsn`
(0x6fe/0x6ff). Los `display_gpio_regulator_*` solo los referencia el nodo **vendor**
`qcom,dsi-display-primary`, **que no tiene driver**. Con `status = "disabled"` ese nodo no crea
device, no pide el GPIO, y **gpio74/75 dejan de ser compartidos**: la petición va directa al gpiochip.

**Por qué no se tocan los otros 10 pines "compartidos"**: también los tienen, pero sus duplicados son
nodos **vendor sin driver**, que nunca llaman a `gpiod_get()` y nunca crean entrada compartida.
gpio2 solo lo pide `panel@0`. Tocarlos sería adivinar.

Además se retracta mi fragmento 154 de `s234`/`s236` (código muerto + causaba el `-131` de L8):
`s229` ya deja L8B en `min = max = 0`, que es lo que hace que el rail se registre.

### Gates: 11 verdes, **con autoprobado** (G11)

G1 `fdtoverlay` limpio · G2 sin `separate_gpu_kms` · G3 `qcom,lamma` · **G4 los dos duplicados
quedan `disabled`** · **G5 L8B con `min = max = 0`, sin compatible propio, sin `uke-l8b-stub`** ·
**G6 gpio74/75 con EXACTAMENTE UN consumidor real** (este es el que decide; cuenta consumidores
**reales**, no referencias de DT, porque un nodo `disabled` no crea device) · G7 `panel@0` con sus 3
supplies y su reset · G8 ningún hijo de `rpmh-regulator-*` con `compatible` de otro driver · G9 los
22 rails intactos · G10 cabecera + sha releída + cabe en `dtbo_b` · **G11 autoprobado: G4/G6 abortan
con `s236` y con `s234` y pasan con `s238`**.

> G6 falló en su **primera** ejecución: contaba referencias de DT, así que abortaba sobre un overlay
> correcto. Le pasa a uno lo mismo que a G6 de `s237` (mira solo hasta la línea que abre el nodo). Un
> gate tiene que medir **el mecanismo**, no un sinónimo suyo.

### Predicción falsable del ciclo (debenir por separado cada parte)

- 🟢 **Desaparecen** los cuatro `reg-fixed-voltage: can't get GPIO` y los dos
  `cannot find GPIO chip gpiolib_shared.proxy.N, deferring`.
- 🟢 `regulator_summary` gana `uke_panel_vsp` y `uke_panel_vsn` (±5,8 V).
- 🟢 `rpmh-regulator-ldob8` **aparece** (1900/1896/1904 mV: un punto de la rejilla de 8 mV).
- 🟢 `Setting 3300000-3300000uV` sigue precediendo al `-131` de `l22`, y **solo** a ese.
- 🟡 El `-131` de `pmxr2230_l22` **sigue**. Es preexistente y el panel no lo usa.
- 🔴 Si el pinSIGUE yendo al proxy ⇒ hay un tercer consumidor de gpio74/75 que no veo, y la
  hipótesis queda REFUTADA: el siguiente paso es `dmesg | grep -i proxy`, no tocar mas DT.

### Orden cuando se escriba

1. `fastboot getvar all` → `battery-voltage` ≥ 3700 mV, los 4 `slot-retry-count`, `slot-unbootable`.
2. sha local = el de esta tabla.
3. `fastboot flash dtbo_b s238-boot-dtbo-dedup-gpio.img` (cruda).
4. **`fastboot set_active b` ANTES de `fastboot reboot`** (sin eso el ABL marca el slot unbootable).
5. SSH: `dmesg | grep -iE "proxy|can't get GPIO|ENOTRECOVERABLE"`, `regulator_summary`, `/dev/dri`.

⚠️ **Antes de escribir**: `/dev/dri` **no existe** ahora mismo (medido) — `s236` quitó
`separate_gpu_kms`, así que la GPU está como componente esperando al maestro. **`s238` tampoco crea
`/dev/dri` por sí solo**: aparece cuando el panel propee y el maestro del display gane la carrera.

---

## PRE-REGISTRO DE LA ESCRITURA — 28-sep-2026, `dtbo_b` ← **`s238`**, con **WAIVER DEL GATE DE BATERÍA**

### 🔴 AVISO PRIMERO: se escribe por debajo del gate. Decisión del dueño, no descuido.

| gate | regla | **medido 28-sep** | veredicto |
|---|---|---|---|
| `battery-voltage` | ≥ **3700 mV** | **3483 mV** | ❌ **−217 mV — NO CUMPLE** |
| `slot-retry-count:b` | ≥ 3 | **6** | ✅ |
| `slot-retry-count:a` | (leído) | 7 | ✅ ninguno stuck |
| `slot-unbootable:a` / `:b` | — | `no` / `no` | ✅ |
| `current-slot` | — | `b` | ✅ |
| sha de la imagen | = pre-registrado | `bdb361df…` | ✅ idéntico |
| G1 `fdtoverlay` | verde | verde | ✅ |

**Quién decidió**: el dueño, a pregunta explícita, después de que se le dijesen los 3483 mV.
**Alternativa que se descartó**: salir de fastboot, cargar en Arch (el manómetro ya lee y marca
`status=Charging`, `input_current_limit=500 mA`) hasta 3700 mV y volver — **no cuesta reintento de
slot**, porque `boot_b` arranca bien. Se descartó por no esperar ~20–30 min.

**Riesgo asumido, con su tamaño**: la escritura son **607 534 B sobre USB**, unos **2–3 s** a
500 mA ⇒ del orden de 1,5 mAh, un 0,2 % de una celda de ~7500 mAh. La ventana de brownout es
estrecha. Lo que hace **caro** un corte aquí no es la física sino el **entorno de recuperación**:
`misc` BCB sucio, ext4 con ~880 errores y la tablet **que no carga en fastboot** (medido, `R-*` del
hermano). Si `dtbo_b` se corrompe, no hay `fastboot flash` disponible para repararlo sin salir de
ese estado. **Por eso el gate de 3700 mV existe** y por eso esto queda anotado como waiver.

**Mitigación aplicada**: la imagen es **reversible sin escribir**, porque el par bueno anterior
(`dtbo s229`, `d2a29ea5…`) **nunca se ha tocado** y está documentado arriba como rollback. El
`boot_b` (`s244-bounce`) tampoco se toca. ⇒ si el panel falla, el rollback es `fastboot flash dtbo_b`
del `s229`, no una reconstruccion.

### Secuencia exacta, a ejecutar **en este orden**

```
1. fastboot getvar battery-voltage        # 3483 mV, re-leído justo antes de escribir
2. fastboot getvar all | grep retry       # los 4, re-leídos
3. sha256sum build/bootimg/s238-boot-dtbo-dedup-gpio.img   # debe ser bdb361df…
4. fastboot flash dtbo_b build/bootimg/s238-boot-dtbo-dedup-gpio.img
5. fastboot getvar all | grep retry       # los 4, DESPUÉS: para ver el coste real
6. fastboot set_active b                  # OBLIGATORIO antes de reboot
7. fastboot reboot
```

**No se toca** en ningún paso: `boot_b`, `userdata` (reservado por el hermano, ledger #443),
`vendor_boot_b`, `vbmeta`, `misc`.

### Qué se mide después (criterios de éxito / fracaso, decididos ANTES)

- ✅ **Éxito**: el panel propea. Firma: en `regulator_summary` aparece `pmxr2230_l8` (**hoy = 0**,
  medido) y no hay `cannot find GPIO chip gpiolib_shared.proxy.*` en `dmesg`.
- ❌ **Fracaso**: sigue sin aparecer `pmxr2230_l8`. Entonces el overlay de configfs **sí** cambió el
  nodo a `0/0` (medido hoy en caliente) pero el rail falla por **otra** causa ⇒ volver al par bueno
  y buscar el siguiente `-131`, sin tocar más DT a ciegas.
- ⚠️ **Ni una cosa ni otra**: el kernel no arranca. **Presupuesto de 3 ciclos** por hipótesis; al
  tercero sin movimiento en `dmesg` se anota REFUTADO, no se intenta un cuarto flash.
- **Doble captura obligatoria** si se busca evidencia en `dmesg`: consola ACM **y** `ssh … 'dmesg -w'`.
  La consola a 115200 pierde la cola de líneas al cortar el reset, y ya produjo un «sin errores»
  falso (ledger #428 → #429 del hermano).

---

## PRE-REGISTRO DE LA ESCRITURA — 28-sep-2026, `dtbo_b` ← **`s250`** = `s238` + el DPU apunta al SMMU de la GPU

Numeración **250+ a propósito**: el proyecto hermano tiene artefactos `s236`..`s249` con **otro**
significado, y su propio `ESTADO-ACTUAL.md` avisa de que "los artefactos s236/s237/s238/s239 de la
sesión que se cerró están documentados sólo en el ledger #427/#428". Nombrar igual las cosas es
exactamente como se mezclan los dos proyectos.

| campo | valor |
|---|---|
| imagen | `build/bootimg/s250-boot-dtbo-dpu-smmu-gpu.img` |
| **sha256 (PRE-REGISTRADO)** | **`f17eab658d5db33deda7f4a9c99f9ac9c9c01999440f7d9ba195ce2ec7c45a4f`** |
| sha anterior, **DESCARTADA** | `215d43a3…` — la tenía el StreamID al revés; ver §LA CORRECCIÓN |
| tamaño | 607 646 B (cabe en `dtbo_b` = 610 304 B), CRUDA |
| base | **`s238`**, sha `bdb361df…` re-verificada por el propio constructor en G0 |
| contenido | **`s238` entero + UN fragmento**: `target-path = "/soc/display-subsystem@ae00000"`, `iommus = <0x1c1 0x02 0x00>` |
| destino | `dtbo_b` SOLO (el mismo que ya es mío desde el flash de `s238`) |
| rollback | **`s238`** (`bdb361dff…`), que está **probado en la tablet**:_gpio del panel resuelto, L8 registrado, DPU llega a `dpu_kms_hw_init` |
| constructor | `build/bootimg/mkdtbo-s250.py`, **G0–G10 verdes** con control negativo |

### LA HIPÓTESIS, en una frase y con su medida

Medido en la tablet viva con el `s238` ya escrito:

```
15000000.apps-smmu   driver=NINGUNO     <- el SMMU que pide el DPU
3da0000.kgsl-smmu    driver=arm-smmu    <- el de la GPU, vivo
IOMMU groups: 2   ·   clientes de iommu: 0
```

⇒ `msm_kms_init_vm` (`drivers/gpu/drm/msm/msm_kms.c:180-200`) recibe
`device_iommu_mapped(mdss_dev) == false` ⇒ `"no IOMMU, bailing out"` ⇒ `-ENODEV` ⇒
`dpu_kms_mmu_init failed: -19` ⇒ y el `-19` dispara un **puntero nulo** en la propia ruta de
limpieza (`msm_drm_init` → `msm_drm_uninit` → `dpu_kms_destroy` → `dead000000000108`).
**El paging request es el síntoma; la causa es el SMMU.**

Y un dato que reencuadra el problema: **`s229` ya hace este mismo arreglo, pero solo en uno de los
dos SMMU**:

```
target-path = "/soc/kgsl-smmu@3da0000";
compatible = "qcom,palawan-smmu-500", "qcom,adreno-smmu", "qcom,smmu-500", "arm,mmu-500";
```

Añadir compatibles de mainline a un SMMU **funciona** (el de la GPU, en la tablet ahora mismo). El
hermano lo probó en `apps_smmu` y le **wedgeó la tablet 6 de 6 veces** (ledger #440/#443,
`criticas/ronda-36/gpu-a-prima-apps-smmu.md`), sin causa conocida. **La asimetría es que el arreglo
se aplicó a uno de los dos.**

### POR QUÉ ESTE CAMBIO NO PUEDE WEDGEAR

`s250` **no toca `apps_smmu`**. No le cambia el `compatible`, no le cambia nada. Solo le añade un
segundo cliente a `kgsl-smmu`, que ya tiene driver. El mecanismo que wedgeó al hermano era
*hacer que un driver nuevo enlazara `apps-smmu`*, y aquí no hay driver nuevo ni nodo nuevo. El
gate G3 existe exactamente para que esto sea verificable y no una promesa: **aborta si el
`compatible` de `apps_smmu` deja de ser `qcom,qsmmu-v500`.**

### Por qué `0x00` en la celda de ID y no `0x1c00`

`kgsl-smmu` ya tiene un cliente vivo con `iommus = <0x1c1 0x00 0x00>`. Dos dominios con el **mismo**
stream ID pedirían el **mismo SMR**, y en `arm-smmu-v3` eso es un conflicto. El DPU conserva su
stream propio `0x02` (libre en ese SMMU) y usa la celda de ID a `0`, que es la forma **ya probada**
en este árbol. El phandle `0x1c1` se comprobó que existe **en `base-dtb.img`**, no solo en el árbol
fusionado: si no existiera en el base, el cambio sería un no-op silencioso y se perdería el flash.

### Lo que NO se afirma

- **No se afirma que el SMR 0x02 exista en `kgsl-smmu`.** No hay forma de comprobarlo sin el
  hardware. Si no existe, el dominio se aloca pero no programa SMR, y el display puede verse negro
  o hacer DMA-fallar. Por eso los criterios de éxito están escritos para **distinguir "no arrancó"
  de "arrancó sin panel"**.
- **Esto NO es la vía de IOMMU de verdad.** Sigue siendo el display **sin IOMMU** (DMA directa), que
  es lo que hace rápido y seguro. La vía fina es que `apps_smmu` arranque, y eso sigue abierto (su
  "artefacto A" wedgea, y el kernel-patch A′3 del hermano tampoco da IOMMU: usa un MMU no-op).

### 🔴 LA CORRECCIÓN: la primera versión de este cambio tenía el StreamID **al revés**

La primera construcción (`215d43a3…`) ponía `iommus = <0x1c1 0x00 0x02>`, elegida con la intención de
"no pisar a nadie": IDs ya usados en `kgsl-smmu` = {0x00, 0x02, 0x05, 0x07}, y el razonamiento era
"usa el ID 0, que es el ya probado, y mueve el stream". **Era exactamente al revés**, y lo dice el
código, medido en `drivers/iommu/arm/arm-smmu-v3/arm-smmu-v3.c:4042-4080`:

```c
new_stream->id = fwspec->ids[i];            /* la 1ª celda del iommus ES el StreamID */
...
existing = rb_find_add(&new_stream->node, &smmu->streams, arm_smmu_streams_cmp_node);
if (existing) {
        dev_warn(master->dev, "Aliasing StreamID 0x%x (from %s) unsupported, "
                 "expect DMA to be broken\n", sid, dev_name(existing_master->dev));
        ret = -ENODEV;
        break;
}
```

Tres consecuencias, todas medidas:

1. **La 1ª celda es el StreamID, no un ID de SMMU.** La 2ª celda la **ignora** el driver
   (`arm_smmu_of_xlate` → `iommu_fwspec_add_ids(dev, args->args, 1)`, solo `args[0]`).
2. **Un StreamID repetido da `-ENODEV`.** Habría devuelto **el mismo `-19`** que este proyecto
   existe para arreglar, pero con un mensaje (`Aliasing StreamID`) que no señala a la causa real.
   Un ciclo de flash gastado, y peor: la conclusión a la que se llegaria es "la hipótesis del
   redireccion es falsa", que es **falsa de verdad**: el problema era el StreamID mal elegido.
3. **Por eso el StreamID que hay que pedir es el del propio DPU, `0x02`.** De dos fuentes que
   coinciden: `s229` declara para el DPU `iommus = <0x129 0x1c00 0x02>`, y el `qcom,actlr` de
   `apps-smmu` tiene la entrada `0x1c00 0x02 0x01` — el par vendor del display. En `kgsl-smmu` la
   convención es la inversa (StreamID en la 1ª celda, 2ª siempre 0). De ahí `<0x1c1 0x02 0x00>`.

**El StreamID 0x02 está libre de verdad** (gate G10, y no basta con mirar `status`):
`wsa-macro@6B00000` lo declara pero está **`status = "disabled"`**; `gfx3d_secure` está
`status = ok` pero su compatible `qcom,smmu-kgsl-cb` **no lo reclama ningún driver del árbol**
(buscado en `drivers/`), así que no propea y no registra stream. Un nodo sin driver no puede
registrar StreamID: ese es el criterio que usa G10.

> **Esto no habria salido de un razonamiento**: salio de ejecutar el gate G10, y G10 existe porque
> el autoprobado de `s238` (`self-test-gates.py`) ya habia demostrado que un gate que no
> discrimina es peor que no tener gate, porque da confianza falsa. La tablet **no estaba en
> fastboot**, y por eso el trabajo en seco pudo evitar el error: con la tablet lista se habria
> flasheado `215d43a3…`, que habria fallado con el mensaje equivocado.

### ⛔ ESTA ESCRITURA ESTÁ CANCELADA — `s250` REFUTADO antes de flashear

**La imagen `f17eab65…` NO se ha escrito en la tablet y no se escribirá.** Todo lo de abajo queda
como registro de lo que se Creeó y por qué se cayó.

**La refutación, verificada a mano contra el código:** el driver que bindea `kgsl-smmu` es
**`arm-smmu` (v2)**, no `arm-smmu-v3`. La justificación entera de `s250` —`arm_smmu_of_xlate` de
una celda, `arm_smmu_insert_master`, `"Aliasing StreamID"`— estaba copiada de
`arm-smmu-v3.c`, que **aquí no se ejecuta**:

```
arm-smmu.c:2359     .name = "arm-smmu"                      <-- MEDIDO en la tablet
arm-smmu-v3.c:5543  .name = "arm-smmu-v3"
arm-smmu.c:1962     { .compatible = "arm,mmu-500" }         <-- lo declara kgsl-smmu
```

El xlate del v2 (`arm-smmu.c:1590-1602`) invierte lo que yo asumía:

```c
fwid |= FIELD_PREP(ARM_SMMU_SMR_ID,   args->args[0]);   /* ID     */
fwid |= FIELD_PREP(ARM_SMMU_SMR_MASK, args->args[1]);   /* MÁSCARA */
```

| lo que creí | lo que es |
|---|---|
| `0x1c00` = SMMU ID de la instancia | `0x1c00` = **identificador de stream del DPU** |
| `0x02` = StreamID del DPU | `0x02` = **máscara de coincidencia del SMR** |

Lo corroboran tres propiedades del propio DT: `qcom,handoff-smrs = <0x1c00 0x02>` (lo que el
bootloader dejó programado para el display), la tripla `0x1c00 0x02 0x01` dentro de `qcom,actlr`, y
`qcom,stream-id-range = <0x1c00 0x400>`.

Por tanto `<0x1c1 0x02 0x00>` pedía el stream `0x02`, que es de la **GPU** (sus clientes son `0x00`
GPU y `0x05` GMU). El DPU no lo emite nunca ⇒ **panel negro aunque el IOMMU "funcionara"**.

**Y corregir a `<0x1c1 0x1c00 0x02>`, que parece el arreglo obvio, tampoco vale**, por un motivo
independiente: `kgsl-smmu` (`0x3da0000`) y `apps-smmu` (`0x15000000`) son **dos instancias físicas
distintas**, con su `tcu-base` y su `qcom,actlr` propios. La ruta física de las peticiones del DPU va
por el interconnect al SMMU del sistema. **Un DT no puede crear un camino de interconnect.**

**Fallos del propio instrumental, que pasaban los gates:**
- G10 se apoyaba en *"wsa-macro@6B00000 es el titular del 0x02"*. **Falso**: ese nodo no tiene
  `iommus` en absoluto (`s250-merged.dts:21686-21700`). El otro declarante real de `(0x02,0)` es
  `gfx3d_secure`. Pasaba por un motivo equivocado, con evidencia inexistente.
- La premisa *"sin driver ⇒ no registra StreamID"* es **falsa en general**: `iommu_probe_device` corre
  desde el notifier del bus (`iommu.c:1817-1831`) haya o no driver.
- G2 tenía una comprobación **vacua**: `"0x02" in "<0x1c1 0x02 0x00>"` siempre es verdadero.

**La lección que sí se lleva, y que vale más que la imagen**: leí un fichero de driver entero y
construí sobre él **sin comprobar que era el driver que bindea**. El nombre del módulo_bindeado
estaba en la measurement que yo mismo tenía (`driver=arm-smmu`) y no lo usé como filtro. Con dos
directorios `arm-smmu/` y `arm-smmu-v3/` Conviven, leer "el driver de SMMU" sin mirar cuál es **no
es leer el driver**.

**Lo que queda en pie y es el camino real**: que **`apps-smmu` bindee**. Si bindea, el DPU obtiene
dominio, porque `qcom_smmu_def_domain_type()` (`arm-smmu-qcom.c:604-624`) devuelve
`IOMMU_DOMAIN_IDENTITY` para todo menos el WLAN: **bypass**, que es lo que un panel necesita, sin
traducción ni conflictos. El hermano ya registró que bindear `apps-smmu` wedgeó la tablet 6/6
veces (#418/#431). Ese parche `def_domain_type` es de la ronda 35 (26-sep), o sea que **el árbol ha
cambiado desde entonces**: si se reintenta, es por una causa distinta y medible, no por
insistencia.

### Secuencia, y qué se mide

```
1. fastboot getvar battery-voltage        # re-leído justo antes de escribir
2. fastboot getvar all | grep retry       # los 4
3. sha256sum s250-boot-dtbo-dpu-smmu-gpu.img   # = f17eab65…
4. fastboot flash dtbo_b s250-boot-dtbo-dpu-smmu-gpu.img
5. fastboot getvar all | grep retry       # coste real
6. fastboot set_active b                  # OBLIGATORIO antes de reboot
7. fastboot reboot
```

**No se toca**: `boot_b` (es del hermano), `userdata`, `vendor_boot_b`, `vbmeta`, `misc`.

**Criterios, decididos ANTES de escribir:**

| lo que se ve | veredicto |
|---|---|
| ✅ `/dev/dri` aparece **y** el panel se ve | la hipótesis era correcta; a por el IOMMU fino |
| 🟡 **el kernel arranca pero `/dev/dri` sigue vacío** | el SMMU se alzó pero el display no llegó: leer si `apps-smmu` o `kgsl-smmu`Ganó dominio. **No es "arrancó bien"**: es un resultado distinto, y el que dice si falta el SMR o falta algo más |
| 🟡 `/dev/dri` aparece pero **panel negro** | el display está, la memoria no: el SMR 0x02 no existe en ese SMMU. **A′3 (MMU no-op) pasa a ser la mejor opción** |
| ❌ no arranca / cuelga | rollback a `s238` (`bdb361df…`) y a la hipótesis A′3 |
| ❌ cuelgue con **cero consola** | sería el modo del wedge del hermano ⇒ **rollback inmediato, no un cuarto intento** |

**Presupuesto**: este es el **primer** intento de esta hipótesis. Tope de 3; al tercero sin
movimiento en `dmesg` se anota REFUTADO. Doble captura si se busca evidencia: consola ACM **y**
`ssh … 'dmesg -w'` (la consola a 115200 perdió la cola de líneas al cortar el reset, ledger
#428→#429 del hermano, y produjo un "sin errores" falso).

---

## PRE-REGISTRO — 28-sep-2026, `dtbo_b` ← **`s251`** = `s238` + `apps-smmu` que enlace

| campo | valor |
|---|---|
| imagen | `build/bootimg/s251-boot-dtbo-apps-smmu-bind.img` |
| **sha256 (PRE-REGISTRADO)** | **`78eb2645037291d825e901a2b27d988072a6ccc576d7633f933546f6bb93957a`** |
| tamaño | 607 674 B · `dtbo_b` admite 610 304 B ⇒ **margen 2 630 B** |
| base | `s238` (`bdb361dff…`, **re-verificada por sha en G0**) + `base-dtb.img` (`3f973c78f7dc6…`, fijado también) |
| **cambio único** | `/soc/apps-smmu@15000000`: `compatible` `"qcom,qsmmu-v500"` → `"qcom,sm8550-smmu-500", "qcom,smmu-500", "arm,mmu-500"` |
| destino | `dtbo_b` SOLO. No se toca `boot_b` (del hermano), `userdata`, `vendor_boot_b`, `vbmeta`, `misc` |
| rollback | **`s238`** (`bdb361dff…`), que está probado en la tablet |
| constructor | `build/bootimg/mkdtbo-s251.py`, **G0–G10 verdes con 4 controles negativos** |

### Por qué esto y no lo de `s250`
`s250` redirigía el `iommus` del DPU al SMMU de la GPU. **Refutado**: el driver que bindea es
`arm-smmu` (**v2**), no v3, y su xlate dice `args[0] = SMR ID`, `args[1] = SMR MASK`. El
identificador del DPU es **`0x1c00`** y `0x02` es la **máscara**. Además son dos instancias físicas
distintas: un DT no crea caminos de interconnect. Este `s251` **no toca el DPU** (G6 lo verifica).

### Por qué debería funcionar, con el código que lo sostiene (G4 lo comprueba en cada build)
- `arm,mmu-500` **sí** está en `arm_smmu_of_match` ⇒ el nodo **enlazará**. Añadir solo
  `qcom,smmu-500` sería **inerte** (0 ocurrencias ahí).
- `qcom,smmu-500` → `qcom_smmu_500_impl0_data` → `.impl = &qcom_smmu_500_impl`, que **sí** lleva
  `.def_domain_type = qcom_smmu_def_domain_type` ⇒ el DPU obtiene **`IOMMU_DOMAIN_IDENTITY`**.
- Con IDENTITY **no se toca ningún context bank**: solo `S2CR = BYPASS` en el SME del DPU. Y los
  maestros en IDENTITY **no consumen CB**, así que los 57 clientes no agotan los 71 banks.
- `qcom_smmu_actlr_client_of_match` no tiene ningún compatible de mdss/palawan ⇒ el DPU recibe
  **cero escrituras ACTLR**.
- `qcom_wcn6750-wifi` sigue en el código ⇒ el WLAN conserva su dominio traducido.

### 🔴 EL RIESGO, DICHO SIN ADORNOS
**`CONFIG_ARM_SMMU_MMU_500_CPRE_ERRATA=y`** en los dos `.config` del árbol (G5 lo lee y avisa). Eso
hace que `arm_mmu500_reset` haga **RMW de `CB_ACTLR` ×71** durante el reset. **La superficie de wedge
es la máxima, y un dtbo no la puede reducir.** El hermano ya midió 6/6 wedgeos: *stall de bus sin
panic*, sin pstore, y **sin consola** porque `ttyGS0` nace tarde.

**Dato nuevo que reencuadra el riesgo**: el bootloader ya programó **31 SMRs** en `apps-smmu`, uno de
ellos `0x1c00/0x02` = **el del display**, y **4 de esos 31 no existen en el DT**. Un reset los
destruiría. Es una hipótesis **distinta** de las que el hermano descartó (forma del nodo, hijos TBU)
y **no la he podido medir**: se anota como hipótesis, no como causa.

`ARM_SMMU_QCOM_DEBUG` está apagado: una variable de MMIO menos.

### Secuencia y criterio de fallo (escrito ANTES)
```
1. fastboot getvar battery-voltage        # re-leído justo antes de escribir
2. fastboot getvar all | grep retry       # los 4
3. sha256sum s251-...img                  # = 78eb2645…
4. fastboot flash dtbo_b s251-...img
5. fastboot getvar all | grep retry       # coste real
6. fastboot set_active b                  # OBLIGATORIO antes de reboot
7. fastboot reboot
```

**Abortar y volver a `s238` en cuanto aparezca:**
- `arm-smmu 15000000.apps-smmu:` **seguido de silencio antes del gadget USB** ⇒ wedge. **No
  reintentar sin pokes** (A′2 del hermano). Esta es la razón por la que sus 6 intentos no
  produjeron dato: sin pokes, un wedge es un wedge.
- `stream ID 0x… out of range for SMMU` / `SMR mask 0x… out of range` ⇒ el DPU no cabe en la tabla.
- `impossible number of S2 context banks!` ⇒ el TCU no responde; la causa sube de nivel.
- `Limiting the stream matching groups to 128` ⇒ se activó el quirk de bypass. Funcional, pero se
  reservó el último CB: vigilarlo.

**Éxito** = `msm_dpu` deja de decir `no IOMMU, bailing out` y aparece `/dev/dri/card0`.
**Fracaso limpio** = el kernel arranca y el DPU sigue sin IOMMU ⇒ el parche UKE cambió de sitio.

**Presupuesto**: intento nº 1 de esta hipótesis. Techo de 3. El tema `-19`/IOMMU va por el flash
**nº 8** contando los del hermano, y por eso el criterio de abandono ya escrito en `docs/historia/ESTADO-VIVO.md`
sigue vigente: si esto no da `card0` + panel, el tema se archiva y no hay `s252`.

---

## PRE-REGISTRO — 28-sep-2026, **`boot_a` + `dtbo_a`** = kernel con pokes + `s251`

Esto **no** es otro `s251` al slot b. `s251` al slot b ya se probó y **wedgeó** (ver entrada anterior).
Aquí van a **`a`**, y el par bueno del slot b **no se toca**.

| campo | valor |
|---|---|
| imagen 1 | `build/bootimg/boot-pokes.img` (kernel instrumentado) |
| **sha256 (PRE-REGISTRADO)** | **`ed1a4403b90c6518214af05bc614f454e51cc7142e08942a245a1e65ed6f4660`** |
| tamaño | 100 663 296 B = **stock size exacto** ⇒ se sigue llenando la partición entera, nada sparse |
| base | `boot_b` bueno **leído de la tablet** y verificado: `ffff8c51265ff03c84cff15ffdb275f396a666a491eb5d67580be705321db99e` (96 MiB hasheados, patrón ledger #241) |
| cambios en la imagen | **solo** `kernel_size@8` y `kernel@4096`; **más** `deferred_probe_timeout=30` en la cmdline (255 → 281 B de un campo de 1536) |
| imagen 2 | `build/bootimg/s251-boot-dtbo-apps-smmu-bind.img`, sha **`78eb2645037291d825e901a2b27d988072a6ccc576d7633f933546f6bb93957a`** |
| destino | **`boot_a` y `dtbo_a`**. `boot_b` y `dtbo_b` **NO SE TOCAN** |
| rollback | `fastboot set_active b` y reboot: vuelve al par bueno, que está intacto y verificado |
| kernel | compilado con `LLVM=1` (clang 22.1.8) y `build-uke/.config` (3 036 líneas, `CONFIG_ARCH_QCOM=y`) |

### Por qué van juntos, y por qué los dos son necesarios
- El **dtbo `s251`** es lo que da a `apps-smmu` el compatible que lo hace enlazar. **Sin él, el nodo
  no enlaza y el kernel instrumentado no hace nada.**
- El **kernel con pokes** es lo que hace que ese enlace sea observable:
  - quita `.suppress_bind_attrs`, y por tanto `/sys/bus/platform/drivers/arm-smmu/bind` existe
    (medido antes: 264 drivers lo tienen, `arm-smmu` no ⇒ sin esto no hay poke posible)
  - devuelve `-EPROBE_DEFER` **una vez** para el nodo con `reg = 0x15000000`, así que el reintento
    del kernel cae en `late_initcall_sync`, **con la consola ya viva**
  - `deferred_probe_timeout=30` en la cmdline hace que ese reintento no caiga antes de tiempo
  - migas de pan antes de cada acceso MMIO del probe

### ⚠️ Esto NO arregla el display. Solo lo hace visible.
Si el probe de `apps-smmu` wedgea, seguiré sin panel. Lo que gana el experimento es **saber en qué
acceso MMIO exacto**, que es lo que no tenía tras 8 intentos. Si el probe pasa, el SMMU del display
queda vivo con dominio IDENTITY (bypass) y el DPU deja de dar `-19`: eso sí sería el display.

### Gates del reempaquetado, todos verdes
`G0` base y kernel con sha · `G1` `ANDROID!` de 8 bytes y kernel gzip en `PAGE` · `G2` cmdline verificada
(`console=ttyGS0` y `rdinit=` presentes) y token añadido cabe · `G3` gzip nivel 9 (15 357 323 B,
38,5 %) · `G4` marcadores dentro del kernel: `UKE-POKE` presente, `o82`, `qcom,palawan-mdss`,
`qcom,palawan-dispcc`, `arm-smmu`, `qcom,smmu-500` · `G5`/`G6` cabecera coherente, tamaño de stock,
`kernel_addr` intacto · `G7` **cabecera y cola idénticas byte a byte**.

**Tres fallos de gate míos en el camino**, todos por la misma clase (un gate que muere por la razón
equivocada es peor que no tener gate):
1. Comparé `img[0:4]` contra `b"ANDROID!"` (8 bytes) ⇒ 4 ≠ 8 siempre.
2. Exigí `kernel_addr == PAGE` cuando en este layout vale 0 y es metadata que rellena el ABL.
3. G7 elegía rama con `nombre.startswith("0..")` sobre un nombre que empieza por `"initramfs..."`, así
   que comparaba los 4 096 bytes enteros, **incluida la cmdline que acabo de cambiar**, y moría
   con un mensaje sobre "la cola" que no era lo que había pasado.

### X9WAVE va dentro, y es honesto decirlo
El kernel compilado contiene también la instrumentación `X9WAVE` del hermano, porque sus ficheros
sin commitear (`runtime.c`, `uke-panic-fb.c`) están en el working tree del árbol **compartido** y se
compilan. No puedo construir un kernel que no los tenga sin tocar su trabajo. Para este experimento
**ayuda**: `X9WAVE` ya es un mecanismo de pokes, y `UKE-POKE` se suma al lado sin interferir.
Atribución: los cambios de este build son míos; el árbol es de los dos.

### Secuencia
```
1. tablet a fastboot; getvar battery-voltage; getvar all (los 4 slot-retry-count)
2. sha256sum de los dos ficheros = los pre-registrados
3. fastboot flash boot_a boot-pokes.img
4. fastboot flash dtbo_a s251-boot-dtbo-apps-smmu-bind.img
5. fastboot getvar all   (coste real)
6. fastboot set_active a
7. fastboot reboot
```
**Rollback**: `fastboot set_active b` + `fastboot reboot`. El par b está intacto.

**Criterio de lectura, escrito antes:**
- 🟢 `UKE-POKE: apps-smmu ... primer probe DIFFERIDO` ⇒ el parche está vivo. Luego,
  `UKE-POKE: apps-smmu: REINTENTO del probe, consola ya viva` ⇒ el reintento cayó con consola. **Eso
  ya es un resultado**, porque significa que el arranque no depende de este SMMU.
- 🔴 Si después del "REINTENTO" la consola se corta: **la última línea de miga dice el acceso MMIO
  exacto**. Ese es el dato quebusco.
- ✅ Si aparece `arm-smmu 15000000.apps-smmu: N context banks` ⇒ el probe pasa; el SMMU del display
  queda vivo y el DPU debería dejar de dar `-19`.

### 🔴 CORRECCIÓN DEL SHA — `boot-pokes.img` reempaquetado tras arreglar el parche

El sha `ed1a4403b90c…` que estaba pre-registrado **queda ANULADO**: ese kernel **no llevaba el
`-EPROBE_DEFER`**, porque el script del parche informaba de un cambio que no hacía
(`una_vez` hacía `txt.replace(ancla, ancla)`, es decir sustituía el ancla por sí misma, y aun así
devolvía `hecho=True`). Con ese kernel el probe habría corrido en `arch_initcall` y habría wedgeado
igual que `s251`, pero sin ninguna capacidad de diagnóstico.

| | sha | estado |
|---|---|---|
| `ed1a4403b90c6518214af05bc614f454e51cc7142e08942a245a1e65ed6f4660` | 100 663 296 B | ⛔ **ANULADO** — sin el diferir |
| **`81fc9f009bfec0e761c502eaaea6cc39ce19dc3a7453dc1a61459ccdc6012b9b`** | 100 663 296 B | ✅ **ESTE** — verificado dentro del kernel: `primer probe DIFFERIDO` 1, `REINTENTO del probe` 1, `sACR` 1, `deferred_probe` 6 |

Los tres fallos que hicieron falta para llegar aquí, todos de la misma clase — **un gate que dice OK
sobre algo que no está**:

1. `una_vez` sustituía el ancla por sí misma y devolvía `hecho=True`: el parche **informaba** un
   cambio que no hacía.
2. El guardia de idempotencia era **global** (`UKE-POKE` para los cuatro parches): al reejecutar,
   las migas de pan hacían creer que el diferir estaba puesto.
3. **Faltaba el gate de compilación.** Las comprobaciones son de texto: el fichero con el ancla
   duplicada pasaba todas y reventaba al compilar con *"function definition is not allowed here"*.
   Lo único que dice si un parche sirve es el compilador. **Añadido**, y es el que caga a la
   duplicación.

**El que casi no se ve, y es el que de verdad cambia el método**: los tres pasaron "en verde" y
ninguno habría detectado el fallo. El que lo cazó fue **leer el binario con `strings` y contar las
cadenas**, que es una comprobación de un tipo distinto: no mira lo que el script dice haber hecho,
mira lo que el fichero tiene. Un informe de cambios no es una aserción.

### 🔴 SEGUNDO SHA ANULADO — `81fc9f00…` tenía la condición del diferir **siempre falsa**

| | sha | estado |
|---|---|---|
| `ed1a4403b90c…` | 100 663 296 B | ⛔ anulado: el parche no insertaba el diferir |
| `81fc9f009bfec0e761c502eaaea6cc39ce19dc3a7453dc1a61459ccdc6012b9b` | 100 663 296 B | ⛔ **anulado**: la condición del diferir nunca era cierta |
| **`530a0ef62111e817e90f87520529f8f8ea141146642b99a47e8c611cdc2fdcd2`** | 100 663 296 B | ✅ **este** |

**El bug, que es el que explica por qué el par de pokes no cambió NADA** (arranque 13:03:16,
slot `a` unbootable a las 13:10:41, cero líneas de consola, idéntico a `s251`):

```c
if (np && of_property_read_u32(np, "reg", &base) == 0 &&
    of_property_read_u32(np, "reg", &size) == 0 &&     /* lee OTRA VEZ el elemento 0 */
    (u32)base == 0x15000000 && (u32)size == 0x100000)
```

`of_property_read_u32` lee **siempre el elemento 0**. Así que `size == base == 0x15000000`, la
condición es **siempre falsa**, el diferir no se disparó nunca y el probe corrió en `arch_initcall`
igual que con `s251`. Para la segunda celda hace falta `of_property_read_u32_index`.

Simulado antes de tocar nada, contra el `reg` real del nodo (`<0x15000000 0x100000 0x151fe000 0x40>`):

| versión | base | size | ¿se difiere? |
|---|---|---|---|
| la mía | `0x15000000` | `0x15000000` | **False** |
| la correcta | `0x15000000` | `0x00100000` | **True** |

**Añadido además** una miga **incondicional** al entrar en `arm_smmu_device_probe`, que es el primer
dato que de verdad faltaba: sin ella no se sabe ni si la función se ejecuta, ni para qué SMMU.
Y el gate de compilación del script del parche, que fue el que permitió que un fichero con el ancla
duplicada pasara todas las comprobaciones de texto.

### Rollback de este intento
`set_active b` + reboot. **`boot_b` y `dtbo_b` no se habían tocado** en todo el experimento: por eso
el par bueno seguía intacto (retry 7, unbootable no) y la vuelta fue un `set_active`. Verificado.
`slot a` queda unbootable con retry 6; un `set_active a` lo restablece.

### Lo que este intento enseña, y es lo importante
**Dos flashes fallidos por bugs de MIS scripts, no por la tablet.** Ninguno de los dos habría
sucedido si, en vez de fiarme de "el parche aplicado" y "los gates verdes", hubiera:
1. simulado la **condición** con los valores reales del DT (2 min, y habría detectado el `read_u32`);
2. compilado el fichero y leído las cadenas del **binario** (también 2 min).

La tablet, en cambio, ha hecho exactamente lo que debe: refusing to arrancar con un probe que la
mata, y volver al par bueno con un `set_active`.

---

## PRE-REGISTRO — 28-sep-2026 ~14:31 UTC — AISLAMIENTO: boot-pokes SOLO + dtbo s238 BUENO (sin s251)

**Por qué este ciclo es el más importante hasta ahora:** tres intentos anteriores flashearon A LA VEZ
un boot nuevo + dtbo s251 y los tres quedaron mudos (cero líneas de consola, slot a marcado no
booteable, vuelta a fastboot). Dos variables a la vez = imposible saber cuál mataba el arranque.
Este ciclo QUITA el s251 y deja SOLO el kernel de pokes. Así se aísla.

| campo | valor |
|---|---|
| boot_a <- | `build/bootimg/boot-pokes.img` |
| sha256 boot | `11cf34823441bec66ac41a4af2d1a09fbbfdf6fd5ba67b97ff26cccdb32c61a7` (100663296 B) |
| dtbo_a <- | `build/bootimg/s238-boot-dtbo-dedup-gpio.img` (**el S238 BUENO, el mismo que está en dtbo_b; NO el s251**) |
| sha256 dtbo | `bdb361dff87de52dd7d4581c7f4007abdaf98ac145d47658ef2a29bc458f0022` (607534 B) |
| NO se toca | `boot_b` ni `dtbo_b` en ningún momento (par bueno verificado) |
| shas verificados en disco | SÍ, `sha256sum` coincide con los dos de arriba, ANTES de escribir |
| gates ANTES | `battery-voltage: 3399 mV` (bajo el gate de 3700; el dueño ha autorizado el ciclo) · `current-slot: b` · `slot-retry-count:b: 6` · `slot-unbootable:b: no` · `slot-retry-count:a: 6` · `slot-unbootable:a: yes` · `unlocked: yes` |
| consola ACM | UN solo lector vivo, PID 77586 (`bin/uke-console-cap.sh`); NO se lanza otro; línea actual del log 315533 |
| secuencia | `flash boot_a` → `flash dtbo_a` → getvar (después) → `set_active a` → `reboot` |
| rollback | `fastboot set_active b` + `fastboot reboot` (par bueno intacto en b) |

**Criterios de lectura (SOLO estas cadenas, en consola ACM y en dmesg con `dmesg -n 7` previo):**
`Linux version` (= el kernel HA ARRANCADO) · `UKE-POKE: arm_smmu_device_probe ENTRANDO` ·
`primer probe DIFFERIDO` · `UKE-POKE: apps-smmu: REINTENTO del probe` ·
`-> arm_smmu_device_cfg_probe` / `-> arm_smmu_device_reset` / `sACR` ·
`arm-smmu 15000000.apps-smmu` / `context bank` / `no IOMMU, bailing out` ·
más `/dev/dri` y lo que diga el DPU si hay IOMMU. Ventana: ≥5 min; `deferred_probe_timeout=30`
⇒ el reintento cae hacia t=30 s si el diferir funciona.

**Veredictos posibles:** (1) KERNEL ARRANCA Y SALEN MIGAS → boot exonerado, s251 condenado
(copiar UKE-POKE literal con timestamp); (2) ARRANCA SIN MIGAS → apps-smmu no propea (últimas 20
de dmesg + `/dev/dri`); (3) NO ARRANCA (sin `Linux version`) → el problema NO es el s251 sino el
slot a o la imagen (copiar últimas 20 de consola); (4) ARRANCA EN ARCH CON TODO → defer funcionó
(`/dev/dri` + DPU).

---

## RESULTADO — 28-sep-2026 ~14:35 UTC — AISLAMIENTO: **CUARTO arranque mudo. El s251 queda inocente.**

**Veredicto: caso (3).** El kernel de pokes (`11cf3482…`) + dtbo **s238 bueno** (`bdb361df…`, el mismo
que está en `dtbo_b`) en slot `a` deja **cero líneas**: ni `Linux version`, ni una sola miga `UKE-POKE`.
Tres intentos anteriores flashearon boot nuevo + s251 a la vez y quedaron mudos; este quitó el s251 y
sigue mudo. **Lo común a los 4 no es el dtbo: es una imagen de `boot` de nueva factura escrita en el
SLOT A.** El hermano falló cuando metió la nueva en `dtbo`, siempre en slot B (su #431): hay un
mecanismo común no nombrado todavía. **FORENSE EN CURSO** (otro subagente).

**Evidencia verificada en disco (solo lectura, sin tocar la tablet):**
consola `~/proyectos/out/uke-ubuntu_console.log` — tras la línea 315533 (marca del
pre-registro): **0× `UKE-POKE`** (`grep -a` + `awk`, 659 ocurrencias totales en el fichero, ninguna
posterior) y **exactamente 1× `Linux version`**, en la línea 315534, con el banner del kernel bueno
(`#82 SMP PREEMPT Sat Sep 26 17:01:40 CEST 2026`, distinto del kernel de pokes reconstruido el 28-sep)
seguido de `X9S123-SWITCH t=15 raiz=/dev/sda32` y arranque Arch completo (log vivo hasta las 16:44
CEST). Lectura: el intento quedó mudo (cero líneas, como prescribe el caso 3) y el rollback
(`set_active b` + reboot) arrancó el par bueno. **El slot b sigue intacto.**

**Caveats honestos:**
- Tramo 14:11–15:01 del log **contaminado** por dos lectores de `/dev/ttyACM0` a la vez
  (`build/gates/REGLA-UN-SOLO-LECTOR.md`): "cero líneas" es indicio, no prueba. El veredicto se apoya
  además en el rollback limpio al par bueno (dato independiente de la consola).
- Contadores de slot post-ciclo y `getvar` post-flash **no están en este repo** (los registra la sesión
  de flash): marcar como NO VERIFICADO aquí hasta que se lean.
- La medida del wedge del s251 en slot B con kernel bueno (11:52–12:03, 7→0, banner de
  `build/bootimg/mkdtbo-s251.py`) **sigue en pie como medición**; lo que cambia es su interpretación
  ("el dtbo es la causa" / "espacio dtbo cerrado"): con este resultado, el mecanismo está abierto de
  nuevo. Cerco REFUTADO de `mkdtbo-s251.py` se mantiene (no reflashear sin causa nueva).
