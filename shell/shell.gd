## 앱 셸. 오토로드 이름: Shell
##
## 이 노드가 소유하는 것:
##   - 저장 파일 user://rogame_save.json 하나 (게임별 저장 파일을 두지 않는다)
##   - 기기 설정(소리·잔잔하게·언어) — 사람이 아니라 기기의 속성이다
##   - 프로필 여러 개 (형제가 한 태블릿을 나눠 쓴다)
##   - 집 공용 도감 (누가 찾았든 같은 칸이 찬다)
##   - 게임별 뷰포트 프로파일 적용
##
## 이 노드가 모르는 것: 게임의 내용. 게임은 shell/game_registry.gd 에만 등록된다.
extends Node

signal profile_changed
signal dex_changed
signal settings_changed
signal session_limit_reached

const SAVE_PATH := "user://rogame_save.json"
const SAVE_BACKUP := "user://rogame_save.bak.json"
const SCHEMA := 3

## 이 시간(초) 안에 다시 켜면 마지막 프로필로 바로 들어간다.
## "형이 아침에, 동생이 저녁에" 라는 실제 교대 패턴은 잡고,
## 30분 만에 다시 켜는 같은 아이는 안 붙잡는다.
const ASK_PROFILE_AFTER_SEC := 10800

## 한 세션의 놀이 단위 상한. 셈놀이 문제 1개 = 1, 공룡 방 1개 = 3.
## 근거는 6~8세 지속주의 12~20분. 0 이면 제한 없음.
## ★ 게임별 값은 shell/game_registry.gd 의 journey_units 에 있다 (add_round_units).
##   아래 상수는 등록되지 않은 게임이 물었을 때의 기본값으로만 남아 있다.
const DEFAULT_SESSION_LIMIT := 20
const DINO_ROOM_UNITS := 3

## 허브 화면의 뷰포트 프로파일.
const SHELL_VIEWPORT := {
	"size": Vector2i(1280, 800),
	"keep": false,
	"clear": Color(0.976, 0.945, 0.882),
}

# --- 기기 설정 (프로필과 무관) --------------------------------------------- #
var sfx_enabled := true
var bgm_enabled := true
var reduce_motion := false
var language := "ko"

# --- 집 공용 --------------------------------------------------------------- #
## 종 id -> {"first_by": 프로필id, "first_at": unix, "count": 만난 횟수}
var dex: Dictionary = {}
## 이사 오기 전에 찾은 마리 수 (도감 첫 진입에서 한 번 알려 준다)
var dex_head_start := 0
var dex_greeted := false

# --- 프로필 ---------------------------------------------------------------- #
var profiles: Array = []
var active := 0
var last_played_unix := 0
var _last_profile_id := ""

# --- 실행 중 상태 (저장하지 않음) ------------------------------------------ #
var current_game := ""
var session_units := 0
var session_notified := false

var _dirty := false
var _save_timer := 0.0
## 자동 검증(테스트/셀프테스트)이 아이 기록을 덮지 않게 한다.
var save_disabled := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	save_disabled = OS.has_environment("ROGAME_NO_SAVE")
	_load_or_migrate()


func _process(delta: float) -> void:
	if _dirty:
		_save_timer -= delta
		if _save_timer <= 0.0:
			save_all()


func _notification(what: int) -> void:
	# 모바일에서 홈 버튼을 누르는 순간 프로세스가 죽을 수 있으므로 즉시 저장한다.
	if what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _dirty:
			save_all()


func mark_dirty() -> void:
	_dirty = true
	_save_timer = 1.2


# --------------------------------------------------------------------------- #
# 프로필
# --------------------------------------------------------------------------- #

