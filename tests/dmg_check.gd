extends Node

## 데미지가 **어떻게 들어가는지**를 눈으로 따라가는 검사기.
##
## 밸런스 검사(tests/balance_check)는 "몇 탄까지 갔나"만 말한다. 그런데 숫자가 이상할 때
## 알고 싶은 것은 그게 아니라 **"이 한 대가 왜 이 숫자인가"** 다. 그걸 볼 데가 없어서
## 여태 print 를 박았다 지웠다 했다 — 이 파일이 그 자리를 대신한다.
##
##   POCKER_NO_SAVE=1 godot --headless --path . res://tests/dmg_check.tscn -- <모드> <옵션>
##
## 모드 넷:
##   --calc      한 대의 곱셈 사슬을 줄줄이 편다 (기본)
##   --trace     실제 전투 한 탄을 돌려 **hp 가 깎이는 것을 전부** 찍는다
##   --selftest  --calc 의 산수와 실제 전투의 차감이 같은가 (판정: 정상)
##   --table     표만 — 상성 5x5 · 탄 방식 · 체력 곡선 · 등급별 화력
##
## ★ 왜 계산을 여기에 **다시 적지 않는가**: 이 검사기는 Run.hero_stats() 와
##   BattleSim._hurt() 를 **그대로 부른다.** 여기에 공식을 베껴 적으면 게임을 고칠 때마다
##   검사기가 조용히 낡아서, 「검사기는 통과하는데 게임은 틀린」 최악의 상태가 된다
##   (CLAUDE.md 18-0-1 이 상점 화면에 대해 말하는 것과 같은 함정이다).
##   곱셈 사슬만은 항목을 하나씩 나눠 적는데, 그 곱이 hero_stats 와 **같은지 매번 잰다** —
##   어긋나면 그 줄에 「!! 어긋남」이 뜬다.

const EPS := 0.0005

## 상성표의 기대값. CLAUDE.md 2-2 의 표를 그대로 옮긴 것이다 —
## 여기가 Balance.MBODY 와 어긋나면 문서와 코드 중 하나가 거짓말을 하고 있다.
const WANT_MULT := {
	"aqua":  {"water": 0.5, "fire": 0.5, "ice": 0.5, "elec": 2.0, "none": 1.0},
	"flame": {"water": 2.0, "fire": 0.5, "ice": 0.5, "elec": 1.0, "none": 1.0},
	"wood":  {"water": 0.5, "fire": 2.0, "ice": 2.0, "elec": 0.5, "none": 1.0},
	"rock":  {"water": 2.0, "fire": 0.5, "ice": 2.0, "elec": 0.0, "none": 1.0},
	"frost": {"water": 0.5, "fire": 2.0, "ice": 0.5, "elec": 1.0, "none": 1.0},
}

var _fail := 0


# =========================================================================== #
# 전투를 들여다보는 시뮬레이터
#
# ★ **게임 코드에 print 를 박지 않는다.** BattleSim 을 물려받아 hp 를 깎는 함수만
#   가로챈다. GDScript 는 모든 메서드가 가상이라, 부모 안에서 부른 _hurt() 도 여기로 온다.
#   그래서 game/battle_sim.gd 는 한 줄도 안 고치고 **모든 차감**을 볼 수 있다 —
#   광역·연쇄·분열처럼 사건(events)을 안 흘리는 자리까지 포함해서.
# =========================================================================== #
class Tracer extends BattleSim:
	## hp 가 깎인 것 전부. {t, ctx, src, mi, name, body, req, em, got, hp0, hp1}
	var rows: Array = []
	## 상태이상이 붙은 것 전부. {t, kind, mi, name, detail}
	var riders: Array = []
	var t: float = 0.0
	## 지금 어느 길로 들어온 피해인가. 아래 override 들이 갈아 끼운다.
	var ctx: String = "?"

	func step(dt: float) -> void:
		t += dt
		super(dt)

	# --- 어느 길로 들어왔는가를 표시만 해 둔다 (계산은 하나도 안 바꾼다) ---
	func _heroes_fire(dt: float) -> void:
		ctx = "장판"      # 장판은 _heroes_fire 안에서 곧장 _hurt 를 부른다
		super(dt)

	func _move_bullets(dt: float) -> void:
		ctx = "직격"
		super(dt)

	func _shoot(hi: int, tgt: int, dmg: float, kind: String, crit: bool, shots: int = 1) -> void:
		var old := ctx
		if kind == "beam":
			ctx = "광선"
		super(hi, tgt, dmg, kind, crit, shots)
		ctx = old

	func _impact(b: Dictionary, mi: int) -> void:
		var old := ctx
		ctx = "직격"
		super(b, mi)
		ctx = old

	func _splash(skip: int, at: Vector2, radius: float, dmg: float, src: int,
			elem: String = "none") -> void:
		var old := ctx
		ctx = "광역"
		super(skip, at, radius, dmg, src, elem)
		ctx = old

	func _chain(from_i: int, dmg: float, jumps: int, decay: float, hop: float,
			seen: Array, col: Color, src: int, elem: String = "none", shot_src: int = -1) -> void:
		var old := ctx
		ctx = "연쇄"
		super(from_i, dmg, jumps, decay, hop, seen, col, src, elem, shot_src)
		ctx = old

	func _field_extras(mi: int, dmg: float) -> void:
		var old := ctx
		ctx = "패시브"
		super(mi, dmg)
		ctx = old

	# --- 여기가 본체. **hp 가 깎이는 유일한 자리**를 앞뒤로 재 둔다 ---
	func _hurt(mi: int, dmg: float, _crit: bool, _src: int, elem: String = "none",
			rider: bool = true, rider_dmg: float = -1.0, rider_n: int = 1,
			flash: bool = true) -> float:
		if mi < 0 or mi >= monsters.size():
			return super(mi, dmg, _crit, _src, elem, rider, rider_dmg, rider_n, flash)
		var mo: Dictionary = monsters[mi]
		var hp0: float = float(mo["hp"])
		var em: float = super(mi, dmg, _crit, _src, elem, rider, rider_dmg, rider_n, flash)
		var hp1: float = float(mo["hp"])
		rows.append({
			"t": t, "ctx": ctx, "src": _src, "mi": mi,
			"name": String(mo["m"].get("ko", mo["m"].get("id", "?"))),
			"kind": String(mo["kind"]), "body": String(mo.get("body", "")),
			"elem": elem, "req": dmg, "em": em, "crit": _crit,
			"got": hp0 - hp1, "hp0": hp0, "hp1": hp1, "max": float(mo["max"]),
		})
		return em

	## 화상 도트는 _hurt 를 안 거치고 여기서 hp 를 직접 깎는다 (CLAUDE.md 5-1 의 유일한 예외).
	## 그래서 걸음 앞뒤로 재서 줄줄 새는 몫을 따로 잡아 둔다.
	func _move_monsters(dt: float) -> void:
		var n := monsters.size()
		# ★ PackedFloat32Array 로 담으면 안 된다 — hp 는 64비트인데 32비트로 깎아 담으면
		#   되돌릴 때 1e-6 쯤이 남아서, 화상이 안 붙은 몬스터까지 **매 걸음** 「깎였다」로
		#   잡힌다(실제로 22,000줄이 그렇게 나왔다).
		var pre := PackedFloat64Array()
		pre.resize(n)
		for i in range(n):
			pre[i] = float(monsters[i]["hp"])
		super(dt)
		for i in range(mini(n, monsters.size())):
			var mo: Dictionary = monsters[i]
			var d: float = pre[i] - float(mo["hp"])
			if d <= 1e-9:
				continue
			rows.append({
				# 화상도 **붙인 영웅의 몫**이다 — 몬스터가 burn_src 로 들고 다닌다.
				"t": t, "ctx": "화상", "src": int(mo.get("burn_src", -1)), "mi": i,
				"name": String(mo["m"].get("ko", "?")), "kind": String(mo["kind"]),
				"body": String(mo.get("body", "")), "elem": "fire",
				"req": d, "em": 1.0, "crit": false,
				"got": d, "hp0": pre[i], "hp1": float(mo["hp"]), "max": float(mo["max"]),
			})

	# --- 상태이상이 실제로 붙었는가 ---
	func _burn(mi: int, dps: float, sec: float, elem: String = "none") -> void:
		super(mi, dps, sec, elem)
		if mi < monsters.size():
			var mo: Dictionary = monsters[mi]
			riders.append({"t": t, "kind": "화상", "mi": mi,
				"name": String(mo["m"].get("ko", "?")),
				"detail": "초당 %.2f · %.1f초 남음" % [float(mo["burn"]), float(mo["burn_t"])]})

	func _slow(mi: int, amount: float, sec: float) -> void:
		super(mi, amount, sec)
		if mi < monsters.size():
			var mo: Dictionary = monsters[mi]
			riders.append({"t": t, "kind": "둔화", "mi": mi,
				"name": String(mo["m"].get("ko", "?")),
				"detail": "%.0f%% · %.1f초 남음" % [float(mo["slow"]) * 100.0, float(mo["slow_t"])]})

	func _stun(mi: int, mult: float = 1.0) -> void:
		var before := 0.0
		if mi < monsters.size():
			before = float(monsters[mi]["stun_t"])
		super(mi, mult)
		if mi < monsters.size() and float(monsters[mi]["stun_t"]) > before:
			var mo: Dictionary = monsters[mi]
			riders.append({"t": t, "kind": "마비", "mi": mi,
				"name": String(mo["m"].get("ko", "?")),
				"detail": "%.2f초" % float(mo["stun_t"])})


