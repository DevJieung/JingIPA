#!/bin/bash
# 최종본 — 0단계부터 엔진 실기까지 한 줄. 전체가 **20초 안쪽**에 돈다.
#
#   tools/blender3d/mk/run.sh            # 엔진 실기까지
#   tools/blender3d/mk/run.sh --no-engine
#
# ★ Xvfb 를 쓰지 마라 — 헤드리스가 EGL 로 GPU 를 직접 잡아 2.6배 빠르다.
#   (엔진 실기 단계만 Xvfb 를 쓴다. Godot 헤드리스는 그리지 않는다)
# ★ 렌더는 **한 프로세스 안에서** 다 돈다.
set -euo pipefail
cd "$(dirname "$0")/../../.."
UNIT=${UNIT:-jokull}
ELEM=${ELEM:-ice}
ZOOM=${ZOOM:-1.05}
BLEND="build/b3d/$UNIT/2_model/$UNIT.blend"
SHEET="build/b3d/$UNIT/7_sheet"

echo "== 0단계 — 스펙·팔레트"
python3 tools/blender3d/spec.py --unit "$UNIT" | sed 's/^/   /'
echo "== 0단계 — 3면도에서 부위색 뽑기"
python3 tools/blender3d/mk/parts.py | tail -1 | sed 's/^/   /'

echo "== 2·3·4단계 — 메시 + 재질 + 리그 + 액션"
env -u DISPLAY bl -b --factory-startup --python tools/blender3d/mk/build.py -- \
    --out "$BLEND" 2>&1 | grep -E "BUILD_JSON|Error" | cut -c1-220

echo "== 5단계 — 직교 툰 렌더 + 내부 선화 + meta.json"
env -u DISPLAY bl -b --factory-startup --python tools/blender3d/mk/render.py -- \
    --blend "$BLEND" --unit "$UNIT" --elem "$ELEM" --zoom "$ZOOM" 2>&1 \
    | grep -E "RENDER_JSON|Error"

echo "== 6단계 — post.clean_one (공식 pixels.py 그대로)"
python3 tools/blender3d/post.py --unit "$UNIT" --elem "$ELEM" | tail -3

echo "== 7단계 — 시트 + anim.json + atlas + preview"
python3 tools/blender3d/pack.py --unit "$UNIT" | tail -3

echo "== 검사 12가지"
#  ★ `--dir` 를 못 쓴다 — pack 이 같은 자리에 굽는 atlas.png(768x960)를 qc 가
#    스트립으로 읽으려다 ValueError 로 죽는다. 시트를 직접 준다.
python3 tools/blender3d/qc.py \
    --sheets "$SHEET/${UNIT}_idle.png,$SHEET/${UNIT}_walk.png,$SHEET/${UNIT}_attack.png" \
    --anim-json "$SHEET/anim.json" \
    --dirs "build/b3d/$UNIT/6_clean/idle" \
    --out "$SHEET/qc.json" | tail -18

echo "== 내부 선화가 얼마나 벌었나"
python3 tools/blender3d/mk/probe_lines.py

echo "== 대조표"
python3 tools/blender3d/mk/contact.py

if [ "${1:-}" != "--no-engine" ]; then
  echo "== 엔진 실기 (Godot + Xvfb)"
  python3 tools/blender3d/engine_check.py --unit "$UNIT" | tail -2
fi
