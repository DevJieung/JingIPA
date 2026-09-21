extends BattleSim
class_name DbgSim

## 전투를 **들여다볼 수 있게 한 겹 씌운** 시뮬레이터.
##
## ★ **game/battle_sim.gd 에는 한 줄도 안 넣는다.** GDScript 는 메서드가 전부 가상이라,
##   부모 안에서 부른 `_hurt()` 도 여기 override 로 온다. 그래서 사건(events)을 안
##   흘리는 자리 — 광역의 둘레 · 연쇄의 두 번째 홉 · 분열 조각 · 장판 — 까지 **hp 가
##   깎이는 모든 자리**를 하나도 안 놓치고 볼 수 있다.
##   (게임 코드에 print 를 박으면 자동 플레이 검사가 초당 수천 줄을 뱉어 몇 배로 느려지고,
##    지우는 것을 잊으면 APK 에 그대로 실린다)
##
## ★ **꺼져 있으면 값이 한 톨도 안 달라진다.** 모든 override 의 첫 줄이
##   `if not Dbg.on:` 이라 곧장 super() 로 빠진다. tests/balance_check 는 아예 이
##   클래스를 안 쓰고 BattleSim 을 그대로 만들므로 자동 플레이 속도도 그대로다.

## 지금 어느 길로 들어온 피해인가. 아래 override 들이 갈아 끼우기만 한다 —
## **계산은 한 줄도 안 바꾼다.**
var _ctx: String = "?"


# --- 어느 길로 들어왔는가 (라벨만 붙인다) ------------------------------------ #
func _heroes_fire(dt: float) -> void:
	if Dbg.on:
		_ctx = "장판"      # 장판은 _heroes_fire 안에서 곧장 _hurt 를 부른다
	super(dt)


func _move_bullets(dt: float) -> void:
	if Dbg.on:
		_ctx = "직격"
	super(dt)


func _shoot(hi: int, tgt: int, dmg: float, kind: String, crit: bool, shots: int = 1) -> void:
	if not Dbg.on:
		super(hi, tgt, dmg, kind, crit, shots)
		return
	var old := _ctx
	if kind == "beam":
		_ctx = "광선"
	super(hi, tgt, dmg, kind, crit, shots)
	_ctx = old


func _impact(b: Dictionary, mi: int) -> void:
	if not Dbg.on:
		super(b, mi)
		return
	var old := _ctx
	_ctx = "직격"
	super(b, mi)
	_ctx = old


func _splash(skip: int, at: Vector2, radius: float, dmg: float, src: int,
		elem: String = "none") -> void:
	if not Dbg.on:
		super(skip, at, radius, dmg, src, elem)
		return
	var old := _ctx
	_ctx = "광역"
	super(skip, at, radius, dmg, src, elem)
	_ctx = old


func _chain(from_i: int, dmg: float, jumps: int, decay: float, hop: float,
		seen: Array, col: Color, src: int, elem: String = "none", shot_src: int = -1) -> void:
	if not Dbg.on:
		super(from_i, dmg, jumps, decay, hop, seen, col, src, elem, shot_src)
		return
	var old := _ctx
	_ctx = "연쇄"
	super(from_i, dmg, jumps, decay, hop, seen, col, src, elem, shot_src)
	_ctx = old


func _zone_hit(z: Dictionary) -> void:
	if not Dbg.on:
		super(z)
		return
	var old := _ctx
	_ctx = "장판"
	super(z)
	_ctx = old


func _field_extras(mi: int, dmg: float) -> void:
	if not Dbg.on:
		super(mi, dmg)
		return
	var old := _ctx
	_ctx = "패시브"
	super(mi, dmg)
	_ctx = old


# --- 본체: hp 가 깎이는 유일한 자리를 앞뒤로 잰다 ---------------------------- #
func _hurt(mi: int, dmg: float, _crit: bool, _src: int, elem: String = "none",
		rider: bool = true, rider_dmg: float = -1.0, rider_n: int = 1,
		flash: bool = true) -> float:
	if not Dbg.on or mi < 0 or mi >= monsters.size():
		return super(mi, dmg, _crit, _src, elem, rider, rider_dmg, rider_n, flash)
	var mo: Dictionary = monsters[mi]
	var hp0: float = float(mo["hp"])
	var em: float = super(mi, dmg, _crit, _src, elem, rider, rider_dmg, rider_n, flash)
	Dbg.push({
		"t": elapsed, "ctx": _ctx, "src": _src,
		"name": String(mo["m"].get("ko", "?")),
		"body": String(mo.get("body", "")), "elem": elem,
		"req": dmg, "em": em, "crit": _crit,
		"got": hp0 - float(mo["hp"]), "hp1": float(mo["hp"]), "max": float(mo["max"]),
	})
	return em


## 화상 도트는 `_hurt` 를 안 거치고 `_move_monsters` 가 hp 를 직접 깎는다
## (CLAUDE.md 5-1 의 유일한 예외). 걸음 앞뒤를 재는 것이 그것을 보는 유일한 길이다.
##
## ★ 임자(src)는 몬스터가 들고 있는 `burn_src` 다 — 화상도 붙인 영웅의 몫으로 세므로
##   여기서 -1 로 적으면 디버그 표만 「임자 없는 피해」로 보인다.
##
## ★ 담는 그릇은 반드시 **PackedFloat64Array** 다. hp 는 64비트인데 32비트로 깎아 담고
##   되돌리면 1e-6 쯤이 남아서, 화상이 안 붙은 몬스터까지 **매 걸음** 「깎였다」로 잡힌다.
func _move_monsters(dt: float) -> void:
	if not Dbg.on:
		super(dt)
		return
	var n := monsters.size()
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
		Dbg.push({
			"t": elapsed, "ctx": "화상", "src": int(mo.get("burn_src", -1)),
			"name": String(mo["m"].get("ko", "?")),
			"body": String(mo.get("body", "")), "elem": "fire",
			"req": d, "em": 1.0, "crit": false,
			"got": d, "hp1": float(mo["hp"]), "max": float(mo["max"]),
		})
