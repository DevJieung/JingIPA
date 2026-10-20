extends Node

## 저장 파일 하나(user://save.cfg). 여기 말고 어디서도 파일을 건드리지 않는다.
##
## 세 가지를 담는다:
##   run      평생 기록(최고 탄·판 수·도감)
##   cur      **지금 하던 판 통째로** — 이것이 자동 저장이다
##   opt      설정(배속처럼 판이 바뀌어도 남아야 하는 것)
##
## ★ STELLARDEFENSE_NO_SAVE=1 이면 읽기만 하고 절대 쓰지 않는다.
##   검사기를 돌릴 때마다 저장이 덮여서 "내 기록"이라고 믿던 값이 사실은 테스트가 만든
##   값이던 일이 rogame 에서 실제로 있었다. 같은 실수를 반복하지 않으려고 처음부터 넣는다.

const PATH := "user://save.cfg"
var storage_path: String = PATH
var last_error: Error = OK
var recovered_backup: bool = false
## 이름 전환 때 접근 가능한 이전 데스크톱 저장을 읽는다. 원본은 수정하지 않는다.
var legacy_loaded: bool = false
var legacy_storage_paths: PackedStringArray = []

var best_wave: int = 0          ## 여태 간 가장 높은 탄
## 연속 수호전에서 여태 밟아 본 가장 높은 탄(1~Balance.ARENA_STAGES). 옛 웨이브 모드의
## best_wave(최대 100)와 뜻이 달라서 따로 둔다.
var best_stage: int = 0
var runs: int = 0               ## 시작한 판 수
var clears: int = 0             ## 100탄까지 끝낸 판 수
var total_kills: int = 0
## 여태 뽑은 가장 높은 등급(반 별 칸 0~9 · Balance.TIER_ATK).
## ★ 저장 파일의 열쇠는 옛 이름 `best_hand` 그대로다 — 포커 시절의 족보 번호도 같은
##   0~9 였으므로 평생 기록이 그대로 이어진다.
var best_tier: int = -1
var seen_units: Dictionary = {} ## 도감: 한 번이라도 나온 캐릭터 id -> true
var seen_tiers: Dictionary = {} ## 등급별 뽑은 횟수 (int -> int). 파일의 열쇠는 옛 이름 `hands` 다.
## 도감: 캐릭터마다 **여태 얻은 가장 높은 등급**(id -> 반 별 칸 0~9).
## ★ 캐릭터에는 정해진 등급이 없다(Balance.TIER_ATK 의 ★). 그래서 도감이 「이 캐릭터는
##   몇 성」이라고 말할 수 있는 것은 **내가 어디까지 얻어 봤는가**뿐이다.
## ★ 포커 시절에 만난 캐릭터는 seen_units 에만 있고 여기에는 없다 — 그때의 등급은 지금의
##   별과 뜻이 달라서 옮기지 않는다. 그런 캐릭터는 best_of() 가 -1 을 준다.
var unit_best: Dictionary = {}
## 스테이지 사다리(2026-10-19, docs/STAGE_LADDER_2026-10-19.md): 열린 가장 높은 스테이지(1부터), 깬 가장
## 높은 스테이지(0 = 아직 없음), 직전에 깬 스테이지 {stage, theme}(theme 은 테마 id — 표 차례가 바뀌어도
## 남는다). ★ 예전 best_stage · clears 는 해금으로 옮기지 않는다 — 모두 STAGE 1 부터다(PLAN M11).
## 파일에 없으면(옛 저장) 기본값이고, _load_checked 의 필수 키가 아니다.
var stage_unlocked: int = 1
var stage_cleared: int = 0
var last_clear: Dictionary = {}
## Hellbound(끝없는 웨이브)의 최고 웨이브와 마지막으로 고른 영웅 id. 쓰는 곳은 Hellbound 다.
var hell_best_wave: int = 0
var hell_squad: Array = []
## 끝나지 않은 사다리 스테이지의 시드 {스테이지: 시드}(2026-10-19 교차 점검). 같은 스테이지를 깨거나 지기 전에
## 새로 시작하면 같은 시드라 무료 첫 상자도 같다 — 새로 시작해 첫 상자를 다시 굴리는 꼼수를 막는다.
var stage_seeds: Dictionary = {}

## 하다 만 판. 비어 있으면 이어 할 것이 없다.
var cur_run: Dictionary = {}

