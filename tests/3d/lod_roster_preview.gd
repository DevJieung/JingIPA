extends Harness

## 2026-10-15 mobile polygon/texture budget: identical captures before and after the pass.
## Capture only (no verdict on looks): every native hero (49 + Limne) and monster (25)
## through the real factory (StellarModels.hero / monster, adapters, StellarShading), at
## the arena camera's scale and in close-ups, plus the legacy wave-mode BattleScreen at
## its maximum zoom. tools/3d/lod_review.py runs it twice and pairs the pictures.
##
##   godot --path . res://tests/3d/lod_roster_preview.tscn -- --out <dir> [--only grid,zoom,seq,legacy]
##
## The pictures are drawn into an off-screen SubViewport (the window only lends its GL
## context), so the login session's GPU display can render them quickly.

const ARENA_OFFSET := Vector3(-3.0, 19.0, 23.0)
const SAMPLES := ["brasa", "echo", "pip", "limne"]
const MONSTER_SAMPLES := ["drop_slime", "frost_imp", "abyss_leviathan"]
var out_dir := "build/character-3d/lod-2026-10-15/review/before"
var film: SubViewport
var stage: Node3D
var camera: Camera3D
var only: PackedStringArray = []
var clock := 10.0

func _ready() -> void:
	if not require_no_save(): return
	out_dir = arg("--out", out_dir)
	only = arg("--only", "grid,zoom,seq,legacy").split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(96, 60)
	film = SubViewport.new()
	film.size = Vector2i(1280, 800)
	film.own_world_3d = true
	film.transparent_bg = false
	film.msaa_3d = Viewport.MSAA_2X
	film.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(film)
	stage = Node3D.new()
	film.add_child(stage)
	StellarLighting.setup(stage)
	StellarLighting.apply_arena(stage)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color("#56664f")
	soil.roughness = 1.0
	ground.material_override = soil
	stage.add_child(ground)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = 0.1
	camera.far = 200
	stage.add_child(camera)
	camera.current = true
	await frames(2)
	if "grid" in only or "zoom" in only or "seq" in only:
		await _models()
	if "legacy" in only:
		await _legacy()
	print("LOD roster captures: " + out_dir)
	finish("LOD roster capture")

func _arena_camera(target: Vector3, size: float) -> void:
	camera.size = size
	camera.position = target + ARENA_OFFSET
	camera.look_at(target + Vector3(0, 0.4, 0), Vector3.UP)

func _front_camera(target: Vector3, size: float, height: float) -> void:
	camera.size = size
	camera.position = target + Vector3(0, height * 0.55, 12)
	camera.look_at(target + Vector3(0, height * 0.5, 0), Vector3.UP)

func _shot(name: String) -> void:
	await frames(1)
	await RenderingServer.frame_post_draw
	film.get_texture().get_image().save_png(out_dir + "/" + name + ".png")

func _hero_units() -> Array:
	var units: Array = []
	for unit in Roster.UNITS:
		var id := String(unit["id"])
		if id == "limne" or NativeCharacterModel.has_model(id): units.append(unit)
	return units

func _monster_rows() -> Array:
	var rows: Array = []
	for data in Roster.MONSTERS:
		if NativeMonsterModel.has_model(String(data["id"])): rows.append(data)
	return rows

