import sys, os; sys.path.insert(0,'.')
import numpy as np, flag_vox as fv, vox_preview as vp
from PIL import Image, ImageDraw, ImageFont
import cetus_final as cf
S=sys.argv[1]
M=fv.Model.load(S+"cetus_final.json")
def down2(a, lo):
    o=np.array(lo)%2; a=np.pad(a,[(o[i],0) for i in range(3)])
    sh=[(s+1)//2*2 for s in a.shape]; b=np.zeros(sh,np.uint8); b[:a.shape[0],:a.shape[1],:a.shape[2]]=a
    v=b.reshape(sh[0]//2,2,sh[1]//2,2,sh[2]//2,2).transpose(0,2,4,1,3,5).reshape(sh[0]//2,sh[1]//2,sh[2]//2,8)
    out=np.zeros(v.shape[:3],np.uint8); best=np.zeros(v.shape[:3],int)
    pri={6:3,10:3,8:3,4:2}   # 발광·궁극기 줄·홈은 1칸이라도 살림
    for c in range(1,11):
        cnt=(v==c).sum(-1)*pri.get(c,1)
        upd=cnt>best; out[upd]=c; best[upd]=cnt[upd]
    out[(v>0).sum(-1)<4]=0
    return out, np.array(lo)-o
H=fv.Model()
for n,p in M.parts.items():
    d,lo=down2(p.a,p.lo)
    q=H.part(n,tuple(lo),tuple(lo+np.array(d.shape)*2),p.pivot,p.parent); q.rot=p.rot
    q.a=np.repeat(np.repeat(np.repeat(d,2,0),2,1),2,2)
f=ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',22)
tiles=[]
for MM,lab in ((M,"원래 해상도 · 146,710 삼각형"),(H,"절반 해상도 · 45,488 삼각형")):
    B=MM.blocks()
    tiles.append((vp.render(B,cf.PAL,cf.EMISSIVE,yaw=-30,pitch=6,ppc=2.4,ss=2,ao_amt=0.5,metal=cf.METAL),lab+" · 앞 3/4"))
    tiles.append((vp.render(B,cf.PAL,cf.EMISSIVE,yaw=155,pitch=8,ppc=2.4,ss=2,ao_amt=0.5,metal=cf.METAL,light=(0.55,0.75,0.85)),lab+" · 뒤 3/4"))
H_=max(t[0].height for t in tiles); W=sum(t[0].width+16 for t in tiles)
sh=Image.new("RGB",(W,H_+44),(18,19,22)); d=ImageDraw.Draw(sh); x=0
for im,t in tiles:
    sh.paste(im,(x,H_-im.height)); d.text((x+8,H_+8),t,fill=(220,220,220),font=f); x+=im.width+16
sh.save(S+"cetus_half_compare.png"); print(sh.size)
