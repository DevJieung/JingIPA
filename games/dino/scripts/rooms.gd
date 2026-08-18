class_name Rooms
extends RefCounted

## 방 6개의 설계도.
##  back  : 공룡보다 뒤에 그려지는 벽 장식
##  front : 공룡을 가려주는 가구 (공룡보다 앞에 그려짐)
##  spots : 숨을 자리. {"p": front 가구 번호, "side": -1 왼쪽 / 1 오른쪽 / 0 뒤에서 빼꼼}

const SCREEN := Vector2(1280, 720)
const FLOOR_Y := 470.0


static func _p(kind: String, x: float, y: float, w: float, h: float, c: String, c2 := "ffffff") -> Dictionary:
	return {"kind": kind, "x": x, "y": y, "w": w, "h": h, "col": Color(c), "col2": Color(c2)}


static func _s(p: int, side: int) -> Dictionary:
	return {"p": p, "side": side}


static func all() -> Array:
	return [
		{
			"name": "거실",
			"wall": Color("fbe9cf"), "wall2": Color("f1dab2"), "wall_pat": "stripes",
			"floor": Color("c98a55"), "floor2": Color("b87b48"), "floor_pat": "wood",
			"trim": Color("fff6e8"), "dim": 0.0,
			"count": 2,
			"back": [
				_p("window", 250, 330, 250, 200, "fff6e8"),
				_p("picture", 700, 300, 150, 110, "b0764a", "fff8ec"),
				_p("rug", 640, 700, 620, 140, "e8b4b8", "fbe0e2"),
			],
			"front": [
				_p("sofa", 430, 610, 420, 215, "7fb5d9", "fdf3e3"),
				_p("table", 870, 670, 220, 110, "c98a55", "ff8fa3"),
				_p("tv", 1160, 560, 240, 230, "d9c3a5", "8fd6ff"),
				_p("plant", 88, 690, 136, 270, "6bbf6b", "e07a5f"),
			],
			"spots": [_s(0, -1), _s(0, 1), _s(1, 0), _s(2, -1)],
		},
		{
			"name": "부엌",
			"wall": Color("dff3e8"), "wall2": Color("cbe9da"), "wall_pat": "tiles",
			"floor": Color("efe6d2"), "floor2": Color("dbcdb2"), "floor_pat": "checker",
			"trim": Color("ffffff"), "dim": 0.0,
			"count": 2,
			"back": [
				_p("window", 430, 320, 240, 190, "ffffff"),
				_p("shelf", 800, 320, 300, 90, "c98a55"),
				_p("picture", 1090, 290, 120, 120, "8fb9a4", "fff8ec"),
			],
			"front": [
				_p("fridge", 140, 640, 200, 340, "bcd9e8", "f4f8fa"),
				_p("counter", 640, 650, 420, 200, "d8a86b", "f4ead6"),
				_p("table", 1060, 660, 220, 120, "c98a55", "ffd166"),
				_p("bin", 1210, 690, 100, 150, "8fd6ff", "ffffff"),
			],
			"spots": [_s(0, 1), _s(1, -1), _s(1, 1), _s(2, 0)],
		},
		{
			"name": "침실",
			"wall": Color("e9e2fb"), "wall2": Color("dbd0f4"), "wall_pat": "dots",
			"floor": Color("d2a46c"), "floor2": Color("c2934f"), "floor_pat": "wood",
			"trim": Color("fdf8ff"), "dim": 0.0,
			"count": 3,
			"back": [
				_p("window", 700, 370, 200, 190, "fdf8ff"),
				_p("curtain", 700, 470, 420, 320, "c9a8e8"),
				_p("picture", 330, 290, 160, 120, "b0764a", "fff8ec"),
				_p("rug", 620, 712, 520, 130, "cfe8d2", "eaf7ec"),
			],
			"front": [
				_p("bed", 520, 650, 420, 210, "9ec6f0", "fdf6e8"),
				_p("nightstand", 900, 640, 140, 170, "c98a55", "ffd166"),
				_p("wardrobe", 1140, 640, 240, 350, "c9976a", "ffffff"),
				_p("toybox", 120, 710, 170, 130, "ff9fb0", "ffffff"),
			],
			"spots": [_s(0, -1), _s(0, 1), _s(2, -1), _s(3, 0)],
		},
		{
			"name": "욕실",
			"wall": Color("d8eef8"), "wall2": Color("c2e2f2"), "wall_pat": "tiles",
			"floor": Color("eef6fa"), "floor2": Color("d5e9f2"), "floor_pat": "checker",
			"trim": Color("ffffff"), "dim": 0.0,
			"count": 3,
			"back": [
				_p("window", 1010, 310, 200, 180, "ffffff"),
				_p("picture", 480, 300, 180, 150, "cfd8e0", "eaf6ff"),
			],
			"front": [
				_p("bathtub", 330, 620, 440, 190, "8fd6ff", "ffffff"),
				_p("sink", 730, 600, 200, 170, "8fd6ff", "f4fafd"),
				_p("toilet", 990, 640, 180, 220, "8fd6ff", "fbfeff"),
				_p("basket", 1190, 690, 160, 120, "e3c48f", "ffffff"),
			],
			"spots": [_s(0, -1), _s(0, 1), _s(1, 1), _s(3, 0)],
		},
		{
			"name": "놀이방",
			"wall": Color("ffe7ec"), "wall2": Color("ffd6df"), "wall_pat": "stripes",
			"floor": Color("e6c08a"), "floor2": Color("d5ac72"), "floor_pat": "wood",
			"trim": Color("fff6f8"), "dim": 0.0,
			"count": 4,
			"back": [
				_p("shelf", 1000, 330, 320, 100, "c98a55"),
				_p("picture", 360, 290, 170, 130, "ffb3c1", "fff8ec"),
				_p("rug", 640, 715, 560, 120, "bfe3ff", "e9f6ff"),
			],
			"front": [
				_p("toybox", 220, 670, 260, 170, "ffb3c1", "ffffff"),
				_p("blocks", 500, 690, 140, 230, "ffd166", "ffffff"),
				_p("horse", 920, 670, 260, 200, "c98a55", "fff0c2"),
				_p("balls", 1150, 700, 190, 120, "ff8fa3", "ffffff"),
			],
			"spots": [_s(0, -1), _s(0, 1), _s(1, 1), _s(2, -1), _s(3, 0)],
		},
		{
			"name": "다락방",
			"wall": Color("e6d9c8"), "wall2": Color("d9c9b3"), "wall_pat": "planks",
			"floor": Color("a97b4f"), "floor2": Color("966a41"), "floor_pat": "wood",
			"trim": Color("f3e7d6"), "dim": 0.18,
			"count": 4,
			"back": [
				_p("cobweb", 120, 200, 180, 180, "ffffff"),
				_p("window", 1040, 300, 200, 190, "d9c9b3"),
				_p("picture", 560, 270, 150, 120, "8a6a4a", "fff8ec"),
			],
			"front": [
				_p("boxes", 230, 650, 250, 270, "d6a86e", "f2e2c6"),
				_p("trunk", 620, 680, 280, 130, "a3703f", "d9b26a"),
				_p("chair", 910, 660, 210, 230, "b98d5e", "ffffff"),
				_p("boxes", 1180, 690, 200, 180, "c99a63", "f2e2c6"),
			],
			"spots": [_s(0, -1), _s(0, 1), _s(1, 0), _s(2, -1), _s(3, -1)],
		},
	]