static func new_profile(id: String, species_id: String, band: String) -> Dictionary:
	return {
		"id": id,
		"badge_species": species_id,
		"age_band": band,          # "pre"(미취학) / "elem"(초등)
		"created_at": 0,
		"ephemeral": false,
		"tuning": default_tuning(band),
		"math": {
			"stars": {}, "stats": {}, "error_tags": {},
			"totals": {"correct": 0, "wrong": 0, "tiers_cleared": 0, "snakes": 0, "seconds": 0.0},
			"endless_best": 0, "last_tier": 0,
			"adapt_d": {}, "adapt_m": {},
		},
		"dino": {
			"best_stage": 1, "lifetime_found": 0, "dex_first_count": 0,
			"skill": 0, "ease_streak": 0, "cushion": 0,
		},
		"daily": [],
	}


## 나이대별 기본 손잡이. 여기 값들이 두 게임의 난이도 전부를 정한다.
static func default_tuning(band: String) -> Dictionary:
	if band == "pre":
		return {
			# 개구리 용사 — 5세가 들어갈 수 있게
			"demo_first": true,      # 블록 시연을 답 받기 전에 보여 준다
			"choice_count": 2,
			"session_limit": 10,
			"skip_demo": false,
			"fast_animation": false,
			# 공룡 찾기
			"dino_min": 2, "dino_max": 3, "dino_step": 8.0,
			"dino_cov_lo": 26, "dino_cov_hi": 52, "dino_cov_ceil": 66,
			"dino_hint_sec": 8.0,
			"dino_dex_hunt": false,
			# 손전등 찾기 — 어린 아이는 빛이 넓고 어둠이 옅다.
			# 이 나이대는 야간공포가 가장 흔한 구간이라 어둠 손잡이를 확실히 벌려 둔다.
			"torch_min": 2, "torch_max": 3, "torch_step": 12.0,
			"torch_cov_lo": 26, "torch_cov_hi": 28, "torch_cov_ceil": 36,
			"torch_props_max": 4,
			"torch_beam": 360.0, "torch_beam_min": 280.0,
			"torch_dark": 0.76, "torch_dark_max": 0.84,
			"torch_hint_sec": 8.0,
			# 참참참 — 어린 아이는 tell(뛸 쪽으로 기우는 것)이 끝까지 크게 남는다.
			# 버릇도 짧고 하늘로는 안 뛴다 (cham_three_at 0 = 없음).
			"cham_len_max": 3, "cham_read_max": 2,
			"cham_tell": 1.0, "cham_tell_min": 0.55, "cham_three_at": 0,
			# 블록 채우기 — 4x4 에서 시작하고, 손이 비면 조각이 저절로 들린다.
			# 그러면 판만 두드려도 놀이가 굴러간다 (트레이를 한 번도 안 봐도 된다).
			"nood_autopick": true,
			"nood_n_min": 4, "nood_n_max": 5,
			"nood_place_min": 2, "nood_place_max": 4,
			"nood_guide_at": 16, "nood_rotate_at": 999,
			"nood_hint_sec": 10.0,
			# 가위바위보 — 카드 두 장에서 시작하고, **"져라"는 아예 안 나온다.**
			# 일부러 지는 것은 억제 조절이라 만 4세에게는 아직 이르다 (규칙 8의 F축이 아니라
			# 그냥 못 하는 것이고, 못 하는 것을 계속 내밀면 그게 평가가 된다).
			# 관계 고리도 절반 아래로는 안 옅어진다.
			"rps_rounds_min": 5, "rps_rounds_max": 6,
			"rps_cards_min": 2, "rps_cards_at": 6,
			"rps_goals_max": 2,
			"rps_help": 1.0, "rps_help_min": 0.55,
		}
	return {
		"demo_first": false,
		"choice_count": 4,
		"session_limit": DEFAULT_SESSION_LIMIT,
		"skip_demo": false,
		"fast_animation": false,
		"dino_min": 3, "dino_max": 6, "dino_step": 4.5,
		"dino_cov_lo": 30, "dino_cov_hi": 58, "dino_cov_ceil": 80,
		"dino_hint_sec": 13.0,
		"dino_dex_hunt": true,
		# 손전등 찾기 — 어둠이 숨기므로 마릿수·가구·가림%는 공룡 찾기보다 낮다.
		# 손전등 반경 하한(200)은 규칙이 아니라 안전장치다: 더 좁히면 방 하나를
		# 훑는 탭 수가 1/r^2 로 늘어 난이도가 아니라 노동이 된다.
		"torch_min": 2, "torch_max": 4, "torch_step": 10.0,
		"torch_cov_lo": 26, "torch_cov_hi": 28, "torch_cov_ceil": 40,
		"torch_props_max": 5,
		"torch_beam": 300.0, "torch_beam_min": 200.0,
		"torch_dark": 0.84, "torch_dark_max": 0.90,
		"torch_hint_sec": 13.0,
		# 참참참 — tell 이 옅어지고 버릇이 길어진다. 24판부터 하늘로도 뛴다.
		"cham_len_max": 4, "cham_read_max": 3,
		"cham_tell": 1.0, "cham_tell_min": 0.15, "cham_three_at": 16,
		"nood_autopick": false,
		"nood_n_min": 4, "nood_n_max": 6,
		"nood_place_min": 3, "nood_place_max": 7,
		"nood_guide_at": 10, "nood_rotate_at": 22,
		"nood_hint_sec": 18.0,
		# 가위바위보 — 처음부터 세 장, 나중에는 "져라"까지. 관계 고리는 끝내 사라진다.
		"rps_rounds_min": 5, "rps_rounds_max": 7,
		"rps_cards_min": 3, "rps_cards_at": 1,
		"rps_goals_max": 3,
		"rps_help": 1.0, "rps_help_min": 0.0,
	}


