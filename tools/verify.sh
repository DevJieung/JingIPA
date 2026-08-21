#!/usr/bin/env bash
# 포커 디펜스 — 검증 한 곳. 갈무리 전에 이것만 돌리면 된다.
#
#   tools/verify.sh          전부      (약 3분)
#   tools/verify.sh quick    빠르게    (족보 전수·자동 플레이를 줄인다, 약 1분)
#
# ★ POCKER_NO_SAVE=1 로 돌린다. 검사를 돌릴 때마다 저장 파일이 덮이면
#   "내 기록"이라고 믿던 값이 사실은 테스트가 만든 값이 된다.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/.local/bin/godot}"
export POCKER_NO_SAVE=1

QUICK=0
[ "${1:-}" = "quick" ] && QUICK=1

fail=0
step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
check() { if [ "$1" -ne 0 ]; then echo "!! 실패: $2"; fail=1; else echo "   ok: $2"; fi; }

# ★ Godot 은 printerr 로 실패를 알려도 종료 코드가 0 인 경우가 있다.
#   그래서 출력에서 성공 문구를 **찾아서** 판정한다.
expect() {  # expect <이름> <꼭 있어야 할 문구> <출력파일>
	if grep -qF -- "$2" "$3"; then echo "   ok: $1"
	else echo "!! 실패: $1 — 기대한 문구가 없습니다: $2"; sed -n '1,12p' "$3"; fail=1; fi
}
forbid() {  # forbid <이름> <있으면 안 되는 문구> <출력파일>
	if grep -qF -- "$2" "$3"; then
		echo "!! 실패: $1 — '$2' 가 나왔습니다"; grep -n -F -- "$2" "$3" | head -5; fail=1
	fi
}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ★ 검사기가 멈추면(스크립트 로드 실패로 씬이 quit 을 영영 못 부르는 등) 여기서 무한정
#   기다린다. **멈춤은 조용한 대기가 아니라 실패다.** 실제로 policy.gd 를 임포트 안 한
#   상태로 돌렸다가 3분을 그냥 기다린 적이 있다.
godot_run() {  # godot_run <제한초> <출력파일> [godot 인자...]
	local limit="$1" out="$2"; shift 2
	# stdbuf -oL 이 빠지면 헤드리스 stdout 이 블록 버퍼링이라, 멈춰서 죽이는 순간
	# 여태 찍은 게 통째로 날아간다 — 어디서 멈췄는지가 안 남는다.
	timeout --signal=TERM --kill-after=15 "$limit" \
		stdbuf -oL "$GODOT" --headless --path . "$@" > "$out" 2>&1
	local rc=$?
	if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then
		printf '!! 멈춤: %s초 안에 안 끝났습니다 — %s\n' "$limit" "$*" >> "$out"
	fi
	return $rc
}

step "0. 게임 코드가 커맨드라인을 읽지 않는가"
# 게임이 인자를 읽으면 촬영 도구와 검사기가 서로의 인자를 삼키고,
# 게임 쪽 get_tree().quit() 이 촬영 도중 앱을 죽인다. 인자는 tests/ 만 읽는다.
if grep -rn 'get_cmdline' --include='*.gd' core/ game/ 2>/dev/null; then
	echo "!! core/ game/ 이 커맨드라인을 읽습니다. tests/ 로 옮기세요."; fail=1
else
	echo "   ok: core/ game/ 어디도 커맨드라인을 읽지 않음"
fi

step "0-1. 무늬를 글자로 그리지 않는가"
# 번들 폰트(DinoKR)에 ♠ ♦ ♣ 가 없다. 글자로 그리면 카드가 통째로 두부(□)가 된다.
if grep -rn $'♠\|♦\|♣' --include='*.gd' core/ game/ 2>/dev/null; then
	echo "!! 무늬를 글자로 씁니다. Look.draw_suit() 을 쓰세요."; fail=1
else
	echo "   ok: 무늬는 전부 도형으로 그린다"
fi

