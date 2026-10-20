extends Node2D
## 보석상자 의식 미리보기 (F10/F11, D1) — 게임 상태 없이 가짜 카드로 연출만 돌린다.
##
## 손으로 보기:
##   godot --path . res://tests/box_preview.tscn
##   클릭/탭 = 화면의 존(건너뛰기 · 고르기 · 다시 뽑기 · 확인), 키 1~5 = 그 등급의 새 상자,
##   F = 빠른 박자 전환, R = 다시 뽑기, S = 건너뛰기, P = 가장 좋은 카드 고르기.
## 촬영(tests/box_review.py 가 부른다):
##   godot --path . --resolution 1280x800 res://tests/box_preview.tscn -- --shot=DIR --scene=full
##        --tier=3 --stars=1,2,3,2,1 [--fast] [--reroll-at=0.4 --reroll-tier=4 --reroll-stars=...]
##        [--pick-at=0.5 --pick=2] [--skip-at=1.0] [--from=0 --dur=5 --fps=30 --every=1] [--lang=en] [--bg=PNG]
## 촬영은 실제 시간이 아니라 1/fps 씩 시계를 밀고 매 프레임을 그린 뒤 PNG 로 남긴다 — 느린 기계에서도
## 같은 시각이면 같은 그림이다.

const BoxCeremony := preload("res://game/box_ceremony.gd")

var show = BoxCeremony.new()
var ui := Ui.new()
var age := 0.0
var pick_age := -1.0
var bg: Texture2D = null
var opts: Dictionary = {}
var free := 1
var _rng := RandomNumberGenerator.new()
var _sound := true
var _reroll_stars: Array = []
## 그리기 비용(마이크로초): 보통 층 + 빛 층, 프레임마다.
var _cost_base := 0
var _cost_light := 0
var _reroll_units: Array = []

const UNITS := ["brasa", "caden", "brigid", "echo", "niamh", "morrigan", "galene", "lugh", "sigrid", "thalassa"]


func _ready() -> void:
	_rng.seed = 7
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if opts.has("lang"):
		I18n.set_locale(String(opts["lang"]))
	var bg_path := String(opts.get("bg", ""))
	if not bg_path.is_empty() and FileAccess.file_exists(bg_path):
		var img := Image.load_from_file(bg_path)
		if img != null:
			bg = ImageTexture.create_from_image(img)
	free = int(opts.get("free", "1"))
	_new_box(int(opts.get("tier", "3")), _ints(String(opts.get("stars", "1,2,3,2,1"))), opts.has("fast"),
			_strs(String(opts.get("units", ",".join(UNITS.slice(0, 5))))))
	_reroll_stars = _ints(String(opts.get("reroll-stars", "2,4,3,2,3")))
	_reroll_units = _strs(String(opts.get("reroll-units", ",".join(UNITS.slice(5, 10)))))
	if opts.has("shot"):
		_sound = false
		set_process(false)
		_shoot.call_deferred()


static func _ints(s: String) -> Array:
	var out: Array = []
	for part in s.split(",", false):
		out.append(int(part))
	return out


static func _strs(s: String) -> Array:
	var out: Array = []
	for part in s.split(",", false):
		out.append(part.strip_edges())
	return out


## 가짜 카드 — 미리보기의 모양은 Arena.card_preview(i) 와 같다. 다섯 장이 새 영웅 · 강화 ·
## 최대를 골고루 보이도록 자리마다 정해 둔다.
func _cards(stars: Array, ids: Array) -> Array:
	var out: Array = []
	var guaranteed := 0
	var best := -1
	for i in range(stars.size()):
		if int(stars[i]) > best:
			best = int(stars[i])
			guaranteed = i
	for i in range(stars.size()):
		var s := clampi(int(stars[i]), 1, 5)
		var t := s * 2 - 1
		var kind: String = ["new", "growth", "new", "growth", "new"][i % 5]
		var pv := {"kind": kind, "before_tier": maxi(0, t - 4) if kind == "growth" else -1, "after_tier": maxi(1, t - 3) if kind == "growth" else t,
			"added_points": (t + 1) * 2, "maxed": kind == "growth" and i == 3 and s >= 4, "where": "bench" if i == 4 else "field",
			"joker": opts.has("joker")}
		if bool(pv["maxed"]):
			pv["after_tier"] = 9
		var unit := Roster.unit_by_id(String(ids[i % ids.size()]))
		out.append({"unit": unit, "stars": s, "guaranteed": i == guaranteed, "preview": pv})
	return out


func _new_box(t: int, stars: Array, quick: bool, ids: Array) -> void:
	show.begin(t, _cards(stars, ids), quick)
	show.free_rerolls = free
	show.can_reroll = free > 0
	show.free_box = opts.has("free-box")
	show.anti_air = opts.has("anti-air")
	show.immune_body = String(opts.get("immune", ""))
	age = 0.0
	pick_age = -1.0


func _reroll(t: int, stars: Array, ids: Array) -> void:
	if free <= 0:
		return
	free -= 1
	show.begin_reroll(t, _cards(stars, ids))
	show.free_rerolls = free
	show.can_reroll = free > 0
	age = 0.0


func _pick(i: int) -> void:
	var card: Dictionary = show.cards[i]
	var pv: Dictionary = card["preview"]
	var res := pv.duplicate()
	res["growth_points"] = 6 if String(pv["kind"]) == "growth" else 0
	res["growth_needed"] = 8 + int(pv["after_tier"]) * 2
	res["joker"] = opts.has("joker")
	res["bumped"] = opts.has("eye")
	if res["bumped"]:
		res["after_tier"] = int(res["after_tier"]) + 1
	show.begin_pick(i, res)
	pick_age = 0.0


