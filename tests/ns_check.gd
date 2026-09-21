extends Node

## 표와 표가 서로 어긋나지 않는지 본다. 사람이 눈으로는 절대 못 잡는 것들이다.
##
##   godot --headless --path . res://tests/ns_check.tscn
##   ... -- --strict     그림이 하나라도 없으면 실패로 친다 (갈무리 전 검사)

var fail := 0


class AttackSyncProbe extends BattleScreen:
	var starts: Dictionary = {}
	var early_shots := 0
	var fired := 0

	func _hero_aim(src: int, w: float, d: Vector2 = Vector2.ZERO) -> void:
		super(src, w, d)
		starts[src] = sim.elapsed

	func _drain() -> void:
		var events := sim.events.duplicate()
		sim.events.clear()
		for event in events:
			# Observe each event before a later aim in the same tick resets its pose.
			sim.events.append(event)
			super()
			if event["t"] == "fire":
				var he: Dictionary = sim.heroes[int(event["src"])]
				fired += 1
				if float(he.get("fx_t", 0.0)) + 0.000001 < float(he.get("fx_w", 0.0)):
					early_shots += 1


func _ready() -> void:
	var strict := Harness.has_arg("--strict")
	_check_scripts()
	_check_roster()
	_check_elem()
	_check_theme()
	_check_wave_plan()
	_check_balance()
	_check_geometry()
	_check_muzzle()
	_check_roster_slots()
	_check_battle()
	_check_attack_sync()
	_check_shop()
	_check_names()
	_check_suits()
	_check_piles()
	_check_save()
	_check_autosave_sites()
	_check_sfx(strict)
	_check_art(strict)
	_check_portrait_routing()
	if fail == 0:
		print("판정: 정상")
	else:
		printerr("!! 실패 %d건" % fail)
	get_tree().quit(0 if fail == 0 else 1)


func _bad(msg: String) -> void:
	printerr("!! " + msg)
	fail += 1


## 상세창에 작은 애니메이션 프레임이 다시 연결되는 회귀를 막는다.
func _check_portrait_routing() -> void:
	var checked := 0
	for u in Roster.UNITS:
		var path := "res://art/portraits/%s.png" % String(u["id"])
		if not ResourceLoader.exists(path):
			continue
		var p := Art.unit_preview(u)
		if p.is_empty() or not p["tex"] is CanvasTexture:
			_bad("전용 원화를 사용하지 않음: " + String(u["id"]))
			continue
		var t: CanvasTexture = p["tex"]
		if t.diffuse_texture.resource_path != path or t.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR:
			_bad("원화 경로/축소 필터 불일치: " + String(u["id"]))
		for size in [Vector2(206, 264), Vector2(80, 60), Vector2(54, 84)]:
			var area := Rect2(Vector2.ZERO, size)
			if not area.grow(0.01).encloses(Art.fit_rect(p["src"].size, area)):
				_bad("원화가 프레임을 넘침: " + String(u["id"]))
		checked += 1
	# 다른 id를 쓰면 전용 원화가 없어도 실제 idle 시트로 대체되어야 한다.
	var fallback: Dictionary = Roster.UNITS[0].duplicate()
	fallback["id"] = "__portrait_fallback_probe__"
	var clip := Anim.clip(fallback, "idle")
	var preview := Art.unit_preview(fallback)
	if not clip.is_empty() and (preview.is_empty() or preview["tex"] != clip["tex"]):
		_bad("원화가 없을 때 idle 대체 실패")
	print("  전용 원화 경로·필터·프레임 경계: %d명" % checked)


## 실제 화면의 배속·프레임 지연에서도 발사와 모션이 같은 시계를 쓰는가.
func _check_attack_sync() -> void:
	var shots := 0
	for frame_dt in [1.0 / 60.0, 0.08, 0.4]:
		for playback in [1.0, 3.0]:
			for rapid in [false, true]:
				Run.start_run(4245)
				Run.begin_draw()
				Run.confirm_hand()
				var screen := AttackSyncProbe.new()
				screen.sim.setup(Run, 6, 31337)
				screen.speed = playback
				if rapid:
					for he in screen.sim.heroes:
						he["rate"] = 12.0
				for tick in range(300):
					if screen.sim.done:
						break
					screen._process(frame_dt)
					for src in screen.starts:
						var age: float = screen.sim.elapsed - float(screen.starts[src])
						if absf(float(screen.sim.heroes[src]["fx_t"]) - age) > 0.00001:
							_bad("배속 %.0f · dt %.3f: 공격 모션 시계가 전투와 어긋남" % [playback, frame_dt])
							break
				if screen.fired == 0 or screen.early_shots > 0:
					_bad("공격 동기화: 발사 %d회 · 모션보다 이른 발사 %d회" % [screen.fired, screen.early_shots])
				shots += screen.fired
				screen.free()
	print("  공격 모션 동기화 (12조건 · 발사 %d회)" % shots)


## 모든 .gd 가 파스되는가. ★ `--import` 는 이미 임포트된 스크립트를 다시 안 볼 때가 있어서
## "화면을 찍으려니 그제서야 파스 에러가 튀어나오는" 일이 실제로 있었다. 여기서 통째로 읽는다.
func _check_scripts() -> void:
	var n := 0
	var bad := 0
	for dir in ["res://core", "res://game", "res://tests"]:
		for f in _gd_files(dir):
			n += 1
			# ⚠ CACHE_MODE_IGNORE 로 읽으면 **지금 돌고 있는 이 스크립트 자신**을 다시
			#   읽다가 엔진이 죽는다(실제로 코어 덤프가 났다). 기본(REUSE)으로 읽는다 —
			#   새 프로세스라 대부분 아직 안 읽힌 상태이므로 파스 오류는 그대로 잡힌다.
			var r := ResourceLoader.load(f)
			# ★ 파스가 깨진 스크립트도 load() 는 **null 이 아닌** GDScript 를 돌려준다.
			#   (예전에는 null 검사만 해서, 문법이 깨진 파일을 이 검사가 그냥 통과시켰다.)
			#   실제로 인스턴스를 만들 수 있는지까지 물어야 잡힌다.
			if r == null or (r is GDScript and not (r as GDScript).can_instantiate()):
				_bad("스크립트가 파스되지 않는다: %s" % f)
				bad += 1
	print("  스크립트 %d개 중 %d개 파스됨" % [n, n - bad])


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_gd_files(dir + "/" + sub))
	return out


func _check_roster() -> void:
	var ids := {}
	var kos := {}
	var per_tier := {}
	for u in Roster.UNITS:
		var id := String(u["id"])
		if ids.has(id):
			_bad("캐릭터 id 중복: %s — 그림 파일이 덮어써진다" % id)
		ids[id] = true
		# 그림 크기 보정. 0 이나 음수면 캐릭터가 안 보이고, 너무 크면 성역을 통째로 덮는다.
		var sc: float = float(u.get("sc", 1.0))
		if sc < 0.6 or sc > 1.5:
			_bad("%s 의 그림 보정(sc %.2f)이 0.6~1.5 밖이다" % [id, sc])
		var ko := String(u["ko"])
		if kos.has(ko):
			_bad("캐릭터 이름 중복: %s" % ko)
		kos[ko] = true
		if not Balance.PROFILE.has(String(u["profile"])):
			_bad("%s 의 profile 이 표에 없다: %s" % [id, u["profile"]])
		if not Balance.BULLET.has(String(u["bullet"])):
			_bad("%s 의 bullet 이 표에 없다: %s" % [id, u["bullet"]])
		var t := int(u["tier"])
		if t < 0 or t > 9:
			_bad("%s 의 등급이 0~9 밖이다: %d" % [id, t])
		per_tier[t] = int(per_tier.get(t, 0)) + 1
		if not Color.html_is_valid(String(u["color"])):
			_bad("%s 의 색이 이상하다: %s" % [id, u["color"]])
	# ★★ **등급마다 정확히 다섯이고, 다섯은 속성 다섯 x 무기 다섯이다.**
	#   (설계서 `pokerdefense_world_characters_v2.md` §4 의 배치 행렬 그대로 —
	#    「각 등급마다 5속성이 1명씩」 · 「각 등급 내에서 무기 5종도 1개씩」)
	#
	#   재는 것이 넷이다:
	#     1. **다섯인가** — 더도 덜도 아니다.
	#     2. **속성 다섯이 저마다 하나씩인가** — 하나라도 겹치면 그 등급에서 어떤
	#        속성 하나를 아예 못 뽑는다. 상성이 규칙의 전부인 게임에서 그것은
	#        「그 등급을 뽑으면 저 몬스터에게는 손도 못 댄다」가 된다.
	#     3. **무기 다섯이 저마다 하나씩인가** — 무기가 곧 자세이고(gen_art.pose_for)
	#        전당 판에 다섯이 나란히 서므로, 둘이 같은 무기면 그 판에서 한 사람으로
	#        보인다. 얼굴이 눈 두 점뿐인 화풍이라 실루엣이 겹치는 것이 곧 캐릭터가
	#        겹치는 것이다.
	#     4. **역할 넷이 전부 있는가** — 하나라도 빠지면 그 등급에서 그 역할을
	#        아예 못 뽑는다. 다섯 자리에 역할이 넷이라 하나는 둘이다(무기가 정한다:
	#        검·총=일격 · 활=도탄 · 채찍=특효 · 광역=광역 → 일격이 둘).
	#
	# ★ 속성이 등급마다 하나씩이므로 **역할 x 속성은 저절로 안 겹친다** — 예전
	#   여든 명 체제에서 따로 재던 검사가 여기서는 산수로 참이다.
	var want_per := 5
	for t in range(10):
		if int(per_tier.get(t, 0)) != want_per:
			_bad("%s 등급의 캐릭터가 %d명이다 (다섯이어야 한다)"
					% [Poker.HAND_KO[t], int(per_tier.get(t, 0))])
		var tu: Array = Roster.units_of_tier(t)
		var roles := {}
		var weaps := {}
		var elems := {}
		for u3 in tu:
			var ro := String(u3.get("role", ""))
			if not Balance.ROLE.has(ro):
				_bad("%s 의 역할이 표에 없다: '%s'" % [u3["id"], ro])
			roles[ro] = int(roles.get(ro, 0)) + 1
			var wp := String(u3.get("weapon", ""))
			if wp == "":
				_bad("%s 에 weapon 이 없다 — 자세가 여기서 나온다(gen_art.pose_for)" % u3["id"])
			elif weaps.has(wp):
				_bad("%s 등급에 %s 무기가 둘이다 (%s · %s) — 다섯이 한 판에 나란히 선다"
						% [Poker.HAND_KO[t], wp, weaps[wp], u3["id"]])
			weaps[wp] = String(u3["id"])
			var el := String(u3.get("elem", ""))
			if elems.has(el):
				_bad("%s 등급에 %s 속성이 둘이다 (%s · %s) — 등급마다 속성 다섯이 하나씩이다"
						% [Poker.HAND_KO[t], el, elems[el], u3["id"]])
			elems[el] = String(u3["id"])
		for e2 in Balance.ELEM_ORDER:
			if not elems.has(String(e2)):
				_bad("%s 등급에 %s 속성이 없다" % [Poker.HAND_KO[t], Balance.elem_ko(String(e2))])
		for ro2 in Balance.ROLE_ORDER:
			if int(roles.get(ro2, 0)) < 1:
				_bad("%s 등급에 「%s」 역할이 하나도 없다"
						% [Poker.HAND_KO[t], Balance.role_ko(String(ro2))])
	# ★ **무기가 역할을 정한다 — 쉰 줄이 다 같은 규칙을 따라야 한다.**
	#   설계서 §2 의 「무기는 전부 카드를 다루는 손동작에서 나왔다」가 곧 이 표다.
	#   한 줄이라도 어긋나면 「같은 검인데 누구는 일격이고 누구는 광역」이 되어,
	#   플레이어가 무기를 보고 성능을 못 읽는다.
	const ROLE_OF_WEAPON := {
		"sword": "single", "gun": "single", "bow": "ricochet",
		"whip": "rider", "deck": "area",
	}
	for u4 in Roster.UNITS:
		var wp2 := String(u4.get("weapon", ""))
		if not ROLE_OF_WEAPON.has(wp2):
			_bad("%s 의 무기가 다섯 중에 없다: '%s'" % [u4["id"], wp2])
		elif String(u4.get("role", "")) != String(ROLE_OF_WEAPON[wp2]):
			_bad("%s 는 %s 인데 역할이 '%s' 다 ('%s' 여야 한다)"
					% [u4["id"], wp2, u4.get("role", ""), ROLE_OF_WEAPON[wp2]])
	# ★ **장판(zone)은 광역 무기(deck)만 쓴다 — 자세가 여기에 매여 있다.**
	#   gen_art.pose_family() 는 bullet == "zone" 이면 **무기보다 먼저** raise 를
	#   돌려준다(두 팔을 든다). 그래서 활잡이에게 zone 을 주면 활을 든 채 두 팔을
	#   드는 그림이 나오고, 겨누는 자세가 통째로 사라진다.
	for u5 in Roster.UNITS:
		var isz := String(u5.get("bullet", "")) == "zone"
		if isz != (String(u5.get("weapon", "")) == "deck"):
			_bad("%s 의 장판(zone)과 광역 무기(deck)가 짝이 안 맞는다" % u5["id"])

	for m in Roster.MONSTERS:
		var mid := String(m["id"])
		if ids.has(mid):
			_bad("몬스터 id 가 캐릭터와 겹친다: %s" % mid)
		ids[mid] = true
		if not Balance.MKIND.has(String(m["kind"])):
			_bad("%s 의 kind 가 표에 없다: %s" % [mid, m["kind"]])
	# ★ **몸 다섯 가지가 저마다 형 넷을 다 갖추어야 한다.** 하나라도 비면 그 테마에서
	#   그 형이 통째로 빠져 "호수에는 육중형이 없다" 같은 규칙이 조용히 생긴다.
	for b in Balance.MBODY_ORDER:
		var got := {}
		for m2 in Roster.monsters_of_body(String(b)):
			got[String(m2["kind"])] = true
		for k in ["swarm", "fast", "tank", "caster"]:
			if not got.has(k):
				_bad("%s 몸에 %s 형 몬스터가 없다" % [Balance.body_ko(String(b)), k])
		if Roster.boss_of_body(String(b)).is_empty():
			_bad("%s 몸의 보스가 없다 — 그 테마의 보스맵에 보스가 안 나온다"
					% Balance.body_ko(String(b)))
	if Roster.TIER_KO.size() != 10:
		_bad("등급 이름이 10개가 아니다")