step "1. 캐릭터 표가 최신인가 (tools/roster.json → core/roster.gd)"
cp core/roster.gd "$TMP/roster.before"
python3 tools/gen_roster.py > "$TMP/genroster.log" 2>&1
if diff -q "$TMP/roster.before" core/roster.gd > /dev/null; then
	echo "   ok: core/roster.gd 가 tools/roster.json 과 일치"
else
	echo "!! core/roster.gd 가 낡았습니다 — 방금 다시 만들었으니 커밋하세요"; fail=1
fi

step "2. 임포트 (파스 오류 없이)"
timeout 300 "$GODOT" --headless --path . --import > "$TMP/import.log" 2>&1
forbid "임포트" "SCRIPT ERROR" "$TMP/import.log"
forbid "임포트" "Parse Error" "$TMP/import.log"
forbid "임포트" "Compile Error" "$TMP/import.log"
[ $fail -eq 0 ] && echo "   ok: 임포트"

step "3. 부팅"
godot_run 90 "$TMP/boot.log" --quit-after 200
forbid "부팅" "SCRIPT ERROR" "$TMP/boot.log"
forbid "부팅" "!! 멈춤" "$TMP/boot.log"
echo "   ok: 부팅"

step "4. 표끼리 어긋나지 않는가 (이름·등급·사거리·투기장)"
if [ $QUICK -eq 1 ]; then
	godot_run 90 "$TMP/ns.log" res://tests/ns_check.tscn
else
	godot_run 90 "$TMP/ns.log" res://tests/ns_check.tscn -- --strict
fi
expect "표 검사" "판정: 정상" "$TMP/ns.log"

step "5. 족보 판정"
if [ $QUICK -eq 1 ]; then
	godot_run 120 "$TMP/poker.log" res://tests/poker_check.tscn -- --quick
else
	godot_run 300 "$TMP/poker.log" res://tests/poker_check.tscn
	expect "전수 2,598,960판" "전수 검사 2598960판" "$TMP/poker.log"
fi
expect "족보 판정" "판정: 정상" "$TMP/poker.log"

step "6. 화면을 눌러서 한 바퀴 (타이틀 → 카드 → 전투 → 상점)"
godot_run 180 "$TMP/play.log" res://tests/play_check.tscn
expect "화면 한 바퀴" "판정: 정상" "$TMP/play.log"

step "7. 자동 플레이로 밸런스 (40탄까지)"
RUNS=12
[ $QUICK -eq 1 ] && RUNS=4
godot_run 300 "$TMP/bal.log" res://tests/balance_check.tscn -- --runs $RUNS
expect "자동 플레이" "판정: 정상" "$TMP/bal.log"
grep -E "^도달 탄" "$TMP/bal.log" | sed 's/^/   /'
# ★ 1~6탄에서 목숨이 깎이면 시작부터 아픈 게임이다. 이건 실패로 친다.
if awk '/^   [1-6]탄/ { if ($4 != "-0.00") bad=1 } END { exit bad?1:0 }' "$TMP/bal.log"; then
	echo "   ok: 1~6탄은 목숨을 잃지 않는다"
else
	echo "!! 실패: 초반(1~6탄)에 목숨이 깎입니다"; grep -E "^   [1-6]탄" "$TMP/bal.log"; fail=1
fi

step "8. 폰트에 없는 글자"
python3 tools/check_font.py > "$TMP/font.log" 2>&1
check $? "폰트"
tail -1 "$TMP/font.log" | sed 's/^/   /'

if [ $QUICK -eq 0 ]; then
	step "9. 안드로이드 APK"
	mkdir -p build/android
	timeout 300 "$GODOT" --headless --path . --export-debug "Android Test APK" \
		"$PWD/build/android/pokerdefense-test.apk" > "$TMP/apk.log" 2>&1
	if [ -s build/android/pokerdefense-test.apk ]; then
		echo "   ok: APK ($(du -h build/android/pokerdefense-test.apk | cut -f1))"
	else
		echo "!! 실패: APK 가 안 나왔습니다"; tail -20 "$TMP/apk.log"; fail=1
	fi
fi

printf '\n\033[1m'
if [ $fail -eq 0 ]; then echo "전부 통과"; else echo "실패가 있습니다"; fi
printf '\033[0m'
exit $fail
