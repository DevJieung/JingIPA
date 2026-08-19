class_name ChamGen
extends RefCounted

## 참참참의 난이도 손잡이와 **친구의 버릇** 만들기. 단일 진실 소스.
##
## ★ 이 게임의 알맹이는 "찍기"가 아니라 "읽기"다. 친구가 뛰는 방향은 무작위가 아니라
##   **주기가 있는 버릇**이고, 그 증거(발자국)가 화면에 계속 남아 있다. 그래서 아이는
##   운이 아니라 관찰로 이긴다. 그리고 **틀릴수록 발자국이 하나 늘어 다음이 쉬워진다** —
##   이 게임에서 틀리는 것이 벌이 아니라 단서인 이유다.
##
## ★ "읽을 수 있다"는 것이 **생성 방식으로 보장된다** (블록 채우기의 역방향 생성과 같은 원리):
##   친구가 처음 한 바퀴(버릇 길이만큼)를 도는 동안에는 **tell — 뛸 쪽으로 몸이 기우는 것 —
##   이 항상 최대**다. 그 한 바퀴가 끝나면 발자국이 이미 한 주기를 통째로 담고 있어서,
##   tell 이 사라져도 다음 방향이 결정돼 있다. 어느 쪽으로도 막다른 길이 없다.
##
## ★ **잡을 횟수 = 버릇 길이 + 읽는 턴 수** 다. 이게 이 게임의 심장이다.
##   무료 tell 창이 정확히 "버릇 한 바퀴"인데, 한 판이 그 안에서 끝나 버리면
##   아이는 발자국을 한 번도 볼 필요가 없다 — 그러면 버릇도 발자국도 tell 이 옅어지는
##   B축도 전부 장식이 되고, 남는 것은 눈치 게임뿐이다. 실제로 처음에 그렇게 짜여 있었고
##   적대적 리뷰가 잡았다. 그래서 판 길이를 **버릇 길이보다 반드시 길게** 묶어 둔다.
##
## 올리는 축은 넷이고 전부 "볼 것이 늘거나(A) · 잘 안 보이거나(B) · 고를 것이 는다(C)" 다.
## 기다림도 시간 압박도 아예 없다 — 아이가 누를 때까지 친구는 영원히 기다린다.
##   e=3   tell 이 작아지기 시작한다              (B)
##   e=8   버릇이 길어진다 2 -> 3                 (A)
##   e=12  발자국으로 읽어야 하는 턴 1 -> 2       (A)
##   e=16  방향이 는다 2 -> 3 (왼·오 + 하늘)      (C)
##   e=20  버릇 3 -> 4                            (A)
##   e=24  읽는 턴 2 -> 3                         (A)
##
## ★ 방향 3개가 버릇 길이 4보다 **먼저** 오는 이유: 왼·오 둘뿐일 때 읽을 수 있는
##   길이 4 버릇은 회전을 빼면 「둘씩 번갈아」 딱 하나다(전수 확인). 그러면 아이가
##   버릇을 읽는 대신 규칙 하나를 외워 버린다. 방향이 셋이면 48가지가 된다.

const LEFT := 0
const UP := 1
const RIGHT := 2

## 버릇의 최대 길이. 이보다 길면 발자국 줄이 화면을 넘고, 읽는 것이 아니라 외우는 것이 된다.
const LEN_MAX := 5

## 한 판을 끝내는 데 드는 탭 수의 상한.
## ★ **tell 을 아예 안 보고 발자국만 읽는 아이**가 기준이다: 첫 한 바퀴(버릇 길이)는
##   찍고, 그 뒤로는 전부 맞힌다 -> 버릇 길이 + 잡을 횟수. 넘으면 놀이가 아니라 노동이다.
##   tests/cham_check.gd 가 실제로 그 아이를 흉내 내서 확인한다.
const TAPS_MAX := 14