func _process(dt: float) -> void:
	age += dt
	if pick_age >= 0.0:
		pick_age += dt
	show.advance(age, pick_age, dt, _sound)
	queue_redraw()


func _draw() -> void:
	ui.begin()
	if bg != null:
		draw_texture_rect(bg, Look.SCREEN, false)
	else:
		draw_rect(Look.SCREEN, Look.BG)
	# The game's way: one canvas, no extra canvas items (ArenaBoxView draws on the screen).
	var t0 := Time.get_ticks_usec()
	show.draw_all(self, ui, age, pick_age)
	_cost_base = Time.get_ticks_usec() - t0


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_action(ui.hit(e.position))
	elif e is InputEventMouseButton and not e.pressed:
		ui.pressed = ""
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				var t: int = e.keycode - KEY_0
				var stars: Array = []
				for i in range(5):
					stars.append(clampi(_rng.randi_range(1, 3) + (1 if _rng.randf() < 0.15 else 0), 1, 5))
				stars[_rng.randi_range(0, 4)] = maxi(t, _rng.randi_range(t, 5) if _rng.randf() < 0.2 else t)
				free = 1
				_new_box(t, stars, show.fast, UNITS.slice(0, 5))
			KEY_F:
				show.fast = not show.fast
			KEY_R:
				_action("box:reroll")
			KEY_S:
				_action("box:skip")
			KEY_P:
				var best := 0
				for i in range(show.cards.size()):
					if int(show.cards[i]["stars"]) > int(show.cards[best]["stars"]):
						best = i
				_action("box:pick:%d" % best)


func _action(id: String) -> void:
	if id.is_empty() or id == "modal:block":
		return
	ui.pressed = id
	if id == "box:skip":
		age = show.skip_target(age)
	elif id == "box:reroll" and show.is_ready(age, pick_age):
		var t: int = maxi(show.tier, mini(5, show.tier + (1 if _rng.randf() < 0.5 else 0)))
		_reroll(t, _reroll_stars, _reroll_units)
	elif id.begins_with("box:pick:") and show.is_ready(age, pick_age):
		_pick(int(id.get_slice(":", 2)))
	elif id == "close":
		free = 1
		_new_box(show.tier, _ints(String(opts.get("stars", "1,2,3,2,1"))), true, UNITS.slice(0, 5))


## 촬영: 대본(--reroll-at · --pick-at · --skip-at)을 시각에 맞춰 누르고, 매 프레임을 남긴다.
func _shoot() -> void:
	var out := String(opts["shot"])
	DirAccess.make_dir_recursive_absolute(out)
	var fps := float(opts.get("fps", "30"))
	var dt := 1.0 / fps
	var start := float(opts.get("from", "0"))
	var dur := float(opts.get("dur", str(show.settle_time() + 1.2)))
	var every := maxi(1, int(opts.get("every", "1")))
	var reroll_at := float(opts.get("reroll-at", "-1"))
	var pick_at := float(opts.get("pick-at", "-1"))
	var skip_at := float(opts.get("skip-at", "-1"))
	var settle_first := opts.has("settled")
	if settle_first:
		age = show.settle_time() + 2.0
	for k in range(3):
		await RenderingServer.frame_post_draw
	var t := 0.0
	var n := 0
	var saved := 0
	var report: Array = []
	while t <= dur + 0.0001:
		if reroll_at >= 0.0 and t >= reroll_at and t - dt < reroll_at:
			_reroll(int(opts.get("reroll-tier", str(show.tier))), _reroll_stars, _reroll_units)
		if pick_at >= 0.0 and t >= pick_at and t - dt < pick_at:
			_pick(int(opts.get("pick", "0")))
		if skip_at >= 0.0 and t >= skip_at and t - dt < skip_at:
			age = show.skip_target(age)
		show.advance(age, pick_age, dt, false)
		queue_redraw()
		await RenderingServer.frame_post_draw
		if t >= start - 0.0001 and n % every == 0:
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/%04d.png" % [out, saved])
			report.append({"frame": saved, "t": snappedf(t, 0.001), "age": snappedf(age, 0.001), "pick": snappedf(pick_age, 0.001),
				"particles": show.alive(), "ready": show.is_ready(age, pick_age), "draw_us": _cost_base + _cost_light})
			saved += 1
		age += dt
		if pick_age >= 0.0:
			pick_age += dt
		t += dt
		n += 1
	var meta := {"settle": show.settle_time(), "plan": {"burst": show.plan.get("burst", 0.0), "deal0": show.plan.get("deal0", 0.0),
		"settle": show.plan.get("settle", 0.0), "ready": show.plan.get("ready", 0.0)}, "frames": report,
		"max_particles": report.reduce(func(m, r): return maxi(m, int(r["particles"])), 0),
		"draw_us_max": report.reduce(func(m, r): return maxi(m, int(r["draw_us"])), 0),
		"draw_us_mean": report.reduce(func(m, r): return m + int(r["draw_us"]), 0) / maxi(1, report.size())}
	var f := FileAccess.open(out + "/meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, " "))
	f.close()
	print("BOX_PREVIEW_DONE frames=%d settle=%.2f max_particles=%d" % [saved, show.settle_time(), int(meta["max_particles"])])
	get_tree().quit(0)
