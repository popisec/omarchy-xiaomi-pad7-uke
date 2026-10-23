#!/usr/bin/env python3
"""Rafagas de presion BLE (separadas por >GAP s sin presion>0) y eventos de hall/btn/enable/rearme alrededor. Uso: rafagas.py DIR [t0 t1]"""
import sys, json, re
GAP=0.4
d=sys.argv[1]; t0=float(sys.argv[2]) if len(sys.argv)>2 else 0; t1=float(sys.argv[3]) if len(sys.argv)>3 else 1e9
rows=[]
for l in open(d+"/ble.log"):
    p=l.split(" ",1)
    try: t=float(p[0]); m=json.loads(p[1])
    except Exception: continue
    if not t0<=t<=t1: continue
    if "pressure" in m: rows.append((t,"P",m["pressure"]))
    elif "btn" in m: rows.append((t,"B","%s %s"%(m["btn"],"down" if m["down"] else "up")))
    elif "attached" in m: rows.append((t,"A",m["attached"]))
    elif "connected" in m and False: pass
last=None; prevA=None
for l in open(d+"/touchd-pen.log"):
    m=re.search(r"\[(\d+\.\d+)\] lapiz: (activar|desactivar|rearme \d+)",l)
    if m and t0<=float(m[1])<=t1: rows.append((float(m[1]),"D",m[2]))
    m=re.search(r"\[(\d+\.\d+)\] lapiz: rearmes=.*frames0x509=(\d+) presentes=(\d+) ruido=(\d+)",l)
    if m and t0<=float(m[1])<=t1: rows.append((float(m[1]),"S","frames=%s presentes=%s ruido=%s"%m.groups()[1:]))
rows.sort(key=lambda r:(r[0],r[1]!="P"))
burst=None
def flush():
    global burst
    if burst: print("%9.3f P  rafaga %.2f s, %d muestras, max %d"%(burst[0],burst[1]-burst[0],burst[2],burst[3])); burst=None
for t,k,v in rows:
    if k=="P":
        if v>0:
            if burst and t-burst[1]>GAP: flush()
            if not burst: burst=[t,t,0,0]
            burst[1]=t; burst[2]+=1; burst[3]=max(burst[3],v)
        continue
    if k=="A":
        if v==prevA: continue
        prevA=v
    if burst and t-burst[1]>GAP: flush()
    print("%9.3f %s  %s"%(t,k,v))
flush()