## Pose every actor the same way: idle, mid-stride walk toward the camera, attack release.
func _pose(actors: Array, pose: String) -> void:
	clock += 3.0
	for item in actors:
		var model: Node3D = item["node"]
		if item["hero"]:
			model.animate_visual(clock, 9.0, 0.3, true)
	if pose == "walk":
		for frame in range(26):
			clock += 1.0 / 60.0
			for item in actors:
				var model: Node3D = item["node"]
				if item["hero"]:
					model.set_locomotion(Vector3(0, 0, 3.4), 1.0 / 60.0)
					model.face_toward(Vector2(0, 1), 1.0 / 60.0)
					model.animate_visual(clock, 9.0, 0.3, true)
				else:
					model.face_toward(Vector2(0, 1), 1.0 / 60.0)
					model.animate_visual(clock, true)
		return
	for frame in range(20):
		clock += 1.0 / 60.0
		for item in actors:
			var model: Node3D = item["node"]
			if item["hero"]:
				model.set_locomotion(Vector3.ZERO, 1.0 / 60.0)
				model.face_toward(Vector2(0, 1), 1.0 / 60.0)
				model.animate_visual(clock, 9.0, 0.3, true)
			else:
				model.face_toward(Vector2(0, 1), 1.0 / 60.0)
				model.set_siege(-1.0)
				model.animate_visual(clock, false)
	if pose == "attack":
		for item in actors:
			var model: Node3D = item["node"]
			if item["hero"]:
				if model is NativeCharacterModel:
					model.visual_event({"t": "aim", "w": 0.3, "d": Vector2(0, 1)})
					model.animate_visual(clock, 0.3, 0.3, true)
					model.visual_event({"t": "fire", "d": Vector2(0, 1)})
					model.animate_visual(clock + 0.065, 0.365, 0.3, true)
				else:
					model.animate_visual(clock, 0.365, 0.3, true)
			else:
				model.set_siege(0.42)
				model.animate_visual(clock, false)

func _spawn_all() -> Array:
	var actors: Array = []
	var heroes := _hero_units()
	for i in range(heroes.size()):
		var model := StellarModels.hero(heroes[i], 0)
		stage.add_child(model)
		model.position = Vector3((i % 10 - 4.5) * 2.4, 0.03, (i / 10 - 2) * 2.6)
		actors.append({"node": model, "hero": true, "id": String(heroes[i]["id"]), "home": model.position})
	var monsters := _monster_rows()
	for i in range(monsters.size()):
		var data: Dictionary = monsters[i]
		var model := StellarModels.monster(data)
		stage.add_child(model)
		var boss := String(data.get("kind", "")) == "boss"
		model.position = Vector3(((i - 20) - 2.0) * 4.4, 0.04, 30.0) if boss else Vector3((i % 10 - 4.5) * 2.4, 0.04, 20.0 + (i / 10) * 2.6)
		if model.has_method("visual_event"): model.visual_event("spawn", {})
		actors.append({"node": model, "hero": false, "id": String(data["id"]), "home": model.position, "boss": boss})
	await frames(3)
	# Let the spawn rise finish before any picture.
	for n in range(150):
		clock += 1.0 / 60.0
		for item in actors:
			if not item["hero"]: item["node"].animate_visual(clock, false)
	return actors

func _models() -> void:
	var actors := await _spawn_all()
	var heroes: Array = actors.filter(func(a): return a["hero"])
	var monsters: Array = actors.filter(func(a): return not a["hero"])
	for pose in ["idle", "walk", "attack"]:
		await _pose(actors, pose)
		for item in actors: item["node"].position = item["home"]
		if "grid" in only:
			film.size = Vector2i(1280, 800)
			_arena_camera(Vector3(0, 0, 0), ArenaWorld.CAMERA_SIZE)
			await _shot("grid_heroes_" + pose)
			_arena_camera(Vector3(0, 0, 0), ArenaWorld.CAMERA_SIZE / 3.0)
			await _shot("grid_heroes_x3_" + pose)
			_arena_camera(Vector3(0, 0, 24.0), ArenaWorld.CAMERA_SIZE)
			await _shot("grid_monsters_" + pose)
			_arena_camera(Vector3(-2.0, 0, 22.0), ArenaWorld.CAMERA_SIZE / 2.4)
			await _shot("grid_monsters_x2_" + pose)
		if "zoom" in only:
			film.size = Vector2i(560, 720)
			for item in actors:
				var model: Node3D = item["node"]
				_solo(actors, model)
				var h := 1.7 if item["hero"] else float(NativeMonsterModel.manifest()["monsters"][item["id"]].get("height", 1.0)) * (2.0 if item.get("boss", false) else 1.0)
				_arena_camera(model.position + Vector3(0, h * 0.3, 0), maxf(1.2, h * 1.55))
				await _shot("zoom_%s_%s" % [item["id"], pose])
				if pose == "idle":
					_front_camera(model.position, maxf(1.2, h * 1.45), h)
					await _shot("front_%s" % item["id"])
			_solo(actors, null)
	if "seq" in only:
		film.size = Vector2i(560, 720)
		await _sequences(heroes, monsters)
	film.size = Vector2i(1280, 800)
	for item in actors: item["node"].queue_free()
	await frames(3)

