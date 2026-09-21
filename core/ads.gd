extends CanvasLayer

signal completed(kind: String, rewarded: bool)

const TEST_REWARDED_ID := "ca-app-pub-3940256099942544/5224354917"
const TEST_REWARDED_INTERSTITIAL_ID := "ca-app-pub-3940256099942544/5354046379"
const FORMAT_SETTINGS := {
	"card": "rewards/android/card_change_format",
	"fusion_undo": "rewards/android/merge_restore_format",
	"continue": "rewards/android/revive_format",
	"crystal": "rewards/android/crystal_format",
}
const UNIT_SETTINGS := {
	"card": "rewards/android/card_change_unit_id",
	"fusion_undo": "rewards/android/merge_restore_unit_id",
	"continue": "rewards/android/revive_unit_id",
	"crystal": "rewards/android/crystal_unit_id",
}
const AD_MAX_AGE_MSEC := 50 * 60 * 1000
const REQUEST_TIMEOUT_MSEC := 45000
const TRANSIENT_RETRY_MSEC := 1500
const GOOGLE_ADS_ERROR_DOMAIN := "com.google.android.gms.ads"
var busy := false
var message := ""
var last_error: Dictionary = {}
var _message_left := 0.0
var _reward_notice := false
var _notice_dismissed_frame := -1
var _native := false
var _initialized := false
var _initializing := false
var _loading := false
var _showing := false
var _awarded := false
var _request: Dictionary = {}
var _serial := 0
var _generation := 0
var _init_generation := 0
var _deadline := 0
var _retry_at := 0
var _request_deadline := 0
var _request_retry_at := 0
var _request_retries := 0
var _ad: RefCounted
var _ad_kind := ""
var _loaded_at := 0
var _load_kind := ""
var _notice: Notice


func _ready() -> void:
	layer = 200
	_notice = Notice.new()
	_notice.service = self
	add_child(_notice)
	_native = OS.get_name() == "Android" and Engine.has_singleton("PoingGodotAdMob") \
			and Engine.has_singleton("PoingGodotAdMobRewardedAd")
	if _native:
		if OS.is_debug_build():
			var configuration := RequestConfiguration.new()
			configuration.test_device_ids.assign(ProjectSettings.get_setting("rewards/android/test_device_ids", PackedStringArray()))
			MobileAds.set_request_configuration(configuration)
		_initialize()


func _initialize() -> void:
	if _initialized or _initializing:
		return
	_initializing = true
	_init_generation += 1
	var generation := _init_generation
	_deadline = Time.get_ticks_msec() + 30000
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status: InitializationStatus) -> void:
		if generation != _init_generation:
			return
		_initializing = false
		_initialized = true
		print("AdMob initialized")
		var kind := String(_request.get("kind", "")) if busy else _preload_kind()
		if not kind.is_empty():
			_load(kind)
	MobileAds.initialize(listener)


func _process(dt: float) -> void:
	if not busy:
		_message_left = maxf(0, _message_left - dt)
	var now := Time.get_ticks_msec()
	if busy and not _showing and _request_deadline > 0 and now > _request_deadline:
		print("AdMob request timed out including retries: kind=", _request.get("kind", ""))
		_retry_at = now + 30000
		_finish(false, "광고 응답이 늦어지고 있습니다. 다시 시도하세요.")
	if (_loading or _initializing) and now > _deadline:
		_loading = false
		_initializing = false
		_generation += 1
		_init_generation += 1
		_retry_at = now + 30000
		print("AdMob request timed out: kind=", _load_kind)
		if busy and not _showing:
			_finish(false, "광고 응답이 늦어지고 있습니다. 다시 시도하세요.")
	if busy and not _showing and _request_retry_at > 0 and now >= _request_retry_at:
		_request_retry_at = 0
		_load(String(_request["kind"]))
	if _native and not busy and not _loading and not _initializing and now >= _retry_at:
		if _initialized:
			var kind := _preload_kind()
			if not kind.is_empty() and not _ad_ready(kind):
				_load(kind)
		else:
			_initialize()
	_notice.queue_redraw()


