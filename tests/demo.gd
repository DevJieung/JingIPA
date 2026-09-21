extends Harness

## 소개 영상 촬영 전용 진입점. **화면을 실제로 돌려서** 프레임을 통째로 받아 낸다.
##
##   godot --path . res://tests/demo.tscn \
##         --write-movie build/video/f.png --fixed-fps 30 -- --fps 30
##
## ★ 커맨드라인을 읽는 코드는 tests/ 에만 둔다(CLAUDE.md 19). 여기도 그 규칙 안이다.
##
## 왜 사진이 아니라 영상인가: 이 게임이 하는 말의 절반은 **움직임**이다 — 겹친 영웅이
## 한 번에 다섯 발을 쏘는 것도, 장판이 저 멀리 깔리는 것도, 발밑에서 머리 위로 파동이
## 지나가는 것도 한 장으로는 한 톨도 안 보인다. 소개서에 붙일 사진은 사진대로 찍고,
## 「무엇을 하는 게임인가」는 영상이 말한다.
##
## ★ **자막을 화면 안에 그린다.** 나중에 편집기로 얹는 길도 있지만, 이 머신에는 화면이
##   없어서 편집기를 못 띄운다. 게임과 같은 폰트·같은 색으로 그리면 결도 안 어긋난다.
##
## ★ `--fixed-fps` 가 걸리면 한 프레임이 정확히 1/fps 초다. 그래서 「몇 초 보여 줄까」를
##   프레임 수로 바꿔 셀 수 있다 — 소프트웨어 OpenGL 이 아무리 느려도 **영상의 시간은
##   실제 시간과 무관하게** 정확하다.

const W := 1280.0
const H := 800.0
## 촬영용 판의 씨앗(shot.gd 와 다른 판을 보여 주려고 다르게 둔다).
const SEED := 20260902

var fps: int = 30
var main: Node2D = null
var cap: Node2D = null      ## 자막을 그리는 겹 (CanvasLayer 안)

## 지금 자막. `cap` 이 이 값을 읽어 그린다.
var cap_no: int = 0
var cap_all: int = 0
var cap_title: String = ""
var cap_sub: String = ""
var cap_a: float = 0.0      ## 자막 알파 (0~1)
var card_t: String = ""     ## 화면 한가운데 큰 글자 (여는 판 · 닫는 판)
var card_s: String = ""
var card_a: float = 0.0
var veil: float = 0.0       ## 검은 막 (챕터 사이 컷)

var _clock: float = 0.0     ## 자막이 숨 쉬는 데만 쓰는 시계


func _ready() -> void:
	fps = maxi(1, arg_int("--fps", fps))

	# 게임 화면 (아래)
	main = load("res://game/main.gd").new()
	main.name = "Main"
	add_child(main)

	# 자막 겹 (위). main 의 페이드가 layer 100 이므로 그보다 위에 둔다 —
	# 아래에 두면 챕터가 바뀔 때마다 자막이 같이 까매진다.
	var cl := CanvasLayer.new()
	cl.layer = 110
	add_child(cl)
	cap = Node2D.new()
	cap.set_script(load("res://tests/demo_caption.gd"))
	cap.set("demo", self)
	cl.add_child(cap)

	await frames(2)
	await _run()
	get_tree().quit(0)


func _process(dt: float) -> void:
	_clock += dt
	if cap != null:
		cap.queue_redraw()


# --------------------------------------------------------------------------- #
# 흐름 도우미
# --------------------------------------------------------------------------- #
## 초 단위로 기다린다. 고정 fps 라 프레임 수로 정확히 환산된다.
func _hold(sec: float) -> void:
	await frames(maxi(1, int(round(sec * fps))))


## 값 하나를 부드럽게 옮긴다(자막·검은 막처럼 화면 밖의 것들).
func _ramp(prop: String, to: float, sec: float) -> void:
	var n := maxi(1, int(round(sec * fps)))
	var from: float = float(get(prop))
	for i in range(n):
		var k := float(i + 1) / float(n)
		k = k * k * (3.0 - 2.0 * k)          # smoothstep — 뚝 끊기지 않게
		set(prop, lerpf(from, to, k))
		await get_tree().process_frame