## 속성 표 — 다섯 공격 속성과 몬스터의 다섯 몸.
##
## ★ **옛 검사는 「약점 마릿수와 저항 마릿수가 대칭인가」를 봤다. 그 잣대를 버렸다.**
##   사용자가 정한 새 표는 일부러 비대칭이다 — 전기만 약점 하나에 **면역 하나**를 진다
##   (바위 몸은 전기를 0배로 받는다). 마릿수로 재면 새 표는 절대 통과하지 못하고,
##   억지로 통과시키려면 사용자의 규칙을 고쳐야 한다.
## ★ 그래서 잣대를 **「어느 속성을 뽑아도 한 테마를 통째로 잃지는 않는가」** 로 옮겼다.
##   대칭이 지키려던 것이 원래 그것이었다 — 뽑기가 선택이지 사형선고가 아니어야 한다.
##   §8 이 테마 쉰 개를 하나씩 돌며 그것을 잰다.
func _check_elem() -> void:
	# 1) 표 자체가 성한가
	if Balance.ELEM_ORDER.size() != Balance.ELEM.size():
		_bad("ELEM_ORDER(%d)와 ELEM(%d)의 개수가 다르다"
				% [Balance.ELEM_ORDER.size(), Balance.ELEM.size()])
	for e in Balance.ELEM_ORDER:
		if not Balance.ELEM.has(e):
			_bad("ELEM_ORDER 에 표에 없는 속성이 있다: %s" % e)
	for e in Balance.ELEM:
		if not Color.html_is_valid(String(Balance.ELEM[e]["color"])):
			_bad("속성 %s 의 색이 이상하다" % e)
		# 상태이상은 표에 있는 것이거나 없거나 둘 뿐이다.
		var rd := Balance.elem_rider(String(e))
		if rd != "" and not Balance.STATUS.has(rd):
			_bad("속성 %s 가 표에 없는 상태이상을 건다: %s" % [e, rd])
		if Balance.elem_dmg(String(e)) <= 0.0:
			_bad("속성 %s 의 기본 화력이 0 이하다" % e)
	if not Balance.ELEM.has("none"):
		_bad("무상성(none)이 속성 표에 없다")
	# ★ 무상성은 상태이상도 없어야 한다. 「안전한 줄」에 덤이 붙으면 안전한 줄이 아니라
	#   그냥 제일 좋은 줄이 된다.
	if Balance.elem_rider("none") != "":
		_bad("무상성이 상태이상을 건다 — 무상성은 이득도 손해도 없어야 한다")
	if Balance.ELEM_WEAK <= 1.0 or Balance.ELEM_RESIST >= 1.0 or Balance.ELEM_RESIST <= 0.0:
		_bad("상성 배수가 이상하다 (약점 %.2f · 저항 %.2f) — 약점>1>저항>0 이어야 한다"
				% [Balance.ELEM_WEAK, Balance.ELEM_RESIST])
	if not is_equal_approx(Balance.ELEM_IMMUNE, 0.0):
		_bad("면역 배수가 0 이 아니다 (%.2f)" % Balance.ELEM_IMMUNE)

	# 1-2) 상태이상 표 — 셋이 다 있고 값이 성한가
	for st_id in ["slow", "burn", "stun"]:
		if not Balance.STATUS.has(st_id):
			_bad("상태이상 표에 %s 가 없다" % st_id)
	var stun: Dictionary = Balance.STATUS.get("stun", {})
	var sc: float = float(stun.get("chance", 0.0))
	if sc <= 0.0 or sc >= 1.0:
		_bad("마비 확률이 0~1 밖이다 (%.2f) — 사용자의 규칙은 「특정확률로 마비」다" % sc)
	if float(stun.get("sec", 0.0)) <= 0.0:
		_bad("마비 지속이 0 이하다")
	# ★ 재우는 시간이 없으면 연사 영웅 하나가 사실상 영구 정지를 건다.
	if Balance.STUN_IMMUNE_SEC <= 0.0:
		_bad("마비 뒤 재우는 시간(STUN_IMMUNE_SEC)이 0 이다 — 영구 정지가 만들어진다")
	# 속성마다 상태이상이 하나씩 붙었는지 — 사용자가 정한 규칙 그대로인지 본다.
	for pair in [["ice", "slow"], ["fire", "burn"], ["elec", "stun"]]:
		if Balance.elem_rider(String(pair[0])) != String(pair[1]):
			_bad("%s 가 %s 를 안 건다 — 사용자가 정한 규칙과 다르다"
					% [Balance.elem_ko(String(pair[0])), Balance.status_ko(String(pair[1]))])

	# 1-3) 아이콘 그림 — **속성 다섯과 몸 다섯이 하나도 안 빠지고 그림을 갖는가**
	#
	# ★ 왜 검사가 필요한가: 표에 없는 열쇠가 오면 Look.draw_elem/draw_body 는 **조용히**
	#   예전 도형(색 동그라미에 한 글자)으로 되돌아간다. 그러면 화면에 아이콘 넷과
	#   글자 하나가 섞여 서고, 그 한 자리는 사진으로만 잡힌다.
	# ★ 그림 파일이 실제로 있는지는 _check_art 가 Roster.ART 를 통째로 훑으며 본다.
	#   여기서는 **짝이 맞는가**만 본다.
	for e2 in Balance.ELEM:
		var ka := String(Look.ELEM_ART.get(e2, ""))
		if ka == "":
			_bad("속성 %s 에 아이콘 그림이 안 붙어 있다 (Look.ELEM_ART)" % e2)
		elif not Roster.ART.has(ka):
			_bad("속성 %s 의 아이콘 %s 가 Roster.ART 에 없다" % [e2, ka])
		# ★ 되돌림 글자도 같이 본다. elem_char 는 모르는 열쇠에 **「무」를 조용히** 돌려주므로
		#   빠져 있어도 화면에 「무상성」으로 찍힌다 — 사진으로도 잡기 어려운 거짓말이다.
		if not Look.ELEM_CHAR.has(e2):
			_bad("속성 %s 에 되돌림용 한 글자가 없다 (Look.ELEM_CHAR)" % e2)
	for b2 in Balance.MBODY:
		var kb := String(Look.BODY_ART.get(b2, ""))
		if kb == "":
			_bad("몸 %s 에 아이콘 그림이 안 붙어 있다 (Look.BODY_ART)" % b2)
		elif not Roster.ART.has(kb):
			_bad("몸 %s 의 아이콘 %s 가 Roster.ART 에 없다" % [b2, kb])
		if not Color.html_is_valid(String(Balance.MBODY[b2].get("color", ""))):
			_bad("몸 %s 의 색이 이상하다 — 화면 네 곳이 이 색으로 몸을 그린다" % b2)
		if not Look.BODY_CHAR.has(b2):
			_bad("몸 %s 에 되돌림용 한 글자가 없다 (Look.BODY_CHAR)" % b2)

	# 2) 몸 표 — 약점·저항·면역이 실재하는 속성이고 서로 안 겹치는가
	if Balance.MBODY_ORDER.size() != Balance.MBODY.size():
		_bad("MBODY_ORDER(%d)와 MBODY(%d)의 개수가 다르다"
				% [Balance.MBODY_ORDER.size(), Balance.MBODY.size()])
	for b in Balance.MBODY_ORDER:
		if not Balance.MBODY.has(b):
			_bad("MBODY_ORDER 에 표에 없는 몸이 있다: %s" % b)
	for b in Balance.MBODY:
		var bs := String(b)
		var wk: Array = Balance.body_weak(bs)
		var rs: Array = Balance.body_resist(bs)
		var im: Array = Balance.body_immune(bs)
		var seen := {}
		for group in [wk, rs, im]:
			for v in group:
				var vs := String(v)
				if not Balance.ELEM.has(vs):
					_bad("몸 %s 가 없는 속성을 가리킨다: %s" % [bs, vs])
				if vs == "none":
					_bad("몸 %s 가 무상성을 약점/저항/면역으로 삼는다 — 무상성은 늘 1.0 이다" % bs)
				if seen.has(vs):
					_bad("몸 %s 가 %s 를 두 번 적었다 (약점·저항·면역은 겹칠 수 없다)" % [bs, vs])
				seen[vs] = true
		# ★ **무상성 공격은 어떤 몸에도 정확히 1.0.** 이것이 무상성 영웅의 값어치 전부다.
		if not is_equal_approx(Balance.elem_mult("none", bs), 1.0):
			_bad("무상성 공격이 %s 에게 1.0 배가 아니다 (%.2f)"
					% [bs, Balance.elem_mult("none", bs)])
		for v2 in wk:
			if not is_equal_approx(Balance.elem_mult(String(v2), bs), Balance.ELEM_WEAK):
				_bad("%s 의 약점(%s)이 약점 배수로 안 들어간다" % [bs, v2])
		for v3 in rs:
			if not is_equal_approx(Balance.elem_mult(String(v3), bs), Balance.ELEM_RESIST):
				_bad("%s 의 저항(%s)이 저항 배수로 안 들어간다" % [bs, v3])
		for v4 in im:
			if not is_equal_approx(Balance.elem_mult(String(v4), bs), 0.0):
				_bad("%s 의 면역(%s)이 0 배로 안 들어간다" % [bs, v4])

	# 3) 캐릭터의 속성이 표에 있는가 · 공격 방식과 어긋나지 않는가
	var hero_n := {}
	var hero_band := {}      # 속성 -> {앞: true, 중: true, 뒤: true}
	for u in Roster.UNITS:
		var e := String(u.get("elem", ""))
		if not Balance.ELEM.has(e):
			_bad("%s 의 속성이 표에 없다: '%s'" % [u["id"], e])
			continue
		hero_n[e] = int(hero_n.get(e, 0)) + 1
		var t := int(u["tier"])
		var band: String = "앞" if t <= 3 else ("중" if t <= 6 else "뒤")
		if not hero_band.has(e):
			hero_band[e] = {}
		hero_band[e][band] = true
		# ★ 공격 방식과 속성이 어긋나면 화면이 거짓말을 한다 — 연쇄는 번개로 그려진다.
		#   표가 그 그림과 다르면 플레이어는 영영 규칙을 못 배운다 (CLAUDE.md 5-4).
		var bk3 := String(u.get("bullet", "shot"))
		if bk3 == "chain" and e != "elec":
			_bad("%s 는 연쇄(번개로 그려진다)인데 속성이 %s 다" % [u["id"], e])
		# ★★ **무상성 장판은 이제 있다 — 옛 금지를 풀었다.**
		#   예전 규칙은 「속성이 없으면 발밑에서 머리 위로 지나갈 이펙트가 없다」였다.
		#   그런데 그것은 기술이 아니라 **설계**의 문제였다. 화면은 캐릭터 색(u.color)과
		#   속성 색(Balance.elem_color)을 같이 쓰므로 무상성도 `#D8DEE6` 로 그려진다 —
		#   지나갈 것이 없던 적이 없다.
		#   그리고 설계서(§3 「이름 없는 가문」)가 그 자리를 뜻으로 채웠다:
		#     미믹  — 다섯 속성 중 **무작위**로 골라 터진다
		#     블랭크 — 떨어진 자리 적의 속성을 **복사해** 그 속성으로 터진다
		#   둘 다 「빌려 온 속성」이라, 무채색 + 홀로그램이라는 이 가문의 결과 맞는다.
		#   ☆ 규칙 5-2(무상성은 어떤 몸에도 1.0배)는 그대로다 — 빌리는 것은 **연출**
		#     이지 배수가 아니다. 배수를 빌리게 하면 「안전한 줄」이 없어진다.
		#   ☆ 무엇보다 **뺄 수가 없다**: 설계서 §4 의 배치 행렬이 등급마다 무기
		#     다섯을 하나씩 세우므로, 무상성에게서 광역을 빼면 그 등급의 무기 하나가
		#     통째로 빈다.
		# ★ **광선과 장판은 탄이 안 생긴다** — 선과 원반으로 얇게 그려지므로 어두운
		#   색이면 화면에서 통째로 사라진다 (CLAUDE.md 4-2 의 뒤집힌 쪽).
		if bk3 == "beam" or bk3 == "zone":
			var cc := Color(String(u.get("color", "#ffffff")))
			if maxf(cc.r, maxf(cc.g, cc.b)) < 0.62:
				_bad("%s 는 %s 인데 탄알 색이 어둡다(%s) — 선·원반은 어두우면 안 보인다"
						% [u["id"], Balance.BULLET[bk3]["ko"], u["color"]])

	# 4) 몬스터의 몸이 표에 있는가
	var weak_n := {}
	var res_n := {}
	var imm_n := {}
	for m in Roster.MONSTERS:
		var b2 := String(m.get("body", ""))
		if not Balance.MBODY.has(b2):
			_bad("%s 의 몸이 표에 없다: '%s'" % [m["id"], b2])
			continue
		for v5 in Balance.body_weak(b2):
			weak_n[v5] = int(weak_n.get(v5, 0)) + 1
		for v6 in Balance.body_resist(b2):
			res_n[v6] = int(res_n.get(v6, 0)) + 1
		for v7 in Balance.body_immune(b2):
			imm_n[v7] = int(imm_n.get(v7, 0)) + 1

	# 5) 죽은 속성이 없는가
	for e3 in Balance.ELEM_ORDER:
		var es := String(e3)
		if int(hero_n.get(es, 0)) < 2:
			# 하나뿐이면 그 캐릭터가 안 나오는 판에서는 그 속성이 아예 없는 것과 같다.
			_bad("%s 속성 영웅이 %d명뿐이다 (둘 이상)"
					% [Balance.elem_ko(es), int(hero_n.get(es, 0))])
		# ★ **속성이 등급 구간에 고루 퍼져야 한다.** 전기가 앞 등급에만 있으면 후반에
		#   전기를 뽑을 길이 없고, 뒤 등급에만 있으면 전기로 전반을 날 수가 없다.
		var bands: Dictionary = hero_band.get(es, {})
		if bands.size() < 3:
			_bad("%s 속성 영웅이 등급 구간 %d곳에만 있다 (앞0-3·중4-6·뒤7-9 모두에 있어야 한다)"
					% [Balance.elem_ko(es), bands.size()])
		if es == "none":
			continue
		if int(weak_n.get(es, 0)) < 1:
			_bad("%s 를 약점으로 갖는 몬스터가 하나도 없다 — 그 속성은 이득이 영영 없다"
					% Balance.elem_ko(es))

	# 6) 무상성이 설 자리 — **어떤 속성에도 안 약한 몸**이 있거나, 없다면 무상성이
	#    「손해를 안 본다」는 것만으로 값을 해야 한다. 지금 표는 다섯 몸이 모두 어딘가에
	#    약하므로, 대신 **저항이 흔한지**를 본다. 저항이 하나도 없으면 상성은 순이득만
	#    남아서 무상성 영웅을 뽑을 까닭이 사라진다.
	var res_total := 0
	for k2 in res_n:
		res_total += int(res_n[k2])
	if res_total < Roster.MONSTERS.size():
		_bad("저항이 %d건뿐이다(몬스터 %d종) — 상성이 순이득만 되면 무상성 영웅이 설 자리가 없다"
				% [res_total, Roster.MONSTERS.size()])

	# 7) 상태이상을 안 거는 속성(물·무상성)은 **기본 화력으로 값을 해야 한다.**
	#    안 그러면 그 줄은 「상성 폭은 같은데 덤이 없는 줄」이라 아무도 안 고른다.
	for e4 in Balance.ELEM_ORDER:
		var e4s := String(e4)
		if e4s == "none" or Balance.elem_rider(e4s) != "":
			continue
		if Balance.elem_dmg(e4s) <= 1.0:
			_bad("%s 는 상태이상도 없고 화력 덤도 없다 — 고를 까닭이 없는 속성이 된다"
					% Balance.elem_ko(e4s))

	# 테마 속성 집중 후에는 상성이 불리한 편성이 분명해진다.
	# 그래도 모든 공격이 일부 몬스터를 때릴 수 있고 유리한 속성은 최소 하나여야 한다.
	var worst := {}
	for th in Roster.THEMES:
		var wt: Dictionary = th.get("weights", {})
		var good := 0
		for e5 in Balance.ELEM_ORDER:
			var e5s := String(e5)
			if e5s == "none":
				continue
			var sum_m := 0.0
			var sum_w := 0.0
			for b3 in Balance.MBODY_ORDER:
				var wv: float = float(wt.get(b3, 0.0))
				sum_w += wv
				sum_m += wv * Balance.elem_mult(e5s, String(b3))
			if sum_w <= 0.0:
				continue
			var avg: float = sum_m / sum_w
			if avg < float(worst.get(e5s, 99.0)):
				worst[e5s] = avg
			if avg < ELEM_FLOOR:
				_bad("테마 「%s」에서 %s 속성의 기대 배수가 %.2f 다 (하한 %.2f) — 그 열 탄을 통째로 잃는다"
						% [th["ko"], Balance.elem_ko(e5s), avg, ELEM_FLOOR])
			if avg >= 1.0:
				good += 1
		# 무상성은 항상 대안이며, 주 속성의 약점을 찌르는 공격도 하나 이상 보장한다.
		if good < 1:
			_bad("테마 「%s」에서 이득을 보는 속성이 %d가지뿐이다 (최소 하나의 유리한 속성이 필요하다)"
					% [th["ko"], good])
	print("  속성 정상 (영웅 %s · 약점 %s · 저항 %s · 면역 %s)"
			% [str(hero_n), str(weak_n), str(res_n), str(imm_n)])
	var wline := ""
	for e6 in Balance.ELEM_ORDER:
		if String(e6) == "none":
			continue
		wline += "%s %.2f  " % [Balance.elem_ko(String(e6)), float(worst.get(String(e6), 1.0))]
	print("  테마 %d개에서의 최악 기대 배수: %s" % [Roster.THEMES.size(), wline])