## 설정 — 판이 끝나도 남는다.
## ★ 배속이 여기 있는 까닭: 사용자가 정한 규칙이다(「배속 설정해놨으면 그거 유지되게」).
##   전투 화면마다 1배로 되돌아가면 100탄을 도는 동안 백 번을 다시 눌러야 한다.
var speed: float = 1.0
var sfx: bool = true
var music: bool = true
var language: String = "ko"
## Frame cap in live battle, 30 or 60 (O8a/M13, 2026-10-19). Phones start at 30 against heat,
## desktops at 60. Every other screen runs at 30 whatever this says (Main.apply_render_budget).
var fps: int = default_fps()

## 구매한 상품(Store 의 id)의 사본. **상점이 원본이다** — 상점이 답하면 그 답으로 덮는다
## (core/store.gd). 연결 없이 켰을 때만 이 사본으로 연다.
var iap_owned: Array = []
## 개발 빌드에서 결제 없이 연 상품. 출시 빌드는 읽지 않는다.
var iap_sandbox: Array = []

var _readonly: bool = false
## ★ 자동 저장은 **탄마다** 불린다. 값이 하나도 안 바뀌었는데 파일을 다시 쓰면
##   안드로이드에서 눈에 띄게 버벅인다. 마지막으로 쓴 것과 같으면 건너뛴다.
var _last_written: String = ""


func _ready() -> void:
	_readonly = OS.get_environment("STELLARDEFENSE_NO_SAVE") == "1"
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
	if Arena != null and Arena.running:
		store_run(Arena.snapshot())
		return
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
	legacy_loaded = false
	if not _load_checked(cf, storage_path):
		cf = ConfigFile.new()
		if not _load_checked(cf, storage_path + ".bak"):
			var found := false
			for source in _legacy_candidates():
				cf = ConfigFile.new()
				if _load_checked(cf, source):
					found = true
					legacy_loaded = true
					break
			if not found:
				return
		else:
			recovered_backup = true
	_last_written = ""
	best_wave = cf.get_value("run", "best_wave", 0)
	var stage_value: Variant = cf.get_value("run", "best_stage", 0)
	best_stage = clampi(int(stage_value), 0, Balance.ARENA_STAGES) if stage_value is int else 0
	runs = cf.get_value("run", "runs", 0)
	clears = cf.get_value("run", "clears", 0)
	total_kills = cf.get_value("run", "total_kills", 0)
	best_tier = cf.get_value("run", "best_hand", -1)
	seen_units = cf.get_value("book", "units", {})
	seen_tiers = cf.get_value("book", "hands", {})
	unit_best = cf.get_value("book", "best", {})
	stage_cleared = _int_in(cf.get_value("run", "stage_cleared", 0), 0, Balance.ARENA_LADDER, 0)
	stage_unlocked = _int_in(cf.get_value("run", "stage_unlocked", 1), 1, Balance.ARENA_LADDER, 1)
	stage_unlocked = maxi(stage_unlocked, mini(stage_cleared + 1, Balance.ARENA_LADDER))
	last_clear = _clear_record(cf.get_value("run", "last_clear", {}))
	hell_best_wave = _int_in(cf.get_value("hell", "best_wave", 0), 0, 1000000, 0)
	hell_squad = _squad(cf.get_value("hell", "squad", []))
	stage_seeds = _seeds(cf.get_value("run", "stage_seeds", {}))
	cur_run = cf.get_value("cur", "state", {})
	speed = clampf(float(cf.get_value("opt", "speed", 1.0)), 1.0, 3.0)
	sfx = bool(cf.get_value("opt", "sfx", true))
	music = bool(cf.get_value("opt", "music", true))
	language = String(cf.get_value("opt", "language", "ko"))
	if language not in ["ko", "en"]:
		language = "ko"
	fps = int(cf.get_value("opt", "fps", default_fps()))
	if fps not in FPS_CHOICES:
		fps = default_fps()
	iap_owned = _strings(cf.get_value("iap", "owned", []))
	iap_sandbox = _strings(cf.get_value("iap", "sandbox", []))


func _legacy_candidates() -> PackedStringArray:
	if not legacy_storage_paths.is_empty():
		return legacy_storage_paths
	if storage_path != PATH or OS.has_feature("mobile"):
		return []
	var parent := OS.get_user_data_dir().get_base_dir()
	var sources := PackedStringArray()
	# These names are retained only as migration sources for previous installations.
	for folder in ["pokerdefense", "allindefense", "AllInDefense"]:
		var source := parent.path_join(folder).path_join("save.cfg")
		sources.append(source)
		sources.append(source + ".bak")
	return sources


