extends Node3D
class_name NativeMonsterModel

## Native creature presentation reads BattleSim's existing motion_t only.
const MANIFEST := "res://art/models/native_monsters.json"
static var _manifest: Dictionary = {}
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _idle := ""
var _move := ""

static func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(MANIFEST):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Dictionary: _manifest = parsed
	return _manifest

static func has_model(id: String) -> bool:
	var data := manifest()
	return id in data.get("ready_ids",[]) and data.get("monsters",{}).has(id) and ResourceLoader.exists(String(data["monsters"][id]["path"]))

static func create(id: String) -> Node3D:
	var row: Dictionary = manifest().get("monsters",{}).get(id,{})
	if row.is_empty(): return null
	var packed := load(String(row["path"])) as PackedScene
	if packed == null: return null
	var root := packed.instantiate() as Node3D
	root.set_script(load("res://game/3d/native_monster_model.gd"))
	root.set_meta("_stellar_native_monster",true)
	root.set_meta("_stellar_monster_id",id)
	root.set_meta("model_source",String(row["path"]))
	NativeCharacterModel._style(root,float(row.get("metallic",0.0)))
	_setup_status(root,float(row.get("height",1.0)))
	var player := _find_type(root,"AnimationPlayer") as AnimationPlayer
	if player != null:
		for clip in player.get_animation_list():
			if String(clip).ends_with("IdleLoop") or String(clip).ends_with("MoveLoop"):
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	return root

static func _setup_status(root: Node3D, height: float) -> void:
	for status in ["Burn","Frost","Stun"]:
		var group := Node3D.new()
		group.name = "Stellar"+status
		group.visible = false
		root.add_child(group)
		if status == "Stun":
			group.position.y = height+0.10
			for n in 3:
				var angle := n*TAU/3.0
				StellarModels.part(group,"sphere",Vector3(cos(angle)*0.20,0,sin(angle)*0.20),Vector3.ONE*0.09,Color("#ffe38b"),0.0,0.7)
		else:
			var tint := Color("#ff994d") if status=="Burn" else Color("#a5e6f0")
			for n in 5:
				var angle := n*TAU/5.0
				StellarModels.part(group,"cone",Vector3(cos(angle)*0.25,0.10,sin(angle)*0.25),Vector3(0.10,0.44 if status=="Burn" else 0.26,0.09),tint,0.0,0.6)

func _ready() -> void:
	_skeleton = _find_type(self,"Skeleton3D") as Skeleton3D
	_player = _find_type(self,"AnimationPlayer") as AnimationPlayer
	if _skeleton == null or _player == null:
		push_error("Native monster requires actual skin and authored motion clips")
		return
	for name in _player.get_animation_list():
		if String(name).ends_with("IdleLoop"): _idle = name
		if String(name).ends_with("MoveLoop"): _move = name
	# glTF stores keyframes but has no animation-loop flag. These named,
	# authored endpoint-matched clips loop uniformly for every instance.
	for clip in [_idle,_move]:
		if clip != "": _player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	animate_visual(0)

func animate_visual(motion_time: float, moving: bool = true) -> void:
	if _player == null: return
	var clip := _move if moving else _idle
	if clip == "": return
	var animation := _player.get_animation(clip)
	if _player.current_animation != clip: _player.play(clip)
	_player.seek(fposmod(motion_time,maxf(animation.length,0.001)),true)
	_player.pause()

static func _find_type(node: Node, type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var found := _find_type(child,type)
		if found != null: return found
	return null
