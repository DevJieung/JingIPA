extends Harness

## 화면 개선 회귀 검사 — 확정 연출 · 편성 판 · 전당 탭 · 지형 그림 · 착탄 연출.
##
##   godot --headless --path . res://tests/presentation_check.tscn

var main: Node2D


func fresh() -> void:
	Fixture.fresh(11092026)


func _ready() -> void:
	if not require_no_save(2):
		return
	main = load("res://game/main.gd").new()
	add_child(main)
	# 확정 연출은 0.7초 뒤부터 아무 데나 눌러 넘긴다(화면과의 약속). 그 전의 터치는 흘린다 —
	# 넘어가 버리면 무엇이 나왔는지 못 보고 지나간다. 시계는 손으로 돌린다(_process).
	fresh()
	var early := DrawScreen.new()
	main._swap(early)
	early.set_process(false)
	await paint(early)
	check(early.state == DrawScreen.PICK and tap(early, "go") and early.state == DrawScreen.REVEAL,
			"the summon button starts the reveal")
	var summoned := Run.hero_total()
	mouse(early, Vector2(640, 760), true)
	mouse(early, Vector2(640, 760), false)
	check(early.state == DrawScreen.REVEAL, "a touch at the very start does not skip the reveal")
	early._process(0.6)
	mouse(early, Vector2(640, 760), true)
	mouse(early, Vector2(640, 760), false)
	check(early.state == DrawScreen.REVEAL, "the reveal cannot be skipped before 0.7 seconds")
	early._process(0.2)
	check(early.state == DrawScreen.REVEAL, "the reveal does not advance by itself")
	mouse(early, Vector2(640, 760), true)
	mouse(early, Vector2(640, 760), false)
	check(early.state == DrawScreen.SWAP and Run.hero_total() == summoned, "after 0.7 seconds a touch anywhere advances to formation")

	fresh()
	var d := DrawScreen.new()
	main._swap(d)
	d.set_process(false)
	await paint(d)
	check(tap(d, "go"), "summon button reachable")
	var count := Run.hero_total()
	d._process(30.0)
	check(d.state == DrawScreen.REVEAL, "reveal waits indefinitely for a user touch")
	mouse(d, Vector2(640, 760), true)
	mouse(d, Vector2(640, 760), false)
	check(d.state == DrawScreen.SWAP, "touch advances to formation")
	check(Run.hero_total() == count, "touch does not grant an extra hero")
	check(d.formation.selected == -1 and d.formation.bench_selected == -1, "new field hero is not selected")
	check(d.formation.is_new(Run.heroes[int(Run.last_result["slot"])]), "new field hero has persistent highlight")
	await paint(main.screen)
	for zone in d.ui.zones:
		check(Look.SCREEN.encloses(zone["rect"]), "placement hit zones remain inside screen")
	var selected_post := int(Run.heroes[int(Run.last_result["slot"])]["post"])
	check(tap(main.screen, "post:%d" % selected_post), "new hero requires an explicit selection")
	check(tap(main.screen, "post:11"), "selected new hero can move by tapping a post")
	check(int(Run.heroes[0]["post"]) == 11 or selected_post == 11, "new hero moves to tapped post")

	# A duplicate acquired in a later round must point to the reserve card, not the older field hero.
	fresh()
	for unit in Roster.UNITS:
		Run.gain_hero(unit, int(unit["tier"]))
	Run.wave = 24
	var unit := Roster.UNITS[0]
	var got := Run.gain_hero(unit, int(unit["tier"]))
	# 그 복사본을 방금 의식으로 받은 것처럼 확정 결과를 붙인다(등급 · 별 수 · 별 자리).
	Run.last_result = {"unit": unit, "tier": int(unit["tier"]), "stars": Rite.MIN_STARS,
		"orbit": Array(Fixture.orbit_for(Rite.MIN_STARS)), "bumped": false, "joker": -1,
		"where": got["where"], "slot": got["slot"], "n": 1}
	Run.phase = Run.Phase.SWAP
	d = DrawScreen.new()
	main._swap(d)
	d.set_process(false)
	await paint(main.screen)
	var form := d.formation
	var newest := int(got["slot"])
	check(form.bench_selected == -1 and form.selected == -1, "latest duplicate reserve is marked without selection")
	check(form.element == String(unit["elem"]), "new card opens its element tab")
	var ordered := form.visible_indices()
	check(ordered[0] == newest, "new low-rarity card precedes older high-rarity cards")
	for i in range(2, ordered.size()):
		check(int(Run.bench[ordered[i - 1]]["tier"]) >= int(Run.bench[ordered[i]]["tier"]), "remaining cards descend by rarity")
	var preserved := Run.snapshot().duplicate(true)
	check(Run.restore(preserved), "selection scenario saves and restores")
	check(Run.latest_draw_location() == ["bench", newest], "restore still identifies the newly acquired duplicate")
	form.focus_latest()
	await paint(main.screen)
	for el in FormationView.ELEMENTS:
		check(tap(main.screen, "element:" + el), "touch switches " + el + " tab")
		await paint(main.screen)
		for index in form.visible_indices():
			check(String(Run.bench[index]["unit"]["elem"]) == el, "tab includes only its element")
		for zone in d.ui.zones:
			if String(zone["id"]).begins_with("reserve:"):
				check(form._side.encloses(zone["rect"]), "hero card hit area stays within hall")
	check(tap(main.screen, "element:" + String(unit["elem"])), "return to new card tab")
	await paint(main.screen)
	check(tap(main.screen, "posts:next") and form.page == 1, "hall next page is reachable")
	await paint(main.screen)
	check(tap(main.screen, "posts:prev") and form.page == 0, "hall previous page is reachable")
	await paint(main.screen)
	check(tap(main.screen, "reserve:%d" % newest), "new reserve card can be selected after filtering")
	var target := -1
	for i in range(Run.heroes.size()):
		if String(Run.heroes[i]["unit"]["id"]) == String(unit["id"]):
			target = i
			break
	var post := int(Run.heroes[target]["post"])
	check(tap(main.screen, "post:%d" % post), "reserve can replace its matching field character")
	check(form.is_new(Run.heroes[target]), "new card highlight follows it onto the field")
	await paint(main.screen)
	check(tap(main.screen, "post:%d" % post), "deployed new card can be selected again")
	await paint(main.screen)
	check(tap(main.screen, "post:bench"), "selected hero can return to hall")
	await paint(main.screen)
	check(form.bench_selected == -1 and form.selected == -1, "returning a hero clears both selections")
	check(form.is_new(Run.bench[form.visible_indices()[0]]), "returned new card remains first")
	check(Run.hero_total() == 51, "all moves preserve the card total")
	for i in range(form.post_rects.size()):
		for j in range(i + 1, form.post_rects.size()):
			check(not form.post_rects[i].intersects(form.post_rects[j]), "post touch areas do not overlap")

	# Both ordinary and boss monsters consume the same 20% adjusted HP curve.
	for wave in [1, 10, 11, 20, 50, 100]:
		for rank in [1, 3, 5]:
			var previous := Balance.HP_BASE * pow(Balance.HP_GROW, wave - 1) * Balance.mid_ramp(wave) * Balance.early_tough(wave) * Balance.theme_hp(rank)
			check(is_equal_approx(Balance.wave_hp(wave, rank), previous * Balance.DIFFICULTY_HP), "HP multiplier applies to all rounds and ranks")
	var rows := {}
	for theme in Roster.THEMES:
		var road := Battlefield.material(theme, true)
		var ground := Battlefield.material(theme, false)
		check(road != null and ground != null and road != ground, "every theme has ground and road images")
		check(Art.has(String(theme["art_floor"])), "every named theme retains its specific floor")
		rows[String(theme["main_body"])] = road.region
	check(rows.size() == 5, "all five biome materials are represented")
	for a in rows:
		for b in rows:
			if a != b:
				check(rows[a] != rows[b], "different biome concepts use different artwork")
	var texture := Art.tex(AreaFx.ATLAS)
	check(texture != null and texture.get_image().detect_alpha() != Image.ALPHA_NONE, "area attack atlas has transparency")
	var area := AreaFx.new()
	for el in AreaFx.ELEMENTS:
		area.zone(Vector2(400, 400), 64, el, Color.WHITE, 9, 0.2, 0.25, 8)
	area.update(0.3)
	check(area.fields.size() == 5, "all five area effects animate")
	area.update(10)
	check(area.fields.is_empty(), "area effects expire")
	for i in range(100):
		area.impact(Vector2.ZERO, 64, "fire", Color.WHITE, 9)
	check(area.fields.size() == AreaFx.MAX_FIELDS, "simultaneous effects are bounded")

	var b := BattleScreen.new()
	b._on_hit(Vector2(400, 300), {"em": 0.0, "n": 0, "src": -1})
	var zeroes := b.fx.items.filter(func(it): return it["t"] == "text" and it["s"] == "0")
	check(zeroes.size() == 1 and int(zeroes[0]["sz"]) >= 24 and Color(zeroes[0]["c"]) == Color("#9a9da3"), "immune damage is a legible gray zero")
	b.fx.clear()
	b._on_hit(Vector2(400, 300), {"em": 2.0, "n": 20, "src": -1, "el": "fire"})
	check(b.fx.items.any(func(it): return it["t"] == "weak"), "double damage has dedicated impact effect")
	check(not b.fx.items.any(func(it): return it["t"] == "text" and String(it["s"]).contains("배")), "double damage has no multiplier word")
	b.free()

	# 별이 많을수록 확정 연출이 크고 풍성하다 — 실제로 1성 · 3성 · 5성을 소환해서 잰다.
	var low := await reveal_weight(Rite.MIN_STARS)
	var mid := await reveal_weight(3)
	var high := await reveal_weight(Rite.MAX_STARS)
	check(not low.is_empty() and not mid.is_empty() and not high.is_empty(), "all three reveals played")
	if not low.is_empty() and not mid.is_empty() and not high.is_empty():
		check(int(high["items"]) > int(low["items"]) * 2 and float(high["shake"]) > float(low["shake"]),
				"more stars in the gate have stronger and richer reveal effects (%d → %d pieces)" % [int(low["items"]), int(high["items"])])
		check(int(mid["items"]) > int(low["items"]) and int(high["items"]) > int(mid["items"])
				and float(mid["shake"]) > float(low["shake"]) and float(high["shake"]) > float(mid["shake"]),
				"the reveal grows with every star")
		check(not bool(low["showy"]) and bool(high["showy"]), "the showy reveal belongs to the high tiers only")
	finish("화면 개선 회귀 검사")


## 문 안에 별이 `stars` 개 선 의식을 실제로 확정해서, 그 확정 연출이 낸 효과의 양을 잰다.
## 돌려주는 것: {"items": 효과 조각 수, "shake": 흔들림 세기, "showy": 화려한 연출인가}. 못 했으면 {}.
##
## ★ 화면 안쪽의 연출 함수를 직접 부르지 않는다 — 소환 단추를 누르고 시계만 손으로 돌린다.
##   (연출이 한 박자에 다 터지도록 3초를 한 번에 넘긴다. 눌러 넘기지는 않는다.)
func reveal_weight(stars: int) -> Dictionary:
	fresh()
	Fixture.stack(stars)
	var screen := DrawScreen.new()
	main._swap(screen)
	screen.set_process(false)
	await paint(screen)
	if not tap(screen, "go") or screen.state != DrawScreen.REVEAL:
		return {}
	var result: Dictionary = Run.last_result
	if int(result.get("stars", 0)) != stars or int(result.get("tier", -1)) != Rite.tier_of(stars):
		return {}
	screen._process(3.0)
	await paint(screen)
	return {"items": screen.fx.items.size(), "shake": screen.fx.shake, "showy": bool(result.get("showy", false))}