func profile() -> Dictionary:
	if profiles.is_empty():
		profiles.append(new_profile("p_1", "trex", "elem"))
		active = 0
	return profiles[clampi(active, 0, profiles.size() - 1)]


func tuning() -> Dictionary:
	return profile()["tuning"]


func tune(key: String, fallback: Variant) -> Variant:
	return tuning().get(key, fallback)


func dino_state() -> Dictionary:
	return profile()["dino"]


func profile_color() -> Color:
	var idx := DinoSpecies.index_of(String(profile().get("badge_species", "trex")))
	return DinoSpecies.data(idx)["col"]


## 프로필을 바꾼다. 지금 프로필의 상태를 먼저 거둬들이고 새 프로필을 적용한다.
func switch_profile(index: int) -> void:
	if index < 0 or index >= profiles.size() or index == active:
		return
	_harvest()
	active = index
	_last_profile_id = String(profile()["id"])
	_apply_to_games()
	mark_dirty()
	profile_changed.emit()


func add_profile(species_id: String, band: String) -> int:
	var n := 1
	var used := {}
	for p in profiles:
		used[String(p["id"])] = true
	while used.has("p_%d" % n):
		n += 1
	var p := new_profile("p_%d" % n, species_id, band)
	p["created_at"] = _now()
	profiles.append(p)
	mark_dirty()
	return profiles.size() - 1


## 앱을 켰을 때 프로필을 물어봐야 하는가.
func should_ask_profile() -> bool:
	if profiles.size() <= 1:
		return false
	return _now() - last_played_unix >= ASK_PROFILE_AFTER_SEC


# --------------------------------------------------------------------------- #
# 도감 — 집 공용. 누가 찾았든 같은 칸이 찬다.
# --------------------------------------------------------------------------- #

## 공룡을 한 마리 만났다. 처음이면 true.
func dex_meet(species_id: String) -> bool:
	var first := not dex.has(species_id)
	var e: Dictionary = dex.get(species_id, {"first_by": "", "first_at": 0, "count": 0})
	if first:
		e["first_by"] = String(profile()["id"])
		e["first_at"] = _now()
		var d := dino_state()
		d["dex_first_count"] = int(d.get("dex_first_count", 0)) + 1
	e["count"] = int(e.get("count", 0)) + 1
	dex[species_id] = e
	mark_dirty()
	if first:
		dex_changed.emit()
	return first