## 주 속성 70~80% 요청에 맞춘 분포 계약. 소수 속성과 전기 유효 대상도 남긴다.
const ELEM_FLOOR := 0.15
const BODY_CAP := 0.80
const BODY_MIN := 0.01
const IMMUNE_SUM_CAP := 0.85


## 테마 표 — 쉰 개의 주 속성·보스·분포가 일치하는가.
func _check_theme() -> void:
	if Roster.THEMES.is_empty():
		_bad("테마 표가 비었다")
		return
	var need := int(ceil(float(Balance.LAST_WAVE) / float(Balance.THEME_BLOCK)))
	if Roster.THEMES.size() < need:
		_bad("테마가 %d개뿐이다 — 한 판에 %d개가 필요하다" % [Roster.THEMES.size(), need])
	if Balance.BOSS_EVERY != Balance.THEME_BLOCK:
		_bad("보스 간격(%d)과 테마 블록(%d)이 다르다 — 테마의 마지막 탄이 보스맵이어야 한다"
				% [Balance.BOSS_EVERY, Balance.THEME_BLOCK])
	var ids := {}
	var kos := {}
	var per_body := {}
	var per_rank := {}
	for th in Roster.THEMES:
		var id := String(th["id"])
		if ids.has(id):
			_bad("테마 id 중복: %s" % id)
		ids[id] = true
		var ko := String(th["ko"])
		if kos.has(ko):
			_bad("테마 이름 중복: %s" % ko)
		kos[ko] = true
		var mb := String(th["main_body"])
		if not Balance.MBODY.has(mb):
			_bad("테마 %s 의 주 몸이 표에 없다: %s" % [id, mb])
		per_body[mb] = int(per_body.get(mb, 0)) + 1
		var bb := String(th["boss_body"])
		if bb != mb or String(Roster.boss_of_body(bb).get("body", "")) != mb:
			_bad("테마 %s 의 보스(%s 몸)가 몬스터 표에 없다" % [id, bb])
		var rk := int(th["rank"])
		if rk < 1 or rk > 5:
			_bad("테마 %s 의 rank 가 1~5 밖이다: %d" % [id, rk])
		per_rank[rk] = int(per_rank.get(rk, 0)) + 1
		for hex in [String(th.get("bg", "")), String(th.get("floor", ""))]:
			if not Color.html_is_valid(hex):
				_bad("테마 %s 의 색이 이상하다: %s" % [id, hex])
		# 분포
		var wt: Dictionary = th.get("weights", {})
		if float(wt.get(mb, 0.0)) < 0.70:
			_bad("테마 %s 의 주 속성 비중이 70%% 미만이다" % id)
		var sum_w := 0.0
		for b in Balance.MBODY_ORDER:
			var v: float = float(wt.get(b, -1.0))
			if v < 0.0:
				_bad("테마 %s 에 %s 몸의 분포가 없다" % [id, b])
				continue
			if v > BODY_CAP + 0.001:
				_bad("테마 %s 의 %s 분포가 %.2f 다 (상한 %.2f — 넘으면 그 속성 영웅이 열 탄을 통째로 잃는다)"
						% [id, b, v, BODY_CAP])
			if v < BODY_MIN - 0.0001:
				_bad("테마 %s 의 %s 분포가 %.2f 다 (%.2f 밑이면 그 몸이 사실상 안 나온다)"
						% [id, b, v, BODY_MIN])
			sum_w += v
		if absf(sum_w - 1.0) > 0.011:
			_bad("테마 %s 의 분포 합이 %.3f 다 (1.0 이어야 한다)" % [id, sum_w])
		# ★ **면역인 몸의 합**(IMMUNE_SUM_CAP 주석). 속성마다 따로 잰다 — 지금은 전기만
		#   면역을 받지만, 다른 속성에 면역을 하나라도 붙이는 날 이 자가 그대로 잰다.
		for e0 in Balance.ELEM_ORDER:
			var e0s := String(e0)
			if e0s == "none":
				continue
			var imm_sum := 0.0
			var imm_names: Array = []
			for b0 in Balance.MBODY_ORDER:
				if Balance.body_immune(String(b0)).has(e0s):
					imm_sum += float(wt.get(b0, 0.0))
					imm_names.append(Balance.body_ko(String(b0)))
			if imm_sum > IMMUNE_SUM_CAP + 0.001:
				_bad("테마 %s 에서 %s에게 면역인 몸(%s)의 합이 %.2f 다 (상한 %.2f — 그 열 탄의 절반 넘게가 %s 영웅에게 벽이 된다)"
						% [id, Balance.elem_ko(e0s), ", ".join(imm_names), imm_sum,
							IMMUNE_SUM_CAP, Balance.elem_ko(e0s)])
		# 주 몸이 실제로 제일 많은가 — 이름이 「호수」인데 바위가 제일 많으면 거짓말이다.
		var top := ""
		var topv := -1.0
		for b2 in Balance.MBODY_ORDER:
			if float(wt.get(b2, 0.0)) > topv:
				topv = float(wt.get(b2, 0.0))
				top = String(b2)
		if top != mb:
			_bad("테마 %s(%s)의 주 몸은 %s 인데 분포에서 제일 많은 것은 %s 다"
					% [id, th["ko"], mb, top])
	# 다섯 몸이 고루 있어야 한다. 한 몸이 없으면 그 몸의 몬스터를 영영 못 만난다.
	for b3 in Balance.MBODY_ORDER:
		if int(per_body.get(b3, 0)) < 1:
			_bad("%s 몸이 주가 되는 테마가 하나도 없다" % Balance.body_ko(String(b3)))
	# rank 가 고루 있어야 Run.roll_themes 가 뒤 블록에서 험한 곳을 고를 수 있다.
	for rk2 in range(1, 6):
		if int(per_rank.get(rk2, 0)) < 1:
			_bad("rank %d 인 테마가 하나도 없다 — 뒤 블록이 셀 수 없게 된다" % rk2)
	print("  테마 %d개 정상 (몸별 %s · 험한정도별 %s)"
			% [Roster.THEMES.size(), str(per_body), str(per_rank)])


