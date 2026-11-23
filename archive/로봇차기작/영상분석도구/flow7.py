import sys,subprocess,numpy as np,cv2,csv
path,out,ss,dur,fps=sys.argv[1],sys.argv[2],float(sys.argv[3]),float(sys.argv[4]),int(sys.argv[5])
W,H=494,215
p=subprocess.Popen(['ffmpeg','-v','error','-ss',str(ss),'-t',str(dur),'-i',path,'-vf',f'fps={fps},scale={W}:{H}','-f','rawvideo','-pix_fmt','bgr24','-'],stdout=subprocess.PIPE)
def grid(x0,x1,y0,y1,step=12):
    xs=np.arange(int(x0*W),int(x1*W),step);ys=np.arange(int(y0*H),int(y1*H),step)
    g=np.array([[x,y] for y in ys for x in xs],np.float32).reshape(-1,1,2);return g
top=grid(.18,.82,.10,.32);bot=grid(.22,.78,.74,.95);side=np.vstack([grid(.16,.32,.3,.72),grid(.68,.84,.3,.72)])
allp=np.vstack([top,bot,side])
nt,nb=len(top),len(bot)
prev=None;i=0
w=csv.writer(open(out,'w'));w.writerow('t tdx tdy bdx bdy sc rot diff sat_edge hue_r hue_g hue_b fb'.split())
lk=dict(winSize=(21,21),maxLevel=3,criteria=(cv2.TERM_CRITERIA_EPS|cv2.TERM_CRITERIA_COUNT,20,.03))
while True:
    b=p.stdout.read(W*H*3)
    if len(b)<W*H*3:break
    f=np.frombuffer(b,np.uint8).reshape(H,W,3);g=cv2.cvtColor(f,cv2.COLOR_BGR2GRAY)
    if prev is not None:
        q,st,err=cv2.calcOpticalFlowPyrLK(prev,g,allp,None,**lk)
        back,st2,_=cv2.calcOpticalFlowPyrLK(g,prev,q,None,**lk)
        fb=np.abs(back-allp).reshape(-1,2).max(1)
        good=(st.ravel()==1)&(st2.ravel()==1)&(fb<1.0)
        d=(q-allp).reshape(-1,2)
        gt=good[:nt];gb=good[nt:nt+nb]
        t_=np.median(d[:nt][gt],0) if gt.sum()>8 else [np.nan,np.nan]
        b_=np.median(d[nt:nt+nb][gb],0) if gb.sum()>8 else [np.nan,np.nan]
        sc=rot=np.nan
        if good.sum()>20:
            M,inl=cv2.estimateAffinePartial2D(allp[good],q[good],method=cv2.RANSAC,ransacReprojThreshold=1.5)
            if M is not None:
                sc=float(np.hypot(M[0,0],M[1,0]));rot=float(np.arctan2(M[1,0],M[0,0]))
        diff=float(np.mean(cv2.absdiff(prev,g)))
        hsv=cv2.cvtColor(f,cv2.COLOR_BGR2HSV)
        m=np.zeros((H,W),bool);m[:12]=1;m[-12:]=1
        edge=f[m].mean(0);sat=hsv[...,1][m].mean()
        w.writerow([round(ss+i/fps,3),*np.round(t_,3),*np.round(b_,3),round(sc,5) if sc==sc else '',round(rot,5) if rot==rot else '',round(diff,2),round(float(sat),1),round(float(edge[2]),1),round(float(edge[1]),1),round(float(edge[0]),1),round(float(np.median(fb[good])),3) if good.any() else ''])
    prev=g;i+=1
print('frames',i)
