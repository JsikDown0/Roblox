"""
valk_spin1.py — 11-04 VALKYRIE 회전베기(부스터 일섬 + 빔 확장) 키 자세 r1.
  유저 결정: 1+2 합본 · 한 손으로 쭉 뻗기 · 총 모드에서도 순간 빔 점화.
  쥔 손 = 왼손(이 기체 칼 손잡이는 왼손 SaberGrip — valk_melee2) → 칼은 왼쪽으로 뻗고 몸은 오른쪽(위에서 시계)으로 돈다(왼쪽 → 정면 쓸기).
  키: SW 모으기(두 손 · 몸 왼쪽으로 감음 · 칼 왼 허리 뒤) / SX 휘두름(왼손만 · 팔·칼 왼쪽 수평 · 오른팔 균형) / SF 멈춤(칼 앞 왼 아래로 흘림).
  회전 자체는 Root 요(yaw) 추가 각(게임 쪽 코드) — 키 사이 보간이 아님(slerp 는 180° 넘게 못 돎).
"""
import sys, json
import numpy as np
import valk_melee1 as V, valk_melee2 as K, valk_melee_opt as O
SP = "/tmp/claude-0/-home-claude/45a5ff43-da6d-586c-af9c-a80fba67e5ee/scratchpad/"
inv = np.linalg.inv
FOOT0 = V.fk({})["FootL"][:3, 3][1]


# 11-04 13:3x 유저 "다리가 다소곳하고 서로 겹쳐 보임" — 원인(실측): HipL rz+ 는 왼발을 안쪽(+x)으로 보냄 → r2 는 벌린다는 게 양다리를 모았음.
#   고침: 벌림은 골반 틀에서 먼저(rz 를 rx 앞에) · 왼쪽 rz − / 오른쪽 rz + · 앞뒤 디딤(런지) · 두 발 다 땅에 닿게 뒷다리 무릎을 맞춤.
def leg(side, hip, knee, spread, toe=0):
    sg = 1 if side == "L" else -1
    H = V.rz(-sg * spread) @ V.ry(sg * toe) @ V.rx(hip)
    return {"Hip" + side: H, "Knee" + side: V.E(knee), "Ankle" + side: V.rx(-(hip + knee)) @ V.rz(sg * spread)}


def stance(front, back, spread=20, toe=15):
    """front/back = (쪽, 엉덩이, 무릎). 앞다리는 그대로, 뒷다리 무릎을 찾아 두 발 높이를 같게."""
    P = {}; P.update(leg(front[0], front[1], front[2], spread, toe))
    best = None
    for kn in np.linspace(-120, 0, 121):
        Q = dict(P); Q.update(leg(back[0], back[1], kn, spread, toe))
        W = V.fk(Q); dy = abs(W["FootL"][1, 3] - W["FootR"][1, 3])
        if best is None or dy < best[0]: best = (dy, Q)
    return best[1]


def leg_clash(P):
    W = V.fk(P); M, B = V.model(); I = K._ijk(); keys = {}
    for side in "LR":
        cs = []
        for n in ("Thigh" + side, "Shin" + side, "Foot" + side):
            f = V.FOLLOW[n]; Tm = V.MB @ W[f] @ inv(V.REST[f]) @ V.MS @ M.world(n)
            cs.append(np.round(I[n] @ Tm[:3, :3].T + Tm[:3, 3]).astype(int))
        keys[side] = set(map(tuple, np.concatenate(cs)))
    return len(keys["L"] & keys["R"])


def grounded(P):
    """발이 땅(쉬는 자세 발 높이)에 닿게 Root 높이 맞춤(Root 회전은 유지)."""
    Q = dict(P); R0 = Q.get("Root", np.eye(4)).copy(); R0[1, 3] = 0; Q["Root"] = R0
    W = V.fk(Q); low = min(W["FootL"][1, 3], W["FootR"][1, 3])
    R0[1, 3] = FOOT0 - low; Q["Root"] = R0
    return Q


