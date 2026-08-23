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

enum { PICK, REVEAL, SWAP }

const CARD_SC := 1.30
const PICK_Y := 214.0
const ROW_GAP := 26.0

var main = null
var ui := Ui.new()
var fx := Fx.new()
## 안뜰이 꽉 찬 채로 새 영웅이 왔을 때 뜨는 편성 판. 상점의 「영웅」 탭과 같은 것이다.
var hv := HeroView.new()

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
	set_process(true)


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
	fx.update(dt)
	hv.update(dt)
	for i in range(_flip.size()):
		if _flip[i] > 0.0:
			_flip[i] = max(0.0, _flip[i] - dt)
	if state == REVEAL:
		rt += dt
		_reveal_beats()
		var wait: float = 3.8 if showy else 2.5
		if rt > wait and not _leaving:
			_after_reveal()
	queue_redraw()


func _input(e: InputEvent) -> void:
	if _leaving:
		return
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	if state == REVEAL:
		# 연출은 언제든 넘길 수 있어야 한다. 40탄을 도는 게임에서 못 넘기는 연출은 고문이다.
		if rt > 0.7:
			_after_reveal()
		return
	var id := ui.hit(e.position)
	if id == "":
		return
	if state == SWAP:
		# ★ 편성 판은 **넘길 수 없다.** 자리를 안 바꾸겠다면 「이대로 전투로」를 누른다 —
		#   아무 데나 눌러서 넘어가게 두면 새로 온 영웅이 조용히 대기석에 남는다.
		if id == "tobattle":
			_leave()
		else:
			hv.tap(id)
		return
	if id == "go":
		_confirm()
	elif id.begins_with("re"):
		var i := int(id.substr(2))
		if Run.reroll(i):
			var r := card_rect(i)
			fx.burst(r.position + r.size * 0.5, Look.GOLD, 14, 240.0)
			_flip[i] = FLIP_SEC


func _confirm() -> void:
	result = Run.confirm_hand()
	showy = bool(result["showy"])
	state = REVEAL
	rt = 0.0
	_fired.clear()


## 연출이 끝났다. 새 영웅이 **자리가 없어 대기석으로 갔으면** 편성 판을 띄운다.
## 겹쳤거나 그냥 안뜰에 섰으면 곧장 전투로 간다 — 고를 것이 없는데 판을 띄우면 성가시다.
func _after_reveal() -> void:
	if state != REVEAL or _leaving:
		return
	if String(result.get("where", "field")) == "bench" and not bool(result.get("stacked", false)):
		state = SWAP
		hv.sel = -1
		hv.new_id = String(result.get("unit", {}).get("id", ""))
		return
	_leave()


func _leave() -> void:
	if main == null or _leaving or state == PICK:
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
	var tier: int = int(result.get("hand", 0))
	var col := Look.tier_color(tier)
	var mid := Vector2(640.0, 386.0)

	if _once("name", 0.55):
		if showy:
			# ★ 화려함의 정체: 섬광 + 빛살 + 고리 + 카드가 깨져 흩어짐 + 화면 흔들림.
			#   등급이 높을수록 전부 세진다.
			var pow_lv: float = float(tier - Poker.SHOWY)      # 0(풀하우스) ~ 3(로열)
			fx.do_flash(Color(1, 1, 1, 0.85), 0.42 + pow_lv * 0.06)
			fx.do_shake(11.0 + pow_lv * 4.0)
			fx.rays(mid, col, 16 + int(pow_lv) * 6, 700.0, 1.3 + pow_lv * 0.25)
			for k in range(3 + int(pow_lv)):
				fx.ring(mid, col, 40.0, 420.0 + float(k) * 130.0, 0.75 + float(k) * 0.12, 9.0)
			for i in range(5):
				fx.shards(reveal_rect(i), Look.CARD_BG, 14)
			fx.burst(mid, Look.GOLD, 90 + int(pow_lv) * 40, 520.0, 1.2, 5.0, 320.0)
			fx.burst(mid, col, 60 + int(pow_lv) * 30, 380.0, 1.0, 4.0, 180.0)
		else:
			fx.ring(mid, col, 30.0, 260.0, 0.5, 5.0)
			fx.burst(mid, col, 24, 260.0)

	if showy and _once("name2", 0.95):
		fx.rays(mid, Look.GOLD, 12, 560.0, 1.1)

	# 로열은 한 번 더. 게임 전체에서 가장 드문 순간이라 아낌없이 준다.
	if tier >= Poker.Hand.STRAIGHT_FLUSH and _once("crown", 1.05):
		fx.do_flash(col, 0.5)
		fx.do_shake(18.0)
		for k in range(6):
			fx.ring(mid, Color.WHITE if k % 2 == 0 else col, 20.0, 300.0 + float(k) * 110.0,
					0.9, 7.0)

	if _once("hero", 1.25):
		var by := 660.0
		fx.ring(Vector2(640.0, by - 10.0), col, 20.0, 190.0, 0.6, 6.0)
		fx.burst(Vector2(640.0, by - 40.0), col, 30, 300.0, 0.7, 4.0)
		if showy:
			fx.do_shake(6.0)


