#!/usr/bin/env python3
"""Para cada inicio de rafaga de presion BLE (presion>0 tras >=0.4 s a 0) busca la primera entrada de herramienta (evmon BTN_TOOL_PEN=1) y el
cierre previo; da la latencia presion->frames del chip. Solo donde evmon cubre. Uso: latencia.py DIR..."""
import sys, json, re
for d in sys.argv[1:]:
    ble=[]
    for l in open(d+"/ble.log"):
        p=l.split(" ",1)
        try: ble.append((float(p[0]),json.loads(p[1])))
        except Exception: pass
    ev=[]
    for l in open(d+"/evmon.log"):
        p=l.split()
        if len(p)==4 and re.match(r"\d+\.\d+$",p[0]): ev.append(tuple(map(float,p)))
    if not ev: continue
    e0,e1=ev[0][0],ev[-1][0]
    tin=[e[0] for e in ev if e[1]==1 and e[2]==320 and e[3]==1]; tout=[e[0] for e in ev if e[1]==1 and e[2]==320 and e[3]==0]
    tch=[(e[0],e[3]) for e in ev if e[1]==1 and e[2]==330]
    onsets=[];last=-9;
    for t,m in ble:
        if "pressure" in m and m["pressure"]>0:
            if t-last>0.4 and e0-1<=t<=e1: onsets.append(t)
            last=t
    print("##",d.split("linux/")[1],"evmon %.1f-%.1f"%(e0,e1),"tool_in",len(tin),"tool_out",len(tout),"onsets BLE",len(onsets))
    for o in onsets:
        nxt=[t for t in tin if t>=o-3]; 
        prev=[t for t in tin if t<o]; po=[t for t in tout if t<o]
        inr = bool(prev) and (not po or po[-1]<prev[-1])   # en rango en el instante del onset
        n=nxt[0] if nxt else None
        print("  onset %.3f  en_rango_ya=%s  primera herramienta-in tras onset-3s: %s"%(o,inr,("%+.2f s"%(n-o)) if n else "ninguna"))
