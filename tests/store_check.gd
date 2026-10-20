extends Harness

## Purchases: what a build without a shop does, the one product for sale (the Guardian's
## blessing, the DLC: revival tickets that each bring a five-star hero, never gold — 2026-10-19 D2),
## battle speed staying free,
## and the three shop backends driven through stand-in clients that speak the same
## signals and methods as the real plugins.

## A shop that answers at once, for the game-rule checks.
class TestShop extends RefCounted:
	const NAME := "test"
	var store: Node
	var selling := true
	var answer := "ok"
	var owned: Array = []
	var asked := 0
	func start() -> void:
		store.set_price("guardian", "T1")
		store.set_owned(owned)
	func sells(_id: String) -> bool: return selling
	func refresh() -> void: store.set_owned(owned)
	func restore() -> void:
		store.set_owned(owned)
		store.finish_restore(true)
	func buy(product: Dictionary) -> void:
		asked += 1
		var id := String(product["id"])
		if answer == "ok":
			owned.append(id)
			store.grant(id)
		elif answer != "hang":
			store.finish_purchase(id, answer)

## Stand-in for addons/GodotGooglePlayBilling BillingClient.
class PlayClient extends RefCounted:
	signal connected
	signal disconnected
	signal connect_error(response_code: int, debug_message: String)
	signal query_product_details_response(response: Dictionary)
	signal query_purchases_response(response: Dictionary)
	signal on_purchase_updated(response: Dictionary)
	var online := true
	var up := false
	var connects := 0
	var purchases: Array = []
	var acknowledged: Array = []
	var flow := "ok"
	func start_connection() -> void:
		connects += 1
		if online:
			up = true
			connected.emit()
		else:
			connect_error.emit(3, "billing unavailable")
	func end_connection() -> void: up = false
	func is_ready() -> bool: return up
	func query_product_details(list: PackedStringArray, _type: int) -> void:
		var details: Array = []
		for sku in list:
			details.append({"product_id": sku, "title": sku, "one_time_purchase_offer_details_list": [{"formatted_price": "W1100"}]})
		query_product_details_response.emit({"response_code": 0, "product_details": details})
	func query_purchases(_type: int, _suspended: bool = false) -> void:
		query_purchases_response.emit({"response_code": 0, "purchases": purchases.duplicate(true)})
	func _record(sku: String, state: int) -> Dictionary:
		return {"purchase_token": "token-" + sku, "purchase_state": state, "is_acknowledged": false, "product_ids": PackedStringArray([sku])}
	func purchase(sku: String, _option: String = "", _offer: String = "", _personal: bool = false) -> Dictionary:
		match flow:
			"ok":
				purchases.append(_record(sku, 1))
				on_purchase_updated.emit({"response_code": 0, "purchases": [purchases[-1].duplicate(true)]})
			"cancel": on_purchase_updated.emit({"response_code": 1, "purchases": []})
			"pending":
				purchases.append(_record(sku, 2))
				on_purchase_updated.emit({"response_code": 0, "purchases": [purchases[-1].duplicate(true)]})
			"owned":
				purchases.append(_record(sku, 1))
				on_purchase_updated.emit({"response_code": 7, "purchases": []})
			"refuse": return {"response_code": 5}
		return {"response_code": 0}
	func approve_pending() -> void:
		for purchase in purchases: purchase["purchase_state"] = 1
		on_purchase_updated.emit({"response_code": 0, "purchases": purchases.duplicate(true)})
	func acknowledge_purchase(token: String) -> void:
		acknowledged.append(token)
		for purchase in purchases:
			if purchase["purchase_token"] == token: purchase["is_acknowledged"] = true

## Stand-in for the IOSInAppPurchase singleton (StoreKit 2).
class AppleShop extends RefCounted:
	signal response(name: String, data: Dictionary)
	var owned: Array = []
	var flow := "success"
	var reachable := true
	var requests: Array = []
	func request(name: String, data: Dictionary) -> int:
		requests.append(name)
		match name:
			"startUpdateTask": return 0
			"products":
				if not reachable:
					response.emit("products", {"request": "products", "result": "error", "error": "offline"})
					return 0
				var products: Array = []
				for sku in data["productIDs"]: products.append({"id": sku, "displayName": sku, "displayPrice": "KRW 1,100", "type": "Non-Consumable"})
				response.emit("products", {"request": "products", "result": "success", "products": products})
			"purchasedProducts":
				response.emit("purchasedProducts", {"request": "purchasedProducts", "result": "success", "productIDs": owned.duplicate()})
			"purchase":
				var sku := String(data["productID"])
				if flow == "success": owned.append(sku)
				response.emit("purchase", {"request": "purchase", "result": flow, "productID": sku})
			"appStoreSync":
				response.emit("appStoreSync", {"request": "appStoreSync", "result": "success" if reachable else "error"})
			_: return 1
		return 0
	func revoke(sku: String) -> void:
		owned.erase(sku)
		response.emit("purchase", {"request": "purchase", "result": "revoked", "productID": sku})

