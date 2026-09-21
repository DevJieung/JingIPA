extends RefCounted
class_name Anim

## 영웅 Idle · Attack · Shot 및 몬스터 Move 클립을 읽어 두는 곳.
##
## 클립은 `tools/anim/mkanim.py` 가 만든다 (절차는 docs/ART.md). 한 클립이 **가로로 이어
## 붙인 스트립 한 장**이고, 칸 크기·기준점·칸마다의 시간은 옆의 `<id>_anim.json` 에 있다.
##
## ★ **그림이 없어도 게임이 돌아가야 한다.** 서른 명의 클립을 다 뽑는 데 GPU 로 몇 시간이
##   걸린다. 없다고 게임이 못 켜지면 검사기도 못 돌리고 개발이 통째로 막힌다.
##   `clip()` 이 빈 딕셔너리를 주면 화면은 지금처럼 **정지 그림 한 장**으로 그린다.
##
## ★ 기준점은 정지 그림과 **같은 규칙**이다 — 가로 가운데 · 세로 발밑(Art.draw_at).
##   칸은 정지 그림보다 큰데(치켜든 팔·이펙트가 밖으로 나간다) 기준점이 같으므로
##   발이 같은 바닥선에 선다. 여기가 어긋나면 전투 화면에서 영웅이 위아래로 튄다.

const CLIPS := ["idle", "attack", "shot", "effect"]

static var _cache: Dictionary = {}


## 그 캐릭터의 그 클립. 없으면 빈 딕셔너리.
##   {"tex": Texture2D, "n": 칸수, "w","h": 칸 크기, "ax","ay": 기준점,
##    "ms": [칸마다 ms], "total": 한 바퀴 ms, "loop": bool, "hit": 때리는 칸}
##
## ★ `mkanim.py` 가 내는 JSON 을 **그대로** 읽는다. 중간에 변환 단계를 두면 두 형식이
##   생기고, 둘 중 하나만 고치는 날 조용히 어긋난다.
## ★ 칸 크기를 JSON 의 `cell` 이 아니라 **그림 폭 ÷ 칸수**로 잰다. `shot` 클립은 배우
##   칸이 아니라 날아가는 탄만 담은 작은 스트립이라 `cell` 과 크기가 다르다 —
##   `cell` 을 믿으면 탄이 통째로 어긋나 잘린다.
static func clip(u: Dictionary, name: String) -> Dictionary:
	var dir := String(u.get("anim", ""))
	if dir == "":
		return {}
	var key := dir + name
	if _cache.has(key):
		return _cache[key]
	var out: Dictionary = {}
	var meta := _meta(dir)
	var clips: Dictionary = meta.get("clips", {})
	if not clips.has(name):
		_cache[key] = out
		return out
	var tex := Art.tex("%s%s_%s.png" % [dir, String(meta.get("name", "")), name])
	if tex != null and clips.has(name):
		var c: Dictionary = clips[name]
		var ms: Array = c.get("ms", [])
		var n: int = maxi(1, int(c.get("frames", ms.size())))
		var total := 0.0
		for v in ms:
			total += float(v)
		if total > 0.0:
			var cw: float = float(tex.get_width()) / float(n)
			var ch: float = float(tex.get_height())
			# 기준점 — 가로 가운데 · 세로 발밑. 배우 칸에만 뜻이 있다.
			# ★ 「탄」 클립에는 발밑이 없다. 가운데를 기준으로 둔다.
			var ax := 0.5
			var ay := 1.0
			var anc: Dictionary = meta.get("anchor", {})
			var cell: Dictionary = meta.get("cell", {})
			if name not in ["shot", "effect"] and not anc.is_empty() and not cell.is_empty():
				ax = float(anc.get("x", cw * 0.5)) / maxf(1.0, float(cell.get("w", cw)))
				ay = float(anc.get("y", ch)) / maxf(1.0, float(cell.get("h", ch)))
			elif name in ["shot", "effect"]:
				ay = 0.5
			out = {
				"tex": tex, "n": n, "w": cw, "h": ch, "ax": ax, "ay": ay,
				"ms": ms, "total": total,
				"loop": bool(c.get("loop", name != "attack")),
				"hit": int(c.get("hit_frame", 0)),
				# ★★ **칸 크기와 그려지는 키는 다른 것이다.**
				#   공식 파이프라인(tools/sprite)의 시트는 등급과 상관없이 언제나
				#   96x96 인데, 게임의 그림 높이는 등급마다 다르다(96~141px).
				#   1:1 로 그리면 로열이 하이카드와 같은 키로 선다.
				#   `scale` 은 `to_game.py` 가 **정지 그림과 같은 자로** 재 둔 값이다
				#   — 아이들 0번 칸의 몸 높이가 `unit_h(등급)` 이 되게 하는 배수.
				#   그래서 편성 판(정지 그림)과 전투 화면(클립)의 키가 같다.
				#   ☆ 없으면 1.0 이다. 옛 길(tools/anim)의 클립은 칸이 이미 등급
				#     높이에 맞춰 잘려 있어서 배율이 필요 없었다.
				"scale": float(c.get("scale", meta.get("scale", 1.0))),
				"fixed_feet": bool(meta.get("fixed_feet", false)),
			}
	_cache[key] = out
	return out