# --------------------------------------------------------------------------- #
# 그리기
# --------------------------------------------------------------------------- #
func _draw() -> void:
	ui.begin()
	_sh = fx.shake_offset()
	draw_set_transform(_sh, 0.0, Vector2.ONE)
	_draw_bg()
	# ★ 화려한 등급에서는 초록 천을 한 번 어둡게 덮고 빛살을 깐다.
	#   안 덮으면 빛살(반투명)이 초록에 물들어 풀하우스의 분홍도, 로열의 금빛도
	#   전부 올리브색으로 보인다. 등급 색이 안 읽히면 화려할 이유가 없다.
	if state == REVEAL and showy:
		var dim: float = clampf((rt - 0.45) / 0.25, 0.0, 1.0) * 0.62
		draw_rect(Rect2(-40, -40, 1360, 880), Color(0, 0, 0, dim))
	fx.draw_back(self)      # 빛살·고리는 글자 **뒤에** 깔린다
	match state:
		PICK:
			_draw_pick()
		SWAP:
			_draw_swap()
		_:
			_draw_reveal()
	fx.draw(self)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	fx.draw_flash(self, Rect2(0, 0, 1280, 800))


func _draw_bg() -> void:
	draw_rect(Rect2(-40, -40, 1360, 880), Look.BG)
	# 카드 테이블. 초록 천 위에 카드가 놓인 것처럼 보이면 포커 판이라는 게 바로 읽힌다.
	Look.fill_round(self, Rect2(70, 92, 1140, 600), 46.0, Look.FELT_EDGE)
	Look.fill_round(self, Rect2(82, 104, 1116, 576), 40.0, Look.FELT)
	_draw_topbar()


func _draw_topbar() -> void:
	draw_rect(Rect2(0, 0, 1280, 68), Look.PANEL)
	draw_rect(Rect2(0, 66, 1280, 2), Look.PANEL_EDGE)
	Look.text_left(self, Vector2(28, 34), "%d탄" % Run.wave, 34, Look.INK)
	# 목숨은 곧 크리스탈이다. 화면마다 다른 그림을 쓰면 같은 값인 줄 모른다.
	Look.draw_crystal(self, Vector2(224, 34), 11.0, true)
	Look.text_left(self, Vector2(244, 34), "%d / %d" % [Run.lives, Run.max_lives()], 28, Look.INK)
	var gx := 420.0
	if not Art.draw_at(self, Roster.ART.get("coin", ""), gx, 47.0):
		draw_circle(Vector2(gx, 34), 12.0, Look.GOLD)
	Look.text_left(self, Vector2(gx + 22, 34), "%d G" % Run.gold, 28, Look.GOLD)
	Look.text_right(self, Vector2(1252, 34), "안뜰 %d / %d  ·  대기 %d명"
			% [Run.heroes.size(), Balance.HERO_SLOTS, Run.bench.size()], 24, Look.INK_DIM)


