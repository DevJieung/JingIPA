extends Node2D
class_name DrawScreen

## 카드 다섯 장을 받고, 맘에 안 드는 것을 다시 뽑고, 족보를 확정하는 화면.
##
## 규칙(사용자가 정한 것):
##  - 각 탄 시작 전에 트럼프 카드 5장을 받는다.
##  - 맘에 안 드는 카드는 **한 번** 리롤할 수 있다.
##  - 이미 리롤한 카드는 **추가 골드를 내지 않으면 더 리롤하지 못한다.** 값은 두 배씩 오른다.
##  - 확정하면 족보 등급에 맞는 캐릭터가 그 등급 안에서 **무작위로** 나온다.
##  - 풀하우스 이상이면 연출이 화려해진다.

enum { PICK, REVEAL, SWAP, REVIVE_REWARD }

const CARD_SC := 1.30
const PICK_Y := 290.0
const ROW_GAP := 26.0

var main = null
var ui := Ui.new()
var fx := Fx.new()
## 확정 연출이 끝나면 **탄마다** 뜨는 편성 판. 상점의 「영웅」 탭과 같은 것이다.
var hv := HeroView.new()
var formation := FormationView.new()
var fusion := FusionView.new()
var card_choice := CardChoiceView.new()
var revive_reward := ReviveRewardView.new()
var formation_tab := true

var state: int = PICK
var t: float = 0.0
var rt: float = 0.0              ## 확정 뒤 흐른 시간
var result: Dictionary = {}
var showy: bool = false
var _fired: Dictionary = {}      ## 연출 중 한 번만 터뜨릴 것들
## 카드가 뒤집히는 중이면 남은 시간. 리롤을 누른 순간 채워진다.
var _flip: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
const FLIP_SEC := 0.30
## ★ 전투로 넘어가는 중인가. 페이드가 도는 0.28초 동안에도 이 화면은 트리에 남아
##   _input 을 받는다. 예전에는 state 를 PICK 으로 되돌려 막았는데, 그러면 뽑기 화면이
##   다시 그려져서 「결정!」을 한 번 더 누를 수 있었고 **영웅이 공짜로 하나 더 생겼다.**
var _leaving: bool = false

## 이번 프레임의 흔들림 오프셋. battle_screen 의 _sh 와 같은 이유다 —
## draw_set_transform 을 되돌릴 때 Vector2.ZERO 로 되돌리면 흔들림이 날아간다.
var _sh: Vector2 = Vector2.ZERO

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	Ads.completed.connect(_ad_completed)
	set_process(true)
	# ★ 이미 확정한 탄을 이어 하는 경우 — 연출은 건너뛰고 **편성 판부터** 연다.
	#   영웅은 이미 받았으므로 뽑기 화면을 다시 띄우면 「결정!」을 한 번 더 누르게 되고,
	#   그것이 곧 영웅 복제다. 그렇다고 전투로 바로 보내면 그 탄만 편성 판이 없어진다
	#   (CLAUDE.md 2-1: 편성 판은 **탄마다** 뜬다).
	if Run.phase == Run.Phase.SWAP and not Run.last_result.is_empty():
		result = Run.last_result
		showy = bool(result.get("showy", false))
		state = SWAP
		hv.new_id = String((result.get("unit", {}) as Dictionary).get("id", ""))
		_focus_latest()
		if bool(result.get("reward_pending", false)):
			state = REVIVE_REWARD
			revive_reward.begin(result)


func _exit_tree() -> void:
	if Ads.completed.is_connected(_ad_completed):
		Ads.completed.disconnect(_ad_completed)
	card_choice.close()


func _ad_completed(kind: String, rewarded: bool) -> void:
	if kind != "card" or _leaving or state != PICK or not is_inside_tree() \
			or (main != null and main.screen != self):
		return
	var changed := card_choice.completed(rewarded)
	if changed >= 0:
		var r := card_rect(changed)
		fx.burst(r.get_center(), Look.GOLD, 14, 240.0)
		_flip[changed] = FLIP_SEC
		Sfx.play("flip")
	queue_redraw()


func card_rect(i: int) -> Rect2:
	var w := Look.CARD_W * CARD_SC
	var h := Look.CARD_H * CARD_SC
	var total := w * 5.0 + ROW_GAP * 4.0
	var x0 := (1280.0 - total) * 0.5
	return Rect2(x0 + float(i) * (w + ROW_GAP), PICK_Y, w, h)