## 자막을 갈아 끼운다. 있던 것은 내리고 새 것을 올린다.
func _say(no: int, title: String, sub: String) -> void:
	if cap_a > 0.01:
		await _ramp("cap_a", 0.0, 0.22)
	cap_no = no
	cap_title = title
	cap_sub = sub
	await _ramp("cap_a", 1.0, 0.30)


func _hush() -> void:
	if cap_a > 0.01:
		await _ramp("cap_a", 0.0, 0.25)


## 자막을 잠깐 띄웠다가 **내리고** 화면을 그대로 둔다.
##
## ★ 자막을 장면 내내 띄워 두면 안 된다. 띠가 왼쪽 아래에 붙는데, 테마 판은 거기에
##   범례(네모=몸 · 동그라미=약점 · 빗금=면역)를 적고 투기장은 거기로 바깥 길이 지난다 —
##   실제로 첫 촬영에서 범례 한 줄이 통째로 가려졌다. 읽을 만큼만 띄우고 비켜 준다.
func _beat(no: int, title: String, sub: String, show_sec: float, clean_sec: float) -> void:
	await _say(no, title, sub)
	await _hold(show_sec)
	await _hush()
	if clean_sec > 0.0:
		await _hold(clean_sec)


## 챕터 사이의 컷. 까맣게 덮었다가 다음 화면을 세우고 다시 연다.
func _cut_out() -> void:
	await _ramp("veil", 1.0, 0.34)


func _cut_in() -> void:
	await _ramp("veil", 0.0, 0.40)


## 화면이 등록한 그 자리를 실제로 누른다(play_check 와 같은 길).
func _tap(id: String) -> bool:
	return press(main.screen, id)


func _wait_screen(cls: String, limit_sec: float = 8.0) -> bool:
	return await wait_screen(main, cls, int(limit_sec * fps))


## 전투를 그 조건이 될 때까지 굴린다. `sec` 이 지나면 어쨌든 끝낸다.
func _battle_for(sec: float) -> void:
	var n := int(sec * fps)
	for i in range(n):
		await get_tree().process_frame
		var s = main.screen
		if s == null or s.get("sim") == null:
			continue
		if bool(s.sim.done):
			break