## 한 판의 테마 차례가 실제로 뽑히는가. **100탄 어디에도 빈 탄이 없어야 한다.**
func _check_wave_plan() -> void:
	var r := Run
	r.start_run(4242)
	if r.themes.size() < int(ceil(float(Balance.LAST_WAVE) / float(Balance.THEME_BLOCK))):
		_bad("테마 차례가 %d칸뿐이다" % r.themes.size())
	var bodies := {}
	for w in range(1, Balance.LAST_WAVE + 1):
		var kinds: Array = r.kinds_for(w)
		if kinds.is_empty():
			_bad("%d탄에 나올 몬스터가 하나도 없다" % w)
			continue
		# ★ 같은 탄을 두 번 물어도 같은 답이어야 한다. 아니면 상점이 보여 준 것과
		#   실제 전투가 달라지고, 그 순간 상성은 플레이어가 쓸 수 없는 규칙이 된다.
		var again: Array = r.kinds_for(w)
		if str(again) != str(kinds):
			_bad("%d탄의 편성이 물을 때마다 다르다" % w)
		# 한 탄에 몸이 둘 이상 섞여야 한다 (전기 영웅의 사형선고 방지).
		var bs := {}
		for m in kinds:
			bs[String(m.get("body", ""))] = true
			bodies[String(m.get("body", ""))] = true
		if bs.size() < 2:
			_bad("%d탄의 몬스터가 전부 %s 몸 하나뿐이다 — 그 몸에 안 통하는 속성은 이 탄을 통째로 잃는다"
					% [w, bs.keys()])
		if Balance.is_boss_wave(w) and r.boss_for(w).is_empty():
			_bad("%d탄은 보스맵인데 보스가 없다" % w)
	for b in Balance.MBODY_ORDER:
		if not bodies.has(String(b)):
			_bad("한 판(100탄) 내내 %s 몸 몬스터가 한 번도 안 나온다" % Balance.body_ko(String(b)))
	print("  100탄 편성 정상 (테마 차례 %s)" % str(r.themes))


func _check_balance() -> void:
	for arr in [Balance.TIER_ATK, Balance.TIER_RATE]:
		if arr.size() != 10:
			_bad("등급별 표의 길이가 10이 아니다")
	# 등급이 오르면 초당 피해가 반드시 올라야 한다. 하나라도 뒤집히면 족보를 맞출 이유가 없다.
	var prev := 0.0
	for t in range(10):
		var dps: float = float(Balance.TIER_ATK[t]) * float(Balance.TIER_RATE[t])
		if dps <= prev:
			_bad("%s 등급의 초당 피해가 아래 등급보다 크지 않다 (%.1f -> %.1f)"
					% [Poker.HAND_KO[t], prev, dps])
		prev = dps
	# 같은 등급 안의 결(프로필)은 초당 피해가 비슷해야 한다 — 하나만 정답이면 나머지는 꽝이다.
	var lo := 9.9
	var hi := 0.0
	for k in Balance.PROFILE:
		var p: Dictionary = Balance.PROFILE[k]
		var v: float = float(p["atk"]) * float(p["rate"])
		lo = min(lo, v)
		hi = max(hi, v)
	if hi / lo > 1.25:
		_bad("프로필끼리 초당 피해 차이가 너무 크다 (%.2f배)" % (hi / lo))
	# ★ **사거리를 없앤 뒤로 프로필의 축은 하나뿐이다** — 한 발이 크냐, 발이 잦냐.
	#   예전에는 저격이 「덜 세지만 멀리」로 값을 했지만 이제 모두가 어디든 때리므로,
	#   공격력이 센 쪽은 반드시 공격속도가 느려야 한다. 둘 다 높은 프로필이 하나라도
	#   생기면 그 아래는 통째로 꽝이 되고, 그 캐릭터들은 뽑아도 반가울 일이 없어진다.
	var ladder: Array = []
	for k2 in Balance.PROFILE:
		var p2: Dictionary = Balance.PROFILE[k2]
		ladder.append([float(p2["atk"]), float(p2["rate"]), String(p2.get("ko", k2))])
	ladder.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for i in range(1, ladder.size()):
		if float(ladder[i][1]) >= float(ladder[i - 1][1]):
			_bad("프로필 「%s」(공격력 %.2f · 속도 %.2f)가 「%s」(%.2f · %.2f)를 두 축 다 이긴다 — 사거리가 없어진 지금 축은 둘뿐이라, 이러면 아래쪽은 고를 까닭이 없는 꽝이 된다"
					% [String(ladder[i][2]), float(ladder[i][0]), float(ladder[i][1]),
						String(ladder[i - 1][2]), float(ladder[i - 1][0]),
						float(ladder[i - 1][1])])


func _check_geometry() -> void:
	var walk := Balance.path_len() / Balance.PATH_SPEED
	# voc2 adds an inner detour while keeping monster speed unchanged (about 30.5s).
	if walk < 25.0 or walk > 35.0:
		_bad("안쪽 우회 경로 보행 시간이 25~35초 밖이다: %.2f" % walk)
	var bounds := Rect2(10, 74, 816, 720)
	for route in range(2):
		var points := Balance.route_points(route)
		if points[0].distance_to(Vector2(24, 150) if route == 0 else Vector2(808, 690)) > 0.1:
			_bad("좌상단/우하단 입구가 스케치와 다르다")
		if absf(points[-1].distance_to(Balance.ARENA_CENTER) - Balance.ALTAR_R) > 0.1:
			_bad("경로가 중앙 크리스탈 제단에 닿지 않는다")
		for jitter in [-Balance.LANE_JITTER, 0.0, Balance.LANE_JITTER]:
			var previous := Balance.path_at(0, jitter, route)
			for i in range(1, 2401):
				var q := Balance.path_at(Balance.path_len() * float(i) / 2400.0, jitter, route)
				if not bounds.has_point(q) or q.distance_to(previous) > 2.0:
					_bad("경로가 화면 밖이거나 모서리에서 끊긴다")
					break
				previous = q
		for i in range(points.size() - 1):
			if points[i].x != points[i + 1].x and points[i].y != points[i + 1].y:
				_bad("경로가 직각이 아니다")
			for j in range(i + 2, points.size() - 1):
				if Geometry2D.segment_intersects_segment(points[i], points[i + 1], points[j], points[j + 1]) != null:
					_bad("안쪽 우회 경로가 자기 자신과 교차한다")
			var other := Balance.route_points(1 - route)
			for j in range(other.size() - 1):
				if Geometry2D.segment_intersects_segment(points[i], points[i + 1], other[j], other[j + 1]) != null:
					_bad("두 진입 경로가 교차한다")
	for post in range(Balance.POST_SLOTS):
		var p := Balance.post_position(post)
		if not bounds.has_point(p) or p.distance_to(Balance.ARENA_CENTER) < Balance.ALTAR_R + 24:
			_bad("배치 지점이 화면 밖이거나 크리스탈에 겹친다")
		for next in range(post + 1, Balance.POST_SLOTS):
			if p.distance_to(Balance.post_position(next)) < 60:
				_bad("배치 지점끼리 너무 가깝다")
		for route in range(2):
			var points := Balance.route_points(route)
			for i in range(points.size() - 1):
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, points[i], points[i + 1])) < 32:
					_bad("배치 지점이 몬스터 길을 막는다")
	if Balance.crystal_pile_r() >= Balance.ALTAR_R:
		_bad("크리스탈이 제단 밖으로 넘친다")
	_check_no_range()
	print("  두 입구 · 직각 경로 연속성 · 4/4/4 발판 · 보행 %.1f초" % walk)