## 연출 중 카드가 가는 자리(가운데 위로 모인다).
func reveal_rect(i: int) -> Rect2:
	var w := Look.CARD_W
	var h := Look.CARD_H
	var total := w * 5.0 + 12.0 * 4.0
	var x0 := (1280.0 - total) * 0.5
	return Rect2(x0 + float(i) * (w + 12.0), 112.0, w, h)


func _process(dt: float) -> void:
	t += dt
	card_choice.update()
	fusion.update(dt)
	fx.update(dt)
	hv.update(dt)
	for i in range(_flip.size()):
		if _flip[i] > 0.0:
			_flip[i] = max(0.0, _flip[i] - dt)
	if state == REVIVE_REWARD:
		revive_reward.update(dt)
	if state == REVEAL:
		rt += dt
		_reveal_beats()
	queue_redraw()


## ★ 편성 판은 **끌어서 굴린다.** 그래서 누르는 순간에 바로 처리하면 안 된다 —
##   목록을 굴리려고 손을 댄 자리의 영웅이 골라져 버린다. 눌렀다(press) · 움직였다
##   (motion) · 뗐다(release) 를 판에 그대로 넘기고, 판이 "굴린 것인지 고른 것인지"를
##   정한다(HeroView.release).
func _input(e: InputEvent) -> void:
	if Ads.busy or _leaving:
		return
	if state == REVIVE_REWARD:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT \
				and ui.hit(e.position) == "revive:confirm" and revive_reward.ready():
			if Run.acknowledge_revive_reward():
				state = SWAP
				_focus_latest()
				Sfx.play("button")
		return
	if card_choice.input(e, ui):
		get_viewport().set_input_as_handled()
		return
	if hv.info >= 0:
		hv.input(e, ui)
		if hv.info < 0 and hv.sel >= 0:
			formation_tab = false
		return
	if fusion.input(e, ui):
		return
	if state == SWAP:
		_swap_input(e)
		return
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	if state == REVEAL:
		# 연출은 언제든 넘길 수 있어야 한다. 100탄을 도는 게임에서 못 넘기는 연출은 고문이다.
		if rt > 0.7:
			_after_reveal()
		return
	var id := ui.hit(e.position)
	if id == "":
		return
	if id == "go":
		Sfx.play("button")
		_confirm()
	elif id.begins_with("want:") and state == PICK:
		card_choice.open(int(id.get_slice(":", 1)))
	elif id.begins_with("re"):
		var i := int(id.substr(2))
		if Run.reroll(i):
			var r := card_rect(i)
			fx.burst(r.position + r.size * 0.5, Look.GOLD, 14, 240.0)
			_flip[i] = FLIP_SEC
			Sfx.play("flip")


func _swap_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var id := ui.hit(e.position)
		if id == "formation:fusion":
			fusion.opened = true
			return
		if id == "formation:map" or id == "formation:roster":
			formation_tab = id == "formation:map"
			if not formation_tab:
				_focus_info_latest()
			return
	if formation_tab:
		if formation.input(e, ui):
			return
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and ui.hit(e.position) == "tobattle":
			_leave()
		return

	if e is InputEventMouseMotion:
		hv.motion(e.position)
		return
	if not (e is InputEventMouseButton):
		return
	var mb := e as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		hv.wheel(-1.0)
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		hv.wheel(1.0)
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		if hv.press(mb.position):
			return
		# 편성 판 밖(전투 시작 단추 · 팝업 단추)은 누르는 순간 그대로 처리한다.
		var id := ui.hit(mb.position)
		if id == "":
			return
		# ★ 편성 판은 **넘길 수 없다.** 자리를 안 바꾸겠다면 「전투 시작」을 누른다 —
		#   아무 데나 눌러서 넘어가게 두면 새로 온 영웅이 조용히 전당에 남는다.
		if id == "tobattle":
			Sfx.play("button")
			_leave()
		else:
			Sfx.play("button", -14.0)
			hv.tap(id)
	else:
		hv.release(mb.position, ui)


