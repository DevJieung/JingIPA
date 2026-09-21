#!/usr/bin/env bash
# 후보 C — 0→7 을 한 줄로. 저장소 안에는 tools/blender3d/cand_c/ 와 build/b3d/cand_c/ 만 건드린다.
#
#   tools/blender3d/cand_c/run.sh
#
# ★ Xvfb 를 쓰지 마라 — 헤드리스가 EGL 로 GPU 를 직접 잡아 2.6배 빠르다.
# ★ 프레임마다 blender 를 새로 띄우지 않는다. render.py 가 **한 프로세스**에서 다 돈다.
set -euo pipefail
cd "$(dirname "$0")/../../.."      # 저장소 뿌리
BL="${BL:-bl}"
C=tools/blender3d/cand_c

echo "== 0  원화에서 색·투영 텍스처 뽑기 (시스템 파이썬 · PIL)"
python3 $C/prep_tex.py

echo "== 2·3·4  메시 + 재질 + 리그 + 액션 → .blend"
env -u DISPLAY $BL -b --factory-startup --python $C/build.py -- --proj "${PROJ:-se}" \
  2>&1 | grep -E '^BUILD_JSON' || true

echo "== 5  직교 툰 렌더 (부위색 flat — 채택본)"
env -u DISPLAY $BL -b --factory-startup --python $C/render.py -- --variant flat \
  2>&1 | grep -E '^RENDER_JSON' || true

echo "== 5b 직교 툰 렌더 (원화 텍스처 투영 tex — 견주기용)"
env -u DISPLAY $BL -b --factory-startup --python $C/render.py -- --variant tex \
  2>&1 | grep -E '^RENDER_JSON' || true

echo "== 6·7  양자화 + 1도트 테두리 + 시트 + 잣대"
python3 $C/sheet.py --variant flat
python3 $C/sheet.py --variant tex > /dev/null

echo "== 대조표"
python3 $C/contact.py
