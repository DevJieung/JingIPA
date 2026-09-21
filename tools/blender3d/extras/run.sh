#!/bin/bash
# 3D 길에만 있는 이점 셋 + 보고 자료 — 한 줄로 (전체 약 90초, 그중 60초가 Godot 실기 둘)
#   tools/blender3d/extras/run.sh
# ★ 쓰는 곳은 build/b3d/extras/ 뿐이다. tools/blender3d/mk/ 는 읽고 import 만 한다.
set -euo pipefail
cd "$(dirname "$0")/../../.."
BL="env -u DISPLAY bl -b --factory-startup --python tools/blender3d/extras/bl_render.py --"

echo "== 1 · 속성 5벌 리컬러 (렌더)"
$BL --job recolor 2>&1 | grep -E 'RECOLOR_JSON|칸 ·|Error'
echo "== 1 · 양자화 + 대조표"
python3 tools/blender3d/extras/recolor.py

echo "== 2 · 8방향 (렌더)"
$BL --job dirs8 2>&1 | grep -E 'DIRS8_JSON|8방향|Error'
echo "== 2 · 양자화 + 대조표"
python3 tools/blender3d/extras/dirs.py

echo "== 3 · 칸마다의 시간 (pack + qc + Godot 실기)"
python3 tools/blender3d/extras/timing.py

echo "== 4 · 보고 자료"
python3 tools/blender3d/extras/report.py
