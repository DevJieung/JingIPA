extends RefCounted
class_name StoreApple

## App Store through StoreKit 2 (ios/plugins/ios-in-app-purchase, singleton
## IOSInAppPurchase): request(name, data) asks, the `response` signal answers. Products
## are non-consumables; the plugin finishes every verified transaction itself.
const NAME := "apple"
const RETRY := [5.0, 15.0, 60.0]

var store: Node
var shop: Object
var _known: Dictionary = {}
var _retry := -1.0
var _tries := 0


func _init(singleton: Object) -> void:
	shop = singleton


func start() -> void:
	# Connect first: purchases approved outside the app arrive as soon as the task starts.
	shop.response.connect(_response)
	shop.request("startUpdateTask", {})
	shop.request("products", {"productIDs": Array(Store.skus())})
	shop.request("purchasedProducts", {})


func poll(dt: float) -> void:
	if _retry < 0.0: return
	_retry -= dt
	if _retry <= 0.0:
		_retry = -1.0
		shop.request("products", {"productIDs": Array(Store.skus())})


func sells(id: String) -> bool:
	return _known.has(id)


func refresh() -> void:
	shop.request("purchasedProducts", {})


## AppStore.sync(): asks for the Apple ID if needed, then reports what is owned.
func restore() -> void:
	if int(shop.request("appStoreSync", {})) != 0:
		store.finish_restore(false)


func buy(product: Dictionary) -> void:
	if int(shop.request("purchase", {"productID": String(product["sku"])})) != 0:
		store.finish_purchase(String(product["id"]), "failed")


## StoreKit answers from its own task; continue on the main thread.
func _response(name: String, data: Dictionary) -> void:
	_on_response.call_deferred(name, data)


func _on_response(name: String, data: Dictionary) -> void:
	if store == null: return
	var result := String(data.get("result", ""))
	match name:
		"products":
			if result != "success":
				if _retry < 0.0 and _tries < RETRY.size():
					_retry = float(RETRY[_tries])
					_tries += 1
				return
			for entry in data.get("products", []):
				if not entry is Dictionary: continue
				var id := Store.product_of_sku(String(entry.get("id", "")))
				if id.is_empty(): continue
				_known[id] = true
				store.set_price(id, String(entry.get("displayPrice", "")))
			store.changed.emit()
		"purchasedProducts":
			if result == "success":
				var owned: Array = []
				for sku in data.get("productIDs", []):
					var id := Store.product_of_sku(String(sku))
					if not id.is_empty(): owned.append(id)
				store.set_owned(owned)
			store.finish_restore(result == "success")
		"purchase":
			# Also sent for transactions that complete or are revoked outside the app.
			var id := Store.product_of_sku(String(data.get("productID", "")))
			var buying: String = store.buying()
			if result == "success" and not id.is_empty():
				store.grant(id)
			elif result == "revoked":
				shop.request("purchasedProducts", {})
			elif not buying.is_empty() and (id.is_empty() or id == buying):
				match result:
					"pending": store.finish_purchase(buying, "pending")
					"userCancelled": store.finish_purchase(buying, "cancelled")
					_: store.finish_purchase(buying, "failed")
		"appStoreSync":
			if result == "success": shop.request("purchasedProducts", {})
			else: store.finish_restore(false)
