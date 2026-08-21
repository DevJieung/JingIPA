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
	var r := rect if not down else Rect2(rect.position + Vector2(0, 2), rect.size)
	var face: Color = col if on else col.darkened(0.62)
	var ink: Color = Look.BG_DEEP if on else Look.INK_DIM
	if not on:
		face = Look.PANEL
	Look.fill_round(ci, Rect2(r.position + Vector2(0, 4), r.size), 10.0, Color(0, 0, 0, 0.5))
	Look.fill_round(ci, r, 10.0, face)
	if on:
		Look.fill_round(ci, Rect2(r.position + Vector2(3, 3), r.size - Vector2(6, 6)),
				8.0, face.lightened(0.10))
	Look.text_center(ci, r.position + r.size * 0.5, label, size, ink)


## 그림 없이 자리만 등록한다(카드처럼 스스로 그리는 것들).
func zone(rect: Rect2, id: String, on: bool = true) -> void:
	zones.append({"rect": rect, "id": id, "on": on})


## 그 자리를 눌렀을 때 어떤 id 인가. 없으면 빈 문자열.
## ★ 나중에 등록한 것(=위에 그린 것)이 이긴다. 겹쳐 그린 대로 눌린다.
func hit(pos: Vector2) -> String:
	for i in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[i]
		if bool(z["on"]) and Rect2(z["rect"]).has_point(pos):
			return String(z["id"])
	return ""
