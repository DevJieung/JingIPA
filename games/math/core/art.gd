## Krea 로 생성한 그림(assets/art/*.png)에 접근하는 곳.
##
## 그림이 없어도 게임은 그대로 돌아가야 한다 —
## 없으면 각 화면이 기존의 '코드로 그리는' 방식으로 알아서 돌아간다.
## (헤드리스 테스트도 그림 없이 돈다.)
##
## 그림을 다시 만들려면: python3 tools/gen_art.py
class_name Art
extends RefCounted

const DIR := "res://games/math/art/"

static var _cache: Dictionary = {}


## 없으면 null. 한 번 찾은 결과는 캐시한다.
static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var path := DIR + name + ".png"
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_cache[name] = t
	return t


static func has(name: String) -> bool:
	return tex(name) != null


## 월드별 배경 (bg_w1 ~ bg_w6). 범위를 벗어나면 가장 가까운 것으로.
static func world_bg(world_index: int) -> Texture2D:
	return tex("bg_w%d" % (clampi(world_index, 0, 5) + 1))


## 월드별 지도 (map_w1 ~ map_w6).
static func world_map(world_index: int) -> Texture2D:
	return tex("map_w%d" % (clampi(world_index, 0, 5) + 1))


## 텍스처를 rect 안에 가득 채우도록(잘라내며) 그린다 — 배경용.
##
## align_y 는 세로로 넘칠 때 **무엇을 남길지**다 (0 = 위, 0.5 = 가운데, 1 = 아래).
## 전투 배경은 아래(땅)를 남겨야 한다 — 개구리와 뱀이 서는 땅선이 그림의 땅과
## 맞아야 하기 때문이다. 가로 화면에서는 띠가 그림보다 훨씬 납작해서
## 가운데로 자르면 땅이 통째로 잘려 나간다.
static func draw_cover(ci: CanvasItem, t: Texture2D, rect: Rect2,
		modulate: Color = Color.WHITE, align_y: float = 0.5) -> void:
	if t == null:
		return
	var ts := Vector2(t.get_size())
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var scale := maxf(rect.size.x / ts.x, rect.size.y / ts.y)
	var draw_size := ts * scale
	var src := Rect2(Vector2.ZERO, ts)
	# 넘치는 만큼 잘라낸다. 가로는 늘 가운데, 세로는 align_y 가 정한다.
	var over := (draw_size - rect.size) / scale
	src.position.x += over.x * 0.5
	src.size.x -= over.x
	src.position.y += over.y * clampf(align_y, 0.0, 1.0)
	src.size.y -= over.y
	ci.draw_texture_rect_region(t, rect, src, modulate)


## 텍스처를 rect 안에 비율 유지로 '들어가게' 그린다 — 캐릭터·로고용.
static func draw_fit(ci: CanvasItem, t: Texture2D, center: Vector2, height: float,
		modulate: Color = Color.WHITE) -> void:
	if t == null or height <= 0.0:
		return
	var ts := Vector2(t.get_size())
	if ts.y <= 0.0:
		return
	var w := height * (ts.x / ts.y)
	ci.draw_texture_rect(t, Rect2(center - Vector2(w, height) * 0.5,
			Vector2(w, height)), false, modulate)
