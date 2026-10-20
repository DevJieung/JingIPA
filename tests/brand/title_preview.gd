extends Harness

## D4 title and stage-select captures (2026-10-19): the brand layout over the real Main.
##   godot --path . --resolution 1280x800 res://tests/brand/title_preview.tscn -- --out <dir> [--locales ko,en]
## States: first launch, last clear (STAGE 12), saved run, stage select (chapter 1 all cleared,
## chapter 2 in progress, chapter 3 locked), Hellbound locked (no DLC: padlock -> shop sheet) and
## owned (ember -> squad picker). Nothing is written (STELLARDEFENSE_NO_SAVE).

class TestShop extends RefCounted:
	const NAME := "test"
	var store: Node
	var owned: Array = []
	func start() -> void: store.set_owned(owned)
	func sells(_id: String) -> bool: return true
	func refresh() -> void: store.set_owned(owned)
	func restore() -> void:
		store.set_owned(owned)
		store.finish_restore(true)
	func buy(_product: Dictionary) -> void: pass

var out_dir := "res://build/feedback-2026-10-19/D4/title"
var main: Node2D
var _errors = preload("res://tests/log_errors.gd").new()


func _ready() -> void:
	if not require_no_save():
		return
	OS.add_logger(_errors)
	out_dir = arg("--out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	Run.running = false
	Arena.running = false
	Save.cur_run.clear()
	main = load("res://game/main.gd").new()
	add_child(main)
	await frames(8)
	for code in arg("--locales", "ko,en").split(",", false):
		I18n.set_locale(code)
		await _states(code)
	check(_errors.count() == 0, "no errors logged (%d)" % _errors.count())
	for line in _errors.lines:
		printerr("   " + line)
	OS.remove_logger(_errors)
	finish("D4 title previews")


func _shop(owned: Array) -> void:
	var shop := TestShop.new()
	shop.owned = owned.duplicate()
	Save.iap_owned = []
	Save.iap_sandbox = []
	Store._owned.clear()
	Store.use_backend(shop)


func _title() -> TitleScreen:
	main.show_title()
	await frames(4)
	return main.screen as TitleScreen


func _shot(name: String, code: String) -> void:
	await frames(3)
	await snap(out_dir.path_join("%s_%s.png" % [code, name]))


func _states(code: String) -> void:
	# 1. first launch: nothing cleared, the shop sells the DLC (Hellbound locked)
	_shop([])
	Save.stage_unlocked = 1
	Save.stage_cleared = 0
	Save.last_clear = {}
	Save.best_stage = 0
	Save.best_tier = -1
	Save.cur_run = {}
	var title := await _title()
	check(title != null, "title shown")
	await _shot("title_first", code)
	# 2. veteran: STAGE 12 cleared last, the DLC owned
	_shop([Store.GUARDIAN])
	var theme12 := String(Roster.THEMES[Arena.ladder_theme(12)]["id"])
	Save.stage_unlocked = 13
	Save.stage_cleared = 12
	Save.last_clear = {"stage": 12, "theme": theme12}
	Save.best_stage = 12
	Save.best_tier = 7
	title = await _title()
	await _shot("title_last_clear", code)
	# 2b. the longest record: STAGE 100 on the longest English field name (two lines, >= 18 px)
	Save.last_clear = {"stage": 100, "theme": "glacier_crevasse"}
	title = await _title()
	await _shot("title_long_record", code)
	Save.last_clear = {"stage": 12, "theme": theme12}
	# 3. a saved run on STAGE 13
	Save.cur_run = {"mode": "arena", "stage": 13, "wave": 3}
	title = await _title()
	await _shot("title_resume", code)
	# 3b. a saved Hellbound run deep into the endless waves (the longest resume line)
	Save.cur_run = {"mode": "arena", "stage": 13, "wave": 3, "hell": true, "sim": {"wave_no": 128}}
	title = await _title()
	await _shot("title_resume_hell", code)
	Save.cur_run = {}
	title = await _title()
	# 4. stage select: chapter 2 (in progress), chapter 1 (cleared), chapter 3 (locked)
	check(tap(title, "stages"), "stages opens")
	await paint(title)
	await _shot("stages_ch2", code)
	check(tap(title, "stage:page:-1"), "previous page")
	await paint(title)
	await _shot("stages_ch1", code)
	title.stage_select.action("stage:page:1")
	title.stage_select.action("stage:page:1")
	await paint(title)
	await _shot("stages_ch3", code)
	title.close_overlay()
	await paint(title)
	# 5. Hellbound owned: the squad picker
	check(tap(title, "hell"), "hell opens (owned)")
	await paint(title)
	await _shot("hell_owned", code)
	title.close_overlay()
	# 6. Hellbound locked: padlock on the title, the shop sheet on tap
	_shop([])
	title = await _title()
	await _shot("title_hell_locked", code)
	check(tap(title, "hell"), "hell opens (locked)")
	await paint(title)
	await _shot("hell_locked_store", code)
	title.close_overlay()
	await paint(title)
