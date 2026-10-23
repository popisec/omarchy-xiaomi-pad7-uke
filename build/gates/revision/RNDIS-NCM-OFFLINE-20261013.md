# Revisión offline NCM/RNDIS (13-oct-2026) — por qué puede haber userspace sin SSH

100 % offline. Sin tablet, sin fastboot/adb, sin compilar, sin commit.
Método: lectura del fuente + extracción del initramfs HORNEADO en los boot.img
(`CONFIG_INITRAMFS_SOURCE`, builtin en el kernel) + `debugfs` sobre el rootfs.

## 1. Definición del gadget: qué se configura, dónde, en qué orden

Hay DOS líneas de gadget en el repo. **Solo una ha sido flasheada jamás.**

### 1.1 Línea fork = la que corre (todos los boots L, `rdinit=/ukeinit`)

Fuente: `build/gates/ukeinit`:

| # | Qué | Línea |
|---|---|---|
| IDs | `0x1d6b` / `0x0104`, serial `UKE-S120`, `Xiaomi Pad 7 Linux`, **`UKE fork shell`** | 137–142 |
| Función serie | `mkdir $G/functions/acm.usb0` | 143 |
| Función red | **`mkdir $G/functions/ncm.usb0`** (solo NCM; **no rndis, no ecm**) | 147–149 |
| Symlinks a `configs/c.1/` | primero `ncm.usb0`, después `acm.usb0` | 149–150 |
| `max_speed=high-speed` | antes del bind | 151 |
| **Bind UDC LO ÚLTIMO** (+ reintento 60×2 s) | `echo $UDC > $G/UDC`, rc en kmsg `X9USB-BIND-ok/mal` | 152–169 |
| IP tablet | `ifconfig $IFACE 192.168.42.129/24 up` + `telnetd -l /bin/sh -p 23` | 299–305 |

**Sin MAC fijada**: ningún `dev_addr`/`host_addr` en todo el fichero
(verificado por grep; igual en los initramfs horneados). Cada boot = MAC
aleatoria del kernel.

### 1.2 Línea Arch = nunca flasheada (`rdinit=/ukeinit-arch`)

`build/init/gadget-setup-arch.sh:21-34` (`acm.GS0` + `rndis.usb0`, fallback
`ecm.usb0`, IDs `18d1:d002`); bind en `build/init/ukeinit-arch:182`;
IP en `ukeinit-arch:200-214`. Todos los repacks usan `rdinit=/ukeinit`
(cmdline L19 verificada por `unpack_bootimg`, §3). **Consecuencia:
`INFORME-A2.md:79-80` («`rndis/ecm.usb0`») describe lo NO desplegado**;
lo desplegado es ACM+NCM del fork. (No edito A2 por encargo; queda
anotado aquí como corrección pendiente.)

### 1.3 Prueba de que L19 y L33 llevan el mismo código S119

Initramfs extraído del kernel horneado (gzip interno del `Image`):

| Par | Initramfs en `Image` | cpio | `/ukeinit` md5 |
|---|---|---|---|
| L19 (`boot-uke-k52L19.img`) | `@0x21d3278` | 2 099 712 B | `c3a52169…` |
| L33 (`boot-uke-k52L33.img`) | `@0x21d2f78` | 2 108 928 B | `72fcd5ca…` |

`diff` L19↔L33 = **24 líneas, un solo hunk** (bloque `UKE-DIAG`, tras
línea 238; cosmético para red). Gadget (L19:147-149, L33:147-149) e IP
(L19:269-271, L33:292-294) **idénticos**. Ambos sin MAC.

Kernel: `CONFIG_USB_F_NCM=y` + `CONFIG_USB_CONFIGFS_NCM=y`
(`build/kernel-config/k52L1-bateria.config:6283,6295`; mismo bloque en
todas las `k52L*`). Nota de roles: la tablet usa `usb_f_ncm` (gadget);
`cdc_ncm`/`cdc_acm` son los drivers del **PC** (el journal del 13-oct los
muestra cargando: el lado PC está cubierto).

## 2. Por qué puede no subir la red aunque el gadget enumere

Ordenadas por probabilidad offline:

1. **`IFACE` equivocado (candidata nº 1).**
   `IFACE=$(ls /sys/class/net | grep -vE "lo|sit0" | head -1)`
   (`build/gates/ukeinit:299`; L19:269, L33:292) coge la primera interfaz
   por orden de readdir, **no `usb0`**. Si el kernel expone otra
   (`wlan0`/ath11k, `dummy0`, …), la `.129` va a la interfaz equivocada y
   `usb0` queda sin IP. El kmsg `S119 NET-OK: $IFACE=…` **miente en ese
   caso** (solo dice que `ifconfig` no falló). Indistinguible desde el PC
   de «no hay red».
2. **PC sin `192.168.42.1/24` (candidata nº 2).**
   Sin MAC fijada (§1.1), cada boot presenta MAC nueva; el perfil NM atado
   a MAC no reaplica y NM intenta DHCP (sin servidor) en `enp0s20f0u3`.
   Resultado: `cdc_ncm` enumera, la interfaz existe, pero sin IP en el PC
   no hay SSH aunque la tablet esté perfecta.
