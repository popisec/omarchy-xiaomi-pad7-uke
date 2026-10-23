#!/bin/bash
# serpbar-tablet — la barra del portatil (uke.serpbar + plugins + ajustes + fondos) en la tablet uke (22-oct-2026).
# Uso: ./deploy.sh backup|pkgs|hyprmoncfg|apply|revert      (UKE_HOST=root@192.168.42.129 para ir por USB)
# Con turno: build/rootfs/deploy/turno/uke-turno pedir plugins-tablet "..."
#   backup     : tar de shell.json, plugins y estado de la shell de la tablet (en la tablet y una copia en el PC, ~/backups)
#   pkgs       : lo que usa serpbar y falta en la tablet (cava, ddcutil, matugen, wf-recorder, gpu-screen-recorder,
#                xdg-terminal-exec), de ALARM extra. Antes muestra `pacman -S --print`.
#   hyprmoncfg : paquete local hyprmoncfg-bin 1.24.0 aarch64 (binario oficial arm64) con makepkg en la tablet.
#   apply      : copia la barra del portatil (plugins, ~/.config/omarchy/serpbar, serpantinum, estado, fondos),
#                la adapta (adapt-serpbar.py), fusiona shell.json (merge-shell.py) y reinicia la shell.
#   revert     : restaura el ultimo backup (shell.json + plugins + estado) y reinicia la shell.
# No copia credenciales: ninguno de estos ficheros las lleva (comprobado: sin token/password/secret).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
HOST=${UKE_HOST:-root@uke}
KEY="$ROOT/build/rootfs/uke-arch-root"
SSH=(ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 "$HOST")
SCP=(scp -q -i "$KEY" -o BatchMode=yes)
H=/home/omarchy
BK=$H/.local/share/uke-plugins
ASO='aso() { U=$(id -u omarchy); cd /home/omarchy; setpriv --reuid=omarchy --regid=omarchy --init-groups env -i LANG=C.UTF-8 HOME=/home/omarchy USER=omarchy OMARCHY_PATH=/usr/share/omarchy PATH=/usr/local/bin:/usr/bin XDG_RUNTIME_DIR=/run/user/$U WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/$U/hypr | head -1) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$U/bus "$@"; }'
PKGS="cava ddcutil matugen wf-recorder xdg-terminal-exec"   # gpu-screen-recorder: 404 en ALARM (22-oct)

bundle() {   # HOME en miniatura con lo del portatil que va a la tablet
	B=$1; L=${PORTATIL_HOME:-$HOME}
	mkdir -p "$B/.config/omarchy/plugins" "$B/.config/omarchy/backgrounds" "$B/.local/state/omarchy"
	rsync -aL --exclude '*.bak' --exclude '*.pre-*' --exclude '.git' \
		"$L/.config/omarchy/plugins/uke.serpbar" "$L/.config/omarchy/plugins/crmne.hyprmoncfg" \
		"$L/.config/omarchy/plugins/radimsem.omafind" "$B/.config/omarchy/plugins/"
	rsync -a --exclude '*.bak' --exclude '*.pre-*' "$L/.config/omarchy/serpbar" "$B/.config/omarchy/"
	rsync -a "$L/.config/serpantinum" "$B/.config/"
	rsync -a "$L/.local/state/omarchy/serpbar" "$B/.local/state/omarchy/"
	rsync -a "$L/.local/state/serpantinum" "$B/.local/state/"
	rsync -a "$L/.config/omarchy/backgrounds/catppuccin" "$B/.config/omarchy/backgrounds/"
	rsync -aL "$L/Wallpapers/" "$B/Wallpapers/"
	grep -rIl "$HOME" "$B" | while read -r f; do
		sed -i 's#$HOME/.omarchy-home#/home/omarchy#g; s#$HOME#/home/omarchy#g' "$f"; done
	if grep -rIil -E '"(token|password|secret|apikey)"' "$B/.config/omarchy/serpbar" "$B/.config/serpantinum" "$B/.local/state"; then
		echo "hay algo con pinta de credencial: no sigo" >&2; exit 1; fi
	python3 -I "$HERE/adapt-serpbar.py" "$B"
}

case "${1:-}" in
backup)
	TS=$(date +%Y%m%d-%H%M%S)
	"${SSH[@]}" "set -e; mkdir -p $BK; cd $H; tar --ignore-failed-read -czf $BK/barra-$TS.tar.gz \
		.config/omarchy/shell.json .config/omarchy/plugins .config/omarchy/serpbar .config/serpantinum \
		.local/state/omarchy/serpbar .local/state/serpantinum .local/state/omarchy/current 2>/dev/null; \
		chown omarchy:omarchy $BK/barra-$TS.tar.gz; ls -la $BK/barra-$TS.tar.gz; sha256sum $BK/barra-$TS.tar.gz"
	mkdir -p "$HOME/backups/uke-barra-$TS"
	"${SCP[@]}" "$HOST:$BK/barra-$TS.tar.gz" "$HOME/backups/uke-barra-$TS/"
	sha256sum "$HOME/backups/uke-barra-$TS/barra-$TS.tar.gz" ;;
pkgs)
	"${SSH[@]}" "pacman -S --print --needed $PKGS && pacman -S --needed --noconfirm $PKGS | tail -2 && pacman -Q $PKGS" ;;
