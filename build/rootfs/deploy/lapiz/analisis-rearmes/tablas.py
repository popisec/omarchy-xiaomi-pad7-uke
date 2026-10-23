#!/usr/bin/env python3
"""Tablas de cuantificacion. Uso: tablas.py DIR..."""
import sys, json, re, bisect
GAP=0.4
tot=dict(en=0,dis=0,en_hall=0,dis_hall=0,flaps=0,rearm=0)
for d in sys.argv[1:]:
    ble=[];
    for l in open(d+"/ble.log"):
        p=l.split(" ",1)
        try: ble.append((float(p[0]),json.loads(p[1])))
        except Exception: pass
    ch=[];prev=None
    for t,m in ble:
        if "attached" in m and m["attached"]!=prev: ch.append((t,m["attached"])); prev=m["attached"]
    ct=[c[0] for c in ch]
    dw=[(ch[i+1][0]-ch[i][0],ch[i][1]) for i in range(len(ch)-1)]
    ev=[]
    for l in open(d+"/touchd-pen.log"):
        m=re.search(r"\[([\d.]+)\] lapiz: (activar|desactivar|rearme \d+)",l)
        if m: ev.append((float(m[1]),m[2]))
    en=[e for e in ev if e[1]=="activar"]; dis=[e for e in ev if e[1]=="desactivar"]; re_=[e for e in ev if e[1].startswith("rearme")]
    def near(t):
        i=bisect.bisect_right(ct,t)-1
        return t-ct[i] if i>=0 else None
    eh=sum(1 for e in en if (near(e[0]) or 9)<0.6); dh=sum(1 for e in dis if (near(e[0]) or 9)<0.6)
    fl=sum(1 for w,s in dw if w<1.0)
    # rafagas con hall=pegado
    bursts=[];cur=None;att=None
    for t,m in ble:
        if "attached" in m: att=m["attached"]
        if "pressure" in m and m["pressure"]>0:
            if cur and t-cur[1]>GAP: bursts.append(cur);cur=None
            if not cur: cur=[t,t,0,att]
            cur[1]=t;cur[2]+=1
    if cur: bursts.append(cur)
    bg=[b for b in bursts if b[2]>=5]
    print("%-52s hallflips=%3d dwell<1s=%2d | enable=%2d (tras flip hall <0.6s: %2d) disable=%2d (idem %2d) rearme=%d | rafagas>=5 muestras=%2d con hall 'pegado' al inicio=%d"%(
        d.split("linux/")[1],len(ch),fl,len(en),eh,len(dis),dh,len(re_),len(bg),sum(1 for b in bg if b[3] is True)))
    if dw: print("   dwell hall: pegado med %.1f s, despegado med %.1f s"%(
        sorted(w for w,s in dw if s)[len([1 for w,s in dw if s])//2] if any(s for w,s in dw) else -1,
        sorted(w for w,s in dw if not s)[len([1 for w,s in dw if not s])//2] if any(not s for w,s in dw) else -1))
