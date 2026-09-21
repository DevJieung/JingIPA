extends RefCounted
class_name Dbg

## 디버그 오버레이가 들고 있는 상태 전부. **정적 변수뿐이다** — 오토로드가 아니다.
##
## 왜 오토로드가 아닌가: 오토로드를 하나 늘리면 project.godot 이 바뀌고, 검사기 넷과
## 촬영 도구가 전부 그 오토로드를 지고 돌게 된다. 여기 있는 것은 「지금 켜져 있나」와
## 「최근에 무엇을 맞았나」뿐이라 판이 바뀌면 버려도 되는 값이다. 정적 변수면
## `Dbg.on` 한 글자로 아무 데서나 읽힌다.
##
## ★ **꺼져 있으면 아무 일도 안 한다.** DbgSim 의 override 들이 첫 줄에서
##   `if not Dbg.on:` 으로 빠져나가므로, 오버레이를 안 켠 판은 예전과 똑같이 돈다.
## ★ 이 파일은 **그리기를 모른다**(CLAUDE.md 11 과 같은 뜻). 그리는 것은
##   game/debug_view.gd 이고, 담는 것은 game/dbg_sim.gd 다.

## 오버레이가 켜져 있는가. F3 으로 토글한다.
static var on: bool = false
## 지금 보고 있는 탭 (0 흐름 · 1 영웅 · 2 몬스터 · 3 표)
static var tab: int = 0
## 곱셈 사슬을 펼쳐 볼 영웅 번호(성역 자리). 1~6 키로 고른다.
static var sel: int = 0
## 전투를 멈춰 뒀는가. 스페이스로 토글한다.
static var paused: bool = false
## 마침표를 눌러 「한 걸음만」을 요청했는가. 굴린 쪽이 지운다.
static var step_once: bool = false

## 담아 두는 줄 수. 초당 수백 줄이 들어오므로 반드시 상한이 있어야 한다 —
## 없으면 한 탄에 이만 줄이 쌓여서 메모리와 그리기가 같이 무너진다.
const CAP := 256

## 고리 버퍼. rows 가 CAP 에 차면 head 부터 덮어쓴다.
## ★ 배열 앞을 remove_at(0) 으로 미는 방식이면 한 줄마다 256칸을 옮긴다.
##   초당 수백 줄이라 그 비용이 그대로 프레임에 얹힌다.
static var rows: Array = []
static var head: int = 0

## 이번 탄에 헛방(면역 0배)이 몇 번이었나. 성역 편성이 틀렸다는 가장 또렷한 신호다.
static var wasted: int = 0
## 경로별 누적 피해 (직격 · 광역 · 연쇄 · 광선 · 장판 · 화상 · 패시브)
static var by_ctx: Dictionary = {}


## 탄이 바뀔 때마다 비운다. 안 비우면 지난 탄의 줄이 섞여서 「지금 무슨 일이
## 일어나는가」를 못 읽는다.
## ★ 멈춤도 같이 푼다. 정적 변수는 화면이 바뀌어도 살아 있어서, 멈춰 둔 채로 그 탄을
##   끝내면 **다음 탄이 얼어붙은 채로 열린다** — 왜 아무 일도 안 일어나는지 알 길이 없다.
static func reset() -> void:
	rows.clear()
	head = 0
	wasted = 0
	by_ctx.clear()
	paused = false
	step_once = false


static func push(row: Dictionary) -> void:
	if rows.size() < CAP:
		rows.append(row)
	else:
		rows[head] = row
		head = (head + 1) % CAP
	var c := String(row.get("ctx", "?"))
	by_ctx[c] = float(by_ctx.get(c, 0.0)) + float(row.get("got", 0.0))
	if float(row.get("em", 1.0)) <= 0.0:
		wasted += 1


## 최근 n 줄을 **오래된 것부터** 돌려준다.
static func recent(n: int) -> Array:
	var out: Array = []
	var cnt: int = mini(n, rows.size())
	if rows.size() < CAP:
		for i in range(rows.size() - cnt, rows.size()):
			out.append(rows[i])
		return out
	for k in range(cnt):
		out.append(rows[(head + rows.size() - cnt + k) % rows.size()])
	return out
