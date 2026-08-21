extends RefCounted
class_name Art

## 그림 파일을 한 번만 읽어 두는 곳.
##
## ★ 그림이 **없어도 게임이 돌아가야 한다.** 그림은 GPU 로 한 시간쯤 걸려 만드는 것이라,
##   없다고 게임이 못 켜지면 검사기도 못 돌리고 개발이 통째로 막힌다.
##   없으면 null 을 주고, 화면 쪽이 색 도형으로 대신 그린다.

static var _cache: Dictionary = {}


static func tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		var r := ResourceLoader.load(path)
		if r is Texture2D:
			t = r
	_cache[path] = t
	return t


static func has(path: String) -> bool:
	return tex(path) != null


## 그림을 (cx, by) — 가로 가운데, 세로 **발밑** — 에 놓고 그린다.
## 발밑을 기준으로 잡아야 키가 다른 캐릭터들이 같은 바닥선에 선다.
static func draw_at(ci: CanvasItem, path: String, cx: float, by: float,
		sc: float = 1.0, mod: Color = Color.WHITE) -> bool:
	var t := tex(path)
	if t == null:
		return false
	var w: float = float(t.get_width()) * sc
	var h: float = float(t.get_height()) * sc
	ci.draw_texture_rect(t, Rect2(cx - w * 0.5, by - h, w, h), false, mod)
	return true


## 배경 그림을 그 네모에 꽉 채워 그린다. 비율이 조금 달라도 늘려서 채운다 —
## 배경은 가장자리에 검은 띠가 생기는 쪽이 훨씬 나쁘다.
static func draw_fill(ci: CanvasItem, path: String, rect: Rect2,
		mod: Color = Color.WHITE) -> bool:
	var t := tex(path)
	if t == null:
		return false
	ci.draw_texture_rect(t, rect, false, mod)
	return true


## 캐릭터/몬스터 한 마리. 그림이 아직 없으면 **색 도형**으로 대신 그린다.
## 이 대체 그림 덕에 그림을 한 장도 안 만든 상태에서도 전투를 끝까지 돌려 볼 수 있다.
static func draw_actor(ci: CanvasItem, path: String, col: Color, h: float,
		cx: float, by: float, sc: float = 1.0, mod: Color = Color.WHITE) -> void:
	if draw_at(ci, path, cx, by, sc, mod):
		return
	var hh: float = h * sc
	var w: float = hh * 0.62
	var body := Rect2(cx - w * 0.5, by - hh * 0.72, w, hh * 0.72)
	var c := Color(col.r * mod.r, col.g * mod.g, col.b * mod.b, mod.a)
	Look.fill_round(ci, body.grow(2.0), 8.0, Color(0, 0, 0, 0.75 * mod.a))
	Look.fill_round(ci, body, 7.0, c)
	ci.draw_circle(Vector2(cx, by - hh * 0.80), hh * 0.20, Color(0, 0, 0, 0.75 * mod.a))
	ci.draw_circle(Vector2(cx, by - hh * 0.80), hh * 0.17, c.lightened(0.25))