func dex_met(species_id: String) -> int:
	return int((dex.get(species_id, {}) as Dictionary).get("count", 0))


## 식구가 된 종 (3번 이상 만남). 도감에서 컬러로 보인다.
func is_family(species_id: String) -> bool:
	return dex_met(species_id) >= FAMILY_MEETS


const FAMILY_MEETS := 3


func family_count() -> int:
	var n := 0
	for k in dex:
		if int((dex[k] as Dictionary).get("count", 0)) >= FAMILY_MEETS:
			n += 1
	return n


func met_count() -> int:
	return dex.size()


## 아직 한 번도 못 만난 종의 인덱스 목록.
func unmet_indices() -> Array[int]:
	var out: Array[int] = []
	for i in DinoSpecies.count():
		if not dex.has(String(DinoSpecies.data(i)["id"])):
			out.append(i)
	return out


# --------------------------------------------------------------------------- #
# 섬 한 바퀴 — 탄이 쭉 이어지는데 게임이 랜덤으로 바뀐다
# --------------------------------------------------------------------------- #
#
# ★ 다음에 무엇이 나올지 **셸이** 정한다. 게임은 "나 한 판 끝났어"만 알린다.
#   그래야 세 번째 게임이 등록되는 순간 저절로 섞인다 — 게임끼리 서로를 몰라도 된다.
#
# 왜 이게 지루함에 듣는가: 두 게임 다 "규칙이 안 바뀌는데 놀라운 것"이 없었다.
# 규칙이 바뀌면 어린 아이는 튕겨내지만(전환 비용), **다음 방이 무엇일지 모르는 것**은
# 규칙을 하나도 안 바꾸면서 예측 오류만 만든다. 전환 비용이 0인 새로움이다.

var journey_active := false
var journey_stage := 1
## 직전에 나온 게임 id 두 개 (같은 게임이 세 번 연속 나오지 않게)
var _journey_recent: Array[String] = []


func journey_best() -> int:
	return int(profile()["dino"].get("journey_best", 1))


## 여행을 시작한다. 이어서 하기.
func journey_begin(from_stage: int = -1) -> void:
	journey_active = true
	journey_stage = maxi(1, from_stage if from_stage > 0 else journey_best())
	_journey_recent.clear()
	profile()["last_game"] = "journey"
	mark_dirty()
	# ★ 첫 탄은 항상 공룡 찾기다. 여행의 첫 60초는 반드시 성공이어야 한다 —
	#   문을 열자마자 셈이 나오면 어린 아이는 그 자리에서 앱을 닫는다.
	_journey_go("dino")


## 한 판이 끝났다. 다음 장소를 고른다.
func journey_advance() -> void:
	if not journey_active:
		return
	journey_stage += 1
	var d: Dictionary = profile()["dino"]
	d["journey_best"] = maxi(int(d.get("journey_best", 1)), journey_stage)
	mark_dirty()
	# 방금 끝난 한 판이 놀이 단위 몇 개인지는 **등록표**가 안다 (journey_units).
	# ★ 예전에는 여기 `if current_game == "dino"` 가 박혀 있었다. 셸이 게임 이름을 아는
	#   자리였고(규칙 15), 그래서 나중에 붙은 게임들(블록 채우기·손전등 찾기)은 여행에서
	#   놀이 단위를 **0으로 세어** 세션 상한이 조용히 늘어나 있었다.
	#   셈놀이는 0 이다 — 문제마다 이미 1씩 센다(count_session_question).
	# ★ round_done() 이 상한을 보고 쉼표까지 찍는다 (세션을 새로 열고 허브로 보낸다).
	#   예전에는 여기서 journey_end() + goto_hub() 만 했고 세션은 안 건드려서,
	#   상한 이후의 「아무거나」가 **한 판만 하고 끝나는 것**을 무한히 반복했다.
	if round_done():
		return
	_journey_go(pick_journey_game())