SPEC = {   # 몸(Root 숙임·요, Waist, Neck, 다리) + 칼(몸통 로컬 p · d · e) + 손(two = 두 손 / 오른팔 FK)
    # r4 = 유저 참고 영상(11-04 13:49, 젤다 BotW 회전베기 — 15fps 프레임 분석) 반영:
    #   ① 처음부터 끝까지 한 손 · 반대 팔(링크는 방패 팔)은 가슴 앞에 들어 균형 → 발키리 오른팔(방패 쪽)을 가슴 앞으로.
    #   ② 넓고 깊은 기마 자세(두 무릎 바깥) 그대로 제자리 축 회전 · 상체는 거의 세움.
    #   ③ 칼 팔은 어깨 높이가 아니라 허리 높이로 낮게 뻗고 칼은 수평 → 잔상 원반이 허리~무릎 높이.
    #   ④ 한 바퀴 ≈ 0.33초(프레임 3 → 8, 5칸 / 15fps). ⑤ 끝 = 칼을 옆 뒤 아래로 흘린 채 잠깐 멈춤.
    #   등 방패가 팔 바깥(몸통 로컬 x ±6~7, z −2~3)에 세로로 있어 칼 팔은 앞 대각을 지나야 함(r2 실측).
    # r6(11-04 14:1x 경로 검사): G → SW 에서 왼 아래팔이 골반을 관통(16754칸) — 칼을 몸 뒤로 보내려면 옆(방패) · 아래(골반) 어디로든 막힘.
    #   → 모으기를 몸 앞 오른 허리 아래(역으로 감아 쥠 · 칼끝 오른 앞 아래)로 바꾸고 회전 방향을 왼쪽(위에서 반시계)으로 뒤집음:
    #     오른 허리에서 몸 앞을 가로질러 왼쪽으로 뻗으며 돎 — 칼은 팔 뒤를 끌려 따라옴(영상의 링크처럼). 손이 늘 몸 앞이라 관통 없음.
    #   멈춤 SF 는 왼 허벅지와 겹치던 것(겨눔으로 돌아갈 때 1451칸) → 왼무릎 덜 굽힘 · 손을 조금 높고 바깥으로.
    # r9(11-04 15:43 유저 "다리가 우스꽝스러움 → 링크 다리만 분석" — 영상 30fps: 넓게 주저앉음 → 돌 때 두 발을 몸 밑으로 모아 살짝 떠서 팽이처럼 →
    #   넓게 착지(앞 굽힘 · 뒤 뻗음) · 한 발로 서는 순간 없음): 모으기 = 넓은 주저앉음(두 발 20°) · 휘두름 = 두 발 모음(안쪽 4°) · 멈춤 = 왼발 앞 굽힘 · 오른발 뒤로
    # r8(11-04 15:11 유저 "발을 디디는 방식" — 플레이 영상: 몸 전체를 돌리니 두 발이 축에서 6.0 떨어진 원을 그리며 바닥을 쓺):
    #   왼발 = 축발 — 몸 바로 밑(축에서 0.07 [엉덩이 35 · 무릎 −95 · 안으로 12° 실측 탐색]) · 모으기 · 휘두름 · 멈춤 내내 같은 각 → 제자리에서 돌기만 함
    #   오른발 = 모으기 땐 뒤 오른쪽 넓게 디딤 → 휘두름 동안 들림(땅에서 약 3.8) → 멈출 때 오른쪽 앞에 쿵 디딤
    # r7(11-04 14:44 유저 "다리가 너무 쩍 벌어져 무게감이 안 삶 — 조금 줄이자"): 벌림 30 → 16° (SF 28 → 16 · SR 18 → 12) · 굽힘은 그대로
    # r10(11-04 15:49 유저 "상체 집중 분석 · 회전 시간 · 속도도 링크와 같게" — 영상 30fps):
    #   모으기 = 칼을 반대편(우리는 오른쪽 — 왼손잡이 거울)으로 가로질러 가슴~허리 높이 수평 · 상체를 그쪽으로 크게 감음 · 반대 팔(방패 팔)은 앞으로
    #   휘두름 = 칼 팔을 옆으로 곧게(어깨 → 칼끝 한 직선) · 허리 높이로 조금 내림 · 상체는 세움 · 반대 팔은 반대 옆으로 굽혀 듦
    #   (팔을 완전한 옆으로 뻗으면 등 방패를 지남 → 앞으로 20°만 — 유저 15:20 "충돌 너무 엄격할 필요 없음")
    "SW": dict(root=(6, 0, 0), waist=(4, -60, 0), neck=(0, 50, 0), legs2={"L": (50, -95, 20, 15), "R": (50, -95, 20, 15)},
               p=(2.4, -4.0, -3.6), d=(0.9, -0.15, 0.25), e=(-0.2, 0, -1), two=False, fistR=(3.5, -1.5, -5.5)),
    "SX": dict(root=(6, 0, 0), waist=(2, 0, 0), neck=(0, 0, 0), legs2={"L": (35, -75, 0, 5), "R": (35, -75, 0, 5)},
               p=(-10.1, -3.35, -1.6), d=(-0.95, -0.15, -0.25), e=(-0.25, 0, 0.95), two=False, fistR=(4.6, -1.2, -3.6)),
    "SF": dict(root=(8, 0, 0), waist=(6, 20, 0), neck=(-4, -20, 0), legs2={"L": (60, -100, 16, 10), "R": (-25, None, 20, 5)},
               p=(-6.4, -4.6, -3.2), d=(-0.75, -0.35, 0.55), e=(-0.55, 0, -0.85), two=False, fistR=(2.2, -1.8, -4.6)),
    # SR = 멈춤 → 겨눔 경유(r6 검사: 곧장 가면 왼 아래팔·손잡이가 앞으로 나온 왼 허벅지를 관통 3058칸) — 손을 허벅지 위 앞 왼쪽으로 들어 올려 지나감
    "SR": dict(root=(4, 0, 0), waist=(3, 10, 0), neck=(0, -10, 0), legs2={"L": (22, -50, -2, 8), "R": (18, None, 10, 0)},
               p=(-2.8, -2.2, -6.8), d=(-0.3, 0.45, -0.85), e=(0, -0.7, -0.7), two=False, fistR=(2.0, -1.2, -4.8)),
}