func save_file() -> bool:
	if _readonly:
		return true
	var cf := ConfigFile.new()
	cf.set_value("run", "best_wave", best_wave)
	cf.set_value("run", "best_stage", best_stage)
	cf.set_value("run", "runs", runs)
	cf.set_value("run", "clears", clears)
	cf.set_value("run", "total_kills", total_kills)
	cf.set_value("run", "best_hand", best_tier)
	cf.set_value("book", "units", seen_units)
	cf.set_value("book", "hands", seen_tiers)
	cf.set_value("book", "best", unit_best)
	cf.set_value("run", "stage_unlocked", stage_unlocked)
	cf.set_value("run", "stage_cleared", stage_cleared)
	cf.set_value("run", "last_clear", last_clear)
	cf.set_value("hell", "best_wave", hell_best_wave)
	cf.set_value("hell", "squad", hell_squad)
	cf.set_value("run", "stage_seeds", stage_seeds)
	cf.set_value("cur", "state", cur_run)
	cf.set_value("opt", "speed", speed)
	cf.set_value("opt", "sfx", sfx)
	cf.set_value("opt", "music", music)
	cf.set_value("opt", "language", language)
	cf.set_value("opt", "fps", fps)
	cf.set_value("iap", "owned", iap_owned)
	cf.set_value("iap", "sandbox", iap_sandbox)
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
	for key in ["units", "hands", "best"]:
		if not cf.get_value("book", key, {}) is Dictionary:
			return false
	var state: Variant = cf.get_value("cur", "state", {})
	if not state is Dictionary:
		return false
	if not state.is_empty():
		if ArenaValidation.outdated(state):
			# 탄 사슬이 들어오기 전의 판은 이어 할 수 없다. 평생 기록과 설정은 보존한다.
			cf.set_value("cur", "state", {})
		elif state.get("mode") == "arena":
			if not ArenaValidation.valid(state):
				# ★ 그 판만 버린다(2026-10-19). 수치가 바뀌어 하던 판이 맞지 않게 되면(정비 시간 · 부활 횟수 …)
				#   파일째 거부하던 때는 백업도 같은 판을 들고 있어 기본값으로 시작했고, 다음 저장이 해금 · 도감 ·
				#   Hellbound 기록 · 설정을 덮어썼다. 평생 기록은 판과 상관없이 지킨다.
				cf.set_value("cur", "state", {})
		elif state.get("v", 0) is int and int(state.get("v", 0)) != Run.SAVE_VERSION:
			# 규칙 버전이 달라도 평생 기록과 설정은 보존한다.
			cf.set_value("cur", "state", {})
		elif not RunValidation.valid(state, Run.SAVE_VERSION):
			return false
	var sp: Variant = cf.get_value("opt", "speed", 1.0)
	return (sp is float or sp is int) and is_finite(float(sp)) \
			and cf.get_value("opt", "sfx", true) is bool \
			and cf.get_value("opt", "music", true) is bool \
			and cf.get_value("opt", "fps", default_fps()) is int


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


const FPS_CHOICES := [30, 60]


static func default_fps() -> int:
	return 30 if OS.has_feature("mobile") else 60


## The battle frame cap (30 or 60). Main.set_fps() calls this and applies it at once.
func set_fps(v: int) -> void:
	if v not in FPS_CHOICES or v == fps:
		return
	fps = v
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


func _strings(value: Variant) -> Array:
	var out: Array = []
	if value is Array:
		for item in value:
			if item is String and not out.has(item): out.append(item)
	return out


## 정수 칸 하나를 low..high 로 읽는다. 형이 틀리면(손상 · 옛 형식) 기본값이다 — 평생 기록 한 칸이
## 깨졌다고 백업으로 물러나지 않는다(_load_checked 를 조이지 않는다).
static func _int_in(value: Variant, low: int, high: int, fallback: int) -> int:
	return clampi(int(value), low, high) if value is int else fallback


