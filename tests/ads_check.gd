extends Harness

class FakeAd extends RewardedAd:
	var destroyed := false
	var shown := false
	var listener: OnUserEarnedRewardListener

	func _init() -> void:
		super(0)

	func show(reward_listener := OnUserEarnedRewardListener.new()) -> void:
		shown = true
		listener = reward_listener

	func destroy() -> void:
		destroyed = true


class FakeInterstitial extends RewardedInterstitialAd:
	var destroyed := false
	var shown := false
	var listener: OnUserEarnedRewardListener

	func _init() -> void:
		super(0)

	func show(reward_listener := OnUserEarnedRewardListener.new()) -> void:
		shown = true
		listener = reward_listener

	func destroy() -> void:
		destroyed = true


class FakeAds extends "res://core/ads.gd":
	var loads: Array[Dictionary] = []

	func _ready() -> void:
		super()
		_native = true
		_initialized = true
		set_process(false)

	func _start_load(unit_id: String, callback: RefCounted) -> void:
		loads.append({"unit": unit_id, "callback": callback})

	func complete_load(index: int) -> RefCounted:
		var ad: RefCounted = FakeInterstitial.new() if loads[index]["callback"] is RewardedInterstitialAdLoadCallback else FakeAd.new()
		loads[index]["callback"].on_ad_loaded.call(ad)
		return ad


func _ready() -> void:
	if not require_no_save():
		return
	var service := FakeAds.new()
	add_child(service)
	var originals := {}
	var ids := {
		"card": "ca-app-pub-1111111111111111/1111111111",
		"fusion_undo": "ca-app-pub-1111111111111111/2222222222",
		"continue": "ca-app-pub-1111111111111111/3333333333",
		"crystal": "ca-app-pub-1111111111111111/4444444444",
	}
	for kind in ids:
		var path: String = service.UNIT_SETTINGS[kind]
		originals[path] = ProjectSettings.get_setting(path)
		ProjectSettings.set_setting(path, ids[kind])
		service._load(kind)
		check(service.loads.back()["unit"] == ids[kind], "SDK load receives the matching placement: " + kind)
		check((service.loads.back()["callback"] is RewardedAdLoadCallback) == (kind == "card"),
				"card uses rewarded loader, other placements use rewarded interstitial: " + kind)
	check(service.rewarded_unit_id("unknown").is_empty(), "unknown placement has no ad unit")
	var stale := service.complete_load(0)
	check(stale.destroyed and service._ad == null, "load from previous placement is destroyed")
	var cached := service.complete_load(3)
	check(not cached.destroyed and not cached.shown, "current placement is cached without auto-showing")
	service._load("continue")
	check(cached.destroyed, "changing placement discards the previous cached ad")
	var expired := service.complete_load(4)
	service._loaded_at = Time.get_ticks_msec() - service.AD_MAX_AGE_MSEC
	service._load("continue")
	check(expired.destroyed and service.loads.size() == 6, "expired cached ad is reloaded")
	service._finish(false, "cancel")
	check(service.complete_load(5).destroyed, "cancelled request cannot populate the next request")

	Fixture.fresh(12345)
	Run.phase = Run.Phase.SHOP
	Run.lives = 1
	check(service.request_reward("crystal"), "valid reward starts loading")
	var index := service.loads.size() - 1
	check(not service.request_reward("crystal"), "busy request cannot start another reward")
	service._load("crystal")
	check(service.loads.size() == index + 1, "matching in-flight load is reused")
	var reward_ad := service.complete_load(index)
	check(reward_ad.shown and Run.lives == 1, "showing an ad does not grant a reward")
	var serial := service._serial
	reward_ad.listener.on_user_earned_reward.call(null)
	check(Run.lives == Run.max_lives(), "only earned callback grants the heal")
	Run.lives = 1
	reward_ad.listener.on_user_earned_reward.call(null)
	check(Run.lives == 1, "duplicate earned callback cannot grant twice")
	reward_ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	check(not service.busy and reward_ad.destroyed, "closed ad is destroyed and unlocks input")

	check(service.request_reward("crystal"), "next reward can load after close")
	reward_ad = service.complete_load(service.loads.size() - 1)
	service._on_earned(null, serial)
	check(Run.lives == 1, "previous request's reward callback is rejected")
	reward_ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	check(Run.lives == 1 and not service.busy, "early close gives no reward")

	service.request_reward("crystal")
	index = service.loads.size() - 1
	service.loads[index]["callback"].on_ad_failed_to_load.call(LoadAdError.new(null, 3, "test", "no fill", null))
	check(not service.busy and Run.lives == 1, "no-fill failure gives no reward and unlocks input")
	service.request_reward("crystal")
	reward_ad = service.complete_load(service.loads.size() - 1)
	reward_ad.full_screen_content_callback.on_ad_failed_to_show_full_screen_content.call(AdError.new(1, "test", "show failure", null))
	check(not service.busy and reward_ad.destroyed and Run.lives == 1, "show failure gives no reward")

	service.request_reward("crystal")
	reward_ad = service.complete_load(service.loads.size() - 1)
	Run.run_seed += 1
	reward_ad.listener.on_user_earned_reward.call(null)
	check(Run.lives == 1, "reward from another run is rejected")
	reward_ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	service.request_reward("crystal")
	index = service.loads.size() - 1
	service._deadline = -1
	service._process(0)
	check(not service.busy and Run.lives == 1, "load timeout gives no reward and unlocks input")
	check(service.complete_load(index).destroyed, "late load after timeout is destroyed")
	check_card_choice_ads(service, ids["card"])
	check_load_recovery(service)
	check_interstitial_rewards(service)
	check_repeated_revive_ads(service)
	check_repeated_fusion_ads(service)

	for path in originals:
		ProjectSettings.set_setting(path, originals[path])
	service.queue_free()
	finish("AdMob placement and callback checks")


