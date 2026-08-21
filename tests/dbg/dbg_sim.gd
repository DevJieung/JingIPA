extends BattleSim
class_name DbgSim

var errors: Array = []
var _uid: int = 0
var _bid: int = 0
var hits_by_uid: Dictionary = {}


func _spawn(m: Dictionary) -> void:
	super(m)
	monsters[-1]["uid"] = _uid
	_uid += 1


func _shoot(hi: int, tgt: int, dmg: float, kind: String, crit: bool) -> void:
	var before := bullets.size()
	super(hi, tgt, dmg, kind, crit)
	if bullets.size() > before:
		var b: Dictionary = bullets[-1]
		b["bid"] = _bid
		b["hituid"] = []
		b["tguid"] = int(monsters[tgt]["uid"])
		_bid += 1


func _impact(b: Dictionary, mi: int) -> void:
	if mi >= 0 and mi < monsters.size() and b.has("hituid"):
		var u := int(monsters[mi]["uid"])
		var hu: Array = b["hituid"]
		if hu.has(u):
			errors.append("DOUBLE-HIT bid=%d uid=%d kind=%s" % [int(b["bid"]), u, String(b["kind"])])
		hu.append(u)
	super(b, mi)


func _reap() -> void:
	var tgmap := {}
	var hitmap := {}
	var alive_before := {}
	for i in range(monsters.size()):
		alive_before[int(monsters[i]["uid"])] = float(monsters[i]["hp"])
	for b in bullets:
		tgmap[int(b["bid"])] = int(b["tguid"])
		var s := []
		for x in (b["hit"] as Array):
			s.append(int(monsters[int(x)]["uid"]))
		hitmap[int(b["bid"])] = s
	super()
	var uid_at := {}
	for i in range(monsters.size()):
		uid_at[int(monsters[i]["uid"])] = i
	for b in bullets:
		var bid := int(b["bid"])
		var want: int = tgmap[bid]
		var t := int(b["tgt"])
		if t >= 0:
			if t >= monsters.size():
				errors.append("TGT OUT OF RANGE bid=%d t=%d n=%d" % [bid, t, monsters.size()])
			elif int(monsters[t]["uid"]) != want:
				errors.append("TGT REMAP WRONG bid=%d got uid %d want %d"
						% [bid, int(monsters[t]["uid"]), want])
		else:
			if uid_at.has(want):
				errors.append("TGT DROPPED though target alive bid=%d uid=%d" % [bid, want])
		# hit 목록: 살아남은 uid 집합이 그대로 유지되어야 한다
		var expect := []
		for u in hitmap[bid]:
			if uid_at.has(int(u)):
				expect.append(uid_at[int(u)])
		var got := []
		for x in (b["hit"] as Array):
			got.append(int(x))
		expect.sort()
		got.sort()
		if str(expect) != str(got):
			errors.append("HITLIST REMAP WRONG bid=%d expect=%s got=%s" % [bid, str(expect), str(got)])
		for x in got:
			if x >= monsters.size():
				errors.append("HITLIST OUT OF RANGE bid=%d x=%d n=%d" % [bid, x, monsters.size()])
