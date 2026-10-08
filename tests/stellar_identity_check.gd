extends Harness


func _ready() -> void:
	if not require_no_save():
		return
	check(ProjectSettings.get_setting("application/config/name") == "스텔라 디펜스", "새 한국어 앱 이름")
	check(ProjectSettings.get_setting("application/config/name_localized")["en"] == "Stellar Defense", "새 영어 앱 이름")
	check(ProjectSettings.get_setting("application/config/custom_user_dir_name") == "stellardefense", "새 저장 디렉터리")
	_test_migration()
	finish("Stellar Defense 명칭·기존 저장 이전 검사")


func _test_migration() -> void:
	var script := load("res://core/save.gd")
	var source := "user://stellar-legacy-%d.cfg" % Time.get_ticks_usec()
	var target := source + ".new"
	var old = script.new()
	old.storage_path = source
	old.best_wave = 42
	old.runs = 8
	old.clears = 2
	old.total_kills = 730
	old.best_tier = 8
	old.speed = 3.0
	old.language = "en"
	old.seen_units = {"limne": true}
	old.unit_best = {"limne": 8}
	check(old.save_file(), "기존 형식 저장 준비")
	var original := FileAccess.get_file_as_bytes(source)
	var fresh = script.new()
	fresh.storage_path = target
	fresh.legacy_storage_paths = PackedStringArray([source])
	fresh.load_file()
	check(fresh.legacy_loaded and fresh.best_wave == 42 and fresh.runs == 8, "이전 평생 기록 이전")
	check(fresh.unit_best == {"limne": 8} and fresh.seen_units == {"limne": true}, "도감·최고 랭크 이전")
	check(fresh.speed == 3.0 and fresh.language == "en", "배속·언어 설정 이전")
	check(not FileAccess.file_exists(target), "읽기만으로 새 파일을 쓰지 않음")
	fresh.runs = 9
	check(fresh.save_file(), "다음 변경은 새 경로에 저장")
	check(FileAccess.get_file_as_bytes(source) == original, "이전 저장 원본 보존")
	var restored = script.new()
	restored.storage_path = target
	restored.legacy_storage_paths = PackedStringArray([source])
	restored.load_file()
	check(not restored.legacy_loaded and restored.runs == 9, "새 저장 우선·과거 기록으로 되돌리지 않음")
	# A valid new backup also takes precedence over an older installation.
	var backup := ConfigFile.new()
	backup.load(target)
	backup.save(target + ".bak")
	var bad := FileAccess.open(target, FileAccess.WRITE)
	bad.store_string("[run]\nbest_wave=\"invalid\"\n")
	bad.close()
	restored.load_file()
	check(restored.recovered_backup and not restored.legacy_loaded and restored.runs == 9, "새 백업 우선 복구")
	DirAccess.remove_absolute(target)
	DirAccess.remove_absolute(target + ".bak")
	var invalid := FileAccess.open(source + ".bad", FileAccess.WRITE)
	invalid.store_string("[run]\nbest_wave=\"invalid\"\n")
	invalid.close()
	restored.legacy_storage_paths = PackedStringArray([source + ".bad", source])
	restored.load_file()
	check(restored.legacy_loaded and restored.runs == 8, "잘못된 이전 후보 건너뛰기")
	old.free()
	fresh.free()
	restored.free()
	for path in [source, target, source + ".bad"]:
		for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
			DirAccess.remove_absolute(path + suffix)
