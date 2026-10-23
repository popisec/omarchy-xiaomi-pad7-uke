import numpy as np, struct, re
S='/tmp/claude-1000/-home-usuario-proyectos-omarchy-uke/c0be0426-2352-4933-a859-00af6537a93c/scratchpad/frames8k.bin'
b=open(S,'rb').read(); N=len(b)//8200
T=[];F=[]
for i in range(N):
    f=b[i*8200+8:(i+1)*8200]
    if struct.unpack_from('<I',f,8)[0]==0x509: T.append(struct.unpack_from('<d',b,i*8200)[0]); F.append(np.frombuffer(f[:0x2000],dtype='<i2'))
ts=np.array(T); F=np.array(F)
ev=[];st={}
for l in open('getevent-event12.txt'):
    m=re.match(r'\[\s*([\d.]+)\]\s+(\w+)\s+(\w+)\s+(\w+)',l)
    if not m: continue
    t=float(m.group(1)); typ,code,val=m.group(2),m.group(3),m.group(4)
    if typ=='EV_SYN':
        if st.get('ABS_X',0)>0 and st.get('ABS_Y',0)>0 and st.get('ABS_PRESSURE',0)>0: d=dict(st); d['t']=t; ev.append(d)
    elif typ=='EV_ABS':
        v=int(val,16); v=v-(1<<32) if v>=1<<31 else v; st[code]=v
et=np.array([e['t'] for e in ev]); EX=np.array([e['ABS_X'] for e in ev],float); EY=np.array([e['ABS_Y'] for e in ev],float); EP=np.array([e['ABS_PRESSURE'] for e in ev],float)
def pair(off=0.008,win=0.004):
    idx=[];sel=[]
    for k,t in enumerate(et):
        i=int(np.searchsorted(ts,t+off-win))
        if i<len(ts) and abs(ts[i]-(t+off))<=win: idx.append(i); sel.append(k)
    return np.array(idx),np.array(sel)
