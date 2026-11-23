"""무쌍 B노선 장난감 시뮬. 모든 계수는 [추측]. 경향 비교용이지 수치 예측용이 아니다.
판: 공격 4장수 vs 수비 4장수, 8분. 성문(600) -> 거점1(100) -> 거점2(100). 거점2 완료 = 공격 승.
"""
import random, statistics as st

TYPES = ["spear", "archer", "cav", "shield"]
HITS = {"spear": 1, "archer": 1, "cav": 1, "shield": 2}
POP = {"spear": 1, "archer": 1, "cav": 2, "shield": 1}
# 병사끼리 상성 배수: ADV[a][b] = a 가 b 를 잡는 속도 배수
ADV = {t: {u: 1.0 for u in TYPES} for t in TYPES}
ADV["spear"]["cav"] = 3; ADV["cav"]["archer"] = 3; ADV["archer"]["spear"] = 2
ADV["shield"]["archer"] = 2; ADV["cav"]["shield"] = 2; ADV["archer"]["shield"] = 0.3
ADV["cav"]["spear"] = 0.4
CHIP = {"spear": 0.10, "archer": 0.30, "cav": 0.15, "shield": 0.05}   # 장수에게 주는 초당 피해
GATE = {"spear": 0.5, "archer": 0.2, "cav": 2.0, "shield": 0.4}
FORM = {  # 진법: 무쌍 노출, 점령배수, 성문배수, 받는 기병 배수, 받는 궁병 배수
    "basic": dict(ult=0.5, cap=1.0, gate=1.0, vs_cav=1.0, vs_arch=1.0),
    "circle": dict(ult=0.8, cap=1.0, gate=1.0, vs_cav=0.4, vs_arch=1.0),
    "wing": dict(ult=0.25, cap=1.5, gate=1.0, vs_cav=1.6, vs_arch=1.0),
    "wedge": dict(ult=0.5, cap=1.0, gate=1.5, vs_cav=1.0, vs_arch=1.5),
}

