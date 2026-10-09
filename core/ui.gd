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
	var edge := (Look.GOLD.lightened(0.3) if primary else col if accent else Look.PANEL_EDGE) if on else Color("#47585e")
	var face := (Look.GOLD if primary else Look.PANEL.lightened(0.12)) if on else Look.BG_DEEP.lerp(Look.PANEL, 0.45)
	if accent:
		face = face.lerp(col, 0.18)
	if down:
		face = face.darkened(0.16)
	# 단색 바탕과 얇은 테두리. 눌린 그림도 원래 터치 영역 안에 둔다.
	Look.fill_round(ci, rect, 7, Look.GOLD_DEEP if primary and on else Look.BG_DEEP)
	Look.fill_round(ci, r, 7, edge)
	Look.fill_round(ci, r.grow(-1.5), 6, face)
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
	Look.fill_round(ci, rect, 6, Look.PANEL_EDGE if selected else Look.BG_DEEP)
	Look.fill_round(ci, rect.grow(-1), 5, Look.PANEL.lightened(0.15) if selected else Look.PANEL.darkened(0.2))
	if selected:
		ci.draw_rect(Rect2(rect.position.x + 5, rect.end.y - 4, rect.size.x - 10, 3), Look.GOLD)
	Look.text_box(ci, Rect2(rect.position + Vector2(10, 3), rect.size - Vector2(20, 8)), label, size, Look.GOLD if selected else Look.INK_DIM)

func glass_button(ci: CanvasItem, rect: Rect2, label: String, id: String,
		on: bool = true, accent: Color = Look.PANEL_EDGE, size: int = 23) -> void:
	zone(rect, id, on)
	var down := on and pressed == id
	var tint := accent if on else Color("#405461")
	var face := Color("#142e3f").lerp(accent, 0.12) if on else Color("#0d1f2b")
	face.a = 0.82 if down else 0.72
	if down: face = face.lightened(0.12)
	Look.glass_panel(ci, rect, tint, face, on and accent != Look.PANEL_EDGE)
	Look.text_box(ci, Rect2(rect.position + Vector2(10, 3), rect.size - Vector2(20, 6)), label, size, Look.INK if on else Color("#8499a5"))
