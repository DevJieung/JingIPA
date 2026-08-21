extends Node

## 저장 파일 하나(user://save.cfg). 여기 말고 어디서도 파일을 건드리지 않는다.
##
## ★ POCKER_NO_SAVE=1 이면 읽기만 하고 절대 쓰지 않는다.
##   검사기를 돌릴 때마다 저장이 덮여서 "내 기록"이라고 믿던 값이 사실은 테스트가 만든
##   값이던 일이 rogame 에서 실제로 있었다. 같은 실수를 반복하지 않으려고 처음부터 넣는다.

const PATH := "user://save.cfg"

var best_wave: int = 0          ## 여태 간 가장 높은 탄
var runs: int = 0               ## 시작한 판 수
var clears: int = 0             ## 40탄까지 끝낸 판 수
var total_kills: int = 0
var best_hand: int = -1         ## 여태 만든 가장 높은 족보 (Poker.Hand)
var seen_units: Dictionary = {} ## 도감: 한 번이라도 나온 캐릭터 id -> true
var seen_hands: Dictionary = {} ## 족보별 만든 횟수 (int -> int)
var sound: bool = true

var _readonly: bool = false


func _ready() -> void:
	_readonly = OS.get_environment("POCKER_NO_SAVE") == "1"
	load_file()


func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	best_wave = cf.get_value("run", "best_wave", 0)
	runs = cf.get_value("run", "runs", 0)
	clears = cf.get_value("run", "clears", 0)
	total_kills = cf.get_value("run", "total_kills", 0)
	best_hand = cf.get_value("run", "best_hand", -1)
	seen_units = cf.get_value("book", "units", {})
	seen_hands = cf.get_value("book", "hands", {})
	sound = cf.get_value("opt", "sound", true)


func save_file() -> void:
	if _readonly:
		return
	var cf := ConfigFile.new()
	cf.set_value("run", "best_wave", best_wave)
	cf.set_value("run", "runs", runs)
	cf.set_value("run", "clears", clears)
	cf.set_value("run", "total_kills", total_kills)
	cf.set_value("run", "best_hand", best_hand)
	cf.set_value("book", "units", seen_units)
	cf.set_value("book", "hands", seen_hands)
	cf.set_value("opt", "sound", sound)
	cf.save(PATH)


## 한 판이 끝났을 때 한 번만 부른다.
func record_run(wave: int, kills: int, cleared: bool) -> void:
	best_wave = maxi(best_wave, wave)
	total_kills += kills
	if cleared:
		clears += 1
	save_file()


func record_hand(hand: int, unit_id: String) -> void:
	if hand > best_hand:
		best_hand = hand
	seen_hands[hand] = int(seen_hands.get(hand, 0)) + 1
	if unit_id != "":
		seen_units[unit_id] = true
	save_file()