## Stand-in for the GodotSteam singleton.
class SteamClient extends RefCounted:
	signal dlc_installed(app_id: int)
	signal overlay_toggled(active: bool, user_initiated: bool, app_id: int)
	var status := 0
	var installed: Array = []
	var opened: Array = []
	func steamInitEx(_app_id: int = 0, _embed: bool = false) -> Dictionary:
		return {"status": status, "verbal": "ok" if status == 0 else "Steam is not running"}
	func isDLCInstalled(app_id: int) -> bool: return installed.has(app_id)
	func activateGameOverlayToStore(app_id: int, _flag: int = 0) -> void:
		opened.append(app_id)
		overlay_toggled.emit(true, true, 0)

var _results: Array = []
var _restores: Array = []
var _runs := 0

func _ready() -> void:
	if not require_no_save(): return
	Run.running = false
	_runs = Save.runs
	Store.purchase_finished.connect(func(id: String, result: String) -> void: _results.append([id, result]))
	Store.restore_finished.connect(func(result: String) -> void: _restores.append(result))
	_check_no_shop()
	_check_ownership_and_cache()
	await _check_speed_is_free()
	await _check_revival()
	await _check_play()
	await _check_apple()
	await _check_steam()
	Store.use_backend(null)
	Save.runs = _runs
	Arena.running = false
	finish("상점·수호자의 가호(부활권·5성 영웅)·무료 배속·플랫폼 연동")

func _shop(owned: Array = []) -> TestShop:
	var shop := TestShop.new()
	shop.owned = owned.duplicate()
	Save.iap_owned = []
	Save.iap_sandbox = []
	Store._owned.clear()
	Store.use_backend(shop)
	_results.clear()
	_restores.clear()
	return shop

func _battle(seed_value: int) -> ArenaSim:
	Arena.start_run(seed_value)
	Arena.choose_theme(0)
	Arena.confirm_summon()
	Arena.close_modal()
	return Arena.sim

func _check_no_shop() -> void:
	Store.use_backend(null)
	check(not Store.has_shop() and Store.shop_name() == "", "상점이 없는 빌드")
	check(Store.owns(Store.GUARDIAN), "상점이 없으면 팔지 않고 잠그지도 않음")
	check(not Store.can_buy(Store.GUARDIAN) and Store.price(Store.GUARDIAN) == "", "상점이 없으면 구매 불가·가격 없음")
	Store.buy(Store.GUARDIAN)
	check(_results == [[Store.GUARDIAN, "unavailable"]], "상점 없는 구매 요청은 바로 거절")
	check(Store.PRODUCTS.size() == 1 and Store.product_of_sku(String(Store.product(Store.GUARDIAN)["sku"])) == Store.GUARDIAN and Store.skus().size() == 1, "상품은 수호자의 가호 하나·상점 상품 ID 왕복")
	check(Store.product("speed3").is_empty() and Store.product_of_sku("stellardefense.speed3") == "", "3배속은 더 이상 상품이 아님")
	for key in ["store.%s.name" % Store.GUARDIAN, "store.%s.desc" % Store.GUARDIAN]:
		check(Arena.label(key) != key, "상품 문구 존재: " + key)