func rewarded_unit_id(kind: String) -> String:
	if not UNIT_SETTINGS.has(kind):
		return ""
	var fallback := TEST_REWARDED_INTERSTITIAL_ID if reward_format(kind) == "rewarded_interstitial" else TEST_REWARDED_ID
	return String(ProjectSettings.get_setting(UNIT_SETTINGS[kind], fallback)).strip_edges()


func reward_format(kind: String) -> String:
	if not FORMAT_SETTINGS.has(kind):
		return ""
	return String(ProjectSettings.get_setting(FORMAT_SETTINGS[kind],
			"rewarded" if kind == "card" else "rewarded_interstitial"))


func _preload_kind() -> String:
	if Run.reward_allowed("fusion_undo", {"fusion_id": int(Run.fusion_pending.get("id", -1))}):
		return "fusion_undo"
	if Run.reward_allowed("continue"):
		return "continue"
	# Prepare the first card ad while the title is open, before the first draw.
	if Run.can_choose_card(0) or not Run.running:
		return "card"
	return ""


func _ad_ready(kind: String) -> bool:
	return _ad != null and _ad_kind == kind and Time.get_ticks_msec() - _loaded_at < AD_MAX_AGE_MSEC


func _clear_ad() -> void:
	_generation += 1
	_loading = false
	_load_kind = ""
	if _ad != null:
		_ad.destroy()
		_ad = null
	_ad_kind = ""
	_loaded_at = 0


func notify(text: String) -> void:
	message = text
	_reward_notice = false
	_message_left = 5.0


## 메뉴/화면보다 먼저 보상 알림의 터치를 처리해 뒤쪽 버튼이 함께 눌리지 않게 한다.
func dismiss_notice_input(event: InputEvent) -> bool:
	var pointer: bool = event is InputEventScreenTouch or (event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT)
	if not pointer or busy or _showing:
		return false
	# Android의 한 터치에서 함께 생성되는 마우스 이벤트도 같은 프레임에 소비한다.
	if _notice_dismissed_frame == Engine.get_process_frames():
		get_viewport().set_input_as_handled()
		return true
	if not event.pressed or not _reward_notice or _message_left <= 0.0:
		return false
	_message_left = 0.0
	_reward_notice = false
	_notice_dismissed_frame = Engine.get_process_frames()
	_notice.queue_redraw()
	get_viewport().set_input_as_handled()
	return true


func request_reward(kind: String, data: Dictionary = {}) -> bool:
	if busy or not Run.reward_allowed(kind, data):
		return false
	if not _native:
		notify("광고는 Android 앱에서 이용할 수 있습니다.")
		return false
	if rewarded_unit_id(kind).is_empty():
		push_error("Missing AdMob unit setting for reward: " + kind)
		notify("광고를 사용할 수 없습니다. 잠시 후 다시 시도하세요.")
		return false
	_serial += 1
	_request = {"kind": kind, "data": data.duplicate(true)}
	_request["data"]["seed"] = Run.run_seed
	_request["data"]["wave"] = Run.wave
	if kind == "card":
		_request["data"]["revision"] = Run.rerolled[int(data["slot"])]
	busy = true
	_awarded = false
	_request_deadline = Time.get_ticks_msec() + REQUEST_TIMEOUT_MSEC
	_request_retry_at = 0
	_request_retries = 0
	notify("광고를 준비하고 있습니다...")
	if _ad_ready(kind):
		_show()
	elif _initialized:
		_load(kind)
	else:
		_initialize()
	return true