def run(cfg, rng):
    T = 480
    sides = ("A", "D")
    sol = {s: {t: 0.0 for t in TYPES} for s in sides}
    gen_hp = {s: [100.0] * 4 for s in sides}
    respawn = {s: [0] * 4 for s in sides}
    gauge = {s: [0.0] * 4 for s in sides}
    skill = {"A": cfg.get("skillA", 0.5)}
    gate, cap1, cap2 = 600.0, 0.0, 0.0
    phase = 0
    st_ = dict(gen_on_sol=0, gen_secs=0, kills=0, ults=0, gen_deaths=0)
    st_["solA"] = st_["solD"] = 0
    for t in range(T):
        # 물결
        if t % 15 == 0 and cfg["soldiers"]:
            for s, n in (("A", cfg.get("waveA", 40)), ("D", cfg.get("waveD", 36))):
                comp = cfg["comp" + s]
                tot = sum(sol[s].values())
                for ty, frac in comp.items():
                    add = n * frac / POP[ty]
                    if tot + add > 300: add = max(0, 300 - tot)
                    sol[s][ty] += add; tot += add
        alive = {s: [i for i in range(4) if respawn[s][i] <= t] for s in sides}
        nsol = {s: sum(sol[s].values()) for s in sides}
        # 장수 행동 정책: 적 병사 10 이상이면 쓸기, 아니면 일기토 / 목표
        kills_by = {s: {t_: 0.0 for t_ in TYPES} for s in sides}
        duelers = {s: [] for s in sides}
        for s in sides:
            o = "D" if s == "A" else "A"
            for i in alive[s]:
                st_["gen_secs"] += 1
                if rng.random() < min(1.0, nsol[o] / cfg.get("sweep_th", 30)):
                    st_["gen_on_sol"] += 1
                    # 무쌍
                    if gauge[s][i] >= 100:
                        gauge[s][i] = 0; st_["ults"] += 1
                        f = FORM[cfg["form" + o]]["ult"]
                        hit = min(40.0, nsol[o] * f)  # 반경 안에 든 병사, 최대 40
                        for ty in TYPES:
                            if nsol[o] > 0:
                                kills_by[s][ty] += hit * sol[o][ty] / nsol[o]
                        continue
                    rate = 2.0 * cfg.get("sweep_mul", 1.0) * (cfg.get("sweepA", 1.0) if s == "A" else 1.0)  # 초당 일반공격 쓸기 (1타 기준)
                    for ty in TYPES:
                        if nsol[o] > 0:
                            share = sol[o][ty] / nsol[o]
                            kills_by[s][ty] += rate * share / HITS[ty]
                    gauge[s][i] += rate * 0.4 * cfg.get("gain_mul", 1.0)
                else:
                    duelers[s].append(i)
        # 병사끼리 소모 (Lanchester 선형)
        loss = {s: {t_: 0.0 for t_ in TYPES} for s in sides}
        if cfg["soldiers"]:
            for s in sides:
                o = "D" if s == "A" else "A"
                fo = FORM[cfg["form" + o]]
                if nsol[o] <= 0: continue
                for a in TYPES:
                    if sol[s][a] <= 0: continue
                    for b in TYPES:
                        if sol[o][b] <= 0: continue
                        m = ADV[a][b]
                        if a == "cav": m *= fo["vs_cav"]
                        if a == "archer": m *= fo["vs_arch"]
                        loss[o][b] += 0.006 * sol[s][a] * m * sol[o][b] / nsol[o]
        for s in sides:
            for ty in TYPES:
                k = kills_by[s][ty]
                o = "D" if s == "A" else "A"
                st_["kills"] += min(k, sol[o][ty])
                loss[o][ty] += k
        for s in sides:
            for ty in TYPES:
                sol[s][ty] = max(0.0, sol[s][ty] - loss[s][ty])
        nsol = {s: sum(sol[s].values()) for s in sides}
        st_["solA"] += nsol["A"]; st_["solD"] += nsol["D"]
        # 병사 -> 장수 피해 (근처 무리 일부만 닿는다: 1/3)
        for s in sides:
            o = "D" if s == "A" else "A"
            chip = sum(sol[o][ty] * CHIP[ty] for ty in TYPES) / 3 * cfg.get("chip_mul", 1.0)
            if alive[s]:
                per = chip / len(alive[s])
                for i in alive[s]:
                    gen_hp[s][i] -= per
                    gauge[s][i] += per * 0.5
        # 일기토
        da, dd = duelers["A"], duelers["D"]
        pairs = min(len(da), len(dd))
        for p in range(pairs):
            if rng.random() < 1 / 30:
                win = "A" if rng.random() < skill["A"] else "D"
                lose = "D" if win == "A" else "A"
                idx = (dd if lose == "D" else da)[p]
                gen_hp[lose][idx] = 0
                gauge[win][(da if win == "A" else dd)[p]] += 1.5 * 10
        # 사망 처리
        for s in sides:
            for i in range(4):
                if respawn[s][i] <= t and gen_hp[s][i] <= 0:
                    respawn[s][i] = t + 10; gen_hp[s][i] = 100; st_["gen_deaths"] += 1
        freeA = len(da) - pairs
        freeD = len(dd) - pairs
        # 목표
        if phase == 0:
            g = sum(sol["A"][ty] * GATE[ty] for ty in TYPES) * FORM[cfg["formA"]]["gate"]
            g += 3.0 * freeA
            if cfg.get("flank") and sol["D"]["spear"] < 5:
                g += sol["A"]["cav"] * 2.0  # 측면 성문 돌파
            gate -= g
            if gate <= 0: phase = 1; st_["t_gate"] = t
        else:
            atk = nsol["A"] + freeA
            dfn = nsol["D"] + 3 * freeD  # 수비 장수 1 = 병사 3 몫
            if cfg.get("gen_gate") and freeD > 0: pass  # 수비 장수가 거점에 있으면 점령 정지
            elif atk > dfn:
                r = 2.7 * cfg.get("capk", 1.0) * FORM[cfg["formA"]]["cap"] * (atk - dfn) / (atk + dfn)
                if phase == 1:
                    cap1 += r
                    if cap1 >= 100: phase = 2; st_["t_cap1"] = t
                else:
                    cap2 += r
                    if cap2 >= 100:
                        st_["win"] = 1; st_["t_end"] = t; break
    st_.setdefault("win", 0); st_.setdefault("t_end", T)
    st_["solA"] /= max(1, st_["t_end"]); st_["solD"] /= max(1, st_["t_end"])
    st_["kpm"] = st_["kills"] / 8 / (st_["t_end"] / 60) if st_["t_end"] else 0
    return st_

