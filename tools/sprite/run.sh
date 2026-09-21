#!/usr/bin/env bash
# 스프라이트 파이프라인 한 번에 (docs/SPRITE.md).
#   tools/sprite/run.sh sdxl            # 원화 고르기까지는 사람이 한다
#   tools/sprite/run.sh sdxl clips      # 골라 둔 것으로 클립부터 끝까지
set -euo pipefail
cd "$(dirname "$0")/../.."
ROUTE="${1:-sdxl}"
FROM="${2:-ref}"

if [ "$FROM" = "ref" ]; then
    python3 tools/sprite/make_ref.py --route "$ROUTE" --tries 3
    python3 tools/sprite/refine.py --route "$ROUTE" --contact
    echo "★ build/sprite/contact_${ROUTE}.png 를 눈으로 보고 고른 뒤:"
    echo "   python3 tools/sprite/refine.py --route $ROUTE --pick <id>=<번호> …"
    echo "   tools/sprite/run.sh $ROUTE clips"
    exit 0
fi

python3 tools/sprite/wan_i2v.py     --route "$ROUTE"
python3 tools/sprite/sprite_post.py --route "$ROUTE"
python3 tools/sprite/preview.py     --route "$ROUTE"

# 엔진 반입 — Godot 이 build/ 를 안 읽으므로(.gdignore) art/ 로 옮겨야 임포트된다
mkdir -p "art/sprite/$ROUTE"
cp -f "build/sprite/$ROUTE/sheets/"*.png "art/sprite/$ROUTE/"
~/.local/bin/godot --headless --path . --import >/dev/null 2>&1 || true
python3 tools/sprite/shot_sprite.py --route "$ROUTE"
echo "끝 — build/sprite/board_${ROUTE}.png · build/sprite/godot_${ROUTE}_*.png"
