extends Node

## 7단계 — **엔진 안에서** 새 파이프라인의 시트가 실제로 도는지 찍는다.
##
## 공식 파이프라인의 `tests/sprite_shot.gd` 와 같은 일을 하되, 저장소의 검사기를 한 줄도
## 안 건드리려고 여기에 따로 뒀다. 이것은 **테스트용 3D 파이프라인 전용**이다.
##
##   godot --path . res://tools/blender3d/godot/b3d_shot.tscn -- \
##         --dir /home/…/build/b3d/estoque/7_sheet --out /home/…/build/b3d/estoque/qc
##
## ★ 시트를 `load()` 가 아니라 `Image.load_from_file()` 로 읽는다. build/ 아래 그림은
##   Godot 이 임포트하기 전에는 res:// 로 못 보는데, 파이프라인을 한 번 돌릴 때마다
##   `--import` 를 다시 돌리게 하면 검사가 아니라 의식이 된다.
##
## 재는 것이 넷이다:
##   1. `SpriteFrames` 가 **가로 한 줄** 시트를 칸으로 제대로 자르는가
##   2. Nearest 필터에서 도트가 안 뭉개지는가 (3배로 같이 그린다)
##   3. **발이 안 튀는가** — 여러 순간을 찍어 바닥선과 겹쳐 본다
##   4. anim.json 의 `anchor`·`scale` 이 `core/anim.gd` 규칙대로 읽히는가
##      (게임과 **같은 산수**로 그려서 키가 맞는지 눈으로 본다)

const BG := Color(0.13, 0.13, 0.16)
const LINE := Color(1, 0.35, 0.35, 0.55)

var dir_path := ""
var out_dir := ""
var meta: Dictionary = {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--dir" and i + 1 < args.size():
			dir_path = String(args[i + 1])
		elif args[i] == "--out" and i + 1 < args.size():
			out_dir = String(args[i + 1])
	if dir_path == "":
		push_error("--dir 이 없습니다")
		get_tree().quit(2)
		return
	if out_dir == "":
		out_dir = dir_path
	DirAccess.make_dir_recursive_absolute(out_dir)

	meta = _read_json(dir_path.path_join("anim.json"))
	if meta.is_empty():
		push_error("anim.json 을 못 읽었습니다: " + dir_path)
		get_tree().quit(2)
		return

	var root := Node2D.new()
	add_child(root)
	var bg := ColorRect.new()
	bg.size = Vector2(1180, 700)
	bg.color = BG
	root.add_child(bg)

	var uid := String(meta.get("name", ""))
	var cell: Dictionary = meta.get("cell", {})
	var cw := int(cell.get("w", 96))
	var ch := int(cell.get("h", 96))
	var anc: Dictionary = meta.get("anchor", {})
	var ax := float(anc.get("x", cw * 0.5))
	var ay := float(anc.get("y", ch))
	var sc := float(meta.get("scale", 1.0))
	var clips: Dictionary = meta.get("clips", {})

	var y := 40
	var report: Array[String] = []
	for cname in ["idle", "walk", "attack"]:
		if not clips.has(cname):
			continue
		var c: Dictionary = clips[cname]
		var n := int(c.get("frames", 0))
		var png := dir_path.path_join("%s_%s.png" % [uid, cname])
		var tex := _tex(png)
		if tex == null:
			report.append("없음: " + png)
			continue
		# ★ 칸 크기는 JSON 의 cell 이 아니라 **그림 폭 ÷ 칸수**로 잰다 (core/anim.gd 와 같게).
		var fw := int(round(float(tex.get_width()) / float(maxi(1, n))))
		var fh := tex.get_height()
		report.append("%s: %d칸 %dx%d (json cell %dx%d)" % [cname, n, fw, fh, cw, ch])

		# 왼쪽 — 낱장을 가로로 (1배)
		for i in range(n):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * fw, 0, fw, fh)
			var s := Sprite2D.new()
			s.texture = at
			s.centered = false
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			s.position = Vector2(40 + i * (fw + 4), y)
			root.add_child(s)
		# 발 바닥선 — 낱장 전부를 가로지른다. 여기서 발이 뜨거나 잠기면 바로 보인다.
		var l := Line2D.new()
		l.points = PackedVector2Array([Vector2(36, y + ay), Vector2(40 + n * (fw + 4), y + ay)])
		l.width = 1.0
		l.default_color = LINE
		root.add_child(l)

		# 오른쪽 — 12fps 로 도는 것을 3배와 **게임 배율**로 둘
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		frames.add_animation(&"a")
		frames.set_animation_speed(&"a", 12.0)
		frames.set_animation_loop(&"a", bool(c.get("loop", cname != "attack")))
		for i in range(n):
			var at2 := AtlasTexture.new()
			at2.atlas = tex
			at2.region = Rect2(i * fw, 0, fw, fh)
			frames.add_frame(&"a", at2)
		for k in range(2):
			var sp := AnimatedSprite2D.new()
			sp.sprite_frames = frames
			sp.animation = &"a"
			sp.centered = false
			sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			# k=0 은 3배 확대, k=1 은 anim.json 의 scale (게임이 그리는 키)
			var m := 3.0 if k == 0 else sc
			sp.scale = Vector2(m, m)
			# ★ 기준점 규칙은 core/anim.gd 와 같다 — 가로 가운데 · 세로 발밑.
			sp.position = Vector2(760 + k * 200 - ax * m, y + 200 - ay * m)
			sp.play()
			root.add_child(sp)
		var gl := Line2D.new()
		gl.points = PackedVector2Array([Vector2(700, y + 200), Vector2(1160, y + 200)])
		gl.width = 1.0
		gl.default_color = LINE
		root.add_child(gl)

		var lb := Label.new()
		lb.text = "%s  %d칸  %dx%d   3배 / 게임배율 %.3f" % [cname, n, fw, fh, sc]
		lb.position = Vector2(40, y + fh + 4)
		lb.add_theme_font_size_override("font_size", 13)
		root.add_child(lb)
		y += maxi(fh, 230) + 34

	for r in report:
		print("  ", r)

	# 여러 순간을 찍는다 — 한 장만 찍으면 발이 튀는지가 안 보인다
	for shot in range(3):
		for i in range(5):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var p := out_dir.path_join("engine_%d.png" % shot)
		img.save_png(p)
		print("찍음: ", p)
	get_tree().quit(0)


func _tex(abs_path: String) -> Texture2D:
	if not FileAccess.file_exists(abs_path):
		return null
	var img := Image.new()
	if img.load(abs_path) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _read_json(abs_path: String) -> Dictionary:
	if not FileAccess.file_exists(abs_path):
		return {}
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}
