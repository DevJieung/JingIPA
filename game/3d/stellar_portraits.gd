extends RefCounted
class_name StellarPortraits

## Captures use the exact live battle rig. Keep decoded mobile textures bounded.
const CACHE_LIMIT := 64
static var _cache: Dictionary = {}

static func path(unit: Dictionary, grade: int) -> String:
	var id := String(unit.get("base_id",unit.get("id","limne")))
	return "res://art/models/portraits/%s/%02d%s.png" % [id,clampi(grade,0,9),"_awakened" if bool(unit.get("fusion_only",false)) else ""]

static func preview(unit: Dictionary, grade: int) -> Dictionary:
	var key := path(unit,grade)
	if _cache.has(key):
		var hit: Dictionary = _cache[key]
		_cache.erase(key)
		_cache[key]=hit
		return hit
	if not ResourceLoader.exists(key): key=path(unit,0)
	if not ResourceLoader.exists(key): return {}
	var texture: Texture2D = ResourceLoader.load(key)
	var filtered := CanvasTexture.new()
	filtered.diffuse_texture=texture
	filtered.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	var preview := {"tex":filtered,"src":Rect2(Vector2.ZERO,texture.get_size())}
	_cache[key]=preview
	while _cache.size()>CACHE_LIMIT: _cache.erase(_cache.keys()[0])
	return preview
