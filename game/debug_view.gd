extends RefCounted
class_name DebugView

## 전투 화면 위에 얹는 디버그 판. **에디터에서 직접 플레이하면서** 숫자가 어떻게
## 흘러가는지 보라고 만든 것이다.
##
##   F3       켜기 / 끄기
##   Tab      탭 넘기기 (흐름 · 영웅 · 몬스터 · 표)
##   1~6      곱셈 사슬을 펼쳐 볼 영웅 고르기
##   스페이스   전투 멈춤 / 재개
##   마침표    멈춘 채로 **한 걸음만** (1/60초)
##
## ★ 그리기만 한다. 담는 것은 game/dbg_sim.gd, 들고 있는 것은 core/dbg.gd 다
##   (CLAUDE.md 11 의 「전투는 그리기를 모른다」와 같은 결이다).
## ★ 여기서 계산을 **다시 적지 않는다.** 곱셈 사슬도 Balance/Run 의 함수를 그대로 부르고,
##   맨 아래에 그 곱이 Run.hero_stats() 와 같은지 적는다 — 어긋나면 화면에 바로 뜬다.
## ★ 자리를 **하나하나 못 박아 둔다.** 글꼴이 고정폭이 아니라서 문자열에 공백을 채워
##   맞추면 반드시 옆 칸을 파고든다(처음에 실제로 「실제 차감」이 「남은 hp」를 덮었다).

const X := 10.0
const Y := 76.0
const W := 700.0
const H := 714.0
const L := X + 16.0            ## 안쪽 왼쪽 끝
const R := X + W - 16.0        ## 안쪽 오른쪽 끝
const ROW := 21.0

const Y_TAB := Y + 24.0        ## 탭 이름 줄
const Y_SUM := Y + 50.0        ## 경로별 누적 줄
const Y_RULE := Y + 64.0       ## 가로줄
const Y_HEAD := Y + 84.0       ## 칸 이름 줄
const Y_BODY := Y + 106.0      ## 첫 줄
const Y_FOOT := Y + H - 16.0

const TABS := ["흐름", "영웅", "몬스터", "표"]


static func draw(ci: CanvasItem, sim, speed: float) -> void:
	if not Dbg.on:
		return
	var r := Rect2(X, Y, W, H)
	Look.fill_round(ci, Rect2(r.position + Vector2(0, 5), r.size), 10.0, Color(0, 0, 0, 0.55))
	# ★ 테두리를 **먼저** 그린다. Look.outline_round 는 안을 비운 테두리가 아니라
	#   `fill_round(rect.grow(w), ...)` — 한 겹 큰 **꽉 찬** 네모다(core/look.gd:237).
	#   뒤에 그리면 반투명하게 잡아 둔 판때기 위에 불투명한 #3a2f4f 를 통째로 덮어서,
	#   투기장이 하나도 안 비친다. hero_view 도 테두리를 먼저 그린다.
	Look.outline_round(ci, r, 10.0, Look.PANEL_EDGE, 2.0)
	Look.fill_round(ci, r, 10.0, Color(Look.BG_DEEP.r, Look.BG_DEEP.g, Look.BG_DEEP.b, 0.94))
	_head(ci, sim, speed)
	match Dbg.tab:
		0: _flow(ci)
		1: _heroes(ci, sim)
		2: _mobs(ci, sim)
		_: _tables(ci, sim)
	_foot(ci)


static func _rule(ci: CanvasItem, y: float) -> void:
	ci.draw_rect(Rect2(L - 6.0, y, R - L + 12.0, 1.0), Look.PANEL_EDGE)


