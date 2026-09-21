extends RefCounted
class_name Ui

## 손으로 그리는 화면용 아주 작은 버튼 도우미.
##
## 화면을 전부 _draw() 로 그리다 보니 Control 노드를 안 쓴다. 그러면 "어디를 눌렀나"를
## 매번 손으로 재게 되는데, 그 계산이 그리기 코드와 떨어져 있으면 반드시 어긋난다
## (버튼은 옮겼는데 눌리는 자리는 그대로인 버그). 그래서 **그리면서 동시에 등록**한다.

var zones: Array = []      ## [{rect, id, on}]
var pressed: String = ""   ## 지금 눌려 있는 버튼 id (눌린 느낌을 내려고)


func begin() -> void:
	zones.clear()


## 버튼 하나를 그리고 누를 자리로 등록한다.
func button(ci: CanvasItem, rect: Rect2, label: String, id: String,
		on: bool = true, col: Color = Look.GOLD, size: int = 26) -> void:
	zones.append({"rect": rect, "id": id, "on": on})
	var down: bool = pressed == id and on
	var r := Rect2(rect.position + Vector2(0, 2 if down else 0), rect.size - Vector2(0, 3))
	var primary := col == Look.GOLD
	var accent := on and col != Look.PANEL_EDGE and not primary
	var edge := (Look.GOLD.lightened(0.3) if primary else col if accent else Color("#83999f")) if on else Color("#47585e")
	var face := (Color("#f6c445") if primary else Color("#31464e")) if on else Color("#1c2a30")
	if accent:
		face = face.lerp(col, 0.18)
	if down:
		face = face.darkened(0.16)
	# 단색 바탕과 얇은 테두리. 눌린 그림도 원래 터치 영역 안에 둔다.
	Look.fill_round(ci, rect, 4, Look.GOLD_DEEP if primary and on else Look.BG_DEEP)
	Look.fill_round(ci, r, 4, edge)
	Look.fill_round(ci, r.grow(-2), 3, face)
	if on and not down:
		ci.draw_line(r.position + Vector2(6, 3), Vector2(r.end.x - 6, r.position.y + 3), face.lightened(0.22), 1)
	Look.text_box(ci, Rect2(r.position + Vector2(12, 2), r.size - Vector2(24, 4)), label, size,
		(Look.BG_DEEP if primary else Look.INK) if on else Color("#8b9aa5"))


## 그림 없이 자리만 등록한다(카드처럼 스스로 그리는 것들).
func zone(rect: Rect2, id: String, on: bool = true) -> void:
	zones.append({"rect": rect, "id": id, "on": on})


## 그 자리를 눌렀을 때 어떤 id 인가. 없으면 빈 문자열.
## ★ 나중에 등록한 것(=위에 그린 것)이 이긴다. 겹쳐 그린 대로 눌린다.
func hit(pos: Vector2) -> String:
	for i in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[i]
		if Rect2(z["rect"]).has_point(pos):
			return String(z["id"]) if bool(z["on"]) else ""
	return ""


func tab(ci: CanvasItem, rect: Rect2, label: String, id: String, selected: bool, size: int = 23) -> void:
	zones.append({"rect": rect, "id": id, "on": true})
	Look.fill_round(ci, rect, 4, Look.PANEL_EDGE if selected else Look.BG_DEEP)
	Look.fill_round(ci, rect.grow(-1), 3, Color("#34464b") if selected else Color("#17272c"))
	if selected:
		ci.draw_rect(Rect2(rect.position.x + 5, rect.end.y - 4, rect.size.x - 10, 3), Look.GOLD)
	Look.text_box(ci, Rect2(rect.position + Vector2(10, 3), rect.size - Vector2(20, 8)), label, size, Look.GOLD if selected else Look.INK_DIM)


## Rewarded actions share a compact film/play icon and a reward-only label.
func reward_button(ci: CanvasItem, rect: Rect2, label: String, id: String,
		on: bool = true, col: Color = Look.CRYSTAL, size: int = 23) -> void:
	button(ci, rect, "", id, on, col, size)
	var sz := Look.fit_size(label, size, rect.size - Vector2(64, 8))
	var text_w := Look.text_width(label, sz)
	var left := rect.get_center().x - (text_w + 38) * 0.5
	var ink := (Look.BG_DEEP if col == Look.GOLD else Look.INK) if on else Color("#8b9aa5")
	Look.draw_reward_icon(ci, Vector2(left + 13, rect.get_center().y - 1), 13, ink)
	Look.text_box(ci, Rect2(left + 38, rect.position.y + 3, text_w + 1, rect.size.y - 8), label, sz, ink, HORIZONTAL_ALIGNMENT_LEFT)
