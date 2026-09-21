extends Harness

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
##   layers         영웅 발밑에 광역 공격·희귀 착탄·전체 섬광을 겹친 가림 현상 재현
##   frost:<탄>     전투 + 서리 부적 — 얼음(둔화) 연출을 찍으려고 일부러 얼린다
##   stun:<탄>      전투 + 전기 영웅 여섯 — 마비 연출을 찍으려고 일부러 감전시킨다
##   dbg:<탄>       전투 + **디버그 오버레이**(F3) — 흐름 탭
##   dbgh / dbgm / dbgt :<탄>              오버레이의 영웅 · 몬스터 · 표 탭
##   shop:<탄>      상점 (능력치 탭)
##   shopp / shopc :<탄>                   상점의 패시브 · 크리스탈 탭
##   theme:<탄>                            그 탄의 테마 판
##   result:<탄>                           라운드 전과 판(영웅별 피해·처치)
##   bullets:<탄>   속성이 다른 영웅 여섯을 세워 놓고 **탄이 여러 발 날 때**를 찍는다
##   zone:<탄>      전투 + **장판** 영웅 넷 — 지목한 자리에 깔린 원을 찍는다
##   zone1:<탄>     전투 + 장판 영웅 **하나** — 원 한 장이 어떻게 그려지는지 보는 쪽
##   swap:<탄>      성역이 꽉 찬 채로 새 영웅이 왔을 때의 편성 판
##   team:<탄>      자리가 남을 때의 편성 판 (탄마다 뜨는 보통의 모습)
##   hall:<탄>      전당이 한 창을 넘겼을 때의 편성 판 (굴림 막대 · 「N / M」 쪽 번호)
##   info:<id>      지정한 영웅의 상세 정보 (info:all = 모든 영웅)
##   over           끝 화면

## 촬영용 판의 씨앗. 같은 씨앗이라야 같은 사진이 다시 나온다.
const SEED := 20260822

var out_dir := "build/shots"
var shots: Array = []
var main: Node2D = null


func _ready() -> void:
	shots = arg("--shots", "").split(",", false)
	out_dir = arg("--out", out_dir)
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
	main.queue_free()
	main = null
	await frames(2)
	get_tree().quit(0)


func _save(name_: String) -> void:
	var path := "%s/%s.png" % [out_dir, name_]
	var img := await snap(path)
	print("  %s  %dx%d" % [path, img.get_width(), img.get_height()])


## 지금 얼어붙어 있는(둔화가 걸린) 몬스터 수. 얼음 사진을 기다리는 데만 쓴다.
func _frozen_count(sim) -> int:
	var n := 0
	for mo in sim.monsters:
		if float(mo["slow_t"]) > 0.0:
			n += 1
	return n

## 지금 마비된 몬스터가 몇 마리인가. 촬영이 "아크가 여럿 보이는 순간"을 기다리는 데 쓴다.
func _stunned_count(sim) -> int:
	var n := 0
	for mo in sim.monsters:
		if float(mo.get("stun_t", 0.0)) > 0.0:
			n += 1
	return n



