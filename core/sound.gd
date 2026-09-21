extends Node

## 효과음과 장면별 반복 음악. (오토로드 `Sfx`)
##
## ElevenLabs 생성 음원: tools/audio/generate_elevenlabs.py, art/sfx/*.wav, art/bgm/*.ogg.
## 이름은 그 표와 정확히 같아야 한다 — `tests/ns_check` 가 여기서 부르는 이름이
## 실제로 있는 파일인지 검사한다.
##
## ★ **소리가 없어도 게임이 돌아가야 한다.** 그림과 같은 규칙이다(core/art.gd).
##   파일이 없으면 조용히 넘어간다. 헤드리스 검사기는 소리 장치가 아예 없다.
## ★ **같은 소리를 초당 수십 번 내면 안 된다.** 전투에서는 영웅 여섯이 초당 열 발을
##   쏘고, 겹친 영웅은 한 번에 다섯 발이 나간다. 겹쳐 울리면 소리가 뭉개져서
##   「지지직」 하는 잡음 한 덩이가 되고, 폰에서는 그것만으로 프레임이 떨어진다.
##   그래서 소리마다 **최소 간격**을 두고, 그 안에 또 오면 그냥 버린다.

const DIR := "res://art/sfx/"
const MUSIC_DIR := "res://art/bgm/"
const SCENE_MUSIC_IDS := ["camp", "ritual", "battle", "boss"]
const MUSIC_FADE := 1.2
const MUSIC_VOLUME := -3.0

## 동시에 울릴 수 있는 수. 넘치면 **가장 오래된 것을 뺏어 쓴다** —
## 새 소리를 버리면 크리스탈이 깨지는 순간처럼 제일 중요한 소리가 조용해진다.
const VOICES := 14

## 소리마다의 최소 간격(초). 적어 두지 않은 것은 DEFAULT_GAP.
const DEFAULT_GAP := 0.045
const GAP := {
	# 발사음은 제일 자주 난다. 0.09초면 초당 열한 번이고, 그 위로는 사람 귀에
	# 어차피 한 덩이로 들린다.
	"shot_none": 0.09, "shot_fire": 0.09, "shot_ice": 0.09, "shot_elec": 0.09,
	"shot_water": 0.09, "shot_beam": 0.11, "shot_zone": 0.26,
	"hit": 0.06, "hit_weak": 0.13, "hit_resist": 0.12, "hit_immune": 0.22,
	"crit": 0.10, "splash": 0.09, "chain": 0.12,
	# 도탄은 한 발이 최대 세 번 튕기고 겹치면 다섯 발이라, 텀이 없으면 초당 수십 번이다.
	"ric": 0.09,
	"die": 0.05, "die_big": 0.40, "leak": 0.18, "block": 0.20,
	"stun": 0.16, "frost": 0.16,
	# 한 번만 나야 하는 것들.
	"wave": 0.60, "boss": 1.20, "victory": 1.0, "defeat": 1.0, "theme": 0.60,
}

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _last: Dictionary = {}     ## id -> 마지막으로 낸 시각(초)
var _cache: Dictionary = {}    ## id -> AudioStream (없으면 null)
var _on: bool = false
var _music_players: Array[AudioStreamPlayer] = []
var _music_active := 0
var _music_id := ""
var _music_fade := MUSIC_FADE
var _app_paused := false


static func music_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(SCENE_MUSIC_IDS)
	for theme in Roster.THEMES:
		ids.append("theme_" + String(theme["id"]))
	return ids


## 보스전도 현재 테마의 음악을 사용하고, 등장은 별도 보스 효과음으로 알린다.
func battle_music_id(w: int) -> String:
	var theme := Run.theme_for(w)
	if not theme.is_empty():
		return "theme_" + String(theme["id"])
	return "boss" if Balance.is_boss_wave(w) else "battle"


func _ready() -> void:
	# ★ 화면이 없는 기기(이 개발 머신·CI)에서는 아예 안 켠다. 더미 오디오 드라이버에
	#   플레이어 열넷을 매달아 봐야 얻는 것이 없고, 검사기만 느려진다.
	if DisplayServer.get_name() == "headless" and OS.get_environment("POCKER_AUDIO_TEST") != "1":
		return
	_on = true
	for i in range(VOICES):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		_music_players.append(p)
	# 음악은 Main._swap에서 첫 화면이 열릴 때 시작한다.


