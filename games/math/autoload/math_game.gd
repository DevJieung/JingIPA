## 개구리 용사의 게임 상태: 진행도, 통계.
##
## 오토로드 이름: MathGame
##
## ★ 저장 파일은 이제 이 노드가 소유하지 않는다. 통합 앱에서는 Shell 이
##   user://rogame_save.json 하나를 소유하고, 이 노드는 활성 프로필의 "math" 칸을
##   메모리에 펼쳐 놓은 것이다. Shell 이 apply()/dump() 로 주고받는다.
##
## 아래 설정 변수들은 Shell 의 값을 비추는 거울이다 (호출부 100여 곳을 그대로 두려고).
## 쓰기는 반드시 set_* 를 거쳐 Shell 로 간다 — 직접 대입하면 저장되지 않는다.
## (테스트가 fast_animation 을 직접 대입하는 곳이 있는데, 그건 일부러 저장 안 되는 게 맞다.)
extends Node

signal progress_changed
signal settings_changed
signal session_limit_reached

## 한 세션(한 번 앉아서 하는 놀이)의 기본 상한.
## 6~8세 지속주의는 흥미로운 과제에서도 12~20분이고, 수학은 다수 아이에게
## 비선호 과제에 가깝다. 무한히 "더 하기"를 허용하지 않는다.
const DEFAULT_SESSION_LIMIT := 20

# --- 설정 (Shell 의 거울) --------------------------------------------------- #
var sfx_enabled := true
var bgm_enabled := true
## 시연 애니메이션을 짧게 (반복 플레이 / 저사양 기기).
var fast_animation := false
## 배경의 잔잔한 움직임을 끈다.
var reduce_motion := false
## 블록 설명을 통째로 건너뛰고 바로 다음 문제로 간다.
## ★ 아이 화면에서 켤 수 없다 — 형이 동생 학습 장치를 끄는 사고가 났었다.
##   부모 화면에서만 켠다 (프로필별 값이다).
var skip_demo := false
## 표시 언어. "ko" 또는 "en".
var language := "ko"
## 0 이면 세션 제한 없음 (부모 메뉴에서 조절).
var session_limit := DEFAULT_SESSION_LIMIT
## 블록 시연을 답 받기 전에 먼저 보여 준다 (미취학 프로필).
## 이게 꺼져 있으면 5세는 "2 + 3 = ?" 기호식만 보고 골라야 한다 — + 를 모르는 나이다.
var demo_first := false
## 보기 개수. 미취학은 2개.
var choice_count := 4

# --- 진행 ------------------------------------------------------------------ #
## 탄 인덱스(문자열) -> 별 개수 1~3. 없으면 미클리어.
var stars: Dictionary = {}
## 문제 키 -> [맞은 횟수, 틀린 횟수]
var stats: Dictionary = {}
## 오류 유형 태그 -> 누적 횟수 (부모 리포트용)
var error_tags: Dictionary = {}
var totals := {
	"correct": 0,
	"wrong": 0,
	"tiers_cleared": 0,
	"snakes": 0,
	"seconds": 0.0,
}
## 무한 도전 최고 기록.
var endless_best := 0
var last_tier := 0
## 탄 -> 난이도 오프셋 d (-1..+2). 아이 눈에 안 보인다.
var adapt_d: Dictionary = {}
## 탄 -> 시연 단계 m (0..4). 올라가면 설명이 짧아진다 = 보상.
var adapt_m: Dictionary = {}

# --- 이번 세션 (저장하지 않음) --------------------------------------------- #
var session_questions := 0
var session_correct := 0

var rng := RandomNumberGenerator.new()

## 이 게임 화면이 떠 있는 동안에만 시간을 잰다.
## (예전에는 _process 가 무조건 누적해서, 헤드리스 테스트 8분이 매번 통계에 붙었다.)
var _timing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	Shell.session_limit_reached.connect(func(): session_limit_reached.emit())
	pull_settings()


func _process(delta: float) -> void:
	if _timing and Shell.current_game == "frog":
		totals["seconds"] = float(totals.get("seconds", 0.0)) + delta


func set_timing(on: bool) -> void:
	_timing = on


## Shell 에서 설정값을 끌어와 거울을 갱신한다.
func pull_settings() -> void:
	sfx_enabled = Shell.sfx_enabled
	bgm_enabled = Shell.bgm_enabled
	reduce_motion = Shell.reduce_motion
	language = Shell.language
	fast_animation = bool(Shell.tune("fast_animation", false))
	skip_demo = bool(Shell.tune("skip_demo", false))
	session_limit = int(Shell.tune("session_limit", DEFAULT_SESSION_LIMIT))
	demo_first = bool(Shell.tune("demo_first", false))
	choice_count = clampi(int(Shell.tune("choice_count", 4)), 2, 4)
	Loc.lang = language
	settings_changed.emit()