## Continuous close-up frames of the sample models: idle -> aim/fire -> walk in place.
func _sequences(heroes: Array, monsters: Array) -> void:
	for item in heroes + monsters:
		if not (item["id"] in SAMPLES or item["id"] in MONSTER_SAMPLES): continue
		var model: Node3D = item["node"]
		var h := 1.7 if item["hero"] else float(NativeMonsterModel.manifest()["monsters"][item["id"]].get("height", 1.0)) * (2.0 if item.get("boss", false) else 1.0)
		model.position = item["home"]
		_solo(heroes + monsters, model)
		var frame := 0
		var start := clock + 5.0
		clock = start
		for n in range(72):
			clock += 1.0 / 30.0
			var t := clock - start
			if item["hero"]:
				if n == 12:
					if model is NativeCharacterModel: model.visual_event({"t": "aim", "w": 0.3, "d": Vector2(0, 1)})
				if n == 21 and model is NativeCharacterModel: model.visual_event({"t": "fire", "d": Vector2(0, 1)})
				var age := (t - 0.4) if n >= 12 and n < 40 else 9.0
				var walking := n >= 40
				model.set_locomotion(Vector3(0, 0, 3.4) if walking else Vector3.ZERO, 1.0 / 30.0)
				model.face_toward(Vector2(0, 1), 1.0 / 30.0)
				model.animate_visual(clock, age, 0.3, true)
			else:
				model.face_toward(Vector2(0, 1), 1.0 / 30.0)
				model.set_siege(fposmod(t, 1.2) / 1.2 if n >= 24 and n < 48 else -1.0)
				model.animate_visual(clock, n >= 48)
			if n >= 40 and item["hero"]:
				model.position = item["home"]   # walk in place: the gait is read on the body
			_arena_camera(model.position + Vector3(0, h * 0.3, 0), maxf(1.2, h * 1.55))
			await _shot("seq_%s_%02d" % [item["id"], frame])
			frame += 1
		model.position = item["home"]
	_solo(heroes + monsters, null)

## Close-ups show one actor alone (null shows everyone again).
func _solo(actors: Array, keep: Node3D) -> void:
	for item in actors:
		item["node"].visible = keep == null or item["node"] == keep

## Legacy wave-mode BattleScreen (StellarView: zoom 0.8..1.8, orbit) at its maximum zoom.
func _legacy() -> void:
	stage.visible = false
	camera.current = false
	film.size = Vector2i(1280, 800)
	film.size_2d_override = Vector2i(1280, 800)
	film.size_2d_override_stretch = true
	var main: Node2D = load("res://game/main.gd").new()
	film.add_child(main)
	await frames(3)
	I18n.set_locale("ko")
	Fixture.prepare(16, 20261015)
	Run.heroes.clear()
	Run.bench.clear()
	for id in ["brasa", "echo", "pip", "limne", "kari", "jokull", "triton", "lind", "chispa", "brigid", "donn", "dummy"]:
		Run.gain_hero(Roster.unit_by_id(id), 4)
	Run.ensure_posts()
	main.go_battle()
	var screen = main.screen
	await frames(5)
	screen.set_process(false)
	for n in range(240):
		screen._process(1.0 / 60)
	await frames(3)
	await _main_shot(screen, "legacy_battle")
	var world: StellarWorld = screen.view_3d.world
	for index in range(4):
		var hero: Dictionary = Run.heroes[index]
		var at := StellarWorld.world(Run.hero_position(hero))
		world.zoom = 1.8
		world.camera_target = Vector3(clampf(at.x, -3, 3), 0, clampf(at.z, -3, 3))
		world.camera_update()
		for n in range(3): screen._process(1.0 / 60)
		await _main_shot(screen, "legacy_zoom_%s" % String(hero["unit"]["id"]))
	main.queue_free()
	await frames(3)

func _main_shot(screen: CanvasItem, name: String) -> void:
	screen.queue_redraw()
	await frames(2)
	await RenderingServer.frame_post_draw
	film.get_texture().get_image().save_png(out_dir + "/" + name + ".png")