## 직전 클리어 기록. 스테이지 번호가 사다리 안이고 테마 id 가 표에 있을 때만 받는다.
static func _clear_record(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("stage") is int or not value.get("theme") is String:
		return {}
	var number := int(value["stage"])
	if number < 1 or number > Balance.ARENA_LADDER or Roster.theme_by_id(String(value["theme"])).is_empty():
		return {}
	return {"stage": number, "theme": String(value["theme"])}


## Hellbound 에서 고른 영웅 id: 표에 있는 것만, 겹침 없이, 출전 한도까지.
## 스테이지 시드 표: 사다리 안의 스테이지 번호와 0 이 아닌 정수 시드만 받는다.
static func _seeds(value: Variant) -> Dictionary:
	var out := {}
	if value is Dictionary:
		for key in value:
			if key is int and int(key) >= 1 and int(key) <= Balance.ARENA_LADDER and value[key] is int and int(value[key]) != 0:
				out[int(key)] = int(value[key])
	return out


## 그 스테이지의 시드: 끝나지 않은 도전이 있으면 그 시드, 없으면 새로 굴려 적어 둔다(파일은 곧 이어지는
## 자동 저장이 쓴다).
func seed_for_stage(number: int) -> int:
	var kept: Variant = stage_seeds.get(number, 0)
	if kept is int and int(kept) != 0:
		return int(kept)
	var fresh := 0
	while fresh == 0:
		fresh = int(randi())
	stage_seeds[number] = fresh
	return fresh


## 그 스테이지의 도전이 끝났다(깼거나 졌다): 다음 도전은 새 시드로.
func end_stage_seed(number: int) -> void:
	stage_seeds.erase(number)


func _squad(value: Variant) -> Array:
	var out: Array = []
	for id in _strings(value):
		if out.size() < Balance.ARENA_HERO_LIMIT and not Roster.unit_by_id(String(id)).is_empty():
			out.append(id)
	return out


func set_iap_owned(ids: Array) -> void:
	iap_owned = _strings(ids)
	save_file()


func set_iap_sandbox(id: String, on: bool) -> void:
	if on and not iap_sandbox.has(id): iap_sandbox.append(id)
	elif not on: iap_sandbox.erase(id)
	save_file()


func clear_iap_sandbox() -> void:
	iap_sandbox = []
	save_file()


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


## 연속 수호전에서 그 탄을 밟았다. 파일은 부르는 쪽의 자동 저장에 같이 담긴다.
## (2026-10-19 사다리부터는 부르지 않는다 — 옛 10탄 연속 판의 기록이다.)
func note_stage(number: int) -> void:
	best_stage = maxi(best_stage, clampi(number, 0, Balance.ARENA_STAGES))


## Hellbound 한 판이 끝났다(ArenaRun.end_run). 닿은 최고 웨이브만 남기고 사다리 해금·직전 클리어는
## 건드리지 않는다. 파일은 바로 뒤의 record_run 이 쓴다.
func record_hell(wave: int) -> void:
	hell_best_wave = maxi(hell_best_wave, clampi(wave, 0, 1000000))


## 사다리 스테이지 하나가 끝났다(ArenaRun.end_run). 이기면 다음 스테이지가 열리고 깬 최고 기록과
## 직전 클리어가 바뀐다. 지면 아무것도 바뀌지 않는다. 파일은 바로 뒤의 record_run 이 쓴다.
func record_stage(number: int, theme_id: String, won: bool) -> void:
	if not won:
		return
	number = clampi(number, 1, Balance.ARENA_LADDER)
	stage_cleared = maxi(stage_cleared, number)
	stage_unlocked = clampi(maxi(stage_unlocked, number + 1), 1, Balance.ARENA_LADDER)
	last_clear = {"stage": number, "theme": theme_id}


## 결과 화면에서 「수호자의 가호」를 사서 방금 끝난 판을 되살린다. record_run 이 이미 더한
## 처치 수를 되돌려, 그 판이 다시 끝날 때 두 번 세지 않게 한다.
func reopen_run(kills: int) -> void:
	total_kills = maxi(0, total_kills - maxi(0, kills))
	_last_written = ""


## 도감에 실제로 셀 수 있는 캐릭터 수. 표에서 사라진 id 는 빼고 센다.
func seen_count() -> int:
	var n := 0
	for u in Roster.UNITS:
		if seen_units.has(String(u["id"])):
			n += 1
	return n


## 영웅 하나를 뽑았다. 등급 기록과 도감을 함께 올린다.
func record_summon(tier: int, unit_id: String, persist: bool = true) -> void:
	if tier > best_tier:
		best_tier = tier
	seen_tiers[tier] = int(seen_tiers.get(tier, 0)) + 1
	note_unit(unit_id, tier)
	if persist:
		save_file()


## 그 캐릭터를 이 등급으로 가져 봤다(소환 · 지원 소환 · 합성 · 승급). 파일은 안 쓴다 —
## 부르는 쪽이 곧 자동 저장을 하므로 거기에 같이 담긴다.
func note_unit(unit_id: String, tier: int) -> void:
	if unit_id == "":
		return
	seen_units[unit_id] = true
	unit_best[unit_id] = maxi(best_of(unit_id), clampi(tier, 0, Balance.TIER_MAX))


## 그 캐릭터로 여태 얻은 가장 높은 등급(반 별 칸). 기록이 없으면 -1.
func best_of(unit_id: String) -> int:
	var value: Variant = unit_best.get(unit_id, -1)
	return int(value) if value is int or value is float else -1
