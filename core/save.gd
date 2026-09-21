extends Node

## 저장 파일 하나(user://save.cfg). 여기 말고 어디서도 파일을 건드리지 않는다.
##
## 세 가지를 담는다:
##   run      평생 기록(최고 탄·판 수·도감)
##   cur      **지금 하던 판 통째로** — 이것이 자동 저장이다
##   opt      설정(배속처럼 판이 바뀌어도 남아야 하는 것)
##
## ★ POCKER_NO_SAVE=1 이면 읽기만 하고 절대 쓰지 않는다.
##   검사기를 돌릴 때마다 저장이 덮여서 "내 기록"이라고 믿던 값이 사실은 테스트가 만든
##   값이던 일이 rogame 에서 실제로 있었다. 같은 실수를 반복하지 않으려고 처음부터 넣는다.

const PATH := "user://save.cfg"
var storage_path: String = PATH
var last_error: Error = OK
var recovered_backup: bool = false

var best_wave: int = 0          ## 여태 간 가장 높은 탄
var runs: int = 0               ## 시작한 판 수
var clears: int = 0             ## 100탄까지 끝낸 판 수
var total_kills: int = 0
var best_hand: int = -1         ## 여태 만든 가장 높은 족보 (Poker.Hand)
var seen_units: Dictionary = {} ## 도감: 한 번이라도 나온 캐릭터 id -> true
var seen_hands: Dictionary = {} ## 족보별 만든 횟수 (int -> int)

## 하다 만 판. 비어 있으면 이어 할 것이 없다.
var cur_run: Dictionary = {}

## 설정 — 판이 끝나도 남는다.
## ★ 배속이 여기 있는 까닭: 사용자가 정한 규칙이다(「배속 설정해놨으면 그거 유지되게」).
##   전투 화면마다 1배로 되돌아가면 100탄을 도는 동안 백 번을 다시 눌러야 한다.
var speed: float = 1.0
var sfx: bool = true
var music: bool = true
var language: String = "ko"

var _readonly: bool = false
## ★ 자동 저장은 **탄마다** 불린다. 값이 하나도 안 바뀌었는데 파일을 다시 쓰면
##   안드로이드에서 눈에 띄게 버벅인다. 마지막으로 쓴 것과 같으면 건너뛴다.
var _last_written: String = ""


func _ready() -> void:
	_readonly = OS.get_environment("POCKER_NO_SAVE") == "1"
	load_file()
	# ★ 안드로이드는 홈 버튼 한 번으로 앱이 통째로 사라질 수 있다. 그때 저장을 못 하면
	#   "게임이 자동저장이 안 된다"가 된다 — 사용자가 제일 급하다고 한 것이 이것이다.
	get_tree().set_auto_accept_quit(false)


## ★ 앱이 뒤로 밀리거나(안드로이드) 창이 닫힐 때 마지막으로 한 번 더 쓴다.
##   화면 전환마다 쓰고 있지만, 전투 한복판에서 홈 버튼을 누르는 것이 제일 흔하다.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_GO_BACK_REQUEST:
			_flush()
		NOTIFICATION_WM_CLOSE_REQUEST:
			_flush()
			get_tree().quit()


func _flush() -> void:
	if Run != null and Run.running and Run.wave > 0:
		# ★ **전투 도중에는 새로 담지 않는다.** 되돌리기는 「그 탄의 처음부터 다시」인데
		#   (Run.restore 주석), 전투 중에 담으면 그 탄에 번 골드와 처치가 담긴 채로
		#   그 탄을 처음부터 다시 하게 된다 — 홈 버튼 한 번에 한 탄 벌이가 공짜로
		#   또 들어오고, 그걸 탄마다 반복하면 골드가 무한이다. 반대로 이미 깨진
		#   크리스탈은 깎인 채로 남아서 그 탄을 온전한 몬스터와 다시 싸운다.
		#   go_battle() 이 그 탄의 **처음**을 이미 담아 뒀으니 그것을 그대로 둔다.
		if Run.phase == Run.Phase.BATTLE \
				and int(cur_run.get("phase", -1)) == Run.Phase.BATTLE \
				and int(cur_run.get("wave", -1)) == Run.wave:
			save_file()
			return
		store_run(Run.snapshot())
	else:
		save_file()


func load_file() -> void:
	var cf := ConfigFile.new()
	recovered_backup = false
	if not _load_checked(cf, storage_path):
		cf = ConfigFile.new()
		if not _load_checked(cf, storage_path + ".bak"):
			return
		recovered_backup = true
	_last_written = ""
	best_wave = cf.get_value("run", "best_wave", 0)
	runs = cf.get_value("run", "runs", 0)
	clears = cf.get_value("run", "clears", 0)
	total_kills = cf.get_value("run", "total_kills", 0)
	best_hand = cf.get_value("run", "best_hand", -1)
	seen_units = cf.get_value("book", "units", {})
	seen_hands = cf.get_value("book", "hands", {})
	cur_run = cf.get_value("cur", "state", {})
	speed = clampf(float(cf.get_value("opt", "speed", 1.0)), 1.0, 3.0)
	sfx = bool(cf.get_value("opt", "sfx", true))
	music = bool(cf.get_value("opt", "music", true))
	language = String(cf.get_value("opt", "language", "ko"))
	if language not in ["ko", "en"]:
		language = "ko"