func _check_ownership_and_cache() -> void:
	var shop := _shop()
	check(Store.has_shop() and not Store.owns(Store.GUARDIAN), "상점이 있으면 사기 전에는 미보유")
	check(Store.price(Store.GUARDIAN) == "T1" and Store.can_buy(Store.GUARDIAN), "상점이 준 가격 표시·구매 가능")
	for outcome in ["cancelled", "pending", "failed"]:
		_results.clear()
		shop.answer = outcome
		Store.buy(Store.GUARDIAN)
		check(not Store.owns(Store.GUARDIAN) and _results == [[Store.GUARDIAN, outcome]] and Store.buying() == "" and Store.can_buy(Store.GUARDIAN), "구매 %s: 미보유·다시 시도 가능" % outcome)
		check(Arena.label("store.result." + outcome) != "store.result." + outcome, "결과 문구 존재: " + outcome)
	# A sheet that never answers is given up; ownership still follows the shop later.
	shop.answer = "hang"
	_results.clear()
	Store.buy(Store.GUARDIAN)
	check(Store.buying() == Store.GUARDIAN and not Store.can_buy(Store.GUARDIAN), "결제 중에는 중복 요청 차단")
	Store._process(Store.BUY_TIMEOUT + 1.0)
	check(Store.buying() == "" and _results == [[Store.GUARDIAN, "failed"]], "응답 없는 결제는 시간 초과로 정리")
	shop.answer = "ok"
	_results.clear()
	Store.buy(Store.GUARDIAN)
	check(Store.owns(Store.GUARDIAN) and _results == [[Store.GUARDIAN, "ok"]] and Store.buying() == "", "구매 성공: 보유")
	check(Save.iap_owned == [Store.GUARDIAN], "보유 사본을 저장에 남김")
	check(not Store.can_buy(Store.GUARDIAN), "이미 가진 상품은 다시 못 삼")
	# A refund: the shop stops listing the product and the unlock goes with it.
	shop.owned = []
	Store.restore()
	check(not Store.owns(Store.GUARDIAN) and Save.iap_owned.is_empty() and _restores == ["ok"], "환불된 상품은 상점 답에 따라 회수")
	# Offline start: the save copy opens what was bought until the shop answers. A product
	# that is no longer sold (3x speed was one for a while) is simply forgotten.
	Save.iap_owned = [Store.GUARDIAN, "unknown_product", "speed3"]
	Save.iap_sandbox = ["speed3"]
	var offline: Node = load("res://core/store.gd").new()
	add_child(offline)
	var silent := TestShop.new()
	silent.selling = false
	offline.backend = silent
	check(offline.owns(Store.GUARDIAN) and not offline._owned.has("unknown_product") and not offline._owned.has("speed3"), "연결 없이 켜면 저장 사본으로 보유 판단·없어진 상품은 무시")
	check(Save.iap_sandbox.is_empty(), "없어진 상품의 테스트 구매 기록 정리")
	offline.queue_free()
	Save.iap_owned = []

## Battle speed is not for sale: 1x, 2x and 3x are free for everyone, shop or not.
func _check_speed_is_free() -> void:
	_shop()
	Save.runs = 50
	_battle(31)
	check(not Store.owns(Store.GUARDIAN), "아무것도 사지 않은 계정")
	Save.speed = 3.0
	var screen := ArenaScreen.new()
	add_child(screen)
	await paint(screen)
	check(is_equal_approx(screen.speed, 3.0), "아무것도 사지 않아도 저장된 3배속으로 열림")
	screen._action("speed:1")
	check(is_equal_approx(screen.speed, 1.0), "1배속 선택")
	screen._action("speed:3")
	check(not screen.store.opened and is_equal_approx(screen.speed, 3.0) and is_equal_approx(Save.speed, 3.0), "3배속은 무료: 구매창 없이 선택·설정 저장")
	var before: float = Arena.sim.elapsed
	screen._process(0.05)
	check(Arena.sim.elapsed > before + 0.12, "3배속이 실제 시뮬 시간을 세 배로 돌림")
	screen.set_speed(9.0)
	check(is_equal_approx(screen.speed, 3.0), "배속은 3배까지")
	# The sheet sells one thing, and the battle waits while it is open.
	screen.store.open()
	var elapsed_before: float = Arena.sim.elapsed
	screen._process(0.5)
	check(screen.store.opened and Arena.sim.elapsed == elapsed_before, "구매창이 열려 있는 동안 전투 정지")
	await paint(screen)
	var buys: Array = []
	for zone in screen.ui.zones:
		if String(zone["id"]).begins_with("store:buy:") and bool(zone["on"]): buys.append(String(zone["id"]))
	check(buys == ["store:buy:" + Store.GUARDIAN], "구매창의 구매 버튼은 수호자의 가호 하나: " + str(buys))
	screen._action("store:close")
	screen.queue_free()
	await frames(1)
	Save.speed = 1.0

func _revive_events(sim: ArenaSim) -> Array:
	return sim.events.filter(func(e: Dictionary) -> bool: return String(e.get("t", "")) == "arena_revive")

func _party() -> int:
	return Arena.heroes.size() + Arena.bench.size()