hyprmoncfg)
	"${SCP[@]}" "$HERE/hyprmoncfg-bin/PKGBUILD" "$HOST:/tmp/hyprmoncfg-PKGBUILD"
	"${SSH[@]}" "set -e; D=/tmp/hyprmoncfg-build; rm -rf \$D; mkdir \$D; mv /tmp/hyprmoncfg-PKGBUILD \$D/PKGBUILD; chown -R omarchy:omarchy \$D
		cd \$D; setpriv --reuid=omarchy --regid=omarchy --init-groups env HOME=/home/omarchy makepkg -f --nodeps 2>&1 | tail -3
		pacman -U --noconfirm \$D/hyprmoncfg-bin-1.24.0-1-aarch64.pkg.tar.* | tail -1; pacman -Q hyprmoncfg-bin; file /usr/bin/hyprmoncfg | cut -c1-90; rm -rf \$D" ;;
apply)
	T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
	bundle "$T/home"
	"${SCP[@]}" "$HOST:$H/.config/omarchy/shell.json" "$T/tablet-shell.json"
	python3 -I "$HERE/merge-shell.py" "$T/tablet-shell.json" "${PORTATIL_HOME:-$HOME}/.config/omarchy/shell.json" "$T/home/.config/omarchy/shell.json"
	# Mismo fondo que el portatil (la imagen va en backgrounds/catppuccin)
	BG=$(basename "$(readlink -f "${PORTATIL_HOME:-$HOME}/.local/state/omarchy/current/background")")
	BGSET="ln -sfn $H/.config/omarchy/backgrounds/catppuccin/$BG $H/.local/state/omarchy/current/background && chown -h omarchy:omarchy $H/.local/state/omarchy/current/background"
	tar -C "$T/home" --owner=0 --group=0 -cf - . | "${SSH[@]}" "set -e; $ASO
		rm -rf /tmp/uke-barra.new; mkdir /tmp/uke-barra.new; tar -C /tmp/uke-barra.new -xf -
		cd /tmp/uke-barra.new
		for p in uke.serpbar crmne.hyprmoncfg radimsem.omafind; do rm -rf $H/.config/omarchy/plugins/\$p; done
		cp -a . $H/; chown -R omarchy:omarchy $H/.config/omarchy $H/.config/serpantinum $H/.local/state/omarchy $H/.local/state/serpantinum $H/Wallpapers
		cd /; rm -rf /tmp/uke-barra.new
		[ -f $H/.config/omarchy/backgrounds/catppuccin/$BG ] && $BGSET
		aso omarchy restart shell >/dev/null 2>&1 || true; echo 'barra del portatil aplicada'" ;;
omafind)
	# Motor de omafind: llama.cpp compilado en la tablet (su build-runtime.sh, sin tocar; sin driver Vulkan en la
	# tablet llama-server se queda en CPU) y el modelo EmbeddingGemma 2 copiado del portatil (GGUF, no depende de la
	# arquitectura; omafind lo verifica). La compilacion va desprendida y con nice: log en /tmp/omafind-build.log.
	"${SSH[@]}" "pacman -S --print --needed vulkan-headers uv && pacman -S --needed --noconfirm vulkan-headers uv | tail -1"
	"${SSH[@]}" "install -d -o omarchy -g omarchy -m 700 $H/.local/share/omafind $H/.local/share/omafind/model"
	for m in embeddinggemma-2-Q8_0.gguf mmproj-embeddinggemma-2-Q8_0.gguf; do
		"${SCP[@]}" "${PORTATIL_HOME:-$HOME}/.local/share/omafind/model/$m" "$HOST:$H/.local/share/omafind/model/$m"; done
	"${SSH[@]}" "set -e; $ASO; chown -R omarchy:omarchy $H/.local/share/omafind
		O=$H/.config/omarchy/plugins/radimsem.omafind/bin/omafind
		aso \$O setup 2>&1 | tail -5
		setsid nohup setpriv --reuid=omarchy --regid=omarchy --init-groups env HOME=$H XDG_RUNTIME_DIR=/run/user/\$(id -u omarchy) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u omarchy)/bus PATH=/usr/bin OMAFIND_BUILD_MEMORY_MAX=3G nice -n 19 \$O build-runtime > /tmp/omafind-build.log 2>&1 < /dev/null &
		echo 'compilando llama-server en segundo plano: /tmp/omafind-build.log'" ;;
omafind-roots)
	# Carpetas de la tablet con el UUID de volumen que da omafind discover (el del portatil no vale aqui)
	"${SSH[@]}" "set -e; $ASO; O=$H/.config/omarchy/plugins/radimsem.omafind/bin/omafind
		V=\$(aso \$O discover --json | jq -r '.roots[] | select(.path==\"$H\") | .volume' | head -1); echo \"volumen: \$V\"; [ -n \"\$V\" ]
		F=$H/.config/omarchy/shell.json
		jq --arg v \"\$V\" '(.plugins[] | select(.id==\"radimsem.omafind\") | .roots[].volume) = \$v' \$F > /tmp/uke-sj.new
		setpriv --reuid=omarchy --regid=omarchy --init-groups cp /tmp/uke-sj.new \$F; rm -f /tmp/uke-sj.new
		jq -c '.plugins[] | select(.id==\"radimsem.omafind\") | .roots' \$F" ;;
bundle) bundle "${2:?DIR}"; du -sh "$2" ;;   # solo en el PC, para revisar lo que se copiaria
revert)
	"${SSH[@]}" "set -e; $ASO; F=\$(ls -t $BK/barra-*.tar.gz | head -1); echo \"restaurando \$F\"
		for p in uke.serpbar crmne.hyprmoncfg radimsem.omafind; do rm -rf $H/.config/omarchy/plugins/\$p; done
		tar -C $H -xzf \$F; chown -R omarchy:omarchy $H/.config/omarchy
		aso omarchy restart shell >/dev/null 2>&1 || true; echo revertido" ;;
*) sed -n 2,13p "$0"; exit 1 ;;
esac
