extends BattleSim
class_name Dbg3

var born: Dictionary = {}    # bid -> 생성 시각
var hits: Dictionary = {}
var _bid: int = 0
var life_1hit: Array = []
var life_full: Array = []
var still_homing_after_hit: int = 0
var hit_total: int = 0

func _shoot(hi: int, tgt: int, dmg: float, kind: String, crit: bool) -> void:
	var before := bullets.size()
	super(hi, tgt, dmg, kind, crit)
	if bullets.size() > before and String(bullets[-1]["kind"]) == "pierce":
		var b: Dictionary = bullets[-1]
		b["bid"] = _bid
		born[_bid] = elapsed
		hits[_bid] = 0
		_bid += 1

func _impact(b: Dictionary, mi: int) -> void:
	if b.has("bid"):
		hits[int(b["bid"])] = int(hits[int(b["bid"])]) + 1
		hit_total += 1
		# 방금 때린 놈이 계속 이 탄의 유도 목표인가?
		if int(b["tgt"]) == mi:
			still_homing_after_hit += 1
	super(b, mi)

func _move_bullets(dt: float) -> void:
	var live := {}
	for b in bullets:
		if b.has("bid"):
			live[int(b["bid"])] = true
	super(dt)
	var now := {}
	for b in bullets:
		if b.has("bid"):
			now[int(b["bid"])] = true
	for bid in live:
		if not now.has(bid):
			var age: float = elapsed - float(born[bid])
			if int(hits[bid]) == 1:
				life_1hit.append(age)
			elif int(hits[bid]) >= int(3):
				life_full.append(age)