# =========================================================================== #
func _ready() -> void:
	if OS.get_environment("POCKER_NO_SAVE") != "1":
		print("!! POCKER_NO_SAVE=1 없이 돌리고 있습니다 — 이 검사가 만든 판이")
		print("   「하다 만 판」으로 남아서 다음에 앱을 켠 사람이 그 판을 잇게 됩니다.")
	if _has("--help") or _has("-h"):
		_usage()
	elif _has("--list"):
		_list()
	elif _has("--table"):
		_table()
	elif _has("--trace"):
		_trace()
	elif _has("--selftest"):
		_selftest()
	else:
		_calc()
	get_tree().quit(1 if _fail > 0 else 0)


# --------------------------------------------------------------------------- #
# 인자
# --------------------------------------------------------------------------- #
func _has(k: String) -> bool:
	return Harness.has_arg(k)


func _opt(k: String, d: String) -> String:
	return Harness.arg(k, d)


func _opti(k: String, d: int) -> int:
	return Harness.arg_int(k, d)


func _optf(k: String, d: float) -> float:
	return Harness.arg_float(k, d)


func _parse_lv(s: String) -> Dictionary:
	var out := {}
	if s == "":
		return out
	for part in s.split(",", false):
		var kv: PackedStringArray = String(part).split("=")
		if kv.size() == 2:
			out[String(kv[0]).strip_edges()] = int(String(kv[1]).strip_edges())
	return out


func _parse_team(s: String) -> Array:
	var out := []
	for part in s.split(",", false):
		var kv: PackedStringArray = String(part).split(":")
		out.append({"id": String(kv[0]).strip_edges(),
				"n": int(String(kv[1])) if kv.size() > 1 else 1})
	return out


func _parse_pas(s: String) -> Array:
	var out := []
	for p in s.split(",", false):
		out.append(String(p).strip_edges())
	return out


## 검사용 판을 하나 세운다. 성역에는 **시킨 캐릭터만** 선다.
##
## ★ 배열을 직접 만지는 것은 여기(tests/)라서 괜찮다. 화면에서 그러면 겹친 수가 딸려
##   오지 않는다(CLAUDE.md 14-3). 여기서는 "이 영웅만 세운 판"을 일부러 만드는 것이다.
func _setup(team: Array, lvs: Dictionary, pas: Array, w: int, seed_value: int) -> bool:
	Run.start_run(seed_value)
	Run.wave = maxi(1, w)
	Run.heroes.clear()
	Run.bench.clear()
	for t in team:
		var u: Dictionary = Roster.unit_by_id(String(t["id"]))
		if u.is_empty():
			printerr("그런 캐릭터가 없습니다: ", t["id"], "   (--list 로 목록)")
			return false
		Run.heroes.append({"unit": u, "tier": int(u.get("tier", 0)),
				"wave": Run.wave, "n": maxi(1, int(t["n"]))})
	Run.levels.clear()
	for k in lvs:
		Run.levels[String(k)] = int(lvs[k])
	Run.passives.clear()
	for p in pas:
		if Balance.passive_by_id(String(p)).is_empty():
			printerr("그런 패시브가 없습니다: ", p)
			return false
		Run.passives.append(String(p))
	return true


func _uname(u: Dictionary) -> String:
	return "%s(%s)" % [String(u.get("ko", "?")), String(u.get("en", ""))]


# --------------------------------------------------------------------------- #
# 1) --calc — 한 대의 곱셈 사슬
# --------------------------------------------------------------------------- #
## 사슬 하나를 찍고, **그 곱이 진짜 함수와 같은지** 잰다.
func _chain_of(title: String, factors: Array, truth: float, truth_src: String) -> void:
	print("\n" + title)
	var acc := 1.0
	var i := 1
	for f in factors:
		acc *= float(f[2])
		print("   %d) %-18s %-40s x %10.4f  = %13.4f"
				% [i, String(f[0]), String(f[1]), float(f[2]), acc])
		i += 1
	var ok: bool = absf(acc - truth) <= maxf(EPS, absf(truth) * 1e-5)
	if not ok:
		_fail += 1
	print("      %-18s %-40s   %10s  = %13.4f   %s"
			% ["→ 합계", truth_src, "", truth, "일치" if ok else "!! 어긋남"])