func check_interstitial_rewards(service: FakeAds) -> void:
	Fixture.fresh(816, 12)
	Run.prepare_battle()
	var before_revive := Run.snapshot()
	Run.add_lives(-Run.max_lives())
	check(service.request_reward("continue"), "defeat starts revive placement")
	var ad := service.complete_load(service.loads.size() - 1)
	check(ad is FakeInterstitial and ad.shown, "revive shows rewarded interstitial")
	ad.listener.on_user_earned_reward.call(null)
	check(Run.running and Run.lives == Run.max_lives() and int(Run.last_result["hand"]) == 9,
			"interstitial earned callback restores all crystals and highest-tier hero")
	check(Run.snapshot()["heroes"] == before_revive["heroes"] and Run.bench.size() == before_revive["bench"].size() + 1,
			"earned reward is reserved without automatic formation changes")
	check(Run.last_result["reward_pending"], "earned reward waits for the player to see and confirm its identity")
	var rewarded := Run.snapshot()
	ad.listener.on_user_earned_reward.call(null)
	check(Run.snapshot() == rewarded, "duplicate earned callback cannot grant a second hero")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	var exercised := false
	for attempt in range(32):
		Fixture.fresh(708 + attempt, 1)
		var rare: Dictionary = Roster.units_of_tier(9)[0]
		for i in range(7):
			Run.gain_hero(rare, 9, false)
		Run.phase = Run.Phase.SHOP
		var before := Run.snapshot()
		var result := Run.fuse_heroes([Run.FUSION_BENCH, Run.FUSION_BENCH + 1,
				Run.FUSION_BENCH + 2, Run.FUSION_BENCH + 3, Run.FUSION_BENCH + 4])
		if not bool(result.get("failed", false)):
			continue
		check(service.request_reward("fusion_undo", {"fusion_id": result["id"]}), "failed fusion starts merge restore placement")
		ad = service.complete_load(service.loads.size() - 1)
		check(ad is FakeInterstitial and ad.shown, "merge restore shows rewarded interstitial")
		ad.listener.on_user_earned_reward.call(null)
		var after := Run.snapshot()
		check(after["heroes"] == before["heroes"] and after["bench"] == before["bench"],
				"interstitial earned callback restores exact fusion materials")
		ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
		exercised = true
		break
	check(exercised, "merge restore callback exercised")


