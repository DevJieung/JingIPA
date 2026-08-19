#!/usr/bin/env bash
# 공룡섬 — 검증 한 곳. 갈무리 전에 이것만 돌리면 된다.
#
#   tools/verify.sh            전부
#   tools/verify.sh quick      느린 것(개구리 전체 검사) 빼고
#
# ★ ROGAME_NO_SAVE=1 로 돌린다. 예전에는 검사를 돌릴 때마다 저장 파일이 덮여서
#   "아이 기록"이라고 믿던 값이 사실은 테스트가 만든 값이었다.
#   통합 앱에서는 저장이 하나라 공룡 기록까지 같이 오염된다.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/.local/bin/godot}"
export ROGAME_NO_SAVE=1

QUICK=0
[ "${1:-}" = "quick" ] && QUICK=1

fail=0
step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
check() { if [ "$1" -ne 0 ]; then echo "!! 실패: $2"; fail=1; else echo "   ok: $2"; fi; }

# ★ Godot 은 printerr 로 실패를 알려도 종료 코드가 0 이다.
#   종료 코드만 보면 "셀프테스트가 17탄에서 멈춤"을 ok 로 보고한다 (실제로 그랬다).
#   그래서 출력에서 성공 문구를 **찾아서** 판정한다.
expect() {  # expect <이름> <꼭 있어야 할 문구> <출력파일>
	if grep -qF -- "$2" "$3"; then echo "   ok: $1"
	else echo "!! 실패: $1 — 기대한 문구가 없습니다: $2"; sed -n "1,6p" "$3"; fail=1; fi
}
forbid() {  # forbid <이름> <있으면 안 되는 문구> <출력파일>
	if grep -qF -- "$2" "$3"; then echo "!! 실패: $1 — $2"; fail=1; fi
}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ★ 검사기가 멈추면(스크립트 로드 실패로 씬이 quit 을 영영 못 부르는 등) 여기서 무한정
#   기다린다. 17분짜리 검증이 6시간이 되고 그동안 아무 소리도 안 난다 — 실제로 물렸다.
#   그래서 Godot 은 전부 이 함수로 부른다. **멈춤은 조용한 대기가 아니라 실패다.**
#   제한을 넘으면 그 사실을 출력 파일에도 적어 둔다 — 아래 grep '^!!' 과 expect 가
#   따로 손볼 것 없이 그대로 잡아 준다.
godot_run() {  # godot_run <제한초> <출력파일> [godot 인자...]
	local limit="$1" out="$2"; shift 2
	# ★ stdbuf -oL 이 빠지면 헤드리스 stdout 이 블록 버퍼링이라, 멈춰서 죽이는 순간
	#   여태 찍은 게 통째로 날아간다 — 파일이 비어서 "어디서 멈췄는지"가 안 남는다.
	timeout --signal=TERM --kill-after=15 "$limit" \
		stdbuf -oL "$GODOT" --headless --path . "$@" > "$out" 2>&1
	local rc=$?
	if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then
		printf '!! 멈춤: %s초 안에 안 끝났습니다 — %s\n' "$limit" "$*" >> "$out"
	fi
	return $rc
}

step "0. 셸이 게임 이름을 모르는가 (커맨드라인 규칙)"
# 게임 쪽 코드가 커맨드라인을 읽으면 두 게임의 개발 도구가 서로를 죽인다.
if grep -rn 'get_cmdline' --include='*.gd' shell/ core/ games/ 2>/dev/null; then
	echo "!! 게임/셸 코드가 커맨드라인을 읽습니다. tests/ 로 옮기세요."
	fail=1
else
	echo "   ok: shell/ core/ games/ 어디도 커맨드라인을 읽지 않음"
fi

step "1. 전역 이름 규칙"
godot_run 180 "$TMP/ns.txt" res://tests/ns_check.tscn
ns_rc=$?
grep -vE '^\[|^Godot Engine' "$TMP/ns.txt" | sed '/^$/d'
check $ns_rc "ns_check"

step "2. 한글 글리프 (개구리 용사 화면)"
python3 tools/check_font.py
check $? "check_font"

step "3. 공룡 찾기 — 방 배치 + 난이도 곡선"
godot_run 600 "$TMP/dump.txt" res://tests/dino_dump.tscn -- --dump
grep -E '자동 생성|판정:|가림 평균|카드 이름|첫 화면|공룡 그림|^!!' "$TMP/dump.txt"
expect "dino --dump" "판정: 정상" "$TMP/dump.txt"
expect "공룡 그림 50종" "공룡 그림 50종 모두 있음" "$TMP/dump.txt"
forbid "카드 이름 넘침" "!! 카드 이름" "$TMP/dump.txt"

