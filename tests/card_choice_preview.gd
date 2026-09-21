extends Harness

class FakeAd extends RewardedAd:
	var listener: OnUserEarnedRewardListener
	func _init() -> void:
		super(0)
	func show(reward_listener := OnUserEarnedRewardListener.new()) -> void:
		listener = reward_listener
	func destroy() -> void:
		pass

var main: Node2D
var output := "build/card-choice-restored/1280x800"


func capture(name_: String) -> void:
	main.screen.queue_redraw()
	Ads._notice.queue_redraw()
	await frames(2)
	await snap(output + "/" + name_ + ".png")


func click(id: String) -> void:
	check(tap(main.screen, id), "action reachable: " + id)
	await paint(main.screen)


func ready_ad() -> FakeAd:
	var ad := FakeAd.new()
	Ads._ad = ad
	Ads._ad_kind = "card"
	Ads._loaded_at = Time.get_ticks_msec()
	Ads._native = true
	Ads._initialized = true
	return ad


func _ready() -> void:
	if not require_no_save():
		return
	Save._readonly = true
	Ads.set_process(false)
	output = arg("--out", output)
	DirAccess.make_dir_recursive_absolute(output)
	main = load("res://game/main.gd").new()
	add_child(main)
	I18n.audit_enabled = true
	for language in ["ko", "en"]:
		I18n.set_locale(language)
		Fixture.fresh(15092026)
		Fixture.stack(2)
		var draw := DrawScreen.new()
		main._swap(draw)
		draw.set_process(false)
		await capture(language + "_free")
		for slot in range(5):
			check(bool(zone_of(draw, "want:%d" % slot).get("on", false)), "direct choice available before free reroll")
		Run.rerolled.assign([1, 1, 1, 1, 1])
		Run.gold = 100
		await capture(language + "_paid")
		Run.gold = 0
		await capture(language + "_no_gold")
		for slot in range(5):
			check(not bool(zone_of(draw, "re%d" % slot).get("on", true)), "unaffordable redraw disabled")
			check(bool(zone_of(draw, "want:%d" % slot).get("on", false)), "direct choice available without gold")
		var before := Run.cards.duplicate()
		await click("want:0")
		await capture(language + "_empty")
		check(main.screen_modal_open(), "choice is a main screen modal")
		check(not bool(zone_of(draw, "choice:watch").get("on", true)), "ad disabled until card selected")
		check(zone_of(draw, "go").is_empty() and zone_of(draw, "re0").is_empty(), "table targets cleared behind choice")
		mouse(draw, Vector2(640, 750), true)
		check(draw.state == DrawScreen.PICK and Run.cards == before, "underlying confirm does not fire")
		main.menu.open()
		check(not main.menu.opened, "choice blocks menu")
		var enabled := 0
		var disabled := 0
		for suit in range(4):
			check(zone_of(draw, "choice:suit:%d" % suit).is_empty(), "no suit tabs hide other cards")
			for rank in range(2, 15):
				var code := Poker.code(rank, suit)
				var zone := zone_of(draw, "choice:card:%d" % code)
				check(not zone.is_empty(), "every rank has a target")
				var rect: Rect2 = zone["rect"]
				check(CardChoiceView.PANEL.encloses(rect), "all 52 candidates visible inside modal")
				var on := bool(zone.get("on", false))
				check(on != before.has(code), "all current hand cards disabled")
				enabled += int(on)
				disabled += int(not on)
				if before.has(code):
					check(not tap(draw, "choice:card:%d" % code), "held card cannot be selected")
			await click("choice:card:%d" % Poker.code(14, suit))
			await capture(language + "_suit_%d" % suit)
		check(enabled == 47 and disabled == 5, "exactly 47 choices and 5 held cards")
		var chosen := Poker.code(14, 1)
		await click("choice:card:%d" % chosen)
		await capture(language + "_selected")
		var preview := draw.card_choice.preview_cards()
		check(preview[0] == chosen and preview.slice(1) == before.slice(1), "preview changes only selected slot")
		check(Poker.evaluate(preview) == Poker.Hand.PAIR, "result preview evaluates replacement hand")
		check(Run.cards == before and not Ads.busy, "selection alone does not request or reward")
		var notices := [
			"인터넷 연결을 확인한 뒤 다시 시도하세요.",
			"광고를 사용할 수 없습니다. 잠시 후 다시 시도하세요.",
			"광고 응답이 늦어지고 있습니다. 다시 시도하세요."
		]
		for index in range(notices.size()):
			Ads.message = notices[index]
			Ads._message_left = 3
			Ads._reward_notice = false
			await capture(language + "_notice_%d" % index)
			check(draw.card_choice.desired == chosen, "ad problem keeps selected card")
		Ads._message_left = 0
		Ads.message = "광고 연결을 다시 시도하고 있습니다..."
		Ads.busy = true
		await capture(language + "_connecting")
		Ads.busy = false
		await paint(draw)
		var ad := ready_ad()
		await click("choice:watch")
		check(Ads.busy and Ads._request["kind"] == "card", "UI starts card reward placement")
		check(Ads._request["data"]["slot"] == 0 and Ads._request["data"]["card"] == chosen \
			and Ads._request["data"]["expected"] == before[0], "UI submits selected card and exact slot snapshot")
		check(Run.cards == before, "showing an ad does not replace the card")
		mouse(draw, Vector2(220, 670), true)
		check(draw.card_choice.opened and draw.card_choice.desired == chosen, "busy ad blocks cancel and changes")
		ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
		check(draw.card_choice.opened and draw.card_choice.desired == chosen and not draw.card_choice.awaiting,
			"incomplete ad retains choice for retry")
		await capture(language + "_retry")
		Ads._message_left = 0
		ad = ready_ad()
		await click("choice:watch")
		ad.listener.on_user_earned_reward.call(null)
		check(Run.cards[0] == chosen and Run.gold == 0, "earned callback applies exact chosen card without gold")
		draw.card_choice.update()
		check(draw.card_choice.opened, "earned-before-dismiss keeps modal stable")
		ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
		check(not draw.card_choice.opened and draw._flip[0] > 0, "completed reward closes modal and animates changed slot")
		for slot in range(1, 5):
			check(Run.cards[slot] == before[slot] and draw._flip[slot] == 0, "unselected slot remains unchanged")
		for frame in range(6):
			draw._flip[0] = DrawScreen.FLIP_SEC * (1.0 - frame / 5.0)
			await capture(language + "_reward_%02d" % frame)
		Ads._message_left = 0
		Ads._notice.queue_redraw()
		await click("want:4")
		await click("choice:close")
		check(not draw.card_choice.opened, "cancel closes without changing hand")
		await click("want:4")
		main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
		check(not draw.card_choice.opened and not main.menu.opened, "Android back closes only card choice")
		await paint(draw)
		await click("want:4")
		var expected: int = Run.cards[4]
		Run.cards[4] = Poker.code(2, 2)
		draw.card_choice.update()
		check(not draw.card_choice.opened, "stale slot closes selection")
		Run.cards[4] = expected
		await paint(draw)
		await click("want:4")
		Run.wave += 1
		draw.card_choice.update()
		check(not draw.card_choice.opened, "new wave invalidates selection")
		Run.wave -= 1
		await paint(draw)
		await click("want:4")
		await click("choice:card:%d" % Poker.code(14, 2))
		ad = ready_ad()
		await click("choice:watch")
		main.show_title()
		await frames(3)
		check(not is_instance_valid(draw), "draw screen exits during pending ad safely")
		ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
		check(not Ads.busy and main.screen is TitleScreen, "late completion does not affect replacement screen")
		Ads._message_left = 0
		Ads._notice.queue_redraw()
		Fixture.fresh(15092026)
		Run.cards.assign([Poker.code(2, 1), Poker.code(10, 0), Poker.code(11, 0), Poker.code(12, 0), Poker.code(13, 0)])
		draw = DrawScreen.new()
		main._swap(draw)
		draw.set_process(false)
		await paint(draw)
		await click("want:0")
		await click("choice:card:%d" % Poker.code(14, 0))
		check(Poker.evaluate(draw.card_choice.preview_cards()) == Poker.Hand.ROYAL, "royal preview uses full resulting hand")
		await capture(language + "_royal_preview")
		await click("choice:close")
		Fixture.stack(Poker.Hand.ROYAL)
		await paint(draw)
		await click("want:4")
		await click("choice:card:%d" % Poker.code(9, 0))
		await capture(language + "_royal_current")
		check(I18n.missing.is_empty(), "choice UI has no missing translations: " + language)
		var audit := FileAccess.open(output + "/" + language + "_missing.json", FileAccess.WRITE)
		audit.store_string(JSON.stringify(I18n.missing, "\t"))
	main.queue_free()
	await frames(3)
	# Rapid fixture scene swaps leave BGM crossfades active. Let the audio mixer
	# release both streams before quitting, independently of UI/advert resources.
	Sfx.stop_effects()
	for player in Sfx._music_players:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	finish("Direct card choice UI")
