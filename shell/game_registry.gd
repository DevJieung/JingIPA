class_name GameRegistry
extends RefCounted

## 게임이 등록되는 유일한 곳.
##
## 새 게임을 넣을 때 손대는 것은 이 배열 한 줄과 씬 하나뿐이다.
## 셸(shell/shell.gd, shell/router.gd, shell/hub.gd)은 게임 이름을 모른다.
##
## 새 게임이 이 섬에 들어오려면 (docs/architecture.md 의 편입 규칙):
##   1. 끝이 없다 (무한 생성이든 무한 도전이든)
##   2. 탭 하나로만 조작한다. 드래그·스와이프·더블탭 금지. 실패로 나가는 출구가 없다
##   3. 타이머·평가·게임오버가 없다
##   4. 난이도를 여러 축으로 올린다 (하나만 올리면 금방 천장에 닿는다)
##   5. 첫 60초 안에 성공한다
##   6. 새 이미지 자산 0장 — 코드로 그린다. 헤드리스로 검증된다
##   7. 저장은 프로필의 자기 칸에만 쓴다
##   8. 나이대별 손잡이를 Shell.default_tuning() 에 둔다

const LIST := [
	{
		"id": "dino",
		"title": "공룡 찾기",
		"subtitle": "숨은 공룡을 콕!",
		"color": Color("6fbf5a"),
		"scene": "res://games/dino/dino.tscn",
		"viewport": {
			"size": Vector2i(1280, 720),
			"keep": true,
			"clear": Color(0.969, 0.941, 0.894),   # Look.BG
		},
		# 공룡 찾기는 배경음이 없다. 빈 문자열이면 셸이 BGM 을 끈다 —
		# 이걸 안 두면 전투 BGM 이 공룡 찾기 내내 루프로 깔린다.
		"bgm": "",
		# "아무거나!" 에서 이 게임이 뽑힐 가중치. 나이대별로 다르다.
		# 미취학은 셈보다 찾기를 훨씬 많이 — 그래야 랜덤이 벽이 되지 않는다.
		"journey": {"pre": 6, "elem": 4},
		"journey_caption": "공룡 찾기",
		# 「섬 한 바퀴」에서 이 게임 한 판이 놀이 단위 몇 개인가.
		# ★ 셀 줄 아는 것은 게임이 아니라 이 표다 — 셸이 게임 이름을 알면 안 되기 때문이다.
		#   셈놀이는 0 이다: 문제마다 이미 1씩 세고 있다(count_session_question).
		"journey_units": 3,
	},
	{
		"id": "math",
		"title": "셈놀이",
		"subtitle": "블록으로 세어 보기",
		"color": Color("f2a03d"),
		"scene": "res://games/math/ui/title.tscn",
		"viewport": {
			"size": Vector2i(1280, 800),
			"keep": false,
			"clear": Color(0.969, 0.941, 0.894),   # Look.BG
		},
		"bgm": "bgm_menu",
		"journey": {"pre": 2, "elem": 4},
		"journey_caption": "셈놀이",
		"journey_units": 0,
		# 랜덤에서는 타이틀을 거치지 않고 문제로 바로 들어간다.
		"journey_scene": "res://games/math/game/battle.tscn",
	},
	{
		"id": "torch",
		"title": "손전등 찾기",
		"subtitle": "깜깜한 방을 비춰 콕!",
		"color": Color("5b4b8a"),
		"scene": "res://games/torch/torch.tscn",
		# ★ 공룡 찾기의 방·가구를 그대로 쓰므로 뷰포트도 **글자 그대로 같아야 한다.**
		#   800 으로 두면 소품 y 좌표 42개(games/dino/scripts/rooms.gd)가 통째로 어긋난다.
		"viewport": {
			"size": Vector2i(1280, 720),
			"keep": true,
			# ★ 레터박스 여백 색. 어두운 방을 저녁빛 액자가 두른다 —
			#   기기 화면이 통째로 새까매지는 일이 없게 하는 장치다 (무서움 완화).
			"clear": Color(0.29, 0.26, 0.38),
		},
		"bgm": "",
		# 미취학에게는 여행에서 갑자기 어두워지는 일이 드물어야 한다 — 가중치를 낮게.
		"journey": {"pre": 2, "elem": 3},
		"journey_caption": "손전등 찾기",
		"journey_units": 3,
	},
	{
		"id": "cham",
		"title": "참참참",
		"subtitle": "어느 쪽으로 뛸까?",
		"color": Color("d95f7a"),
		"scene": "res://games/cham/cham.tscn",
		"viewport": {
			"size": Vector2i(1280, 800),
			"keep": false,
			"clear": Color(0.969, 0.941, 0.894),   # Look.BG
		},
		"bgm": "",
		"journey": {"pre": 3, "elem": 3},
		"journey_caption": "참참참",
		# 한 판이 10~30초라 공룡 방(40~70초)의 3분의 1쯤이다.
		# ★ 여기 숫자가 곧 세션 상한을 태우는 속도다. 3으로 두면 미취학(상한 10)이
		#   참참참만 하다가 네 판, 약 1분 만에 허브로 튕긴다.
		"journey_units": 1,
	},
	{
		"id": "kanoodle",
		"title": "블록 채우기",
		"subtitle": "모양을 맞춰 넣기",
		"color": Color("3d6ea8"),
		"scene": "res://games/kanoodle/kanoodle.tscn",
		"viewport": {
			"size": Vector2i(1280, 800),
			"keep": false,
			"clear": Color(0.969, 0.941, 0.894),   # Look.BG
		},
		"bgm": "",
		"journey": {"pre": 3, "elem": 4},
		"journey_caption": "블록 채우기",
		"journey_units": 3,
	},
]


static func get_game(id: String) -> Dictionary:
	for g in LIST:
		if String(g["id"]) == id:
			return g
	return {}


static func has(id: String) -> bool:
	return not get_game(id).is_empty()


static func ids() -> Array[String]:
	var out: Array[String] = []
	for g in LIST:
		out.append(String(g["id"]))
	return out