step "4. 공룡 찾기 — 미취학 프로필"
godot_run 600 "$TMP/pre.txt" res://tests/dino_dump.tscn -- --dump --pre
grep -E '자동 생성|판정:|가림 평균|^!!' "$TMP/pre.txt"
expect "dino --dump --pre" "판정: 정상" "$TMP/pre.txt"

step "5. 공룡 찾기 — 30탄 자동 플레이"
godot_run 600 "$TMP/self.txt" res://tests/dino_dump.tscn -- --selftest
grep -E '자동 테스트|^!!' "$TMP/self.txt"
expect "dino --selftest" "자동 테스트: 30탄까지 진행" "$TMP/self.txt"

step "5a. 블록 채우기 — 퍼즐 생성기"
# ★ 역방향 생성이라 "풀 수 있다"가 생성 방식으로 보장되지만, 정말 빈틈없이 덮였는지는
#   격자로 다시 세어 본다. 조용히 실패하면 아이 화면에 빈 판이 뜬다.
godot_run 600 "$TMP/nood.txt" res://tests/kanoodle_check.tscn
grep -E '판 [0-9]+개|판정:|^!!' "$TMP/nood.txt"
expect "kanoodle_check" "판정: 정상" "$TMP/nood.txt"
godot_run 600 "$TMP/nood_pre.txt" res://tests/kanoodle_check.tscn -- --pre
grep -E '판 [0-9]+개|판정:|^!!' "$TMP/nood_pre.txt"
expect "kanoodle_check --pre" "판정: 정상" "$TMP/nood_pre.txt"

step "5b. 손전등 찾기 — 방 배치 + 실제 플레이"
# ★ 여기서만 잡히는 것: **어두운 데의 공룡이 눌러서 찾아지지 않는가.** 이게 뒤집히면
#   게임이 그냥 "어두운 공룡 찾기"가 되는데, 화면을 눈으로 봐서는 절대 안 보인다.
#   그리고 어둠 x 가림 x 좁은 빛의 **곱**에 상한이 있는지도 여기가 강제한다.
godot_run 600 "$TMP/torch.txt" res://tests/torch_check.tscn
grep -E '방 [0-9]+개|판정:|^!!' "$TMP/torch.txt"
expect "torch_check" "판정: 정상" "$TMP/torch.txt"
godot_run 600 "$TMP/torch_pre.txt" res://tests/torch_check.tscn -- --pre
grep -E '방 [0-9]+개|판정:|^!!' "$TMP/torch_pre.txt"
expect "torch_check --pre" "판정: 정상" "$TMP/torch_pre.txt"

step "5c. 참참참 — 버릇 만들기 + 읽어서 잡기"
# ★ 여기서만 잡히는 것: **버릇을 읽을 수 있는가.** 친구의 방향이 무작위가 되면
#   게임이 그 자리에서 동전 던지기가 되는데, 화면을 봐서는 절대 안 보인다.
#   버릇을 못 읽는 아이(발자국만 보는 아이)까지 흉내 내서 반드시 잡히는지 확인한다.
godot_run 600 "$TMP/cham.txt" res://tests/cham_check.tscn
grep -E '버릇 [0-9]+개|판정:|^!!' "$TMP/cham.txt"
expect "cham_check" "판정: 정상" "$TMP/cham.txt"
godot_run 600 "$TMP/cham_pre.txt" res://tests/cham_check.tscn -- --pre
grep -E '버릇 [0-9]+개|판정:|^!!' "$TMP/cham_pre.txt"
expect "cham_check --pre" "판정: 정상" "$TMP/cham_pre.txt"

step "5d. 아무거나 — 게임을 오가는 흐름"
# ★ 게임과 게임 **사이**를 보는 유일한 검사다. 화면 전환 잠금이 안 풀려서
#   그 뒤 모든 전환이 조용히 무시되던 사고가 여기서 잡혔다.
godot_run 900 "$TMP/journey.txt" res://tests/journey_check.tscn
grep -E '섬 한 바퀴|게임별|판정:|^!!' "$TMP/journey.txt"
expect "journey_check" "판정: 정상" "$TMP/journey.txt"