func _confirm() -> void:
	if card_choice.opened or Ads.busy or _leaving:
		return
	# ★ 이미 확정한 탄이면 편성 판으로 보낸다. 그냥 돌아가면 「결정!」이 죽은 단추가 되고
	#   _leave() 가 state == PICK 을 거절하므로(아래) 그 판에서 나갈 길이 없어진다.
	if Run.phase == Run.Phase.SWAP:
		result = Run.last_result
		showy = bool(result.get("showy", false))
		state = SWAP
		hv.new_id = String((result.get("unit", {}) as Dictionary).get("id", ""))
		_focus_latest()
		return
	result = Run.confirm_hand()
	showy = bool(result["showy"])
	state = REVEAL
	rt = 0.0
	_fired.clear()
	# 족보마다 다른 소리. 등급이 높을수록 화음이 길고 아래에 북이 깔린다.
	Sfx.play("card_collect")


## 연출이 끝났다. **탄마다 빠짐없이** 편성 판을 띄운다.
##
## ★ 예전에는 "전장이 꽉 찬 채로 새 영웅이 왔을 때"만 띄웠다. 그러면 앞 여섯 탄은 판을
##   한 번도 못 보고, 그 뒤로도 겹치는 탄에는 안 떠서 **언제 자리를 짤 수 있는지**를
##   플레이어가 배울 데가 없었다. 다음 탄의 몬스터 속성을 보고 여섯을 다시 짜는 것이
##   이 게임의 절반인데, 그 절반이 우연히 뜨는 창 뒤에 숨어 있었던 셈이다.
## ★ 고를 것이 없는 탄에는 「전투 시작」 한 번이면 끝난다 — 성가심은 한 번의 탭이고,
##   얻는 것은 "여기서 짤 수 있다"는 규칙이 매 탄 같은 자리에 있다는 것이다.
func _after_reveal() -> void:
	if state != REVEAL or _leaving:
		return
	state = SWAP
	hv.new_id = String(result.get("unit", {}).get("id", ""))
	fx.clear()
	_focus_latest()


func _focus_latest() -> void:
	formation.focus_latest()
	_focus_info_latest()


func _focus_info_latest() -> void:
	# 정보 탭은 터치하면 설명을 여는 동작을 유지하고, 새 카드에 강조 테두리를 준다.
	hv.sel = -1
	hv.new_id = String(Run.last_result.get("unit", {}).get("id", ""))


func _leave() -> void:
	if main == null or _leaving or state != SWAP:
		return
	_leaving = true
	main.go(main.go_battle)


# --------------------------------------------------------------------------- #
# 확정 연출 — 풀하우스 이상이면 여기가 화려해진다
# --------------------------------------------------------------------------- #
func _once(key: String, at: float) -> bool:
	if rt >= at and not _fired.has(key):
		_fired[key] = true
		return true
	return false


func _reveal_beats() -> void:
	var tier := int(result.get("hand", 0))
	var col := Look.tier_color(tier)
	var center := Vector2(444, 412)
	if _once("charge", 0.7):
		Sfx.play("summon_charge")
		fx.ring(Vector2(602, 246), Look.CRYSTAL, 90, 12, 0.62, 3)
	if _once("burst", 1.65):
		Sfx.play("summon_burst")
		Sfx.force("reveal%d" % tier)
		fx.do_flash(Color(1, 0.96, 0.8, 0.56 if showy else 0.34), 0.28)
		fx.do_shake(6 + tier * 0.9)
		fx.rays(center, col, 14 + tier * 2, 380 + tier * 25, 0.85)
		for i in range(3):
			fx.ring(center, Look.GOLD if i == 1 else col, 18, 170 + i * 65, 0.7 + i * 0.1, 5)
		fx.shards(Rect2(center - Vector2(42, 58), Vector2(84, 116)), Look.CARD_BG, 32)
		fx.burst(center, col.lightened(0.3), 32 + tier * 15, 360, 0.9, 4, 140)


