extends Node

## Purchases. The game asks only owns() / price() / buy() / restore(); which shop stands
## behind them is decided once at boot from the engine singletons this build carries:
##   GodotGooglePlayBilling  (Android plugin)            -> Google Play Billing
##   IOSInAppPurchase        (iOS plugin, StoreKit 2)    -> App Store
##   Steam                   (GodotSteam)                -> Steam DLC / paid base game
## A build with none of them (tests, a desktop development run, an export made without
## the plugin) has no shop: nothing is for sale there and nothing is locked.
##
## Every product is a one-time permanent unlock. The shop is the source of truth: what
## is owned is asked again at every boot, on resume and after every purchase, so a
## refund takes the unlock back. The copy in the save file (Save.iap_owned) only covers
## a start without a connection.
signal changed
## result: "ok" | "cancelled" | "pending" | "failed" | "unavailable"
signal purchase_finished(id: String, result: String)
## result: "ok" | "failed"
signal restore_finished(result: String)

const GUARDIAN := "guardian"
## sku is the product id registered in Play Console and App Store Connect (one name for
## both). steam_dlc is the DLC's Steam app id; it is only read when STEAM_INCLUDED is false.
const PRODUCTS := [
	{"id": GUARDIAN, "sku": "stellardefense.guardian", "steam_dlc": 0},
]
## Steam sells the game as a paid title with everything in it: true owns every product.
## For a free Steam release set this to false and fill steam_dlc above.
const STEAM_INCLUDED := true
## 0 lets Steam supply the app id (launch through Steam, or steam_appid.txt while developing).
const STEAM_APP_ID := 0
## A purchase sheet that never answers is given up after this long.
const BUY_TIMEOUT := 180.0

const PLAY_SINGLETON := "GodotGooglePlayBilling"
const PLAY_CLIENT := "res://addons/GodotGooglePlayBilling/BillingClient.gd"
const APPLE_SINGLETON := "IOSInAppPurchase"
const STEAM_SINGLETON := "Steam"

var backend: RefCounted = null
var _owned: Dictionary = {}
var _prices: Dictionary = {}
var _buying := ""
var _buy_t := 0.0
var _restoring := false


func _ready() -> void:
	for id in Save.iap_owned:
		if not product(String(id)).is_empty(): _owned[String(id)] = true
	# A product that is no longer sold (3x speed was one for a while) is forgotten.
	for id in Save.iap_sandbox.duplicate():
		if product(String(id)).is_empty(): Save.set_iap_sandbox(String(id), false)
	set_process(false)
	if Engine.has_singleton(PLAY_SINGLETON) and ResourceLoader.exists(PLAY_CLIENT):
		use_backend(StorePlay.new(load(PLAY_CLIENT).new()))
	elif Engine.has_singleton(APPLE_SINGLETON):
		use_backend(StoreApple.new(Engine.get_singleton(APPLE_SINGLETON)))
	elif Engine.has_singleton(STEAM_SINGLETON):
		use_backend(StoreSteam.new(Engine.get_singleton(STEAM_SINGLETON)))


## Attach a shop. Tests pass a backend built on a stand-in client.
func use_backend(shop: RefCounted) -> void:
	if backend != null:
		# A replaced shop must not answer any more.
		if backend.has_method("stop"): backend.stop()
		backend.store = null
	backend = shop
	_buying = ""
	_restoring = false
	_prices.clear()
	set_process(backend != null)
	if backend != null:
		backend.store = self
		backend.start()
	changed.emit()


func _process(dt: float) -> void:
	if backend != null and backend.has_method("poll"): backend.poll(dt)
	if _buying.is_empty(): return
	_buy_t += dt
	if _buy_t >= BUY_TIMEOUT: finish_purchase(_buying, "failed")


func _notification(what: int) -> void:
	# A purchase approved or refunded while the app was away shows up on return.
	if what == NOTIFICATION_APPLICATION_RESUMED and backend != null and _buying.is_empty():
		backend.refresh()