func _load(kind: String) -> void:
	if not _initialized or (_loading and _load_kind == kind) or _ad_ready(kind):
		return
	_clear_ad()
	var unit_id := rewarded_unit_id(kind)
	if unit_id.is_empty():
		return
	_loading = true
	_load_kind = kind
	_deadline = Time.get_ticks_msec() + 30000
	var generation := _generation
	var callback: RefCounted
	if reward_format(kind) == "rewarded_interstitial":
		callback = RewardedInterstitialAdLoadCallback.new()
	else:
		callback = RewardedAdLoadCallback.new()
	callback.on_ad_loaded = _on_loaded.bind(generation, kind)
	callback.on_ad_failed_to_load = _on_load_failed.bind(generation, kind)
	print("AdMob loading reward: ", kind, " format=", reward_format(kind))
	_start_load(unit_id, callback)


func _start_load(unit_id: String, callback: RefCounted) -> void:
	if callback is RewardedInterstitialAdLoadCallback:
		RewardedInterstitialAdLoader.new().load(unit_id, AdRequest.new(), callback)
	else:
		RewardedAdLoader.new().load(unit_id, AdRequest.new(), callback)


func _on_loaded(ad: RefCounted, generation: int, kind: String) -> void:
	if generation != _generation:
		ad.destroy()
		return
	_loading = false
	_load_kind = ""
	_ad = ad
	_ad_kind = kind
	_loaded_at = Time.get_ticks_msec()
	_retry_at = 0
	last_error = {}
	print("AdMob reward ready: ", kind)
	if busy:
		_show()


func _on_load_failed(error: LoadAdError, generation: int, kind: String) -> void:
	if generation != _generation:
		return
	_clear_ad()
	_retry_at = Time.get_ticks_msec() + 30000
	_record_load_error(error, kind)
	if busy:
		# A brief network/SDK failure can recover. Retry from _process, never
		# recursively from the callback, and keep the user's original choice.
		if error != null and error.domain == GOOGLE_ADS_ERROR_DOMAIN \
				and error.code in [0, 2] and _request_retries < 1:
			_request_retries += 1
			_request_retry_at = Time.get_ticks_msec() + TRANSIENT_RETRY_MSEC
			notify("광고 연결을 다시 시도하고 있습니다...")
			return
		_finish(false, _load_error_message(error))


func _load_error_message(error: LoadAdError) -> String:
	if error != null and error.domain == GOOGLE_ADS_ERROR_DOMAIN:
		match error.code:
			1, 8:
				return "광고를 사용할 수 없습니다. 잠시 후 다시 시도하세요."
			2:
				return "인터넷 연결을 확인한 뒤 다시 시도하세요."
			3, 9:
				return "지금 표시할 광고가 없습니다. 잠시 후 다시 시도하세요."
	return "광고를 불러오지 못했습니다. 잠시 후 다시 시도하세요."


func _record_load_error(error: LoadAdError, kind: String) -> void:
	last_error = {"kind": kind, "code": -1, "domain": "", "message": "Missing SDK error details"}
	last_error["format"] = reward_format(kind)
	if error != null:
		last_error["code"] = error.code
		last_error["domain"] = error.domain
		last_error["message"] = error.message
		if error.cause != null:
			last_error["cause"] = {"code": error.cause.code, "domain": error.cause.domain, "message": error.cause.message}
		if error.response_info != null:
			last_error["response_id"] = error.response_info.response_id
			last_error["adapter"] = error.response_info.mediation_adapter_class_name
			var adapters: Array[Dictionary] = []
			for adapter in error.response_info.adapter_responses:
				if adapter != null and adapter.ad_error != null:
					adapters.append({"adapter": adapter.adapter_class_name, "code": adapter.ad_error.code,
						"domain": adapter.ad_error.domain, "message": adapter.ad_error.message})
			last_error["adapter_errors"] = adapters
	print("AdMob load failed: ", JSON.stringify(last_error))