## 파고듦(tuck)의 범위. 0.0 이 예전 동작이고, 클수록 가구 안으로 더 들어가 잘 안 보인다.
## ★ 이 파라미터가 난이도 설계 전체의 열쇠다. 예전에는 자리가 "가구당 좌/우/뒤"로
##   이산이라 가림%가 뽑고 보니 나온 값이었고, 그래서 탄이 올라가도 53~56%에서
##   평평했다. u 를 넣어 연속으로 만들면 가림%가 진짜 손잡이가 된다.
const U_MIN := -0.55
const U_MAX := 1.0

## 가림%의 절대 한계. 이 밖으로는 어떤 튜닝으로도 못 나간다.
## 26% 미만이면 "숨은 적이 없는" 그림이고, 86% 초과면 아이가 못 찾는다.
const COV_HARD_LO := 26
const COV_HARD_HI := 86


## 유효탄 e 에서 노리는 가림% 밴드. 생성기와 검사기가 **같은 함수**를 본다 —
## 그래야 곡선을 바꿔도 --dump 검사가 구조적으로 어긋날 수 없다.
## ceil 은 그 프로필이 끝까지 올라갈 수 있는 천장이다 — 미취학은 여기서 멈춘다.
## (5세에게 80% 가림은 "숨은 그림"이 아니라 "안 보이는 그림"이다.)
static func band(e: int, lo0: int = 30, hi0: int = 58, ceil_hi: int = 80) -> Vector2i:
	var over := float(maxi(0, e - 6))
	var lo := mini(ceil_hi - 26, lo0 + int(round(0.8 * over)))
	var hi := mini(ceil_hi, hi0 + int(round(1.0 * over)))
	return Vector2i(maxi(COV_HARD_LO, lo), mini(COV_HARD_HI, maxi(lo + 8, hi)))