## The revival's hero (D2): on the field or the bench at the top grade, where Arena.revive_gift says, and the
## arena_revive event names it — unit, tier and where, and no gold.
func _gift_ok(event: Dictionary) -> bool:
	var gift: Dictionary = Arena.revive_gift
	if gift.is_empty() or int(gift.get("tier", -1)) != Balance.TIER_MAX or event.has("gold"):
		return false
	var id := String(gift["unit"]["id"])
	var found: Array = Arena.find_hero(id)
	if int(found[1]) < 0 or String(found[0]) != String(gift["where"]) or int(found[1]) != int(gift["slot"]):
		return false
	var list: Array = Arena.heroes if String(found[0]) == "field" else Arena.bench
	return int(list[int(found[1])]["tier"]) == Balance.TIER_MAX and String(event.get("unit", "")) == id \
		and int(event.get("tier", -1)) == Balance.TIER_MAX and String(event.get("where", "")) == String(gift["where"])

## Break the crystal inside a tick: a monster at the altar strikes on the next frame while the crystal is
## nearly gone. The revival then lands in the middle of _move_monsters, and its hero must wait for the
## end of the tick.
func _break_in_tick(sim: ArenaSim) -> bool:
	sim._spawn(Arena.wave_spawns(Arena.stage, 1)[0]["m"])
	var mo: Dictionary = sim.monsters[sim.monsters.size() - 1]
	mo["pos"] = Balance.ARENA_CENTER + Vector2(Balance.ALTAR_R + Balance.ARENA_MONSTER_RADIUS - 2, 0)
	mo["hp"] = 1.0e9
	mo["max"] = 1.0e9
	mo["siege_t"] = 0.99
	sim.invuln_t = 0.0
	sim.shield = 0.0
	sim.crystal_hp = 0.01
	var before := sim.revives
	for i in range(30):
		sim._tick(1.0 / 60.0)
		if sim.revives > before or sim.done: break
	return sim.revives == before + 1