## 총구 — **탄이 나가는 자리**와 **팔을 뻗는 시간**.
##
## ★ 이 둘이 표와 클립에 따로 적혀 있으면 반드시 어긋난다. roster.gd 의 muz·wind 는
##   `art/anim/<id>/anim.json` 에서 그대로 찍어 낸 값이므로(tools/gen_roster.py),
##   여기서 두 파일을 나란히 놓고 같은지 본다. 어긋났다는 것은 **클립을 다시 짜 놓고
##   gen_roster.py 를 안 돌렸다**는 뜻이고, 그러면 총구 불꽃만 손끝에 있고 탄은
##   옛 자리에서 나간다.
func _check_muzzle() -> void:
	var checked := 0
	var flipped: Array = []
	for u in Roster.UNITS:
		var uid := String(u["id"])
		var m: Array = u.get("muz", [])
		if m.size() != 2:
			_bad("%s 에 총구(muz)가 없다 — 탄이 발바닥에서 나간다" % uid)
			continue
		var mx: float = float(m[0])
		var my: float = float(m[1])
		var wind: float = float(u.get("wind", -1.0))
		# 큰 활은 몸 높이보다 옆으로 길다. H3 시트는 고정된 발 원점부터
		# 실제 캔버스 끝까지를 재서, 올바른 무기 끝을 옛 체형 한도로 막지 않는다.
		var source_meta := _anim_meta(String(u.get("anim", "")))
		var max_mx := 0.95
		if String(source_meta.get("source", "")) == "last_refuge_v3_pixel_h3":
			max_mx = (float(source_meta["cell"]["w"]) - float(source_meta["anchor"]["x"])) \
					/ float(source_meta["static"]["h"])
		# 가로는 몸 옆으로 나가 있어야 하고, 세로는 발밑보다 **위**여야 한다.
		# ★ **장판(zone)은 예외다.** 두 팔을 머리 위로 드는 자세라 손이 몸 한가운데에
		#   오고, 그래서 총구 가로가 0 근처로 나온다. 그것이 **맞다** — 장판은 캐릭터에서
		#   탄이 나가지 않는다(피해는 저 멀리 깔린 원 안에서 난다). 여기서 「몸 옆」을
		#   억지로 맞추면 손이 아닌 자리에 총구 불꽃이 찍힌다.
		#   ☆ 세로는 여전히 잰다 — 발밑보다 위여야 하는 것은 장판도 마찬가지다.
		var is_zone: bool = String(u.get("bullet", "")) == "zone"
		if not is_zone and (absf(mx) < 0.05 or absf(mx) > max_mx):
			_bad("%s 의 총구 가로(%.3f)가 이상하다 — 범위 0.05~%.3f" % [uid, mx, max_mx])
		elif is_zone and absf(mx) > 0.95:
			_bad("%s 는 장판인데 총구 가로(%.3f)가 몸 밖이다" % [uid, mx])
		if my > -0.30 or my < -1.30:
			_bad("%s 의 총구 세로(%.3f)가 이상하다 — 발밑 위(-0.30~-1.30)여야 한다" % [uid, my])
		# 준비 시간이 긴 H3 내려치기도 놓는 칸이 클립 안에 있으면 유효하다.
		# 실제 전투 딜레이는 쿨다운에 맞춰 제한되어야 한다.
		var attack_length := Anim.length(u, "attack")
		var wind_limit := attack_length if attack_length > 0.0 else 0.51
		if wind < 0.05 or wind >= wind_limit:
			_bad("%s 의 뻗는 시간(%.3f초)이 공격 클립 범위를 벗어남" % [uid, wind])
		for cool in [0.08, 0.2, 0.5, 2.0]:
			var delay := Balance.windup(u, cool)
			if delay <= 0.0 or delay > cool * Balance.WIND_MAX_OF_COOL + 0.000001:
				_bad("%s 의 발사 딜레이가 연사 간격을 벗어남" % uid)
		if mx < 0.0:
			flipped.append(uid)

		# 좌우 뒤집기가 총구까지 같이 뒤집는가. 안 그러면 그림은 왼쪽을 보는데
		# 탄만 오른쪽에서 나간다.
		var r := Balance.muzzle_off(u, 1.0, 1.0)
		var l := Balance.muzzle_off(u, 1.0, -1.0)
		if r.x <= 0.0 or l.x >= 0.0 or absf(r.x + l.x) > 0.001 or absf(r.y - l.y) > 0.001:
			_bad("%s 의 총구가 좌우로 안 뒤집힌다 (%s / %s)" % [uid, str(r), str(l)])
		if Balance.art_aim(u) != (-1.0 if mx < 0.0 else 1.0):
			_bad("%s 의 그림 방향(art_aim)이 총구 부호와 다르다" % uid)

		# 클립이 있으면 **클립이 원본이다.** 표가 그것과 같은지 본다.
		var dir := String(u.get("anim", ""))
		if dir == "":
			continue
		var meta := _anim_meta(dir)
		if meta.is_empty():
			continue
		# 내보내기에서 JSON이나 시트가 빠지면 조용히 정지 그림으로 돌아간다.
		# 등록된 발사체·범위 효과까지 엔진이 실제로 읽는지 확인한다.
		for clip_name in meta.get("clips", {}):
			var loaded := Anim.clip(u, String(clip_name))
			if loaded.is_empty():
				_bad("%s: %s 애니메이션을 읽지 못했다" % [uid, clip_name])
				continue
			var spec: Dictionary = meta["clips"][clip_name]
			var cell: Dictionary = spec.get("cell", meta.get("cell", {}))
			if int(loaded["w"]) != int(cell["w"]) or int(loaded["h"]) != int(cell["h"]):
				_bad("%s: %s 프레임 크기가 다르다" % [uid, clip_name])
			if clip_name in ["shot", "effect"] and float(loaded["ay"]) != 0.5:
				_bad("%s: %s 효과의 중심점이 어긋났다" % [uid, clip_name])
		var mz: Dictionary = meta.get("muzzle_at", {})
		var st: Dictionary = meta.get("static", {})
		if mz.is_empty() or st.is_empty():
			_bad("%s 의 anim.json 에 muzzle_at 이 없다 — mkanim.py 를 다시 돌려라" % uid)
			continue
		var h: float = maxf(1.0, float(st.get("h", 1)))
		var want := Vector2(float(mz["x"]) / h, float(mz["y"]) / h)
		if absf(want.x - mx) > 0.002 or absf(want.y - my) > 0.002:
			_bad("%s 의 총구가 클립(%.3f, %.3f)과 표(%.3f, %.3f)에서 다르다"
					% [uid, want.x, want.y, mx, my])
		var hit_ms: float = float(meta.get("hit_ms", -1.0))
		if hit_ms >= 0.0 and absf(hit_ms / 1000.0 - wind) > 0.002:
			_bad("%s 의 뻗는 시간이 클립(%.3f초)과 표(%.3f초)에서 다르다"
					% [uid, hit_ms / 1000.0, wind])
		# 그리는 쪽(core/anim.gd)이 재는 값과도 같아야 한다 — 화면이 클립 속도를
		# 여기에 맞춰 돌린다.
		var ht: float = Anim.hit_time(u, "attack")
		if ht > 0.0 and absf(ht - wind) > 0.002:
			_bad("%s: Anim.hit_time(%.3f) 과 표의 wind(%.3f) 가 다르다" % [uid, ht, wind])
		if Anim.length(u, "attack") <= ht:
			_bad("%s 의 공격 클립이 놓는 칸에서 끝난다 — 되돌아오는 칸이 없다" % uid)
		checked += 1
	print("  총구 정상 (클립과 대조 %d명 · 왼쪽을 겨눈 그림 %d명 %s)"
			% [checked, flipped.size(), str(flipped)])


func _anim_meta(dir: String) -> Dictionary:
	var path := dir + "anim.json"
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


## **사거리가 되살아나지 않았는가.**
##
## ★ 사용자가 규칙을 바꿔 사거리를 통째로 없앴다 — 영웅은 어디에 서든 길 위의 아무나
##   때린다. 그런데 이렇게 **없앤 개념**은 표에 한 줄, 사전에 한 열쇠만 남아도 조용히
##   되살아난다: `hero_stats` 가 rng 를 다시 돌려주고 전투가 그것을 사거리로 읽으면,
##   화면 어디에도 안 적힌 채로 「어떤 영웅은 안 닿는다」가 다시 생긴다. 그건 플레이어가
##   원인을 영영 못 찾는 종류의 어긋남이라, 없어졌다는 것 자체를 못 박아 둔다.
## ★ **없어진 상수를 코드로 적으면 안 된다** — `Balance.TIER_RNG` 라고 쓰는 순간 이
##   파일이 파스부터 깨져서 검사기가 통째로 안 돈다. 그래서 표는 반사(상수 목록)로,
##   함수는 글자로 본다.
func _check_no_range() -> void:
	# ★ 하나라도 잡혔으면 끝의 「없음 확인」을 안 찍는다. 이 검사를 만들다가 실패 셋과
	#   「없음 확인」이 같은 로그에 나란히 찍히는 것을 봤다 — 로그를 훑는 사람은 그 줄만
	#   보고 통과한 것으로 읽는다.
	var was := fail
	var probe: Dictionary = {"unit": Roster.UNITS[0], "tier": int(Roster.UNITS[0]["tier"]),
			"wave": 1, "n": 1}
	if Run.hero_stats(probe).has("rng"):
		_bad("hero_stats() 가 아직 'rng' 를 돌려준다 — 사거리는 없앴다(어디서든 때린다). 전투가 그 값을 다시 사거리로 읽는 순간 개념이 통째로 되살아난다")
	for u in Balance.UPGRADES:
		if String(u["id"]) == "rng":
			_bad("상점에 「사거리」 능력치가 남아 있다 — 늘릴 사거리가 없다")
	for k in Balance.PROFILE:
		if (Balance.PROFILE[k] as Dictionary).has("rng"):
			_bad("프로필 %s 에 rng 가 남아 있다 — 프로필의 축은 이제 한 발의 크기와 발 수 둘뿐이다"
					% String(k))
	for p in Balance.PASSIVES:
		if p.has("rng"):
			_bad("패시브 %s 가 사거리를 올린다 — 올릴 사거리가 없다" % String(p["id"]))
	var bs := load("res://core/balance.gd") as GDScript
	if bs == null:
		_bad("core/balance.gd 를 못 읽었다")
	elif bs.get_script_constant_map().has("TIER_RNG"):
		_bad("Balance.TIER_RNG 가 남아 있다 — 등급별 사거리 표는 없앴다")
	for line in _lines_of("res://core/balance.gd"):
		if line.contains("func rng_mult"):
			_bad("Balance.rng_mult() 가 남아 있다 — 살 수 있는 사거리가 없으므로 곱할 것도 없다")
	# ★ **전투가 들고 도는 영웅 사전**에도 남으면 안 된다. 표를 다 지워도 여기 한 줄이
	#   남아 있으면 화면이 그 값으로 원반과 사거리 고리를 계속 그린다.
	Run.start_run(31415)
	Run.begin_draw()
	Run.confirm_hand()
	var sim := BattleSim.new()
	sim.setup(Run, 1, 4242)
	if sim.heroes.is_empty():
		_bad("영웅을 하나도 못 받았다 — 사거리 검사를 못 한다")
	elif (sim.heroes[0] as Dictionary).has("rng"):
		_bad("전투의 영웅 사전에 아직 'rng' 가 있다 — 표에서 지워도 전투가 그것으로 사거리를 잰다")
	if fail == was:
		print("  사거리 없음 확인 (등급표·프로필·상점·패시브·hero_stats·전투 어디에도 안 남았다)")


## 그 파일의 줄들. **주석 줄은 건너뛴다** — 없앤 것을 **설명하는** 자리(주석에 남은
## 옛 이름)까지 걸리면 검사가 켜자마자 늘 실패해서, 결국 아무도 안 보게 된다.
func _lines_of(path: String) -> Array[String]:
	var out: Array[String] = []
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return out
	for line in fa.get_as_text().split("\n"):
		var t := String(line).strip_edges()
		if t.begins_with("#"):
			continue
		out.append(t)
	return out


## 영웅 편성 — 전장 열두 자리 · 중복 출전 금지 · 복사본은 전당 보관.
##
## ★ 여기서 실제로 영웅을 마흔 번 받아 본다. 화면 없이 규칙만 돌려 보는 것이라
##   "겹쳤는데 전당에도 남아 있는" 종류의 어긋남이 여기서 잡힌다.
func _check_roster_slots() -> void:
	if Balance.HERO_SLOTS != 12 or Balance.POST_SLOTS != 12 or Balance.POST_POINTS.size() != 12:
		_bad("좌측/중앙/우측 각 4개 배치 지점이 필요하다")
	# ★ 캐릭터 전부가 성역+전당에 들어가야 한다. 안 그러면 넘칠 때 영웅이 사라진다.
	if Balance.HERO_SLOTS + Balance.BENCH_SLOTS < Roster.UNITS.size():
		_bad("자리가 모자란다: 성역 %d + 전당 %d < 캐릭터 %d명"
				% [Balance.HERO_SLOTS, Balance.BENCH_SLOTS, Roster.UNITS.size()])
	# ★ 겹치면 **한 발의 세기 x 발 수**가 정확히 n 이어야 한다. 둘 중 하나만 맞으면
	#   x8 영웅이 단일 대상에게 여덟 배가 아니게 된다 — 화면에는 x8 이라고 적힌 채로.
	for n in [1, 2, 3, 5, 8, 16]:
		var got: float = Balance.stack_atk(n) * float(Balance.stack_shots(n))
		if absf(got - float(n)) > 0.0001:
			_bad("x%d 의 세기 x 발 수가 %.3f 다 (%d 이어야 한다)" % [n, got, n])
	if Balance.stack_shots(1) != 1:
		_bad("1겹인데 발이 %d개 나간다" % Balance.stack_shots(1))
	if Balance.stack_shots(99) != Balance.STACK_SHOT_MAX:
		_bad("발 수 상한이 안 걸린다")

	Run.start_run(5150)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var given := 0
	for i in range(Balance.LAST_WAVE):
		Run.wave = i + 1
		var tier: int = i % 10
		Run.gain_hero(Roster.pick_unit(tier, rng), tier)
		given += 1
		if Run.heroes.size() > Balance.HERO_SLOTS:
			_bad("성역에 %d명이 섰다 (%d명까지다)" % [Run.heroes.size(), Balance.HERO_SLOTS])
			break
	# 같은 캐릭터의 중복 출전은 금지하고 전당의 복사본은 허용한다.
	var seen := {}
	for h in Run.heroes:
		var id := String(h["unit"]["id"])
		if seen.has(id):
			_bad("%s 가 전장 두 자리에 중복 배치되었다" % id)
		seen[id] = true
	# 받은 수와 겹친 수의 합이 같아야 한다. 하나라도 사라지면 여기서 잡힌다.
	if Run.hero_total() != given:
		_bad("영웅 %d명을 받았는데 겹친 수까지 세면 %d명이다 — 어디선가 사라졌다"
				% [given, Run.hero_total()])

	# 이전 저장의 중첩 값이 현재 단일 영웅의 공격력을 바꾸면 안 된다.
	if Run.heroes.is_empty():
		_bad("영웅을 마흔 번 받았는데 성역이 비었다")
		return
	var one: Dictionary = {"unit": Run.heroes[0]["unit"], "tier": int(Run.heroes[0]["tier"]),
			"wave": 1, "n": 1}
	var three: Dictionary = one.duplicate()
	three["n"] = 3
	var s1: Dictionary = Run.hero_stats(one)
	var s3: Dictionary = Run.hero_stats(three)
	var a1: float = float(s1["atk"]) * float(s1.get("shots", 1))
	var a3: float = float(s3["atk"]) * float(s3.get("shots", 1))
	if absf(a3 - a1) > 0.01:
		_bad("이전 중첩 값이 현재 1인 화력을 바꾼다 (%.2f -> %.2f)" % [a1, a3])
	# 자리바꿈: 성역 0번과 전당 0번을 맞바꿔도 둘 다 그대로 있어야 한다
	if not Run.bench.is_empty():
		var f0 := String(Run.heroes[0]["unit"]["id"])
		var b0 := String(Run.bench[0]["unit"]["id"])
		if not Run.swap_field_bench(0, 0):
			_bad("성역과 전당을 맞바꾸지 못했다")
		elif String(Run.heroes[0]["unit"]["id"]) != b0 \
				or String(Run.bench[0]["unit"]["id"]) != f0:
			_bad("맞바꿨는데 자리가 안 바뀌었다")
		if Run.hero_total() != given:
			_bad("자리를 바꿨더니 영웅 수가 %d 로 바뀌었다 (%d 이어야 한다)"
					% [Run.hero_total(), given])
	print("  영웅 편성 정상 (성역 %d · 전당 %d · 전체 %d)"
			% [Run.heroes.size(), Run.bench.size(), Run.hero_total()])