func check_repeated_revive_ads(service: FakeAds) -> void:
	Fixture.fresh(922816, 12)
	var previous_ad: RefCounted
	for attempt in range(12):
		Run.prepare_battle()
		var before := Run.snapshot()
		Run.add_lives(-Run.max_lives())
		var defeat := Run.snapshot()
		check(service._preload_kind() == "continue", "every repeated defeat preloads another revive ad")
		if attempt == 1:
			check(service.request_reward("continue"), "repeat revival can request an ad before cancellation")
			var cancelled_load := service.loads.size() - 1
			service._finish(false, "cancel")
			check(service.complete_load(cancelled_load).destroyed and Run.snapshot() == defeat,
					"cancelled repeat revival discards late ads without changing the defeat")
			check(service.request_reward("continue"), "cancelled revival can retry")
			var skipped := service.complete_load(service.loads.size() - 1)
			skipped.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
			skipped.listener.on_user_earned_reward.call(null)
			check(Run.snapshot() == defeat and Run.reward_allowed("continue"),
					"incomplete viewing and late reward do not revive or consume eligibility")
			check(service.request_reward("continue"), "incomplete viewing can retry")
			fail_load(service, service.loads.size() - 1, 3)
			check(not service.busy and Run.snapshot() == defeat and Run.reward_allowed("continue"),
					"failed ad load does not consume another revival")
			check(service.request_reward("continue"), "failed load can retry revival")
			var failed := service.complete_load(service.loads.size() - 1)
			failed.full_screen_content_callback.on_ad_failed_to_show_full_screen_content.call(AdError.new(1, "test", "show failure", null))
			check(not service.busy and Run.snapshot() == defeat and Run.reward_allowed("continue"),
					"failed ad display does not consume another revival")
		var requested := service.request_reward("continue")
		check(requested, "every repeated defeat can request a fresh ad: " + str(attempt + 1))
		if not requested:
			break
		check(not service.request_reward("continue"), "repeated taps cannot request parallel revival ads")
		var ad := service.complete_load(service.loads.size() - 1)
		check(ad is FakeInterstitial and ad.shown and Run.snapshot() == defeat,
				"every revival needs completion of a newly shown interstitial")
		if previous_ad != null:
			previous_ad.listener.on_user_earned_reward.call(null)
			previous_ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
			check(service.busy and Run.snapshot() == defeat, "earlier ad callbacks cannot revive or close the current request")
		ad.listener.on_user_earned_reward.call(null)
		check(Run.phase == Run.Phase.SWAP and Run.lives == Run.max_lives() and Run.wave == before["wave"],
				"each new ad completion revives the same wave")
		check(Run.snapshot()["heroes"] == before["heroes"] and Run.bench.size() == before["bench"].size() + 1,
				"each new ad preserves the formation and grants exactly one reserve hero")
		var rewarded := Run.snapshot()
		ad.listener.on_user_earned_reward.call(null)
		check(Run.snapshot() == rewarded, "duplicate completion cannot grant another revival reward")
		ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
		check(not service.busy and ad.destroyed and Run.acknowledge_revive_reward(),
				"closing each ad unlocks confirmation and the next battle")
		previous_ad = ad


func fail_load(service: FakeAds, index: int, code: int, domain := "com.google.android.gms.ads") -> void:
	service.loads[index]["callback"].on_ad_failed_to_load.call(LoadAdError.new(null, code, domain, "SDK diagnostic", null))


