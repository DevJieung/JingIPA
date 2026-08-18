class_name TorchGen
extends RefCounted

## 손전등 찾기의 난이도 손잡이. **단일 진실 소스**다.
##
## ★ 방을 만드는 코드는 새로 쓰지 않는다. 공룡 찾기의 RoomGen 에 **손잡이만 바꿔 낀다** —
##   가구 배치·자리 고르기·가림% 이분탐색은 이미 실측으로 다듬어진 코드고, 두 벌이 되는
##   순간 한쪽만 고쳐지는 날이 온다. (games/dino/scripts/room_gen.gd)
##
## ★ 이 게임에서 공룡을 숨기는 것은 **가구가 아니라 어둠**이다. 그래서 가림%도 마릿수도
##   가구 수도 공룡 찾기보다 낮게 준다. 셋을 같이 올리면 각각은 온건해 보이는데
##   합쳐서 "안 보이는 방"이 된다 — 어둠·가림·좁은 빛은 서로 **곱해지기** 때문이다.
##   그 곱을 hardness() 로 재서 tests/torch_check.gd 가 상한을 강제한다.
##
## 올리는 축은 전부 "볼 것이 늘거나(A) · 잘 안 보이거나(B)" 다.
## 기다림(E)은 내려가기만 하고, 평가(F)·시간 압박(G)은 아예 없다.
##
## 축이 들어오는 순서 (규칙 10: 새 축은 한 번에 하나씩, 간격 최소 3방):
##   e=3   어둠이 짙어지기 시작
##   e=7   가구 3 -> 4
##   e=10  공룡 2 -> 3
##   e=14  가구 4 -> 5
##   e=17  손전등이 좁아지기 시작   ← **가장 늦게 들어온다**
##   e=20  공룡 3 -> 4
##
## ★ 손전등 반경이 왜 마지막이고 왜 하한이 높은가:
##   반경을 줄이는 것은 "잘 안 보이게" 하는 축처럼 보이지만, 실제로는
##   **방 하나를 훑는 데 필요한 탭 수**를 1/r^2 로 올린다 (r=260 이면 7~9번,
##   r=160 이면 18~23번, r=100 이면 47~59번). 그건 난이도가 아니라 노동이고,
##   화면에 안 보이는 시간 압박(G축)으로 되돌아온다. 그래서 하한을 박아 둔다.
const BEAM_FLOOR := 200.0

## 공룡 그림은 최대 250x184px 이라 대각 반지름이 약 116px 이다.
## 반경이 이보다 작으면 큰 공룡이 빛 안에 통째로 안 들어와서 "다리만 보이는" 방이 된다.
const BEAM_ABS_MIN := 150.0

## 어둠이 이보다 짙으면 가구 실루엣이 사라진다 — 그 순간 "깜깜한 방"이 아니라
## "아무것도 없는 화면"이 되고, 그건 이 나이대에게 그냥 무섭다.
const DARK_CEIL := 0.91

## 어둠 x 가림 x 좁은 빛을 곱한 값의 상한. 검사기가 이 줄 하나만 본다.
const HARD_CEIL := 1.85


## 공룡 찾기의 RoomGen 에 넘길 손잡이. torch_* 값을 dino_* 자리에 끼워 넣는다.
##
## ★ torch_cov_lo 는 사실상 죽은 손잡이다 — Rooms.band() 안의 `mini(ceil_hi - 26, ...)`
##   때문에 ceil 이 52 미만이면 lo 가 항상 COV_HARD_LO(26)로 눌린다. 그래도 26 이라고
##   적어 둔다: 값이 뜻을 말하게 하고, 나중에 ceil 을 올릴 때 같이 살아나게.
static func room_tuning(t: Dictionary) -> Dictionary:
	var r: Dictionary = t.duplicate()
	r["dino_min"] = int(t.get("torch_min", 2))
	r["dino_max"] = int(t.get("torch_max", 4))
	r["dino_step"] = float(t.get("torch_step", 10.0))
	r["dino_cov_lo"] = int(t.get("torch_cov_lo", 26))
	r["dino_cov_hi"] = int(t.get("torch_cov_hi", 28))
	r["dino_cov_ceil"] = int(t.get("torch_cov_ceil", 40))
	r["dino_props_max"] = int(t.get("torch_props_max", 5))
	r["dino_hint_sec"] = float(t.get("torch_hint_sec", 13.0))
	return r