## 크리스탈 셈이 맞는가. **실제로 전투를 돌려서** 본다.
##
## ★ play_check 로는 이걸 못 잡는다 — 앞 네 탄은 한 마리도 안 놓쳐서 "크리스탈이 두 번
##   깎이는가"를 물어볼 상황 자체가 안 만들어진다. 여기서는 **영웅을 한 명도 안 세워**
##   전부 통과시킨 다음, 깎인 수와 센 수가 같은지 본다.
func _check_battle() -> void:
	# 1) end_run 은 두 번 불려도 기록을 두 번 쌓지 않아야 한다
	Run.start_run(4242)
	Run.kills = 7
	var before: int = Save.total_kills
	Run.end_run(false)
	Run.end_run(false)
	# Defeat statistics settle only after the player declines the continue option.
	Run.finish_defeat()
	Run.finish_defeat()
	if Save.total_kills != before + 7:
		_bad("패배 확정을 두 번 불렀더니 누적 처치 수가 %d 늘었다 (7 이어야 한다)"
				% (Save.total_kills - before))

	# 2) 영웅 없이 한 탄을 돌린다 — 전부 크리스탈까지 온다
	Run.start_run(4243)
	Run.begin_draw()          # 영웅은 안 세운다(confirm_hand 를 안 부른다)
	var sim := BattleSim.new()
	sim.setup(Run, 1, 99)
	var guard := 0
	while not sim.done and guard < 20000:
		sim.step(1.0 / 30.0)
		sim.events.clear()
		guard += 1
	if not sim.done:
		_bad("영웅 없는 전투가 안 끝난다")
	if sim.leak_n != Balance.wave_count(1):
		_bad("1탄 몬스터 %d마리 중 %d마리만 크리스탈에 닿았다"
				% [Balance.wave_count(1), sim.leak_n])
	if Run.lives != Balance.START_LIVES - sim.leaked:
		_bad("크리스탈 셈이 안 맞는다: 깨졌다고 센 것 %d, 실제로 준 것 %d"
				% [sim.leaked, Balance.START_LIVES - Run.lives])
	if sim.wiped:
		_bad("한 마리도 못 잡았는데 전멸(wiped)로 나온다")

	# 3) 크리스탈이 모자랄 때 — 없는 것까지 깨졌다고 세면 안 된다
	Run.start_run(4244)
	Run.begin_draw()
	Run.lives = 3
	var sim2 := BattleSim.new()
	# 보스탄 — 보스 하나가 다섯을 부순다.
	# ★ 5 를 못 박지 마라. 보스 간격이 10 으로 바뀌면 5탄은 보스탄이 아니게 되어,
	#   이 검사가 **아무 말 없이 아무것도 안 보게** 된다.
	sim2.setup(Run, Balance.BOSS_EVERY, 77)
	guard = 0
	while not sim2.done and guard < 20000:
		sim2.step(1.0 / 30.0)
		sim2.events.clear()
		guard += 1
	if sim2.leaked > 3:
		_bad("크리스탈이 3개뿐인데 %d개가 깨진 것으로 셌다" % sim2.leaked)
	if Run.lives != 0 or Run.running:
		_bad("크리스탈이 0 이 됐는데 판이 안 끝났다 (크리스탈 %d, running %s)"
				% [Run.lives, Run.running])
	print("  크리스탈 셈 정상 (1탄 %d마리 통과 · 보스탄에서 %d개까지만 깨짐)"
			% [sim.leak_n, sim2.leaked])
	_check_fire_events()


## 탄이 **총구에서 · 팔을 다 뻗은 뒤에** 나가는가 — 실제로 한 탄을 돌려서 본다.
##
## ★ 표만 봐서는 못 잡는 것들이 여기서 잡힌다: 「aim 을 흘리는 것을 깜빡했다」,
##   「fire 자리를 다시 발밑으로 되돌렸다」, 「기다리는 시간이 0 이 됐다」.
##   셋 다 화면에서는 "모션이 안 맞는다"로만 보여서 눈으로는 원인을 못 찾는다.
func _check_fire_events() -> void:
	Run.start_run(4245)
	Run.begin_draw()
	Run.confirm_hand()
	var sim := BattleSim.new()
	sim.setup(Run, 6, 31337)
	if sim.heroes.is_empty():
		_bad("영웅을 하나도 못 받았다 — 사격 검사를 못 한다")
		return
	var aim_t := {}          # 영웅 번호 → 마지막으로 팔을 뻗기 시작한 때
	var pairs := 0
	var worst_dt := 0.0
	var worst_dp := 0.0
	var guard := 0
	var el := 0.0
	var dt: float = 1.0 / 60.0
	while not sim.done and guard < 20000:
		sim.step(dt)
		el += dt
		for e in sim.events:
			var ty := String(e["t"])
			if ty != "aim" and ty != "fire":
				continue
			var src: int = int(e.get("src", -1))
			if src < 0 or src >= sim.heroes.size():
				continue
			var he: Dictionary = sim.heroes[src]
			# 총구는 **발밑이 아니다.** 시뮬레이터가 들고 있는 값과 정확히 같아야 한다.
			var muz: Vector2 = he["muz"]
			var want: Vector2 = Vector2(he["pos"]) \
					+ Vector2(muz.x * float(he["face"]), muz.y)
			var dp: float = (Vector2(e["p"]) - want).length()
			worst_dp = maxf(worst_dp, dp)
			if ty == "aim":
				aim_t[src] = el
				# 장판은 뻗는 시간이 없다(0). 나머지는 반드시 기다렸다 쏜다.
				# ★ 예전에는 장판(aura)만 예외였다 — 쿨다운도 총구도 팔 뻗기도 없이
				#   판 위의 전부를 매 프레임 때리는 방식이었기 때문이다. 지금은 그 방식이
				#   없고(zone 이 갈아 끼웠다) **모든 방식이 팔을 뻗는다.** 예외는 없다.
				if float(e.get("w", 0.0)) <= 0.0:
					_bad("%s 가 기다리지 않고 쏜다 (wind 0)"
							% String(he["h"]["unit"]["ko"]))
			elif aim_t.has(src):
				var gap: float = el - float(aim_t[src])
				var wind: float = float(he["h"]["unit"].get("wind", 0.0))
				# 연사로 깎였을 수 있으니 위쪽만 본다 — **0 이면 안 된다**가 요점이다.
				if gap > wind + 3.0 * dt:
					worst_dt = maxf(worst_dt, gap - wind)
				if gap < dt:
					_bad("%s 가 팔을 뻗기도 전에 쐈다 (%.3f초)"
							% [String(he["h"]["unit"]["ko"]), gap])
				pairs += 1
				aim_t.erase(src)
		sim.events.clear()
		guard += 1
	if pairs < 5:
		_bad("사격 검사에서 aim→fire 짝을 %d번밖에 못 봤다 — 검사가 뜻이 없어졌다" % pairs)
	if worst_dp > 0.001:
		_bad("탄이 총구가 아닌 곳에서 나간다 (최대 %.2fpx 어긋남)" % worst_dp)
	print("  사격 정상 (aim→fire %d쌍 · 총구 어긋남 %.3fpx · 기다린 시간 초과 %.3f초)"
			% [pairs, worst_dp, worst_dt])
	_check_dmg_split(sim)


## 상성별 세 통(2배 · 보통 · 반감)이 합계와 어긋나지 않는가.
##
## ★ 왜 검사가 필요한가: 전투 정보판이 영웅마다 이 셋을 막대 세 줄로 쌓는데, 합계와
##   따로 세는 값이라 **한쪽만 더하고 다른 쪽을 빠뜨리면 아무도 못 잡는다.** 막대는
##   그럴듯하게 자라고 합계도 그럴듯하게 자라는데 둘이 서로 다른 이야기를 한다.
## ★ 면역(0배)은 어디에도 안 쌓인다 — 피해가 0 이라 셋 중 어느 통에도 안 들어간다.
##   그래서 「합계 = 셋의 합」이 그대로 성립한다.
func _check_dmg_split(sim: BattleSim) -> void:
	var worst := 0.0
	var tot := 0.0
	var seen := {"dw": 0.0, "dn": 0.0, "dr": 0.0}
	for he in sim.heroes:
		var d: float = float(he.get("dmg", 0.0))
		var sum := 0.0
		for k in ["dw", "dn", "dr"]:
			var v: float = float(he.get(k, 0.0))
			if v < 0.0:
				_bad("상성별 피해가 음수다 (%s = %.3f)" % [k, v])
			seen[k] = float(seen[k]) + v
			sum += v
		tot += d
		worst = maxf(worst, absf(sum - d))
	if tot <= 0.0:
		_bad("한 탄을 돌렸는데 아무도 피해를 안 줬다 — 상성 검사가 뜻이 없어졌다")
		return
	# 부동소수 오차만 허용한다. 합계와 셋의 합은 **같은 한 줄**에서 쌓이므로 원래 같다.
	if worst > tot * 1e-6 + 0.001:
		_bad("상성별 세 통의 합이 합계와 다르다 (최대 %.4f 어긋남)" % worst)
	print("  상성별 피해 정상 (합계 %.0f = 2배 %.0f + 보통 %.0f + 반감 %.0f)"
			% [tot, seen["dw"], seen["dn"], seen["dr"]])