func check_repeated_fusion_ads(service: FakeAds) -> void:
	Fixture.fresh(91208, 1)
	var material: Dictionary = Roster.units_of_tier(0)[0]
	for i in range(7):
		Run.gain_hero(material, 0, false, false)
	Run.phase = Run.Phase.SHOP
	var before := Run.snapshot()
	var previous_ad: RefCounted
	var upgraded := false
	for attempt in range(12):
		var result := Run.fuse_heroes([Run.FUSION_BENCH, Run.FUSION_BENCH + 1,
				Run.FUSION_BENCH + 2, Run.FUSION_BENCH + 3, Run.FUSION_BENCH + 4])
		check(not result.is_empty(), "fusion can repeat after the preceding ad refund")
		if result.is_empty():
			break
		upgraded = upgraded or int(result["tier"]) > 0
		var pending := Run.snapshot()
		var request := {"fusion_id": result["id"]}
		check(service._preload_kind() == "fusion_undo", "every pending result can preload the next refund ad")
		if attempt == 0:
			check(service.request_reward("fusion_undo", request), "refund ad can be requested before cancelling")
			var cancelled_load := service.loads.size() - 1
			service._finish(false, "cancel")
			check(service.complete_load(cancelled_load).destroyed and Run.snapshot() == pending,
					"cancel leaves the same fusion available for another ad")
			check(service.request_reward("fusion_undo", request), "cancelled refund can be retried")
			fail_load(service, service.loads.size() - 1, 3)
			check(not service.busy and Run.snapshot() == pending, "failed load preserves the refund opportunity")
		if attempt == 1:
			check(service.request_reward("fusion_undo", request), "next fusion can request another ad")
			var skipped := service.complete_load(service.loads.size() - 1)
			skipped.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
			skipped.listener.on_user_earned_reward.call(null)
			check(not service.busy and Run.snapshot() == pending, "unfinished ad and late reward leave materials unrefunded")
		var load_count := service.loads.size()
		var started := service.request_reward("fusion_undo", request)
		check(started and service.loads.size() == load_count + 1, "each refund requests a fresh ad with no per-run limit")
		if not started:
			break
		var ad := service.complete_load(service.loads.size() - 1)
		check(ad is FakeInterstitial and ad.shown and Run.snapshot() == pending,
				"showing each new fusion ad alone never refunds materials")
		if previous_ad != null:
			previous_ad.listener.on_user_earned_reward.call(null)
			previous_ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
			check(service.busy and Run.snapshot() == pending, "old ad callbacks cannot affect a later fusion")
		ad.listener.on_user_earned_reward.call(null)
		var restored := Run.snapshot()
		check(restored["heroes"] == before["heroes"] and restored["bench"] == before["bench"]
				and Run.fusion_pending.is_empty(), "each newly completed ad restores exactly five materials")
		ad.listener.on_user_earned_reward.call(null)
		check(Run.snapshot() == restored, "duplicate reward cannot multiply materials")
		ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
		check(not service.busy and ad.destroyed, "closing each ad unlocks another fusion and ad")
		previous_ad = ad
	check(upgraded, "repeated SDK rewards include successful higher-tier fusion results")


func check_load_recovery(service: FakeAds) -> void:
	Fixture.fresh(99123)
	Run.running = false
	check(service._preload_kind() == "card", "first card placement is preloaded at the title")
	Run.running = true
	var before := Run.cards.duplicate()
	var counts := Run.rerolled.duplicate()
	service.request_reward("card", card_request(0))
	var intended := service._request.duplicate(true)
	var index := service.loads.size() - 1
	fail_load(service, index, 2)
	check(service.busy and service._request_retry_at > 0, "temporary network failure schedules recovery")
	check(service.loads.size() == index + 1, "failure callback does not recursively load")
	check(Run.cards == before and Run.rerolled == counts, "retry does not replace a card or consume a reward")
	check(service.last_error.get("code") == 2, "SDK diagnostic preserves actual error code")
	var stale := service.complete_load(index)
	check(stale.destroyed, "failed load cannot later populate the retry cache")
	service._request_retry_at = Time.get_ticks_msec() - 1
	service._process(0)
	check(service.loads.size() == index + 2 and service._request == intended, "delayed retry preserves the exact requested choice")
	var ad := service.complete_load(index + 1)
	check(ad.shown and Run.cards == before, "recovered ad plays before granting any reward")
	ad.listener.on_user_earned_reward.call(null)
	check(Run.cards[0] == int(intended["data"]["card"]), "recovered ad grants the selected card after earned callback")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	check(not service.busy and service.last_error.is_empty(), "successful recovery clears the error and unlocks input")

	before = Run.cards.duplicate()
	service.request_reward("card", card_request(0))
	index = service.loads.size() - 1
	fail_load(service, index, 2)
	service._request_retry_at = Time.get_ticks_msec() - 1
	service._process(0)
	fail_load(service, index + 1, 2)
	check(not service.busy and service._request_retry_at == 0 and Run.cards == before, "second failure stops retrying without a reward")
	check(service.message == "인터넷 연결을 확인한 뒤 다시 시도하세요.", "network failure is not mislabeled as no inventory")

	for code in [1, 3, 8, 9]:
		service.request_reward("card", card_request(0))
		index = service.loads.size() - 1
		fail_load(service, index, code)
		check(not service.busy and service.loads.size() == index + 1, "configuration/no-fill errors do not spin in foreground: " + str(code))
		check(service.message == ("지금 표시할 광고가 없습니다. 잠시 후 다시 시도하세요." if code in [3, 9] \
				else "광고를 사용할 수 없습니다. 잠시 후 다시 시도하세요."), "specific failure category: " + str(code))
	check(Run.cards == before, "no-fill and configuration failures preserve the hand")
	service._process(0)
	check(service.loads.size() == index + 1, "background preloading respects the failure cooldown")
	check(service._load_error_message(LoadAdError.new(null, 2, "mediation.vendor", "vendor code", null)) \
			== "광고를 불러오지 못했습니다. 잠시 후 다시 시도하세요.", "third-party codes are not mistaken for Google's network code")
	check(not service._load_error_message(null).is_empty(), "missing SDK details still produce a failure notice")

	service.request_reward("card", card_request(0))
	index = service.loads.size() - 1
	fail_load(service, index, 0)
	check(service.busy and service._request_retry_at > 0, "internal SDK failure also permits one delayed retry")
	service._finish(false, "cancel")
	service._process(0)
	check(not service.busy and service.loads.size() == index + 1, "cancel during retry delay prevents the retry")

	service.request_reward("card", card_request(0))
	index = service.loads.size() - 1
	fail_load(service, index, 2)
	service._request_deadline = 1
	service._process(0)
	check(not service.busy and service._request_retry_at == 0 and service.loads.size() == index + 1,
			"overall request deadline includes recovery delay")