func _check_revival() -> void:
	var uses := Balance.ARENA_REVIVE_USES
	check(uses >= 1 and JewelBox.tier_of(JewelBox.MAX_STARS) == Balance.TIER_MAX, "부활권: 판마다 %d번, 부활마다 5성 영웅(골드 없음)" % uses)
	# Without the DLC a broken crystal ends the stage.
	var shop := _shop()
	var sim := _battle(41)
	check(not Arena.revive_ready() and Arena.revives_left() == 0, "DLC 가 없으면 부활 없음")
	sim._damage_crystal(100000.0, Balance.ARENA_CENTER)
	check(sim.done and not Arena.running and Arena.modal == "result" and sim.revives == 0 and Arena.revive_gift.is_empty(), "DLC 없이 수정이 깨지면 패배")
	# Bought on the defeat screen: this very stage picks up again, with a five-star hero instead of gold.
	var kills_total: int = Save.total_kills
	Arena.kills = 5
	var screen := ArenaScreen.new()
	add_child(screen)
	await paint(screen)
	var offered := false
	for zone in screen.ui.zones:
		if String(zone["id"]) == "result:guardian" and bool(zone["on"]): offered = true
	check(offered, "패배 화면에 DLC 제안")
	screen._action("result:guardian")
	check(screen.store.opened and screen.store.focus == Store.GUARDIAN, "제안을 누르면 구매창")
	Save.total_kills = kills_total + 5
	var gold_before: int = Arena.gold
	var party_before := _party()
	var candidate: Dictionary = Arena.revive_candidate()
	var candidate_free: bool = int(Arena.find_hero(String(candidate["id"]))[1]) < 0
	sim.events.clear()
	screen._action("store:buy:" + Store.GUARDIAN)
	check(Store.owns(Store.GUARDIAN) and Arena.running and Arena.modal == "" and not screen.store.opened, "패배 화면에서 사면 그 판이 이어짐")
	sim = Arena.sim
	check(sim.revives == 1 and not sim.done and is_equal_approx(sim.crystal_hp, sim.crystal_max * Balance.ARENA_REVIVE_HP) and sim.invuln_t > 0.0, "수정이 절반으로 되살아나고 잠시 무적")
	var revived := _revive_events(sim)
	check(Arena.gold == gold_before and revived.size() == 1 and _gift_ok(revived[0]) and int(revived[0].get("left", -1)) == uses - 1, "골드 없이 5성 영웅 하나 합류·이벤트에 영웅·자리·남은 횟수")
	check(_party() == party_before + 1 and (not candidate_free or String(Arena.revive_gift["unit"]["id"]) == String(candidate["id"])), "판의 시드로 정한 후보 영웅이 온다(미리 불러 둘 수 있음)")
	check(sim.heroes.size() == Arena.heroes.size(), "합류한 영웅이 전투에도 섬")
	check(Save.total_kills == kills_total, "되살린 판의 처치 수를 두 번 세지 않음")
	check(ArenaValidation.valid(Arena.snapshot()), "되살린 판 저장 가능")
	screen.queue_free()
	await frames(1)
	# The rest of the tickets: each one is automatic and brings another hero, never gold.
	for n in range(2, uses + 1):
		sim.invuln_t = 0.0
		gold_before = Arena.gold
		party_before = _party()
		sim.events.clear()
		sim._damage_crystal(100000.0, Balance.ARENA_CENTER)
		revived = _revive_events(sim)
		check(Arena.running and not sim.done and sim.revives == n and Arena.revives_left() == uses - n and Arena.gold == gold_before \
			and _party() == party_before + 1 and revived.size() == 1 and _gift_ok(revived[0]), "%d번째 부활: 자동·5성 영웅·골드 없음·남은 %d" % [n, uses - n])
	sim.invuln_t = 0.0
	gold_before = Arena.gold
	sim._damage_crystal(100000.0, Balance.ARENA_CENTER)
	check(sim.done and not Arena.running and Arena.modal == "result" and Arena.gold == gold_before, "부활권을 다 쓰면 다음 파괴는 패배")
	check(not Arena.revive_from_defeat() and not Arena.revive_ready(), "다 쓴 판은 다시 못 되살림")
	# Owned from the start: every stage has all its tickets; a break inside a tick brings the hero at the
	# end of that tick.
	sim = _battle(42)
	check(Arena.revive_ready() and Arena.revives_left() == uses and sim.revives == 0 and Arena.revive_gift.is_empty(), "DLC 보유: 새 판마다 %d번" % uses)
	var before_break := Arena.snapshot()
	party_before = _party()
	sim.events.clear()
	var in_tick := _break_in_tick(sim)
	revived = _revive_events(sim)
	check(in_tick and Arena.running and not sim.done and Arena.modal == "" and revived.size() == 1 and _gift_ok(revived[0]), "틱 안에서 깨져도 자동 부활·영웅은 틱이 끝난 뒤 합류")
	check(_party() == party_before + 1 and sim.heroes.size() == Arena.heroes.size() and is_equal_approx(float(revived[0].get("sec", 0.0)), Balance.ARENA_REVIVE_INVULN), "합류 영웅이 전투 목록과 맞음·무적 시간 이벤트")
	var mo: Dictionary = sim.monsters[sim.monsters.size() - 1]
	check(float(mo["stun_t"]) > Balance.ARENA_REVIVE_STUN - 0.1 and Arena.lives > 0, "부활 충격으로 몬스터 정지")
	var first_gift := String(Arena.revive_gift["unit"]["id"])
	# The same moment again from its save: the same hero comes.
	check(Arena.restore(before_break), "부활 직전으로 되돌림")
	sim = Arena.sim
	_break_in_tick(sim)
	check(not Arena.revive_gift.is_empty() and String(Arena.revive_gift["unit"]["id"]) == first_gift, "같은 저장에서는 같은 영웅이 옴")
	var hp: float = sim.crystal_hp
	for i in range(roundi((Balance.ARENA_REVIVE_INVULN - 0.5) * 60)): sim._tick(1.0 / 60.0)
	check(sim.crystal_hp == hp and sim.invuln_t > 0.0, "무적 시간 동안 수정 피해 없음")
	var mid := Arena.snapshot()
	check(ArenaValidation.valid(mid) and Arena.restore(mid) and Arena.sim.revives == 1 and Arena.sim.invuln_t > 0.0 and Arena.revives_left() == uses - 1, "쓴 횟수·무적 시간 저장·복구")
	check(String(Arena.revive_gift.get("unit", {}).get("id", "")) == first_gift and int(Arena.revive_gift["tier"]) == Balance.TIER_MAX and Arena.revive_gift["where"] == mid["revive_gift"]["where"] and int(Arena.revive_gift["slot"]) == int(mid["revive_gift"]["slot"]), "부활 영웅 기록(영웅·등급·자리) 저장·복구")
	# A save made while the blessing revived once carries a flag instead of the count.
	var flagged := mid.duplicate(true)
	flagged["sim"].erase("revives")
	flagged["sim"]["revived"] = true
	check(ArenaValidation.valid(flagged) and Arena.restore(flagged) and Arena.sim.revives == 1, "부활이 한 번이던 때의 저장도 이어 함")
	var older := mid.duplicate(true)
	older.erase("revive_gift")
	check(ArenaValidation.valid(older) and Arena.restore(older) and Arena.revive_gift.is_empty(), "부활 영웅 기록이 없는 저장도 이어 함")
	var broken := mid.duplicate(true)
	broken["sim"]["revives"] = -1
	check(not ArenaValidation.valid(broken), "음수 부활 횟수 저장 거부")
	# More revivals than today's ARENA_REVIVE_USES (the value was lowered): valid, restored as all used.
	var lowered := mid.duplicate(true)
	lowered["sim"]["revives"] = uses + 2
	check(ArenaValidation.valid(lowered) and Arena.restore(lowered) and Arena.sim.revives == uses and Arena.revives_left() == 0, "지금 횟수보다 많이 쓴 저장은 받아 다 쓴 것으로")
	check(Arena.restore(mid), "부활 한 번 쓴 판으로 되돌림")
	for bad in [{"u": "nobody"}, {"t": Balance.TIER_MAX + 1}, {"where": "sky"}, {"slot": -1}]:
		broken = mid.duplicate(true)
		broken["revive_gift"].merge(bad, true)
		check(not ArenaValidation.valid(broken), "부활 영웅 기록이 틀린 저장 거부: " + str(bad))
	var stranger := ""
	for unit in Roster.UNITS:
		if int(Arena.find_hero(String(unit["id"]))[1]) < 0: stranger = String(unit["id"])
	broken = mid.duplicate(true)
	broken["revive_gift"]["u"] = stranger
	check(stranger != "" and not ArenaValidation.valid(broken), "판에 없는 영웅을 가리키는 부활 기록 거부")
	check(Arena.restore(mid), "판 되돌림")
	sim = Arena.sim
	for i in range(240): sim._tick(1.0 / 60.0)
	check(sim.invuln_t == 0.0 and sim.crystal_hp < hp, "무적이 끝나면 다시 피해")
	# Everyone already here: the lowest hero below the top grade reaches it; all at the top: nobody comes.
	for unit in Roster.UNITS:
		if int(Arena.find_hero(String(unit["id"]))[1]) < 0:
			Arena.bench.append({"unit": unit, "tier": Balance.TIER_MAX, "n": 1, "wave": 1, "growth_points": 0})
	for hero in Arena.heroes + Arena.bench:
		hero["tier"] = Balance.TIER_MAX
		hero["growth_points"] = 0
	var low: Dictionary = Arena.bench[Arena.bench.size() - 1]
	low["tier"] = 2
	low["growth_points"] = 3
	party_before = _party()
	var gift := Arena.grant_revive_hero()
	check(_party() == party_before and int(low["tier"]) == Balance.TIER_MAX and int(low["growth_points"]) == 0 and gift.get("where") == "bench" and int(gift.get("slot", -1)) == Arena.bench.size() - 1 and String(gift["unit"]["id"]) == String(low["unit"]["id"]), "모두 와 있으면 가장 낮은 영웅이 5성이 됨")
	check(ArenaValidation.valid(Arena.snapshot()), "그 뒤의 판도 저장 가능")
	if uses >= 2:
		sim.events.clear()
		sim.invuln_t = 0.0
		sim._damage_crystal(100000.0, Balance.ARENA_CENTER)
		revived = _revive_events(sim)
		check(Arena.running and sim.revives == 2 and _party() == party_before and Arena.revive_gift.is_empty() and revived.size() == 1 \
			and String(revived[0].get("unit", "?")) == "" and int(revived[0].get("tier", 0)) == -1 and not revived[0].has("gold"), "모두 5성이면 아무도 오지 않고 부활만 함")
	else:
		check(Arena.grant_revive_hero().is_empty() and _party() == party_before and Arena.revive_gift.is_empty(), "모두 5성이면 아무도 오지 않음")
	sim.revives = uses
	sim.invuln_t = 0.0
	sim._damage_crystal(100000.0, Balance.ARENA_CENTER)
	check(sim.done and Arena.modal == "result", "남은 횟수가 없으면 패배")
	await frames(1)
	screen = ArenaScreen.new()
	add_child(screen)
	await paint(screen)
	offered = false
	for zone in screen.ui.zones:
		if String(zone["id"]) == "result:guardian": offered = true
	check(not offered, "DLC 를 가진 사람에게는 제안하지 않음")
	screen.queue_free()
	await frames(1)
	# A new stage starts the count again.
	sim = _battle(43)
	check(sim.revives == 0 and Arena.revives_left() == uses and Arena.revive_gift.is_empty(), "새 판은 다시 %d번" % uses)
	shop.owned = []

