#!/bin/bash
# SUPERADO 22-oct-2026 ~20:35 por el plugin uke.navidrome (deploy.sh navidrome-fork), que no necesita este parche: en la tablet
# el parche está REVERTIDO. Se conserva solo como referencia del parche local del portátil.
# omarchy-parche-servicefor.sh — reaplica en la uke el parche local del portátil (22-oct-2026):
# un widget alojado por una barra de terceros (powerbar) recibe de Omarchy la fachada pluginShellForBarEntry, que no trae
# _serviceLookup ⇒ serviceFor(<su propio id>) devuelve null y Navidrome se queda en el login. El parche añade un
# _serviceLookup limitado al propio id del widget (ningún otro servicio es accesible). Idéntico al del portátil
# (~/.local/share/omarchy/shell/shell.qml, «LOCAL PATCH (usuario)»). Hay que reaplicarlo tras cada actualización de omarchy.
#   apply | status | revert      (después: omarchy restart shell)
set -u
R=$(cd "$(dirname "$0")/../../../.." && pwd)
S() { ssh -i "$R/build/rootfs/uke-arch-root" -o BatchMode=yes -o ConnectTimeout=8 "${UKE_HOST:-root@uke}" "$@"; }
F=/usr/share/omarchy/shell/shell.qml
case "${1:-status}" in
apply)
	S "python3 -I - '$F'" <<'PY'
import sys, shutil, os
p = sys.argv[1]; s = open(p).read()
if "LOCAL PATCH (usuario)" in s:
    print("ya aplicado"); sys.exit(0)
i = s.index("function pluginShellForBarEntry(ownerId, moduleName)")
anchor = "      barConfig: shell.publicBarConfig(),\n"
j = s.index(anchor, i) + len(anchor)
add = """      // LOCAL PATCH (usuario): a widget hosted by a third-party bar gets this
      // entry facade instead of pluginShellForId(), so without this its own
      // `serviceFor(<its id>)` returns null and every bar-widget+service plugin
      // (Navidrome) draws its login form and does nothing under Powerbar.
      // Scoped to the widget's own id: no other plugin's service is reachable,
      // so the reason omarchy narrowed this facade (a bar traversing to
      // another plugin's service) still holds. Re-apply after omarchy update.
      _serviceLookup: function(requestedId) {
        return owns(requestedId)
          ? shell.serviceFor(shell.pluginRegistry.resolveEnabledId(target)) : null
      },
"""
bak = p + ".pre-servicefor"
if not os.path.exists(bak): shutil.copy2(p, bak)
open(p, "w").write(s[:j] + add + s[j:])
print("aplicado (copia en %s)" % bak)
PY
	S "sync -f $F; grep -c 'LOCAL PATCH (usuario)' $F"
	echo "falta: omarchy restart shell (como omarchy)" ;;
status) S "grep -c 'LOCAL PATCH (usuario)' $F; pacman -Q omarchy; pacman -Qkk omarchy 2>/dev/null | grep shell.qml" ;;
revert) S "[ -f $F.pre-servicefor ] && cp -a $F.pre-servicefor $F && sync -f $F && echo revertido" ;;
esac