func journey_end() -> void:
	journey_active = false
	_journey_recent.clear()


## 다음에 나올 게임을 고른다. 가중치 + "세 번 연속 금지".
func pick_journey_game() -> String:
	var band := String(profile()["age_band"])
	var bag: Array[String] = []
	for g in GameRegistry.LIST:
		var id := String(g["id"])
		# 같은 게임이 세 번 연속 나오면 섞는 의미가 없다.
		if _journey_recent.size() >= 2 and _journey_recent[-1] == id and _journey_recent[-2] == id:
			continue
		var w := int((g.get("journey", {}) as Dictionary).get(band, 0))
		for i in w:
			bag.append(id)
	if bag.is_empty():
		return "dino"
	return bag[randi() % bag.size()]


func _journey_go(id: String) -> void:
	_journey_recent.append(id)
	while _journey_recent.size() > 2:
		_journey_recent.pop_front()
	Router.goto_journey(id, journey_stage)


# --------------------------------------------------------------------------- #
# 세션 — 두 게임을 합쳐서 센다
# --------------------------------------------------------------------------- #

func begin_session() -> void:
	session_units = 0
	session_notified = false


## 상한에 닿아 허브로 돌려보냈다 — **그 나감이 곧 쉼이므로 여기서 세션을 새로 연다.**
##
## ★ 이걸 안 하면 상한은 "쉼표"가 아니라 **영구 자물쇠**가 된다. session_units 를
##   0 으로 되돌리는 곳이 앱 부팅(shell/boot.gd) 하나뿐이라, 한 번 넘긴 뒤로는
##   방을 깰 때마다 예외 없이 허브로 튕긴다 — 다시 들어가서 한 방, 또 허브, 또 한 방.
##   아이 눈에는 "다 찾았는데 다음 방이 안 나온다"로만 보인다(규칙 11).
##   게다가 안드로이드는 홈 버튼으로 나가도 프로세스가 살아 있어서 boot.gd 가 다시
##   안 돌고, 그 상태가 **며칠씩** 이어진다. 실제로 물렸다 — 부모가 이 증상으로 신고했다.
##   제한이 없는 것보다 나쁜 상태였다.
func take_session_break() -> void:
	begin_session()


## 한 판이 끝났다. 놀이 단위를 세고, 상한에 닿았으면 **쉼표를 찍고 허브로 보낸다.**
##
## 돌려주는 값이 true 면 게임은 다음 판을 만들지 말고 그냥 돌아가면 된다 —
## 화면을 옮기는 일은 셸이 한다(규칙 15: 게임은 다음에 무엇이 오는지 몰라도 된다).
##
## ★ 게임 쪽에서 제 페이드로 덮은 뒤 Router.goto_hub() 를 부르면 화면이 한 번 깜빡인다:
##   [게임이 덮음 -> cb 가 Router 를 부름 -> 게임이 제 페이드를 되밝힘 -> Router 가 다시 덮음].
##   아이 눈에는 "넘어가려다 실패한 것"으로 보인다. 그래서 덮는 일도 여기 한 곳에 모은다.
func round_done(dev := false) -> bool:
	add_round_units()
	if dev or not session_over_limit():
		return false
	take_session_break()
	journey_end()
	Router.goto_rest()
	return true


## 방금 한 판이 끝났다 — 그 게임의 놀이 단위를 센다.
##
## ★ 몇 단위인지는 **등록표가 안다** (game_registry 의 journey_units). 게임이 숫자를
##   직접 들고 있으면 여행 안(셸이 세는 길)과 밖(게임이 세는 길)이 서로 다른 값을 쓰게 된다 —
##   실제로 참참참에서 2 와 3 으로 갈렸고, 다른 넷은 우연히 같아서 안 드러났을 뿐이다.
func add_round_units() -> void:
	var g := GameRegistry.get_game(current_game)
	add_session_units(int(g.get("journey_units", DINO_ROOM_UNITS)))