func _play(client: PlayClient) -> StorePlay:
	Save.iap_owned = []
	Store._owned.clear()
	var backend := StorePlay.new(client)
	Store.use_backend(backend)
	_results.clear()
	_restores.clear()
	return backend

func _check_play() -> void:
	var client := PlayClient.new()
	var backend := _play(client)
	var sku := String(Store.product(Store.GUARDIAN)["sku"])
	await frames(2)
	check(Store.shop_name() == "google" and client.up and Store.price(Store.GUARDIAN) == "W1100", "Play: 연결 뒤 상품 가격 조회")
	check(not Store.owns(Store.GUARDIAN) and Store.can_buy(Store.GUARDIAN) and not Store.sandbox(Store.GUARDIAN), "Play: 처음에는 미보유·구매 가능")
	client.flow = "cancel"
	Store.buy(Store.GUARDIAN)
	await frames(2)
	check(not Store.owns(Store.GUARDIAN) and _results == [[Store.GUARDIAN, "cancelled"]], "Play: 사용자가 취소")
	client.flow = "refuse"
	_results.clear()
	Store.buy(Store.GUARDIAN)
	await frames(2)
	check(_results == [[Store.GUARDIAN, "failed"]] and Store.buying() == "", "Play: 결제창을 못 띄움")
	client.flow = "pending"
	_results.clear()
	Store.buy(Store.GUARDIAN)
	await frames(2)
	check(not Store.owns(Store.GUARDIAN) and _results == [[Store.GUARDIAN, "pending"]], "Play: 승인 대기 결제는 아직 미보유")
	client.approve_pending()
	await frames(2)
	check(Store.owns(Store.GUARDIAN) and client.acknowledged == ["token-" + sku], "Play: 나중에 승인되면 보유·구매 승인(acknowledge) 한 번")
	# A refund, seen at the next refresh (app resume).
	client.purchases.clear()
	Store.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await frames(2)
	check(not Store.owns(Store.GUARDIAN), "Play: 앱 복귀 때 환불 반영")
	client.flow = "ok"
	_results.clear()
	Store.buy(Store.GUARDIAN)
	await frames(2)
	check(Store.owns(Store.GUARDIAN) and _results == [[Store.GUARDIAN, "ok"]] and client.acknowledged.size() == 2, "Play: 결제 완료·승인")
	# The shop says "already owned" (bought on another device): the list is asked again.
	client.purchases.clear()
	Store.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await frames(2)
	client.flow = "owned"
	_results.clear()
	Store.buy(Store.GUARDIAN)
	await frames(3)
	check(Store.owns(Store.GUARDIAN) and _results == [[Store.GUARDIAN, "ok"]], "Play: 이미 보유 응답이면 목록을 다시 받아 보유 처리")
	Store.restore()
	await frames(2)
	check(_restores == ["ok"], "Play: 구매 복원")
	# No connection: nothing can be bought, the save copy still opens what was owned.
	var offline := PlayClient.new()
	offline.online = false
	backend = _play(offline)
	Store._owned[Store.GUARDIAN] = true
	await frames(2)
	check(Store.owns(Store.GUARDIAN) and not backend.sells(Store.GUARDIAN) and Store.price(Store.GUARDIAN) == "", "Play: 연결 실패 때 사본 유지·판매 불가")
	Store._owned.clear()
	check(Store.can_buy(Store.GUARDIAN) == Store.test_build() and Store.sandbox(Store.GUARDIAN) == Store.test_build(), "Play: 상점이 못 팔 때 결제 없는 해제는 테스트 빌드에서만")
	check(Store.test_build() == (OS.is_debug_build() or OS.has_feature("store_test")), "테스트 빌드 = 디버그 익스포트 또는 store_test 표시가 있는 프리셋")
	if Store.test_build():
		# The whole path a tester walks on an unregistered build: unlock, then reset.
		_results.clear()
		Store.buy(Store.GUARDIAN)
		check(Store.owns(Store.GUARDIAN) and _results == [[Store.GUARDIAN, "ok"]] and Save.iap_sandbox == [Store.GUARDIAN], "테스트 해제: 결제 없이 보유")
		Store.sandbox_reset()
		check(not Store.owns(Store.GUARDIAN) and Save.iap_sandbox.is_empty(), "테스트 구매 초기화")
	var before := offline.connects
	offline.online = true
	Store._process(RETRY_WAIT)
	await frames(2)
	check(offline.connects > before and offline.up and Store.price(Store.GUARDIAN) == "W1100" and not Store.owns(Store.GUARDIAN), "Play: 다시 연결되면 가격·보유를 상점 답으로 갱신")

