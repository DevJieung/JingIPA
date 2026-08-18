## 효과음 / 배경음 재생기.
##
## 오토로드 이름: Audio
## 모든 사운드는 tools/gen_audio.py 로 합성한 res://games/math/audio/*.ogg 이다.
extends Node

const SFX_DIR := "res://games/math/audio/"
const VOICE_COUNT := 10

const SFX_NAMES: PackedStringArray = [
	"ui_tap", "answer_pick", "block_pop", "block_snap", "count_tick", "merge",
	"ten_bundle",
	"correct", "wrong", "tongue", "snake_hit", "snake_die", "frog_hurt",
	"heart_lost", "jump", "star", "stage_clear", "world_clear", "game_over",
	"unlock",
]

const BGM_NAMES: PackedStringArray = ["bgm_menu", "bgm_battle"]

## 효과음별 기본 볼륨(dB) 보정 — 합성 결과가 균일하지 않아 여기서 다듬는다.
const SFX_GAIN := {
	"ui_tap": -6.0,
	"answer_pick": -5.0,
	"block_pop": -7.0,
	"block_snap": -5.0,
	"count_tick": -11.0,
	"merge": -7.0,
	"ten_bundle": -4.0,
	"correct": -2.0,
	"wrong": -4.0,
	"tongue": -5.0,
	"snake_hit": -4.0,
	"snake_die": -4.0,
	"frog_hurt": -5.0,
	"heart_lost": -5.0,
	"jump": -8.0,
	"star": -3.0,
	"stage_clear": -2.0,
	"world_clear": -2.0,
	"game_over": -4.0,
	"unlock": -3.0,
}

const BGM_VOLUME_DB := -10.0   # 파일 피크를 0.52 로 낮춘 만큼 재생 볼륨으로 보정
const FADE_TIME := 0.7

var _sfx: Dictionary = {}          # name -> AudioStream
var _bgm: Dictionary = {}          # name -> AudioStream
var _voices: Array[AudioStreamPlayer] = []
var _voice_index := 0
var _bgm_players: Array[AudioStreamPlayer] = []
var _bgm_active := 0
var _current_bgm := ""
var _bgm_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_streams()
	for i in VOICE_COUNT:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_voices.append(p)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = -80.0
		add_child(p)
		_bgm_players.append(p)
	MathGame.settings_changed.connect(_on_settings_changed)


func _exit_tree() -> void:
	# 종료 시 스트림을 놓아주지 않으면 엔진이 "resources still in use" 를 찍는다.
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	for p in _bgm_players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	for v in _voices:
		if is_instance_valid(v):
			v.stop()
			v.stream = null
	_sfx.clear()
	_bgm.clear()


func _load_streams() -> void:
	for n in SFX_NAMES:
		var path := SFX_DIR + n + ".ogg"
		if ResourceLoader.exists(path):
			_sfx[n] = load(path)
		else:
			push_warning("효과음 없음: %s (tools/gen_audio.py 를 실행하세요)" % path)
	for n in BGM_NAMES:
		var path := SFX_DIR + n + ".ogg"
		if not ResourceLoader.exists(path):
			push_warning("배경음 없음: %s" % path)
			continue
		var s: AudioStream = load(path)
		# .import 파일을 손으로 만들지 않고 런타임에 루프를 켠다.
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		_bgm[n] = s


# --------------------------------------------------------------------------- #
# 효과음
# --------------------------------------------------------------------------- #

## 효과음 재생. pitch 로 음정을 바꿔 같은 샘플을 다양하게 쓴다.
func play(name: String, pitch: float = 1.0, extra_db: float = 0.0) -> void:
	if not MathGame.sfx_enabled:
		return
	if not _sfx.has(name):
		return
	var p := _next_voice()
	p.stream = _sfx[name]
	p.pitch_scale = clampf(pitch, 0.1, 4.0)
	p.volume_db = float(SFX_GAIN.get(name, -5.0)) + extra_db
	p.play()


## 블록을 하나씩 놓을 때 음이 도-레-미처럼 올라가게 한다.
func play_block(index: int, total: int, sfx: String = "block_pop") -> void:
	var t := 0.0 if total <= 1 else float(index) / float(maxi(1, total - 1))
	# 장음계 5음(펜타토닉)을 따라 올라가면 어떤 순서로 들어도 듣기 좋다.
	var steps := [0, 2, 4, 7, 9, 12, 14, 16, 19, 21]
	var idx: int = int(round(t * (steps.size() - 1)))
	var semi: float = float(steps[clampi(idx, 0, steps.size() - 1)])
	play(sfx, pow(2.0, semi / 12.0), -2.0)


func play_count(index: int, total: int) -> void:
	var t := 0.0 if total <= 1 else float(index) / float(maxi(1, total - 1))
	play("count_tick", 1.0 + t * 0.8)


func stop_all_sfx() -> void:
	for v in _voices:
		v.stop()


func _next_voice() -> AudioStreamPlayer:
	# 재생 중이 아닌 보이스를 우선 쓰고, 없으면 가장 오래된 것을 뺏는다.
	for i in _voices.size():
		var idx := (_voice_index + i) % _voices.size()
		if not _voices[idx].playing:
			_voice_index = (idx + 1) % _voices.size()
			return _voices[idx]
	var v := _voices[_voice_index]
	_voice_index = (_voice_index + 1) % _voices.size()
	return v


# --------------------------------------------------------------------------- #
# 배경음
# --------------------------------------------------------------------------- #

func play_bgm(name: String) -> void:
	if _current_bgm == name and _bgm_players[_bgm_active].playing:
		_apply_bgm_volume()
		return
	if not _bgm.has(name):
		return
	_current_bgm = name

	var nxt := 1 - _bgm_active
	var from_p := _bgm_players[_bgm_active]
	var to_p := _bgm_players[nxt]

	to_p.stream = _bgm[name]
	to_p.volume_db = -80.0
	to_p.play()
	_bgm_active = nxt

	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	_bgm_tween = create_tween()
	_bgm_tween.set_parallel(true)
	var target := BGM_VOLUME_DB if MathGame.bgm_enabled else -80.0
	_bgm_tween.tween_property(to_p, "volume_db", target, FADE_TIME)
	_bgm_tween.tween_property(from_p, "volume_db", -80.0, FADE_TIME)
	_bgm_tween.chain().tween_callback(from_p.stop)


func stop_bgm() -> void:
	_current_bgm = ""
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	for p in _bgm_players:
		p.stop()


func _apply_bgm_volume() -> void:
	var target := BGM_VOLUME_DB if MathGame.bgm_enabled else -80.0
	var p := _bgm_players[_bgm_active]
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	_bgm_tween = create_tween()
	_bgm_tween.tween_property(p, "volume_db", target, 0.25)


func _on_settings_changed() -> void:
	if not MathGame.bgm_enabled:
		_apply_bgm_volume()
	elif _current_bgm != "":
		if not _bgm_players[_bgm_active].playing:
			_bgm_players[_bgm_active].play()
		_apply_bgm_volume()
	if not MathGame.sfx_enabled:
		stop_all_sfx()
