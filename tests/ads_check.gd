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
	check_star_pull_ads(service, ids["card"])
	check_load_recovery(service)
	check_interstitial_rewards(service)
	check_repeated_revive_ads(service)
	check_repeated_fusion_ads(service)
	check_arena_star_pull_ads(service)

	for path in originals:
		ProjectSettings.set_setting(path, originals[path])
	service.queue_free()
	finish("AdMob placement and callback checks")


func check_arena_star_pull_ads(service: FakeAds) -> void:
	Run.running = false
	Arena.start_run(90876)
	Arena.choose_theme(0)
	Arena.orbit.assign(Fixture.orbit_for(2))
	var before: Dictionary = Arena.snapshot()["rite"].duplicate(true)
	var gold_before: int = Arena.gold
	check(service._preload_kind() == "card", "continuous arena preloads the existing star-pull placement")
	check(not Arena.reward_allowed("continue") and not Arena.reward_allowed("crystal")
			and not Arena.reward_allowed("fusion_undo"), "arena does not apply legacy wave rewards")
	check(service.request_reward("card", {"slot": Arena.pull_target()}), "arena rite starts a star-pull request")
	check(service._request["mode"] == "arena" and service._request["data"]["summon_count"] == 0,
			"arena ad captures mode and summon identity")
	var ad := service.complete_load(service.loads.size() - 1)
	Arena.sim.step(0.25)
	check(ad.shown and Arena.snapshot()["rite"] == before and Arena.sim.elapsed == 0,
			"showing the ad grants nothing and keeps the battlefield paused")
	ad.listener.on_user_earned_reward.call(null)
	check(Arena.rite_stars() == 3 and Arena.pulls == 1 and Arena.gold == gold_before,
			"arena earns one star without charging summon gold")
	before = Arena.snapshot()["rite"].duplicate(true)
	ad.listener.on_user_earned_reward.call(null)
	check(Arena.snapshot()["rite"] == before, "duplicate arena reward callback grants nothing")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	check(not service.busy and ArenaValidation.valid(Arena.snapshot()), "arena rewarded rite remains resumable")

	check(service.request_reward("card", {"slot": Arena.pull_target()}), "next arena star may be requested")
	ad = service.complete_load(service.loads.size() - 1)
	Arena.confirm_summon()
	Arena.close_modal()
	Arena.gold = Arena.summon_cost()
	Arena.begin_summon()
	Arena.orbit.assign(Fixture.orbit_for(3))
	before = Arena.snapshot()["rite"].duplicate(true)
	ad.listener.on_user_earned_reward.call(null)
	check(Arena.snapshot()["rite"] == before and not service._awarded,
			"late reward from a previous summon cannot alter the new rite on wave 1")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()

	service.request_reward("card", {"slot": Arena.pull_target()})
	ad = service.complete_load(service.loads.size() - 1)
	Arena.respin()
	Arena.orbit.assign(Fixture.orbit_for(3))
	before = Arena.snapshot()["rite"].duplicate(true)
	ad.listener.on_user_earned_reward.call(null)
	check(Arena.snapshot()["rite"] == before, "arena re-spin rejects stale ad reward")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()

	service.request_reward("card", {"slot": Arena.pull_target()})
	var index := service.loads.size() - 1
	Arena.confirm_summon()
	ad = service.complete_load(index)
	check(not ad.shown and ad.destroyed and not service.busy, "confirmed arena rite cancels late ad loading")
	Arena.close_modal()
	check(not service.request_reward("card", {"slot": 4}), "battle rejects star-pull requests")

	Arena.running = false
	Fixture.fresh(90876)
	Fixture.stack(2)
	service.request_reward("card", pull_request())
	ad = service.complete_load(service.loads.size() - 1)
	Arena.start_run(90876)
	Arena.choose_theme(0)
	Arena.orbit.assign(Fixture.orbit_for(2))
	before = rite_state()
	ad.listener.on_user_earned_reward.call(null)
	check(rite_state() == before and Arena.pulls == 0,
			"entering arena rejects a legacy ad even with the same seed and wave")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	Arena.running = false
	Run.running = false


