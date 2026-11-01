"""aello_wing_view.py — AELLO 날개 상태 렌더(Studio 와 같은 각도) + 날개 끝 노즐 불꽃 표시 (10-27 00:20)
Studio 관절(WingJointL/R, 템플릿 축)의 Transform = Rx(−젖힘) · Rz(∓펼침) → Blender 축 R_b = Mm^T R_t Mm 를 pose 로 넣어 그림.
불꽃 = 날개 아래 끝(주황 판 끝 6칸 높이 가운데)에서 (긴 축 + 뒤 0.3) 방향 30칸 원뿔, 색 6(발광) — Studio WingNozzleL/R 와 같은 자리·방향.
  python3 rig/aello_wing_view.py OUT.png"""
import sys
import numpy as np
sys.path.insert(0, "/home/claude/flag")
import aero_export as E
import aero_colors as Cc
import aero_r1 as A
import vox_preview as vp

Mm = np.array([[-1, 0, 0], [0, 0, 1], [0, 1, 0]], float)
F = np.diag([-1.0, 1, 1])


def Rx(d):
    a = np.radians(d); c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def Rz(d):
    a = np.radians(d); c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


AXIS_T = np.array([0.057, -0.964, 0.262])      # 왼 날개 긴 축(아래 방향, 템플릿 축) [실측: 복셀 PCA]


def rot_axis(ax, deg):
    ax = np.asarray(ax, float); ax = ax / np.linalg.norm(ax); a = np.radians(deg)
    K = np.array([[0, -ax[2], ax[1]], [ax[2], 0, -ax[0]], [-ax[1], ax[0], 0]])
    return np.eye(3) + np.sin(a) * K + (1 - np.cos(a)) * K @ K


def wing_pose(spread, back, twist=0):
    """twist(10-27): 날개를 제 긴 축으로 비틂 — + 면 뒤 판(주황 넓은 면)이 뒤·위(게임 카메라)를 봄."""
    RtL = Rx(-back) @ Rz(-spread) @ rot_axis(AXIS_T, twist)   # 템플릿 축(왼 날개)
    RbL = Mm.T @ RtL @ Mm
    return {"WingL": RbL, "WingR": F @ RbL @ F}


def add_flames(M, pose, length=30):
    for side in ("L", "R"):
        n = "Wing" + side
        p = M.parts[n]
        ijk = np.argwhere(p.a == 1).astype(float) + p.lo + 0.5        # 주황 판(로컬 칸)
        W0 = M.world(n, A.STANCE)                                         # 쉬는 자세에서 아래 끝 고름
        z = (ijk @ W0[:3, :3].T + W0[:3, 3])[:, 2]
        tip = ijk[z <= z.min() + 6].mean(0)
        allc = np.argwhere(p.a > 0).astype(float) + p.lo + 0.5
        c = allc.mean(0); u, s, vt = np.linalg.svd(allc - c, full_matrices=False)
        ax_w = W0[:3, :3] @ vt[0]
        if ax_w[2] > 0:
            vt0 = -vt[0]
        else:
            vt0 = vt[0]
        # 분사 방향(로컬) = 긴 축(아래) + 뒤(+Y 월드)를 로컬로
        back_l = W0[:3, :3].T @ np.array([0, 1.0, 0])
        d = vt0 / np.linalg.norm(vt0) * 1.0
        d = d + 0.3 * back_l * (1 / 0.964)                               # Studio: (축 + (0,0,0.3)) — 축의 아래 성분 0.964 기준
        d /= np.linalg.norm(d)
        W = M.world(n, pose)
        tip_w = W[:3, :3] @ tip + W[:3, 3]
        d_w = W[:3, :3] @ d
        pts = [tip_w + d_w * t for t in np.arange(2, length)]
        lo = np.floor(np.min(pts, 0) - 4).astype(int); hi = np.ceil(np.max(pts, 0) + 4).astype(int)
        q = M.part("Flame" + side, tuple(lo), tuple(hi), pivot=tuple(lo))
        G = q.g(); X, Y, Zg = G
        shp = np.broadcast_shapes(X.shape, Y.shape, Zg.shape)
        m = np.zeros(shp, bool)
        for i, pt in enumerate(pts):
            r = 2.2 * (1 - i / len(pts)) + 0.6
            m |= ((X - pt[0]) ** 2 + (Y - pt[1]) ** 2 + (Zg - pt[2]) ** 2) <= r * r
        q.add(m, 6)


if __name__ == "__main__":
    out = sys.argv[1]
    pal = Cc.SCHEMES[E.SCHEME]
    rows = []
    for lab, sp, bk in (("folded (ground)", 0, 0), ("air: spread 55", 55, 0), ("air boost: 35 + back 28", 35, 28)):
        M = E.build()
        pose = dict(A.STANCE); pose.update(wing_pose(sp, bk))
        if sp or bk:
            add_flames(M, pose)
        B = M.blocks(pose=pose)
        ims = [vp.render(B, pal, A.EMISSIVE, yaw=y, pitch=p, ppc=1.3, ss=2, size=((-160, 160), (-10, 320)), ao_amt=0.5)
               for y, p in ((180, 10), (150, 12), (90, 4), (20, 6))]
        rows.append(vp.sheet(ims, [lab + "  back", "back 3/4", "side", "front 3/4"]))
    from PIL import Image
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("saved", out, S.size)
