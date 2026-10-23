# Tailscale en la tablet (20-oct-2026)

Motivo: el router (RED-EJEMPLO-1) tiene **aislamiento de clientes WiFi**: PC y tablet en el mismo AP (02:00:5e:00:00:18,
5500 MHz) no se ven (ARP INCOMPLETE desde el PC; ping de la tablet al PC sin respuesta; ambos llegan al router).
- `tailscale 1.104.1-1` (ALARM extra, solo depende de glibc) por `pacman -U` con .sig; `systemctl enable --now tailscaled`.
- El kernel no tiene netfilter (ni iptables ni nftables) → `tailscaled` moría en `router.Up`. Arreglo: `/etc/default/tailscaled`
  con `FLAGS="--tun=userspace-networking"` (sin tun ni cortafuegos; las conexiones entrantes llegan a sshd igual).
- `tailscale up --hostname=uke --accept-dns=false`; el dueño aprobó el dispositivo en su cuenta.
- Nodo: **uke = 100.64.0.10**. Huella ED25519 del host comprobada igual que por USB (SHA256:y7xJpXRg…/hPU).
Acceso: `ssh -i build/rootfs/uke-arch-root -o BatchMode=yes root@uke` (o `root@100.64.0.10`). USB (192.168.42.129) sigue valiendo.
Ojo: en modo userspace la tablet no tiene interfaz tailscale0; para salir HACIA la tailnet desde la tablet haría falta proxy SOCKS.

## 21-oct-2026 — prueba de modo TUN: FALLÓ (revertida)
Probado por USB con reversión automática: `tailscale set --netfilter-mode=off`, `FLAGS=""` en `/etc/default/tailscaled`, reinicio. Resultado: no se crea `tailscale0`; `tailscaled` entra en bucle de reinicios (`linuxfw: clear iptables: could not get iptables version`, `router: failed to look up link "tailscale0"`). Revertido a `--tun=userspace-networking` y `--netfilter-mode=on` (estado verificado: `active`, nodos visibles, SSH por Tailscale y USB). Consecuencia: las apps de la tablet no alcanzan IPs 100.x (Navidrome/Jellyfin/Kavita en PC-PORTATIL, Nextcloud en SERVIDOR-01:9454). Alternativa sin probar: `--socks5-server=localhost:1055` (o `--outbound-http-proxy-listen`) + reenvíos locales o proxy por app. Detalle en `build/gates/revision/APPS-TABLET-20261021.md`.

## 22-oct-2026 — proxy de salida a la tailnet: HECHO (autorizado por el dueño)
`/etc/default/tailscaled` (copia previa en la tablet: `/root/tailscaled.default.bak-20261022`):
```
FLAGS="--tun=userspace-networking --outbound-http-proxy-listen=localhost:1055 --socks5-server=localhost:1055"
```
Un mismo puerto sirve **HTTP (CONNECT) y SOCKS5** (tailscaled los multiplexa); escucha solo en `127.0.0.1:1055`.
Aplicado por USB con reversión automática y turno; tras `systemctl restart tailscaled` vuelve el SSH por Tailscale.
Medido desde la tablet (22-oct, ~03 h): `https://SERVIDORhost.tailnet-ejemplo.ts.net:9454/status.php` → 200 (0,17 s por HTTP, 0,12 s por
SOCKS); `http://PC-PORTATIL:4533/` → 302 (Navidrome); también vale `PC-PORTATIL.tailnet-ejemplo.ts.net` y la IP 100.64.0.12 (MagicDNS lo
resuelve el propio proxy aunque la tablet tenga `--accept-dns=false`). Internet sin proxy sigue igual (archlinux.org 200).
`PC-PORTATIL:8096` y `:5000` dieron 502 porque no existen. Según la sesión resto-apps, Jellyfin está en `https://SERVIDORhost.tailnet-ejemplo.ts.net:9444` y Kavita en `:9455` (tras Authelia).

### Cómo usarlo en una app
- **Por variables** (curl, Python urllib/requests, Go, la mayoría de CLIs y Qt con `QNetworkProxyFactory::setUseSystemConfiguration`):
  ```
  export http_proxy=http://127.0.0.1:1055 https_proxy=http://127.0.0.1:1055
  export HTTP_PROXY=$http_proxy HTTPS_PROXY=$https_proxy
  export ALL_PROXY=socks5h://127.0.0.1:1055          # para lo que solo entiende SOCKS (usar socks5h: DNS en el proxy)
  export NO_PROXY=localhost,127.0.0.1,::1,192.0.2.0/16,.local   no_proxy=$NO_PROXY
  ```
  Ojo: el proxy **también saca a internet** (tailscaled hace de salida normal para lo que no es tailnet), así que no rompe nada
  ponerlo global, pero es más lento y conviene `NO_PROXY` para lo local. Formato de `NO_PROXY` con CIDR: curl ≥ 7.86 y Python
  lo entienden; algunas apps no.
- **Por app**: `curl -x http://127.0.0.1:1055 …`, `chromium --proxy-server=socks5://127.0.0.1:1055`, Nextcloud desktop →
  Ajustes → Red → proxy HTTP 127.0.0.1:1055. En una unidad systemd: `Environment=https_proxy=http://127.0.0.1:1055`.
- **Para toda la sesión gráfica** del usuario `omarchy`: `~/.config/environment.d/50-tailnet-proxy.conf` con las mismas
  líneas (sin `export`); aplica a lo que se lance tras volver a entrar. No está puesto: cada sesión decide por app.
- Revertir: `cp /root/tailscaled.default.bak-20261022 /etc/default/tailscaled && systemctl restart tailscaled` (con USB abierto).