BASE = dict(soldiers=True, compA={"spear": .5, "archer": .25, "shield": .25},
            compD={"spear": .5, "archer": .25, "shield": .25}, formA="basic", formD="basic")

def scen(**kw):
    c = dict(BASE); c.update(kw); return c

SCEN = [
    ("S0 기준(창·궁·방패 혼합, 기본진)", scen()),
    ("S1 병사 없음(대조군)", scen(soldiers=False)),
    ("S2 공격 기병 40% + 측면돌파", scen(compA={"spear": .3, "archer": .2, "cav": .4, "shield": .1}, flank=True)),
    ("S3 S2 + 수비 방원진·창병 70%", scen(compA={"spear": .3, "archer": .2, "cav": .4, "shield": .1}, flank=True,
                                     compD={"spear": .7, "archer": .15, "shield": .15}, formD="circle")),
    ("S4 S3 + 공격 무쌍 게이지 2배", scen(compA={"spear": .3, "archer": .2, "cav": .4, "shield": .1}, flank=True,
                                    compD={"spear": .7, "archer": .15, "shield": .15}, formD="circle", gain_mul=2)),
    ("S5 S4 인데 수비가 학익진으로 바꿈", scen(compA={"spear": .3, "archer": .2, "cav": .4, "shield": .1}, flank=True,
                                       compD={"spear": .7, "archer": .15, "shield": .15}, formD="wing", gain_mul=2)),
    ("S6 공격 장수 실력 우위(일기토 60%)", scen(skillA=0.6)),
    ("S7 S6 + 수비 궁병 50%·학익진", scen(skillA=0.6, compD={"spear": .3, "archer": .5, "shield": .2}, formD="wing")),
    ("S8 공격 장수 큰 우위(일기토 75%)", scen(skillA=0.75)),
    ("S9 CAA식 강한 병사(피해 4배, 쓸기 1/3)", scen(chip_mul=4, sweep_mul=1/3)),
]

SOFT = dict(circle=dict(ult=0.6, vs_cav=0.6), wing=dict(ult=0.4, cap=1.2, vs_cav=1.3))  # 진법 완화판
BIG = dict(waveA=100, waveD=90, gen_gate=True, capk=0.6)
SCEN2 = [("B0 기준", scen(**BIG)), ("B1 장수 60%", scen(**BIG, skillA=0.6)), ("B2 장수 40%", scen(**BIG, skillA=0.4)),
         ("B3 쓸기 1.2배", scen(**BIG, sweepA=1.2)), ("B4 쓸기 0.8배", scen(**BIG, sweepA=0.8)),
         ("B5 수비 방원진", scen(**BIG, formD="circle")), ("B6 수비 학익진", scen(**BIG, formD="wing"))]

if __name__ == "__main__":
    import sys
    N = int(sys.argv[1]) if len(sys.argv) > 1 else 400
    def table(lst):
      for name, c in lst:
        yield name, c
    print("시나리오|공격승률|평균종료(초)|성문함락(초)|장수 처치/분|장수 시간 중 병사 처리|무쌍/판|장수 사망/판")
    for name, c in SCEN + [("--- 2차(진법 완화판 적용) ---", None)] + SCEN2:
        if c is None:
            for k, v in SOFT.items(): FORM[k].update(v)
            print(name); continue
        rs = [run(c, random.Random(i)) for i in range(N)]
        w = st.mean(r["win"] for r in rs)
        te = st.mean(r["t_end"] for r in rs)
        tg = [r["t_gate"] for r in rs if "t_gate" in r]
        tg = st.mean(tg) if tg else float("nan")
        kpm = st.mean(r["kpm"] for r in rs)
        on = st.mean(r["gen_on_sol"] / max(1, r["gen_secs"]) for r in rs)
        ul = st.mean(r["ults"] for r in rs)
        gd = st.mean(r["gen_deaths"] for r in rs)
        sa = st.mean(r["solA"] for r in rs); sd = st.mean(r["solD"] for r in rs)
        print(f"{name}|{w:.0%}|{te:.0f}|{tg:.0f}|{kpm:.1f}|{on:.0%}|{ul:.1f}|{gd:.1f}|{sa:.0f}/{sd:.0f}")