const RETRY_WAIT := 3.0

func _check_apple() -> void:
	Save.iap_owned = []
	Store._owned.clear()
	var shop := AppleShop.new()
	var sku := String(Store.product(Store.GUARDIAN)["sku"])
	Store.use_backend(StoreApple.new(shop))
	_results.clear()
	_restores.clear()
	await frames(2)
	check(Store.shop_name() == "apple" and shop.requests.slice(0, 3) == ["startUpdateTask", "products", "purchasedProducts"], "App Store: 갱신 수신 시작·상품·보유 조회")
	check(Store.price(Store.GUARDIAN) == "KRW 1,100" and not Store.owns(Store.GUARDIAN) and Store.can_buy(Store.GUARDIAN), "App Store: 현지 가격 표시·구매 가능")
	for pair in [["userCancelled", "cancelled"], ["pending", "pending"], ["error", "failed"], ["unverified", "failed"]]:
		shop.flow = pair[0]
		_results.clear()
		Store.buy(Store.GUARDIAN)
		await frames(2)
		check(not Store.owns(Store.GUARDIAN) and _results == [[Store.GUARDIAN, pair[1]]], "App Store: %s" % pair[0])
	# Approved later outside the app (Ask to Buy): arrives as a purchase response.
	shop.owned.append(sku)
	shop.response.emit("purchase", {"request": "purchase", "result": "success", "productID": sku})
	await frames(2)
	check(Store.owns(Store.GUARDIAN), "App Store: 앱 밖에서 승인된 구매 반영")
	shop.revoke(sku)
	await frames(3)
	check(not Store.owns(Store.GUARDIAN), "App Store: 환불(revoked) 반영")
	shop.flow = "success"
	_results.clear()
	Store.buy(Store.GUARDIAN)
	await frames(2)
	check(Store.owns(Store.GUARDIAN) and _results == [[Store.GUARDIAN, "ok"]], "App Store: 결제 완료")
	Store.restore()
	await frames(3)
	check(_restores == ["ok"] and shop.requests.has("appStoreSync"), "App Store: 구매 복원(AppStore.sync)")
	shop.reachable = false
	_restores.clear()
	Store.restore()
	await frames(3)
	check(_restores == ["failed"] and Store.owns(Store.GUARDIAN), "App Store: 복원 실패해도 보유 유지")

