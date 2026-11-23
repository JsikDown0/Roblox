import numpy as np, sys
from scipy.ndimage import uniform_filter1d
k=sys.argv[1]; st={'1':420,'2':0,'3':440,'4':240,'5':0}[k]
s=np.load(f"s{k}_stats.npy"); g=np.load(f"g{k}.npy")
d,dx,dy,resp,mean,cen=s.T
# flash: center brightness jump vs median of previous 10 frames
base=np.array([np.median(cen[max(0,i-12):i-2]) if i>3 else cen[i] for i in range(len(cen))])
jump=cen-base
# shake: residual of shift vs 11-frame moving average (px at 320 scale)
rx=dx-uniform_filter1d(dx,11); ry=dy-uniform_filter1d(dy,11)
sh=np.hypot(rx,ry)
shs=uniform_filter1d(sh,6)
np.savez(f"ev{k}.npz", jump=jump, sh=sh, shs=shs)
print(f"seg{k} gameplay shake resid px@320 pct50 {np.percentile(sh[g],50):.2f} p90 {np.percentile(sh[g],90):.2f} p99 {np.percentile(sh[g],99):.2f}")
def peaks(x, th, gap=30):
    idx=np.where((x>th)&g)[0]; out=[]; last=-999
    for i in idx:
        if i-last>gap: out.append(i)
        elif x[i]>x[out[-1]]: out[-1]=i
        last=i
    return out
fp=peaks(jump,35)
print("flash peaks", len(fp), [(round(st+i/60,2), int(jump[i])) for i in fp][:80])
sp=peaks(shs,np.percentile(shs[g],99.3))
print("shake peaks", len(sp), [(round(st+i/60,2), round(float(shs[i]),2)) for i in sp][:80])