func _show() -> void:
	if _ad == null or not busy:
		return
	var kind := String(_request["kind"])
	if not _ad_ready(kind):
		_load(kind)
		return
	if not Run.reward_allowed(String(_request["kind"]), _request["data"]):
		_finish(false, "상태가 변경되어 광고 요청을 취소했습니다.")
		return
	_showing = true
	print("AdMob showing reward: ", kind)
	var callback := FullScreenContentCallback.new()
	callback.on_ad_dismissed_full_screen_content = _on_closed.bind(_serial)
	callback.on_ad_failed_to_show_full_screen_content = _on_show_failed.bind(_serial)
	_ad.full_screen_content_callback = callback
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = _on_earned.bind(_serial)
	_ad.show(listener)


func _on_earned(_item: RewardedItem, serial: int) -> void:
	if not busy or not _showing or serial != _serial or _awarded:
		return
	_awarded = Run.apply_ad_reward(String(_request["kind"]), _request["data"])
	print("AdMob earned reward: kind=%s applied=%s" % [_request["kind"], _awarded])


func _on_closed(serial: int) -> void:
	if serial != _serial or not busy:
		return
	_finish(_awarded, "광고 보상을 받았습니다." if _awarded else "시청이 완료되지 않아 보상이 지급되지 않았습니다.")


func _on_show_failed(error: AdError, serial: int) -> void:
	if serial != _serial or not busy:
		return
	print("Rewarded ad show failed: ", error.message)
	_finish(false, "광고를 표시하지 못했습니다. 다시 시도하세요.")


func _finish(rewarded: bool, text: String) -> void:
	var kind := String(_request.get("kind", ""))
	_clear_ad()
	busy = false
	_showing = false
	_request_retry_at = 0
	_request_deadline = 0
	_request = {}
	notify(text)
	_reward_notice = rewarded
	if rewarded:
		_message_left = 3.0
	completed.emit(kind, rewarded)


class Notice extends Node2D:
	var service: CanvasLayer
	var ui := Ui.new()

	func _input(event: InputEvent) -> void:
		if service.dismiss_notice_input(event):
			return
		if not service.busy:
			return
		get_viewport().set_input_as_handled()
		if not service._showing and event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT and ui.hit(event.position) == "cancel":
			service._finish(false, "광고 요청을 취소했습니다.")

	func _draw() -> void:
		ui.begin()
		if service.busy and not service._showing:
			draw_rect(Look.SCREEN, Color(0, 0, 0, 0.8))
			Look.material_panel(self, Rect2(320, 282, 640, 228), Look.PANEL, Look.CRYSTAL)
			Look.text_center(self, Vector2(640, 350), service.message, 27, Look.INK)
			ui.button(self, Rect2(500, 424, 280, 56), "취소", "cancel", true, Look.PANEL_EDGE, 24)
		elif service._message_left > 0 and not service._showing and service._reward_notice:
			var box := Rect2(290, 89, 700, 132)
			Look.fill_round(self, box.grow(8), 8, Color(Look.GOLD, 0.12))
			Look.fill_round(self, Rect2(box.position + Vector2(0, 6), box.size), 6, Color(0, 0, 0, 0.55))
			Look.material_panel(self, box, Color("#203635"), Look.GOLD)
			var seal := Vector2(350, 150)
			draw_circle(seal, 29, Look.GOLD)
			draw_line(seal + Vector2(-12, 0), seal + Vector2(-3, 9), Look.BG_DEEP, 5, true)
			draw_line(seal + Vector2(-3, 9), seal + Vector2(14, -11), Look.BG_DEEP, 5, true)
			Look.text_left(self, Vector2(398, 128), "보상 획득", 21, Look.GOLD)
			Look.text_center_fit(self, Vector2(681, 169), service.message, 31, Look.INK, 560, 21)
		elif service._message_left > 0 and not service._showing:
			Look.fill_round(self, Rect2(210, 72, 860, 52), 5, Color(0.03, 0.09, 0.12, 0.96))
			Look.text_center_fit(self, Vector2(640, 98), service.message, 22, Look.CRYSTAL, 828, 16)
