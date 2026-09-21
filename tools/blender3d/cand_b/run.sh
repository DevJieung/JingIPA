#!/usr/bin/env bash
# 후보 B — 2·3·4단계(build) → 5단계(render) → 6단계(post) + 시트 + 대조표 를 한 번에.
#
#   tools/blender3d/cand_b/run.sh
#
# ★ Xvfb 를 쓰지 마라 — 헤드리스가 EGL 로 GPU 를 바로 잡아 2.6배 빠르다.
# ★ 렌더는 **한 프로세스 안에서** 20장을 다 돈다(EEVEE 컨텍스트 1초를 한 번만 낸다).
set -euo pipefail
cd "$(dirname "$0")/../../.."          # 저장소 뿌리
BL="${BL:-bl}"
D=tools/blender3d/cand_b

t0=$(date +%s.%N)
env -u DISPLAY "$BL" -b --factory-startup --python $D/build.py  -- "$@" | grep -E 'BUILD_JSON|MATHIST|Error' || true
env -u DISPLAY "$BL" -b --factory-startup --python $D/render.py -- "$@" | grep -E 'RENDER_JSON|Error' || true
python3 $D/pack.py
t1=$(date +%s.%N)
echo "TOTAL_SEC $(echo "$t1 - $t0" | bc)"
echo "산출물: build/b3d/cand_b/  (contact.png · jokull_idle.png · jokull_attack.png · metrics.json · anim.json)"