static func axes(e: int, t: Dictionary = {}) -> Dictionary:
	var lmax := clampi(int(t.get("cham_len_max", 4)), 2, LEN_MAX)
	var rmax := maxi(1, int(t.get("cham_read_max", 3)))
	var tell0 := float(t.get("cham_tell", 1.0))
	var tellmin := clampf(float(t.get("cham_tell_min", 0.15)), 0.0, tell0)
	var three := int(t.get("cham_three_at", 16))
	var plen := clampi(2 + _steps(e, [8, 20]), 2, lmax)
	# 무료 tell 창(= 버릇 한 바퀴)이 끝난 뒤에도 이만큼은 더 잡아야 한다.
	# 그 턴들이 **발자국을 읽어야만 맞는 턴**이다.
	var read := clampi(1 + _steps(e, [12, 24]), 1, rmax)
	return {
		# A. 볼 것이 는다
		"pattern_len": plen,
		"read_turns": read,
		"catches": plen + read,
		# B. 잘 안 보인다 — 뛰기 전의 기울임이 작아진다 (첫 한 바퀴는 늘 최대다)
		"tell": clampf(tell0 - (tell0 - tellmin) * float(maxi(0, e - 3)) / 27.0, tellmin, tell0),
		# C. 고를 것이 는다 — 하늘로도 뛴다
		"dirs": 3 if (three > 0 and e >= three) else 2,
	}


static func _steps(e: int, at: Array) -> int:
	var n := 0
	for x in at:
		if e >= int(x):
			n += 1
	return n


## 이 친구의 버릇. 주기가 정확히 plen 이고, 같은 쪽으로 세 번 연속 뛰지 않는다.
##
## ★ 주기를 정확히 맞추는 이유: [왼,오,왼,오] 처럼 더 짧은 주기로 접히면 난이도 축이
##   숫자만 오르고 실제로는 안 오른다. 3연속을 막는 이유: 발자국이 "쭉 한쪽"으로 보이면
##   아이가 버릇이 아니라 습관으로 읽어서, 바뀌는 순간이 배신처럼 느껴진다.
static func pattern(plen: int, dirs: int, rng: RandomNumberGenerator) -> Array[int]:
	var syms: Array[int] = []
	syms.append(LEFT)
	syms.append(RIGHT)
	if dirs >= 3:
		syms.append(UP)
	for attempt in 60:
		var out: Array[int] = []
		for i in plen:
			out.append(int(syms[rng.randi() % syms.size()]))
		if readable(out):
			return out
	return fallback(plen)


## 무작위로 못 만들었을 때 쓰는 예비 버릇. 길이마다 **readable() 을 통과하는 것으로**
## 손으로 정해 둔다 — 예전에는 여기서 만든 것이 스스로 조건을 어겼다
## (길이 4에서 [왼,오,오,오] = 오 3연속). 검사기가 이 함수를 직접 확인한다.
static func fallback(plen: int) -> Array[int]:
	var fb: Array[int] = []
	match plen:
		2: fb = [LEFT, RIGHT]
		3: fb = [LEFT, LEFT, RIGHT]
		4: fb = [LEFT, LEFT, RIGHT, RIGHT]
		5: fb = [LEFT, LEFT, RIGHT, LEFT, RIGHT]
		_:
			for i in plen:
				fb.append(LEFT if (i / 2) % 2 == 0 else RIGHT)
	if not readable(fb):
		fb = [LEFT, RIGHT]      # 마지막 방어선: 어떤 경우에도 읽을 수 있는 버릇
	return fb


## 읽을 수 있는 버릇인가 (검사기가 같은 함수를 본다)
static func readable(p: Array) -> bool:
	if p.size() < 2:
		return false
	var seen := {}
	for d in p:
		seen[int(d)] = true
	if seen.size() < 2:
		return false            # 한쪽으로만 뛰면 버릇이 아니다
	if min_period(p) != p.size():
		return false            # 더 짧은 주기로 접히면 안 된다
	# 같은 쪽 3연속 금지 (동그랗게 이어서 본다 — 버릇은 계속 반복되므로)
	var run := 1
	for i in range(1, p.size() * 2):
		if int(p[i % p.size()]) == int(p[(i - 1) % p.size()]):
			run += 1
			if run >= 3:
				return false
		else:
			run = 1
	return true


## 이 배열이 실제로 갖는 가장 짧은 반복 주기
static func min_period(p: Array) -> int:
	for k in range(1, p.size()):
		if p.size() % k != 0:
			continue
		var ok := true
		for i in p.size():
			if int(p[i]) != int(p[i % k]):
				ok = false
				break
		if ok:
			return k
	return p.size()