func card_request(slot: int) -> Dictionary:
	var desired := 0
	while Run.cards.has(desired):
		desired += 1
	return {"slot": slot, "card": desired, "expected": Run.cards[slot]}


func check_card_choice_ads(service: FakeAds, unit_id: String) -> void:
	Fixture.fresh(87234)
	Run.gold = 0
	var before := Run.cards.duplicate()
	var counts := Run.rerolled.duplicate()
	var request := card_request(3)
	check(service._preload_kind() == "card", "draw phase preloads the direct-choice placement")
	check(service.request_reward("card", request), "direct choice starts a real SDK request")
	check(service.loads.back()["unit"] == unit_id, "direct choice uses ADMOB_REWARD_CARD_CHANGE_ID mapping")
	var index := service.loads.size() - 1
	check(Run.cards == before and Run.rerolled == counts, "request does not change hand or spend a replacement")
	check(int(service._request["data"]["revision"]) == counts[3], "request records slot revision")
	request["card"] = before[0]
	var ad := service.complete_load(index)
	var intended := int(service._request["data"]["card"])
	check(ad.shown and Run.cards == before, "loading and showing preserve the original hand")
	ad.listener.on_user_earned_reward.call(null)
	check(Run.cards[3] == intended and Run.gold == 0, "earned callback applies the captured choice at no gold cost")
	check(Run.rerolled[3] == counts[3] + 1, "earned choice counts one replacement")
	ad.listener.on_user_earned_reward.call(null)
	check(Run.rerolled[3] == counts[3] + 1, "duplicate earned choice does not count twice")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	check(not service.busy, "choice ad close unlocks the draw")

	before = Run.cards.duplicate()
	counts = Run.rerolled.duplicate()
	service.request_reward("card", card_request(0))
	ad = service.complete_load(service.loads.size() - 1)
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	check(Run.cards == before and Run.rerolled == counts, "early close preserves card and replacement count")
	service.request_reward("card", card_request(0))
	index = service.loads.size() - 1
	service._finish(false, "cancel")
	check(service.complete_load(index).destroyed and Run.cards == before, "cancelled choice discards late ad without changing hand")

	service.request_reward("card", card_request(0))
	index = service.loads.size() - 1
	Run.phase = Run.Phase.SWAP
	ad = service.complete_load(index)
	check(not ad.shown and ad.destroyed and not service.busy, "confirmed hand cancels the pending choice before display")
	Run.phase = Run.Phase.DRAW
	service.request_reward("card", card_request(0))
	ad = service.complete_load(service.loads.size() - 1)
	Run.rerolled[0] += 1
	ad.listener.on_user_earned_reward.call(null)
	check(Run.cards == before, "changed slot revision rejects a late earned choice")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()

	service.request_reward("card", card_request(0))
	ad = service.complete_load(service.loads.size() - 1)
	Run.cards[1] = int(service._request["data"]["card"])
	var current := Run.cards.duplicate()
	ad.listener.on_user_earned_reward.call(null)
	check(Run.cards == current, "choice that would duplicate another current card is rejected")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