func _draw_pick() -> void:
	Look.text_center(self, Vector2(640, 150),
			"카드 다섯 장 — 맘에 안 드는 것을 다시 뽑아라", 30, Look.INK)

	# ★ 지금 족보를 이루고 있는 카드에 금테를 둘러 준다.
	#   무엇을 남기고 무엇을 바꿔야 하는지가 한눈에 보여야, 리롤이 도박이 아니라 선택이 된다.
	var now := Poker.evaluate(Run.cards)
	var keys := Poker.key_cards(Run.cards, now)
	for i in range(Run.cards.size()):
		var r := card_rect(i)
		var bob := sin(t * 2.2 + float(i) * 0.9) * 3.0
		var at := r.position + Vector2(0, bob)
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
			Look.draw_card(self, at, Run.cards[i], CARD_SC, keys.has(Run.cards[i]))
		ui.zone(Rect2(at, r.size), "re%d" % i, Run.can_reroll(i))

		# 리롤 버튼 — 값이 얼마인지 **카드 밑에 항상** 보이게 한다.
		var cost := Run.reroll_cost_of(i)
		var left := Run.free_rerolls() - Run.rerolled[i]
		var label := ""
		var col := Look.GREEN
		if left > 0:
			label = "다시 (공짜 %d)" % left
		else:
			label = "다시 %dG" % cost
			col = Look.GOLD if Run.gold >= cost else Look.RED
		var br := Rect2(r.position.x, r.position.y + r.size.y + 16.0, r.size.x, 52.0)
		ui.button(self, br, label, "re%d" % i, Run.can_reroll(i), col, 22)
		if Run.rerolled[i] > 0:
			Look.text_center(self, Vector2(r.position.x + r.size.x * 0.5,
					br.position.y + 74.0), "%d번 바꿈" % Run.rerolled[i], 18, Look.INK_DIM)

	# 지금 족보
	var h := now
	var hc := Look.tier_color(h)
	var name_: String = Poker.HAND_KO.get(h, "?")
	Look.text_center(self, Vector2(640, 620), "지금은  %s" % name_, 44, hc)
	if h >= Poker.SHOWY:
		Look.text_center(self, Vector2(640, 664), "★ 대단하다 ★", 24, Look.GOLD)
	elif Run.has("joker"):
		Look.text_center(self, Vector2(640, 664), "조커가 한 장을 바꿔 줄 것이다", 22, Look.INK_DIM)

	ui.button(self, Rect2(490, 700, 300, 76), "결정!", "go", true, Look.GOLD, 34)


