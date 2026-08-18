class_name Sfx
extends Node

## 소리 파일 없이 코드로 만드는 효과음.

var enabled := true

var _players: Array[AudioStreamPlayer] = []
var _idx := 0
var _bank: Dictionary = {}

const RATE := 22050


func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_bank["find"] = _make([784.0, 988.0, 1319.0], 0.085, 7.0, 0.42)
	_bank["clear"] = _make([523.0, 659.0, 784.0, 1047.0], 0.12, 5.0, 0.42)
	_bank["hooray"] = _make([523.0, 659.0, 784.0, 1047.0, 1319.0, 1047.0, 1319.0], 0.13, 4.0, 0.42)
	_bank["tap"] = _make([520.0], 0.05, 26.0, 0.20)
	_bank["miss"] = _make([300.0, 240.0], 0.07, 18.0, 0.18)
	_bank["start"] = _make([392.0, 523.0, 784.0], 0.1, 6.0, 0.4)


func play(name: String, pitch := 1.0) -> void:
	if not enabled or not _bank.has(name):
		return
	var p := _players[_idx]
	_idx = (_idx + 1) % _players.size()
	p.stream = _bank[name]
	p.pitch_scale = clampf(pitch, 0.5, 2.0)
	p.play()


func stop_all() -> void:
	for p in _players:
		p.stop()


func _make(notes: Array, note_dur: float, decay: float, vol: float) -> AudioStreamWAV:
	var tail := note_dur * 2.5
	var total := int(RATE * (note_dur * notes.size() + tail))
	var buf := PackedFloat32Array()
	buf.resize(total)

	for n in notes.size():
		var f: float = notes[n]
		var start := int(n * note_dur * RATE)
		var count := int((note_dur + tail) * RATE)
		for i in count:
			var idx := start + i
			if idx >= total:
				break
			var tt := float(i) / float(RATE)
			var env: float = exp(-tt * decay) * minf(1.0, tt * 300.0)
			var s := sin(TAU * f * tt) + 0.35 * sin(TAU * f * 2.0 * tt) + 0.12 * sin(TAU * f * 3.0 * tt)
			buf[idx] += s / 1.47 * env * vol

	var data := PackedByteArray()
	data.resize(total * 2)
	for i in total:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 31000.0))

	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = data
	return st