func check_interstitial_rewards(service: FakeAds) -> void:
	Fixture.fresh(816, 12)
	Run.prepare_battle()
	var before_revive := Run.snapshot()
	Run.add_lives(-Run.max_lives())
	check(service.request_reward("continue"), "defeat starts revive placement")
	var ad := service.complete_load(service.loads.size() - 1)
	check(ad is FakeInterstitial and ad.shown, "revive shows rewarded interstitial")
	ad.listener.on_user_earned_reward.call(null)
	check(Run.running and Run.lives == Run.max_lives() and Run.last_result["gold"] == Balance.REVIVE_GOLD,
			"interstitial earned callback restores all crystals and grants the revival gold")
	check(Run.snapshot()["heroes"] == before_revive["heroes"] and Run.bench.size() == before_revive["bench"].size(),
			"earned gold reward leaves all heroes untouched")
	check(Run.last_result["reward_pending"], "earned reward waits for the player to see and confirm its identity")
	var rewarded := Run.snapshot()
	ad.listener.on_user_earned_reward.call(null)
	check(Run.snapshot() == rewarded, "duplicate earned callback cannot grant a second hero")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	Fixture.fresh(708, 1)
	# 5성 영웅 일곱 장(등급은 영웅 한 장의 것이라 누구든 5성일 수 있다).
	var rare: Dictionary = Roster.UNITS[Roster.UNITS.size() - 1]
	for i in range(7):
		Run.gain_hero(rare, Balance.TIER_MAX, false)
	Run.phase = Run.Phase.SHOP
	var before := Run.snapshot()
	var result := Run.fuse_heroes([Run.FUSION_BENCH, Run.FUSION_BENCH + 1,
			Run.FUSION_BENCH + 2, Run.FUSION_BENCH + 3, Run.FUSION_BENCH + 4])
	check(not bool(result.get("failed", true)) and float(result.get("awakening_mult", 1.0)) > 1.0,
			"highest-tier fusion guarantees an awakened result")
	check(service.request_reward("fusion_undo", {"fusion_id": result["id"]}), "successful fusion starts merge restore placement")
	ad = service.complete_load(service.loads.size() - 1)
	check(ad is FakeInterstitial and ad.shown, "merge restore shows rewarded interstitial")
	ad.listener.on_user_earned_reward.call(null)
	var after := Run.snapshot()
	check(after["heroes"] == before["heroes"] and after["bench"] == before["bench"],
			"interstitial earned callback restores exact fusion materials")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()


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
		check(Run.snapshot()["heroes"] == before["heroes"] and Run.bench.size() == before["bench"].size(),
				"each new ad preserves all heroes")
		check(Run.gold == before["gold"] + Balance.REVIVE_GOLD, "every ad grants exactly the revival gold")
		var rewarded := Run.snapshot()
		ad.listener.on_user_earned_reward.call(null)
		check(Run.snapshot() == rewarded, "duplicate completion cannot grant another revival reward")
		ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
		check(service._message_left == 0.0, "dedicated reveal replaces the generic success notice")
		check(not service.busy and ad.destroyed and Run.acknowledge_revive_reward(),
				"closing each ad unlocks confirmation and the next battle")
		previous_ad = ad


func fail_load(service: FakeAds, index: int, code: int, domain := "com.google.android.gms.ads") -> void:
	service.loads[index]["callback"].on_ad_failed_to_load.call(LoadAdError.new(null, code, domain, "SDK diagnostic", null))