## 유효탄 e 에서의 모든 손잡이.
static func axes(e: int, t: Dictionary = {}) -> Dictionary:
	var base := RoomGen.axes(e, room_tuning(t))
	# ★ 손잡이를 먼저 한계 안으로 접어 넣는다. clampf 는 min > max 로 부르면 조용히
	#   이상한 값을 돌려주므로, 부모가 tuning 을 엉뚱하게 고쳐도 하한/상한을 못 넘게 한다.
	var b0 := maxf(BEAM_ABS_MIN, float(t.get("torch_beam", 300.0)))
	var bmin := clampf(float(t.get("torch_beam_min", BEAM_FLOOR)), BEAM_ABS_MIN, b0)
	var d0 := clampf(float(t.get("torch_dark", 0.84)), 0.0, DARK_CEIL)
	var dmax := clampf(float(t.get("torch_dark_max", 0.90)), d0, DARK_CEIL)
	return {
		# A. 볼 것이 는다
		"dinos": int(base["dinos"]),
		"props": int(base["props"]),
		# B. 잘 안 보인다
		"beam": clampf(b0 - 3.0 * float(maxi(0, e - 17)), bmin, b0),
		"dark": clampf(d0 + 0.0022 * float(maxi(0, e - 2)), d0, dmax),
		"band": base["band"],
		# E. 기다림 — 내려가기만 한다
		"hint_sec": float(base["hint_sec"]),
	}


## 어둠 x 가림 x 좁은 빛. 셋이 곱해지는 것을 한 숫자로 본다.
## 1.0 이 "1탄쯤"이고 HARD_CEIL 을 넘으면 아이가 방을 통째로 훑어도 못 찾는 방이다.
static func hardness(ax: Dictionary) -> float:
	var band: Vector2i = ax["band"]
	return float(ax["dark"]) / 0.84 \
			* (1.0 + float(band.y) / 100.0) / 1.28 \
			* (300.0 / maxf(1.0, float(ax["beam"])))


## 한 마리라도 이보다 더 가려지면 그 방은 다시 만든다.
##
## ★ 왜 필요한가 (실측): RoomGen 은 목표 밴드에 **못 닿아도** 절대 한계(26~86%)만
##   지키면 그 자리를 통과시킨다. 밝은 방에서는 그래도 되지만 — 조금 더 가려질 뿐이다 —
##   여기서는 가림%가 어둠과 **곱해진다.** 82% 가려진 공룡은 빛을 정확히 그 자리에
##   비춰도 알아볼 수 없다. 밴드를 아무리 낮춰도 실제 가림%는 안 내려간다는 것을
##   실측으로 확인했으므로(낮은 가림% 자리가 방에 물리적으로 모자란다), 밴드가 아니라
##   **결과**를 보고 거른다.
const COV_CAP := 62


## 이 탄의 방. 아이가 보는 탄 번호(stage)와 난이도용 유효탄(e)이 따로다.
##
## ★ stage + 6 을 넘긴다. RoomGen 의 방 이름·색 표는 "7탄부터 자동 생성"을 전제로
##   (stage - 7) 로 도는데, 손전등 찾기는 1탄부터 전부 자동 생성이기 때문이다.
##   이걸 안 맞추면 1~6탄이 표를 뒤에서부터 거꾸로 돈다.
static func stage_room(e: int, rng: RandomNumberGenerator, stage: int, t: Dictionary = {}) -> Dictionary:
	var tt := room_tuning(t)
	var want := int(RoomGen.axes(e, tt)["dinos"])
	var best: Dictionary = {}
	var best_n := -1
	var best_hi := 999
	# 세 번까지 만들어 보고 **가장 덜 가려진 방**을 쓴다. 방 전환은 페이드 뒤에서
	# 일어나므로 20ms 쯤은 아이 눈에 안 보인다 (한 방 생성이 3~7ms).
	#
	# ★ 마릿수가 먼저다. 가림%만 보고 고르면 **공룡이 덜 놓인 방이 유리해진다** —
	#   자리가 적을수록 최대 가림%도 낮게 나오기 때문이다. 그 편향을 그대로 두면
	#   생성기가 조용히 "쉬운 대신 짧은 방"을 뽑는 쪽으로 흐른다.
	for attempt in 3:
		var room := RoomGen.stage_room(e, rng, stage + 6, tt)
		var n := mini(int(room["count"]), (room["spots"] as Array).size())
		var hi := max_coverage(room)
		if n > best_n or (n == best_n and hi < best_hi):
			best_n = n
			best_hi = hi
			best = room
		if n >= want and hi <= COV_CAP:
			break
	return best


## 이 방에서 가장 많이 가려진 공룡의 가림%
static func max_coverage(room: Dictionary) -> int:
	var hi := 0
	for sp in (room["spots"] as Array).slice(0, int(room["count"])):
		var st: Dictionary = Rooms.spot_transform(room["front"], sp)
		hi = maxi(hi, Rooms.coverage(st["pos"], room["front"]))
	return hi
