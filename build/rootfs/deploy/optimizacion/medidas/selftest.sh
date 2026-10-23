#!/bin/bash
# selftest.sh — prueba EN SECO de los scripts de medida (solo PC, sin tablet: ssh falso + sysfs falso en un directorio temporal). 22-oct-2026.
set -u; H=$(cd "$(dirname "$0")" && pwd); cd "$H"; D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
OK=0; NG=0; t() { if [ "$2" = 0 ]; then echo "  PASA  $1"; OK=$((OK+1)); else echo "  FALLA $1"; NG=$((NG+1)); fi; }
# ---- arbol falso
mkdir -p $D/sys/class/power_supply/qcom-battmgr-bat $D/sys/class/power_supply/qcom-battmgr-usb $D/sys/power $D/bin $D/var
B=$D/sys/class/power_supply/qcom-battmgr-bat; U=$D/sys/class/power_supply/qcom-battmgr-usb
echo Discharging > $B/status; echo 80 > $B/capacity; echo 6000000 > $B/charge_counter; echo 0 > $U/online; echo "[s2idle] deep" > $D/sys/power/mem_sleep; echo 184 > $D/sys/power/pm_wakeup_irq
touch $D/hook; chmod +x $D/hook; echo 60 > $D/hz
cat > $D/bin/runuser <<'X'
#!/bin/bash
echo "[{\"refreshRate\": $(cat $FAKE/hz).0}]"
X
cat > $D/bin/rtcwake <<'X'
#!/bin/bash
echo "rtcwake $*" >> $FAKE/rtc.log
X
cat > $D/bin/systemd-run <<'X'
#!/bin/bash
echo "systemd-run $*" >> $FAKE/sdrun.log
X
cat > $D/bin/systemctl <<'X'
#!/bin/bash
echo "systemctl $*" >> $FAKE/sdrun.log; echo active
X
cat > $D/bin/journalctl <<'X'
#!/bin/bash
echo "ene 01 00:00:00 uke NetworkManager[1]: NetworkManager is stopping (journalctl $*)"
X
for c in coredumpctl iw; do printf '#!/bin/bash\necho "%s stub $*"\n' $c > $D/bin/$c; done; chmod +x $D/bin/*
export FAKE=$D PATH=$D/bin:$PATH SYSFS=$D UKE_SSH=$H/fixtures/fake-ssh.sh UKE_RUN=$D/run.sh UKE_S2CSV=$D/s2.csv UKE_MARCAS=$D/marcas.csv UKE_HOOK=$D/hook
echo "== 1. check (sintaxis) de todos"
for f in medir-s2idle.sh medir-drenaje-uso.sh medir-carga-rapida.sh probar-refresco-bateria.sh leer-journal-wifi.sh medir-mic-ab.sh; do bash $f check >/dev/null 2>&1; t "check $f" $?; done
echo "== 2. gates negativos"
( unset UKE_TURNO; bash medir-s2idle.sh arm 600 >/dev/null 2>&1 ); t "s2idle arm sin turno -> aborta" $((! $?))
echo Charging > $B/status; ( UKE_TURNO=1 bash medir-s2idle.sh arm 600 >/dev/null 2>&1 ); t "s2idle arm con Charging -> aborta" $((! $?))
( UKE_TURNO=1 bash medir-carga-rapida.sh run 5 >/dev/null 2>&1 ); t "carga-rapida con 80 % -> aborta" $((! $?))
echo Discharging > $B/status; echo 20 > $B/capacity; ( UKE_TURNO=1 bash medir-s2idle.sh arm 600 >/dev/null 2>&1 ); t "s2idle arm con 20 % -> aborta" $((! $?))
echo 80 > $B/capacity
( UKE_TURNO=1 bash medir-s2idle.sh arm 100 >/dev/null 2>&1 ); t "s2idle arm 100 s (fuera de rango) -> aborta" $((! $?))
echo "== 3. s2idle: arm + runner en seco"
UKE_TURNO=1 bash medir-s2idle.sh arm 600 >$D/arm.out 2>&1; t "arm OK (copia runner y lanza systemd-run)" $?
grep -q "unit=uke-s2idle-run" $D/sdrun.log 2>/dev/null; t "systemd-run recibio la unidad" $?
cat > $D/suspend.sh <<X
#!/bin/bash
echo 5990000 > $B/charge_counter; echo 76 > $B/capacity; sleep 2
X
chmod +x $D/suspend.sh
SYSFS=$D S2IDLE_OUT=$D/s2.csv RTCWAKE=$D/bin/rtcwake SUSPEND_CMD=$D/suspend.sh bash $D/run.sh 600 > $D/run.out 2>&1; t "runner: ejecuta y anota" $?
tail -1 $D/s2.csv | grep -qE ",[0-9]+,80,76,6000000,5990000,[0-9-]+,Discharging,184$"; t "runner: fila del CSV correcta ($(tail -1 $D/s2.csv))" $?
grep -q "rtcwake -m no -s 600" $D/rtc.log; t "runner: alarma RTC armada a 600 s" $?
echo Charging > $B/status; SYSFS=$D S2IDLE_OUT=$D/s2b.csv RTCWAKE=$D/bin/rtcwake SUSPEND_CMD=true bash $D/run.sh 600 >/dev/null 2>&1; t "runner con Charging -> sale 3 sin suspender" $(( $? != 3 )); echo Discharging > $B/status
UKE_S2MIN=1 bash medir-s2idle.sh report 2>&1 | grep -q "media s2idle"; t "report calcula la media" $?
UKE_TURNO=1 bash medir-s2idle.sh revert >/dev/null 2>&1; [ ! -e $D/run.sh ] && grep -q "rtcwake -m disable" $D/rtc.log; t "revert borra el runner y desarma la RTC (rtcwake -m disable)" $?
echo "== 4. drenaje uso real: report con el CSV real del 21-oct (65 min, esperado ~3,88 %/h)"
C=$H/../../bateria/medidas/log-2026-10-21.csv
read A Z < <(python3 - $C <<'P'
import csv,sys
r=[x for x in csv.DictReader(open(sys.argv[1])) if x['estado']=='Discharging' and not x['event']]
print(r[0]['ts'], r[-1]['ts'])
P
)
printf 'etiqueta,inicio,fin\nprueba,%s,%s\n' "$A" "$Z" > $D/marcas.csv
bash medir-drenaje-uso.sh report $C > $D/dr.out 2>&1; cat $D/dr.out | sed 's/^/    /'
grep -q "= 3.88 %/h" $D/dr.out; t "drenaje: reproduce 3,88 %/h del 21-oct" $?
rm -f $D/marcas.csv; UKE_TURNO=1 bash medir-drenaje-uso.sh start prueba >/dev/null 2>&1; t "drenaje start crea marca" $?
UKE_TURNO=1 bash medir-drenaje-uso.sh stop >/dev/null 2>&1; t "drenaje stop cierra marca" $?
UKE_TURNO=1 bash medir-drenaje-uso.sh revert >/dev/null 2>&1; [ ! -e $D/marcas.csv ]; t "drenaje revert borra marcas" $?
echo "== 5. refresco en bateria (sondeo en seco; el 'dueño' enchufa/desenchufa en segundo plano)"
echo 1 > $U/online; echo 120 > $D/hz
( sleep 2; echo 0 > $U/online; sleep 3; echo 60 > $D/hz; sleep 4; echo 1 > $U/online; sleep 3; echo 120 > $D/hz ) &
UKE_TURNO=1 bash probar-refresco-bateria.sh run 18 > $D/ref.out 2>&1; wait; sed 's/^/    /' $D/ref.out | tail -4
grep -q "PASA bateria" $D/ref.out && grep -q "PASA cargador" $D/ref.out && grep -q "latencia" $D/ref.out; t "refresco: ve las transiciones y mide la latencia" $?
echo 0 > $U/online; echo 60 > $D/hz; UKE_TURNO=1 bash probar-refresco-bateria.sh run 6 > $D/ref2.out 2>&1; grep -q "NO VISTO bateria" $D/ref2.out && grep -q "NO VISTO cargador" $D/ref2.out; t "refresco: SIN transicion no da PASA (estado inicial ya correcto)" $?
echo "== 6. journal del WiFi (lectura)"
bash leer-journal-wifi.sh run -1 > $D/j.out 2>&1; grep -q "guardado:" $D/j.out; t "journal: genera el informe" $?
F=$(grep -o "guardado: .*" $D/j.out | cut -d' ' -f2); [ -f "$F" ] && rm -f "$F"
echo "== 7. micro siempre abierto: A/B en seco"
cat > $D/bin/uke-bateria-lectura <<'X'
#!/bin/bash
echo "70.00|$(cat $FAKE/w)|9999|Discharging|power-saver|1"
X
chmod +x $D/bin/uke-bateria-lectura; echo 0.95 > $D/w
cat > $D/mic-stub.sh <<X
#!/bin/bash
case "\$1" in --go) echo 1.05 > $D/w; echo "node.pause-on-idle = false" > $D/mic.conf;; --revert) echo 0.95 > $D/w; echo "# base" > $D/mic.conf;; esac; echo "mic \$1" >> $D/mic.log
X
chmod +x $D/mic-stub.sh
echo "# base" > $D/mic.conf; UKE_MICCONF=$D/mic.conf MICABIERTA=$D/mic-stub.sh MIC_SETTLE=1 UKE_TURNO=1 bash medir-mic-ab.sh run 4 > $D/mic.out 2>&1; sed 's/^/    /' $D/mic.out | tail -4
grep -q "ΔW = +0.100 W" $D/mic.out; t "mic A/B: calcula ΔW = +0,100 W entre base y variante" $?
grep -q "PROPONER" $D/mic.out; t "mic A/B: propone dejar la base si cuesta >0,05 W" $?
[ "$(tail -1 $D/mic.log)" = "mic --revert" ]; t "mic A/B: restaura el estado inicial al terminar" $?
rm -f $H/../../../../logs/mic-ab-*.csv 2>/dev/null
echo "SELFTEST: $OK PASA / $NG FALLA"; [ "$NG" = 0 ]
