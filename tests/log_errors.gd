extends Logger

## Collects engine, script and shader errors while a check runs, so the check itself can
## fail on them (tools/verify.sh also greps the output for "ERROR:"). Warnings are ignored.
##   var errors := preload("res://tests/log_errors.gd").new()
##   OS.add_logger(errors) ... check(errors.lines.is_empty(), ...) ... OS.remove_logger(errors)
## Engine threads may log too, hence the lock.

var lines: Array[String] = []
var _lock := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	_lock.lock()
	lines.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
	_lock.unlock()


func count() -> int:
	_lock.lock()
	var n := lines.size()
	_lock.unlock()
	return n