func _calc() -> void:
	var uid := _opt("--unit", "chispa")
	var n := _opti("--n", 1)
	var w := _opti("--wave", 1)
	var rank := _opti("--rank", 1)
	var mkind := _opt("--mkind", "swarm")
	var lvs := _parse_lv(_opt("--lv", ""))
	var pas := _parse_pas(_opt("--pas", ""))
	var crit := _has("--crit")
	if not _setup([{"id": uid, "n": n}], lvs, pas, w, 20260829):
		_fail += 1
		return

	var h: Dictionary = Run.heroes[0]
	var u: Dictionary = h["unit"]
	var t: int = int(h["tier"])
	var el := String(u.get("elem", "none"))
	var bk := String(u.get("bullet", "shot"))
	var pk := String(u.get("profile", "balance"))
	var prof: Dictionary = Balance.PROFILE[pk]
	var bul: Dictionary = Balance.BULLET.get(bk, Balance.BULLET["shot"])
	var st: Dictionary = Run.hero_stats(h)

	print("\n========== 한 대의 계산 ==========")
	print("캐릭터   %s  ·  등급 %d %s" % [_uname(u), t, Roster.TIER_KO[t]])
	print("         속성 %s(%s)  ·  탄 방식 %s(%s)  ·  성향 %s(%s)  ·  겹침 x%d"
			% [Balance.elem_ko(el), el, String(bul["ko"]), bk, String(prof["ko"]), pk, n])
	var rk := String(u.get("role", "single"))
	var rol: Dictionary = Balance.ROLE.get(rk, Balance.ROLE["single"])
	print("상점     %s" % ("없음" if lvs.is_empty() else str(lvs)))
	print("패시브   %s" % ("없음" if pas.is_empty() else ", ".join(PackedStringArray(pas))))

	# --- 1. 한 발의 세기 (Run.hero_stats) ---
	_chain_of("── 1. 한 발의 세기  (core/run.gd  hero_stats)",
		[
			["등급 기본",   "Balance.TIER_ATK[%d]" % t,            Balance.TIER_ATK[t]],
			["성향",        "PROFILE[%s].atk" % pk,                float(prof["atk"])],
			["탄 방식",     "BULLET[%s].dmg" % bk,                 float(bul["dmg"])],
			["역할",        "ROLE[%s].atk" % rk,                   float(rol["atk"])],
			["속성 기본화력", "Balance.elem_dmg(%s)" % el,          Balance.elem_dmg(el)],
			["공명 패시브", "Run.resonance_mult(%s)" % el,         Run.resonance_mult(el)],
			["겹침 한 발 몫", "Balance.stack_atk(%d)" % n,          Balance.stack_atk(n)],
			["상점 공격력", "Balance.atk_mult(lv %d)" % Run.lv("atk"), Balance.atk_mult(Run.lv("atk"))],
			["패시브 공격력", "Run.pas_mult(\"atk\")",              Run.pas_mult("atk")],
		], float(st["atk"]), "hero_stats()[\"atk\"]")

	_chain_of("── 2. 공격 속도  (초당 발사 횟수)",
		[
			["등급 기본",   "Balance.TIER_RATE[%d]" % t,           Balance.TIER_RATE[t]],
			["성향",        "PROFILE[%s].rate" % pk,               float(prof["rate"])],
			["상점 공격속도", "Balance.rate_mult(lv %d)" % Run.lv("rate"), Balance.rate_mult(Run.lv("rate"))],
			["패시브 공격속도", "Run.pas_mult(\"rate\")",           Run.pas_mult("rate")],
		], float(st["rate"]), "hero_stats()[\"rate\"]")

	var shots: int = int(st["shots"])
	print("\n── 3. 겹침이 하는 일  (CLAUDE.md 14-5)")
	print("   한 번에 나가는 발 수   Balance.stack_shots(%d)          = %d발  (상한 %d)"
			% [n, shots, Balance.STACK_SHOT_MAX])
	print("   한 발의 세기 몫        Balance.stack_atk(%d)            = x%.4f" % [n, Balance.stack_atk(n)])
	var prod: float = Balance.stack_atk(n) * float(shots)
	print("   발 수 x 한 발 몫       = %.4f   (겹침 %d 과 %s)"
			% [prod, n, "같다" if absf(prod - float(n)) < EPS else "!! 다르다"])
	if absf(prod - float(n)) >= EPS:
		_fail += 1
	if bk == "beam":
		print("   ★ 그런데 **광선은 예외다.** _shoot 이 겹친 만큼 _nearest_targets(%d) 로" % shots)
		print("      앞선 놈 %d마리를 서로 다르게 꿴다 — 같은 놈을 %d번 지지지 않는다."
				% [shots, shots])
		print("      그래서 한 대상 기준 피해는 %d배가 아니라 x%.2f (= stack_atk) 다."
				% [n, Balance.stack_atk(n)])
		print("      혼자 오는 보스에게는 겹친 값어치가 %s. (아래 7번의 total_dps 는 %d배로 세므로 그만큼 부풀어 있다)"
				% ["통째로 없다" if Balance.stack_atk(n) <= 1.0 + EPS else "x%.2f 뿐이다" % Balance.stack_atk(n), shots])
	else:
		print("   → 단일 대상 피해는 정확히 %d배. 달라지는 것은 광역·연쇄·상태이상이 %d번 굴려진다는 것뿐이다."
				% [n, shots])

	# --- 4. 발사 순간 ---
	var critx: float = float(st["critx"])
	var cp: float = float(st["crit"])
	var am_first: float = Balance.PASSIVE_FIRST if Run.has("first") else 1.0
	print("\n── 4. 쏘는 순간  (game/battle_sim.gd  _heroes_fire)")
	print("   var dmg = he.atk * _atk_mult() * (critx if crit else 1.0)")
	print("   한 발의 세기 he.atk                                       = %13.4f" % float(st["atk"]))
	print("   x 선제 패시브 _atk_mult()   (%s)                          x %10.4f"
			% ["첫 %.0f초만" % Balance.PASSIVE_FIRST_SEC if Run.has("first") else "패시브 없음 → 1.0", am_first])
	print("   x 치명타      %.1f%% 확률로 x%.2f  (%s)                   x %10.4f"
			% [cp * 100.0, critx, "이번엔 터졌다고 친다" if crit else "안 터진 값으로 계산", critx if crit else 1.0])
	var fired: float = float(st["atk"]) * am_first * (critx if crit else 1.0)
	print("   = _hurt() 에 들어가는 값                                  = %13.4f" % fired)

	# --- 5. _hurt ---
	print("\n── 5. 맞는 순간  (game/battle_sim.gd  _hurt — hp 가 깎이는 유일한 자리)")
	print("   순서: dmg x 상성  →  (면역이면 여기서 끝)  →  x 거인사냥  →  x 과잉살상  →  hp -= dmg")
	var hp1: float = Balance.wave_hp(w, rank) * float(Balance.MKIND[mkind]["hp"])
	print("\n   %-10s %-8s %-13s %-13s %-9s %s"
			% ["맞는 몸", "상성", "실제 차감", "화상/상태이상", "몇 대", "비고"])
	for body in Balance.MBODY_ORDER:
		var em: float = Balance.elem_mult(el, String(body))
		var shown := em
		if em > 0.0 and em < 1.0 and Run.has("antibody"):
			shown = maxf(em, Balance.PASSIVE_ANTIBODY)
		var got: float = fired * shown
		if mkind == "boss" and Run.has("giantslay"):
			got *= Balance.PASSIVE_GIANT
		var tag := "보통"
		if shown >= 2.0:
			tag = "약점 2배"
		elif shown <= 0.0:
			tag = "면역 — 숫자도 상태이상도 없다"
		elif shown < 1.0:
			tag = "저항"
		var rid := "—"
		match Balance.elem_rider(el):
			"burn":
				rid = "화상 초당 %.2f x %.0f초" % [got * float(Balance.STATUS["burn"]["amount"]),
						float(Balance.STATUS["burn"]["sec"])]
			"slow":
				rid = "둔화 %.0f%% %.0f초" % [float(Balance.STATUS["slow"]["amount"]) * 100.0,
						float(Balance.STATUS["slow"]["sec"])]
			"stun":
				var p: float = float(Balance.STATUS["stun"]["chance"])
				if mkind == "boss":
					p *= Balance.BOSS_STUN_MUL
				rid = "마비 %.0f%% 확률 %.1f초" % [p * 100.0, float(Balance.STATUS["stun"]["sec"])]
		if shown <= 0.0:
			rid = "—"
		var hits: float = 99999.0 if got <= 0.0 else ceil(hp1 / got)
		print("   %-10s x%-7.2f %13.2f %-13s %-9s %s"
				% ["%s %s" % [Balance.body_ko(String(body)), body], shown, got, rid,
				   "—" if got <= 0.0 else "%d대" % int(hits), tag])
	print("   (한 발 x %d발 = 한 번에 %.2f배. 위 표는 **한 발** 기준이다)" % [shots, float(shots)])
	if Run.has("overkill"):
		print("   ★ 「몇 대」는 과잉살상(hp %.0f%% 이하에서 x%.2f)을 안 셌다 — 실제로는 마지막 몇 대가 더 빠르다."
				% [Balance.PASSIVE_OVERKILL_AT * 100.0, Balance.PASSIVE_OVERKILL])

	# --- 6. 맞는 쪽 ---
	print("\n── 6. 맞는 쪽의 체력  (core/balance.gd  wave_hp)")
	print("   wave_hp(%d, rank %d) = HP_BASE x HP_GROW^(w-1) x mid_ramp x early_tough x theme_hp" % [w, rank])
	print("     HP_BASE                          = %10.4f" % Balance.HP_BASE)
	print("     x HP_GROW^%-3d  (%.4f^%d)         x %10.4f" % [w - 1, Balance.HP_GROW, w - 1,
			pow(Balance.HP_GROW, float(w - 1))])
	print("     x mid_ramp(%d)                    x %10.4f" % [w, Balance.mid_ramp(w)])
	print("     x early_tough(%d)                 x %10.4f" % [w, Balance.early_tough(w)])
	print("     x theme_hp(rank %d)               x %10.4f" % [rank, Balance.theme_hp(rank)])
	print("     = 기준 체력                       = %10.2f" % Balance.wave_hp(w, rank))
	print("   x MKIND[%s].hp %.2f  →  한 마리 최대 체력 = %.2f  (마릿수 %d)"
			% [mkind, float(Balance.MKIND[mkind]["hp"]), hp1, Balance.wave_count(w)])

	# ★ 그 탄에 **실제로 오는 놈**들. 씨앗으로 미리 정해져 있으므로(CLAUDE.md 2-4)
	#   여기서 물어봐도 전투와 같은 답이 온다 — 이 줄이 "이 영웅을 세울까"의 답이다.
	print("\n   이 탄에 실제로 오는 놈 (Run.kinds_for(%d) — 전투와 같은 답이다)" % w)
	print("      %-16s %-8s %-6s %-12s %-9s %s" % ["몬스터", "종류", "몸", "최대 체력", "상성", "한 발에 몇 대"])
	for m in Run.kinds_for(w):
		var b := String(m.get("body", ""))
		var mk := String(m.get("kind", "swarm"))
		var mhp: float = Balance.wave_hp(w, rank) * float(Balance.MKIND[mk]["hp"])
		var em2: float = Balance.elem_mult(el, b)
		var got2: float = fired * em2
		print("      %-16s %-8s %-6s %-12.1f x%-8.2f %s"
				% [String(m.get("ko", "?")), String(Balance.MKIND[mk]["ko"]), Balance.body_ko(b),
				   mhp, em2, "안 통함" if got2 <= 0.0 else "%d대" % int(ceil(mhp / got2))])
	if Balance.is_boss_wave(w):
		var bs: Dictionary = Run.boss_for(w)
		var bhp: float = Balance.wave_hp(w, rank) * float(Balance.MKIND["boss"]["hp"])
		var bem: float = Balance.elem_mult(el, String(bs.get("body", "")))
		print("      %-16s %-8s %-6s %-12.1f x%-8.2f %s   (크리스탈 %d개를 부순다)"
				% [String(bs.get("ko", "?")), "보스", Balance.body_ko(String(bs.get("body", ""))),
				   bhp, bem, "안 통함" if bem <= 0.0 else "%d대" % int(ceil(bhp / (fired * bem))),
				   int(Balance.MKIND["boss"]["crush"])])

	# --- 7. 초당 ---
	var cmul: float = 1.0 + cp * (critx - 1.0)
	print("\n── 7. 초당 피해  (단일 대상 · 상성 빼고)")
	print("   atk %.3f x rate %.3f x 치명타 기대 %.3f x 발 수 %d = %.2f"
			% [float(st["atk"]), float(st["rate"]), cmul, shots,
			   float(st["atk"]) * float(st["rate"]) * cmul * float(shots)])
	print("   Run.total_dps()  (성역 전체)                       = %.2f" % Run.total_dps())
	print("   ⚠ 광역·연쇄·장판이 여럿을 동시에 때리는 몫은 안 들어 있다. 어림수다(CLAUDE.md 17).")
	print("")