func _draw_reveal() -> void:
	var tier: int = int(result.get("hand", 0))
	var col := Look.tier_color(tier)
	var cards: Array = result.get("cards", [])
	var key: Array = result.get("key", [])

	# 1) 카드가 가운데 위로 모인다
	var k := clampf(rt / 0.5, 0.0, 1.0)
	var ease_k := 1.0 - pow(1.0 - k, 3.0)
	for i in range(cards.size()):
		var a := card_rect(i)
		var b := reveal_rect(i)
		var pos := a.position.lerp(b.position, ease_k)
		var sc := lerpf(CARD_SC, 1.0, ease_k)
		var is_key: bool = key.has(cards[i])
		# 화려한 등급에서는 카드가 깨져 사라진다 (조각은 fx 가 그린다)
		if showy and rt > 0.58:
			continue
		Look.draw_card(self, pos, int(cards[i]), sc, is_key and rt > 0.35,
				(not is_key) and rt > 0.35)

	if rt < 0.55:
		return

	# 2) 족보 이름 — 화려한 연출 위에서도 읽히게 어두운 판을 깔고 테두리를 두른다
	var pop := clampf((rt - 0.55) / 0.30, 0.0, 1.0)
	var size := int(lerpf(150.0, 92.0, pop)) if showy else int(lerpf(96.0, 64.0, pop))
	var nm: String = Poker.HAND_KO[tier]
	if showy:
		var tw := Look.text_width(nm, size)
		Look.fill_round(self, Rect2(640.0 - tw * 0.5 - 40.0, 386.0 - float(size) * 0.62,
				tw + 80.0, float(size) * 1.24), float(size) * 0.5, Color(0, 0, 0, 0.55))
	Look.text_center_out(self, Vector2(640, 386), nm, size, col, Look.BG_DEEP, 4.0)
	if bool(result.get("bumped", false)):
		Look.text_center(self, Vector2(640, 452), "도박꾼의 눈 — 한 단계 올랐다!", 26, Look.GOLD)
	elif int(result.get("joker", -1)) >= 0:
		Look.text_center(self, Vector2(640, 452), "조커가 %s 로 바꿨다"
				% Poker.card_text(int(cards[int(result["joker"])])), 26, Look.GOLD)

	if rt < 1.25:
		return

	# 3) 영웅 등장
	var u: Dictionary = result.get("unit", {})
	var hk := clampf((rt - 1.25) / 0.32, 0.0, 1.0)
	var over := 1.0 + sin(hk * PI) * 0.22          # 뿅 하고 커졌다 제자리로
	# ★ 690 에 두면 그 아래의 설명 두 줄이 800 을 넘어가 잘린다. 실제로 잘렸다.
	var by := 654.0
	# 이 순간의 주인공이다. 1.0 배로 그리면 96~141px 라 화면에서 너무 작다.
	Art.draw_unit(self, u, 640.0, by, over * 1.3, Color(1, 1, 1, hk))
	Look.text_center_out(self, Vector2(640, by + 34.0), String(u.get("ko", "")), 40, col)
	# ★ 겹쳤는가 · 자리가 없어 대기석으로 갔는가 — 이 한 줄이 없으면 플레이어는
	#   "영웅이 왔는데 안뜰에 안 보인다"만 겪는다.
	var stacked: bool = bool(result.get("stacked", false))
	var where := String(result.get("where", "field"))
	if stacked:
		Look.text_center_out(self, Vector2(640, by + 74.0),
				"겹쳤다!  %d겹 — 공격력 %d배" % [int(result.get("n", 2)), int(result.get("n", 2))],
				26, Look.GOLD, Look.BG_DEEP, 2.0)
	elif where == "bench":
		Look.text_center_out(self, Vector2(640, by + 74.0),
				"안뜰이 꽉 찼다 — 누구와 바꿀지 고른다", 26, Look.CRYSTAL, Look.BG_DEEP, 2.0)
	else:
		Look.text_center_out(self, Vector2(640, by + 74.0), String(u.get("desc", "")), 24,
				Look.INK_DIM, Look.BG_DEEP, 2.0)
	# ★ 이 줄을 화면 맨 위(y=108)에 뒀더니 카드 다섯 장에 가려 안 보였다. 영웅 밑으로.
	var prof: Dictionary = Balance.PROFILE[String(u.get("profile", "balance"))]
	var bul: Dictionary = Balance.BULLET[String(u.get("bullet", "shot"))]
	Look.text_center(self, Vector2(640, by + 110.0),
			"%s · %s" % [prof["ko"], bul["ko"]], 24, Look.GOLD)


## 안뜰이 꽉 찼는데 새 영웅이 왔다. 누구를 물리고 누구를 세울지 여기서 고른다.
func _draw_swap() -> void:
	draw_rect(Rect2(-40, -40, 1360, 880), Color(0, 0, 0, 0.55))
	var u: Dictionary = result.get("unit", {})
	var tier: int = int(result.get("hand", 0))
	var col := Look.tier_color(tier)
	Look.text_center(self, Vector2(640, 118), "새 영웅 · %s" % String(u.get("ko", "")), 40, col)
	Look.text_center(self, Vector2(640, 158),
			"안뜰은 %d자리뿐이다. 바꿔 세울 사람을 고르거나, 이대로 두고 전투로 간다."
			% Balance.HERO_SLOTS, 22, Look.INK_DIM)

	hv.draw(self, ui, Rect2(60, 190, 1160, 480))
	ui.button(self, Rect2(490, 706, 300, 66), "이대로 전투로", "tobattle", true, Look.GOLD, 28)
