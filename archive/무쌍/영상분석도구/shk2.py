import numpy as np
from scipy.ndimage import uniform_filter1d
def run(f, st, sel=None):
    s=np.load(f); d,dx,dy,r=s.T
    dx=np.where(r<0.03,0,dx); dy=np.where(r<0.03,0,dy)   # 상관 실패 프레임 버림
    # 한 프레임 큰 점프(컷 · 순간이동) 제외: 20px 넘는 이동은 0
    big=np.hypot(dx,dy)>20; dx[big]=0; dy[big]=0
    px=np.cumsum(dx); py=np.cumsum(dy)
    hx=px-uniform_filter1d(px,15); hy=py-uniform_filter1d(py,15)
    a=np.hypot(hx,hy)
    a6=uniform_filter1d(a,6)
    th=1.0
    idx=np.where(a6>th)[0]; b=[]
    for i in idx:
        if b and i-b[-1][1]<=6: b[-1][1]=i
        else: b.append([i,i])
    mins=len(a)/3600
    amps=[a[x[0]:x[1]+1].max() for x in b] or [0]; durs=[(x[1]-x[0]+1) for x in b] or [0]
    print(f"{f}: 0.25초 고주파 위치 성분 |r| pct50 {np.percentile(a,50):.2f} p90 {np.percentile(a,90):.2f} p99 {np.percentile(a,99):.2f} (px@320)")
    print(f"   bursts>{th}px: {len(b)/mins:.1f}/min  peak med {np.median(amps):.2f} p90 {np.percentile(amps,90):.2f}  dur med {np.median(durs):.0f}f p90 {np.percentile(durs,90):.0f}f")
    return a
run("c4.npy",280); run("c5.npy",0)
