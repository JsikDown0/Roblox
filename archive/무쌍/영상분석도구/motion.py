# motion.py seg t [crop] : per-frame mean abs diff in crop, -15..+30 frames
import sys, subprocess, numpy as np
seg=sys.argv[1]; t=float(sys.argv[2]); crop=sys.argv[3] if len(sys.argv)>3 else "960:540:480:270"
W,H=[int(x) for x in crop.split(":")[:2]]
cmd=["ffmpeg","-v","error","-ss",f"{t-15/60:.3f}","-i",f"seg{seg}.webm","-frames:v","46","-vf",f"crop={crop},scale={W//4}:{H//4},format=gray","-f","rawvideo","-"]
b=subprocess.run(cmd,capture_output=True).stdout
f=np.frombuffer(b,np.uint8).reshape(-1,H//4,W//4).astype(float)
d=np.abs(np.diff(f,axis=0)).mean((1,2)); br=f.mean((1,2))
print(f"t={t}: frame: diff / bright")
print(" ".join(f"{i-14:+d}:{x:.1f}" for i,x in enumerate(d)))