## 숨을 자리 -> 공룡 발 위치와 바라보는 방향
## spot 에 "u" 가 없으면 0.0 — 손으로 꾸민 1~6탄은 픽셀 단위로 예전과 같다.
static func spot_transform(front: Array, spot: Dictionary) -> Dictionary:
	var p: Dictionary = front[int(spot["p"])]
	var side := int(spot["side"])
	var u := clampf(float(spot.get("u", 0.0)), U_MIN, U_MAX)
	var px: float = p["x"]
	var py: float = p["y"]
	var pw: float = p["w"]
	var ph: float = p["h"]
	var pos: Vector2
	var face := 1.0
	if side == 0:
		# 뒤에 서는 자리: u 가 크면 가구 위쪽으로 더 붙어 몸이 많이 가려진다.
		pos = Vector2(px, py - ph * (0.45 + 0.25 * u))
		face = 1.0 if px < SCREEN.x * 0.5 else -1.0
	else:
		# 옆에 서는 자리: u 가 크면 가구 안쪽으로 파고든다.
		pos = Vector2(px + side * (pw * 0.5 + 22.0) * (1.0 - 0.9 * u), py - ph * 0.18)
		face = float(side)
	pos.x = clampf(pos.x, 130.0, SCREEN.x - 130.0)
	pos.y = clampf(pos.y, 360.0, SCREEN.y - 24.0)
	return {"pos": pos, "face": face}


## 공룡이 차지하는 대략적인 네모 (숨은 정도 계산용).
## 실제 그림은 종마다 다르지만 평균이 이 정도다.
static func dino_box(pos: Vector2) -> Rect2:
	return Rect2(pos + Vector2(-100, -150), Vector2(200, 150))


static func prop_rect(p: Dictionary) -> Rect2:
	var w: float = p["w"]
	var h: float = p["h"]
	return Rect2(float(p["x"]) - w * 0.5, float(p["y"]) - h, w, h)


## 이 자리에 선 공룡이 가구에 몇 % 가려지는지 (0~100). 화면 밖으로 나가면 -1.
static func coverage(pos: Vector2, front: Array) -> int:
	var box := dino_box(pos)
	var hidden := 0
	var n := 0
	var boxes: Array[Rect2] = []
	for p in front:
		boxes.append(prop_rect(p))
	for gy in 16:
		for gx in 16:
			var q := box.position + Vector2(box.size.x * (gx + 0.5) / 16.0, box.size.y * (gy + 0.5) / 16.0)
			n += 1
			if q.x < 4.0 or q.x > SCREEN.x - 4.0 or q.y < 118.0:
				return -1
			for b in boxes:
				if b.has_point(q):
					hidden += 1
					break
	return int(round(100.0 * float(hidden) / float(n)))