## 몸 색 한 칸. 흐름 탭에서 「무엇을 때리고 있나」를 한눈에 가른다.
## ★ 속성 아이콘(Look.draw_elem)을 쓰면 안 된다 — 나무와 바위에 해당하는 공격 속성이
##   없어서 둘 다 「무」로 찍히고, 그러면 서로 다른 두 몸이 화면에서 같아 보인다.
##   색은 표 한 곳(Balance.MBODY)의 것이다.
static func _body_swatch(ci: CanvasItem, x: float, y: float, body: String) -> void:
	ci.draw_rect(Rect2(x, y - 6.0, 9.0, 12.0), Balance.body_color(body))


## 큰 수를 줄여 적는다. 후반 한 대가 삼십만이라 그대로 찍으면 칸을 넘는다.
static func _num(v: float) -> String:
	if absf(v) >= 100000.0:
		return "%.0fk" % (v / 1000.0)
	if absf(v) >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	if absf(v) >= 100.0:
		return "%.0f" % v
	return "%.1f" % v


## 상성 배수에 맞는 색. 약점은 초록(내게 좋다) · 면역은 빨강(헛방이다).
static func _em_col(em: float) -> Color:
	if em >= 2.0:
		return Look.GREEN
	if em <= 0.0:
		return Look.RED
	if em < 1.0:
		return Look.INK_DIM
	return Look.INK


# --------------------------------------------------------------------------- #
static func _head(ci: CanvasItem, sim, speed: float) -> void:
	var tx := L
	for i in range(TABS.size()):
		var on: bool = i == Dbg.tab
		var lab := String(TABS[i])
		var w: float = Look.text_width(lab, 22) + 22.0
		if on:
			Look.fill_round(ci, Rect2(tx - 8.0, Y_TAB - 15.0, w, 30.0), 6.0, Look.PANEL_EDGE)
		Look.text_left(ci, Vector2(tx, Y_TAB), lab, 22, Look.GOLD if on else Look.INK_DIM)
		tx += w + 6.0
	var st := "%d탄  %.1f초  남은 %d마리  배속 %d배" % [sim.wave, sim.elapsed,
			sim.remaining(), int(speed)]
	if Dbg.paused:
		st = "멈춤 (스페이스)  " + st
	Look.text_right(ci, Vector2(R, Y_TAB), st, 19, Look.RED if Dbg.paused else Look.INK_DIM)

	# 경로별 누적 — 「어느 길로 얼마나 들어갔나」
	var sx := L
	var tot := 0.0
	for k in Dbg.by_ctx:
		tot += float(Dbg.by_ctx[k])
	Look.text_left(ci, Vector2(sx, Y_SUM), "총 %s" % _num(tot), 18, Look.INK)
	sx += Look.text_width("총 %s" % _num(tot), 18) + 20.0
	for k in Dbg.by_ctx:
		var s := "%s %s" % [k, _num(float(Dbg.by_ctx[k]))]
		if sx + Look.text_width(s, 18) > R - 130.0:
			break
		Look.text_left(ci, Vector2(sx, Y_SUM), s, 18, Look.INK_DIM)
		sx += Look.text_width(s, 18) + 16.0
	if Dbg.wasted > 0:
		Look.text_right(ci, Vector2(R, Y_SUM), "헛방 %d번" % Dbg.wasted, 18, Look.RED)
	_rule(ci, Y_RULE)


static func _foot(ci: CanvasItem) -> void:
	_rule(ci, Y_FOOT - 20.0)
	Look.text_left(ci, Vector2(L, Y_FOOT),
			"F3 끄기   Tab 탭   1~6 영웅   스페이스 멈춤   마침표 한 걸음", 18, Look.INK_DIM)


# --------------------------------------------------------------------------- #
# 탭 1 — 흐름. **hp 가 깎인 것을 전부** 새것부터 위로.
# --------------------------------------------------------------------------- #
const F_TIME_R := X + 56.0
const F_PATH := X + 66.0
const F_WHO := X + 114.0
const F_NAME := X + 156.0
const F_BODY := X + 292.0
const F_REQ_R := X + 418.0
const F_EM_R := X + 488.0
const F_GOT_R := X + 560.0