# --------------------------------------------------------------------------- #
# 2) --trace — 실제 전투 한 탄
# --------------------------------------------------------------------------- #
func _trace() -> void:
	var w := _opti("--wave", 12)
	var team := _parse_team(_opt("--team", _opt("--unit", "chispa") + ":" + str(_opti("--n", 1))))
	var lvs := _parse_lv(_opt("--lv", ""))
	var pas := _parse_pas(_opt("--pas", ""))
	var seed_value := _opti("--seed", 20260829)
	var dt := _optf("--dt", 1.0 / 60.0)
	var maxrow := _opti("--max", 50)
	var only_hero := _opti("--hero", -1)
	if not _setup(team, lvs, pas, w, seed_value):
		_fail += 1
		return

	var sim := Tracer.new()
	sim.setup(Run, w, seed_value + w)

	print("\n========== 전투 추적 · %d탄 ==========" % w)
	print("성역:")
	for i in range(sim.heroes.size()):
		var he: Dictionary = sim.heroes[i]
		var u: Dictionary = he["h"]["unit"]
		print("   [%d] %-24s x%-2d  %s %s  한 발 %.2f · 초당 %.2f발 · %d발씩"
				% [i, _uname(u), int(he["h"].get("n", 1)),
				   Balance.elem_ko(String(he["elem"])), String(Balance.BULLET[String(he["kind"])]["ko"]),
				   float(he["atk"]), float(he["rate"]), int(he["shots"])])
	var bodies := {}
	for m in Run.kinds_for(w):
		var b := String(m.get("body", ""))
		bodies[b] = "%s %s" % [String(bodies.get(b, "")), String(m.get("ko", ""))]
	print("이번 탄 몬스터: %s   (테마 rank %d · 마릿수 %d%s)"
			% [str(bodies).replace("\"", ""), Run.theme_rank(w), Balance.wave_count(w),
			   " + 보스" if Balance.is_boss_wave(w) else ""])
	print("한 걸음 %.4f초 · 씨앗 %d\n" % [dt, seed_value])
	print("   %-8s %-7s %-4s %-16s %-6s %-9s %-11s %s"
			% ["시각", "경로", "누가", "누구를", "몸", "요청", "x상성", "실제 차감 → 남은 hp"])

	var guard := 0
	while not sim.done and guard < 40000:
		sim.step(dt)
		sim.events.clear()
		guard += 1

	var shown := 0
	for r in sim.rows:
		if only_hero >= 0 and int(r["src"]) != only_hero:
			continue
		if shown >= maxrow:
			break
		shown += 1
		var em: float = float(r["em"])
		var mark := ""
		if em >= 2.0:
			mark = " 약점!"
		elif em <= 0.0:
			mark = " 무효"
		elif em < 1.0:
			mark = " 저항"
		if bool(r["crit"]):
			mark += " 치명타"
		print("   %7.3f  %-7s [%s]  %-16s %-6s %9.2f  x%-9.2f %9.2f → %8.2f%s"
				% [float(r["t"]), String(r["ctx"]),
				   "화상" if int(r["src"]) < 0 else str(int(r["src"])),
				   String(r["name"]), Balance.body_ko(String(r["body"])),
				   float(r["req"]), em, float(r["got"]), float(r["hp1"]), mark])
	if sim.rows.size() > shown:
		print("   ... %d줄 더 있음 (--max 로 늘린다)" % (sim.rows.size() - shown))

	# 상태이상
	print("\n── 붙은 상태이상 (앞 %d개)" % mini(15, sim.riders.size()))
	if sim.riders.is_empty():
		print("   없음 — 물/무상성만 세웠거나, 면역에 걸렸거나(바위 몸 x 전기).")
	for i in range(mini(15, sim.riders.size())):
		var rd: Dictionary = sim.riders[i]
		print("   %7.3f  %-5s %-16s %s" % [float(rd["t"]), String(rd["kind"]),
				String(rd["name"]), String(rd["detail"])])

	# 요약
	var by_ctx := {}
	var by_hero := {}
	var by_body := {}
	var total := 0.0
	var wasted := 0
	for r in sim.rows:
		var g: float = float(r["got"])
		total += g
		by_ctx[r["ctx"]] = float(by_ctx.get(r["ctx"], 0.0)) + g
		by_body[r["body"]] = float(by_body.get(r["body"], 0.0)) + g
		if int(r["src"]) >= 0:
			by_hero[int(r["src"])] = float(by_hero.get(int(r["src"]), 0.0)) + g
		if float(r["em"]) <= 0.0:
			wasted += 1
	print("\n── 요약")
	print("   전투 시간 %.1f초 · hp 가 깎인 횟수 %d번 · 총 피해 %.0f" % [sim.t, sim.rows.size(), total])
	print("   경로별:")
	for k in by_ctx:
		print("      %-8s %12.0f  (%.1f%%)" % [k, float(by_ctx[k]), float(by_ctx[k]) * 100.0 / maxf(1.0, total)])
	print("   영웅별 (BattleSim 이 센 heroes[i][\"dmg\"] 와 나란히):")
	for i in range(sim.heroes.size()):
		var mine: float = float(by_hero.get(i, 0.0))
		var theirs: float = float(sim.heroes[i]["dmg"])
		var ok: bool = absf(mine - theirs) <= maxf(1.0, theirs * 0.02)
		print("      [%d] %-24s 추적 %12.0f   전과판 %12.0f  %s"
				% [i, _uname(sim.heroes[i]["h"]["unit"]), mine, theirs,
				   "" if ok else "!! 다름"])
	print("   몸별로 들어간 피해:")
	for b in by_body:
		print("      %-6s %12.0f" % [Balance.body_ko(String(b)), float(by_body[b])])
	if wasted > 0:
		print("   무효(0배) 타격 %d번 — 그만큼 헛방이다. 성역에서 그 속성을 빼야 한다는 뜻이다." % wasted)
	print("   처치 %d마리 · 뚫림 %d마리 · 깨진 크리스탈 %d개 · 번 골드 %d"
			% [sim.kills, sim.leak_n, sim.leaked, sim.gold])
	print("")