func check_repeated_fusion_ads(service: FakeAds) -> void:
	Fixture.fresh(91208, 1)
	var material: Dictionary = Roster.UNITS[0]
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
	Fixture.stack(1)          # 문 밖에 별 넷 — 끌어올 별이 넉넉하다
	Run.running = false
	check(service._preload_kind() == "card", "the star-pull placement is preloaded at the title")
	Run.running = true
	var before := rite_state()
	service.request_reward("card", pull_request())
	var intended := service._request.duplicate(true)
	var index := service.loads.size() - 1
	fail_load(service, index, 2)
	check(service.busy and service._request_retry_at > 0, "temporary network failure schedules recovery")
	check(service.loads.size() == index + 1, "failure callback does not recursively load")
	check(rite_state() == before, "retry does not pull a star or consume a reward")
	check(service.last_error.get("code") == 2, "SDK diagnostic preserves actual error code")
	var stale := service.complete_load(index)
	check(stale.destroyed, "failed load cannot later populate the retry cache")
	service._request_retry_at = Time.get_ticks_msec() - 1
	service._process(0)
	check(service.loads.size() == index + 2 and service._request == intended, "delayed retry preserves the exact requested pull")
	var ad := service.complete_load(index + 1)
	check(ad.shown and rite_state() == before, "recovered ad plays before granting any reward")
	ad.listener.on_user_earned_reward.call(null)
	var ring := int(intended["data"]["slot"])
	check(ring == Rite.RINGS - 1 and Rite.in_gate(ring, Run.orbit[ring]) and Run.rite_stars() == 2 and Run.pulls == 1,
			"recovered ad pulls the requested star after the earned callback")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	check(not service.busy and service.last_error.is_empty(), "successful recovery clears the error and unlocks input")

	before = rite_state()
	service.request_reward("card", pull_request())
	index = service.loads.size() - 1
	fail_load(service, index, 2)
	service._request_retry_at = Time.get_ticks_msec() - 1
	service._process(0)
	fail_load(service, index + 1, 2)
	check(not service.busy and service._request_retry_at == 0 and rite_state() == before, "second failure stops retrying without a reward")
	check(service.message == "인터넷 연결을 확인한 뒤 다시 시도하세요.", "network failure is not mislabeled as no inventory")

	for code in [1, 3, 8, 9]:
		service.request_reward("card", pull_request())
		index = service.loads.size() - 1
		fail_load(service, index, code)
		check(not service.busy and service.loads.size() == index + 1, "configuration/no-fill errors do not spin in foreground: " + str(code))
		check(service.message == ("지금 표시할 광고가 없습니다. 잠시 후 다시 시도하세요." if code in [3, 9] \
				else "광고를 사용할 수 없습니다. 잠시 후 다시 시도하세요."), "specific failure category: " + str(code))
	check(rite_state() == before, "no-fill and configuration failures preserve the rite")
	service._process(0)
	check(service.loads.size() == index + 1, "background preloading respects the failure cooldown")
	check(service._load_error_message(LoadAdError.new(null, 2, "mediation.vendor", "vendor code", null)) \
			== "광고를 불러오지 못했습니다. 잠시 후 다시 시도하세요.", "third-party codes are not mistaken for Google's network code")
	check(not service._load_error_message(null).is_empty(), "missing SDK details still produce a failure notice")

	service.request_reward("card", pull_request())
	index = service.loads.size() - 1
	fail_load(service, index, 0)
	check(service.busy and service._request_retry_at > 0, "internal SDK failure also permits one delayed retry")
	service._finish(false, "cancel")
	service._process(0)
	check(not service.busy and service.loads.size() == index + 1, "cancel during retry delay prevents the retry")

	service.request_reward("card", pull_request())
	index = service.loads.size() - 1
	fail_load(service, index, 2)
	service._request_deadline = 1
	service._process(0)
	check(not service.busy and service._request_retry_at == 0 and service.loads.size() == index + 1,
			"overall request deadline includes recovery delay")
	check(rite_state() == before, "every failed or cancelled request leaves the rite untouched")


## 지금 끌어올 별(문 밖의 가장 바깥 별)을 겨눈 광고 요청. 화면의 「별 끌어오기」가 보내는 꼴 그대로다.
func pull_request() -> Dictionary:
	return {"slot": Run.pull_target()}


## 의식의 상태 통째 — 별 다섯의 자리 · 다시 돌린 횟수 · 유료 횟수 · 끌어온 횟수.
## 「광고가 아무것도 안 바꿨다」를 이것 하나로 잰다.
func rite_state() -> Dictionary:
	return (Run.snapshot()["rite"] as Dictionary).duplicate(true)