static func _flow(ci: CanvasItem) -> void:
	Look.text_right(ci, Vector2(F_TIME_R, Y_HEAD), "시각", 17, Look.INK_DIM)
	Look.text_left(ci, Vector2(F_PATH, Y_HEAD), "경로", 17, Look.INK_DIM)
	Look.text_left(ci, Vector2(F_WHO, Y_HEAD), "누가", 17, Look.INK_DIM)
	Look.text_left(ci, Vector2(F_NAME, Y_HEAD), "누구를", 17, Look.INK_DIM)
	Look.text_left(ci, Vector2(F_BODY, Y_HEAD), "몸", 17, Look.INK_DIM)
	Look.text_right(ci, Vector2(F_REQ_R, Y_HEAD), "요청", 17, Look.INK_DIM)
	Look.text_right(ci, Vector2(F_EM_R, Y_HEAD), "x상성", 17, Look.INK_DIM)
	Look.text_right(ci, Vector2(F_GOT_R, Y_HEAD), "실제 차감", 17, Look.INK_DIM)
	Look.text_right(ci, Vector2(R, Y_HEAD), "남은 hp", 17, Look.INK_DIM)

	var n: int = int((Y_FOOT - 26.0 - Y_BODY) / ROW)
	var rows := Dbg.recent(n)
	rows.reverse()      # 새것이 위로 — 눈이 한 자리에 머문다
	var y := Y_BODY
	for r in rows:
		var em: float = float(r["em"])
		var col := _em_col(em)
		var body := String(r["body"])
		var who: String = "화상" if int(r["src"]) < 0 else "%d번" % (int(r["src"]) + 1)
		Look.text_right(ci, Vector2(F_TIME_R, y), "%.2f" % float(r["t"]), 17, Look.INK_DIM)
		Look.text_left(ci, Vector2(F_PATH, y), String(r["ctx"]), 17, Look.INK_DIM)
		Look.text_left(ci, Vector2(F_WHO, y), who, 17, Look.INK_DIM)
		Look.text_left(ci, Vector2(F_NAME, y), String(r["name"]), 17, col)
		_body_swatch(ci, F_BODY, y, body)
		Look.text_left(ci, Vector2(F_BODY + 15.0, y), Balance.body_ko(body), 17, Look.INK_DIM)
		Look.text_right(ci, Vector2(F_REQ_R, y), _num(float(r["req"])), 17, Look.INK_DIM)
		Look.text_right(ci, Vector2(F_EM_R, y), "x%.2f" % em, 17, col)
		Look.text_right(ci, Vector2(F_GOT_R, y), _num(float(r["got"])), 17, col)
		# ★ 마지막 한 대는 hp 를 음수로 만든다(넘치는 몫은 버려진다). 그대로 찍으면
		#   「-130 / 82.9」 같은 줄이 나와서 읽는 사람이 계산이 틀린 줄 안다.
		if float(r["hp1"]) <= 0.0:
			Look.text_right(ci, Vector2(R, y), "처치", 17, Look.GOLD)
		else:
			Look.text_right(ci, Vector2(R, y),
					"%s / %s" % [_num(float(r["hp1"])), _num(float(r["max"]))], 17, Look.INK_DIM)
		y += ROW
	if rows.is_empty():
		Look.text_left(ci, Vector2(L, Y_BODY + 10.0),
				"아직 아무도 안 맞았다. 전투가 시작되면 한 대마다 한 줄씩 쌓인다.",
				19, Look.INK_DIM)


# --------------------------------------------------------------------------- #
# 탭 2 — 영웅. 전장 여섯의 실시간 값 + 고른 하나의 곱셈 사슬
# --------------------------------------------------------------------------- #
const H_NO := X + 16.0
const H_NAME := X + 42.0
const H_ELEM := X + 196.0
const H_KIND := X + 292.0
const H_STACK := X + 352.0
const H_ATK_R := X + 452.0
const H_RATE_R := X + 548.0
const H_DMG_R := X + 634.0