# --------------------------------------------------------------------------- #
# 그리기
# --------------------------------------------------------------------------- #
func _draw() -> void:
	ui.begin()
	if state == REVIVE_REWARD:
		Look.camp_backdrop(self)
		revive_reward.draw(self, ui)
		_draw_topbar()
		return
	_sh = fx.shake_offset()
	draw_set_transform(_sh, 0.0, Vector2.ONE)
	_draw_bg()
	# ★ 화려한 등급에서는 초록 천을 한 번 어둡게 덮고 빛살을 깐다.
	#   안 덮으면 빛살(반투명)이 초록에 물들어 풀하우스의 분홍도, 로열의 금빛도
	#   전부 올리브색으로 보인다. 등급 색이 안 읽히면 화려할 이유가 없다.
	if state == REVEAL:
		var dim: float = clampf((rt - 0.45) / 0.25, 0.0, 1.0) * 0.62
		draw_rect(Rect2(-40, -40, 1360, 880), Color(0, 0, 0, dim))
	if state == REVEAL and rt >= 1.65:
		var element := String((result.get("unit", {}) as Dictionary).get("elem", "none"))
		Look.material_panel(self, Rect2(180, 235, 920, 424), Look.hero_card_face(element), Look.hero_card_edge(element))
	fx.draw_back(self)      # 빛살·고리는 글자 **뒤에** 깔린다
	fx.draw(self)
	fx.draw_flash(self, Rect2(-40, -40, 1360, 880))
	match state:
		PICK:
			_draw_pick()
		SWAP:
			_draw_swap()
		_:
			_draw_reveal()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	fusion.draw(self, ui)
	hv.draw_info(self, ui)
	card_choice.draw(self, ui)


## 카드 테이블 — **도트로 그린다.**
##
## ★ 사용자가 정한 것: 「포커하는 화면도 2D 픽셀로 하고 디자인적으로 이질감이 안
##   느껴지게」. 예전에는 반지름 46짜리 둥근 모서리에 매끈한 초록 천이었는데, 같은
##   화면 아래에 96px 도트 캐릭터가 서 있어서 위아래가 다른 게임처럼 보였다.
##   지금은 (1) 모서리를 한 칸씩 깎고 (2) 천에 **디더 격자**를 깔고 (3) 테두리를
##   나무 널빤지 두 겹으로 두른다. 카드도 같은 격자로 그린다(Look.draw_card).
func _draw_bg() -> void:
	Look.camp_backdrop(self)
	var g := Look.PX
	if state == SWAP:
		_draw_topbar()
		return
	var table := Rect2(72, 92, 1136, 600)
	# 널빤지 테두리 두 겹 — 바깥이 어둡고 안쪽이 밝다.
	Look.px_panel(self, table, Look.FELT_EDGE, Color("#2a1a12"), 0.0)
	Look.px_panel(self, table.grow(-g * 3.0), Look.FELT, Color("#4a3220"), 0.12)
	# 천의 결 — 두 칸마다 한 점씩 밝게. 매끈한 초록은 도트 화면에서 저 혼자 매끈하다.
	var felt := table.grow(-g * 5.0)
	var y: float = Look.snap(felt.position.y, g)
	var row := 0
	while y < felt.position.y + felt.size.y:
		var x: float = Look.snap(felt.position.x + (0.0 if row % 2 == 0 else g * 4.0), g)
		while x < felt.position.x + felt.size.x - g:
			draw_rect(Rect2(x, y, g, g), Color(1, 1, 1, 0.028))
			x += g * 8.0
		y += g * 4.0
		row += 1
	# 가운데 자리 표시 — 카드 다섯 장이 놓이는 자리를 옅게 파 둔다.
	for i in range(5 if state == PICK else 0):
		var cr := card_rect(i)
		draw_rect(Look.snap_rect(cr.grow(6.0)), Color(0, 0, 0, 0.16))
	_draw_topbar()


func _draw_topbar() -> void:
	Hud.topbar(self, "%d탄" % Run.wave)


