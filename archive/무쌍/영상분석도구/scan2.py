# scan2.py video start dur crop out : camera shift in a crop (no HUD / letterbox)
import sys, subprocess, numpy as np, cv2
v, ss, du, crop, out = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4], sys.argv[5]
cw, ch = [int(x) for x in crop.split(":")[:2]]
W = 480; H = int(round(ch * W / cw / 2) * 2)
cmd = ["ffmpeg","-v","error","-ss",str(ss),"-t",str(du),"-i",v,"-vf",f"crop={crop},scale={W}:{H}:flags=area,format=gray","-f","rawvideo","-"]
p = subprocess.Popen(cmd, stdout=subprocess.PIPE, bufsize=10**7)
win = cv2.createHanningWindow((W, H), cv2.CV_32F); prev=None; st=[]
while True:
    b = p.stdout.read(W*H)
    if len(b) < W*H: break
    g = np.frombuffer(b, np.uint8).reshape(H, W).astype(np.float32)
    if prev is None: st.append((0,0,0,0))
    else:
        (dx,dy),r = cv2.phaseCorrelate(prev.copy(), g.copy(), win)
        st.append((np.abs(g-prev).mean(), dx*320/W, dy*320/W, r))   # 320 폭 기준으로 환산
    prev = g
np.save(out, np.array(st, np.float32)); print(out, len(st), W, H)
