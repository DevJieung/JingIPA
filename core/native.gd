extends RefCounted
class_name Native

## The optional C++ kernels (addons/stellar_native, docs/PERF_NATIVE.md): road tests and
## monster navigation for ArenaGeometry / ArenaSim and the monster pose sampler.
## Every caller keeps its GDScript path and asks here first, so the game is the same game
## without the library (iOS and desktop builds have none yet) and with
## STELLARDEFENSE_NO_NATIVE=1, which the checks use to compare the two paths.
## ★ Never name a native class in GDScript (`StellarRoads.new()`): a script that does
##   fails to compile wherever the library is absent. Instantiate through make().
static var _state := -1

static func enabled() -> bool:
	if _state < 0:
		var wanted := OS.get_environment("STELLARDEFENSE_NO_NATIVE") != "1"
		_state = 1 if wanted and ClassDB.class_exists("StellarRoads") and ClassDB.can_instantiate("StellarRoads") else 0
	return _state == 1

## A fresh instance of a native class, or null without the library.
static func make(cls: String):
	return ClassDB.instantiate(cls) if enabled() else null

## Tools and checks only: force the GDScript path (false) or the library (true) for the
## objects created from now on. Objects already built keep whatever they got.
static func override(on: bool) -> void:
	_state = 1 if on and ClassDB.class_exists("StellarRoads") else 0