static func product(id: String) -> Dictionary:
	for entry in PRODUCTS:
		if entry["id"] == id: return entry
	return {}


static func product_of_sku(sku: String) -> String:
	for entry in PRODUCTS:
		if entry["sku"] == sku: return String(entry["id"])
	return ""


static func skus() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in PRODUCTS: out.append(String(entry["sku"]))
	return out


func has_shop() -> bool:
	return backend != null


func shop_name() -> String:
	return String(backend.NAME) if backend != null else ""


## Without a shop on this build nothing is for sale, so nothing is withheld.
func owns(id: String) -> bool:
	return backend == null or _owned.has(id)


## The shop's own price text in the buyer's currency ("" until the shop has answered).
func price(id: String) -> String:
	return String(_prices.get(id, ""))


func buying() -> String:
	return _buying


func restoring() -> bool:
	return _restoring


## A test build: a debug export, or an export preset that carries the `store_test`
## feature (the unsigned test IPA is a release export). Builds sent to a store must be
## neither: remove `store_test` from the preset's custom features.
func test_build() -> bool:
	return OS.is_debug_build() or OS.has_feature("store_test")


## A test build may unlock without paying when the shop cannot sell (the app or its
## products are not registered with the shop yet). Store builds never do.
func sandbox(id: String) -> bool:
	return backend != null and test_build() and not backend.sells(id)


func can_buy(id: String) -> bool:
	if backend == null or product(id).is_empty() or _owned.has(id) or not _buying.is_empty() or _restoring:
		return false
	return backend.sells(id) or sandbox(id)


func buy(id: String) -> void:
	if not can_buy(id):
		purchase_finished.emit(id, "unavailable")
		return
	_buying = id
	_buy_t = 0.0
	changed.emit()
	if sandbox(id):
		Save.set_iap_sandbox(id, true)
		grant(id)
		return
	backend.buy(product(id))


## Ask the shop again for everything this account owns (the App Store requires the
## button; on the other shops it simply refreshes).
func restore() -> void:
	if backend == null or _restoring or not _buying.is_empty():
		return
	_restoring = true
	changed.emit()
	backend.restore()


## Test builds: forget the purchases made without paying.
func sandbox_reset() -> void:
	if not test_build(): return
	for id in Save.iap_sandbox: _owned.erase(String(id))
	Save.clear_iap_sandbox()
	_remember()
	if backend != null: backend.refresh()
	changed.emit()


# --------------------------------------------------------------------------- #
# Called by the backends
# --------------------------------------------------------------------------- #
func set_price(id: String, text: String) -> void:
	if product(id).is_empty() or String(_prices.get(id, "")) == text: return
	_prices[id] = text
	changed.emit()


## One product is owned (a purchase went through, or the shop reported it).
func grant(id: String) -> void:
	if product(id).is_empty(): return
	var fresh := not _owned.has(id)
	_owned[id] = true
	if fresh: _remember()
	if _buying == id: finish_purchase(id, "ok")
	elif fresh: changed.emit()


## The shop's complete answer: exactly these products are owned by this account.
func set_owned(ids: Array) -> void:
	var next := {}
	for id in ids:
		if not product(String(id)).is_empty(): next[String(id)] = true
	for id in Save.iap_sandbox:
		if test_build() and not product(String(id)).is_empty(): next[String(id)] = true
	var same := next.size() == _owned.size()
	for id in next:
		if not _owned.has(id): same = false
	_owned = next
	if not same: _remember()
	if not _buying.is_empty() and _owned.has(_buying): finish_purchase(_buying, "ok")
	elif not same: changed.emit()


func finish_purchase(id: String, result: String) -> void:
	if _buying == id: _buying = ""
	changed.emit()
	purchase_finished.emit(id, result)


func finish_restore(ok: bool) -> void:
	if not _restoring: return
	_restoring = false
	changed.emit()
	restore_finished.emit("ok" if ok else "failed")


func _remember() -> void:
	var ids: Array = _owned.keys()
	ids.sort()
	Save.set_iap_owned(ids)