3. **Dependencia total de `systemd-networkd` tras el switch.**
   El propio `10-uke-usb.network` documenta que networkd «reinicia la
   interfaz» (la IP del initramfs no sobrevive al switch_root). El rootfs
   desplegado (`rootfs-uke-k521.img`, verificado por `debugfs`) trae el
   fix: `etc/systemd/network/10-uke-usb.network` (`Match usb0/enx*/rndis*`,
   `Address=192.168.42.129/24`) + `systemd-networkd.service` habilitado +
   `sshd` + `uke-fix.service`/`uke-diag.service`. Si networkd está caído o
   enmascarado (precedente 1-oct: journald enmascarado tumbó sshd), no hay
   red. Doble-`.129` (init en `wlan0` + networkd en `usb0`) = ARP flux.
4. **Etiqueta «RNDIS» errónea.**
   `docs/historia/ESTADO-VIVO.md:113-130` dice «el gadget RNDIS no enumera». Ningún boot
   L usa RNDIS: buscar `rndis_host` en el PC es el test equivocado; lo
   correcto es `cdc_ncm` + `enp0s20f0u3`. Y hay **prueba de SSH con L33+s283
   el mismo 13-oct**: `out/diag-L33/BASE-pre-sddm.txt:2496-2508,2584-2600`
   y `dmesg.{1,3,4}.txt` muestran `sshd-session … hostname=192.168.42.1`
   a t=24/33/37/175/186 s. El «bloqueo» como imposibilidad general queda
   **refutado por evidencia propia**; lo que hay son boots concretos sin
   red (causas 1–3) más el #613 nocturno (silencio USB total, ya clasificado
   INCONCLUYENTE por batería 3321 mV < gate 3700).
5. **No-carreras (descartadas).** Bind UDC lo último (fix B3a) = correcto;
   el netdev `usb0` lo crea el bind, la IP va después; IP estática no
   necesita carrier. Nada que arreglar aquí.

## 3. Checklist operativo para el próximo arranque de L19

### (a) Lado tablet, por consola ACM (escribir a `ttyGS0`; el getty evalúa línea a línea)

En initramfs (antes del switch):
```
cat /sys/kernel/config/usb_gadget/g1/UDC
ls /sys/kernel/config/usb_gadget/g1/functions /sys/kernel/config/usb_gadget/g1/configs/c.1
ls /sys/class/net
busybox ifconfig -a          # ¿qué interfaz tiene 192.168.42.129?
busybox dmesg | busybox grep -E 'S119|BIND|ncm|UDC'
```
Tras el switch (systemd):
```
ip -br addr; networkctl status usb0; systemctl is-active systemd-networkd sshd
journalctl -u systemd-networkd -n 20 --no-pager
dmesg | grep -i -E 'ncm|gadget|udc'
```

### (b) Lado PC

```
ip -br link; ip -br addr show enp0s20f0u3
dmesg | grep -E 'cdc_ncm|cdc_acm|1d6b:0104'
nmcli device status; nmcli connection show
```
Si falta la `.1` (caso esperado por causa 2):
```
sudo ip addr add 192.168.42.1/24 dev enp0s20f0u3 && sudo ip link set enp0s20f0u3 up
ping -c3 192.168.42.129
ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=8 root@192.168.42.129
```
Histórico: tablet `.129` ↔ PC `.1`, puerto del PC `enp0s20f0u3`
(`NOTAS-OMARCHY.md:4350`; SSH 25-sep `out/acm-s285.log:11134`,
27-sep `NOTAS-OMARCHY.md:409-411` ping 3/3). Para persistente: perfil NM
atado al **nombre** `enp0s20f0u3`, nunca a MAC (cambia por boot, §1.1).

### (c) Criterio pasa/falla y dato a guardar

- **PASA** = `ping` OK + SSH OK → peldaño 0 desbloqueado → correr
  `charge/lee-forklog.sh` (lee `/dev/sda30`).
- **FALLA con ACM vivo** = guardar: volcado `X9DUMP`, `ip -br addr` de
  ambos lados, líneas kmsg `S119`/`BIND`, `ls functions/`, `networkctl status`.
  Con eso se distingue causa 1 (IP en interfaz ajena) de causa 2 (PC sin `.1`)
  de causa 3 (networkd caído).
- **FALLA sin ACM ni USB** = INCONCLUYENTE si batería < 3700 mV (regla
  adoptada `docs/historia/ESTADO-VIVO.md:127-130`); no es evidencia contra la red.

## 4. Veredicto sobre el fallo del 13-oct

Sin un único culpable demostrable offline, pero acotado con evidencia:
el gadget L33+s283 **sí** dio SSH ese día (diag-L33, §2.4), así que el par
red/tablet funciona; el «sin SSH aun habiendo userspace» apunta a
**IP en interfaz equivocada (`head -1`, causa 1) y/o PC sin `.1` estática
(causa 2)**, ambas comprobables en 2 minutos con §3. El #613 (silencio USB)
no es fallo de red: INCONCLUYENTE por batería. Recomendación: en el
próximo ciclo, ejecutar §3 antes de cualquier flash; si la causa 1 se
confirma por ACM, el fix es un cambio de una línea en `ukeinit:299`
(`IFACE=usb0` explícito con fallback), horneado en el siguiente kernel.
