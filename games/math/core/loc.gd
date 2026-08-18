## 화면에 나오는 글자 모음 (한국어 / English).
##
## 쓰는 법: Loc.t("start")  ->  현재 언어의 문자열
## 언어는 MathGame.set_language("ko" | "en") 로 바꾸고 저장된다.
##
## 규칙: 새 문자열을 화면에 쓸 때는 반드시 여기에 키를 만들고 Loc.t() 로 꺼내 쓴다.
## 코드에 한글을 직접 박으면 영어 모드에서 그대로 한글이 나온다.
## (tools/check_font.py 가 두 언어 글자가 모두 폰트에 있는지 검사한다.)
class_name Loc
extends RefCounted

static var lang := "ko"


static func t(key: String) -> String:
	var e: Variant = STRINGS.get(key)
	if typeof(e) != TYPE_DICTIONARY:
		return key
	var d: Dictionary = e
	return String(d.get(lang, d.get("ko", key)))


## "%s" 하나가 들어가는 문자열에 값을 끼운다.
static func f(key: String, args: Array) -> String:
	return t(key) % args


static func is_en() -> bool:
	return lang == "en"


const STRINGS := {
	# --- 공통 / 타이틀 ---
	"game_title": {"ko": "셈놀이", "en": "Number Play"},
	"start": {"ko": "시작!", "en": "Start!"},
	"continue": {"ko": "이어하기", "en": "Continue"},
	"map": {"ko": "지도 보기", "en": "World Map"},
	"endless": {"ko": "무한 도전", "en": "Endless"},
	"skip_demo_on": {"ko": "설명 건너뛰기: 켬", "en": "Skip Demo: ON"},
	"skip_demo_off": {"ko": "설명 건너뛰기: 끔", "en": "Skip Demo: OFF"},
	"lang_ko": {"ko": "한국어", "en": "한국어"},
	"lang_en": {"ko": "English", "en": "English"},

	# --- 전투 ---
	"next": {"ko": "다음", "en": "Next"},
	"tier_clear": {"ko": "탄 클리어!", "en": "Stage Clear!"},
	"boss_clear": {"ko": "보스 격파!", "en": "Boss Defeated!"},
	"all_correct": {"ko": "다 맞혔어요!", "en": "All correct!"},
	"new_record": {"ko": "기록을 넘었어요!", "en": "New best!"},
	"snakes_beaten": {"ko": "%d문제 풀었어요", "en": "%d problems solved"},
	"rest_today": {"ko": "오늘은 여기까지 하고 쉬어요", "en": "That's enough for today"},
	"go_map": {"ko": "지도로", "en": "Map"},
	"next_tier": {"ko": "다음 탄", "en": "Next Stage"},
	"one_more": {"ko": "한 번 더", "en": "Once more"},
	"endless_done": {"ko": "무한 도전 끝!", "en": "Endless over!"},
	"solved_count": {"ko": "맞힌 문제 %d개", "en": "Solved %d"},
	"best_count": {"ko": "최고 기록 %d개", "en": "Best %d"},
	"is_new_record": {"ko": "새 기록이에요!", "en": "That's a new record!"},
	"groups_of": {"ko": "%d씩 %d묶음", "en": "%d in each of %d groups"},
	"tens": {"ko": "십", "en": "10s"},
	"ones": {"ko": "일", "en": "1s"},

	# --- 지도 ---
	"stage_n": {"ko": "%d탄", "en": "Stage %d"},

	# --- 부모 화면 ---
	"parent_check": {"ko": "부모님 확인", "en": "Grown-ups only"},
	"close": {"ko": "닫기", "en": "Close"},
	"report": {"ko": "학습 리포트", "en": "Progress Report"},
	"solved": {"ko": "푼 문제", "en": "Solved"},
	"accuracy": {"ko": "정답률", "en": "Accuracy"},
	"stages_done": {"ko": "깬 탄", "en": "Stages"},
	"stars": {"ko": "별", "en": "Stars"},
	"snakes": {"ko": "푼 문제", "en": "Solved"},
	"playtime": {"ko": "플레이", "en": "Playtime"},
	"count_unit": {"ko": "%d개", "en": "%d"},
	"snake_unit": {"ko": "%d마리", "en": "%d"},
	"minutes": {"ko": "%d분", "en": "%d min"},
	"weak_problems": {"ko": "자주 틀리는 문제", "en": "Trouble spots"},
	"error_types": {"ko": "실수 유형", "en": "Mistake types"},
	"none_yet": {"ko": "아직 없어요", "en": "Nothing yet"},
	"wrong_times": {"ko": "%s   (%d번 틀림)", "en": "%s   (missed %d)"},
	"tag_times": {"ko": "%s (%d회)", "en": "%s (%d)"},
	"opt_sfx": {"ko": "효과음", "en": "Sound effects"},
	"opt_bgm": {"ko": "배경 음악", "en": "Music"},
	"opt_fast": {"ko": "시연 짧게", "en": "Shorter demo"},
	"opt_motion": {"ko": "배경 움직임 줄이기", "en": "Reduce motion"},
	"opt_session": {"ko": "한 번에 20문제로 제한", "en": "Limit to 20 per session"},
	"opt_skip": {"ko": "설명 건너뛰기", "en": "Skip the demo"},
	"opt_lang": {"ko": "언어: 한국어", "en": "Language: English"},
	"reset": {"ko": "진행 처음부터 다시", "en": "Reset all progress"},
	"reset_ask": {"ko": "정말 지울까요?", "en": "Erase everything?"},
	"reset_warn": {"ko": "별과 기록이 모두 사라져요", "en": "All stars and records will be lost"},
	"no": {"ko": "아니요", "en": "No"},
	"yes_erase": {"ko": "네, 지울래요", "en": "Yes, erase"},

	# --- 오답 유형 (부모 화면) ---
	"counting_on_low": {"ko": "하나 적게 셈 (답 -1)", "en": "Counted one short (answer -1)"},
	"counting_on_high": {"ko": "하나 많게 셈 (답 +1)", "en": "Counted one extra (answer +1)"},
	"count_back_low": {"ko": "거꾸로 세기 오류 (답 +1)", "en": "Counting back slip (answer +1)"},
	"count_back_high": {"ko": "거꾸로 세기 오류 (답 -1)", "en": "Counting back slip (answer -1)"},
	"count_off2": {"ko": "두 칸 어긋난 세기", "en": "Off by two"},
	"carry_dropped": {"ko": "받아올림을 빠뜨림", "en": "Dropped the carry"},
	"carry_twice": {"ko": "받아올림을 두 번 함", "en": "Carried twice"},
	"decompose_slip": {"ko": "10 만들기 가르기 실수", "en": "Make-ten split slip"},
	"borrow_forgot": {"ko": "빌린 뒤 십의 자리를 안 줄임", "en": "Forgot to reduce the ten"},
	"smaller_from_larger": {"ko": "자리마다 큰 수에서 작은 수를 뺌",
		"en": "Subtracted smaller from larger digit"},
	"ten_only": {"ko": "10에서만 빼고 낱개를 잊음", "en": "Subtracted from 10 only"},
	"sign_confusion": {"ko": "연산 기호를 반대로 봄", "en": "Misread the operator"},
	"place_value_confusion": {"ko": "자릿값을 헷갈림", "en": "Place value confusion"},
	"tens_slip_high": {"ko": "십의 자리 +10 오류", "en": "Tens place +10"},
	"tens_slip_low": {"ko": "십의 자리 -10 오류", "en": "Tens place -10"},
	"term_echo": {"ko": "보이는 수를 그대로 답함", "en": "Echoed a given number"},
	"term_echo_minuend": {"ko": "앞의 수를 그대로 답함", "en": "Echoed the first number"},
	"term_echo_subtrahend": {"ko": "빼는 수를 그대로 답함", "en": "Echoed the subtrahend"},
	"total_echo": {"ko": "합을 그대로 답함", "en": "Echoed the total"},
	"dropped_last_term": {"ko": "마지막 수를 빠뜨림", "en": "Dropped the last number"},
	"dropped_first_term": {"ko": "첫 수를 빠뜨림", "en": "Dropped the first number"},
	"added_last_term": {"ko": "마지막 수를 더해버림", "en": "Added instead of subtracting"},
	"leftover_only": {"ko": "10을 만들고 나머지만 답함", "en": "Answered only the leftover"},
	"operand_error_low": {"ko": "같은 단의 바로 아래 곱", "en": "Neighbour below in the table"},
	"operand_error_high": {"ko": "같은 단의 바로 위 곱", "en": "Neighbour above in the table"},
	"operand_other_low": {"ko": "다른 단의 이웃 곱", "en": "Neighbour in the other table"},
	"operand_other_high": {"ko": "다른 단의 이웃 곱", "en": "Neighbour in the other table"},
	"mul_as_add": {"ko": "곱셈을 덧셈으로 계산", "en": "Added instead of multiplying"},
	"digit_swap": {"ko": "자릿수를 뒤집어 씀", "en": "Digits swapped"},
	"one_rule_overgeneralized": {"ko": "1단 규칙 과일반화", "en": "Over-applied the x1 rule"},
	"zero_as_identity": {"ko": "0의 곱을 0 더하기로 봄", "en": "Treated x0 like +0"},
	"zero_as_one": {"ko": "0의 곱을 1로 봄", "en": "Treated x0 as 1"},
	"group_short": {"ko": "묶음을 하나 덜 셈", "en": "One group short"},
	"group_extra": {"ko": "묶음을 하나 더 셈", "en": "One group too many"},
	"near": {"ko": "가까운 수를 찍음", "en": "Guessed a nearby number"},
	"unknown": {"ko": "기타", "en": "Other"},

	# --- 월드 이름 ---
	"w1": {"ko": "모으기와 가르기", "en": "Make and Break"},
	"w1s": {"ko": "더하기의 시작", "en": "First steps in adding"},
	"w2": {"ko": "십몇", "en": "Teens"},
	"w2s": {"ko": "10과 십몇", "en": "Ten and the teens"},
	"w3": {"ko": "받아올림", "en": "Carrying"},
	"w3s": {"ko": "받아올림으로 가는 길", "en": "The road to carrying"},
	"w4": {"ko": "스무 고개", "en": "Up to Twenty"},
	"w4s": {"ko": "받아내림의 관문", "en": "The borrowing gate"},
	"w5": {"ko": "곱셈 첫걸음", "en": "First Times"},
	"w5s": {"ko": "묶어 세기와 구구단", "en": "Groups and times tables"},
	"w6": {"ko": "구구단", "en": "Times Tables"},
	"w6s": {"ko": "마지막 결전", "en": "The final battle"},

	# --- 탄 이름 / 목표 ---
	"t1": {"ko": "모으기", "en": "Putting together"},
	"t1g": {"ko": "합이 5까지", "en": "Sums up to 5"},
	"t2": {"ko": "한 자리 더하기", "en": "Adding to 9"},
	"t2g": {"ko": "합이 6~9", "en": "Sums 6-9"},
	"t3": {"ko": "첫 빼기", "en": "First subtraction"},
	"t3g": {"ko": "9까지의 뺄셈", "en": "Take away within 9"},
	"t4": {"ko": "10의 문", "en": "The gate of ten"},
	"t4g": {"ko": "10 모으기와 가르기", "en": "Making and breaking 10"},
	"t5": {"ko": "십몇 더하기", "en": "Teens plus"},
	"t5g": {"ko": "13 + 4", "en": "13 + 4"},
	"t6": {"ko": "십몇 빼기", "en": "Teens minus"},
	"t6g": {"ko": "17 - 4", "en": "17 - 4"},
	"t7": {"ko": "세 수 더하기", "en": "Three numbers"},
	"t7g": {"ko": "세 수의 덧셈과 뺄셈", "en": "Three numbers in a row"},
	"t8": {"ko": "10을 만들어", "en": "Make a ten"},
	"t8g": {"ko": "10을 채우고 더하기", "en": "Fill ten, then add"},
	"t9": {"ko": "받아올림", "en": "Carrying"},
	"t9g": {"ko": "(몇) + (몇)", "en": "Sums past ten"},
	"t10": {"ko": "받아내림", "en": "Borrowing"},
	"t10g": {"ko": "(십몇) - (몇)", "en": "Teens take away"},
	"t11": {"ko": "20까지 더하기", "en": "Adding to 20"},
	"t11g": {"ko": "10 + 10 까지", "en": "Up to 10 + 10"},
	"t12": {"ko": "20까지 빼기", "en": "Subtracting within 20"},
	"t12g": {"ko": "20 이내의 뺄셈", "en": "Take away within 20"},
	"t13": {"ko": "곱셈의 문", "en": "The gate of times"},
	"t13g": {"ko": "몇씩 몇 묶음", "en": "Equal groups"},
	"t14": {"ko": "2단, 5단", "en": "2s and 5s"},
	"t14g": {"ko": "곱셈구구 첫걸음", "en": "First times tables"},
	"t15": {"ko": "3단, 6단", "en": "3s and 6s"},
	"t15g": {"ko": "3단의 두 배가 6단", "en": "6s are double the 3s"},
	"t16": {"ko": "4단, 8단", "en": "4s and 8s"},
	"t16g": {"ko": "4단의 두 배가 8단", "en": "8s are double the 4s"},
	"t17": {"ko": "7단, 9단", "en": "7s and 9s"},
	"t17g": {"ko": "가장 어려운 단", "en": "The hardest tables"},
	"t18": {"ko": "구구단 모두", "en": "All tables"},
	"t18g": {"ko": "곱셈구구 총력전", "en": "All tables mixed"},
}
