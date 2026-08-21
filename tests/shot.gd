extends Node

## 화면을 PNG 로 찍는 전용 진입점.
##
## ★ 커맨드라인을 읽는 코드는 **여기에만** 둔다. 게임 쪽(core/ · game/)이 인자를 읽으면
##   검사기와 촬영이 서로의 인자를 삼키고 get_tree().quit() 이 촬영 도중 앱을 죽인다.
##
##   godot --path . res://tests/shot.tscn -- --shots title,draw:5,reveal:9,battle:12,shop:8,over \
##         --out build/shots
##
## 찍을 수 있는 것:
##   title          타이틀
##   draw:<탄>      카드 다섯 장 고르는 화면
##   reveal:<족보>  족보 확정 연출 (0=하이카드 … 9=로열). 풀하우스 이상이 화려한 쪽이다.
##   battle:<탄>    전투 (몇 초 굴린 뒤)
##   shop:<탄>      상점
##   over           끝 화면

var out_dir := "build/shots"
var shots: Array = []
var main: Node2D = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--shots" and i + 1 < args.size():
			shots = String(args[i + 1]).split(",", false)
		elif args[i] == "--out" and i + 1 < args.size():
			out_dir = String(args[i + 1])
	if shots.is_empty():
		shots = ["title"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	main = load("res://game/main.gd").new()
	main.name = "Main"
	add_child(main)
	await get_tree().process_frame

	for s in shots:
		await _one(String(s))
	print("찍은 곳: %s" % out_dir)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name_]
	img.save_png(path)
	print("  %s  %dx%d" % [path, img.get_width(), img.get_height()])


## 원하는 탄까지 상태를 만든다(영웅 n명 · 골드 넉넉히).
func _prepare(wave: int) -> void:
	Run.start_run(20260822)
	Run.gold = 400 + wave * 90
	for i in range(maxi(0, wave - 1)):
		Run.begin_draw()
		Run.confirm_hand()
	# 상점을 몇 번 거친 것처럼 능력치도 조금 올려 둔다 — 빈 상점은 실제 화면이 아니다.
	Run.levels["atk"] = int(wave / 3)
	Run.levels["rate"] = int(wave / 5)
	Run.levels["rng"] = int(wave / 6)


## 원하는 족보가 나오도록 카드를 손으로 깔아 준다.
func _stack(hand: int) -> void:
	# ★ `var c := Poker.code` 처럼 static 함수를 변수에 담아 c(...) 로 부르면
	#   "Function c() not found in base self" 로 **파스 자체가** 깨진다. 그냥 풀어 쓴다.
	var sets := {
		0: [Poker.code(14, 0), Poker.code(10, 1), Poker.code(7, 2), Poker.code(5, 3), Poker.code(3, 0)],
		1: [Poker.code(11, 0), Poker.code(11, 1), Poker.code(7, 2), Poker.code(5, 3), Poker.code(3, 0)],
		2: [Poker.code(11, 0), Poker.code(11, 1), Poker.code(7, 2), Poker.code(7, 3), Poker.code(3, 0)],
		3: [Poker.code(9, 0), Poker.code(9, 1), Poker.code(9, 2), Poker.code(5, 3), Poker.code(3, 0)],
		4: [Poker.code(9, 0), Poker.code(8, 1), Poker.code(7, 2), Poker.code(6, 3), Poker.code(5, 0)],
		5: [Poker.code(14, 2), Poker.code(10, 2), Poker.code(8, 2), Poker.code(5, 2), Poker.code(3, 2)],
		6: [Poker.code(12, 0), Poker.code(12, 1), Poker.code(12, 2), Poker.code(6, 3), Poker.code(6, 0)],
		7: [Poker.code(8, 0), Poker.code(8, 1), Poker.code(8, 2), Poker.code(8, 3), Poker.code(13, 0)],
		8: [Poker.code(9, 1), Poker.code(8, 1), Poker.code(7, 1), Poker.code(6, 1), Poker.code(5, 1)],
		9: [Poker.code(14, 0), Poker.code(13, 0), Poker.code(12, 0), Poker.code(11, 0), Poker.code(10, 0)],
	}
	var cards: Array[int] = []
	for x in sets[hand]:
		cards.append(int(x))
	Run.cards = cards
	Run.rerolled = [0, 0, 0, 0, 0]
	Run.paid = [0, 0, 0, 0, 0]


func _one(spec: String) -> void:
	var parts := spec.split(":")
	var what := parts[0]
	var arg := int(parts[1]) if parts.size() > 1 else 0
	match what:
		"title":
			main._swap(TitleScreen.new())
			await _frames(6)
			await _save("title")
		"draw":
			_prepare(maxi(1, arg))
			Run.begin_draw()
			main._swap(DrawScreen.new())
			await _frames(6)
			await _save("draw%d" % arg)
		"reveal":
			_prepare(8)
			Run.begin_draw()
			_stack(arg)
			var d := DrawScreen.new()
			main._swap(d)
			await _frames(2)
			d._confirm()
			# 이름이 뜨고 영웅이 나온 순간을 찍는다 (연출의 절정)
			for i in range(100):
				await get_tree().process_frame
				if d.rt > 1.55:
					break
			await _save("reveal%d" % arg)
		"battle":
			_prepare(maxi(1, arg))
			Run.wave = maxi(1, arg)
			var b := BattleScreen.new()
			main._swap(b)
			await _frames(2)
			# 몬스터가 다 나오고 한창 싸울 때를 찍는다
			for i in range(1200):
				await get_tree().process_frame
				if b.sim.elapsed > 12.0 or b.sim.done:
					break
			await _save("battle%d" % arg)
		"shop":
			_prepare(maxi(1, arg))
			Run.wave = maxi(1, arg)
			main._swap(ShopScreen.new())
			await _frames(6)
			await _save("shop%d" % arg)
		"over":
			_prepare(24)
			Run.wave = 24
			Run.end_run(false)
			main._swap(OverScreen.new())
			await _frames(20)
			await _save("over")
		_:
			printerr("모르는 화면: %s" % spec)