func _check_shop() -> void:
	var seen := {}
	for u in Balance.UPGRADES:
		var id := String(u["id"])
		if seen.has(id):
			_bad("업그레이드 id 중복: %s" % id)
		seen[id] = true
		if Balance.upgrade_cost(id, 0) <= 0:
			_bad("%s 의 값이 0 이다" % id)
	# ★ 패시브 id 가 능력치 id 와 겹치면 상점 버튼 id 가 같아져서 **엉뚱한 것이 팔린다.**
	var ranks := {}
	for p in Balance.PASSIVES:
		var id := String(p["id"])
		if seen.has(id):
			_bad("패시브 id 가 다른 상품과 겹친다: %s" % id)
		seen[id] = true
		if int(p["cost"]) <= 0:
			_bad("패시브 %s 의 값이 0 이다" % id)
		if Balance.passive_by_id(id).is_empty():
			_bad("패시브 %s 를 id 로 못 찾는다" % id)
		if String(p.get("icon", "")) == "":
			_bad("패시브 %s 에 문양(icon)이 없다 — 카드가 빈 채로 그려진다" % id)
		if not Color.html_is_valid(String(p.get("tint", ""))):
			_bad("패시브 %s 의 카드 색(tint)이 이상하다" % id)
		var rk := int(p.get("rank", 0))
		if rk < 1 or rk > 3:
			_bad("패시브 %s 의 rank(%d)가 1~3 밖이다" % [id, rk])
		ranks[rk] = int(ranks.get(rk, 0)) + 1
	# ★ **칸(3)보다 훨씬 많아야 고르는 재미가 있다.** 넷뿐이면 "셋만 든다"가 규칙이 아니라
	#   그냥 다 드는 것과 같다.
	if Balance.PASSIVE_SLOTS < 1 or Balance.PASSIVES.size() < Balance.PASSIVE_SLOTS * 5:
		_bad("패시브 칸(%d)에 견줘 종류(%d)가 너무 적다 — 고를 것이 없다"
				% [Balance.PASSIVE_SLOTS, Balance.PASSIVES.size()])
	# ★ rank 마다 셋은 있어야 한다. 하나뿐이면 그 rank 가 열리는 탄에 진열이 늘 같다.
	for rk2 in [1, 2, 3]:
		if int(ranks.get(rk2, 0)) < 3:
			_bad("rank %d 패시브가 %d개뿐이다 (셋은 있어야 진열이 안 굳는다)"
					% [rk2, int(ranks.get(rk2, 0))])
	# ★ 1탄 상점에 rank 3 이 뜨면 살 수도 없는 카드가 셋 중 한 자리를 먹는다.
	if Balance.passive_rank_cap(1) != 1 or Balance.passive_rank_cap(Balance.LAST_WAVE) != 3:
		_bad("패시브 rank 문턱이 이상하다 (1탄 %d · 마지막 탄 %d)"
				% [Balance.passive_rank_cap(1), Balance.passive_rank_cap(Balance.LAST_WAVE)])
	# ★ 크리스탈 되사기 값은 **탄에 따라 올라야 한다.** 고정이면 후반 한 탄 벌이로
	#   스무 개를 통째로 되사서 크리스탈이 목숨이 아니게 된다(옛 「크리스탈 수리」의 사고).
	if Balance.repair_cost(Balance.LAST_WAVE, 0) <= Balance.repair_cost(1, 0) * 4:
		_bad("크리스탈 되사기 값이 마지막 탄에서도 %d 다 (1탄 %d)"
				% [Balance.repair_cost(Balance.LAST_WAVE, 0), Balance.repair_cost(1, 0)])
	if Balance.repair_cost(10, 5) <= Balance.repair_cost(10, 0):
		_bad("크리스탈을 살수록 값이 올라야 한다")
	# ★ 최대치는 **늘지 않는다.** 사용자가 정한 규칙이다.
	if Balance.MAX_LIVES != Balance.START_LIVES:
		_bad("크리스탈 최대치(%d)가 시작 개수(%d)와 다르다 — 늘어나면 안 된다"
				% [Balance.MAX_LIVES, Balance.START_LIVES])
	for u2 in Balance.UPGRADES:
		if String(u2["id"]) == "life":
			_bad("「크리스탈 +1」 업그레이드가 남아 있다 — 최대치는 안 는다")
	# 리롤 값은 반드시 올라야 한다 — 안 오르면 "한 번만 공짜"라는 규칙이 무너진다.
	var prev := -1
	for n in range(5):
		var c := Balance.reroll_cost(n)
		if c <= prev:
			_bad("유료 리롤 값이 오르지 않는다: %d번째 %d" % [n, c])
		prev = c

	# --- 상점이 적는 **누적 값**이 썩지 않게 (「Lv 3」이 아니라 「x1.52 (+52%)」다) ---
	# ★ 왜 세 겹이나 거는가: 새 업그레이드 한 줄을 넣을 때 `Run.up_at()` 의 match 에 그
	#   id 를 넣는 것을 깜빡하면 **어느 단계에서나 1.0** 이 돌아온다. 그러면 상점은
	#   「x1.00 (+0%)」을 얌전히 적고, 아무도 그것이 「안 오른다」가 아니라
	#   「안 적혀 있다」임을 못 알아챈다. 화면에도 로그에도 티가 안 나는 종류의 어긋남이다.
	# 아무것도 안 산 값 — show 마다 「기준점」이 다르다.
	var neutral := {"mult": 1.0, "pct": 0.0, "x": Balance.CRIT_BASE_MULT,
			"count": float(Balance.FREE_REROLL), "slow": 1.0}
	for u3 in Balance.UPGRADES:
		var id3 := String(u3["id"])
		var shw := String(u3.get("show", ""))
		# (a) 표시 방법이 있고, 그것을 upgrade_show() 가 아는가.
		if not neutral.has(shw):
			_bad("업그레이드 %s 의 show 가 '%s' 다 — upgrade_show() 가 아는 것은 %s 뿐이고, 모르는 값은 조용히 곱셈배수로 적힌다"
					% [id3, shw, str(neutral.keys())])
			continue
		# (b) 0단계 값이 그 show 의 기준값인가. 여기가 up_at 의 match 를 지키는 그물이다.
		var at0: float = Run.up_at(id3, 0)
		if absf(at0 - float(neutral[shw])) > 1e-9:
			_bad("%s 를 하나도 안 샀는데 값이 %.4f 다 (%.4f 이어야 한다 · 상점에는 「%s」로 찍힌다) — up_at() 의 match 에서 이 id 가 빠졌을 때 나는 증상이다"
					% [id3, at0, float(neutral[shw]), Balance.upgrade_show(id3, at0)])
		# (c) 끝까지 사면 **옳은 쪽으로** 움직이는가. 진창만 내려간다(몬스터가 느려진다).
		var cap3: int = int(u3.get("cap", 0))
		var top3: int = cap3 if cap3 > 0 else 8
		var atc: float = Run.up_at(id3, top3)
		if id3 == "mire":
			if atc >= at0:
				_bad("길 진창을 %d단계까지 샀는데 %.4f → %.4f 다 — 사도 몬스터가 안 느려진다"
						% [top3, at0, atc])
		elif atc <= at0:
			_bad("%s 를 %d단계까지 샀는데 %.4f → %.4f 다 — 사도 안 오르는 상품이다"
					% [id3, top3, at0, atc])

	# (d) ★ 여기가 이 검사에서 제일 값어치가 있다 — **공식이 두 벌 있는 것**을 잡는다.
	#   상점은 Run.stat_now() 를 보고 전투는 Run.hero_stats() 를 본다. 패시브를 하나도
	#   안 들었으면 셋(up_at·stat_now·hero_stats)이 **글자 그대로 같은 값**이어야 한다.
	#   한쪽만 고치면 상점에 적힌 숫자와 실제로 걸리는 값이 갈라지는데, 그 어긋남은
	#   화면으로도 로그로도 안 잡힌다 (CLAUDE.md 18).
	Run.start_run(778899)
	Run.passives.clear()
	Run.levels = {"atk": 3, "rate": 2, "crit": 4, "critx": 2,
			"gold": 3, "reroll": 1, "mire": 2}
	for u4 in Balance.UPGRADES:
		var id4 := String(u4["id"])
		var now_v: float = Run.stat_now(id4)
		var at_v: float = Run.up_at(id4, Run.lv(id4))
		if absf(now_v - at_v) > 1e-9:
			_bad("패시브를 안 들었는데 %s 의 stat_now(%.6f)와 up_at(%.6f)가 다르다 — 상점이 적는 값과 실제로 걸리는 값이 갈라졌다"
					% [id4, now_v, at_v])
	var probe: Dictionary = {"unit": Roster.UNITS[0], "tier": int(Roster.UNITS[0]["tier"]),
			"wave": 1, "n": 1}
	var pst: Dictionary = Run.hero_stats(probe)
	if absf(float(pst["crit"]) - Run.stat_now("crit")) > 1e-9:
		_bad("치명타 확률이 전투(%.6f)와 상점(%.6f)에서 다르다 — 같은 공식이 두 벌이다"
				% [float(pst["crit"]), Run.stat_now("crit")])
	if absf(float(pst["critx"]) - Run.stat_now("critx")) > 1e-9:
		_bad("치명타 배율이 전투(%.6f)와 상점(%.6f)에서 다르다 — 같은 공식이 두 벌이다"
				% [float(pst["critx"]), Run.stat_now("critx")])
	print("  상점 표시 정상 (능력치 %d줄 · 0단계 기준값과 만렙 방향 · stat_now = hero_stats)"
			% Balance.UPGRADES.size())


## 무작위 카드 교체: 중복 없이 다른 네 슬롯을 보존한다.
func _check_piles() -> void:
	# Current rerolls choose randomly from all cards outside the current five.
	Run.start_run(20260828)
	for wave in range(3):
		Run.begin_draw()
		if Run.cards.size() != 5 or Poker.evaluate(Run.cards) < 0:
			_bad("새 손패는 서로 다른 정상 카드 다섯 장이어야 한다")
		var seen := {}
		for turn in range(512):
			Run.gold = 999999
			Run.paid[0] = 0
			var before := Run.cards.duplicate()
			if not Run.reroll(0):
				_bad("골드가 충분한 교체가 차단되었다")
				break
			if before.has(Run.cards[0]) or Poker.evaluate(Run.cards) < 0:
				_bad("교체 결과는 이전 손패와 중복되면 안 된다")
			for slot in range(1, 5):
				if Run.cards[slot] != before[slot]:
					_bad("한 장 교체가 다른 슬롯까지 바꿨다")
			seen[Run.cards[0]] = true
		if seen.size() != 48:
			_bad("교체 슬롯은 다른 네 장을 제외한 48장 모두에 도달해야 한다")
	print("  카드 교체 정상 (다섯 장 중복 금지 · 다른 슬롯 보존 · 48장 선택 가능)")


## **판을 담은 것이 파일에 그대로 들어갔다 나오는가.**
##
## ★ 왜 따로 보는가: `play_check` 는 담고 되돌리는 것을 **메모리에서** 맞춰 본다.
##   그런데 실제로 저장되는 길은 `ConfigFile` 이고, 거기에는 담을 수 있는 값의 종류가
##   따로 있다 — 형이 붙은 배열(`Array[String]`)이나 중첩 딕셔너리가 조용히 다른 것으로
##   바뀌면, 게임에서는 멀쩡한데 **앱을 껐다 켠 다음에만** 판이 깨진다. 그건 사용자만
##   겪고 로그에는 한 줄도 안 남는 종류의 버그다.
## ★ **진짜 저장 파일(user://save.cfg)은 건드리지 않는다.** 임시 파일에 써 보고 지운다 —
##   검사가 "내 기록"을 덮으면 안 된다는 규칙(CLAUDE.md 21번)과 같은 뜻이다.
const SAVE_TMP := "user://_ns_savecheck.tmp"

func _check_save() -> void:
	Run.start_run(20260828)
	Run.begin_draw()
	Run.confirm_hand()
	Run.gold = 1234
	Run.lives = 15
	Run.levels["atk"] = 4
	Run.passives.clear()
	Run.passives.append(String(Balance.PASSIVES[0]["id"]))
	Run.roll_shop()
	Run.reroll(0)
	var snap := Run.snapshot()

	var cf := ConfigFile.new()
	cf.set_value("cur", "state", snap)
	if cf.save(SAVE_TMP) != OK:
		_bad("자동 저장: 임시 파일에 못 썼다")
		return
	var cf2 := ConfigFile.new()
	if cf2.load(SAVE_TMP) != OK:
		_bad("자동 저장: 임시 파일을 못 읽었다")
		return
	var back: Dictionary = cf2.get_value("cur", "state", {})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TMP))

	if back.is_empty():
		_bad("자동 저장: 파일에서 돌아온 것이 비었다")
		return
	# 같은 값이 그대로 돌아왔는가 — 키마다 하나씩 본다.
	for k in snap:
		if not back.has(k):
			_bad("자동 저장: 파일을 거치니 '%s' 가 사라졌다" % String(k))
	var want_gold := int(snap["gold"])
	var want_cards: Array = Array(snap["cards"])
	if not Run.restore(back):
		_bad("자동 저장: 파일에서 돌아온 것을 되돌리지 못했다")
		return
	if Run.gold != want_gold:
		_bad("자동 저장: 골드가 %d → %d" % [want_gold, Run.gold])
	if Array(Run.cards) != want_cards:
		_bad("자동 저장: 카드 다섯 장이 파일을 거치며 달라졌다")
	if Run.passives.size() != 1:
		_bad("자동 저장: 패시브가 파일을 거치며 %d개가 됐다" % Run.passives.size())
	if Run.lv("atk") != 4:
		_bad("자동 저장: 능력치 단계가 파일을 거치며 %d 가 됐다" % Run.lv("atk"))
	# 형이 다른 판 번호는 **거절**해야 한다. 안 그러면 옛 저장이 새 규칙에 섞인다.
	var stale := snap.duplicate(true)
	stale["v"] = int(snap["v"]) - 1
	if Run.restore(stale):
		_bad("자동 저장: 판 번호가 다른 저장을 받아들였다 — 옛 저장이 새 규칙에 섞인다")
	print("  자동 저장 정상 (파일을 거쳐 %d개 키가 그대로 돌아옴)" % snap.size())