func add_session_units(n: int) -> void:
	session_units += n
	var lim := int(tune("session_limit", DEFAULT_SESSION_LIMIT))
	if lim > 0 and session_units >= lim and not session_notified:
		session_notified = true
		session_limit_reached.emit()


func session_over_limit() -> bool:
	var lim := int(tune("session_limit", DEFAULT_SESSION_LIMIT))
	return lim > 0 and session_units >= lim


# --------------------------------------------------------------------------- #
# 오늘 기록 (부모 화면용)
# --------------------------------------------------------------------------- #

func bump_today(key: String, n: int = 1) -> void:
	var p := profile()
	var days: Array = p["daily"]
	var today := Time.get_date_string_from_system()
	var row: Dictionary = {}
	if not days.is_empty() and String((days[-1] as Dictionary).get("d", "")) == today:
		row = days[-1]
	else:
		row = {"d": today, "sec": 0, "q": 0, "correct": 0,
				"dino": 0, "nood": 0, "torch": 0, "cham": 0, "rps": 0}
		days.append(row)
		while days.size() > 14:
			days.pop_front()
	row[key] = int(row.get(key, 0)) + n
	mark_dirty()


# --------------------------------------------------------------------------- #
# 뷰포트 — 게임마다 다른 기준 해상도를 런타임으로 갈아 끼운다
# --------------------------------------------------------------------------- #

## Router 의 페이드가 화면을 완전히 덮은 순간에만 부른다.
func enter_game(id: String) -> void:
	current_game = id
	var g := GameRegistry.get_game(id)
	_apply_viewport(g.get("viewport", SHELL_VIEWPORT))
	var bgm := String(g.get("bgm", ""))
	if bgm.is_empty():
		Audio.stop_bgm()
	else:
		Audio.play_bgm(bgm)


func enter_shell() -> void:
	current_game = ""
	_apply_viewport(SHELL_VIEWPORT)
	Audio.stop_bgm()


func _apply_viewport(v: Dictionary) -> void:
	var w := get_window()
	if w == null:
		return
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_size = v.get("size", SHELL_VIEWPORT["size"])
	w.content_scale_aspect = (Window.CONTENT_SCALE_ASPECT_KEEP if bool(v.get("keep", false))
			else Window.CONTENT_SCALE_ASPECT_EXPAND)
	RenderingServer.set_default_clear_color(v.get("clear", SHELL_VIEWPORT["clear"]))


# --------------------------------------------------------------------------- #
# 설정
# --------------------------------------------------------------------------- #

func set_sfx(v: bool) -> void:
	sfx_enabled = v
	_push_settings()


func set_bgm(v: bool) -> void:
	bgm_enabled = v
	_push_settings()


func set_reduce_motion(v: bool) -> void:
	reduce_motion = v
	_push_settings()


func set_language(code: String) -> void:
	language = "en" if code == "en" else "ko"
	Loc.lang = language
	_push_settings()


func set_tuning(key: String, value: Variant) -> void:
	tuning()[key] = value
	_push_settings()


func _push_settings() -> void:
	mark_dirty()
	settings_changed.emit()
	if MathGame != null:
		MathGame.pull_settings()


## 연출 길이 배율. 잔잔하게가 켜져 있으면 더 짧다.
func anim_scale() -> float:
	if bool(tune("fast_animation", false)):
		return 0.62
	return 0.85 if reduce_motion else 1.0


# --------------------------------------------------------------------------- #
# 저장 / 불러오기
# --------------------------------------------------------------------------- #

