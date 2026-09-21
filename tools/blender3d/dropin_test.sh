#!/usr/bin/env bash
# ★ 「정말로 게임에 꽂히는가」를 게임의 **자기 검사기**로 확인한다 — 그리고 되돌린다.
#
#   tools/blender3d/dropin_test.sh jokull
#
# 하는 일: 3D 시트를 art/anim/<id>/ 에 **잠깐** 얹고 → 임포트 → gen_roster → ns_check --strict
#          → 무슨 일이 있어도 **원래대로 되돌리고, 되돌아갔는지 체크섬으로 확인**한다.
#
# ★ 이 검사가 필요한 까닭: engine_check.py 는 Godot 안에서 시트가 제대로 잘리고 그려지는지만
#   본다. 그런데 계약에는 화면 밖의 것이 더 있다 — `gen_roster.py` 가 anim.json 의
#   `muzzle_at`/`hit_ms` 를 `core/roster.gd` 의 `muz`/`wind` 로 옮기고, `ns_check._check_muzzle`
#   이 **세 파일을 나란히 놓고** 잰다. 그 사슬은 실제로 얹어 보지 않으면 확인할 길이 없다.
#
# ★★ **git 으로 되돌리지 마라.** 이 저장소에서 `art/anim/` 은 아직 **커밋되지 않은**
#    파일이고 `core/roster.gd` 에도 수정본이 있다. `git checkout` 은 커밋 안 된 파일을
#    되살리지 못하고 `git clean -fd` 는 그것을 **영영 지운다** — 사용자의 작업분이 날아간다.
#    그래서 되돌리기는 오직 **파일 복사 백업**으로만 한다.
set -uo pipefail
cd "$(dirname "$0")/../.."

ID=${1:-jokull}
SRC="build/b3d/$ID/7_sheet"
DST="art/anim/$ID"
GODOT="$HOME/.local/bin/godot"
BK="$(mktemp -d /tmp/b3d-dropin-XXXXXX)"

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
sums() { find "$DST" -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null; }

[ -f "$SRC/anim.json" ] || { echo "!! 3D 시트가 없다: $SRC/anim.json"; exit 2; }
[ -d "$DST" ] || { echo "!! 원본이 없다: $DST"; exit 2; }

# 1) 백업 — 이것이 유일한 되돌림 길이다
say "1. 백업 (git 이 아니라 파일 복사)"
cp -a "$DST" "$BK/anim" || { echo "!! 백업 실패 — 중단한다"; exit 2; }
cp -a core/roster.gd "$BK/roster.gd" || { echo "!! 백업 실패 — 중단한다"; exit 2; }
sums > "$BK/before.sha256"
BEFORE_ROSTER=$(sha256sum core/roster.gd | cut -d' ' -f1)
echo "   $BK 에 $(wc -l < "$BK/before.sha256") 개 파일 + roster.gd"

restore() {
	say "되돌리기"
	rm -rf "$DST"
	cp -a "$BK/anim" "$DST"
	cp -a "$BK/roster.gd" core/roster.gd
	# 임포트 캐시도 원래 파일 기준으로 다시 만든다 (안 하면 옛 .ctex 가 남는다)
	timeout 300 "$GODOT" --headless --path . --import >/dev/null 2>&1
	rm -rf "$DST"; cp -a "$BK/anim" "$DST"          # 임포트가 .import 를 건드렸을 수 있다
	cp -a "$BK/roster.gd" core/roster.gd
	local after_roster; after_roster=$(sha256sum core/roster.gd | cut -d' ' -f1)
	if diff -q <(sums) "$BK/before.sha256" >/dev/null 2>&1 && [ "$after_roster" = "$BEFORE_ROSTER" ]; then
		printf '   \033[32m원래대로 — 체크섬 일치\033[0m (백업은 %s 에 남겨 둔다)\n' "$BK"
	else
		printf '   \033[31m!! 되돌리기가 덜 됐다. 손으로 복구해라: cp -a %s/anim/. %s/\033[0m\n' "$BK" "$DST"
		diff <(sums) "$BK/before.sha256" | head -20
	fi
}
trap restore EXIT

# 2) 얹는다
say "2. 3D 시트를 $DST/ 에 얹는다"
cp -f "$SRC"/*.png "$DST"/ 2>/dev/null
cp -f "$SRC/anim.json" "$DST/anim.json"
ls "$DST"

# 3) 임포트 — 안 하면 Godot 이 옛 .ctex 캐시를 쓴다 (CLAUDE.md 10-12)
say "3. godot --import"
timeout 300 "$GODOT" --headless --path . --import 2>&1 | grep -iE "error" | head -5

# 4) anim.json → core/roster.gd 의 muz · wind
say "4. gen_roster.py"
python3 tools/gen_roster.py 2>&1 | tail -3
grep -n "\"$ID\"" -A2 core/roster.gd | grep -E "muz|wind" | head -4

# 5) 게임의 자기 검사기
say "5. ns_check --strict"
POCKER_NO_SAVE=1 stdbuf -oL timeout 600 "$GODOT" --headless --path . \
	res://tests/ns_check.tscn -- --strict 2>&1 | tail -40