# --------------------------------------------------------------------------- #
# 진행도 (탄 단위)
# --------------------------------------------------------------------------- #

func tier_stars(index: int) -> int:
	return int(stars.get(str(index), 0))


func is_cleared(index: int) -> bool:
	return tier_stars(index) > 0


func is_unlocked(index: int) -> bool:
	if index <= 0:
		return true
	return is_cleared(index - 1)


func highest_unlocked() -> int:
	var best := 0
	for i in Curriculum.tier_count():
		if is_unlocked(i):
			best = i
	return best


func highest_cleared() -> int:
	var best := -1
	for i in Curriculum.tier_count():
		if is_cleared(i):
			best = i
	return best


func all_cleared() -> bool:
	return highest_cleared() >= Curriculum.tier_count() - 1


func world_stars(w: int) -> int:
	var n := 0
	for t in (Curriculum.world(w)["tiers"] as Array):
		n += tier_stars(int(t))
	return n


func world_max_stars(w: int) -> int:
	return (Curriculum.world(w)["tiers"] as Array).size() * 3


func world_unlocked(w: int) -> bool:
	var ts: Array = Curriculum.world(w)["tiers"]
	return ts.is_empty() or is_unlocked(int(ts[0]))


func total_stars() -> int:
	var n := 0
	for k in stars:
		n += int(stars[k])
	return n


func max_stars() -> int:
	return Curriculum.tier_count() * 3


## 이어하기 버튼이 가리킬 탄.
func next_tier() -> int:
	for i in Curriculum.tier_count():
		if not is_cleared(i):
			return i
	return Curriculum.tier_count() - 1


## 탄 결과 기록. 더 좋은 기록만 갱신한다.
func record_tier(index: int, earned: int) -> bool:
	var key := str(index)
	var prev := int(stars.get(key, 0))
	if prev == 0:
		totals["tiers_cleared"] = int(totals.get("tiers_cleared", 0)) + 1
	var improved := earned > prev
	if improved:
		stars[key] = earned
	last_tier = index
	mark_dirty()
	progress_changed.emit()
	return improved


func record_endless(score: int) -> bool:
	if score <= endless_best:
		return false
	endless_best = score
	mark_dirty()
	progress_changed.emit()
	return true


# --------------------------------------------------------------------------- #
# 문제별 통계 + 오류 유형 (부모 리포트, 복습 큐)
# --------------------------------------------------------------------------- #

func record_answer(p: Problem, correct: bool, chosen: int = -1) -> void:
	var k := p.key()
	var e: Array = stats.get(k, [0, 0])
	if correct:
		e[0] = int(e[0]) + 1
		totals["correct"] = int(totals.get("correct", 0)) + 1
	else:
		e[1] = int(e[1]) + 1
		totals["wrong"] = int(totals.get("wrong", 0)) + 1
		var tag := String(p.choice_tags.get(chosen, "unknown"))
		error_tags[tag] = int(error_tags.get(tag, 0)) + 1
	stats[k] = e
	if stats.size() > 900:
		_trim_stats()
	mark_dirty()


func _trim_stats() -> void:
	# 틀린 적 없는 항목부터 버린다 (복습 가치가 낮음).
	var keys := stats.keys()
	keys.sort_custom(func(x, y): return int(stats[x][1]) < int(stats[y][1]))
	for i in range(250):
		if i >= keys.size():
			break
		stats.erase(keys[i])


## 자주 틀린 문제들. [{key, problem, wrong, correct}, ...]
func weak_problems(limit: int = 10) -> Array:
	var out: Array = []
	for k in stats:
		var e: Array = stats[k]
		if int(e[1]) <= 0:
			continue
		var p := Problem.from_key(String(k))
		if p == null:
			continue
		out.append({"key": k, "problem": p, "wrong": int(e[1]), "correct": int(e[0])})
	out.sort_custom(func(x, y):
		if x["wrong"] != y["wrong"]:
			return x["wrong"] > y["wrong"]
		return x["correct"] < y["correct"])
	return out.slice(0, limit)


## 오류 유형 상위 목록. [[tag, count], ...]
func top_error_tags(limit: int = 6) -> Array:
	var out: Array = []
	for t in error_tags:
		out.append([String(t), int(error_tags[t])])
	out.sort_custom(func(x, y): return x[1] > y[1])
	return out.slice(0, limit)


func accuracy() -> float:
	var c := int(totals.get("correct", 0))
	var w := int(totals.get("wrong", 0))
	if c + w <= 0:
		return 0.0
	return float(c) / float(c + w)


# --------------------------------------------------------------------------- #
# 세션
# --------------------------------------------------------------------------- #

## ★ 세션은 이제 Shell 이 센다 — 두 게임을 합쳐서 세야 하기 때문이다.
##   예전에는 이 함수를 타이틀 화면이 불렀는데, 통합 앱에서는 허브 왕복 한 번이
##   카운터를 0 으로 리셋해 상한이 사실상 사라진다.
func begin_session() -> void:
	session_questions = 0
	session_correct = 0
	Shell.begin_session()


