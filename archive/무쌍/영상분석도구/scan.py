# usage: scan.py video start dur outprefix
import sys, subprocess, numpy as np, cv2
v, ss, du, out = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
W, H = 320, 180
cmd = ["ffmpeg","-v","error","-ss",str(ss),"-t",str(du),"-i",v,"-vf",f"scale={W}:{H}:flags=area,format=gray","-f","rawvideo","-"]
p = subprocess.Popen(cmd, stdout=subprocess.PIPE, bufsize=10**7)
fsz = W*H
prev = None
win = cv2.createHanningWindow((W, 150), cv2.CV_32F)
stats = []; small = []
while True:
    b = p.stdout.read(fsz)
    if len(b) < fsz: break
    f = np.frombuffer(b, np.uint8).reshape(H, W)
    g = f[30:, :].astype(np.float32)          # 오버레이(왼쪽 위 FPS 표시) 제외
    cen = g[35:115, 100:220].mean()
    if prev is None:
        d = 0; dx = dy = 0; resp = 0
    else:
        d = np.abs(g - prev).mean()
        (dx, dy), resp = cv2.phaseCorrelate(prev.copy(), g.copy(), win)
    stats.append((d, dx, dy, resp, g.mean(), cen))
    small.append(cv2.resize(f, (80, 45), interpolation=cv2.INTER_AREA))
    prev = g
np.save(out + "_stats.npy", np.array(stats, np.float32))
np.save(out + "_small.npy", np.array(small, np.uint8))
print(out, len(stats))
