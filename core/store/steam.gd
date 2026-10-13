extends RefCounted
class_name StoreSteam

## Steam through GodotSteam (singleton Steam). Steam has no in-game purchase sheet for
## permanent unlocks: a product is either part of the paid base game
## (Store.STEAM_INCLUDED) or a DLC whose store page opens in the overlay. Ownership is
## what the Steam client reports, so it also works offline and after a refund.
const NAME := "steam"

var store: Node
var steam: Object
var online := false
## True: the paid base game owns every product. False: each product is the DLC in `dlc`.
var included: bool = Store.STEAM_INCLUDED
## product id -> Steam app id of its DLC.
var dlc: Dictionary = {}
var _watch := ""


func _init(singleton: Object) -> void:
	steam = singleton
	for entry in Store.PRODUCTS:
		dlc[String(entry["id"])] = int(entry.get("steam_dlc", 0))


func start() -> void:
	# Embedded callbacks: GodotSteam pumps Steam itself, no run_callbacks() per frame.
	var info: Dictionary = steam.steamInitEx(Store.STEAM_APP_ID, true)
	online = int(info.get("status", 1)) == 0
	if not online:
		push_warning("Steam is not available: %s" % String(info.get("verbal", "")))
		return
	steam.dlc_installed.connect(_installed)
	steam.overlay_toggled.connect(_overlay)
	refresh()


func _installed(_app_id: int) -> void:
	refresh.call_deferred()


func _overlay(active: bool, _user_initiated: bool, _app_id: int) -> void:
	if not active: _on_overlay_closed.call_deferred()


func sells(id: String) -> bool:
	return online and not included and int(dlc.get(id, 0)) > 0


func refresh() -> void:
	if store == null or not online: return
	var owned: Array = []
	for id in dlc:
		var app := int(dlc[id])
		if included or (app > 0 and bool(steam.isDLCInstalled(app))):
			owned.append(String(id))
	store.set_owned(owned)


func restore() -> void:
	refresh()
	store.finish_restore(online)


## Opens the DLC's store page in the overlay; the purchase itself happens in Steam.
func buy(product: Dictionary) -> void:
	var id := String(product["id"])
	if not sells(id):
		store.finish_purchase(id, "unavailable")
		return
	_watch = id
	steam.activateGameOverlayToStore(int(dlc[id]))


func _on_overlay_closed() -> void:
	if store == null: return
	refresh()
	if _watch.is_empty(): return
	var id := _watch
	_watch = ""
	if store.buying() == id: store.finish_purchase(id, "cancelled")
