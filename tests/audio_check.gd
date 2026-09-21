extends Harness

func _ready() -> void:
	if not require_no_save():
		return
	check(Sfx._on, "audio runtime enabled for regression test")
	Save.set_music(true)
	Save.set_sfx(true)
	Fixture.fresh(15092026)
	var theme_tracks: Dictionary = {}
	for i in range(Roster.THEMES.size()):
		Run.themes.fill(i)
		var expected := "theme_" + String(Roster.THEMES[i]["id"])
		check(Sfx.battle_music_id(6) == expected, "regular battle uses its location track")
		check(Sfx.battle_music_id(10) == expected, "boss battle keeps its location track")
		theme_tracks[expected] = true
	check(theme_tracks.size() == 50, "all 50 locations have distinct music")
	Run.themes[0] = 0
	Run.themes[1] = 10
	check(Sfx.battle_music_id(10) == "theme_calm_lake" and Sfx.battle_music_id(11) == "theme_kiln_yard",
		"music changes at the theme boundary")
	for id in Sfx.music_ids():
		Sfx.play_music(id)
		Sfx._process(Sfx.MUSIC_FADE)
		await get_tree().create_timer(0.04).timeout
		var p: AudioStreamPlayer = Sfx._music_players[Sfx._music_active]
		check(Sfx._music_id == id and p.playing, "music starts: " + id)
		check(p.stream is AudioStreamOggVorbis and p.stream.loop, "stream loops: " + id)
		check(p.stream.get_length() >= 40.0, "full length music: " + id)
		check(is_equal_approx(p.volume_db, Sfx.MUSIC_VOLUME), "music fade reaches target gain")
		var active: int = Sfx._music_active
		Sfx.play_music(id)
		check(Sfx._music_active == active and Sfx._music_fade == Sfx.MUSIC_FADE, "same track does not restart")
	var p: AudioStreamPlayer = Sfx._music_players[Sfx._music_active]
	p.play(p.stream.get_length() - 0.08)
	await get_tree().create_timer(0.25).timeout
	check(p.playing and p.get_playback_position() < 1.0,
		"music passes the end and resumes at the loop start (position %.3f / %.3f)" % [p.get_playback_position(), p.stream.get_length()])
	Save.set_music(false)
	check(p.stream_paused, "music setting immediately pauses playback")
	Sfx.force("button")
	check(Sfx._players.any(func(v): return v.playing), "effects work with music disabled")
	Save.set_sfx(false)
	check(Sfx._players.all(func(v): return not v.playing), "effects off stops outstanding effects")
	Save.set_music(true)
	check(not p.stream_paused, "music independent from effects setting")
	Ads.busy = true
	Sfx._process(0.1)
	check(p.stream_paused, "ad playback pauses background music")
	Ads.busy = false
	Sfx._process(0.1)
	check(not p.stream_paused, "background music resumes after ad")
	var main := load("res://game/main.gd").new() as Node2D
	add_child(main)
	Fixture.fresh(71)
	Run.themes[0] = 0
	Run.themes[1] = 10
	main.go_shop()
	check(Sfx._music_id == "camp", "lobby plays the minor-key forge arrangement")
	Run.phase = Run.Phase.DRAW
	main.show_draw()
	check(Sfx._music_id == "ritual", "card selection uses its separate all-in fate arrangement")
	for wave in [6, 10, 11]:
		Run.wave = wave
		main.go_battle()
		check(Sfx._music_id == Sfx.battle_music_id(wave), "screen transition plays the selected theme")
		Sfx._process(Sfx.MUSIC_FADE)
		await frames(2)
	Run.wave = 10
	main._theme_shown = -1
	main.go_draw()
	check(main.screen is ThemeScreen and Sfx._music_id == "theme_kiln_yard",
		"theme introduction previews the upcoming location music")
	main.show_title()
	check(Sfx._music_id == "camp", "return to title restores camp music")
	main.queue_free()
	await frames(2)
	p = Sfx._music_players[Sfx._music_active]
	Sfx._notification(NOTIFICATION_APPLICATION_PAUSED)
	check(p.stream_paused, "background application cannot continue playing music")
	Sfx._notification(NOTIFICATION_APPLICATION_RESUMED)
	check(not p.stream_paused, "foreground application resumes its music")
	for file in DirAccess.get_files_at("res://art/sfx"):
		if file.ends_with(".wav"):
			var stream: AudioStream = Sfx._stream(file.get_basename())
			check(stream != null and stream.get_length() > 0.05, "generated effect loads: " + file)
	Save.set_sfx(true)
	Sfx.stop_effects()
	for player in Sfx._players:
		player.stream = null
	for player in Sfx._music_players:
		player.stop()
		player.stream = null
	Sfx._cache.clear()
	await get_tree().create_timer(0.2).timeout
	call_deferred("finish", "오디오 회귀 검사")