static func _heroes(ci: CanvasItem, sim) -> void:
	Look.text_left(ci, Vector2(H_NAME, Y_HEAD), "이름", 17, Look.INK_DIM)
	Look.text_left(ci, Vector2(H_ELEM, Y_HEAD), "속성", 17, Look.INK_DIM)
	Look.text_left(ci, Vector2(H_KIND, Y_HEAD), "방식", 17, Look.INK_DIM)
	Look.text_left(ci, Vector2(H_STACK, Y_HEAD), "겹침", 17, Look.INK_DIM)
	Look.text_right(ci, Vector2(H_ATK_R, Y_HEAD), "한 발", 17, Look.INK_DIM)
	Look.text_right(ci, Vector2(H_RATE_R, Y_HEAD), "초당 발", 17, Look.INK_DIM)
	Look.text_right(ci, Vector2(H_DMG_R, Y_HEAD), "누적 피해", 17, Look.INK_DIM)
	Look.text_right(ci, Vector2(R, Y_HEAD), "처치", 17, Look.INK_DIM)

	var y := Y_BODY
	for i in range(sim.heroes.size()):
		var he: Dictionary = sim.heroes[i]
		var u: Dictionary = he["h"]["unit"]
		var on: bool = i == Dbg.sel
		if on:
			Look.fill_round(ci, Rect2(L - 6.0, y - 13.0, R - L + 12.0, 23.0), 4.0, Look.PANEL)
		Look.text_left(ci, Vector2(H_NO, y), "%d" % (i + 1), 18,
				Look.GOLD if on else Look.INK_DIM)
		Look.text_left(ci, Vector2(H_NAME, y), Look.unit_name(u), 18,
				Look.tier_color(int(he["h"]["tier"])))
		Look.draw_elem(ci, Vector2(H_ELEM + 7.0, y), 7.0, String(he["elem"]))
		Look.text_left(ci, Vector2(H_ELEM + 19.0, y), Balance.elem_ko(String(he["elem"])),
				17, Look.INK_DIM)
		Look.text_left(ci, Vector2(H_KIND, y), String(Balance.BULLET[String(he["kind"])]["ko"]),
				17, Look.INK_DIM)
		Look.text_left(ci, Vector2(H_STACK, y), "x%d" % int(he["h"].get("n", 1)), 17, Look.INK)
		Look.text_right(ci, Vector2(H_ATK_R, y), _num(float(he["atk"])), 17, Look.INK)
		Look.text_right(ci, Vector2(H_RATE_R, y),
				"%.2f x%d" % [float(he["rate"]), int(he["shots"])], 17, Look.INK_DIM)
		Look.text_right(ci, Vector2(H_DMG_R, y), _num(float(he["dmg"])), 17, Look.GREEN)
		Look.text_right(ci, Vector2(R, y), "%d" % int(he["kills"]), 17, Look.INK_DIM)
		y += ROW + 3.0
	_rule(ci, y + 6.0)
	_chain(ci, y + 30.0)


const C_IDX := X + 22.0
const C_LAB := X + 46.0
const C_EXPR := X + 172.0
const C_MUL_R := X + 440.0
const C_ACC_R := X + 520.0
const C_BODY := X + 540.0
## 배수와 피해를 **따로** 오른쪽 맞춤한다. 한 문자열로 붙이면 몸 이름을 파고든다.
const C_BEM_R := X + 630.0

