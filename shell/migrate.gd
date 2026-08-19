class_name Migrate
extends RefCounted

## 옛 저장 파일 -> 통합 스키마 v3.
##
## 전부 순수 함수다 — 씬도 파일 접근도 없이 딕셔너리만 받고 딕셔너리를 돌려준다.
## 그래야 화면 없는 서버에서 tests/ 가 전 경우를 돌려 볼 수 있다.
## (이관은 한 번 잘못되면 아이 기록이 사라지는 코드라 반드시 테스트가 있어야 한다.)


## 옛 파일들을 모은 것을 받아 통합 저장 딕셔너리를 만든다.
##   legacy = {"frog": <save.json 을 파싱한 것>, "dino": {"best_stage":.., "found":..}}
static func build(legacy: Dictionary) -> Dictionary:
	var frog: Dictionary = legacy.get("frog", {})
	var dino: Dictionary = legacy.get("dino", {})

	var best_stage := maxi(1, int(dino.get("best_stage", 1)))
	var found := maxi(0, int(dino.get("found", 0)))

	var stars := _int_dict(frog.get("stars", {}))
	var totals := _totals(frog.get("totals", {}))
	var has_frog := not stars.is_empty() or int(totals["correct"]) > 0
	var has_dino := best_stage > 1 or found > 0

	# 나이대 추론: t3 이상을 깼으면 초등으로 본다.
	var band := "elem"
	if has_frog:
		var top := -1
		for k in stars:
			top = maxi(top, int(k))
		band = "elem" if top >= 2 else "pre"

	var p := Shell.new_profile("p_1", "trex", band)
	if has_frog:
		var settings: Dictionary = frog.get("settings", {})
		p["tuning"]["fast_animation"] = bool(settings.get("fast_animation", false))
		p["tuning"]["skip_demo"] = bool(settings.get("skip_demo", false))
		p["tuning"]["session_limit"] = int(settings.get("session_limit", Shell.DEFAULT_SESSION_LIMIT))
		p["math"] = {
			"stars": stars,
			"stats": _stats(frog.get("stats", {})),
			"error_tags": _int_dict(frog.get("error_tags", {})),
			"totals": totals,
			"endless_best": int(frog.get("endless_best", 0)),
			"last_tier": int(frog.get("last_tier", 0)),
			"adapt_d": {}, "adapt_m": {},
		}
	p["dino"]["best_stage"] = best_stage
	p["dino"]["lifetime_found"] = found

	# ── "이사 온 날" ────────────────────────────────────────────────────────
	# 옛 저장에는 종별 기록이 아예 없었다(정수 두 개뿐). 없는 것을 지어내지는 않되,
	# 254마리를 찾은 아이에게 도감 0/50 을 보여 주면 "예전 게임이 없어졌다"로 읽는다.
	# 셔플백은 50번마다 전 종을 정확히 한 바퀴 돌리므로, 한 바퀴 이상 돌았다면
	# "전 종을 만난 적이 있다"는 통계적으로 참이다. 만난 것(회색)까지만 채우고
	# 식구(컬러)는 앞쪽 몇 종만 — 도감이 첫날에 끝나 버리면 채울 칸이 없어진다.
	var dex := {}
	var device_settings: Dictionary = frog.get("settings", {})
	if found >= DinoSpecies.count():
		var family := clampi(found / 32, 0, 10)
		for i in DinoSpecies.count():
			var id := String(DinoSpecies.data(i)["id"])
			dex[id] = {
				"first_by": "p_1",
				"first_at": 0,
				"count": Shell.FAMILY_MEETS if i < family else 1,
			}
		p["dino"]["dex_first_count"] = dex.size()

	return {
		"schema": Shell.SCHEMA,
		"app": "rogame",
		"migrated": has_frog or has_dino,
		"device": {
			"sfx": bool(device_settings.get("sfx", true)),
			"bgm": bool(device_settings.get("bgm", true)),
			"reduce_motion": bool(device_settings.get("reduce_motion", false)),
			"language": "en" if String(device_settings.get("language", "ko")) == "en" else "ko",
			"last_profile": "p_1",
			"last_played_unix": 0,
		},
		"shared": {
			"dex": dex,
			"dex_head_start": found,
			"dex_greeted": false,
		},
		# 두 번째 프로필은 자동으로 만들지 않는다 — 자동 분할하면
		# 형 기록이 반으로 잘린 것처럼 보인다. 부모가 "+" 로 만든다.
		"profiles": [p],
	}