func count_session_question(correct: bool) -> void:
	session_questions += 1
	if correct:
		session_correct += 1
	Shell.bump_today("q")
	if correct:
		Shell.bump_today("correct")
	Shell.add_session_units(1)


func session_over_limit() -> bool:
	return Shell.session_over_limit()


# --------------------------------------------------------------------------- #
# 설정
# --------------------------------------------------------------------------- #

## 설정 쓰기는 전부 Shell 로 간다. Shell 이 저장하고 pull_settings() 로 거울을 되돌린다.
func set_sfx(v: bool) -> void:
	Shell.set_sfx(v)


func set_bgm(v: bool) -> void:
	Shell.set_bgm(v)


func set_fast_animation(v: bool) -> void:
	Shell.set_tuning("fast_animation", v)


func set_reduce_motion(v: bool) -> void:
	Shell.set_reduce_motion(v)


func set_skip_demo(v: bool) -> void:
	Shell.set_tuning("skip_demo", v)


func set_language(code: String) -> void:
	Shell.set_language(code)


func set_session_limit(v: int) -> void:
	Shell.set_tuning("session_limit", maxi(0, v))


## 애니메이션 길이 배율.
func anim_scale() -> float:
	return Shell.anim_scale()


# --------------------------------------------------------------------------- #
# 적응형 난이도 (문제 생성 변형 d, 시연 단계 m)
# --------------------------------------------------------------------------- #

## 이 탄의 난이도 오프셋. -1 ~ +2.
func tier_d(tier: int) -> int:
	return clampi(int(adapt_d.get(str(tier), 0)), -1, 2)


## 이 탄의 시연 단계. 0(전체 설명) ~ 4(결과만).
func tier_m(tier: int) -> int:
	return clampi(int(adapt_m.get(str(tier), 0)), 0, 4)


func set_tier_d(tier: int, v: int) -> void:
	adapt_d[str(tier)] = clampi(v, -1, 2)
	mark_dirty()


func set_tier_m(tier: int, v: int) -> void:
	adapt_m[str(tier)] = clampi(v, 0, 4)
	mark_dirty()


## 이 문제 키를 첫 시도에 맞힌 누적 횟수.
## ★ 숙련도의 신호로 응답 시간(초시계)을 쓰지 않는다. 그건 (a) 화면에 안 보이는
##   타이머이고, (b) 아이가 잠깐 자리를 비우면 무너지고, (c) 4지선다 찍기를
##   숙련으로 오독한다(2연속 확률 1/16 -> 20문제 세션에 기대 1.2회 승급).
##   같은 문제를 반복해서 맞혀야만 올라가는 이 값이 유일하게 안전한 신호다.
func mastery(key: String) -> int:
	var e: Array = stats.get(key, [0, 0])
	return int(e[0])


func add_snake_defeated(n: int = 1) -> void:
	totals["snakes"] = int(totals.get("snakes", 0)) + n
	mark_dirty()


# --------------------------------------------------------------------------- #
# 저장 / 불러오기
# --------------------------------------------------------------------------- #

func mark_dirty() -> void:
	Shell.mark_dirty()


## 활성 프로필의 "math" 칸으로 내보낸다. Shell 이 파일에 쓴다.
## ★ 키 이름은 예전 v2 저장 파일과 글자 그대로 같다 — 그래야 이관이 단순 복사가 된다.
func dump() -> Dictionary:
	return {
		"stars": stars,
		"stats": stats,
		"error_tags": error_tags,
		"totals": totals,
		"endless_best": endless_best,
		"last_tier": last_tier,
		"adapt_d": adapt_d,
		"adapt_m": adapt_m,
	}


## 프로필의 "math" 칸을 메모리에 펼친다. Shell 이 부른다 (부팅 / 프로필 전환).
## Migrate.normalize_profile() 이 이미 int() 재조립을 끝낸 딕셔너리가 들어온다.
func apply(d: Dictionary) -> void:
	stars = d.get("stars", {}).duplicate()
	stats = d.get("stats", {}).duplicate()
	error_tags = d.get("error_tags", {}).duplicate()
	totals = d.get("totals", {}).duplicate()
	endless_best = int(d.get("endless_best", 0))
	last_tier = int(d.get("last_tier", 0))
	adapt_d = d.get("adapt_d", {}).duplicate()
	adapt_m = d.get("adapt_m", {}).duplicate()
	progress_changed.emit()


## 부모 메뉴의 "처음부터 다시" — 지금 프로필만 지운다.
## ★ 예전에는 저장 파일 전체를 지웠다. 형제가 한 기기를 쓰면 그건 형 기록을 날리는 지뢰다.
func reset_progress() -> void:
	Shell.reset_profile()
	progress_changed.emit()