# --------------------------------------------------------------------------- #
# 3) --selftest — 산수와 실제가 같은가
# --------------------------------------------------------------------------- #
func _bad(msg: String) -> void:
	_fail += 1
	print("   !! " + msg)


## 표에서 조건에 맞는 캐릭터 하나를 골라 온다.
##
## ★ **검사에 id 를 못 박지 마라.** 로스터가 바뀌면 `unit_by_id` 가 빈 사전을 돌려주고,
##   그러면 검사가 **조용히 아무것도 안 재고** 통과한다. 서른 명을 여든 명으로 갈아
##   끼울 때 실제로 여섯 자리가 그렇게 죽어 있었다. 조건으로 고르면 로스터가 어떻게
##   바뀌든 그 방식을 쓰는 캐릭터가 있는 한 검사가 산다.
func _find(bullet: String = "", elem: String = "", role: String = "") -> String:
	for u in Roster.UNITS:
		if bullet != "" and String(u.get("bullet", "")) != bullet:
			continue
		if elem != "" and String(u.get("elem", "")) != elem:
			continue
		if role != "" and String(u.get("role", "")) != role:
			continue
		return String(u["id"])
	return ""


## 방식마다 하나씩. 없는 방식은 건너뛴다(빈 문자열은 부르는 쪽이 거른다).
func _one_per_bullet(kinds: Array) -> Array:
	var out: Array = []
	for k in kinds:
		var id := _find(String(k))
		if id != "":
			out.append(id)
	return out