func _process(dt: float) -> void:
	if not _on:
		return
	sync_music()
	if _app_paused or Ads.busy or not Save.music:
		return
	_music_fade = minf(MUSIC_FADE, _music_fade + dt)
	var ratio := _music_fade / MUSIC_FADE
	for i in range(_music_players.size()):
		var p := _music_players[i]
		p.volume_db = MUSIC_VOLUME + linear_to_db(maxf(0.0001, ratio if i == _music_active else 1.0 - ratio))
		if i != _music_active and ratio >= 1.0:
			p.stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_app_paused = true
		stop_effects()
		sync_music()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_app_paused = false
		sync_music()


func stop_effects() -> void:
	for p in _players:
		p.stop()


func sync_music() -> void:
	var paused := _app_paused or Ads.busy or not Save.music
	for p in _music_players:
		p.stream_paused = paused
	if Ads.busy:
		stop_effects()


func play_music(id: String) -> void:
	if not _on or id == _music_id or not id in music_ids():
		return
	var path := MUSIC_DIR + id + ".ogg"
	if not ResourceLoader.exists(path):
		return
	var stream := ResourceLoader.load(path) as AudioStreamOggVorbis
	if stream == null:
		return
	stream.loop = true
	_music_active = 1 - _music_active
	var p := _music_players[_music_active]
	p.stream = stream
	p.volume_db = -80.0
	p.play()
	_music_id = id
	_music_fade = 0.0
	sync_music()


## 소리 하나를 낸다. `vol` 은 데시벨, `pitch` 는 1.0 이 원래 속도.
##
## ★ pitch 를 살짝 흔들면 같은 소리가 이어져도 기계처럼 안 들린다. 발사음처럼
##   초당 열 번 나는 것에는 이것이 있고 없고가 크다.
func play(id: String, vol: float = 0.0, pitch: float = 1.0, jitter: float = 0.0) -> void:
	if not _on or not Save.sfx or _app_paused or Ads.busy or id == "":
		return
	var now: float = float(Time.get_ticks_msec()) * 0.001
	var gap: float = float(GAP.get(id, DEFAULT_GAP))
	if now - float(_last.get(id, -99.0)) < gap:
		return
	_last[id] = now
	var st := _stream(id)
	if st == null:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = st
	p.volume_db = vol
	p.pitch_scale = clampf(pitch + (randf() * 2.0 - 1.0) * jitter, 0.4, 2.4)
	p.play()


## 간격을 무시하고 반드시 낸다. 크리스탈이 깨지는 순간처럼 **놓치면 안 되는** 것에만.
func force(id: String, vol: float = 0.0, pitch: float = 1.0) -> void:
	_last.erase(id)
	play(id, vol, pitch)


## 그 영웅의 발사음 이름. **속성이 먼저이고 방식이 그다음이다** —
## 광선과 장판은 탄이 없어서 소리가 통째로 달라야 하고, 나머지는 속성이 정한다.
##
## ★ 화면(battle_screen)이 이 규칙을 따로 적으면 언젠가 표와 어긋난다. 여기 한 곳에 둔다.
static func shot_id(elem: String, kind: String) -> String:
	if kind == "beam":
		return "shot_beam"
	if kind == "zone":
		return "shot_zone"
	match elem:
		"fire":
			return "shot_fire"
		"ice":
			return "shot_ice"
		"elec":
			return "shot_elec"
		"water":
			return "shot_water"
	return "shot_none"


## 상성 배수에 맞는 명중음. 화면의 연출과 **같은 갈래**를 탄다(약점 · 저항 · 무효 · 보통).
static func hit_id(em: float) -> String:
	if em > 1.01:
		return "hit_weak"
	if em <= 0.001:
		return "hit_immune"
	if em < 0.99:
		return "hit_resist"
	return "hit"


func _stream(id: String) -> AudioStream:
	if _cache.has(id):
		return _cache[id]
	var st: AudioStream = null
	var path := DIR + id + ".wav"
	if ResourceLoader.exists(path):
		var r := ResourceLoader.load(path)
		if r is AudioStream:
			st = r
	_cache[id] = st
	return st