func _check_steam() -> void:
	Save.iap_owned = []
	Store._owned.clear()
	var steam := SteamClient.new()
	var backend := StoreSteam.new(steam)
	Store.use_backend(backend)
	_results.clear()
	check(Store.shop_name() == "steam" and backend.online, "Steam: 초기화")
	check(backend.included == Store.STEAM_INCLUDED and Store.owns(Store.GUARDIAN) and not Store.can_buy(Store.GUARDIAN), "Steam: 유료 본편은 가호 포함")
	# A free release sells the product as a DLC.
	backend = StoreSteam.new(steam)
	backend.included = false
	backend.dlc = {Store.GUARDIAN: 4002}
	Store._owned.clear()
	Store.use_backend(backend)
	check(not Store.owns(Store.GUARDIAN) and Store.can_buy(Store.GUARDIAN), "Steam DLC: 미보유·구매 가능")
	Store.buy(Store.GUARDIAN)
	check(steam.opened == [4002] and Store.buying() == Store.GUARDIAN, "Steam DLC: 오버레이로 상점 페이지 열기")
	steam.overlay_toggled.emit(false, true, 0)
	await frames(2)
	check(not Store.owns(Store.GUARDIAN) and _results == [[Store.GUARDIAN, "cancelled"]], "Steam DLC: 사지 않고 닫으면 취소")
	_results.clear()
	Store.buy(Store.GUARDIAN)
	steam.installed.append(4002)
	steam.dlc_installed.emit(4002)
	await frames(2)
	check(Store.owns(Store.GUARDIAN) and _results == [[Store.GUARDIAN, "ok"]], "Steam DLC: 구매(설치)되면 보유")
	steam.installed.clear()
	Store.restore()
	check(not Store.owns(Store.GUARDIAN), "Steam DLC: 환불되면 회수")
	var down := SteamClient.new()
	down.status = 2
	backend = StoreSteam.new(down)
	backend.included = false
	Store._owned.clear()
	Store._owned[Store.GUARDIAN] = true
	Store.use_backend(backend)
	check(not backend.online and Store.owns(Store.GUARDIAN) and not backend.sells(Store.GUARDIAN), "Steam: 클라이언트가 없으면 사본 유지·판매 불가")