## `<dir>anim.json` 을 한 번만 읽는다.
##
## ★ `mkanim.py` 는 `<id>_anim.json` 으로 내놓는다. 그것을 그대로
##   `art/anim/<id>/anim.json` 에 옮겨 둔다 — **형식을 바꾸지 마라.** 중간에 변환 단계를
##   두면 두 형식이 생기고, 둘 중 하나만 고치는 날 조용히 어긋난다.
## ★ `ResourceLoader.exists` 로는 안 된다. JSON 은 임포트되는 리소스가 아니라 **날 파일**이라
##   내보낸 APK 안에서도 FileAccess 로 읽어야 한다.
static func _meta(dir: String) -> Dictionary:
	var key := dir + "@meta"
	if _cache.has(key):
		return _cache[key]
	var out: Dictionary = {}
	var path := dir + "anim.json"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				out = parsed
	_cache[key] = out
	return out


## 그 클립 한 바퀴가 걸리는 시간(초). 없으면 0.
##
## ★ 화면이 공격 모션을 **얼마나 오래 보여 줄지**를 여기서 받는다. 예전에는 0.26초로
##   못 박혀 있었는데 공격 클립은 0.405초짜리라, **놓는 칸에 닿기도 전에** 아이들로
##   돌아갔다 — 팔을 끝까지 뻗는 장면을 아무도 못 봤다.
static func length(u: Dictionary, name: String = "attack") -> float:
	var c := clip(u, name)
	return 0.0 if c.is_empty() else float(c["total"]) / 1000.0


## 클립이 시작한 뒤 **놓는 칸**에 닿기까지 걸리는 시간(초).
##
## ★ 놓는 칸(hit_frame)은 **제일 짧은 칸**이다 — 눈은 제일 짧은 프레임을 타격으로 읽는다
##   (docs/ART.md 6). 전투는 이 시간만큼 기다렸다가 탄을 내보내므로, 화면에서 팔이
##   가장 앞으로 나간 그 칸과 탄이 떠나는 순간이 같아진다.
static func hit_time(u: Dictionary, name: String = "attack") -> float:
	var c := clip(u, name)
	if c.is_empty():
		return 0.0
	var arr: Array = c["ms"]
	var acc := 0.0
	for i in range(mini(int(c["hit"]), arr.size())):
		acc += float(arr[i])
	return acc / 1000.0


## 지금 몇 번째 칸인가. `t` 는 클립이 시작한 뒤 흐른 시간(초).
##
## ★ 칸마다 시간이 다르다. 균등하게 나누면 **언제 쐈는지가 안 읽힌다** — 가장 짧은 칸
##   (20ms)이 놓는 순간이고, 눈은 제일 짧은 프레임을 타격으로 읽는다 (docs/ART.md 6).
static func frame_at(c: Dictionary, t: float) -> int:
	if c.is_empty():
		return 0
	var ms: float = t * 1000.0
	if bool(c["loop"]):
		ms = fposmod(ms, float(c["total"]))
	elif ms >= float(c["total"]):
		return int(c["n"]) - 1
	var acc := 0.0
	var arr: Array = c["ms"]
	for i in range(arr.size()):
		acc += float(arr[i])
		if ms < acc:
			return i
	return arr.size() - 1


## 한 칸을 그린다. 기준점은 (cx, by) — 가로 가운데 · 세로 발밑.
##
## ★ 좌우 뒤집기·눌림은 **여기서 받지 않는다.** 부르는 쪽이 draw_set_transform 아래에서
##   그린다 (CLAUDE.md 10-3). 여기에 인자를 더하면 화면 세 곳이 저마다 다른 방법으로
##   뒤집게 되고 언젠가 한 곳이 빠진다.
static func draw_frame(ci: CanvasItem, c: Dictionary, i: int, cx: float, by: float,
		sc: float = 1.0, mod: Color = Color.WHITE) -> void:
	if c.is_empty():
		return
	var w: float = float(c["w"])
	var h: float = float(c["h"])
	# ★ 시트가 제 등급 키로 커지는 배수. 부르는 쪽이 아니라 **여기서** 곱한다 —
	#   부르는 쪽에 맡기면 화면 세 곳 중 한 곳이 언젠가 빠뜨린다 (10-3 과 같은 규칙).
	var ks: float = sc * float(c.get("scale", 1.0))
	var src := Rect2(float(i) * w, 0.0, w, h)
	var dst := Rect2(cx - w * float(c["ax"]) * ks, by - h * float(c["ay"]) * ks, w * ks, h * ks)
	ci.draw_texture_rect_region(c["tex"], dst, src, mod)


## 그 캐릭터를 클립으로 그린다. **클립이 없으면 false 를 준다** — 그때 부르는 쪽이
## 정지 그림(Art.draw_unit)으로 그린다.
##
## ★ `sc` 는 정지 그림과 **같은 보정**(roster 의 sc)을 이미 곱한 값이어야 한다.
##   안 그러면 애니메이션이 도는 캐릭터만 크기가 달라진다.
static func draw_unit(ci: CanvasItem, u: Dictionary, name: String, t: float,
		cx: float, by: float, sc: float = 1.0, mod: Color = Color.WHITE) -> bool:
	var c := clip(u, name)
	if c.is_empty():
		return false
	draw_frame(ci, c, frame_at(c, t), cx, by, sc * float(u.get("sc", 1.0)), mod)
	return true