## 고른 영웅 하나의 곱셈 사슬. **Run 과 Balance 의 함수를 그대로 부른다.**
static func _chain(ci: CanvasItem, top: float) -> void:
	if Dbg.sel >= Run.heroes.size():
		Look.text_left(ci, Vector2(L, top), "그 자리에는 영웅이 없다. 1~6 으로 고른다.",
				19, Look.INK_DIM)
		return
	var h: Dictionary = Run.heroes[Dbg.sel]
	var u: Dictionary = h["unit"]
	var t: int = int(h["tier"])
	var n: int = int(h.get("n", 1))
	var el := String(u.get("elem", "none"))
	var pk := String(u.get("profile", "balance"))
	var bk := String(u.get("bullet", "shot"))
	var st: Dictionary = Run.hero_stats(h)
	Look.text_left(ci, Vector2(L, top), "%d번 %s 의 한 발" % [Dbg.sel + 1, Look.unit_name(u)],
			19, Look.GOLD)
	Look.text_left(ci, Vector2(C_BODY, top), "몸마다 실제 차감", 17, Look.GOLD)
	var rows := [
		["등급 기본", "TIER_ATK[%d]" % t, Balance.TIER_ATK[t]],
		["성향", "PROFILE[%s].atk" % pk, float(Balance.PROFILE[pk]["atk"])],
		["탄 방식", "BULLET[%s].dmg" % bk, float(Balance.BULLET[bk]["dmg"])],
		["속성 기본화력", "elem_dmg(%s)" % el, Balance.elem_dmg(el)],
		["공명 패시브", "resonance_mult()", Run.resonance_mult(el)],
		["겹침 한 발 몫", "stack_atk(%d)" % n, Balance.stack_atk(n)],
		["상점 공격력", "atk_mult(lv %d)" % Run.lv("atk"), Balance.atk_mult(Run.lv("atk"))],
		["패시브 공격력", "pas_mult(atk)", Run.pas_mult("atk")],
	]
	var y := top + 26.0
	var acc := 1.0
	for i in range(rows.size()):
		var f: Array = rows[i]
		acc *= float(f[2])
		Look.text_left(ci, Vector2(C_IDX, y), "%d)" % (i + 1), 17, Look.INK_DIM)
		Look.text_left(ci, Vector2(C_LAB, y), String(f[0]), 17, Look.INK_DIM)
		Look.text_left(ci, Vector2(C_EXPR, y), String(f[1]), 17, Look.INK_DIM)
		Look.text_right(ci, Vector2(C_MUL_R, y), "x %.4f" % float(f[2]), 17, Look.INK)
		Look.text_right(ci, Vector2(C_ACC_R, y), _num(acc), 17, Look.INK)
		y += 19.0
	var ok: bool = absf(acc - float(st["atk"])) <= maxf(0.0005, float(st["atk"]) * 1e-5)
	Look.text_left(ci, Vector2(C_LAB, y + 6.0), "합계 = hero_stats().atk", 17, Look.INK_DIM)
	Look.text_right(ci, Vector2(C_ACC_R, y + 6.0), _num(float(st["atk"])), 17,
			Look.GREEN if ok else Look.RED)
	Look.text_left(ci, Vector2(C_LAB, y + 28.0),
			"쏘는 순간 여기에 치명타(%.0f%% 로 x%.2f)가 곱해지고, 맞는 순간 상성이 곱해진다."
			% [float(st["crit"]) * 100.0, float(st["critx"])], 17, Look.INK_DIM)
	# 그 한 발이 다섯 몸에 각각 얼마로 들어가는가
	var cy := top + 26.0
	for body in Balance.MBODY_ORDER:
		var em: float = Balance.elem_mult(el, String(body))
		_body_swatch(ci, C_BODY, cy, String(body))
		Look.text_left(ci, Vector2(C_BODY + 15.0, cy), Balance.body_ko(String(body)),
				17, Look.INK_DIM)
		Look.text_right(ci, Vector2(C_BEM_R, cy), "x%.1f" % em, 17, _em_col(em))
		Look.text_right(ci, Vector2(R, cy), _num(float(st["atk"]) * em), 17, _em_col(em))
		cy += 19.0