## 보상형 광고 「별 끌어오기」 — 광고 단위는 예전 「원하는 카드」의 것을 그대로 쓴다(kind "card").
##
## ★ 지키는 것은 포커 시절과 같다: 요청만으로는 아무것도 안 바뀐다 / 끝까지 본 광고만 준다 /
##   한 광고는 한 번만 준다 / 광고를 보는 사이에 상태가 바뀌었으면 그 보상은 거절한다.
##   「상태가 바뀌었다」가 지금은 **의식의 판 번호**(다시 돌린 횟수 + 끌어온 횟수)다.
func check_star_pull_ads(service: FakeAds, unit_id: String) -> void:
	Fixture.fresh(87234)
	Fixture.stack(2)          # 문 안 0 · 1번, 문 밖 2 · 3 · 4번
	Run.gold = 0
	var before := rite_state()
	var request := pull_request()
	check(service._preload_kind() == "card", "the rite preloads the star-pull placement")
	check(service.request_reward("card", request), "a star pull starts a real SDK request")
	check(service.loads.back()["unit"] == unit_id, "star pull uses the ADMOB_REWARD_CARD_CHANGE_ID mapping")
	var index := service.loads.size() - 1
	check(rite_state() == before, "the request moves no star and spends no re-spin")
	check(int(service._request["data"]["revision"]) == Run.rite_revision()
			and int(service._request["data"]["seed"]) == Run.run_seed
			and int(service._request["data"]["wave"]) == Run.wave, "the request records the rite revision, the run and the wave")
	# 요청한 쪽의 사전을 나중에 바꿔도 잡아 둔 요청은 안 바뀐다.
	request["slot"] = 2
	var ad := service.complete_load(index)
	var intended := int(service._request["data"]["slot"])
	check(intended == Rite.RINGS - 1 and ad.shown and rite_state() == before, "loading and showing preserve the stars and the captured ring")
	ad.listener.on_user_earned_reward.call(null)
	check(Rite.in_gate(intended, Run.orbit[intended]) and Run.rite_stars() == 3 and Run.gold == 0,
			"the earned callback pulls the captured star at no gold cost")
	for other in range(Rite.RINGS):
		if other != intended:
			check(Run.orbit[other] == int(before["orbit"][other]), "the other stars stay where they stopped")
	check(Run.pulls == 1 and Run.spins == 0 and Run.paid_spins == 0 and Run.respins_left() == Run.free_rerolls(),
			"an earned pull is counted once and spends no re-spin")
	var pulled := rite_state()
	ad.listener.on_user_earned_reward.call(null)
	check(rite_state() == pulled, "a duplicate earned callback does not pull twice")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	check(not service.busy, "closing the star-pull ad unlocks the rite")
	var first_ad := ad

	before = rite_state()
	check(Run.pull_target() == Rite.RINGS - 2, "the next pull aims at the next outermost star")
	service.request_reward("card", pull_request())
	ad = service.complete_load(service.loads.size() - 1)
	# 앞선 광고의 콜백이 늦게 다시 와도 지금 열린 요청의 별은 끌려오지 않는다.
	first_ad.listener.on_user_earned_reward.call(null)
	check(rite_state() == before and service.busy, "an earlier ad's callback cannot pull the star of the current request")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	check(rite_state() == before and not service.busy, "early close preserves the stars and the pull count")
	service.request_reward("card", pull_request())
	index = service.loads.size() - 1
	service._finish(false, "cancel")
	check(service.complete_load(index).destroyed and rite_state() == before, "a cancelled pull discards the late ad without moving a star")

	service.request_reward("card", pull_request())
	index = service.loads.size() - 1
	Run.phase = Run.Phase.SWAP
	ad = service.complete_load(index)
	check(not ad.shown and ad.destroyed and not service.busy, "a confirmed rite cancels the pending pull before display")
	Run.phase = Run.Phase.DRAW
	check(rite_state() == before, "the cancelled pull changed nothing")

	# 광고를 보는 사이에 다시 돌렸다 — 그 별이 여전히 문 밖에 서 있어도 옛 보상은 거절한다.
	service.request_reward("card", pull_request())
	ad = service.complete_load(service.loads.size() - 1)
	var aimed := int(service._request["data"]["slot"])
	check(not Run.respin().is_empty(), "the rite is re-spun while the ad is open")
	Run.orbit.assign(Fixture.orbit_for(2))
	before = rite_state()
	check(Run.can_pull(aimed), "the aimed star still stands outside the gate")
	ad.listener.on_user_earned_reward.call(null)
	check(rite_state() == before, "a re-spin after the request rejects the late earned pull")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	check(not service.busy, "the rejected pull still unlocks the rite")

	# 그 별이 이미 문 안에 섰다면(다른 길로 들어왔다) 광고가 끝나도 한 번 더 세지 않는다.
	service.request_reward("card", pull_request())
	ad = service.complete_load(service.loads.size() - 1)
	aimed = int(service._request["data"]["slot"])
	Run.orbit[aimed] = Fixture.orbit_for(Rite.RINGS)[aimed]
	var current := rite_state()
	ad.listener.on_user_earned_reward.call(null)
	check(rite_state() == current, "a star that already stands inside the gate is not pulled or counted again")
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()

	# 끌어올 별이 없으면(5성) 광고를 아예 청하지 않는다.
	Fixture.stack(Rite.MAX_STARS)
	var loads := service.loads.size()
	check(Run.pull_target() == -1 and not service.request_reward("card", pull_request())
			and not service.request_reward("card", {"slot": Rite.RINGS - 1}) and not service.busy
			and service.loads.size() == loads, "with five stars in the gate no star-pull ad is requested")
	# 조커가 확정 때 끌어올 별도, 광고로 먼저 끌어오면 그 다음 바깥 별로 넘어간다.
	Fixture.stack(3)
	Run.owned_passives.assign(["joker"])
	Run.passives.assign(["joker"])
	check(service.request_reward("card", pull_request()), "a pull can be requested while the joker is active")
	ad = service.complete_load(service.loads.size() - 1)
	ad.listener.on_user_earned_reward.call(null)
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	var preview := Run.rite_preview()
	check(Run.rite_stars() == 4 and int(preview["stars"]) == 5 and int(preview["joker"]) == Rite.RINGS - 2,
			"after the ad pulled the outermost star the joker aims at the next one")
	var summoned := Run.confirm_summon()
	check(int(summoned["stars"]) == Rite.MAX_STARS and int(summoned["tier"]) == Balance.TIER_MAX
			and int(summoned["joker"]) == Rite.RINGS - 2, "ad pull and joker stack into five stars")
