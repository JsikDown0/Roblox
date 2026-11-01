로봇차기작 코드 묶음 (2026-11-01) — 프로젝트 claude/로봇차기작/ 의 .py / .lua 107개, 폴더 구조 그대로.
- 대표기체_시안/*_r2, *_r1 파일은 서로 import 할 때 접미사 없는 이름(flagship_heavy, final_m2b, heavy_heads ...)을 쓴다. 실행하려면 이름을 맞춰 복사해야 한다.
- 승리포즈/*.py 는 aero_export, aero_r1, aero_colors, vox_preview, flag_vox 를 다른 폴더에서 import 한다 → 같은 폴더에 모으거나 PYTHONPATH 에 추가.
- 프로젝트에 없어 빠진 것: pads, nova_mesh, bust (모듈) / heavy_rig.json, tunnel.json, heavy_pose_dump.json, ref/ref_mesh.npz (데이터) / VALKYRIE 날개 파일(valk_*).
