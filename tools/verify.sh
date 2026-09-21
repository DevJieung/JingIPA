#!/usr/bin/env bash
# 올인 디펜스 — 검증 한 곳. 갈무리 전에 이것만 돌리면 된다.
#
#   tools/verify.sh          전부      (약 8분)
#   tools/verify.sh --skip-sprites  스프라이트 검수 제외
#   tools/verify.sh quick    빠르게    (족보 전수·자동 플레이를 줄인다, 약 3분)
#
# ★ POCKER_NO_SAVE=1 로 돌린다. 검사를 돌릴 때마다 저장 파일이 덮이면
#   "내 기록"이라고 믿던 값이 사실은 테스트가 만든 값이 된다.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/.local/bin/godot}"
export POCKER_NO_SAVE=1

QUICK=0
SKIP_SPRITES=0
for arg in "$@"; do
	case "$arg" in
		quick) QUICK=1 ;;
		--skip-sprites) SKIP_SPRITES=1 ;;
		*) echo "사용법: tools/verify.sh [quick] [--skip-sprites]"; exit 2 ;;
	esac
done

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
finish() {
	if [ "$fail" -ne 0 ]; then
		mkdir -p build/verify-failure
		cp "$TMP"/*.log build/verify-failure/ 2>/dev/null || true
		echo "실패 로그: build/verify-failure/"
	fi
	rm -rf "$TMP"
}
trap finish EXIT

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
	if [ $rc -ne 0 ]; then
		echo "!! 실패: Godot 종료 코드 $rc — $*"; fail=1
	fi
	forbid "Godot 실행" "ERROR:" "$out"
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
# ★ 주석에는 "이 글자를 쓰지 마라"고 적어 두므로, 주석 줄은 빼고 본다.
#   안 빼면 그 설명 자체가 걸려서 늘 실패한다(실제로 그랬다).
if grep -rn --include='*.gd' -E '♠|♦|♣' core/ game/ 2>/dev/null \
		| grep -vE ':[0-9]+:[[:space:]]*#'; then
	echo "!! 무늬를 글자로 씁니다. Look.draw_suit() 을 쓰세요."; fail=1
else
	echo "   ok: 무늬는 전부 도형으로 그린다"
fi

step "1. 캐릭터 표가 최신인가 (tools/roster.json → core/roster.gd)"
python3 tools/gen_roster.py --check > "$TMP/genroster.log" 2>&1
check $? "로스터 일치 (파일 수정 없음)"

step "1-1. ElevenLabs 음악·효과음 파일과 루프가 정상인가"
if python3 tools/audio/check_audio.py > "$TMP/sfx.log" 2>&1; then
	tail -1 "$TMP/sfx.log" | sed 's/^/   /'
else
	echo "!! 실패: 효과음 검사가 실패했습니다"; tail -5 "$TMP/sfx.log"; fail=1
fi

step "2. 임포트 (파스 오류 없이)"
godot_run 300 "$TMP/import.log" --import
forbid "임포트" "SCRIPT ERROR" "$TMP/import.log"
forbid "임포트" "Parse Error" "$TMP/import.log"
forbid "임포트" "Compile Error" "$TMP/import.log"
[ $fail -eq 0 ] && echo "   ok: 임포트"

step "3. 부팅"
godot_run 90 "$TMP/boot.log" --quit-after 200
forbid "부팅" "SCRIPT ERROR" "$TMP/boot.log"
forbid "부팅" "!! 멈춤" "$TMP/boot.log"
# ★ CLAUDE.md 10번(0 으로 줄어든 도형에 draw_colored_polygon 을 부르지 마라)을 지키는
#   **유일한 자동 검사**다. 점이 한 곳에 뭉치면 이 말이 프레임마다 쏟아지는데, 종료
#   코드는 0 이고 사진에도 안 남아서 여기서 안 보면 아무도 못 잡는다.
forbid "부팅" "triangulation failed" "$TMP/boot.log"
echo "   ok: 부팅"

step "4. 표끼리 어긋나지 않는가 (이름·등급·사거리·투기장)"
if [ $QUICK -eq 1 ]; then
	godot_run 90 "$TMP/ns.log" res://tests/ns_check.tscn
else
	godot_run 90 "$TMP/ns.log" res://tests/ns_check.tscn -- --strict
fi
expect "표 검사" "판정: 정상" "$TMP/ns.log"

if [ $SKIP_SPRITES -eq 0 ]; then
step "4-1. 출고된 스프라이트 시트 (art/anim/)"
# ★★ **굽는 순간의 지적은 아무것도 안 막았다.** `sprite_post.qc()` 는 시트를 구울 때
#   `!!` 한 줄을 찍고 그대로 저장한다 — 실제로 쉰 명을 구울 때
#   「unit_sigrid_attack_96x96_12.png — 발 높이가 5px 흔들림」이 찍혔는데, 아무도
#   안 봤고 그대로 게임에 들어갔다 — 시그리드는 그동안 공격할 때마다 5px 가라앉고
#   있었다(지금은 고쳤다 · docs/SPRITE.md 1-11).
#   그래서 **출고된 것을 다시 재고, 지적이 나오면 여기서 세운다.**
# ★ `qc_game.py` 는 공식 검사 여덟 가지를 `sprite_post.qc()` 에서 **그대로 불러** 쓰고
#   (잣대를 베끼면 언젠가 갈린다), 그 위에 공식 qc 가 못 보는 둘을 더 잰다 —
#   **클립 사이** 발 높이(qc 는 한 시트 안에서만 잰다)와 **총구 가로의 부호**
#   (qc 는 anim.json 을 아예 안 본다. 음수면 Balance.art_aim() 이 그림을 뒤집는다).
# ★ 몇 초면 끝나므로 `quick` 에서도 돈다.
python3 tools/sprite/qc_game.py --json "$TMP/qc_game.json" > "$TMP/qc_game.log" 2>&1
QCRC=$?
grep -E "^   (발 높이|총구 가로|테두리)" "$TMP/qc_game.log" | sed 's/^/   /'
if [ $QCRC -ne 0 ]; then
	echo "!! 실패: 출고된 시트에 지적 사항이 있습니다"
	grep -E "^ !!|^      -" "$TMP/qc_game.log" | head -30
	fail=1
else
	tail -2 "$TMP/qc_game.log" | sed 's/^/   /'
	echo "   ok: 출고된 시트 (공식 8종 + 클립 사이 발 높이 + 총구 부호)"
fi

else
	echo "   제외: 스프라이트 검수 (--skip-sprites)"
fi

step "4-2. 저장 · 보상 · 메뉴 · 거래 회귀 검사"
godot_run 120 "$TMP/flow.log" res://tests/flow_check.tscn
expect "게임 흐름" "판정: 정상" "$TMP/flow.log"

step "4-2d. 누적 전과 · 패시브 전체 보유 · 합성 규칙"
godot_run 120 "$TMP/run-stats.log" res://tests/run_stats_check.tscn
expect "누적 전과와 패시브" "판정: 정상" "$TMP/run-stats.log"
godot_run 120 "$TMP/rules.log" res://tests/rules_check.tscn
expect "합성과 보상 규칙" "판정: 정상" "$TMP/rules.log"
godot_run 120 "$TMP/wave-scaling.log" res://tests/wave_scaling_check.tscn
expect "후반 몬스터 수와 체력" "판정: 정상" "$TMP/wave-scaling.log"
godot_run 120 "$TMP/revive-flow.log" res://tests/revive_flow_check.tscn
expect "광고 부활 획득 연출" "판정: 정상" "$TMP/revive-flow.log"
godot_run 120 "$TMP/reroll.log" res://tests/reroll_check.tscn
expect "무료 교체 횟수" "판정: 정상" "$TMP/reroll.log"

step "4-2a. 테마 출현 비율·목록 · 보상 알림 닫기"
godot_run 120 "$TMP/theme-notice.log" res://tests/theme_notice_check.tscn
expect "테마 정보·보상 알림" "판정: 정상" "$TMP/theme-notice.log"

step "4-2b. 50개 테마 주 속성 비중·보스 고정"
godot_run 120 "$TMP/theme-distribution.log" res://tests/theme_distribution_check.tscn
expect "테마 분포" "판정: 정상" "$TMP/theme-distribution.log"

step "4-2c. 테마 BGM 전환·반복·독립 음량 설정"
POCKER_AUDIO_TEST=1 godot_run 120 "$TMP/audio-runtime.log" res://tests/audio_check.tscn
expect "음악 재생" "판정: 정상" "$TMP/audio-runtime.log"

step "4-3. 두 입구 · 12자리 · 실시간 재배치"
godot_run 120 "$TMP/formation.log" res://tests/formation_check.tscn
expect "배치 검사" "판정: 정상" "$TMP/formation.log"
godot_run 120 "$TMP/course.log" res://tests/course_check.tscn
expect "전체 테마 코어 우회 경로" "판정: 정상" "$TMP/course.log"

step "4-4. 실제 피해 · 겹침 · 속성"
godot_run 120 "$TMP/dmg.log" res://tests/dmg_check.tscn -- --selftest
expect "피해 검사" "판정: 정상" "$TMP/dmg.log"

step "4-5. 몬스터 이동 클립 · 상태이상 · 희귀 착탄"
godot_run 120 "$TMP/monster.log" res://tests/monster_check.tscn -- --assets
expect "몬스터·이펙트 검사" "판정: 정상" "$TMP/monster.log"

step "5. 족보 판정"
if [ $QUICK -eq 1 ]; then
	godot_run 120 "$TMP/poker.log" res://tests/poker_check.tscn -- --quick
else
	godot_run 300 "$TMP/poker.log" res://tests/poker_check.tscn
	expect "전수 2,598,960판" "전수 검사 2598960판" "$TMP/poker.log"
fi
expect "족보 판정" "판정: 정상" "$TMP/poker.log"

step "6. 화면을 눌러서 한 바퀴 (타이틀 → 카드 → 전투 → 상점)"
godot_run 360 "$TMP/play.log" res://tests/play_check.tscn
expect "화면 한 바퀴" "판정: 정상" "$TMP/play.log"
# 부팅과 같은 이유로 여기서도 본다 — 전투·편성 판은 부팅만으로는 한 번도 안 그려진다.
forbid "화면 한 바퀴" "triangulation failed" "$TMP/play.log"

step "7. 자동 플레이로 밸런스 (100탄까지)"
RUNS=12
[ $QUICK -eq 1 ] && RUNS=4
# ★ 100탄이 되면서 한 판이 길어졌다. 12판에 4분쯤 걸린다 — 넉넉히 준다.
godot_run 900 "$TMP/bal.log" res://tests/balance_check.tscn -- --runs $RUNS
expect "자동 플레이" "판정: 정상" "$TMP/bal.log"
grep -E "^도달 탄" "$TMP/bal.log" | sed 's/^/   /'
# ★ 클리어율이 밸런스의 본체다. 한 판도 못 깨거나 거의 다 깨면 숫자가 무너진 것이다.
#   (12판 표본이라 폭은 넓게 잡는다 — 기대값은 3판 안팎이다. CLAUDE.md 16번 참고)
if [ $QUICK -eq 0 ]; then
	CLEARS=$(sed -n 's/^도달 탄:.*클리어 \([0-9]*\)판.*/\1/p' "$TMP/bal.log")
	if [ -z "$CLEARS" ]; then
		echo "!! 실패: 클리어 판수를 못 읽었습니다"; fail=1
	elif [ "$CLEARS" -lt 1 ] || [ "$CLEARS" -gt 6 ]; then
		# ★ 위 칸을 8 → 6 으로 좁혔다. 사용자가 「조금 어렵게」로 정했으므로 기대값이
		#   12판 중 2~3판(약 20%)이다. 8판까지 통과시키면 다시 쉬워져도 안 잡힌다.
		echo "!! 실패: 12판 중 클리어 $CLEARS 판 — 1~6판이어야 합니다 (밸런스가 무너졌습니다)"
		fail=1
	else
		echo "   ok: 12판 중 클리어 $CLEARS 판"
	fi
fi
# 초반 난이도 상향 후 드문 누수는 허용하되, 탄마다 평균 0.5개를 넘으면 막는다.
# 첫 탄은 더 엄격하게 평균 0.25개 이하. 체력 상향 전의 무손실 조건을 유지하면
# 요청한 초반 압박 자체를 회귀 오류로 판정하게 된다.
if awk '/^   [1-6]탄/ { loss=-$4; limit=($1=="1탄" ? 0.25 : 0.5); if (loss>limit) bad=1 } END { exit bad?1:0 }' "$TMP/bal.log"; then
	echo "   ok: 초반 손실 한도 (1탄 평균 0.25개 / 2~6탄 평균 0.5개 이하)"
else
	echo "!! 실패: 초반(1~6탄) 크리스탈 손실이 한도를 넘습니다"; grep -E "^   [1-6]탄" "$TMP/bal.log"; fail=1
fi
# ★ **어느 속성이 죽었는지는 클리어율로 절대 안 보인다.** 나무·바위 몸이 전기를 0배로 받으므로
#   (사용자가 정한 표) 전기 영웅이 조용히 안 쓰이게 될 수 있다. 안뜰에 실제로 선 비율을
#   찍어 두고, 한 속성이 10% 밑으로 내려가면 실패로 친다(고르면 20%씩이다).
# ★ **빠르게(4판)에서는 재기만 하고 실패로 안 친다.** 넉 판은 뽑은 손이 곧 표본이라
#   흔들림이 그 문턱보다 크다 — 실측으로 4판에서 물이 7.9%, 같은 코드로 12판에서
#   11.2%, 24판에서 12.0% 가 나왔다. 넉 판으로 실패를 내면 이 검사가 「고쳐도 안 고쳐도
#   가끔 빨간 줄」이 되고, 그러면 아무도 안 보게 된다. 전부(12판)에서는 그대로 잰다.
sed -n '/성역에 선 영웅의 속성/,/^$/p' "$TMP/bal.log" | sed 's/^/   /'
if awk '/성역에 선 영웅의 속성/ { on=1; next } on && /\(/ { gsub(/[()%]/,"",$3); if ($3+0 < 10.0) bad=1 } END { exit bad?1:0 }' "$TMP/bal.log"; then
	echo "   ok: 다섯 속성이 다 쓰인다"
elif [ $QUICK -eq 1 ]; then
	echo "   (빠르게: 10% 밑인 속성이 있지만 넉 판은 표본이 작아 실패로 안 칩니다 — tools/verify.sh 로 다시 재세요)"
else
	echo "!! 실패: 안 쓰이는 속성이 있습니다 (10% 미만) — 상성표가 한쪽으로 기울었습니다"; fail=1
fi

step "7-1. AdMob 설정·보상 콜백"
python3 -m unittest discover -s tests -p test_admob_config.py > "$TMP/admob-config.log" 2>&1
check $? "AdMob 환경 설정"
godot_run 60 "$TMP/ads.log" res://tests/ads_check.tscn
expect "AdMob 광고 종류·보상 콜백" "판정: 정상" "$TMP/ads.log"

step "8. 폰트에 없는 글자"
python3 tools/check_font.py > "$TMP/font.log" 2>&1
check $? "폰트"
tail -1 "$TMP/font.log" | sed 's/^/   /'

step "8-1. 한영 문구·언어 저장·영웅정보"
python3 tools/check_localization.py > "$TMP/localization-catalog.log" 2>&1
check $? "번역 문구 누락"
godot_run 120 "$TMP/localization.log" res://tests/localization_check.tscn
expect "한영 언어·영웅정보" "판정: 정상" "$TMP/localization.log"

if [ $QUICK -eq 0 ]; then
	step "9. 안드로이드 APK"
	# ★ APK 는 **홈 디렉터리**에 굽는다(사용자가 정한 것). 저장소 안(build/)에 두면
	#   폰으로 옮길 때마다 경로를 찾아 들어가야 하고, 지운 줄 알았던 옛 APK 가 남는다.
	# ★ 굽는 것은 tools/build_apk.sh 한 곳이다. 광고 플러그인이 들어오면서 Gradle 빌드가
	#   됐고(use_gradle_build=true), 그것은 JDK 17(build/toolchains/jdk17)을 가리키는
	#   **따로 둔 편집기 설정**(build/godot-config) 아래에서만 돈다 — 기본 설정의 Java 8 로
	#   내보내면 Gradle 이 「JVM 11 이상」이라며 거절한다. 여기서 export 를 또 적으면
	#   그 어긋남이 언젠가 되살아나므로, 서명·플러그인 매니페스트 검사까지 하는 그 대본에
	#   통째로 맡기고 성공한 새 파일로만 기존 APK 를 교체한다.
	APK="$HOME/pokerdefense-test.apk"
	if timeout --signal=TERM --kill-after=15 900 tools/build_apk.sh > "$TMP/apk.log" 2>&1 \
			&& [ -s "$APK" ]; then
		echo "   ok: APK $APK ($(du -h "$APK" | cut -f1))"
	else
		echo "!! 실패: 새 APK가 안 나왔습니다"; tail -20 "$TMP/apk.log"; fail=1
	fi
fi

printf '\n\033[1m'
if [ $fail -eq 0 ]; then echo "전부 통과"; else echo "실패가 있습니다"; fi
printf '\033[0m'
exit $fail
