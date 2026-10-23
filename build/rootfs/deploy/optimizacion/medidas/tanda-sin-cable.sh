#!/bin/bash
# tanda-sin-cable.sh check|run [fases]|restaura — SE EJECUTA EN EL PC, por Tailscale (la SSH sigue viva sin cable). 22-oct-2026.
# Junta en UNA desconexion del dueño las medidas de bateria que necesitan la tablet sin cable:
#   refresco  B1: al desenchufar, uke-refresco (regla udev) debe pasar a 60 Hz en <15 s
#   perfiles  ahorro/equilibrado/rendimiento x {pantalla en reposo, pantalla + carga fija, DPMS off} (brillo fijo 20 %)
#   wifi      power_save off/on con DPMS off
#   tactil    uke-touchd corriendo / parado (SIGSTOP) con pantalla encendida
#   mic       A/B del micro siempre abierto (delegado en medir-mic-ab.sh run 150)
#   s2idle    30 min suspendida con alarma RTC (delegado en medir-s2idle.sh arm 1800) + comprobar-reanudacion.sh
# Gates: turno (UKE_TURNO=1), Discharging >= 40 %. El DUEÑO desenchufa cuando el script lo pide y no toca la pantalla hasta el final de «tactil».
# Escribe en la tablet: perfil (se restaura), brillo (se restaura), DPMS, iw power_save (se restaura el del perfil), SIGSTOP/SIGCONT del tactil,
# unidades transitorias uke-tanda-inhibe (inhibidor de reposo) y uke-tanda-carga (carga fija). Todo se deshace en el trap EXIT o con `restaura`.
# Salida: build/logs/tanda-sin-cable-<fecha>.csv  (fase,seg,uah0,uah1,w_gauge,w_corriente,v,pct_h,cpu_pct,estado,n)
set -u; . "$(dirname "$0")/lib.sh"
D=$(cd "$(dirname "$0")" && pwd); FASES=${2:-"refresco perfiles wifi tactil mic s2idle"}
ON=${TANDA_ON:-180}; OFF=${TANDA_OFF:-240}; BL_PCT=${TANDA_BL:-20}
H='setpriv --reuid=1001 --regid=1001 --init-groups env XDG_RUNTIME_DIR=/run/user/1001 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1001/hypr | head -1) hyprctl'
dpms() { S "$H dispatch 'hl.dsp.dpms({ action = \"$1\" })' >/dev/null 2>&1"; }
brillo() { S "m=\$(cat /sys/class/backlight/uke-backlight/max_brightness); echo \$((m * $1 / 100)) > /sys/class/backlight/uke-backlight/brightness"; }
muestra() { T=$(( $1 + 90 )) S "python3 - $1 $2 ${3:-20}" < "$D/tablet/uke-tanda-muestra.py" | tee -a "$OUT"; }
# carga fija: cada 50 ms, K x sha256 de 1 MiB (K=12: 22-oct en la tablet sha256 1 MiB = 0,99 ms en un nucleo medio a 1,4 GHz (tope Ahorro), 1,46 ms en uno pequeno => ~25 % de un nucleo en Ahorro); cuenta los ticks que no caben (saturacion)
CARGA='import hashlib,time
b=b"x"*(1<<20); K=int(__import__("sys").argv[1]); p=0.05; t=time.monotonic(); n=over=0
while True:
    for _ in range(K): hashlib.sha256(b).digest()
    n+=1; t+=p; d=t-time.monotonic()
    if d>0: time.sleep(d)
    else: over+=1; t=time.monotonic()
    if n%100==0: open("/run/uke-tanda-carga.txt","w").write(f"{n} {over}\n")'