## 저장 파일에서 읽은 프로필 하나를 온전한 모양으로 맞춘다.
## JSON 은 정수를 float 으로 돌려주므로 반드시 int() 로 다시 조인다.
static func normalize_profile(raw: Variant) -> Dictionary:
	var r: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var band := String(r.get("age_band", "elem"))
	if band != "pre":
		band = "elem"
	var p := Shell.new_profile(
		String(r.get("id", "p_1")),
		String(r.get("badge_species", "trex")),
		band)
	p["created_at"] = int(r.get("created_at", 0))
	p["ephemeral"] = bool(r.get("ephemeral", false))

	var t: Dictionary = r.get("tuning", {})
	for k in p["tuning"]:
		if t.has(k):
			var def: Variant = p["tuning"][k]
			match typeof(def):
				TYPE_BOOL: p["tuning"][k] = bool(t[k])
				TYPE_INT: p["tuning"][k] = int(t[k])
				TYPE_FLOAT: p["tuning"][k] = float(t[k])
				_: p["tuning"][k] = t[k]

	var m: Dictionary = r.get("math", {})
	p["math"] = {
		"stars": _int_dict(m.get("stars", {})),
		"stats": _stats(m.get("stats", {})),
		"error_tags": _int_dict(m.get("error_tags", {})),
		"totals": _totals(m.get("totals", {})),
		"endless_best": int(m.get("endless_best", 0)),
		"last_tier": int(m.get("last_tier", 0)),
		"adapt_d": _int_dict(m.get("adapt_d", {})),
		"adapt_m": _int_dict(m.get("adapt_m", {})),
	}

	var dn: Dictionary = r.get("dino", {})
	p["dino"] = {
		"best_stage": maxi(1, int(dn.get("best_stage", 1))),
		"lifetime_found": maxi(0, int(dn.get("lifetime_found", 0))),
		"dex_first_count": maxi(0, int(dn.get("dex_first_count", 0))),
		"skill": clampi(int(dn.get("skill", 0)), -8, 10),
		"ease_streak": maxi(0, int(dn.get("ease_streak", 0))),
		"cushion": maxi(0, int(dn.get("cushion", 0))),
		"journey_best": maxi(1, int(dn.get("journey_best", 1))),
	}

	var kn: Dictionary = r.get("kanoodle", {})
	p["kanoodle"] = {
		"best_stage": maxi(1, int(kn.get("best_stage", 1))),
		"skill": clampi(int(kn.get("skill", 0)), -6, 10),
		"cleared": maxi(0, int(kn.get("cleared", 0))),
	}

	# ★ 여기 안 적힌 키는 앱을 다시 켤 때마다 **통째로 사라진다.**
	#   normalize_profile 은 new_profile() 로 새 딕셔너리를 만든 뒤 아는 키만 베껴 넣기
	#   때문이다. 새 게임을 넣을 때 가장 조용히 물리는 자리 — 어떤 검사도 안 잡아 준다.
	var ch: Dictionary = r.get("cham", {})
	p["cham"] = {
		"best_stage": maxi(1, int(ch.get("best_stage", 1))),
		"caught": maxi(0, int(ch.get("caught", 0))),
		"skill": clampi(int(ch.get("skill", 0)), -8, 10),
		"ease_streak": maxi(0, int(ch.get("ease_streak", 0))),
		"cushion": maxi(0, int(ch.get("cushion", 0))),
	}

	var tc: Dictionary = r.get("torch", {})
	p["torch"] = {
		"best_stage": maxi(1, int(tc.get("best_stage", 1))),
		"lifetime_found": maxi(0, int(tc.get("lifetime_found", 0))),
		"skill": clampi(int(tc.get("skill", 0)), -8, 10),
		"ease_streak": maxi(0, int(tc.get("ease_streak", 0))),
		"cushion": maxi(0, int(tc.get("cushion", 0))),
	}

	p["daily"] = []
	for row in (r.get("daily", []) as Array):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		p["daily"].append({
			"d": String((row as Dictionary).get("d", "")),
			"sec": int((row as Dictionary).get("sec", 0)),
			"q": int((row as Dictionary).get("q", 0)),
			"correct": int((row as Dictionary).get("correct", 0)),
			"dino": int((row as Dictionary).get("dino", 0)),
			"nood": int((row as Dictionary).get("nood", 0)),
			"torch": int((row as Dictionary).get("torch", 0)),
			"cham": int((row as Dictionary).get("cham", 0)),
		})
	while p["daily"].size() > 14:
		p["daily"].pop_front()
	return p


static func _int_dict(src: Variant) -> Dictionary:
	var out := {}
	if typeof(src) != TYPE_DICTIONARY:
		return out
	for k in (src as Dictionary):
		out[String(k)] = int((src as Dictionary)[k])
	return out


static func _stats(src: Variant) -> Dictionary:
	var out := {}
	if typeof(src) != TYPE_DICTIONARY:
		return out
	for k in (src as Dictionary):
		var e: Variant = (src as Dictionary)[k]
		if typeof(e) == TYPE_ARRAY and (e as Array).size() >= 2:
			out[String(k)] = [int(e[0]), int(e[1])]
	return out


static func _totals(src: Variant) -> Dictionary:
	var t: Dictionary = src if typeof(src) == TYPE_DICTIONARY else {}
	return {
		"correct": int(t.get("correct", 0)),
		"wrong": int(t.get("wrong", 0)),
		"tiers_cleared": int(t.get("tiers_cleared", 0)),
		"snakes": int(t.get("snakes", 0)),
		"seconds": float(t.get("seconds", 0.0)),
	}
