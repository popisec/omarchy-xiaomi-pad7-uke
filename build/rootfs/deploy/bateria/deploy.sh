#!/bin/bash
# deploy.sh — bateria exacta + perfiles + log (19-oct-2026).  check | apply | revert | status | informe
# apply: copia ficheros, habilita uke-perfil.service y uke-bateria-log.service (los arranca), instala el widget
#        uke.bateria en ~omarchy/.config/omarchy/plugins/ y la linea de autostart de Hyprland. NO toca /usr/share/omarchy.
#        Activar el widget en la barra: omarchy plugin enable uke.bateria  (o arrastrar desde Preferencias de powerbar).
# revert: deshabilita servicios, borra ficheros y autostart. Conserva /var/log/uke-bateria y /var/lib/uke-bateria.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}; HOST=${UKE_HOST:-root@uke}
S() { timeout "${T:-60}" ssh -i "$KEY" -o BatchMode=yes "$HOST" "$@"; }
PL=/home/omarchy/.config/omarchy/plugins/uke.bateria
AS=/home/omarchy/.config/hypr/autostart.lua
BINS="uke-perfil uke-bateria-lectura uke-bateria-log uke-bateria-informe powerprofilesctl uke-icl uke-idle-guard uke-modo-carga uke-apagar uke-refresco"
case "${1:-}" in
check) for f in uke-perfil powerprofilesctl uke-icl uke-idle-guard uke-refresco; do bash -n "$HERE/root/usr/local/bin/$f" || exit 1; done
	for f in uke-bateria-lectura uke-bateria-log uke-bateria-informe; do python3 -m py_compile "$HERE/root/usr/local/bin/$f" || exit 1; done
	rm -rf "$HERE"/root/usr/local/bin/__pycache__; visudo -cf "$HERE/root/etc/sudoers.d/uke-perfil" >/dev/null 2>&1 || echo "(aviso: visudo no disponible en el PC, se valida en la tablet)"
	echo "CHECK OK" ;;
apply) bash "$0" check || exit 1
	tar -C "$HERE/root" --owner=0 --group=0 --numeric-owner -cf - . | S "tar -x -C / && chmod 755 /usr/local/bin/{uke-perfil,uke-bateria-lectura,uke-bateria-log,uke-bateria-informe,powerprofilesctl,uke-icl,uke-idle-guard,uke-modo-carga,uke-apagar,uke-refresco} && chmod 755 /etc/NetworkManager/dispatcher.d/90-uke-wifi-ps /usr/lib/systemd/system-sleep/uke-susp-log && chmod 440 /etc/sudoers.d/uke-perfil && visudo -cf /etc/sudoers.d/uke-perfil && mkdir -p /var/lib/uke-bateria /var/log/uke-bateria"
	tar -C "$HERE/plugin" --owner=1001 --group=1001 --numeric-owner -cf - uke.bateria | S "tar -x -C /home/omarchy/.config/omarchy/plugins/"
	S "grep -q 'uke-bateria' $AS || printf '%s\n' '-- >>> uke-bateria (19-oct-2026): reaplica refresco/tope de brillo del perfil. Revertir con bateria/deploy.sh revert.' 'o.launch_on_start(\"/usr/local/bin/uke-perfil apply-user\")' '-- <<< uke-bateria' >> $AS
		udevadm control --reload; systemctl daemon-reload && systemctl enable --now uke-perfil.service uke-bateria-log.service uke-idle-guard.service; systemctl enable uke-modo-carga.service uke-modo-carga-boton.service && sync"
	echo "listo. Widget: omarchy plugin enable uke.bateria (como omarchy) y colocarlo en la barra." ;;
revert) S "systemctl disable --now uke-idle-guard.service uke-bateria-log.service uke-perfil.service 2>/dev/null; systemctl disable uke-modo-carga.service uke-modo-carga-boton.service 2>/dev/null
	sed -i '/>>> uke-bateria/,/<<< uke-bateria/d' $AS
	[ -r /etc/uke/hypridle-normal.conf ] && cp /etc/uke/hypridle-normal.conf /home/omarchy/.config/hypr/hypridle.conf && chown omarchy:omarchy /home/omarchy/.config/hypr/hypridle.conf; iw dev wlan0 set power_save off 2>/dev/null
	rm -rf $PL; cd /usr/local/bin && rm -f $BINS; rm -f /etc/systemd/system/uke-perfil.service /etc/systemd/system/uke-bateria-log.service /etc/systemd/system/uke-idle-guard.service /etc/systemd/system/uke-modo-carga.service /etc/systemd/system/uke-modo-carga-boton.service /etc/uke/modo-carga.conf /etc/uke/hypridle-ahorro.conf /etc/uke/hypridle-normal.conf /etc/systemd/system/sddm.service.d/uke-modo-carga.conf /etc/sudoers.d/uke-perfil /etc/uke/perfiles.conf /etc/udev/rules.d/90-uke-icl.rules /etc/NetworkManager/dispatcher.d/90-uke-wifi-ps /usr/lib/systemd/system-sleep/uke-susp-log
	for p in /sys/devices/system/cpu/cpufreq/policy*; do cat \$p/cpuinfo_max_freq > \$p/scaling_max_freq; echo performance > \$p/scaling_governor; done
	systemctl daemon-reload; sync; echo revertido (governor performance y max originales)" ;;
status) S "uke-perfil status; systemctl is-active uke-perfil uke-bateria-log; ls -la /var/log/uke-bateria | tail -5; uke-bateria-lectura --short" ;;
informe) S "uke-bateria-informe ${2:-7}" ;;
*) echo "uso: $0 check|apply|revert|status|informe [dias]"; exit 2 ;;
esac
