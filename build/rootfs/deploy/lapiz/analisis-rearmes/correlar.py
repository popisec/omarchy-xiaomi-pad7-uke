#!/usr/bin/env python3
"""Correlaciona rearmes/enable/disable del demonio con BLE y evmon (reloj monotonico comun). Uso: correlar.py DIR_SESION..."""
import re, sys, bisect, json
def load(d):
    tl=[]
    for l in open(d+"/touchd-pen.log"):
        m=re.search(r"\[(\d+\.\d+)\] lapiz: (activar|desactivar|rearme)(?: modo| (\d+) \()",l)
        if m: tl.append((float(m[1]),m[2]+(m[3] or "").strip(), l.strip()))
    ble=[]
    for l in open(d+"/ble.log"):
        p=l.split(" ",1)
        try: ble.append((float(p[0]),json.loads(p[1])))
        except Exception: pass
    ev=[]
    try:
        for l in open(d+"/evmon.log"):
            p=l.split()
            if len(p)==4 and re.match(r"\d+\.\d+$",p[0]): ev.append((float(p[0]),int(p[1]),int(p[2]),int(p[3])))
    except FileNotFoundError: pass
    return tl,ble,ev
def ctx(t,ble,ev):
    last_p=None;pv=0;att=None;att_t=None;lift=None;conn=None;btn=None
    for bt,m in ble:
        if bt>t: break
        if "pressure" in m:
            if m["pressure"]>0: last_p=bt
            if pv>0 and m["pressure"]==0: lift=bt
            pv=m["pressure"]
        if "attached" in m and m["attached"]!=att: att,att_t=m["attached"],bt
        if "connected" in m: conn=m["connected"]
        if "btn" in m: btn=bt
    lastev=None;tool=None;touch=None;lastabs=None
    for e in ev:
        if e[0]>t: break
        lastev=e[0]
        if e[1]==1 and e[2]==320: tool=e[3]
        if e[1]==1 and e[2]==330: touch=e[3]
    return dict(p=pv,dt_p=(t-last_p) if last_p else None,att=att,dt_att=(t-att_t) if att_t else None,dt_lift=(t-lift) if lift else None,
        tool=tool,touch=touch,dt_ev=(t-lastev) if lastev else None,dt_btn=(t-btn) if btn else None,ev_ok=bool(ev))
def f(x): return "  -  " if x is None else ("%5.1f"%x if isinstance(x,float) else "%5s"%x)
for d in sys.argv[1:]:
    tl,ble,ev=load(d); print("##",d,"eventos evmon:",len(ev))
    print("   t       tipo       p  dt_p  att dt_att dt_lift tool touch dt_ev dt_btn")
    for t,k,_ in tl:
        c=ctx(t,ble,ev)
        print("%9.3f %-9s %5s %s %5s %s %s %4s %4s %s %s"%(t,k,c["p"],f(c["dt_p"]),c["att"],f(c["dt_att"]),f(c["dt_lift"]),c["tool"],c["touch"],f(c["dt_ev"]) if c["ev_ok"] else " n/d ",f(c["dt_btn"])))