# --------------------------------------------------------------------------- #
# 대본
# --------------------------------------------------------------------------- #
func _run() -> void:
	cap_all = 9

	# ── 여는 판 ──────────────────────────────────────────────────────────
	veil = 1.0
	Save.clear_run()
	main._swap(TitleScreen.new())
	await frames(4)
	card_t = "올인 디펜스"
	card_s = "트럼프 다섯 장으로 영웅을 뽑아 몬스터를 막는다"
	await _ramp("card_a", 1.0, 0.7)
	await _hold(1.9)
	await _ramp("card_a", 0.0, 0.5)
	await _cut_in()
	await _beat(1, "타이틀", "한 판은 100탄. 크리스탈 스무 개가 목숨이다", 2.8, 0.6)

	# ── 1. 테마 판 ───────────────────────────────────────────────────────
	await _cut_out()
	Fixture.prepare(11, SEED)
	Run.wave = 10
	main._theme_shown = -1
	main._swap(ThemeScreen.new())
	await frames(4)
	await _cut_in()
	await _beat(2, "테마 판 — 열 탄에 한 번",
			"열 탄의 이름 · 다섯 몸의 등장 확률 · 보스 · 약점 2배와 면역이 이 한 장에",
			3.2, 3.4)

	# ── 2. 카드 다섯 장 · 리롤 ──────────────────────────────────────────
	await _cut_out()
	Fixture.prepare(12, SEED)
	Run.begin_draw()
	main._swap(DrawScreen.new())
	await frames(4)
	await _cut_in()
	await _say(3, "카드 다섯 장을 받는다",
			"맘에 안 드는 카드는 한 번 공짜로 · 그 뒤로는 15 → 30 → 60 골드")
	await _hold(2.6)
	await _hush()
	# 두 장을 실제로 다시 뽑는다 — 카드가 뒤집히는 것이 이 게임의 첫 손맛이다.
	_tap("re1")
	await _hold(1.3)
	_tap("re3")
	await _hold(2.2)

	# ── 3. 족보 확정 연출 (로열) ────────────────────────────────────────
	await _cut_out()
	Fixture.prepare(12, SEED)
	Run.begin_draw()
	Fixture.stack(9)
	var d := DrawScreen.new()
	main._swap(d)
	await frames(4)
	await _cut_in()
	await _say(4, "족보가 곧 등급이다",
			"로열 플러시 — 열 등급의 맨 위. 그 등급의 다섯 중 하나가 무작위로 나온다")
	await _hold(2.0)
	await _hush()
	d._confirm()
	await _hold(5.0)

	# ── 4. 편성 판 ──────────────────────────────────────────────────────
	await _cut_out()
	Fixture.prepare(24, SEED)
	Run.begin_draw()
	Run.confirm_hand()
	# ★ `confirm_hand()` 이 phase 를 SWAP 으로 올리고 `last_result` 를 남기므로,
	#   DrawScreen 이 스스로 **편성 판부터** 연다(draw_screen._ready).
	main._swap(DrawScreen.new())
	await frames(4)
	await _cut_in()
	await _beat(5, "성역은 여섯 자리",
			"같은 영웅이 또 나오면 옆에 안 세우고 겹친다 — x4 는 한 번에 네 발이다",
			3.4, 2.4)

	# ── 5. 전투 — 속성과 상성 ───────────────────────────────────────────
	await _cut_out()
	Fixture.prepare(16, SEED)
	Run.begin_draw()
	Run.confirm_hand()
	PlayPolicy.arrange(Run)
	Run.wave = 16
	main._swap(BattleScreen.new())
	await frames(4)
	await _cut_in()
	await _beat(6, "속성 다섯 · 무기 다섯",
			"약점이면 2배 · 저항이면 0.5배 · 나무와 바위는 전기를 아예 안 받는다",
			4.2, 0.0)
	await _battle_for(9.5)

	# ── 6. 장판 ─────────────────────────────────────────────────────────
	await _cut_out()
	Fixture.prepare(40, SEED)
	Run.begin_draw()
	Run.confirm_hand()
	Run.heroes.clear()
	Run.bench.clear()
	# 장판(광역) 영웅만 넷 세운다 — 원이 여럿 깔리는 것이 이 장의 요점이다.
	var zn := 0
	for uu in Roster.UNITS:
		if String(uu.get("bullet", "")) == "zone" and int(uu["tier"]) >= 5:
			Run.gain_hero(uu, int(uu["tier"]))
			zn += 1
			if zn >= 4:
				break
	Run.wave = 40
	main._swap(BattleScreen.new())
	await frames(4)
	await _cut_in()
	await _beat(7, "광역은 「어디를」 때릴지 고른다",
			"두 팔을 들면 발밑에서 파동이 지나가고, 가장 많이 겹친 자리에 원이 깔린다",
			4.2, 0.0)
	await _battle_for(8.0)

	# ── 7. 보스 ─────────────────────────────────────────────────────────
	await _cut_out()
	Fixture.prepare(30, SEED)
	Run.begin_draw()
	Run.confirm_hand()
	PlayPolicy.arrange(Run)
	Run.wave = 30
	main._swap(BattleScreen.new())
	await frames(4)
	await _cut_in()
	await _beat(8, "열 탄마다 보스",
			"테마가 보스의 몸을 정한다. 한 번 닿으면 크리스탈이 세 개 깨진다",
			4.2, 0.0)
	await _battle_for(11.0)

	# ── 8. 상점 ─────────────────────────────────────────────────────────
	await _cut_out()
	Fixture.prepare(24, SEED)
	Run.phase = Run.Phase.SHOP
	Run.roll_shop()
	main._swap(ShopScreen.new())
	await frames(4)
	await _cut_in()
	await _say(9, "상점은 세 갈래",
			"능력치 · 패시브 카드 스물여섯 중 셋 · 깨진 크리스탈 되사기")
	await _hold(2.8)
	await _hush()
	_tap("tab:p")
	await _hold(3.2)
	_tap("tab:c")
	await _hold(2.6)

	# ── 닫는 판 ─────────────────────────────────────────────────────────
	await _cut_out()
	card_t = "올인 디펜스"
	card_s = "Godot 4.7 · 안드로이드 · 캐릭터 50 · 몬스터 25 · 테마 50 · 100탄"
	await _ramp("card_a", 1.0, 0.7)
	await _hold(2.8)
	await _ramp("card_a", 0.0, 0.6)
	await _hold(0.6)