## 화면에 뜨는 **영문 이름**. 사용자가 정한 것이라 표에 반드시 있어야 하고, 겹치면
## 편성 판에서 같은 이름 둘이 서게 된다.
##
## ★ 폭도 같이 본다. 「Thunderthrone」은 열세 자라, 전당 칸(약 94px)에서 9px 로 줄여도
##   안 들어가면 옆 칸까지 흘러넘친다 — 예전에 「스트레이트플러시」로 똑같이 겪었다.
func _check_names() -> void:
	var previous_locale := I18n.locale
	I18n.set_locale("en")
	var seen := {}
	var widest := ""
	var wmax := 0.0
	for u in Roster.UNITS:
		var en := String(u.get("en", ""))
		if en == "":
			_bad("%s 에 영문 이름(en)이 없다" % u["id"])
			continue
		if seen.has(en):
			_bad("영문 이름 중복: %s" % en)
		seen[en] = true
		if Look.unit_name(u) != en:
			_bad("%s 의 화면 이름이 en 과 다르다" % u["id"])
		if String(u.get("lore", "")) == "":
			_bad("%s 에 설명(lore)이 없다 — 설명 팝업이 빈 채로 뜬다" % u["id"])
		var w := Look.text_width(en, 9)
		if w > wmax:
			wmax = w
			widest = en
	# 9px 는 text_center_fit 의 바닥값이다. 그것으로도 안 들어가면 줄일 길이 없다.
	if wmax > 96.0:
		_bad("제일 긴 이름 「%s」이 9px 로도 %.0fpx 다 — 전당 칸(94px)을 넘는다"
				% [widest, wmax])
	else:
		print("  영문 이름 %d개, 제일 긴 「%s」 %.0fpx (9px 기준)" % [seen.size(), widest, wmax])
	I18n.set_locale(previous_locale)


## **부르는 소리 이름이 실제로 있는 파일인가.** 표를 두 곳에 두지 않으려고
## `tools/gen_sfx.py` 한 곳에서만 이름을 짓는데, 화면이 오타 난 이름을 부르면
## 그 소리는 **조용히** 안 난다 — 사진으로도 로그로도 안 잡히는 종류의 어긋남이다.
func _check_sfx(strict: bool) -> void:
	var want := {}
	for dir in ["res://core", "res://game"]:
		for f in _gd_files(dir):
			var fa := FileAccess.open(f, FileAccess.READ)
			if fa == null:
				continue
			var txt := fa.get_as_text()
			for fn in ["Sfx.play(\"", "Sfx.force(\""]:
				var at := 0
				while true:
					at = txt.find(fn, at)
					if at < 0:
						break
					at += fn.length()
					var end := txt.find("\"", at)
					if end > at:
						var nm := txt.substr(at, end - at)
						# ★ "reveal%d" 처럼 **코드가 만드는 이름**은 건너뛴다. 그런 것은
						#   아래에서 손으로 풀어 적는다.
						if not nm.contains("%"):
							want[nm] = f
	# 속성마다의 발사음도 실제로 있어야 한다 — 이름이 코드로 지어지므로 위 검색에 안 걸린다.
	for e in Balance.ELEM_ORDER:
		want[Sfx.shot_id(String(e), "shot")] = "Sfx.shot_id"
	for k in ["beam", "zone"]:
		want[Sfx.shot_id("none", k)] = "Sfx.shot_id"
	for em in [2.0, 1.0, 0.5, 0.0]:
		want[Sfx.hit_id(em)] = "Sfx.hit_id"
	# 족보 열 등급의 확정음.
	for i in range(10):
		want["reveal%d" % i] = "draw_screen"
	var miss: Array[String] = []
	for id in want:
		if not ResourceLoader.exists("res://art/sfx/%s.wav" % String(id)):
			miss.append("%s (%s)" % [String(id), String(want[id])])
	if miss.is_empty():
		print("  소리 %d개 모두 있음" % want.size())
	elif strict:
		_bad("소리 %d개가 없다: %s" % [miss.size(), ", ".join(miss.slice(0, 8))])
	else:
		print("  (소리 %d개 아직 없음 — python3 tools/gen_sfx.py)" % miss.size())


func _check_art(strict: bool) -> void:
	var miss: Array[String] = []
	for u in Roster.UNITS:
		if not ResourceLoader.exists(String(u["art"])):
			miss.append(String(u["id"]))
	for m in Roster.MONSTERS:
		if not ResourceLoader.exists(String(m["art"])):
			miss.append(String(m["id"]))
	for k in Roster.ART:
		if not ResourceLoader.exists(String(Roster.ART[k])):
			miss.append(String(k))
	# ★ 테마 그림(배경·바닥)은 **없어도 게임이 돈다** — core/scenery.gd 가 코드로 그린다.
	#   그래서 여기서 세기는 하되, 몇 곳만 있고 몇 곳은 없는 **어중간한 상태**만 잡는다.
	#   그 상태가 제일 나쁘다: 열 탄마다 그림 배경과 코드 배경이 번갈아 나와서 한 판이
	#   두 게임처럼 보인다.
	var th_have := 0
	var th_miss: Array[String] = []
	for t in Roster.THEMES:
		for key in ["art_bg", "art_floor"]:
			if ResourceLoader.exists(String(t.get(key, ""))):
				th_have += 1
			else:
				th_miss.append("%s.%s" % [String(t["id"]), String(key)])
	var th_total: int = Roster.THEMES.size() * 2
	if th_have == th_total:
		print("  테마 그림 %d장 모두 있음 (배경 %d · 바닥 %d)"
				% [th_total, Roster.THEMES.size(), Roster.THEMES.size()])
	elif th_have == 0:
		print("  (테마 그림 없음 — core/scenery.gd 가 코드로 그린다)")
	else:
		_bad("테마 그림이 %d/%d 장뿐이다 — 있는 곳과 없는 곳이 섞이면 한 판이 두 게임처럼 보인다. %s"
				% [th_have, th_total, ", ".join(th_miss.slice(0, 6))])
	if miss.is_empty():
		print("  그림 %d장 모두 있음" % (Roster.UNITS.size() + Roster.MONSTERS.size() + Roster.ART.size()))
	elif strict:
		_bad("그림 %d장이 없다: %s" % [miss.size(), ", ".join(miss.slice(0, 12))])
	else:
		print("  (그림 %d장 아직 없음 — python3 tools/gen_art.py)" % miss.size())


## **`Run.autosave()` 를 부르는 곳이 어디인가.**
##
## ★ 옛 규칙은 「자동 저장은 game/main.gd 한 곳에서만」이었는데, 그 규칙이 **조용히
##   썩었다** — game/shop_screen.gd 가 물건을 판 뒤에 제 손으로 부르고 있었다. 한 줄이
##   늘어난 것은 아무도 못 보는데, 그 순간부터 「어떤 화면은 담고 어떤 화면은 안 담는」
##   상태가 된다. 그런 어긋남은 앱을 껐다 켠 사람만 겪고 로그에는 한 줄도 안 남는다.
## ★ 지금 규칙은 두 곳이다: **단계가 바뀔 때는 game/main.gd**, **되돌릴 수 없는 것을
##   얻거나 쓴 순간은 core/run.gd**(리롤·확정·영웅 옮기기·상점 구매).
##   **화면에서는 절대 부르지 마라** — 화면은 「지금이 담을 때인가」를 알 수가 없다.
## ★ 주석 줄은 건너뛴다. 이 규칙을 **설명하는** 자리(core/save.gd 가 그렇다)까지 걸리면
##   검사가 켜자마자 늘 실패해서, 결국 아무도 안 보게 된다.
func _check_autosave_sites() -> void:
	var needle := "Run.autosave()"
	var allow := {"res://core/run.gd": true, "res://game/main.gd": true}
	var hits := {}
	for dir in ["res://core", "res://game"]:
		for f in _gd_files(dir):
			var fa := FileAccess.open(f, FileAccess.READ)
			if fa == null:
				continue
			for line in fa.get_as_text().split("\n"):
				var t := String(line).strip_edges()
				if t.begins_with("#") or not t.contains(needle):
					continue
				hits[f] = int(hits.get(f, 0)) + 1
	for f2 in hits:
		if allow.has(String(f2)):
			continue
		_bad("%s 가 %s 를 부른다 — 담는 곳은 **단계가 바뀌는 game/main.gd** 와 **되돌릴 수 없는 것을 얻거나 쓴 core/run.gd** 둘뿐이다. 화면이 부르기 시작하면 언젠가 한 화면을 빠뜨리고, 그러면 「그 화면에서만 안 저장되는」 판이 된다"
				% [String(f2), needle])
	if int(hits.get("res://game/main.gd", 0)) < 1:
		_bad("game/main.gd 가 %s 를 한 번도 안 부른다 — 단계가 바뀌어도 판이 안 담긴다" % needle)
	print("  자동 저장을 부르는 곳 %d곳 %s" % [hits.size(), str(hits.keys())])


## **카드 무늬 도트판** — `Look.SUIT_PX` 는 무늬마다 한 장씩, 줄 길이가 같은 문자열 배열이다.
##
## ★ 실제로 나갔던 버그가 여기다: **스페이드 자리에 하트가, 하트 자리에 스페이드가**
##   들어 있어서 화면에 **검은 하트와 빨간 스페이드**가 찍혔다. 색은 무늬 번호로 고르고
##   모양은 이 표에서 고르는데, 두 장만 뒤바뀌면 양쪽 다 "그럴듯한 무늬"로 그려져서
##   눈으로도 한참을 못 본다.
## ★ 그래서 이름이 아니라 **실루엣의 뜻**으로 잰다:
##     스페이드 — 꼭대기가 하나로 뾰족하고(첫 줄 잉크 덩어리 **하나**) 밑에 자루가 붙는다
##                (마지막 줄에 잉크가 **있다**)
##     하트     — 꼭대기가 두 봉우리이고(첫 줄 잉크 덩어리 **둘**) 밑은 한 점에서 끝난다
##                (마지막 줄이 **비어 있다**)
func _check_suits() -> void:
	var swapped := "스페이드 자리에 하트가, 하트 자리에 스페이드가 들어 있으면 이렇게 된다 — 화면에 검은 하트와 빨간 스페이드가 찍힌다"
	for s in [Poker.Suit.SPADE, Poker.Suit.HEART, Poker.Suit.DIAMOND, Poker.Suit.CLUB]:
		if not Look.SUIT_PX.has(s):
			# ★ 없는 무늬는 draw_suit_px 가 **스페이드로 대신 그린다.** 빠진 것이
			#   화면에서는 "스페이드가 넷"으로 보여서 영영 안 잡힌다.
			_bad("무늬 도트판에 %d번 무늬가 없다 — 없는 무늬는 스페이드로 그려진다" % int(s))
			continue
		var rows: Array = Look.SUIT_PX[s]
		if rows.is_empty():
			_bad("%d번 무늬의 도트판이 비었다" % int(s))
			continue
		var w: int = String(rows[0]).length()
		for r in range(rows.size()):
			var ln := String(rows[r])
			if ln.length() != w:
				_bad("%d번 무늬 도트판의 %d번째 줄이 %d칸이다 (%d칸이어야 한다) — 줄 길이가 다르면 무늬가 기울어 찍힌다"
						% [int(s), r, ln.length(), w])
	if not (Look.SUIT_PX.has(Poker.Suit.SPADE) and Look.SUIT_PX.has(Poker.Suit.HEART)):
		return
	var sp: Array = Look.SUIT_PX[Poker.Suit.SPADE]
	var he: Array = Look.SUIT_PX[Poker.Suit.HEART]
	if _ink_runs(String(sp[sp.size() - 1])) < 1:
		_bad("스페이드 도트판의 마지막 줄이 비었다 (자루가 없다). %s" % swapped)
	if _ink_runs(String(he[he.size() - 1])) != 0:
		_bad("하트 도트판의 마지막 줄에 잉크가 있다 (하트는 한 점에서 끝난다). %s" % swapped)
	if _ink_runs(String(sp[0])) != 1:
		_bad("스페이드 도트판의 첫 줄에 잉크 덩어리가 %d개다 (꼭대기 하나여야 한다). %s"
				% [_ink_runs(String(sp[0])), swapped])
	if _ink_runs(String(he[0])) != 2:
		_bad("하트 도트판의 첫 줄에 잉크 덩어리가 %d개다 (두 봉우리여야 한다). %s"
				% [_ink_runs(String(he[0])), swapped])
	print("  무늬 도트판 %d장 정상 (스페이드=자루 있음 · 하트=두 봉우리)" % Look.SUIT_PX.size())


## 한 줄에 잉크(#) 덩어리가 몇 개인가. 무늬를 **이름 없이** 재는 자다.
func _ink_runs(line: String) -> int:
	var n := 0
	var on := false
	for i in range(line.length()):
		var ink: bool = line[i] == "#"
		if ink and not on:
			n += 1
		on = ink
	return n