func _selftest() -> void:
	print("\n========== 데미지 계산 자체 검사 ==========")

	# (1) 곱셈 사슬 = hero_stats  — 캐릭터 서른 명 x 겹침 여섯 가지 x 상점/패시브 두 가지
	print("\n1. 곱셈 사슬의 곱이 Run.hero_stats() 와 같은가")
	var cases := [
		{"lv": {}, "pas": []},
		{"lv": {"atk": 7, "rate": 5, "crit": 4, "critx": 3}, "pas": ["heavytip", "repeater", "keenedge"]},
	]
	var n_checked := 0
	for c in cases:
		for u in Roster.UNITS:
			for n in [1, 2, 3, 5, 8, 16]:
				if not _setup([{"id": String(u["id"]), "n": n}], c["lv"], c["pas"], 1, 7):
					_bad("판을 못 세웠다: %s" % u["id"])
					continue
				var h: Dictionary = Run.heroes[0]
				var st: Dictionary = Run.hero_stats(h)
				var t: int = int(h["tier"])
				var pk := String(u.get("profile", "balance"))
				var bk := String(u.get("bullet", "shot"))
				var el := String(u.get("elem", "none"))
				var rk2 := String(u.get("role", "single"))
				var want_atk: float = Balance.TIER_ATK[t] \
						* float(Balance.PROFILE[pk]["atk"]) \
						* float(Balance.BULLET[bk]["dmg"]) \
						* float(Balance.ROLE.get(rk2, Balance.ROLE["single"])["atk"]) \
						* Balance.elem_dmg(el) * Run.resonance_mult(el) \
						* Balance.atk_mult(Run.lv("atk")) * Run.pas_mult("atk")
				var want_rate: float = Balance.TIER_RATE[t] * float(Balance.PROFILE[pk]["rate"]) \
						* Balance.rate_mult(Run.lv("rate")) * Run.pas_mult("rate")
				if absf(want_atk - float(st["atk"])) > maxf(EPS, want_atk * 1e-5):
					_bad("%s x%d atk: 사슬 %.4f vs hero_stats %.4f" % [u["id"], n, want_atk, float(st["atk"])])
				if absf(want_rate - float(st["rate"])) > maxf(EPS, want_rate * 1e-5):
					_bad("%s x%d rate: 사슬 %.4f vs hero_stats %.4f" % [u["id"], n, want_rate, float(st["rate"])])
				n_checked += 1
	print("   %d가지를 재 봤다 (캐릭터 %d명 x 겹침 6 x 상점·패시브 2)" % [n_checked, Roster.UNITS.size()])

	# (2) Duplicate cards are separate fusion materials, never stacked damage.
	print("\n2. 기존 중첩 데이터가 출전 영웅의 화력을 부풀리지 않는가")
	_setup([{"id": "pip", "n": 1}], {}, [], 1, 7)
	var baseline := Run.hero_stats(Run.heroes[0])
	for n in [1, 2, 3, 4, 5, 8, 16, 40]:
		Run.heroes[0]["n"] = n
		var stats := Run.hero_stats(Run.heroes[0])
		if stats["atk"] != baseline["atk"] or stats["shots"] != 1:
			_bad("기존 중첩 %d가 공격력 또는 발 수를 변경한다" % n)
	print("   기존 중첩 1~40에서도 공격력과 단일 발사 유지")

	# (3) 상성표가 CLAUDE.md 의 표와 같은가
	print("\n3. 상성표가 문서(CLAUDE.md 2-2)와 같은가")
	for body in Balance.MBODY_ORDER:
		for el in Balance.ELEM_ORDER:
			var want: float = float(WANT_MULT[body][el])
			var got: float = Balance.elem_mult(String(el), String(body))
			if absf(want - got) > EPS:
				_bad("%s 몸에 %s 공격: 표 %.2f vs Balance.elem_mult %.2f" % [body, el, want, got])
	print("   5가지 몸 x 5가지 속성 = 25칸 확인")
	# 전기는 나무에 저항(0.5), 바위에 면역(0)이다.
	if absf(Balance.elem_mult("elec", "wood") - 0.5) > EPS:
		_bad("전기 → 나무는 0.5배여야 한다")
	for imm_body in ["rock"]:
		if absf(Balance.elem_mult("elec", imm_body)) > EPS:
			_bad("%s x 전기가 0배가 아니다 — 이 게임에서 제일 위험한 두 줄이다(CLAUDE.md 5-3)"
					% Balance.body_ko(imm_body))
	for body in Balance.MBODY_ORDER:
		if absf(Balance.elem_mult("none", String(body)) - 1.0) > EPS:
			_bad("무상성이 %s 에게 1.0 배가 아니다 (CLAUDE.md 5-2)" % body)

	# (4) 실제 전투가 산수와 같은 값을 깎는가
	print("\n4. 실제 전투(BattleSim)가 깎는 값이 산수와 같은가")
	# ★ 방식을 골고루 덮는다 — 단발·광역·연쇄·관통·**광선**.
	#   (장판은 「직격」이 아예 없어서 이 검사로는 못 잰다. 7번이 대신 잰다)
	var probes := _one_per_bullet(["shot", "splash", "chain", "pierce", "beam",
			"ricochet"])
	for uid in probes:
		var w := 12
		if not _setup([{"id": uid, "n": 1}], {}, [], w, 424242):
			_bad("판을 못 세웠다: %s" % uid)
			continue
		var st: Dictionary = Run.hero_stats(Run.heroes[0])
		var el := String(Run.heroes[0]["unit"].get("elem", "none"))
		var sim := Tracer.new()
		sim.setup(Run, w, 424242 + w)
		var guard := 0
		while not sim.done and guard < 20000:
			sim.step(1.0 / 60.0)
			sim.events.clear()
			guard += 1
		var direct := 0
		var bad := 0
		for r in sim.rows:
			if String(r["ctx"]) != "직격" and String(r["ctx"]) != "광선":
				continue
			direct += 1
			var em: float = Balance.elem_mult(el, String(r["body"]))
			# ★ **남은 체력까지만** 깎인다(BattleSim._hurt). 넘겨 죽인 몫은 hp 를 음수로
			#   내리지 않고 버려지므로, 마지막 한 대는 산수보다 적게 들어가는 것이 정상이다.
			var want: float = minf(float(st["atk"]) * em, maxf(0.0, float(r["hp0"])))
			# ★ **도탄은 튈 때마다 약해진다**(BULLET.ricochet.decay). 그래서 한 발이
			#   내는 직격이 여럿이고 그 값이 저마다 다르다 — 첫 대만 산수와 같고
			#   그 뒤는 decay 의 거듭제곱이다. 몇 번째 튄 것인지가 행에 안 적혀 있으므로
			#   **셋 중 하나와 맞으면 통과**로 친다(튀는 횟수가 셋이다).
			if String(Run.heroes[0]["unit"].get("bullet", "")) == "ricochet":
				var dec: float = float(Balance.BULLET["ricochet"]["decay"])
				var okr := false
				var w2: float = float(st["atk"]) * em
				for _b in range(int(Balance.BULLET["ricochet"]["bounce"]) + 1):
					if absf(minf(w2, maxf(0.0, float(r["hp0"]))) - float(r["got"])) \
							<= maxf(EPS, w2 * 1e-4):
						okr = true
						break
					w2 *= dec
				if okr:
					continue
			if absf(want - float(r["got"])) > maxf(EPS, want * 1e-4):
				bad += 1
				if bad <= 3:
					_bad("%s → %s(%s): 산수 %.4f vs 실제 %.4f"
							% [uid, r["name"], r["body"], want, float(r["got"])])
		if direct == 0:
			_bad("%s: 직격이 한 번도 안 났다 — 검사가 아무것도 안 재고 있다" % uid)
		else:
			print("   %-20s 직격 %4d번 확인 (틀린 것 %d)" % [uid, direct, bad])

	# (5) 면역이면 아무 일도 일어나지 않아야 한다 (CLAUDE.md 5-6)
	print("\n5. 면역(0배)이면 hp 도 안 깎이고 상태이상도 안 붙는가")
	# 전기 캐릭터 하나 — 바위 몸에 0배(면역)로 들어가는 줄이다.
	var immu := _find("", "elec")
	if immu == "" or not _setup([{"id": immu, "n": 3}], {}, [], 1, 31337):
		_bad("판을 못 세웠다")
	else:
		var sim2 := Tracer.new()
		sim2.setup(Run, 1, 31337)
		# 바위 몬스터를 억지로 하나 세운다 (앞 세 탄에는 원래 안 나온다 — CLAUDE.md 5-3)
		sim2.monsters.clear()
		sim2._queue.clear()
		var rockm: Dictionary = {}
		for m in Roster.MONSTERS:
			if String(m.get("body", "")) == "rock":
				rockm = m
				break
		sim2._spawn(rockm)
		var mo: Dictionary = sim2.monsters[0]
		var hp0: float = float(mo["hp"])
		var guard2 := 0
		while guard2 < 600:
			sim2.step(1.0 / 60.0)
			sim2.events.clear()
			guard2 += 1
			if sim2.monsters.is_empty():
				break
		if sim2.monsters.is_empty():
			_bad("바위 몬스터가 전기에 죽었다 — 면역이 안 걸린다")
		else:
			var m0: Dictionary = sim2.monsters[0]
			if absf(float(m0["hp"]) - hp0) > EPS:
				_bad("바위 몬스터의 hp 가 %.3f 깎였다 — 전기는 0배여야 한다" % (hp0 - float(m0["hp"])))
			if float(m0["stun_t"]) > 0.0 or float(m0["stun_cd"]) > 0.0:
				_bad("면역인데 마비가 걸렸다 (CLAUDE.md 5-6)")
			if float(m0["flash"]) > 0.0:
				_bad("면역인데 붉게 번쩍인다 (CLAUDE.md 5-6)")
			else:
				print("   바위 x 전기 %d초: hp 그대로 · 마비 없음 · 번쩍임 없음" % 10)

	# (6) 화면보다 굵게 돌려도 결과가 같은가 (장판의 dt 의존 결함이 실제로 있었다)
	print("\n6. 한 걸음(dt)을 바꿔도 총 피해가 같은가 — 장판의 dt 의존을 잡는 검사")
	# ★ 장판(aura)을 반드시 하나 넣는다 — dt 에 매인 결함이 실제로 났던 자리가 거기다
	#   (BattleSim._hurt 의 rider_dmg 주석: dt=1/30 과 1/60 에서 화상 세기가 두 배 달랐다).
	# 불 단발 하나(화상이 dt 에 매였던 자리)와 **장판** 하나. 장판은 매 프레임 때리고
	# 상태이상은 0.25초 틱에만 붙이므로, dt 의존 결함이 나면 여기서만 난다.
	for uid in [_find("shot", "fire"), _find("zone", "fire")]:
		if String(uid) == "":
			continue
		var tot := []
		for dt in [1.0 / 60.0, 1.0 / 30.0, 0.02]:
			if not _setup([{"id": uid, "n": 2}], {}, [], 8, 555):
				continue
			var s := Tracer.new()
			s.setup(Run, 8, 555)
			var g := 0
			while not s.done and g < 30000:
				s.step(dt)
				s.events.clear()
				g += 1
			var sum := 0.0
			for r in s.rows:
				sum += float(r["got"])
			tot.append(sum)
		if tot.size() == 3:
			var spread: float = (tot.max() - tot.min()) / maxf(1.0, tot.max())
			print("   %-20s dt 1/60 %.0f · 1/30 %.0f · 0.02 %.0f   (벌어짐 %.1f%%)"
					% [uid, tot[0], tot[1], tot[2], spread * 100.0])
			if spread > 0.35:
				_bad("%s: dt 를 바꿨더니 총 피해가 %.0f%% 나 달라진다 — 프레임에 매인 계산이 있다" % [uid, spread * 100.0])

	# (7) 겹침이 **실제 전투에서** 몇 배로 들어가는가 — 대상이 하나뿐일 때
	#
	# 중복 카드는 별도 재료이며 기존 n 필드가 출전 영웅의 화력을 늘리면 안 된다.
	print("\n7. 기존 중첩 데이터에도 실제 단일 대상 피해가 일정한가")
	print("   %-22s %-8s %-10s %-10s %s" % ["캐릭터", "방식", "x1 피해", "x4 피해", "실제 배수 (기대)"])
	var probe_kinds := _one_per_bullet(["shot", "pierce", "splash", "chain", "beam",
			"ricochet", "zone"])
	for uid in probe_kinds:
		var u0: Dictionary = Roster.unit_by_id(uid)
		if u0.is_empty():
			continue
		var bk0 := String(u0.get("bullet", "shot"))
		var got := []
		for nn in [1, 4]:
			if not _setup([{"id": uid, "n": nn}], {}, [], 40, 909090):
				continue
			got.append(_solo_damage(40, 909090))
		if got.size() < 2 or float(got[0]) <= 0.0:
			_bad("%s: 한 대도 안 때렸다 — 검사가 아무것도 안 재고 있다" % uid)
			continue
		var ratio: float = float(got[1]) / float(got[0])
		var want: float = 1.0
		var ok: bool = absf(ratio - want) <= 0.02 * want
		print("   %-22s %-8s %-10.1f %-10.1f x%.2f  (기대 x%.2f) %s"
				% [String(u0["ko"]), String(Balance.BULLET[bk0]["ko"]),
				   float(got[0]), float(got[1]), ratio, want, "" if ok else "!! 어긋남"])
		if not ok:
			_bad("%s(%s): 겹침 x4 가 대상 하나에게 x%.2f 로 들어간다 (기대 x%.2f)"
					% [uid, bk0, ratio, want])


	# (8) 추적이 **하나도 안 놓쳤는가** — 하네스 자신을 재는 검사다.
	#
	# ★ heroes[i]["dmg"] 는 `_credit()` 으로만 쌓이고, 부르는 곳은 둘뿐이다 — `_hurt` 와
	#   화상 도트(`_move_monsters`). 화상도 **붙인 영웅의 몫**이라 임자가 있는 화상은
	#   전과판에 들어간다. 그러니 「src 가 있는 행의 합 == 전과판의 합」이 정확히 성립해야
	#   한다. 안 맞으면 `_credit` 을 안 거치고 hp 를 깎는 자리가 새로 생겼다는 뜻이다 —
	#   그게 이 게임에서 제일 위험한 변경이다(CLAUDE.md 5-1).
	# ★ src 가 -1 인 화상은 임자 없는 것뿐이다(들불이 옮아 붙었는데 눕힌 영웅이 없는 경우).
	print("\n8. 추적이 하나도 안 놓쳤는가 (src 있는 행의 합 == BattleSim 의 전과판 합)")
	# ★ id 를 못 박지 않는다 — 불(화상이 _hurt 를 안 거치는 유일한 예외다)과 전기를 하나씩.
	var f8 := _find("", "fire")
	var e8 := _find("", "elec")
	if f8 != "" and e8 != "" \
			and _setup([{"id": f8, "n": 2}, {"id": e8, "n": 1}], {}, [], 16, 13579):
		var s8 := Tracer.new()
		s8.setup(Run, 16, 13579)
		var g8 := 0
		while not s8.done and g8 < 40000:
			s8.step(1.0 / 60.0)
			s8.events.clear()
			g8 += 1
		var mine := 0.0
		var burn := 0.0
		for r in s8.rows:
			if int(r["src"]) >= 0:
				mine += float(r["got"])
			else:
				burn += float(r["got"])
		var theirs := 0.0
		for he in s8.heroes:
			theirs += float(he["dmg"])
		var ok8: bool = absf(mine - theirs) <= maxf(0.01, theirs * 1e-5)
		print("   추적 %.2f · 전과판 %.2f · 임자 없는 피해(전과판 밖) %.2f   %s"
				% [mine, theirs, burn, "일치" if ok8 else "!! 어긋남"])
		if not ok8:
			_bad("추적 합계 %.4f 와 전과판 합계 %.4f 가 다르다 — _hurt 를 안 거치고 hp 를 깎는 자리가 있다" % [mine, theirs])
	else:
		_bad("판을 못 세웠다")

	print("")
	if _fail == 0:
		print("판정: 정상")
	else:
		print("판정: 실패 %d건" % _fail)
	print("")