func save_file() -> bool:
	if _readonly:
		return true
	var cf := ConfigFile.new()
	cf.set_value("run", "best_wave", best_wave)
	cf.set_value("run", "runs", runs)
	cf.set_value("run", "clears", clears)
	cf.set_value("run", "total_kills", total_kills)
	cf.set_value("run", "best_hand", best_hand)
	cf.set_value("book", "units", seen_units)
	cf.set_value("book", "hands", seen_hands)
	cf.set_value("cur", "state", cur_run)
	cf.set_value("opt", "speed", speed)
	cf.set_value("opt", "sfx", sfx)
	cf.set_value("opt", "music", music)
	cf.set_value("opt", "language", language)
	var text := cf.encode_to_text()
	if text == _last_written and last_error == OK:
		return true
	# 먼저 임시 파일을 완성한다. 쓰기 실패는 기존 기록을 건드리지 않는다.
	last_error = cf.save(storage_path + ".tmp")
	if last_error != OK:
		return false
	var previous := ConfigFile.new()
	if _load_checked(previous, storage_path):
		last_error = previous.save(storage_path + ".bak.tmp")
		if last_error != OK:
			return false
		last_error = DirAccess.rename_absolute(storage_path + ".bak.tmp", storage_path + ".bak")
		if last_error != OK:
			return false
	last_error = DirAccess.rename_absolute(storage_path + ".tmp", storage_path)
	if last_error != OK:
		return false
	_last_written = text
	return true


## 문법이 맞아도 값의 형이 깨져 있으면 백업을 읽는다.
func _load_checked(cf: ConfigFile, path: String) -> bool:
	if cf.load(path) != OK:
		return false
	for key in ["best_wave", "runs", "clears", "total_kills", "best_hand"]:
		if not cf.has_section_key("run", key) or not cf.get_value("run", key) is int:
			return false
		if key != "best_hand" and int(cf.get_value("run", key)) < 0:
			return false
	var hand: int = cf.get_value("run", "best_hand", -1)
	if hand < -1 or hand > 9:
		return false
	for key in ["units", "hands"]:
		if not cf.get_value("book", key, {}) is Dictionary:
			return false
	var state: Variant = cf.get_value("cur", "state", {})
	if not state is Dictionary:
		return false
	if not state.is_empty():
		if state.get("v", 0) is int and int(state.get("v", 0)) != Run.SAVE_VERSION:
			# 규칙 버전이 달라도 평생 기록과 설정은 보존한다.
			cf.set_value("cur", "state", {})
		elif not RunValidation.valid(state, Run.SAVE_VERSION):
			return false
	var sp: Variant = cf.get_value("opt", "speed", 1.0)
	return (sp is float or sp is int) and is_finite(float(sp)) \
			and cf.get_value("opt", "sfx", true) is bool \
			and cf.get_value("opt", "music", true) is bool


# --------------------------------------------------------------------------- #
# 하다 만 판 — 자동 저장
# --------------------------------------------------------------------------- #
## 이어 할 판이 있는가. 타이틀의 「이어하기」가 이 값으로 켜진다.
func has_run() -> bool:
	return not cur_run.is_empty() and int(cur_run.get("wave", 0)) > 0


## 하다 만 판이 몇 탄인가(타이틀에 적는다). 없으면 0.
func run_wave() -> int:
	return int(cur_run.get("wave", 0)) if has_run() else 0


## 판을 통째로 적는다. Run.autosave() 하나만 이 함수를 부른다.
## ★ 같은 내용이면 파일을 다시 안 쓴다 — 탄마다 쓰는 것이라 폰에서 티가 난다.
func store_run(d: Dictionary) -> void:
	cur_run = d.duplicate(true)
	save_file()


## 판이 끝났다. 이어 할 것을 지운다 — 안 지우면 죽은 판이 계속 되살아난다.
func clear_run() -> void:
	if cur_run.is_empty():
		return
	cur_run = {}
	_last_written = ""
	save_file()


## 설정 하나가 바뀌었다.
func set_speed(v: float) -> void:
	v = clampf(v, 1.0, 3.0)
	if is_equal_approx(v, speed):
		return
	speed = v
	save_file()


func set_sfx(on: bool) -> void:
	if on == sfx:
		return
	sfx = on
	save_file()
	if not on:
		Sfx.stop_effects()


func set_music(on: bool) -> void:
	if on == music:
		return
	music = on
	save_file()
	Sfx.sync_music()


func set_language(code: String) -> void:
	if code not in ["ko", "en"] or language == code:
		return
	language = code
	save_file()


# --------------------------------------------------------------------------- #
# 평생 기록
# --------------------------------------------------------------------------- #
## 한 판이 끝났을 때 한 번만 부른다.
func record_run(wave: int, kills: int, cleared: bool) -> void:
	best_wave = maxi(best_wave, wave)
	total_kills += kills
	if cleared:
		clears += 1
	# ★ 끝난 판은 이어 할 수 없다. 여기서 안 지우면 죽은 판이 타이틀에 남는다.
	cur_run = {}
	_last_written = ""
	save_file()


## 도감에 실제로 셀 수 있는 캐릭터 수. 표에서 사라진 id 는 빼고 센다.
func seen_count() -> int:
	var n := 0
	for u in Roster.UNITS:
		if seen_units.has(String(u["id"])):
			n += 1
	return n


func record_hand(hand: int, unit_id: String, persist: bool = true) -> void:
	if hand > best_hand:
		best_hand = hand
	seen_hands[hand] = int(seen_hands.get(hand, 0)) + 1
	if unit_id != "":
		seen_units[unit_id] = true
	if persist:
		save_file()