func _draw_pick() -> void:
	var dealing := _flip.any(func(seconds: float) -> bool: return seconds > 0)
	SummonArt.dealer(self, Rect2(498, 78, 216, 204), t, "" if dealing else "카드를 골라 운명을 완성하세요.")

	# ★ 지금 족보를 이루고 있는 카드에 금테를 둘러 준다.
	#   무엇을 남기고 무엇을 바꿔야 하는지가 한눈에 보여야, 리롤이 도박이 아니라 선택이 된다.
	var now := Poker.evaluate(Run.cards)
	var keys := Poker.key_cards(Run.cards, now)
	for i in range(Run.cards.size()):
		var r := card_rect(i)
		var bob := sin(t * 2.2 + float(i) * 0.9) * 3.0
		var matched := keys.has(Run.cards[i])
		var at := r.position + Vector2(0, bob - (9 if matched else 0))
		if matched:
			Look.fill_round(self, Rect2(at - Vector2(7, 7), r.size + Vector2(14, 14)), 7, Color(Look.GOLD, 0.25))
		if _flip[i] > 0.0:
			# 다시 뽑은 카드는 한 번 뒤집힌다. 앞 절반은 뒷면, 뒤 절반은 새 카드.
			# 가로만 눌러서 뒤집히는 것처럼 보이게 한다.
			var fk: float = _flip[i] / FLIP_SEC          # 1 → 0
			var squash: float = abs(fk * 2.0 - 1.0)      # 1 → 0 → 1
			var w := Look.CARD_W * CARD_SC
			draw_set_transform(at + Vector2(w * 0.5, 0.0) + _sh, 0.0,
					Vector2(max(0.06, squash), 1.0))
			if fk > 0.5:
				Look.draw_card_back(self, Vector2(-w * 0.5, 0.0), CARD_SC)
			else:
				Look.draw_card(self, Vector2(-w * 0.5, 0.0), Run.cards[i], CARD_SC)
			draw_set_transform(_sh, 0.0, Vector2.ONE)
		else:
			Look.draw_card(self, at, Run.cards[i], CARD_SC, matched)
			if matched:
				var ribbon := Rect2(at + Vector2(10, r.size.y - 28), Vector2(r.size.x - 62, 24))
				Look.fill_round(self, ribbon, 3, Look.GOLD)
				Look.text_center_fit(self, ribbon.get_center(), "족보 카드", 16, Look.BG_DEEP, ribbon.size.x - 8, 12)
		ui.zone(Rect2(at, r.size), "re%d" % i, Run.can_reroll(i))

		# 조작명은 짧게 유지하고 실제 남은 횟수/가격은 별도 상태 칸에서 읽는다.
		var quota := Rect2(r.position.x, r.end.y + 12, r.size.x, 28)
		var br := _draw_reroll(i, quota)
		ui.reward_button(self, Rect2(br.position.x, br.end.y + 8, br.size.x, 50),
			"원하는 카드", "want:%d" % i, Run.can_choose_card(i) and not Ads.busy, Look.CRYSTAL, 20)

	# The hand summary occupies the empty felt to the dealer's left.
	var hc := Look.tier_color(now)
	var summary := Rect2(117, 129, 355, 124)
	Look.fill_round(self, summary, 5, Color("#172c2c"))
	Look.text_left(self, Vector2(138, 154), "현재 족보", 18, Look.INK_DIM)
	Look.text_center_fit(self, Vector2(summary.get_center().x + 2, 195), Poker.HAND_KO.get(now, "?"), 35, hc.lightened(0.2), 319, 22)
	Look.draw_rarity_fit(self, Rect2(145, 224, 297, 20), now, 5.6)
	if Run.has("joker"):
		Look.text_center(self, Vector2(640, 667), "조커 · 카드 1장 자동 교체", 22, Look.INK_DIM)

	ui.button(self, Rect2(490, 700, 300, 76), "족보 확정", "go", true, Look.GOLD, 34)


func _draw_reroll(slot: int, quota: Rect2) -> Rect2:
	var left := Run.rerolls_left(slot)
	var cost := Run.reroll_cost_of(slot)
	var enabled := Run.can_reroll(slot)
	var accent := Look.GREEN if left > 0 else (Look.GOLD if enabled else Look.RED)
	Look.fill_round(self, quota, 4, Look.BG_DEEP)
	draw_line(quota.position + Vector2(8, quota.size.y - 1),
		Vector2(quota.end.x - 8, quota.end.y - 1), Color(accent, 0.6), 1)
	Look.text_left(self, quota.position + Vector2(9, 13),
		"무료 잔여" if left > 0 else "교체 비용", 16, Look.INK_DIM)
	var value := str(left) if left > 0 else "%d G" % cost
	var value_size := 21
	while value_size > 12 and Look.text_width(value, value_size) > quota.size.x - 82:
		value_size -= 1
	Look.text_right(self, Vector2(quota.end.x - 9, quota.position.y + 13), value, value_size, accent)
	var action := Rect2(quota.position.x, quota.end.y + 5, quota.size.x, 48)
	ui.button(self, action, "교체", "re%d" % slot, enabled, accent, 23)
	return action


