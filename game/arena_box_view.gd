extends RefCounted
class_name ArenaBoxView

## The jewel-box modal of ArenaScreen (F10/F11, modal "box"): the box drops, climbs to its grade,
## leaks light at the seam and bursts, deals five cards that turn over best-last with per-grade
## effects, and after the pick shows the hero (new or grown). The pictures and their timing live
## in BoxCeremony (game/box_ceremony.gd); this file hands it the run's box and the screen's clocks.
## Record: build/feedback-2026-10-19/D1/RECORD.md.
##
## Draws on the screen's own canvas (`s`) from ArenaScreen._draw, in the screen's order, and
## registers its zones in `s.ui` as it goes — no node or canvas item of its own. Zones: before the
## cards settle the whole screen is `box:skip`; then `modal:block` + `box:pick:<i>` (card and its
## button) + `box:reroll`; while the pick plays `modal:block`; after it `close`.
##
## Clocks: the screen's `box_deal_age()` (0 at the box and at each successful reroll) and
## `box_pick_age()` (0 at the pick, below 0 before) when it has them; until then this view keeps
## the same two clocks on `s.t` itself. A held screen (`s._settled()`) shows everything settled.
## The screen asks `is_ready()` before acting on a pick or a reroll and calls `skip()` for
## `box:skip` (the cards then turn over at once).

const BoxCeremony := preload("res://game/box_ceremony.gd")

var s: ArenaScreen
var show = BoxCeremony.new()
var _sig := ""
var _t_last := -1.0
var _deal_t0 := 0.0
var _pick_t0 := -1.0
## Seconds `skip()` moved the deal clock forward (added to the screen's clock as well).
var _skip_add := 0.0
var _picked := false
var _restored := false

func _init(screen: ArenaScreen) -> void:
	s = screen

func _tr(key: String) -> String:
	return Arena.label("arena." + key)

## The modal, every frame it is up.
func draw_box() -> void:
	_sync()
	var age := deal_age()
	var pick := pick_age()
	var dt := 0.0
	if _t_last >= 0.0:
		dt = clampf(s.t - _t_last, 0.0, 0.1)
	_t_last = s.t
	show.free_rerolls = Arena.respins_left()
	show.can_reroll = Arena.can_respin()
	show.advance(age, pick, dt, not s._settled())
	show.draw_all(s, s.ui, age, pick)

## The old name the screen's draw match still uses for the summon modal.
func _draw_box() -> void:
	draw_box()

func _draw_rite() -> void:
	draw_box()

## The run's box as the ceremony reads it, rebuilt only when the box changes (a new box, a
## reroll): the previews are taken before the pick, so the picked card keeps saying what it
## was going to do.
func _sync() -> void:
	var sig := "%d|%d|%d" % [Arena.run_seed, Arena.box_tier, Arena.spins]
	for card in Arena.box_cards:
		sig += "|%s:%d" % [String(card["unit"]["id"]), int(card["stars"])]
	if sig != _sig:
		var cards: Array = []
		for i in range(Arena.box_cards.size()):
			var card: Dictionary = Arena.box_cards[i]
			cards.append({"unit": card["unit"], "stars": int(card["stars"]), "guaranteed": bool(card.get("guaranteed", false)),
				"preview": Arena.card_preview(i)})
		var reroll: bool = not _sig.is_empty() and not show.cards.is_empty() and _sig.get_slice("|", 0) == str(Arena.run_seed) \
				and int(_sig.get_slice("|", 2)) < Arena.spins and Arena.phase == Arena.Phase.DRAW
		_sig = sig
		_picked = false
		_skip_add = 0.0
		# The fairness rules' badges (once a box — they walk the stage's waves): 「대공 보장」 when a flying
		# body ahead is one nobody in the party can hurt and a dealt card can (the rule on: ARENA_BOX_AIR_CARDS),
		# 「면역 대응 보장」 when the same holds for a walking body every hero is immune to (its body glyph shown).
		show.anti_air = false
		show.immune_body = ""
		var uncovered: Array = Arena.uncovered_bodies() if Arena.has_method("uncovered_bodies") else []
		for need in uncovered:
			var flying := bool(need["fly"])
			var body := String(need["body"])
			var served := false
			for card in cards:
				if Arena.hurts(card["unit"], body, flying):
					served = true
			if not served:
				continue
			if flying and Balance.ARENA_BOX_AIR_CARDS > 0:
				show.anti_air = true
			elif not flying and show.immune_body.is_empty():
				show.immune_body = body
		if reroll:
			show.begin_reroll(Arena.box_tier, cards)
		else:
			BoxCeremony.release_art()
			show.free_box = Arena.summon_count == 0
			show.begin(Arena.box_tier, cards, Arena.summon_count > 0)
			# A box the screen opens onto after the pick (a restored run) shows its result settled.
			_restored = Arena.phase == Arena.Phase.SWAP
		_deal_t0 = s.t
		_pick_t0 = -1.0
	if Arena.phase == Arena.Phase.SWAP and not _picked and not Arena.summon_result.is_empty():
		_picked = true
		show.begin_pick(int(Arena.summon_result.get("card", 0)), Arena.summon_result)
		_pick_t0 = s.t

## Seconds into this deal (the box's arrival, or the last reroll).
func deal_age() -> float:
	if s._settled() or _restored:
		return show.settle_time() + 10.0
	var age := s.t - _deal_t0
	if s.has_method("box_deal_age"):
		age = float(s.call("box_deal_age"))
	return age + _skip_add

## Seconds since the pick (below 0 before it).
func pick_age() -> float:
	if not _picked:
		return -1.0
	if s._settled() or _restored:
		return BoxCeremony.RESULT_READY + 10.0
	if s.has_method("box_pick_age"):
		var screen_age := float(s.call("box_pick_age"))
		if screen_age >= 0.0:
			return screen_age
	return s.t - _pick_t0

## Picks and the reroll listen only once the cards have settled; the result's button once the
## result is in.
func is_ready() -> bool:
	return show.is_ready(deal_age(), pick_age())

## `box:skip`: the cards that have not turned over do so at once (a 4-star or better still gets
## its burst), and the buttons come up.
func skip() -> void:
	var age := deal_age()
	_skip_add += show.skip_target(age) - age

## When input opens on this deal (seconds of the deal clock) — for a screen that wants a number.
func settle_time() -> float:
	return show.settle_time()

## The box closed: let its pictures go.
func release() -> void:
	BoxCeremony.release_art()
	_sig = ""
	_picked = false
	_restored = false