def fist_right(P, target_local, pole_local):
    """오른 주먹(Grip 관절 점)을 몸통 로컬 target 에 — 회전베기 때 링크 방패 팔처럼 가슴 앞에 듦."""
    W = V.fk(P); Tt = W["Torso"]
    _, _, c0s, c1s = V.J["ShoulderR"]; _, _, c0e, c1e = V.J["ElbowR"]
    gC0 = V.CF((0.28029, -2.70493, 0.0945)); S = Tt @ c0s
    a = (inv(c1s) @ c0e)[:3, 3]; b = (inv(c1e) @ gC0)[:3, 3]
    tgt = (Tt @ np.append(np.asarray(target_local, float), 1))[:3]
    Rs, th = V.solve_arm(S, a, b, tgt, Tt[:3, :3] @ K.nrm(pole_local))
    Q = dict(P); Q["ShoulderR"] = Rs; Q["ElbowR"] = V.rx(np.degrees(th)); return Q


def base_body(s):
    rx_, ry_, rz_ = s["root"]
    P = {"Root": V.E(rx_, ry_, rz_), "Waist": V.E(*s["waist"]), "Neck": V.E(*s["neck"])}
    if "legs2" in s:   # r8: 다리마다 (엉덩이, 무릎 | None = 두 발 높이 맞춤, 벌림, 발끝) · lift = 그 다리는 들림(맞추지 않음)
        L2 = s["legs2"]
        fixed = [sd for sd in "LR" if L2[sd][1] is not None]
        for sd in fixed: P.update(leg(sd, L2[sd][0], L2[sd][1], L2[sd][2], L2[sd][3]))
        for sd in "LR":
            if sd in fixed: continue
            best = None
            for kn in np.linspace(-120, 0, 241):
                Q = dict(P); Q.update(leg(sd, L2[sd][0], kn, L2[sd][2], L2[sd][3]))
                W = V.fk(Q); dy = abs(W["FootL"][1, 3] - W["FootR"][1, 3])
                if best is None or dy < best[0]: best = (dy, Q)
            P = best[1]
    else:
        fr, bk, sp = s["legs"]; P.update(leg(fr[0], fr[1], fr[2], sp, 15))
        best = None
        for kn in np.linspace(-120, 0, 241):                 # 뒷다리 무릎: Root 숙임까지 넣은 채로 두 발 높이 맞춤
            Q = dict(P); Q.update(leg(bk[0], bk[1], kn, sp, 15))
            W = V.fk(Q); dy = abs(W["FootL"][1, 3] - W["FootR"][1, 3])
            if best is None or dy < best[0]: best = (dy, Q)
        P = best[1]
    if not s["two"]:
        P = fist_right(P, s["fistR"], (1, -0.7, 0.2))
    return grounded(P)