restaura() {
  S "systemctl stop uke-tanda-carga uke-tanda-inhibe 2>/dev/null; systemctl kill -s CONT uke-touch.service 2>/dev/null
     p=\$(cat /run/uke-tanda.perfil 2>/dev/null); [ -n \"\$p\" ] && uke-perfil set \"\$p\" >/dev/null 2>&1
     b=\$(cat /run/uke-tanda.brillo 2>/dev/null); [ -n \"\$b\" ] && echo \$b > /sys/class/backlight/uke-backlight/brightness
     echo \"restaurado: perfil=\$(cat /var/lib/uke-bateria/perfil) brillo=\$(cat /sys/class/backlight/uke-backlight/brightness) wifi_ps=\$(iw dev wlan0 get power_save | cut -d: -f2) touchd=\$(ps -o stat= -p \$(pgrep -f "[u]ke-touchd" | head -1))\""
  dpms on
}
case "${1:-}" in
check) bash -n "$0" && python3 -m py_compile "$D/tablet/uke-tanda-muestra.py" && bash -n "$D/comprobar-reanudacion.sh" && echo "CHECK OK"; rm -rf "$D/tablet/__pycache__";;
restaura) restaura;;
run) gate_turno
  OUT=$R/build/logs/tanda-sin-cable-$(date +%Y%m%d-%H%M%S).csv; mkdir -p "$R/build/logs"
  echo "fase,seg,uah0,uah1,w_gauge,w_corriente,v,pct_h,cpu_pct,estado,n" > "$OUT"
  S "cat /var/lib/uke-bateria/perfil > /run/uke-tanda.perfil; cat /sys/class/backlight/uke-backlight/brightness > /run/uke-tanda.brillo" || die "tablet inalcanzable"
  trap 'restaura; echo "CSV: $OUT"' EXIT
  # inhibidor de reposo (hypridle respeta los inhibidores de systemd: ignore_systemd_inhibit = false) durante las fases con pantalla
  S "systemctl stop uke-tanda-inhibe 2>/dev/null; systemd-run --unit=uke-tanda-inhibe --collect systemd-inhibit --what=idle --who=uke-tanda --why=medida-bateria sleep 7200 >/dev/null"
  if [ "$(bat_status)" != Discharging ]; then
    echo ">>> DESENCHUFA la tablet ahora (espero hasta 10 min)"; for _ in $(seq 120); do [ "$(bat_status)" = Discharging ] && break; sleep 5; done
  fi
  gate_bateria 40 Discharging
  for F in $FASES; do case $F in
  refresco) hz=""; for _ in 1 2 3; do sleep 5; hz=$(S "$H monitors -j | jq -r '.[0].refreshRate|floor'"); [ "$hz" = 60 ] && break; done
    echo "refresco,0,,,,,,,,hz=$hz,$( [ "$hz" = 60 ] && echo PASA || echo FALLA)" | tee -a "$OUT"
    S "journalctl --since -2min --no-pager | grep -E 'uke-refresco' | tail -3";;
  perfiles) for p in ahorro equilibrado rendimiento; do
      S "uke-perfil set $p >/dev/null"; brillo "$BL_PCT"; dpms on
      muestra "$ON" "$p-pantalla"
      K=${TANDA_K:-$(S "cat /run/uke-tanda.k 2>/dev/null")}; K=${K:-12}
      S "rm -f /run/uke-tanda-carga.txt; systemd-run --unit=uke-tanda-carga --collect python3 -c '$CARGA' $K >/dev/null"
      muestra "$ON" "$p-carga"
      S "echo \"  ticks/saturados: \$(cat /run/uke-tanda-carga.txt 2>/dev/null) (K=$K)\"; systemctl stop uke-tanda-carga"
      dpms off; muestra "$OFF" "$p-dpmsoff"; dpms on
      gate_bateria 30 Discharging >/dev/null || die "bateria < 30 % o enchufada"
    done; S "uke-perfil set \$(cat /run/uke-tanda.perfil) >/dev/null";;
  wifi) dpms off
    S "iw dev wlan0 set power_save off"; muestra "$OFF" wifi-ps-off
    S "iw dev wlan0 set power_save on"; muestra "$OFF" wifi-ps-on
    S "uke-perfil set \$(cat /run/uke-tanda.perfil) >/dev/null"; dpms on;;
  tactil) brillo "$BL_PCT"; dpms on
    muestra "$ON" tactil-on
    S "systemctl kill -s STOP uke-touch.service"; muestra "$ON" tactil-parado; S "systemctl kill -s CONT uke-touch.service";;
  mic) bash "$D/medir-mic-ab.sh" run 150 | tee -a "${OUT%.csv}-mic.txt";;
  s2idle) S "systemctl stop uke-tanda-inhibe 2>/dev/null"; dpms off
    bash "$D/medir-s2idle.sh" arm 1800 || die "no se pudo armar s2idle"
    echo "suspendida; espero 1800 s + 120 s"; sleep 1920
    for _ in $(seq 30); do S true 2>/dev/null && break; sleep 10; done
    bash "$D/medir-s2idle.sh" report | tee -a "${OUT%.csv}-s2idle.txt"
    bash "$D/comprobar-reanudacion.sh" | tee -a "${OUT%.csv}-s2idle.txt";;
  *) echo "fase desconocida: $F" >&2;;
  esac; done
  python3 - "$OUT" <<'P'
import csv,sys
r=[x for x in csv.DictReader(open(sys.argv[1])) if x['w_gauge']]
print("%-24s %8s %10s %8s %6s"%("fase","W gauge","W corriente","%/h","cpu%"))
for x in r: print("%-24s %8s %10s %8s %6s"%(x['fase'],x['w_gauge'],x['w_corriente'],x['pct_h'],x['cpu_pct']))
P
  ;;
*) echo "uso: $0 check|run [\"fases\"]|restaura   (fases: refresco perfiles wifi tactil mic s2idle)"; exit 2;;
esac
