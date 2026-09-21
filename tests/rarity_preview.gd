extends Node2D

var main = null
var fx := Fx.new()
var shot: Dictionary = {}

func _ready() -> void:
	for u in Roster.UNITS:
		if u["id"] == "chispa":
			shot = Anim.clip(u, "shot")
	for tier in range(10):
		var origin := Vector2(28 + (tier / 5) * 624, 126 + (tier % 5) * 126)
		fx.rarity_impact(origin + Vector2(513, 50), Color("#ff8d3e"), tier)
		fx.ring(origin + Vector2(513, 50), Color("#ffe8bd"), 2.0, 17.0, 0.20, 3.0)
	fx.update(0.10)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), Look.BG_DEEP)
	Look.text_left(self, Vector2(32, 38), "희귀도별 샷 · 착탄 이펙트", 30, Look.GOLD)
	Look.text_left(self, Vector2(32, 78), "같은 기본 탄으로 등급에 따른 크기와 잔광을 비교합니다", 20, Look.INK_DIM)
	for tier in range(10):
		var origin := Vector2(28 + (tier / 5) * 624, 126 + (tier % 5) * 126)
		Look.px_panel(self, Rect2(origin, Vector2(604, 112)), Look.PANEL, Look.PANEL_EDGE)
		Look.text_left(self, origin + Vector2(14, 24), "%d등급" % (tier + 1), 19, Look.GOLD)
		Look.text_left(self, origin + Vector2(14, 73), Poker.HAND_KO[tier], 17, Look.INK)
		var p := origin + Vector2(355, 50)
		Fx.projectile_glow(self, p, p - Vector2(25, 0), Vector2.RIGHT, Color("#ff8d3e"), tier, 0.35)
		if not shot.is_empty():
			Anim.draw_frame(self, shot, 2, p.x, p.y, 0.32 * Fx.shot_scale(tier))
	fx.draw(self)