if [ "$QUICK" -eq 0 ]; then
	step "5e. 개구리 용사 — 시연을 켠 채로 한 탄씩 (test_runner 가 안 보는 경로)"
	godot_run 1500 "$TMP/battle.txt" res://tests/battle_check.tscn
	grep -E '탄:|판정:|^!!' "$TMP/battle.txt"
	expect "battle_check" "판정: 정상" "$TMP/battle.txt"

	step "6. 개구리 용사 — 전체 검사 (약 8분)"
	godot_run 1800 "$TMP/tr.txt" res://tests/test_runner.tscn
	grep -E '결과:' "$TMP/tr.txt" || tail -4 "$TMP/tr.txt"
	expect "test_runner" "실패 0개" "$TMP/tr.txt"
fi

step "7. 익스포트가 살아 있는가"
# ★ rm -rf 를 쓰지 않는다 — 실행 환경에 따라 막혀서 "명령어를 찾을 수 없음"이 난다.
#   지우는 대신 "이번 실행보다 새로 만들어졌는가"를 시각으로 확인한다.
mkdir -p build/ios build/android
touch "$TMP/mark"
godot_run 900 "$TMP/ios.txt" --export-release "iOS" "$PWD/build/ios/rogame.ipa"
if [ -d build/ios/rogame.xcodeproj ] && [ build/ios/rogame.xcodeproj -nt "$TMP/mark" ]; then
	echo "   ok: iOS Xcode 프로젝트 (새로 생성됨)"
else
	echo "!! 실패: iOS Xcode 프로젝트가 새로 안 나왔습니다"; fail=1
fi

godot_run 900 "$TMP/apk.txt" --export-debug "Android Test APK" \
	"$PWD/build/android/rogame-test.apk"
grep -E '\[ DONE \]|Signed' "$TMP/apk.txt" | head -2
if [ -s build/android/rogame-test.apk ] && [ build/android/rogame-test.apk -nt "$TMP/mark" ] \
		&& grep -q 'Signed' "$TMP/apk.txt"; then
	echo "   ok: Android APK (서명까지 새로)"
else
	echo "!! 실패: APK 가 새로 안 나왔거나 서명이 안 됐습니다"; tail -5 "$TMP/apk.txt"; fail=1
fi

step "8. 저장소에 새어 나가면 안 되는 것"
leak=$(git ls-files | grep -E '\.(keystore|jks|p12|pem|key|mobileprovision|b64)$|^\.godot/|export_credentials\.cfg|^\.certs/' || true)
if [ -n "$leak" ]; then echo "!! $leak"; fail=1; else echo "   ok: 비밀 파일 없음"; fi
# ★ 개수를 숫자로 박아 두면 자산을 지울 때마다 빨간불이 된다(실제로 그랬다).
#   대신 **디스크의 자산마다 .import 가 커밋돼 있는지**를 본다 — 자산이 늘든 줄든 맞는다.
miss_imp=""
# preview/ 는 .gdignore 가 걸려 있어 Godot 이 임포트하지 않는다 (그래서 .import 가 없다).
for f in $(git ls-files '*.png' '*.ogg' '*.ttf' '*.svg' | grep -v '^preview/'); do
	git ls-files --error-unmatch "$f.import" >/dev/null 2>&1 || miss_imp="$miss_imp $f"
done
miss_uid=""
for f in $(git ls-files 'games/*.gd' 'shell/*.gd' 'core/*.gd'); do
	[ -f "$f.uid" ] && { git ls-files --error-unmatch "$f.uid" >/dev/null 2>&1 || miss_uid="$miss_uid $f"; }
done
imp=$(git ls-files '*.import' | wc -l); uid=$(git ls-files '*.uid' | wc -l)
echo "   자산 .import $imp개 / 스크립트 .uid $uid개"
if [ -n "$miss_imp" ]; then echo "!! .import 가 커밋 안 된 자산:$miss_imp"; fail=1
elif [ -n "$miss_uid" ]; then echo "!! .uid 가 커밋 안 된 스크립트:$miss_uid"; fail=1
else echo "   ok: 자산마다 .import 가, 스크립트마다 .uid 가 커밋돼 있음"; fi

printf '\n'
if [ "$fail" -eq 0 ]; then
	printf '\033[1;32m전부 통과\033[0m\n'
else
	printf '\033[1;31m실패 있음 — 위를 보세요\033[0m\n'
fi
exit $fail