func _harvest() -> void:
	# 게임들이 들고 있는 값을 프로필 딕셔너리로 거둬들인다.
	if MathGame != null:
		profile()["math"] = MathGame.dump()


func _apply_to_games() -> void:
	if MathGame != null:
		MathGame.apply(profile()["math"])
		MathGame.pull_settings()


func to_dict() -> Dictionary:
	_harvest()
	return {
		"schema": SCHEMA,
		"app": "rogame",
		"device": {
			"sfx": sfx_enabled,
			"bgm": bgm_enabled,
			"reduce_motion": reduce_motion,
			"language": language,
			"last_profile": _last_profile_id,
			"last_played_unix": last_played_unix,
		},
		"shared": {
			"dex": dex,
			"dex_head_start": dex_head_start,
			"dex_greeted": dex_greeted,
		},
		"profiles": profiles,
	}


func save_all() -> void:
	_dirty = false
	if save_disabled:
		return
	last_played_unix = _now()
	var payload := JSON.stringify(to_dict())
	# 쓰다가 앱이 죽어도 직전 저장은 남도록 백업을 먼저 굴린다.
	if FileAccess.file_exists(SAVE_PATH):
		var prev := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if prev != null:
			var old := prev.get_as_text()
			prev.close()
			var bak := FileAccess.open(SAVE_BACKUP, FileAccess.WRITE)
			if bak != null:
				bak.store_string(old)
				bak.close()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("저장 실패: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(payload)
	f.close()


func _load_or_migrate() -> void:
	var d := _read_json(SAVE_PATH)
	if d.is_empty():
		d = _read_json(SAVE_BACKUP)
	if not d.is_empty() and _has_content(d):
		_apply_dict(d)
		_apply_to_games()
		return
	# 통합 저장이 없거나 비어 있다 — 옛 파일에서 이관한다.
	var leg := _gather_legacy()
	if OS.has_environment("ROGAME_DEBUG"):
		print("[migrate] user:// = ", ProjectSettings.globalize_path("user://"))
		print("[migrate] frog keys = ", leg["frog"].keys())
		print("[migrate] dino = ", leg["dino"])
	var built := Migrate.build(leg)
	if OS.has_environment("ROGAME_DEBUG"):
		print("[migrate] has_content = ", _has_content(built))
	_apply_dict(built)
	_apply_to_games()
	if _has_content(built):
		mark_dirty()


## 스키마만 맞고 내용이 텅 빈 파일(중간에 끊긴 이관 등)은 없는 것으로 친다.
func _has_content(d: Dictionary) -> bool:
	var ps: Array = d.get("profiles", [])
	for p in ps:
		var m: Dictionary = (p as Dictionary).get("math", {})
		var dn: Dictionary = (p as Dictionary).get("dino", {})
		if not (m.get("stars", {}) as Dictionary).is_empty():
			return true
		if int((m.get("totals", {}) as Dictionary).get("correct", 0)) > 0:
			return true
		if int(dn.get("best_stage", 1)) > 1 or int(dn.get("lifetime_found", 0)) > 0:
			return true
	return not (d.get("shared", {}) as Dictionary).get("dex", {}).is_empty()


func _gather_legacy() -> Dictionary:
	var out := {"frog": {}, "dino": {}}
	# ① 같은 샌드박스의 옛 파일
	out["frog"] = _frog_v2("user://save.json")
	if out["frog"].is_empty():
		out["frog"] = _frog_v2("user://save.bak.json")
	out["dino"] = _read_cfg("user://dino_save.cfg")
	# ② 데스크톱이면 옛 앱들의 user_data 폴더도 본다 (개발 편의).
	#    폰에서는 샌드박스가 UID 로 격리돼 있어 이 경로가 존재할 수 없다.
	#    ★ use_custom_user_dir=true 라 user:// 는 ~/.local/share/rogame 이고,
	#      옛 앱들은 ~/.local/share/godot/app_userdata/<앱이름>/ 에 있다.
	if OS.has_feature("pc"):
		# globalize_path 는 끝에 / 를 붙여 돌려준다. 그대로 get_base_dir() 하면
		# 슬래시만 떨어져서 자기 자신이 나온다.
		var base := ProjectSettings.globalize_path("user://").trim_suffix("/").get_base_dir()
		for root in [base.path_join("godot/app_userdata"), base]:
			if out["frog"].is_empty():
				out["frog"] = _frog_v2(root.path_join("개구리 용사/save.json"))
			if out["frog"].is_empty():
				out["frog"] = _frog_v2(root.path_join("개구리 용사/save.bak.json"))
			if out["dino"].is_empty():
				out["dino"] = _read_cfg(root.path_join("공룡을 찾아라!/dino_save.cfg"))
	return out


func _apply_dict(d: Dictionary) -> void:
	var dev: Dictionary = d.get("device", {})
	sfx_enabled = bool(dev.get("sfx", true))
	bgm_enabled = bool(dev.get("bgm", true))
	reduce_motion = bool(dev.get("reduce_motion", false))
	language = "en" if String(dev.get("language", "ko")) == "en" else "ko"
	Loc.lang = language
	_last_profile_id = String(dev.get("last_profile", ""))
	last_played_unix = int(dev.get("last_played_unix", 0))

	var sh: Dictionary = d.get("shared", {})
	dex = {}
	for k in (sh.get("dex", {}) as Dictionary):
		var e: Dictionary = sh["dex"][k]
		dex[String(k)] = {
			"first_by": String(e.get("first_by", "")),
			"first_at": int(e.get("first_at", 0)),
			"count": int(e.get("count", 0)),
		}
	dex_head_start = int(sh.get("dex_head_start", 0))
	dex_greeted = bool(sh.get("dex_greeted", false))

	profiles = []
	for p in (d.get("profiles", []) as Array):
		profiles.append(Migrate.normalize_profile(p))
	if profiles.is_empty():
		profiles.append(new_profile("p_1", "trex", "elem"))

	active = 0
	for i in profiles.size():
		if String(profiles[i]["id"]) == _last_profile_id:
			active = i
			break
	_last_profile_id = String(profile()["id"])


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


## 개구리 용사의 옛 v2 저장 파일만 받아들인다.
## ★ 통합 스키마(v3)로 반쯤 쓰이다 만 파일이 같은 이름으로 남아 있을 수 있다.
##   그걸 v2 로 착각해 읽으면 stars 가 빈 채로 이관이 "성공"해서 아이 기록이 사라진다.
func _frog_v2(path: String) -> Dictionary:
	var d := _read_json(path)
	if d.is_empty():
		return {}
	if d.has("profiles") or d.has("schema") or int(d.get("version", 0)) > 2:
		return {}
	return d


func _read_cfg(path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	return {
		"best_stage": int(cfg.get_value("record", "best_stage", 1)),
		"found": int(cfg.get_value("record", "found", 0)),
	}


func _now() -> int:
	return int(Time.get_unix_time_from_system())


## 부모 화면의 "처음부터 다시" — 지금 프로필만 지운다.
func reset_profile() -> void:
	var p := profile()
	var fresh := new_profile(String(p["id"]), String(p["badge_species"]), String(p["age_band"]))
	fresh["created_at"] = int(p.get("created_at", 0))
	profiles[active] = fresh
	_apply_to_games()
	save_all()
	profile_changed.emit()


## 집 전체 초기화 (도감까지). 더 깊은 곳에 둔다.
func reset_house() -> void:
	dex = {}
	dex_head_start = 0
	dex_greeted = false
	for i in profiles.size():
		var p: Dictionary = profiles[i]
		profiles[i] = new_profile(String(p["id"]), String(p["badge_species"]), String(p["age_band"]))
	active = 0
	_apply_to_games()
	save_all()
	dex_changed.emit()
	profile_changed.emit()
