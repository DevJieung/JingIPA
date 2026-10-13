extends RefCounted
class_name StorePlay

## Google Play Billing through the official Godot plugin (addons/GodotGooglePlayBilling,
## Billing Library 9). `client` is its BillingClient; tests pass a stand-in with the same
## signals and methods. Products are one-time in-app products that are never consumed:
## each purchase is acknowledged once (Google refunds it after three days otherwise).
const NAME := "google"
const OK := 0
const USER_CANCELED := 1
const ITEM_ALREADY_OWNED := 7
const PURCHASED := 1
const PENDING := 2
const INAPP := 0
const RETRY := [2.0, 5.0, 15.0, 60.0]

var store: Node
var client: Object
var _known: Dictionary = {}
var _retry := -1.0
var _tries := 0


func _init(billing_client: Object) -> void:
	client = billing_client


func start() -> void:
	# The client is a Node (BillingClient); the Store keeps it so it is freed with it.
	if client is Node and client.get_parent() == null: store.add_child(client)
	client.connected.connect(_signal.bind("_on_connected"))
	client.disconnected.connect(_signal.bind("_on_lost"))
	client.connect_error.connect(_error)
	client.query_product_details_response.connect(_answer.bind("_on_products"))
	client.query_purchases_response.connect(_answer.bind("_on_purchases"))
	client.on_purchase_updated.connect(_answer.bind("_on_updated"))
	client.start_connection()


func stop() -> void:
	client.end_connection()


## The plugin may signal from Android's own thread; continue on the main thread.
func _signal(method: String) -> void:
	Callable(self, method).call_deferred()


func _error(_code: int, _message: String) -> void:
	_on_lost.call_deferred()


func _answer(response: Dictionary, method: String) -> void:
	Callable(self, method).call_deferred(response)


func poll(dt: float) -> void:
	if _retry < 0.0: return
	_retry -= dt
	if _retry <= 0.0:
		_retry = -1.0
		client.start_connection()


func sells(id: String) -> bool:
	return _known.has(id) and client.is_ready()


func refresh() -> void:
	if client.is_ready():
		client.query_purchases(INAPP)
	else:
		client.start_connection()


func restore() -> void:
	if not client.is_ready():
		client.start_connection()
		store.finish_restore(false)
		return
	client.query_purchases(INAPP)


func buy(product: Dictionary) -> void:
	var id := String(product["id"])
	if not sells(id):
		store.finish_purchase(id, "unavailable")
		return
	var launched: Dictionary = client.purchase(String(product["sku"]))
	if int(launched.get("response_code", OK)) != OK:
		store.finish_purchase(id, "failed")


func _on_connected() -> void:
	if store == null: return
	_tries = 0
	_retry = -1.0
	client.query_product_details(Store.skus(), INAPP)
	client.query_purchases(INAPP)


func _on_lost() -> void:
	if store == null or _retry >= 0.0: return
	_retry = float(RETRY[mini(_tries, RETRY.size() - 1)])
	_tries += 1
	if store.restoring(): store.finish_restore(false)


func _on_products(response: Dictionary) -> void:
	if store == null or int(response.get("response_code", -1)) != OK: return
	for details in response.get("product_details", []):
		if not details is Dictionary: continue
		var id := Store.product_of_sku(String(details.get("product_id", "")))
		if id.is_empty(): continue
		_known[id] = true
		store.set_price(id, _find_price(details))
	store.changed.emit()


## The formatted price sits in the one-time offer details, whose nesting has changed
## between Billing Library versions; take the first one found.
func _find_price(value: Variant) -> String:
	if value is Dictionary:
		if value.has("formatted_price"): return String(value["formatted_price"])
		for key in value:
			var found := _find_price(value[key])
			if not found.is_empty(): return found
	elif value is Array:
		for item in value:
			var found := _find_price(item)
			if not found.is_empty(): return found
	return ""


func _owned_in(purchases: Array) -> Dictionary:
	var owned := {}
	var pending := {}
	for purchase in purchases:
		if not purchase is Dictionary: continue
		var state := int(purchase.get("purchase_state", 0))
		for sku in purchase.get("product_ids", []):
			var id := Store.product_of_sku(String(sku))
			if id.is_empty(): continue
			if state == PURCHASED: owned[id] = true
			elif state == PENDING: pending[id] = true
		if state == PURCHASED and not bool(purchase.get("is_acknowledged", false)):
			client.acknowledge_purchase(String(purchase.get("purchase_token", "")))
	return {"owned": owned, "pending": pending}


func _on_purchases(response: Dictionary) -> void:
	if store == null: return
	var ok := int(response.get("response_code", -1)) == OK
	if ok:
		store.set_owned(_owned_in(response.get("purchases", []))["owned"].keys())
	store.finish_restore(ok)


func _on_updated(response: Dictionary) -> void:
	if store == null: return
	var buying: String = store.buying()
	var code := int(response.get("response_code", -1))
	if code == OK:
		var seen := _owned_in(response.get("purchases", []))
		for id in seen["owned"]: store.grant(id)
		if not buying.is_empty() and seen["pending"].has(buying):
			store.finish_purchase(buying, "pending")
	elif code == ITEM_ALREADY_OWNED:
		client.query_purchases(INAPP)
	elif not buying.is_empty():
		store.finish_purchase(buying, "cancelled" if code == USER_CANCELED else "failed")