func _one(spec: String) -> void:
	main.menu.close()
	var parts := spec.split(":")
	var what := parts[0]
	var arg := int(parts[1]) if parts.size() > 1 else 0
	match what:
		"monsters":
			var preview = load("res://tests/monster_preview.gd").new()
			main._swap(preview)
			preview.set_process(false)
			preview.time = float(arg) / 12.0
			preview.queue_redraw()
			await frames(3)
			await _save("monsters%d" % arg)
		"rarity":
			main._swap(load("res://tests/rarity_preview.gd").new())
			await frames(3)
			await _save("rarity")
		"info":
			Fixture.prepare(13, SEED)
			Run.passives.clear()
			Run.heroes.clear()
			Run.bench.clear()
			for hu in Roster.UNITS:
				Run.gain_hero(hu, int(hu["tier"]))
			Run.begin_draw()
			Run.confirm_hand()
			var details := DrawScreen.new()
			details.formation_tab = false
			main._swap(details)
			await frames(3)
			var requested := parts[1] if parts.size() > 1 else "niamh"
			for hu in Roster.UNITS:
				if requested != "all" and requested != String(hu["id"]):
					continue
				for i in range(Run.heroes.size()):
					if Run.heroes[i]["unit"]["id"] == hu["id"]:
						details.hv.info = i
				for i in range(Run.bench.size()):
					if Run.bench[i]["unit"]["id"] == hu["id"]:
						details.hv.info = HeroView.BENCH + i
				details.queue_redraw()
				await frames(3)
				await _save("info_" + String(hu["id"]))
		"menu", "rules", "hands", "elements":
			Fixture.prepare(12, SEED)
			Run.begin_draw()
			Run.confirm_hand()
			main.go_battle()
			await frames(6)
			main.menu.open()
			main.menu.page = what
			await frames(3)
			await _save(what)
		"title":
			# ★ 인자를 주면 **하다 만 판이 있는 타이틀**을 찍는다. 단추가 둘이 되는 갈래는
			#   이것 말고는 찍을 길이 없어서, 「새로 시작」이 평생 기록 줄을 덮는 버그가
			#   사진에도 검사에도 한 번도 안 걸렸다.
			if arg > 0:
				Fixture.prepare(arg, SEED)
				Run.begin_draw()
				Save.store_run(Run.snapshot())
			else:
				Save.clear_run()
			main._swap(TitleScreen.new())
			await frames(6)
			await _save("title%s" % ("%d" % arg if arg > 0 else ""))
		"draw":
			Fixture.prepare(maxi(1, arg), SEED)
			Run.begin_draw()
			main._swap(DrawScreen.new())
			await frames(6)
			await _save("draw%d" % arg)
		"reveal":
			Fixture.prepare(8, SEED)
			Run.begin_draw()
			Fixture.stack(arg)
			var d := DrawScreen.new()
			main._swap(d)
			await frames(2)
			d._confirm()
			# 이름이 뜨고 영웅이 나온 순간을 찍는다 (연출의 절정)
			for i in range(240):
				await get_tree().process_frame
				if d.rt > 2.4:
					break
			await _save("reveal%d" % arg)
		"biome":
			Fixture.prepare(21, SEED)
			var body: String = Battlefield.BODIES[clampi(arg, 0, 4)]
			for i in range(Roster.THEMES.size()):
				if String(Roster.THEMES[i]["main_body"]) == body:
					Run.themes[Balance.theme_block(Run.wave)] = i
					break
			Run.phase = Run.Phase.BATTLE
			var b := BattleScreen.new()
			main._swap(b)
			b.set_process(false)
			await frames(3)
			await _save("biome%d" % arg)
		"halltabs", "newfield":
			Fixture.prepare(24, SEED)
			Run.heroes.clear()
			Run.bench.clear()
			Run.wave = 1
			for u in Roster.UNITS.slice(0, 3 if what == "newfield" else Roster.UNITS.size()):
				Run.gain_hero(u, int(u["tier"]))
			Run.wave = 24
			Run.begin_draw()
			Fixture.stack(4)
			var d := DrawScreen.new()
			main._swap(d)
			await frames(2)
			d._confirm()
			d._after_reveal()
			await frames(3)
			await _save(what)
		"map", "move", "report12", "layers":
			Fixture.prepare(24, SEED)
			Run.heroes.clear()
			Run.bench.clear()
			for el in Balance.ELEM_ORDER:
				for tier in [2, 5, 8]:
					for u in Roster.units_of_tier(tier):
						if String(u.get("elem", "")) == el and Run.heroes.size() < Balance.HERO_SLOTS:
							Run.gain_hero(u, tier)
			Run.wave = 24
			Run.phase = Run.Phase.BATTLE
			var b := BattleScreen.new()
			main._swap(b)
			b.set_process(false)
			await frames(2)
			b.sim.monsters.clear()
			for i in range(18):
				b.sim._spawn(Run.wave_lineup(24)[i % 3])
				b.sim.monsters[-1]["s"] = Balance.path_len() * float(i / 2 + 1) / 12.0
			if what == "move":
				b.selected_hero = 0
			if what == "layers":
				for hero in b.sim.heroes:
					var el := String(hero["h"]["unit"]["elem"])
					var at := Vector2(hero["pos"])
					var col := Balance.elem_color(el)
					b.area_fx.impact(at, 90, el, col, 9)
					b.fx.weak_impact(at - Vector2(0, 36), col, 9, true)
					b.fx.rarity_impact(at - Vector2(0, 36), col, 9, 2.0)
				b.area_fx.update(0.2)
				b.fx.update(0.1)
				b.fx.flash_color = Color(1, 1, 1, 0.25)
				b.fx.flash_t = 1.0
				b.fx.flash_max = 1.0
			if what == "report12":
				b.ended = true
				b.end_t = 1.0
				b.sim.wiped = true
				for i in range(b.sim.heroes.size()):
					b.sim.heroes[i]["dmg"] = (i + 1) * 110.0
					b.sim.heroes[i]["kills"] = i
			b.queue_redraw()
			await frames(3)
			await _save(what)
		"battle", "frost", "stun", "dbg", "dbgh", "dbgm", "dbgt":
			var bw: int = maxi(1, arg)
			Fixture.prepare(bw, SEED)
			# ★ 전투에 들어설 때는 그 탄의 영웅까지 **이미 받은** 상태다
			#   (뽑기 → 확정 → 전투). _prepare 는 뽑기 화면 기준이라 한 명이 모자라고,
			#   1탄이면 아예 0명이라 아무도 안 쏴서 사진이 통째로 거짓말이 된다.
			Run.begin_draw()
			Run.confirm_hand()
			PlayPolicy.arrange(Run)
			Run.wave = bw
			# 얼음은 맞는 족족 얼어붙어야 한 장에 담긴다. 서리 부적을 쥐여 준다.
			if what == "frost":
				if not Run.has("frost"):
					if Run.passive_full():
						Run.passives.remove_at(0)
					Run.passives.append("frost")
			# 마비는 **전기 영웅**만 건다(확률 16%). 자동 편성이 전기를 안 세우면
			# 한 장에 한 마리도 안 잡히므로 촬영용으로 여섯을 전부 전기로 세운다.
			if what == "stun":
				Run.heroes.clear()
				Run.bench.clear()
				# ★ **id 를 못 박지 않는다** — 로스터가 바뀌면 조용히 빈 성역이 찍힌다.
				#   전기 캐릭터를 등급 순으로 여섯 골라 세운다.
				var elecs: Array = []
				for eu in Roster.UNITS:
					if String(eu.get("elem", "")) == "elec":
						elecs.append(eu)
				for k in range(mini(6, elecs.size())):
					var eu2: Dictionary = elecs[(k * maxi(1, elecs.size() / 6))
							% maxi(1, elecs.size())]
					Run.gain_hero(eu2, int(eu2["tier"]))
			# 디버그 오버레이(F3)를 켠 채로 찍는다. 자판이 없는 이 머신에서는 이것이
			# 오버레이를 눈으로 보는 유일한 길이다.
			Dbg.on = what.begins_with("dbg")
			Dbg.paused = false
			Dbg.sel = 0
			Dbg.tab = {"dbg": 0, "dbgh": 1, "dbgm": 2, "dbgt": 3}.get(what, 0)
			var b := BattleScreen.new()
			main._swap(b)
			await frames(2)
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
				# ★ 마비도 같은 이유로 **걸린 놈이 여럿인 순간**을 기다린다. 시간만 재고
				#   찍으면 하필 아무도 안 마비된 프레임이 걸려서 아크가 한 조각도 안 나온다.
				if what == "stun":
					if b.sim.elapsed > 5.0 and _stunned_count(b.sim) >= 2:
						break
					if b.sim.elapsed > 26.0:
						break
					continue
				# ★ **길에 몬스터가 가장 많이 깔린 순간**을 찍는다. 시간만 재고 찍으면
				#   그 탄이 벌써 끝나 있어서 결과판이 화면을 통째로 덮는다 — 밸런스를
				#   다시 잡은 뒤 12·14탄이 실제로 그랬다(사진 두 장을 버렸다).
				#   나오는 데 걸리는 시간(SPAWN_WINDOW)을 넘기고 나서, 아직 여럿 남아
				#   있으면 그때가 제일 볼 만한 프레임이다.
				# ★ 오버레이 사진은 **줄이 넉넉히 쌓인 뒤**를 찍는다. 시간만 재고 찍으면
				#   표가 텅 빈 사진이 나와서 아무것도 확인이 안 된다.
				if what.begins_with("dbg"):
					if Dbg.rows.size() >= 60 and b.sim.elapsed > 6.0:
						break
					if b.sim.elapsed > 26.0:
						break
					continue
				if b.sim.elapsed > Balance.SPAWN_WINDOW + 1.0 and b.sim.monsters.size() >= 4:
					break
				if b.sim.elapsed > want:
					break
			await _save("%s%d" % [what, bw])
		"bullets":
			# 탄 모양은 **속성마다 다르다.** 그런데 자동 편성(PlayPolicy)은 센 놈만
			# 세우므로 불·물·전기·얼음 탄이 한 장에 같이 잡히는 일이 거의 없다 —
			# 그러면 눈으로 볼 방법이 아예 없다. 그래서 촬영용으로 손수 세운다.
			var bw2: int = maxi(1, arg)
			Fixture.prepare(bw2, SEED)
			Run.wave = bw2
			Run.heroes.clear()
			Run.bench.clear()
			# ★ **다섯 속성이 한 장에 다 잡혀야 한다.** id 를 못 박으면 로스터가 바뀔 때
			#   조용히 건너뛰어 "탄이 네 가지밖에 안 보이는" 사진이 나온다 — 그러니
			#   속성으로 고른다. 탄이 실제로 날아가는 방식만 고른다(광선·장판은 탄이 없다).
			for el2 in Balance.ELEM_ORDER:
				for uu2 in Roster.UNITS:
					if String(uu2.get("elem", "")) != String(el2):
						continue
					var bk4 := String(uu2.get("bullet", ""))
					if bk4 == "beam" or bk4 == "zone":
						continue
					Run.gain_hero(uu2, int(uu2["tier"]))
					break
			var b2 := BattleScreen.new()
			main._swap(b2)
			await frames(2)
			# 탄이 여러 발 날고 있는 순간을 기다린다 — 시간만 재고 찍으면 하필
			# 아무것도 안 날아가는 프레임이 걸린다(얼음 사진에서 겪었다).
			for i in range(6000):
				await get_tree().process_frame
				if b2.sim.done:
					break
				if b2.sim.elapsed > 5.0 and b2.sim.bullets.size() >= 4:
					break
				if b2.sim.elapsed > 30.0:
					break
			await _save("bullets%d" % bw2)
		"zone", "zone1":
			# 장판(zone)은 **탄이 안 생긴다** — 지목한 자리에 원이 깔리고 0.25초마다
			# 틱이 돈다(CLAUDE.md 5-1). 자동 편성(PlayPolicy)은 센 놈만 세우므로 이
			# 연출은 보통 사진에 한 번도 안 잡힌다. 그래서 손수 세운다.
			# ★ 예전에 이 원반은 **사거리만큼** 컸고, 그래서 「사거리 상한에 닿는 40탄」이
			#   촬영 이유였다. 사거리를 없앤 지금 발판은 탄에 따라 커지지 않는다 —
			#   그러니 탄은 다른 까닭으로 고른다: **뒤 탄일수록 몬스터가 많이 깔려서**
			#   (Balance.wave_count) 발판 위에 여럿이 들어와 틱이 도는 순간이 잡힌다.
			#   앞 탄에서는 아래의 「넷 이상」을 못 채우고 시간만 재다 끝난다.
			var aw: int = maxi(1, arg)
			Fixture.prepare(aw, SEED)
			Run.begin_draw()
			Run.confirm_hand()
			Run.wave = aw
			Run.heroes.clear()
			Run.bench.clear()
			# 장판 넷은 roster 의 bullet 이 "zone" 인 캐릭터다. **id 를 못 박지 않는다** —
			# 로스터가 바뀌면 조용히 빈 성역이 찍히기 때문이다.
			var auras: Array = []
			for au in Roster.UNITS:
				if String(au.get("bullet", "")) == "zone":
					auras.append(au)
			if auras.is_empty():
				printerr("장판(zone) 캐릭터가 하나도 없다 — roster 를 봐라")
			elif what == "zone1":
				# 한 장만 깔았을 때 발판이 어떻게 그려지는지 — 넷이 겹치면 그게 안 보인다.
				var solo: Dictionary = auras[auras.size() - 1]
				Run.gain_hero(solo, int(solo["tier"]))
			else:
				# ★ 장판 캐릭터가 열여섯으로 늘었다(등급마다 광역 둘 중 마법 쪽).
				#   성역은 여섯 자리뿐이라 전부 세우면 열이 전당으로 밀려나 안 찍힌다.
				#   등급을 골고루 넷만 세운다.
				var step: int = maxi(1, auras.size() / 4)
				for k in range(4):
					var av: Dictionary = auras[mini(auras.size() - 1, k * step)]
					Run.gain_hero(av, int(av["tier"]))
			var ab := BattleScreen.new()
			main._swap(ab)
			await frames(2)
			for i in range(6000):
				await get_tree().process_frame
				if ab.sim.done:
					break
				# 발판 **안에 몬스터가 여럿 들어와 있는** 순간을 기다린다. 시간만 재고
				# 찍으면 하필 아무도 안 닿은 프레임이 걸려서 빈 발판만 나온다
				# (얼음·마비 사진에서 이미 겪었다).
				if ab.sim.elapsed > 5.0 and ab.sim.monsters.size() >= 4:
					break
				if ab.sim.elapsed > 26.0:
					break
			await _save("%s%d" % [what, aw])
		"shop", "shopp", "shopc", "shopf":
			Fixture.prepare(maxi(1, arg), SEED)
			Run.wave = maxi(1, arg)
			var sc := ShopScreen.new()
			main._swap(sc)
			sc.tab = {"shop": "u", "shopp": "p", "shopc": "c", "shopf": "f"}[what]
			await frames(6)
			await _save("%s%d" % [what, arg])
		"result":
			# 라운드 전과 판 — 전투를 끝까지 돌린 뒤 찍는다.
			# ★ 배속을 올려 두지 않으면 한 탄에 서른 초씩 걸려서 촬영이 하염없다.
			var rw: int = maxi(1, arg)
			Fixture.prepare(rw, SEED)
			Run.begin_draw()
			Run.confirm_hand()
			PlayPolicy.arrange(Run)
			Run.wave = rw
			Run.phase = Run.Phase.BATTLE
			var rb := BattleScreen.new()
			main._swap(rb)
			await frames(2)
			rb.speed = 3.0
			for i in range(12000):
				await get_tree().process_frame
				if rb.ended and rb.end_t > 0.5:
					break
			await _save("result%d" % rw)
		"theme":
			# 테마 판 — 열 탄마다 한 번 뜬다. 그 열 탄의 규칙이 여기 한 장에 있다.
			Fixture.prepare(maxi(1, arg), SEED)
			Run.wave = maxi(1, arg) - 1
			var th := ThemeScreen.new()
			main._swap(th)
			for i in range(200):
				await get_tree().process_frame
				if th.t > 1.4:
					break
			await _save("theme%d" % arg)
		"team":
			# 자리가 남는 보통의 탄. 확정 연출이 끝나면 **탄마다** 이 판이 뜬다.
			# ★ 성역을 억지로 채우지 않는다 — 꽉 찼을 때는 swap 이 따로 찍는다.
			# ★ Run.wave 를 손으로 맞추지 마라. Fixture.prepare(w) 는 **w 탄을 뽑기 직전**
			#   (wave = w-1)까지 만들어 두고, begin_draw() 가 w 로 올린다. 여기서 arg 를
			#   한 번 더 대입하면 그 다음 탄이 그려진다 — team:7 이 8탄을 찍었다.
			Fixture.prepare(maxi(1, arg), SEED)
			Run.begin_draw()
			var d3 := DrawScreen.new()
			main._swap(d3)
			await frames(2)
			d3._confirm()
			d3._after_reveal()
			for i in range(2000):
				await get_tree().process_frame
				if d3.state == DrawScreen.SWAP:
					break
			await frames(4)
			await _save("team%d" % arg)
		"swap", "place":
			# 성역을 서로 다른 여섯으로 꽉 채운 뒤 한 명을 더 받는다 — 자리가 없는 상황.
			# ★ team 과 같은 이유로 Run.wave 를 손으로 안 맞춘다 — 맞추면 swap:14 가
			#   15탄을 찍는다(예전에 그랬다).
			Fixture.prepare(maxi(1, arg), SEED)
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
			# ★ 성역(7~9등급)에도 대기석(1~3등급)에도 없는 등급으로 뽑는다. 겹쳐 버리면
			#   교체 창이 안 뜨고 엉뚱한 사진이 찍힌다.
			Fixture.stack(4)
			var d2 := DrawScreen.new()
			main._swap(d2)
			await frames(2)
			d2._confirm()
			d2._after_reveal()
			for i in range(2000):
				await get_tree().process_frame
				if d2.state == DrawScreen.SWAP:
					break
			await frames(4)
			if what == "place":
				d2.formation.tap("post:%d" % int(Run.heroes[0]["post"]))
				d2.queue_redraw()
				await frames(3)
			await _save("%s%d" % [what, arg])
		"hall":
			# 전당이 **한 창을 넘겼을 때**의 편성 판 — 굴림 막대와 「N / M」 쪽 번호가
			# 같이 잡힌다. swap:<탄> 은 성역이 꽉 찬 순간을 찍는 자리라 전당이 넉 칸뿐이고,
			# 그 사진으로는 굴림이 있다는 것 자체가 안 보였다.
			# ★ `gain_hero` 는 같은 id 를 **겹치므로**(x2 …) 같은 캐릭터를 여러 번 줘도
			#   전당은 안 는다. 서로 다른 id 로 훑어야 스무 명이 쌓인다.
			Fixture.prepare(maxi(1, arg), SEED)
			Run.heroes.clear()
			Run.bench.clear()
			for hu in Roster.UNITS:
				if Run.bench.size() >= 20:
					break
				Run.gain_hero(hu, int(hu["tier"]))
			Run.begin_draw()
			var d4 := DrawScreen.new()
			d4.formation_tab = false
			main._swap(d4)
			await frames(2)
			d4._confirm()
			d4._after_reveal()
			for i in range(2000):
				await get_tree().process_frame
				if d4.state == DrawScreen.SWAP:
					break
			await frames(4)
			await _save("hall%d" % arg)
		"over":
			Fixture.prepare(24, SEED)
			Run.wave = 24
			Run.end_run(false)
			main._swap(OverScreen.new())
			await frames(20)
			await _save("over")
		_:
			printerr("모르는 화면: %s" % spec)
