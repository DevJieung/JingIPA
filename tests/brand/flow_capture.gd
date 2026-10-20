extends Harness

## D4 continuous capture (2026-10-19): the real cold start (game/boot.tscn) — MindMorph logo,
## loading cover with the key art, the title — then the title's own ways out: the stage select,
## Hellbound locked (no DLC: the shop sheet) and Hellbound owned (the squad picker).
##   godot --path . --resolution 1280x800 --fixed-fps 60 res://tests/brand/flow_capture.tscn -- --out <dir>
## Writes numbered frames (every --every frames during the boot, one per step after) and steps.json.

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

var out_dir := "res://build/feedback-2026-10-19/D4/flow"
var _n := 0
var _steps: Array = []


func _ready() -> void:
	if not require_no_save():
		return
	out_dir = arg("--out", out_dir)
	var every := int(arg("--every", "6"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	Run.running = false
	Arena.running = false
	Save.cur_run.clear()
	Save.stage_unlocked = 13
	Save.stage_cleared = 12
	Save.last_clear = {"stage": 12, "theme": String(Roster.THEMES[Arena.ladder_theme(12)]["id"])}
	var boot: Node = load("res://game/boot.tscn").instantiate()
	add_child(boot)
	var main: Node = null
	for frame in range(900):
		await get_tree().process_frame
		main = boot.get_node_or_null("Main")
		var cover := false
		for child in boot.get_children():
			var script: Script = child.get_script()
			if script != null and script.get_global_name() in ["StartupSplash", "StartupLoading"]:
				cover = true
		if frame % every == 0:
			await _shot("boot f%03d" % frame)
		if not cover and main != null and main.interactive:
			break
	check(main != null and main.screen is TitleScreen, "title reached after the cold start")
	if main == null or not main.screen is TitleScreen:
		finish("D4 flow capture")
		return
	var title: TitleScreen = main.screen
	await frames(20)
	await _shot("title")
	check(tap(title, "stages"), "stage select opens")
	await frames(6)
	await _shot("stage select")
	title.stage_select.action("stage:page:-1")
	await frames(4)
	await _shot("stage select chapter 1")
	title.close_overlay()
	_shop([])
	await frames(6)
	await _shot("title, Hellbound locked")
	check(tap(title, "hell"), "Hellbound (locked) opens the shop sheet")
	await frames(10)
	await _shot("Hellbound locked: shop sheet")
	title.close_overlay()
	_shop([Store.GUARDIAN])
	await frames(6)
	await _shot("title, Hellbound owned")
	check(tap(title, "hell"), "Hellbound (owned) opens the squad picker")
	await frames(10)
	await _shot("Hellbound owned: squad picker")
	title.close_overlay()
	var f := FileAccess.open(out_dir.path_join("steps.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_steps, "\t"))
	f.close()
	finish("D4 flow capture")


func _shop(owned: Array) -> void:
	var shop := TestShop.new()
	shop.owned = owned.duplicate()
	Save.iap_owned = []
	Save.iap_sandbox = []
	Store._owned.clear()
	Store.use_backend(shop)


func _shot(label: String) -> void:
	var file := "%03d.png" % _n
	_n += 1
	await snap(out_dir.path_join(file))
	_steps.append({"file": file, "label": label})
