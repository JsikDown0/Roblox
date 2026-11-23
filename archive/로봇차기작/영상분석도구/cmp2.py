import csv,sys,numpy as np
B=sys.argv[1]
V=[('MB ground','vid',480,[(430,470),(545,570)]),('MB air','vid2',480,[]),('GD melee','vid3',382.2,[]),('GD sniper','vid4',480,[]),('OURS skadi','vid5',382.2,[]),('OURS valk','vid6',382.2,[])]
def sm(x,n=5):
    x=np.where(np.isnan(x),0,x);return np.convolve(x,np.ones(n)/n,'same')
for name,d,W,ex in V:
    r=list(csv.DictReader(open(f'{B}/{d}/flow.csv')))
    c=lambda k:np.array([float(x[k]) if x[k] not in('','nan') else np.nan for x in r])
    t=c('t');td=np.c_[c('tdx'),c('tdy')];bd=np.c_[c('bdx'),c('bdy')];diff=c('diff');sc=c('sc')
    okb=~np.isnan(bd).any(1);okt=~np.isnan(td).any(1)
    m=okb.copy()
    for a,b in ex:m&=~((t>=a)&(t<b))
    raw=sm(np.linalg.norm(bd,axis=1)*20/W*100)
    par=sm(np.linalg.norm(np.nan_to_num(bd-td),axis=1)*20/W*100)
    vert=sm(np.abs(bd[:,1])*20/W*100)
    yaw=sm(np.abs(td[:,0])*20/W*100)
    z=sm((sc-1)*2000)
    Q=[50,75,90,99]
    print(f'== {name} n={len(t)} bottomValid={okb.mean()*100:.0f}% topValid={okt.mean()*100:.0f}%')
    print(' raw bottom',np.round(np.percentile(raw[m],Q),1),' <5:',round((raw[m]<5).mean()*100),'% >30:',round((raw[m]>30).mean()*100),'% >60:',round((raw[m]>60).mean()*100),'%')
    if okt.mean()>.5: print(' parallax',np.round(np.percentile(par[m&okt],Q),1))
    print(' vert',np.round(np.percentile(vert[m],Q),1),' yaw(top)',np.round(np.percentile(yaw[m&okt],Q),1) if (m&okt).sum()>50 else 'na')
    print(' expand>10%',round((z[m]>10).mean()*100),'% shrink',round((z[m]<-10).mean()*100),'%')
    # 절대 기준 급가속: raw>60 진입 횟수
    above=raw>60;ent=np.sum(above[1:]&~above[:-1]&m[1:]);mins=m.sum()/20/60
    print(' raw>60 entries/min',round(ent/mins,1))
    dd=diff[m];print(' framediff med',round(np.median(dd),1),'p90',round(np.percentile(dd,90),1),'>25 frames %',round((dd>25).mean()*100,1))
    sp=0;last=-9
    for i in np.where(diff>25)[0]:
        if t[i]-last>.5:sp+=1;last=t[i]
    print(' spikes(>25)/min',round(sp/mins,1))