func _draw_reveal() -> void:
	var tier := int(result.get("hand", 0))
	var col := Look.tier_color(tier)
	var cards: Array = result.get("cards", [])
	if rt < 1.65:
		var charge := clampf((rt - 0.6) / 0.65, 0, 1)
		SummonArt.dealer(self, Rect2(498, 78, 216, 204), t, "", charge)
		var gather := 1.0 - pow(1.0 - clampf(rt / 0.72, 0, 1), 3)
		var launch := clampf((rt - 1.28) / 0.37, 0, 1)
		var pile := Vector2(602, 244).lerp(Vector2(444, 412), launch * launch)
		SummonArt.seal(self, pile, 28 + charge * 67, rt * 3, Look.CRYSTAL, charge)
		for i in range(cards.size()):
			var sc := lerpf(CARD_SC, 0.52, gather)
			var destination := pile - Vector2(Look.CARD_W, Look.CARD_H) * sc * 0.5 + Vector2(i * 2, -i * 2)
			var pos := card_rect(i).position.lerp(destination, gather)
			draw_set_transform(pos + _sh, sin(rt * 8 + i) * 0.025 * charge, Vector2.ONE)
			Look.draw_card(self, Vector2.ZERO, int(cards[i]), sc, false)
			draw_set_transform(_sh, 0, Vector2.ONE)
		return
	var unit: Dictionary = result.get("unit", {})
	var pop := clampf((rt - 1.65) / 0.3, 0, 1)
	Look.text_center_out(self, Vector2(640, 180), Poker.HAND_KO[tier], 64 if showy else 54, col, Look.BG_DEEP, 3)
	var element := String(unit.get("elem", "none"))
	SummonArt.seal(self, Vector2(417, 433), 142, rt * 0.35, Balance.elem_color(element), 0.40)
	var portrait := Rect2(248, 264 + (1 - pop) * 48, 332, 300)
	Art.draw_unit_fit(self, unit, portrait, Color(1, 1, 1, pop))
	Look.draw_rarity(self, Vector2(414, 603), tier, 13)
	SummonArt.hero_info(self, unit, tier, Rect2(622, 246, 432, 394))
	if String(result.get("where", "field")) == "bench":
		Look.text_center(self, Vector2(640, 690), "영웅 전당에 보관되었습니다", 21, Look.CRYSTAL)
	Look.text_center_out(self, Vector2(640, 748), "터치하여 배치하기", 24, Look.INK)


## 편성 판 — **탄마다** 뜬다. 새로 온 영웅을 어디에 세울지, 이번 탄에 오는 몬스터에
## 맞춰 여섯을 어떻게 짤지를 여기서 고른다.
func _draw_swap() -> void:
	Look.material_panel(self, Rect2(24, 86, 1232, 698), Look.PANEL, Look.GOLD_DEEP)
	_draw_wave_monsters()

	ui.tab(self, Rect2(46, 152, 170, 42), "전장 배치", "formation:map", formation_tab, 21)
	ui.tab(self, Rect2(224, 152, 170, 42), "영웅 정보", "formation:roster", not formation_tab, 21)
	ui.tab(self, Rect2(402, 152, 170, 42), "영웅 합성", "formation:fusion", false, 21)
	if formation_tab:
		formation.draw(self, ui, Rect2(44, 214, 1192, 490), t)
	else:
		hv.draw(self, ui, Rect2(60, 214, 1160, 490), 6, false)
	ui.button(self, Rect2(490, 706, 300, 66), "전투시작", "tobattle", not Run.heroes.is_empty(), Look.GOLD, 28)


## 이번 탄의 몬스터 이름과 해당 몬스터의 속성만 표시한다.
func _draw_wave_monsters() -> void:
	var pool: Array = Run.wave_lineup(Run.wave)
	var head := Hud.wave_head(Run.wave, "Next Stage")
	var x := maxf(60, 640.0 - Hud.lineup_width(head, pool) * 0.5)
	Hud.draw_lineup(self, Vector2(x, 117), head, pool)