# --------------------------------------------------------------------------- #
# 탭 3 — 몬스터. 지금 살아 있는 놈들
# --------------------------------------------------------------------------- #
const M_NAME := X + 16.0
const M_BODY := X + 162.0
const M_BAR := X + 222.0
const M_BAR_W := 130.0
const M_HP_R := X + 428.0
const M_ST := X + 440.0
const M_PR := X + 584.0
const M_PR_W := 100.0

static func _mobs(ci: CanvasItem, sim) -> void:
	Look.text_left(ci, Vector2(M_NAME, Y_HEAD), "몬스터", 17, Look.INK_DIM)
	Look.text_left(ci, Vector2(M_BODY, Y_HEAD), "몸", 17, Look.INK_DIM)
	Look.text_left(ci, Vector2(M_BAR, Y_HEAD), "체력", 17, Look.INK_DIM)
	Look.text_left(ci, Vector2(M_ST, Y_HEAD), "상태이상 (남은 초)", 17, Look.INK_DIM)
	Look.text_right(ci, Vector2(R, Y_HEAD), "길을 온 만큼", 17, Look.INK_DIM)
	var idx: Array = []
	for i in range(sim.monsters.size()):
		idx.append(i)
	idx.sort_custom(func(a, b): return float(sim.monsters[a]["s"]) > float(sim.monsters[b]["s"]))
	var y := Y_BODY
	var lim: int = int((Y_FOOT - 40.0 - Y_BODY) / (ROW + 3.0))
	for k in range(mini(lim, idx.size())):
		var mo: Dictionary = sim.monsters[int(idx[k])]
		var hp: float = float(mo["hp"])
		var mx: float = maxf(1.0, float(mo["max"]))
		var body := String(mo.get("body", ""))
		Look.text_left(ci, Vector2(M_NAME, y), String(mo["m"].get("ko", "?")), 18,
				Look.RED if String(mo["kind"]) == "boss" else Look.INK)
		_body_swatch(ci, M_BODY, y, body)
		Look.text_left(ci, Vector2(M_BODY + 15.0, y), Balance.body_ko(body), 17, Look.INK_DIM)
		Look.fill_round(ci, Rect2(M_BAR, y - 8.0, M_BAR_W, 12.0), 4.0, Look.BG_DEEP)
		Look.fill_round(ci, Rect2(M_BAR, y - 8.0, M_BAR_W * clampf(hp / mx, 0.0, 1.0), 12.0),
				4.0, Look.hp_color(hp / mx))
		Look.text_right(ci, Vector2(M_HP_R, y), "%s / %s" % [_num(hp), _num(mx)],
				16, Look.INK_DIM)
		var sts: Array = []
		if float(mo["slow_t"]) > 0.0:
			sts.append("둔화 %.1f" % float(mo["slow_t"]))
		if float(mo["burn_t"]) > 0.0:
			sts.append("화상 %.1f" % float(mo["burn_t"]))
		if float(mo["stun_t"]) > 0.0:
			sts.append("마비 %.2f" % float(mo["stun_t"]))
		Look.text_left(ci, Vector2(M_ST, y),
				" ".join(PackedStringArray(sts)) if not sts.is_empty() else "-",
				16, Look.BLUE if not sts.is_empty() else Look.PANEL_EDGE)
		var pr: float = sim.progress(mo)
		Look.fill_round(ci, Rect2(M_PR, y - 8.0, M_PR_W, 12.0), 4.0, Look.BG_DEEP)
		if pr > 0.004:
			Look.fill_round(ci, Rect2(M_PR, y - 8.0, M_PR_W * pr, 12.0), 4.0,
					Look.RED if pr > 0.72 else Look.GOLD)
		y += ROW + 3.0
	if idx.is_empty():
		Look.text_left(ci, Vector2(M_NAME, Y_BODY + 10.0), "판 위에 몬스터가 없다.",
				19, Look.INK_DIM)
	elif idx.size() > lim:
		Look.text_left(ci, Vector2(M_NAME, y + 8.0),
				"그리고 %d마리 더" % (idx.size() - lim), 17, Look.INK_DIM)


