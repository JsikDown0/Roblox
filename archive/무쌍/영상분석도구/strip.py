# strip.py seg out t1 t2 ... ; each row = event, cols = offsets
import sys, subprocess, numpy as np, cv2
seg, out = sys.argv[1], sys.argv[2]; ts=[float(x) for x in sys.argv[3:]]
import os
OFF=[int(x) for x in os.environ.get("OFF","-6,-3,-1,0,1,2,3,4,6,8,11,15,20,28").split(",")]
W,H=320,180
CROP=os.environ.get("CROP","")
rows=[]
for t in ts:
    t0=t+OFF[0]/60
    n=OFF[-1]-OFF[0]+1
    cmd=["ffmpeg","-v","error","-ss",f"{t0:.3f}","-i",f"seg{seg}.webm","-frames:v",str(n),"-vf",(f"crop={CROP}," if CROP else "")+f"scale={W}:{H}","-f","rawvideo","-pix_fmt","bgr24","-"]
    b=subprocess.run(cmd,capture_output=True).stdout
    fr=np.frombuffer(b,np.uint8).reshape(-1,H,W,3)
    cells=[]
    for o in OFF:
        i=o-OFF[0]; f=fr[min(i,len(fr)-1)].copy()
        cv2.putText(f,f"{o:+d}",(3,174),cv2.FONT_HERSHEY_SIMPLEX,0.45,(0,255,255),1)
        cells.append(f)
    C=int(os.environ.get('COLS','99'))
    while len(cells)%C and C<99: cells.append(np.zeros_like(cells[0]))
    row=np.vstack([np.hstack(cells[i:i+C]) for i in range(0,len(cells),C)]) if C<99 else np.hstack(cells); cv2.putText(row,f"{t:.2f}",(3,12),cv2.FONT_HERSHEY_SIMPLEX,0.45,(0,255,0),1)
    rows.append(row)
cv2.imwrite(out,np.vstack(rows),[cv2.IMWRITE_JPEG_QUALITY,85])
