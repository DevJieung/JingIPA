extends Node

## Translation happens before layout in Look. Game IDs, save data and combat values
## stay language-independent. Formatted messages use catalog templates, not word order guesses.
signal language_changed(code: String)

var locale := "ko"
var audit_enabled := false
var missing: Dictionary = {}
var observed: Dictionary = {}
var _catalog: Dictionary = {}
var _heroes: Dictionary = {}
var _cache: Dictionary = {}
var _patterns: Dictionary = {"ko": [], "en": []}
var _fragments: Dictionary = {"ko": [], "en": []}
var _hangul := RegEx.new()
var _placeholder := RegEx.new()


func _init() -> void:
	_hangul.compile("[가-힣ㄱ-ㅎㅏ-ㅣ]")
	_placeholder.compile("%(?:[-+0-9.]*[dfs]|%)")
	_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://core/locales/ui.json"))
	_heroes = JSON.parse_string(FileAccess.get_file_as_string("res://core/locales/heroes.json"))
	for u in Roster.UNITS:
		_catalog["en"][String(u["ko"])] = String(u["en"])
		_catalog["ko"][String(u["en"])] = String(u["ko"])
	for code in ["ko", "en"]:
		for source in _catalog[code]:
			var value := String(_catalog[code][source])
			var entry := _pattern(String(source), value)
			if not entry.is_empty():
				_patterns[code].append(entry)
			elif String(source).length() >= 2:
				_fragments[code].append(String(source))
		_patterns[code].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["weight"] > b["weight"])
		_fragments[code].sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())


func _ready() -> void:
	locale = Save.language
	TranslationServer.set_locale(locale)


func set_locale(code: String) -> void:
	if code not in ["ko", "en"] or locale == code:
		return
	locale = code
	_cache.clear()
	missing.clear()
	observed.clear()
	Save.set_language(code)
	TranslationServer.set_locale(code)
	language_changed.emit(code)


func hero_name(id: String) -> String:
	var u := Roster.unit_by_id(id)
	return String(u.get("en" if locale == "en" else "ko", id))


func hero_concept(id: String) -> String:
	var entry: Dictionary = _heroes.get(id, {})
	return String(entry.get(locale, ""))


func t(source: String) -> String:
	if _cache.has(source):
		return String(_cache[source])
	var result := _translate(source, 0)
	if audit_enabled:
		observed[source] = result
		if locale == "en" and _hangul.search(result) != null:
			missing[source] = result
	# Damage counters vary every frame; keep the cache bounded for long runs.
	if _cache.size() >= 4096:
		_cache.clear()
	_cache[source] = result
	return result


func _translate(source: String, depth: int) -> String:
	if source.is_empty() or depth > 8:
		return source
	var entries: Dictionary = _catalog[locale]
	if entries.has(source):
		return String(entries[source])
	# English text produced by an earlier layout call must remain unchanged.
	if locale == "en" and _hangul.search(source) == null:
		return source
	for entry in _patterns[locale]:
		var found: RegExMatch = entry["regex"].search(source)
		if found == null:
			continue
		var out := String(entry["value"])
		for i in range(found.get_group_count()):
			var captured := found.get_string(i + 1)
			out = out.replace("{" + str(i) + "}", _translate(captured, depth + 1))
		return out
	# A UI row often joins independent labels or stat values with a separator.
	for separator in ["\n", "   ·   ", " · ", "  "]:
		if source.contains(separator):
			var parts: PackedStringArray = source.split(separator)
			for i in range(parts.size()):
				parts[i] = _translate(parts[i], depth + 1)
			return separator.join(parts)
	var result := source
	for fragment in _fragments[locale]:
		if not result.contains(fragment):
			continue
		if locale == "ko":
			# Never change a hero's name inside a longer English word.
			var boundary := RegEx.new()
			boundary.compile("(?<![A-Za-z])" + _escape(fragment) + "(?![A-Za-z])")
			result = boundary.sub(result, String(entries[fragment]), true)
		else:
			result = result.replace(fragment, String(entries[fragment]))
	return result


func _escape(value: String) -> String:
	var result := ""
	for c in value:
		result += ("\\" if c in "\\.^$|?*+()[]{}" else "") + c
	return result


func _pattern(source: String, value: String) -> Dictionary:
	var matches := _placeholder.search_all(source)
	if matches.is_empty():
		return {}
	var pattern := "^"
	var at := 0
	var count := 0
	var weight := source.length()
	for found in matches:
		pattern += _escape(source.substr(at, found.get_start() - at))
		var token := found.get_string()
		if token == "%%":
			pattern += "%"
		else:
			pattern += "(.+?)" if token.ends_with("s") else "([-+]?[0-9]+(?:\\.[0-9]+)?)"
			count += 1
			weight -= token.length()
		at = found.get_end()
	pattern += _escape(source.substr(at)) + "$"
	if count == 0:
		return {}
	var regex := RegEx.new()
	regex.compile(pattern)
	return {"regex": regex, "value": value, "weight": weight}