def ev(s, x, P0):
    p = np.array(s["p"], float) + x[:3]
    d = K.nrm(s["d"]); e = np.array(s["e"], float)
    Rm = O.rot(np.cross(d, e) if np.linalg.norm(np.cross(d, e)) > 1e-6 else [0, 1, 0], x[3]) @ O.rot([0, 1, 0], x[4])
    d2 = Rm @ d; e2 = O.rot(d2, x[5]) @ (Rm @ e)
    P = dict(P0); Hw = V.fk(P)["Torso"] @ K.hilt_local(p, d2, e2)
    P, eL, wr = K.solve_left(P, Hw, O.pole(x[6], x[7], -1))
    eR = 0; rw = 0
    if s["two"]:
        P, eR, _ = K.solve_right(P, O.pole(x[8], x[9], 1)); rw, _ = K.right_wrist(P)
    c = K.fast2(P)
    cost = c + 4 * max(0, wr - 75) + 1.5 * max(0, rw - 100) + 3000 * (eR + eL) + 10 * float(x[:3] @ x[:3]) + 0.02 * float(x[3:6] @ x[3:6])
    return cost, P, dict(clash=c, wrL=wr, wrR=rw, eL=eL, eR=eR, pr=O.pole(x[8], x[9], 1).tolist())


def solve(name, it=140, seed=7):
    s = SPEC[name]; P0 = base_body(s); rng = np.random.default_rng(seed)
    x = np.zeros(10); x[6:] = [0, -30, 0, -30]
    best = (*ev(s, x, P0), x)
    sc = np.array([1.0, 1.0, 1.0, 10, 10, 20, 60, 50, 60, 50])
    for i in range(it):
        xx = best[3] + rng.normal(0, 0.6 if i < it // 2 else 0.25, 10) * sc
        r = ev(s, xx, P0)
        if r[0] < best[0]: best = (*r, xx)
    if not s["two"]:                                   # 오른팔: 주먹 목표 둘레(±1 스터드)·팔꿈치 방향에서 겹침 최소
        c0, P, info, x0 = best; cand = []
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for pol in ((1, -0.7, 0.2), (1, 0, 0), (1, -1, -0.5), (0.6, -1, 0.4)):
                        Q = fist_right(P, np.array(s["fistR"]) + (dx, dy, dz), pol)
                        cand.append((K.fast2(Q) + 0.5 * (dx * dx + dy * dy + dz * dz), Q))
        cand.sort(key=lambda t: t[0]); P = cand[0][1]; info["clash"] = K.fast2(P)
        best = (c0, P, info, x0)
    return best


if __name__ == "__main__":
    import hview as H
    import os
    out = json.load(open(SP + "spin_keys_r10.json")) if sys.argv[1:] and os.path.exists(SP + "spin_keys_r10.json") else {}
    rows = []
    for n in (sys.argv[1:] or ["SW", "SX", "SF"]):
        c, P, info, x = solve(n)
        print(n, "cost", round(c, 1), {k: round(v, 2) for k, v in info.items() if k != "pr"}, "다리 겹침", leg_clash(P), "Root 내림", round(P["Root"][1, 3], 2), flush=True)
        out[n] = dict(P={k: m.tolist() for k, m in P.items()}, pr=info["pr"], two=SPEC[n]["two"])
        ims = [V.render(P, yaw=y, pitch=p, ppc=1.25) for y, p in ((0, 4), (35, 10), (0, 80), (155, 18))]
        rows.append(H.ksheet(ims, ["정면", "앞 3/4", "위", "게임 카메라"], title={"SW": "① 모으기 (한 손 · 몸 앞 오른 허리 아래로 감아 쥠)", "SX": "② 휘두름 (허리 높이 · 기마 자세 — 이 자세로 왼쪽 한 바퀴 0.33초)", "SF": "③ 멈춤 (칼 옆 뒤 아래로 흘림)", "SR": "④ 겨눔으로 돌아가는 경유"}[n], bg=(128, 142, 160), fs=15))
    json.dump(out, open(SP + "spin_keys_r10.json", "w"))
    from PIL import Image
    W_ = max(r.width for r in rows); S = Image.new("RGB", (W_, sum(r.height for r in rows)), (128, 142, 160)); y = 0
    for r in rows: S.paste(r, (0, y)); y += r.height
    S.save(SP + ("valk_spin_keys_r10.png" if not sys.argv[1:] else "valk_spin_keys_r10_" + "_".join(sys.argv[1:]) + ".png")); print(S.size)
