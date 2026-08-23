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
##   frost:<탄>     전투 + 서리 부적 — 얼음(둔화) 연출을 찍으려고 일부러 얼린다
##   shop:<탄>      상점 (능력치 탭)
##   shopw / shopi / shopp / shoph :<탄>   상점의 무기 · 아이템 · 패시브 · 영웅 탭
##   swap:<탄>      안뜰이 꽉 찼을 때 뜨는 영웅 교체 창
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
	# ★ 안뜰은 여섯 자리뿐이다. 사람이라면 센 여섯을 세워 두므로 검사 정책과 같은 손으로
	#   정리해 둔다 — 안 그러면 사진 속 안뜰이 "먼저 뽑은 여섯"이라 실제 화면과 다르다.
	PlayPolicy.arrange(Run)
	# 상점을 몇 번 거친 것처럼 능력치도 조금 올려 둔다 — 빈 상점은 실제 화면이 아니다.
	Run.levels["atk"] = int(wave / 3)
	Run.levels["rate"] = int(wave / 5)
	Run.levels["rng"] = int(wave / 6)
	# 무기와 아이템도 조금 쥐여 준다. 빈 칸만 찍으면 새 화면이 제대로 도는지 안 보인다.
	Run.weapons.clear()
	if wave >= 4:
		Run.weapons.append("longbow")
	if wave >= 8:
		Run.weapons.append("repeater")
	if wave >= 12:
		Run.weapons.append("scope")
	Run.items.clear()
	if wave >= 3:
		Run.items["bomb"] = 2
		Run.items["freeze"] = 1


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


## 지금 얼어붙어 있는(둔화가 걸린) 몬스터 수. 얼음 사진을 기다리는 데만 쓴다.
func _frozen_count(sim) -> int:
	var n := 0
	for mo in sim.monsters:
		if float(mo["slow_t"]) > 0.0:
			n += 1
	return n


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
		"battle", "frost":
			var bw: int = maxi(1, arg)
			_prepare(bw)
			# ★ 전투에 들어설 때는 그 탄의 영웅까지 **이미 받은** 상태다
			#   (뽑기 → 확정 → 전투). _prepare 는 뽑기 화면 기준이라 한 명이 모자라고,
			#   1탄이면 아예 0명이라 아무도 안 쏴서 사진이 통째로 거짓말이 된다.
			Run.begin_draw()
			Run.confirm_hand()
			PlayPolicy.arrange(Run)
			Run.wave = bw
			# 얼음은 맞는 족족 얼어붙어야 한 장에 담긴다. 서리 부적을 쥐여 준다.
			if what == "frost":
				Run.passives["frost"] = true
			var b := BattleScreen.new()
			main._swap(b)
			await _frames(2)
			# 몬스터가 길을 반쯤 돌아 안팎 두 겹에 다 깔렸을 때를 찍는다.
			# 앞 탄은 그 전에 전멸시켜 버리므로 더 일찍 찍는다.
			var want: float = 20.0 if bw >= 8 else 9.0
			for i in range(4000):
				await get_tree().process_frame
				if b.sim.done:
					break
				# ★ 얼음 사진은 "얼어붙은 놈이 화면에 여럿 있는 순간"을 기다린다.
				#   시간만 재고 찍으면 하필 아무도 안 맞은 프레임이 걸려서 얼음이 한
				#   조각도 안 나온다(실제로 그렇게 두 장을 버렸다).
				if what == "frost":
					if b.sim.elapsed > 6.0 and _frozen_count(b.sim) >= 3:
						break
					if b.sim.elapsed > 26.0:
						break
					continue
				if b.sim.elapsed > want:
					break
			await _save("%s%d" % [what, bw])
		"shop", "shopw", "shopi", "shopp", "shoph":
			_prepare(maxi(1, arg))
			Run.wave = maxi(1, arg)
			var sc := ShopScreen.new()
			main._swap(sc)
			sc.tab = {"shop": "u", "shopw": "w", "shopi": "i", "shopp": "p",
					"shoph": "h"}[what]
			await _frames(6)
			await _save("%s%d" % [what, arg])
		"swap":
			# 안뜰을 서로 다른 여섯으로 꽉 채운 뒤 한 명을 더 받는다 — 교체 창이 뜨는 상황.
			_prepare(maxi(1, arg))
			Run.wave = maxi(1, arg)
			Run.heroes.clear()
			Run.bench.clear()
			for i in range(Roster.UNITS.size() - 1, -1, -1):
				if Run.heroes.size() >= Balance.HERO_SLOTS:
					break
				var uu: Dictionary = Roster.UNITS[i]
				Run.gain_hero(uu, int(uu["tier"]))
			for t2 in [3, 2, 1]:
				Run.gain_hero(Roster.units_of_tier(t2)[0], t2)
			Run.begin_draw()
			# ★ 안뜰(7~9등급)에도 대기석(1~3등급)에도 없는 등급으로 뽑는다. 겹쳐 버리면
			#   교체 창이 안 뜨고 엉뚱한 사진이 찍힌다.
			_stack(4)
			var d2 := DrawScreen.new()
			main._swap(d2)
			await _frames(2)
			d2._confirm()
			for i in range(2000):
				await get_tree().process_frame
				if d2.state == DrawScreen.SWAP:
					break
			await _frames(4)
			await _save("swap%d" % arg)
		"over":
			_prepare(24)
			Run.wave = 24
			Run.end_run(false)
			main._swap(OverScreen.new())
			await _frames(20)
			await _save("over")
		_:
			printerr("모르는 화면: %s" % spec)
