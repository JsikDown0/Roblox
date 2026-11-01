#!/usr/bin/env bash
# Prepare a cloud session to run the mech voxel tools.
# Usage: bash mech/tools/setup_cloud.sh [work_dir]
# Builds a flat work folder: heavy/ (flagship_tools + rig + 대표기체_시안 with _r2/_r1 suffix removed)
# and skadi/ (저격기_복셀이식). Then: cd <work>/heavy && python final_m2b.py <out_dir>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../code" && pwd)"
WORK="${1:-/tmp/mechwork}"
pip install -q numpy scipy pillow matplotlib numba pygltflib
if [ ! -f /usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc ]; then
  (apt-get install -y -q fonts-noto-cjk || (apt-get update -q && apt-get install -y -q fonts-noto-cjk)) >/dev/null
fi
rm -rf "$WORK"; mkdir -p "$WORK/heavy" "$WORK/skadi" "$WORK/victory"
cp "$ROOT"/flagship_tools/*.py "$ROOT"/flagship_tools/rig/*.py "$WORK/heavy/"
for f in "$ROOT"/대표기체_시안/*.py; do b="$(basename "$f" .py)"; b="${b%_r2}"; cp "$f" "$WORK/heavy/${b}.py"; done
cp "$ROOT"/대표기체_시안/*.py "$WORK/heavy/" 2>/dev/null || true   # keep suffixed originals too (aero_r1 etc.)
cp "$ROOT"/저격기_복셀이식/*.py "$WORK/skadi/"
cp "$WORK"/heavy/*.py "$WORK/victory/"; cp "$ROOT"/승리포즈/*.py "$WORK/victory/"
echo "work dir: $WORK  (heavy/ skadi/ victory/)"
