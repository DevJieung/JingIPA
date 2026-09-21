#!/usr/bin/env bash
# 쉰 명 스프라이트를 원화부터 엔진 반입까지 한 번에 (docs/SPRITE.md).
#   gpujob run pd-sprite tools/sprite/run50.sh
# ★ GPU 를 쓰는 것은 1·3 단계뿐이고 2·4·5 는 CPU 다. 한 유닛에 묶어 두는 까닭은
#   차례가 어긋나면 안 되기 때문이다 — 클립은 마스터가 있어야 하고 시트는 클립이
#   있어야 한다.
set -euo pipefail
cd "$(dirname "$0")/../.."
echo "=== 1/7 원화 50장 (Krea2 · 약 55분) ==="
python3 tools/sprite/make_ref.py --route krea
echo "=== 2/7 마스터 96 + Wan 입력 512 (CPU) ==="
python3 tools/sprite/refine.py --route krea --all
echo "=== 3/7 클립 100장 (Wan 2.2 I2V · 약 45분) ==="
# ★ 다른 길: MiniMax H3 (docs/SPRITE.md 6 — 정체성·되돌아오기가 낫고, 백 장에 ~3.8시간).
#   아래 한 줄을 이것으로 바꾼다. 서버(~/pjt/h3/serve.sh · 8199)가 떠 있어야 한다. 1단계의
#   Krea2 와는 같은 순간에 못 뜨는데, 그것은 tools/gpu_guard.py 가 알아서 한다 — Krea2 를
#   올리기 전에 H3 의 메모리를 비우고, H3 를 부르기 전에 Krea2 가 없는지 본다.
#   python3 tools/sprite/h3_i2v.py --route krea --tag ""
python3 tools/sprite/wan_i2v.py --route krea
echo "=== 4/7 클립 구간 고치기 — 다리 놓기 (약 6분 · docs/PIXELLAB.md 3-2) ==="
# ★ 무엇을 고칠지는 tools/sprite/repairs.json 에 적혀 있다. build/ 는 gitignore 라
#   그 표가 없으면 다시 구울 때마다 그 캐릭터가 조용히 옛 결함으로 되돌아간다
#   (units.SEED · anim/rig_overrides.json 과 같은 규칙이다).
# ★ scan 은 GPU 를 안 쓴다. 표에 없는 **새** 결함이 생겼는지를 로그에 남겨 둔다 —
#   씨앗이나 프롬프트를 만진 날 여기서 먼저 보인다.
python3 tools/sprite/repair.py --route krea --scan
python3 tools/sprite/repair.py --route krea --apply

echo "=== 5/7 시트 100장 + 품질 검사 (CPU) ==="
python3 tools/sprite/sprite_post.py --route krea
echo "=== 6/7 엔진 반입 ==="
mkdir -p art/sprite/krea
rm -f art/sprite/krea/*.png art/sprite/krea/*.import
cp -f build/sprite/krea/sheets/*.png art/sprite/krea/
python3 tools/sprite/to_game.py --route krea --clean
echo "=== 7/7 임포트 + 총구·뻗는 시간 다시 재기 ==="
# ★ 임포트를 빼먹으면 Godot 이 **옛 캐시**를 그대로 쓴다 (CLAUDE.md 10-12).
~/.local/bin/godot --headless --path . --import >/dev/null 2>&1 || true
# ★ 총구(muz)와 뻗는 시간(wind)이 art/anim/<id>/anim.json 에서 나온다 —
#   이걸 안 돌리면 총구 불꽃만 손끝에 있고 탄은 옛 자리에서 나간다 (CLAUDE.md 18-8).
python3 tools/gen_roster.py
echo "끝 — 다음은 tools/verify.sh"
