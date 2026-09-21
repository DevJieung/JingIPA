extends Node

## 스프라이트 시트가 **엔진 안에서** 실제로 도는지 찍는다 (sprite_pipeline.md Step 5).
##
## ★ 커맨드라인을 읽는 코드는 tests/ 에만 둔다 (CLAUDE.md 19).
##
##   godot --headless --path . res://tests/sprite_shot.tscn -- --route sdxl --out build/sprite
##
## 재는 것이 셋이다:
##   1. `AnimatedSprite2D` + `SpriteFrames` 가 시트를 **가로 1행**으로 제대로 자르는가
##   2. `default_texture_filter=0`(Nearest) 에서 도트가 안 뭉개지는가
##   3. 12fps 로 돌 때 **발이 안 튀는가** — 공통 크롭이 실제로 먹었는지는
##      여기서 여러 칸을 한 판에 겹쳐 찍어야만 보인다

const SIZE := 96
const FPS := 12.0
const ANIMS := {"idle": 8, "attack": 12}

## ★ 로스터에서 **그때그때 읽는다.** 예전에는 시범 다섯의 id 가 여기 박혀 있었는데,
##   설계서 rev.2 로 캐릭터를 통째로 갈아 끼우자 다섯 다 없는 id 가 됐다.
##   등급마다 하나씩 골라 열 명을 본다 — 배율(to_game 의 scale)이 등급마다 달라서
##   한 등급만 보면 「로열이 하이카드와 같은 키로 선다」를 못 잡는다.
static func _units() -> Array:
	var out: Array = []
	for t in range(10):
		var pool: Array = Roster.units_of_tier(t)
		if not pool.is_empty():
			out.append(String(pool[t % pool.size()]["id"]))
	return out


var route := "sdxl"
var out_dir := "build/sprite"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--route" and i + 1 < args.size():
			route = String(args[i + 1])
		elif args[i] == "--out" and i + 1 < args.size():
			out_dir = String(args[i + 1])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	var root := Node2D.new()
	add_child(root)
	var bg := ColorRect.new()
	bg.size = Vector2(SIZE * 3 * 6 + 80, SIZE * 3 * 2 + 120)
	bg.color = Color(0.18, 0.18, 0.21)
	root.add_child(bg)

	var missing: Array[String] = []
	var col := 0
	for uid in _units():
		var row := 0
		for anim in ANIMS:
			var n: int = ANIMS[anim]
			var path := "res://art/sprite/%s/unit_%s_%s_%dx%d_%d.png" % [route, uid, anim, SIZE, SIZE, n]
			if not ResourceLoader.exists(path):
				missing.append(path)
				row += 1
				continue
			var tex: Texture2D = load(path)
			var sf := SpriteFrames.new()
			sf.remove_animation("default")
			sf.add_animation(&"a")
			sf.set_animation_speed(&"a", FPS)
			sf.set_animation_loop(&"a", true)
			for i in range(n):
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * SIZE, 0, SIZE, SIZE)
				sf.add_frame(&"a", at)
			var sp := AnimatedSprite2D.new()
			sp.sprite_frames = sf
			sp.animation = &"a"
			sp.scale = Vector2(3, 3)
			sp.centered = false
			# 발이 같은 바닥선에 서는지 보려고 **밑변**을 맞춘다
			sp.position = Vector2(40 + col * SIZE * 3, 40 + row * (SIZE * 3 + 40))
			sp.play()
			root.add_child(sp)

			var lb := Label.new()
			lb.text = "%s\n%s" % [uid, anim]
			lb.position = sp.position + Vector2(0, SIZE * 3 + 2)
			lb.add_theme_font_size_override("font_size", 13)
			root.add_child(lb)
			row += 1
		col += 1

	if not missing.is_empty():
		print("없는 시트 %d장:" % missing.size())
		for m in missing:
			print("  ", m)

	# 여러 순간을 찍는다 — 한 장만 찍으면 발이 튀는지가 안 보인다
	for shot in range(3):
		for i in range(int(FPS / 3.0)):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var p := "%s/godot_%s_%d.png" % [out_dir, route, shot]
		img.save_png(ProjectSettings.globalize_path(p))
		print("찍음: ", p)
	get_tree().quit(0)
