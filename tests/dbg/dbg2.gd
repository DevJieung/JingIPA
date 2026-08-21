extends BattleSim
class_name Dbg2

var errors: Array = []
var pierce_made: int = 0
var pierce_hits: Dictionary = {}   # bid -> 명중 수
var pierce_cap: Dictionary = {}
var _bid: int = 0
var aura_no_extras: int = 0

func _shoot(hi: int, tgt: int, dmg: float, kind: String, crit: bool) -> void:
	if _mp.size() != monsters.size():
		errors.append("STALE _mp in _shoot: %d vs %d" % [_mp.size(), monsters.size()])
	var before := bullets.size()
	super(hi, tgt, dmg, kind, crit)
	if bullets.size() > before:
		var b: Dictionary = bullets[-1]
		b["bid"] = _bid
		if String(b["kind"]) == "pierce":
			pierce_made += 1
			pierce_hits[_bid] = 0
			pierce_cap[_bid] = int(b["pierce"])
		_bid += 1

func _impact(b: Dictionary, mi: int) -> void:
	if _mp.size() != monsters.size():
		errors.append("STALE _mp in _impact: %d vs %d" % [_mp.size(), monsters.size()])
	if b.has("bid") and pierce_hits.has(int(b["bid"])):
		pierce_hits[int(b["bid"])] = int(pierce_hits[int(b["bid"])]) + 1
	super(b, mi)

func _hurt(mi: int, dmg: float, crit: bool, src: int) -> void:
	if mi >= monsters.size() or mi < 0:
		errors.append("HURT OUT OF RANGE mi=%d n=%d" % [mi, monsters.size()])
	super(mi, dmg, crit, src)