## 몬스터를 **딱 하나만** 세워 놓고, 그 하나에게 12초 동안 들어간 피해를 잰다.
##
## ★ 화상은 안 센다 — 화상은 max() 로 덮어쓰므로 겹쳐도 선형으로 안 늘고, 그러면
##   「공격 자체가 몇 배로 나가는가」를 재는 이 검사가 흐려진다. 직격·광선·장판만 센다.
## ★ 체력을 크게 올려 두는 까닭: 죽어 버리면 그 뒤로 안 때려서 x1 과 x4 의 시간이 달라진다.
func _solo_damage(w: int, seed_value: int) -> float:
	var sim := Tracer.new()
	sim.setup(Run, w, seed_value)
	sim.monsters.clear()
	sim._queue.clear()
	var target: Dictionary = {}
	for m in Roster.MONSTERS:
		if String(m.get("kind", "")) == "tank":
			target = m
			break
	sim._spawn(target)
	sim.monsters[0]["hp"] = 1e12
	sim.monsters[0]["max"] = 1e12
	# Keep the target stationary beside a real post, inside every tested weapon's range.
	sim.monsters[0]["s"] = 360.0
	sim.monsters[0]["spd"] = 0.0
	sim.monsters[0]["off"] = 0.0
	sim.move_hero(0, 1)
	var steps := int(12.0 * 60.0)
	for i in range(steps):
		sim.step(1.0 / 60.0)
		sim.events.clear()
		if sim.monsters.is_empty():
			break
	var sum := 0.0
	for r in sim.rows:
		var c := String(r["ctx"])
		if c == "직격" or c == "광선" or c == "장판":
			sum += float(r["got"])
	return sum

