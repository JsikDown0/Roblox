# ST-10 BISON (양산형, 컨셉 표기 R-03) 모델 파일 (flag_vox/1 JSON)

| 파일 | 내용 | 삼각형 |
|---|---|---|
| `BISON_full.json` | 원래 해상도(칸 0.05) · **28 파트(몸 23 + 무장 5)** · 섬 0 · 파트당 1만 미만 · 두께 B(몸통·골반·다리 앞뒤 ×1.15) | 35,838 |

- 만드는 코드: `mech/code/mass/mass_final.py` (→ `mass_hose_r1` B1 → `mass_leg_r4` → `mass_leg_r3` → `mass_leg_r2` → `mass_arm_r2` f → `mass_shoulder_r3` → `mass_chest_r4` a → `mass_head_r5` A …).
  다시 만들기: `cd mech/code/mass && python3 mass_final.py <그림 폴더> ../../models/BISON` (`build_armed()` = 몸 + 무장, `build_body()` = 무장 전 몸)
- 무장 파트: `Rifle`(부모 HandR, 개머리 K2) · `RifleStowed`(부모 UpperLegR, 오른 허벅지 바깥 세로) — 둘 중 하나만 보임 · `RifleMount`(부모 UpperLegR, 간이 거치대 H1: 허벅지 받침판 + 팔 2 + 리시버 고리 2) · `Shield`(부모 LowerArmL, 방패 치기 = R) · `SaberHilt`(부모 Pelvis, 왼 허리 뒤, 빔사벨 = 근접).
- 관절 계층: Pelvis(뿌리) → Torso → Head · ShoulderL(→ PlateF · PlateB) · ShoulderR · UpperArmL/R → LowerArmL/R → HandL/R /
  Pelvis → UpperLegL/R → LowerLegL/R(→ PistonCylL/R) → FootL/R(→ PistonRodL/R).
- 쉬는 자세: 팔 9° 벌림(`UpperArm roty ∓9`) · 다리 굽힘은 rot 에 구워져 있음(허벅지 −6° · 정강이 +10° · 발 −4°).
- 색 번호: 1 회올리브 (102,103,82) · 2 짙은 쇠 회색 · 3 짙은 프레임 · 4 검정(홈·호스) · 5 노랑(피스톤 띠) · 6 주황 발광(바이저만) · 7 강철(금속) · 8 크롬(금속, 피스톤 로드 — 공용 팔레트에 없는 새 칸).
- 금속 = 7·8 · 발광 = 6.
- **회전을 메시에 굽지 말 것**(Studio 에서 CFrame 으로 돌림): PlateF · PlateB(데칼 면) · PistonCyl/Rod L/R(매 프레임 구동). 구동 = `mech/studio/mass_piston.lua`.
- 데칼 자리(평평하게 비워 둠): 왼 어깨 PlateF 바깥("03") · PlateB 바깥(부대 표식, 게임 카메라 쪽) · 허벅지 앞 판(R-03) · 발목 커프 앞 판 · 뒤꿈치 블록 · 흉판(엠블럼) · 경고 줄무늬(복셀엔 없음, 데칼로).
