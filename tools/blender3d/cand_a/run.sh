#!/bin/bash
# 후보 A — 2·3·4단계(build) → 5단계(render) → 6단계+시트(finish) → 대조표. 한 줄.
#
#   tools/blender3d/cand_a/run.sh
#
# ★ Xvfb 를 쓰지 마라 — 헤드리스가 EGL 로 GPU 를 직접 잡아 2.6배 빠르다.
# ★ 렌더는 **한 프로세스 안에서** 다 돈다. 프레임마다 blender 를 띄우면 EEVEE 의
#   GPU 컨텍스트 잡는 1초가 매번 든다.
set -euo pipefail
cd "$(dirname "$0")/../../.."
OUT=${1:-build/b3d/cand_a}
BLEND="$OUT/2_model/jokull.blend"

echo "== 2·3·4단계 — 메시 + 재질 + 리그 + 액션"
env -u DISPLAY bl -b --factory-startup --python tools/blender3d/cand_a/build.py -- \
    --out "$BLEND" 2>&1 | grep -E "BUILD_JSON|Error"

echo "== 5단계 — 직교 툰 렌더 (96x96 · filter 0 · Standard)"
env -u DISPLAY bl -b --factory-startup --python tools/blender3d/cand_a/render.py -- \
    --blend "$BLEND" --out "$OUT/5_frames" 2>&1 | grep -E "RENDER_JSON|Error"

echo "== 6단계 — post.clean_one (공식 pixels.py) + 시트 + 잣대"
python3 tools/blender3d/cand_a/finish.py "$OUT"

echo "== 대조표"
python3 tools/blender3d/cand_a/contact.py "$OUT" "$OUT/contact.png"