# --------------------------------------------------------------------------- #
# 4) --table / --list
# --------------------------------------------------------------------------- #
func _table() -> void:
	print("\n========== 상성표 (세로=공격 속성 · 가로=몬스터 몸) ==========")
	var head := "   %-10s" % "공격\\몸"
	for b in Balance.MBODY_ORDER:
		head += "%-10s" % ("%s %s" % [Balance.body_ko(String(b)), b])
	print(head)
	for el in Balance.ELEM_ORDER:
		var line := "   %-10s" % ("%s %s" % [Balance.elem_ko(String(el)), el])
		for b in Balance.MBODY_ORDER:
			var m: float = Balance.elem_mult(String(el), String(b))
			line += "%-10s" % ("x%.1f%s" % [m, "" if m != 0.0 else " 면역"])
		print(line)
	print("\n   속성 기본화력 (Balance.ELEM 의 dmg) · 붙는 상태이상")
	for el in Balance.ELEM_ORDER:
		var rid := Balance.elem_rider(String(el))
		var d := "—"
		match rid:
			"burn": d = "화상 — 한 대의 %.0f%% 를 초당 %.0f초" % [float(Balance.STATUS["burn"]["amount"]) * 100.0, float(Balance.STATUS["burn"]["sec"])]
			"slow": d = "둔화 — %.0f%% · %.0f초" % [float(Balance.STATUS["slow"]["amount"]) * 100.0, float(Balance.STATUS["slow"]["sec"])]
			"stun": d = "마비 — %.0f%% 확률 %.1f초 (보스 x%.2f · 재우는 시간 %.1f초)" % [float(Balance.STATUS["stun"]["chance"]) * 100.0, float(Balance.STATUS["stun"]["sec"]), Balance.BOSS_STUN_MUL, Balance.STUN_IMMUNE_SEC]
		print("   %-10s x%.2f   %s" % [Balance.elem_ko(String(el)), Balance.elem_dmg(String(el)), d])

	print("\n========== 탄 방식 ==========")
	print("   %-10s %-8s %-8s %s" % ["방식", "피해배수", "속도", "덤"])
	for k in Balance.BULLET:
		var b: Dictionary = Balance.BULLET[k]
		var extra := []
		for key in ["pierce", "radius", "falloff", "jumps", "decay", "hop",
				"bounce", "cast", "delay", "dur", "tick"]:
			if b.has(key):
				extra.append("%s %s" % [key, b[key]])
		print("   %-10s %-8.3f %-8.0f %s" % [String(b["ko"]) + "(" + String(k) + ")",
				float(b["dmg"]), float(b["speed"]), ", ".join(PackedStringArray(extra))])

	print("\n========== 등급별 기본 화력 ==========")
	print("   %-4s %-16s %-10s %-10s %s" % ["등급", "족보", "TIER_ATK", "TIER_RATE", "그 등급 캐릭터"])
	for t in range(10):
		var names := []
		for u in Roster.units_of_tier(t):
			names.append(String(u["ko"]))
		print("   %-4d %-16s %-10.1f %-10.2f %s" % [t, Roster.TIER_KO[t],
				Balance.TIER_ATK[t], Balance.TIER_RATE[t], ", ".join(PackedStringArray(names))])

	print("\n========== 체력 곡선 ==========")
	print("   %-6s %-12s %-8s %-14s %-10s %s" % ["탄", "기준 체력", "마릿수", "합", "처치골드", "보스"])
	for w in [1, 2, 3, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]:
		print("   %-6d %-12.1f %-8d %-14.0f %-10d %s"
				% [w, Balance.wave_hp(w), Balance.wave_count(w),
				   Balance.wave_hp(w) * Balance.wave_count(w),
				   Balance.kill_gold(w, "swarm"),
				   "보스(x%.0f 체력 · 크리스탈 %d개)" % [float(Balance.MKIND["boss"]["hp"]), int(Balance.MKIND["boss"]["crush"])] if Balance.is_boss_wave(w) else ""])
	print("")


func _list() -> void:
	print("\n캐릭터 %d명" % Roster.UNITS.size())
	for t in range(10):
		for u in Roster.units_of_tier(t):
			print("   %-22s %-4d %-16s %-6s %-8s %s"
					% [String(u["id"]), t, Roster.TIER_KO[t],
					   Balance.elem_ko(String(u.get("elem", "none"))),
					   String(Balance.BULLET[String(u.get("bullet", "shot"))]["ko"]),
					   String(u["ko"])])
	print("\n몬스터 %d종" % Roster.MONSTERS.size())
	for m in Roster.MONSTERS:
		print("   %-20s %-8s %-6s %s" % [String(m["id"]), String(m["kind"]),
				Balance.body_ko(String(m.get("body", ""))), String(m["ko"])])
	print("\n패시브 %d장" % Balance.PASSIVES.size())
	for p in Balance.PASSIVES:
		print("   %-14s rank%d %-8d %-14s %s" % [String(p["id"]), int(p["rank"]),
				int(p["cost"]), String(p["ko"]), String(p["desc"])])
	print("")


func _usage() -> void:
	print("""
데미지 계산 검사기 — POCKER_NO_SAVE=1 godot --headless --path . res://tests/dmg_check.tscn -- <모드>

  --calc      한 대의 곱셈 사슬을 편다 (기본)
      --unit <id>       캐릭터 (기본 match_gunner)
      --n <겹>          겹친 수 (기본 1)
      --wave <탄>       맞는 쪽을 이 탄으로 (기본 1)
      --rank <1~5>      테마의 험한 정도 (기본 1)
      --mkind <종류>    swarm|fast|tank|caster|boss (기본 swarm)
      --lv atk=7,rate=5,crit=4,critx=3
      --pas heavytip,repeater,keenedge
      --crit            치명타가 터진 값으로 계산

  --trace     실제 전투 한 탄을 돌려 hp 가 깎이는 것을 전부 찍는다
      --wave <탄>       (기본 12)
      --team a:2,b:1    성역에 세울 캐릭터 (기본 --unit 하나)
      --seed <씨앗>     (기본 20260829)
      --dt <걸음>       (기본 1/60)
      --max <줄>        찍을 줄 수 (기본 50)
      --hero <번호>     그 영웅 것만
      --lv / --pas      --calc 과 같다

  --selftest  산수와 실제 전투가 같은 값인가 (판정: 정상 이 나와야 한다)
  --table     상성표 · 탄 방식 · 등급별 화력 · 체력 곡선
  --list      캐릭터 / 몬스터 / 패시브 id 목록
""")