# --------------------------------------------------------------------------- #
# 탭 4 — 표. 상성 5x5 와 이번 탄 편성
# --------------------------------------------------------------------------- #
static func _tables(ci: CanvasItem, sim) -> void:
	Look.text_left(ci, Vector2(L, Y_HEAD), "상성 — 세로가 공격 속성, 가로가 몬스터의 몸",
			19, Look.GOLD)
	var x0 := X + 150.0
	var step := 106.0
	var y := Y_HEAD + 28.0
	for j in range(Balance.MBODY_ORDER.size()):
		var b0 := String(Balance.MBODY_ORDER[j])
		_body_swatch(ci, x0 + step * float(j) + 14.0, y - 1.0, b0)
		Look.text_left(ci, Vector2(x0 + step * float(j) + 29.0, y), Balance.body_ko(b0),
				18, Look.INK_DIM)
	y += 26.0
	for el in Balance.ELEM_ORDER:
		Look.draw_elem(ci, Vector2(L + 8.0, y), 8.0, String(el))
		Look.text_left(ci, Vector2(L + 24.0, y), Balance.elem_ko(String(el)), 18, Look.INK)
		for j in range(Balance.MBODY_ORDER.size()):
			var m: float = Balance.elem_mult(String(el), String(Balance.MBODY_ORDER[j]))
			var s := "x%.1f" % m
			if m <= 0.0:
				s = "0배 면역"
			Look.text_left(ci, Vector2(x0 + step * float(j) + 14.0, y), s, 18, _em_col(m))
		y += 26.0
	_rule(ci, y - 4.0)
	y += 20.0
	Look.text_left(ci, Vector2(L, y), "이번 탄에 오는 놈 (Run.kinds_for — 전투와 같은 답이다)",
			19, Look.GOLD)
	y += 30.0
	for m2 in Run.kinds_for(sim.wave):
		_mob_row(ci, y, String(m2.get("ko", "?")),
				String(Balance.MKIND[String(m2.get("kind", "swarm"))]["ko"]),
				String(m2.get("body", "")), false)
		y += 24.0
	if Balance.is_boss_wave(sim.wave):
		var bs: Dictionary = Run.boss_for(sim.wave)
		_mob_row(ci, y, String(bs.get("ko", "?")), "보스", String(bs.get("body", "")), true)
		y += 24.0
	y += 16.0
	Look.text_left(ci, Vector2(L, y), "전장에 선 영웅의 속성", 19, Look.GOLD)
	var ex := X + 220.0
	for he in sim.heroes:
		Look.draw_elem(ci, Vector2(ex, y), 8.0, String(he["elem"]))
		ex += 24.0


static func _mob_row(ci: CanvasItem, y: float, nm: String, kind_ko: String,
		body: String, boss: bool) -> void:
	Look.text_left(ci, Vector2(L + 10.0, y), nm, 18, Look.RED if boss else Look.INK)
	Look.text_left(ci, Vector2(X + 190.0, y), kind_ko, 17,
			Look.RED if boss else Look.INK_DIM)
	_body_swatch(ci, X + 256.0, y, body)
	Look.text_left(ci, Vector2(X + 271.0, y), Balance.body_ko(body), 17, Look.INK_DIM)
	var wx := X + 340.0
	Look.text_left(ci, Vector2(wx, y), "약점", 16, Look.INK_DIM)
	wx += 40.0
	for e in Balance.body_weak(body):
		Look.draw_elem(ci, Vector2(wx, y), 8.0, String(e))
		wx += 22.0
	if not Balance.body_immune(body).is_empty():
		Look.text_left(ci, Vector2(wx + 12.0, y), "면역", 16, Look.RED)
		wx += 54.0
		for e2 in Balance.body_immune(body):
			Look.draw_elem_x(ci, Vector2(wx, y), 8.0, String(e2))
			wx += 22.0
