extends RefCounted
class_name Art

## 그림 파일을 한 번만 읽어 두는 곳.
##
## ★ 그림이 **없어도 게임이 돌아가야 한다.** 그림은 GPU 로 한 시간쯤 걸려 만드는 것이라,
##   없다고 게임이 못 켜지면 검사기도 못 돌리고 개발이 통째로 막힌다.
##   없으면 null 을 주고, 화면 쪽이 색 도형으로 대신 그린다.

static var _cache: Dictionary = {}
static var _previews: Dictionary = {}


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


## 앞머리가 같은 그림을 캐시에서 통째로 잊는다.
##
## ★ 왜 필요한가: 테마 그림이 백 장(배경 1280x800 · 바닥 720x720)이고 캐시는 **한 번 읽은
##   것을 영영 들고 있다.** 한 판은 테마를 열 곳만 쓰지만, 앱을 안 끄고 판을 여러 번 하면
##   쉰 곳이 다 쌓여서 그림만 300MB 를 먹는다 — 폰에서 그대로 죽는다.
##   판이 시작될 때 한 번 잊어 주면 언제나 열 곳(약 60MB) 안쪽이다.
## ★ 캐릭터·몬스터·UI 는 **안 잊는다.** 그쪽은 63장이고 늘 쓰는 것이라, 잊으면 탄마다
##   디스크에서 다시 읽느라 전투 첫 프레임이 튄다.
static func forget(prefix: String) -> void:
	var keep: Dictionary = {}
	for k in _cache:
		if not String(k).begins_with(prefix):
			keep[k] = _cache[k]
	_cache = keep


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


## 캐릭터 한 명. **영웅을 그리는 곳은 전부 이 함수를 쓴다.**
##
## ★ 왜 따로 두는가: 그림은 등급마다 같은 높이로 저장되는데, 그 높이는 지팡이·꼬리·
##   회오리까지 포함한 테두리 상자의 높이다. 그래서 소품이 큰 캐릭터는 사람 몸이
##   그만큼 작게 나온다 — 같은 등급인데 누구는 크고 누구는 작아 보였다.
##   보정값(roster 의 sc)을 곱하는 자리를 한 곳으로 묶어야 화면 세 곳(전투·확정 연출·
##   영웅 편성)이 같은 크기로 그린다. 손으로 세 번 곱하면 반드시 한 곳을 빠뜨린다.
static func draw_unit(ci: CanvasItem, u: Dictionary, cx: float, by: float,
		sc: float = 1.0, mod: Color = Color.WHITE) -> void:
	# 같은 시트와 발 원점을 써야 편성 화면에서 전투로 넘어갈 때 몸이 이동하지 않는다.
	if Anim.draw_unit(ci, u, "idle", 0.0, cx, by, sc, mod):
		return
	draw_actor(ci, String(u.get("art", "")), Color(String(u.get("color", "#ffffff"))),
			float(u.get("h", 100)), cx, by, sc * float(u.get("sc", 1.0)), mod)


## 그 캐릭터를 그렸을 때의 실제 높이(px). 그림자·이름표 자리를 잡는 데 쓴다.
static func unit_h(u: Dictionary, sc: float = 1.0) -> float:
	return float(u.get("h", 100)) * float(u.get("sc", 1.0)) * sc


## 목록/상세창은 전용 원화의 불투명 영역을 가로·세로 모두 맞춘다.
## 작은 전투 프레임을 확대하면 얼굴과 외곽이 깨지므로 원본에서 따로 만든다.
## 전용 원화가 없는 개발 환경에서는 idle 첫 프레임과 정지 그림을 차례로 쓴다.
static func unit_preview(u: Dictionary) -> Dictionary:
	var t := tex("res://art/portraits/%s.png" % String(u.get("id", "")))
	var portrait := t != null
	var c: Dictionary = {}
	if t == null:
		c = Anim.clip(u, "idle")
		t = c["tex"] if not c.is_empty() else tex(String(u.get("art", "")))
	if t == null:
		return {}
	var key := t.resource_path
	if _previews.has(key):
		return _previews[key]
	var img := t.get_image()
	if img.is_compressed():
		img.decompress()
	if not c.is_empty():
		img = img.get_region(Rect2i(0, 0, int(c["w"]), int(c["h"])))
	var used := img.get_used_rect()
	if portrait:
		# 생성 PNG의 거의 투명한 외곽 점이 브라사만 작게 축소시키지 않도록,
		# 검수한 실루엣 경계 + 선형 필터 안전 여백 4px를 원화 표시 영역으로 쓴다.
		# 원본 픽셀/다른 원화는 보존한다. 근거: art/portraits/sources/brasa-head-repair/manifest.json.
		if String(u.get("id", "")) == "brasa" and img.get_size() == Vector2i(1029, 1528):
			used = Rect2i(109, 183, 759, 1124)
		# 원화는 작은 목록에도 축소된다. 이 텍스처만 선형 샘플링해서 얇은 선이
		# 빠지는 것을 줄이고, 전투 도트와 UI 전체의 Nearest 설정은 유지한다.
		var filtered := CanvasTexture.new()
		filtered.diffuse_texture = t
		filtered.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		t = filtered
	var out: Dictionary = {} if not used.has_area() else {"tex": t, "src": Rect2(used)}
	_previews[key] = out
	return out


static func fit_rect(source: Vector2, box: Rect2) -> Rect2:
	if source.x <= 0 or source.y <= 0 or not box.has_area():
		return Rect2(box.position, Vector2.ZERO)
	var sc := minf(box.size.x / source.x, box.size.y / source.y)
	var drawn := source * sc
	return Rect2(box.position + Vector2((box.size.x - drawn.x) * 0.5, box.size.y - drawn.y), drawn)


static func draw_unit_fit(ci: CanvasItem, u: Dictionary, box: Rect2,
		mod: Color = Color.WHITE) -> void:
	if not box.has_area():
		return
	var preview := unit_preview(u)
	if not preview.is_empty():
		var src: Rect2 = preview["src"]
		ci.draw_texture_rect_region(preview["tex"], fit_rect(src.size, box), src, mod)
		return
	# 그림이 없는 개발 환경도 같은 경계를 지킨다(외곽선 여백 포함).
	var target := fit_rect(Vector2(66, 104), box)
	draw_actor(ci, "", Color(String(u.get("color", "#ffffff"))), 100,
			target.get_center().x, target.end.y - target.size.y * 2.0 / 104.0,
			target.size.y / 104.0, mod)


## 배치 지도는 실제 전투의 굵은 실루엣을 사용한다. 원화는 목록·상세창에 유지한다.
static func draw_deployed_fit(ci: CanvasItem, u: Dictionary, box: Rect2) -> void:
	var clip := Anim.clip(u, "idle")
	if clip.is_empty():
		draw_unit_fit(ci, u, box)
		return
	var key := "deployment:" + String(u.get("id", ""))
	if not _previews.has(key):
		var img: Image = clip["tex"].get_image()
		if img.is_compressed():
			img.decompress()
		var frame := img.get_region(Rect2i(0, 0, int(clip["w"]), int(clip["h"])))
		_previews[key] = {"src": Rect2(frame.get_used_rect())}
	var src: Rect2 = _previews[key]["src"]
	ci.draw_texture_rect_region(clip["tex"], fit_rect(src.size, box), src)


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
