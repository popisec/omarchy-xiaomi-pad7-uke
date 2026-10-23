import sys,os,time,importlib.util
def load(p):
    sp=importlib.util.spec_from_file_location("m"+p.replace('/','_'),p+"/thp_algo.py"); m=importlib.util.module_from_spec(sp); sp.loader.exec_module(m); return m
A,B=load(sys.argv[1]),load(sys.argv[2])
D='../fr/frames'
frs=[open(os.path.join(D,f),'rb').read() for f in sorted(os.listdir(D))]
ms=[]
for F in frs:
    p=A.parse_frame(F)
    ms.append(p[1] if p else None)
import array
def run(M,fast=True):
    tr=M.Tracker(); out=[]; t0=time.perf_counter()
    for m in ms:
        if m is None: out.append(None); continue
        mm=array.array('H',m)
        out.append([] if tr.quick_idle(mm) else tr.feed(mm))
    return out,time.perf_counter()-t0
oa,ta=run(A); ob,tb=run(B)
print("time A %.2fs B %.2fs speedup %.1fx"%(ta,tb,ta/tb))
nd=0;mx=0;idd=0
for a,b in zip(oa,ob):
    if a is None: continue
    if len(a)!=len(b): nd+=1; continue
    a=sorted(a,key=lambda p:(round(p[1]/3000),p[2])); b=sorted(b,key=lambda p:(round(p[1]/3000),p[2]))
    for (t1,x1,y1,n1),(t2,x2,y2,n2) in zip(a,b):
        mx=max(mx,abs(x1-x2),abs(y1-y2)); idd+= 0
print("frames with different touch count",nd,"max pos diff (android units, 10=1px)",mx,"id mismatches",idd)
