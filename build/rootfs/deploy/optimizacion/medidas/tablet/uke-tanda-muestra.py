#!/usr/bin/python3
# uke-tanda-muestra.py SEG ETIQUETA [ASENTAR_S=20] — SE EJECUTA EN LA TABLET por stdin (ssh ... python3 - args < este fichero); no se copia. 22-oct-2026.
# Espera ASENTAR_S (excluido), muestrea cada 2 s durante SEG y escribe UNA linea CSV:
#   fase,seg,uah0,uah1,w_gauge,w_corriente,v,pct_h,cpu_pct,estado,n
# w_gauge = descarga del contador del gauge (charge_counter, pasos de 1000 uAh) x V medio: es la cifra buena para autonomia.
# w_corriente = media de -current_now x voltage_now (Linux: + = carga): ~20 % por encima del gauge (PENDIENTES-BATERIA §2), solo para comparar fases.
import sys, time
seg, et = int(sys.argv[1]), sys.argv[2]; settle = int(sys.argv[3]) if len(sys.argv) > 3 else 20
B = "/sys/class/power_supply/qcom-battmgr-bat/"
def rd(f): return int(open(B + f).read())
def cpu():
    a = list(map(int, open("/proc/stat").readline().split()[1:])); return sum(a), a[3] + a[4]
time.sleep(settle)
t0 = time.time(); u0 = rd("charge_counter"); c0 = cpu(); full = rd("charge_full"); vs, ws, st = [], [], set()
while time.time() - t0 < seg:
    v = rd("voltage_now") / 1e6; i = rd("current_now") / 1e6
    vs.append(v); ws.append(-i * v); st.add(open(B + "status").read().strip()); time.sleep(2)
t1 = time.time(); u1 = rd("charge_counter"); c1 = cpu(); dt = t1 - t0; vm = sum(vs) / len(vs)
wg = (u0 - u1) / 1e6 / (dt / 3600) * vm
pct_h = (u0 - u1) / full * 100 / (dt / 3600)
cp = 100 * (1 - (c1[1] - c0[1]) / max(1, c1[0] - c0[0]))
print(f"{et},{int(dt)},{u0},{u1},{wg:.3f},{sum(ws) / len(ws):.3f},{vm:.3f},{pct_h:.2f},{cp:.1f},{'/'.join(sorted(st))},{len(ws)}", flush=True)
