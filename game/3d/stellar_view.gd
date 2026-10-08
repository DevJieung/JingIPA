extends RefCounted
class_name StellarView

## A real 3D viewport is composed underneath the existing localized, touch-sized UI.
var viewport: SubViewport
var world: StellarWorld
var box := Rect2()
var _drag := false
var _pan := false
var _centroid := Vector2.INF
var _last := Vector2.ZERO
var _touches: Dictionary = {}
var _pinch := -1.0

func attach(parent: CanvasItem, rect: Rect2) -> void:
	box = rect
	if viewport == null or not is_instance_valid(viewport):
		viewport=SubViewport.new()
		viewport.name="Stellar3DViewport"
		viewport.own_world_3d=true
		viewport.transparent_bg=false
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		viewport.msaa_3d=Viewport.MSAA_2X
		parent.add_child(viewport)
		world=StellarWorld.new()
		viewport.add_child(world)
	var wanted := Vector2i(maxi(64,int(rect.size.x)),maxi(64,int(rect.size.y)))
	if viewport.size!=wanted: viewport.size=wanted

func draw(ci: CanvasItem, rect: Rect2, time: float, heroes: Array, selected: int = -1,
		available: bool = false, sim = null, paused: bool = false) -> void:
	attach(ci,rect)
	world.build_map(Run.theme_for(Run.wave))
	if sim == null:
		world.sync_heroes(heroes,time)
		world.weather_update(time)
		for i in range(world.crystals.size()): world.crystals[i].visible=i<Run.lives
	else:
		world.sync_battle(sim, time, Run.lives, 0.0 if paused else 0.016)
	var post := -1
	var radius := 0.0
	if selected>=0 and selected<heroes.size():
		var hero: Dictionary = heroes[selected]["h"] if sim!=null else heroes[selected]
		post = int(hero.get("post",selected))
		radius=float(heroes[selected]["range"]) if sim!=null else float(Run.hero_stats(hero)["range"])
	world.set_selection(post,available,radius)
	ci.draw_texture_rect(viewport.get_texture(),rect,false)
	for item in world.texts:
		var at := project(item["p"],0.98)+Vector2(0,-float(item["age"])*30)
		if not rect.grow(-12).has_point(at): continue
		var color: Color=item["color"]
		color.a=clampf(1.5-float(item["age"])*2.0,0,1)
		Look.text_center_out(ci,at,Fx._short_num(float(item["n"])),20 if item["big"] else 15,color,Color("#0c1522"),1.5)

func project(p: Vector2, height: float = 0) -> Vector2:
	return box.position+world.screen(p,height)

func post_at(p: Vector2) -> int:
	if world==null or not box.has_point(p): return -1
	# Screen rectangles follow model heads, including camera orbit and zoom.
	var best := -1
	var distance := INF
	for post in range(Balance.POST_SLOTS):
		var at := project(Balance.post_position(post),0.30)
		var head := project(Balance.post_position(post),1.85)
		var rect := Rect2(Vector2(at.x-24,head.y-8),Vector2(48,maxf(48,at.y-head.y+25)))
		if rect.has_point(p) and p.distance_squared_to(at)<distance:
			best=post
			distance=p.distance_squared_to(at)
	if best>=0: return best
	var logical := world.ground_at(p-box.position)
	for post in range(Balance.POST_SLOTS):
		var value := logical.distance_to(Balance.post_position(post))
		if value<35 and value<distance:
			best=post
			distance=value
	return best

func camera_input(e: InputEvent) -> bool:
	if world==null: return false
	if e is InputEventMouseButton:
		if e.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE] and not e.pressed:
			_drag=false
			_pan=false
			return true
		if not box.has_point(e.position): return false
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and e.pressed:
			world.zoom=clampf(world.zoom*(1.10 if e.button_index==MOUSE_BUTTON_WHEEL_UP else 0.91),0.8,1.8)
			world.camera_update()
			return true
		if e.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			_pan=e.button_index==MOUSE_BUTTON_MIDDLE or e.shift_pressed
			_drag=not _pan
			_last=e.position
			return true
	if e is InputEventMouseMotion and _pan:
		_pan_camera(_last,e.position)
		_last=e.position
		return true
	if e is InputEventMouseMotion and _drag:
		world.yaw+=e.relative.x*0.006
		world.camera_update()
		return true
	if e is InputEventScreenTouch:
		if e.pressed and box.has_point(e.position): _touches[e.index]=e.position
		else: _touches.erase(e.index)
		if _touches.size()<2:
			_pinch=-1
			_centroid=Vector2.INF
		else:
			var points := _touches.values()
			_centroid=(points[0]+points[1])*0.5
			_pinch=points[0].distance_to(points[1])
		return _touches.size()>=2
	if e is InputEventScreenDrag and _touches.has(e.index):
		_touches[e.index]=e.position
		if _touches.size()==2:
			var points := _touches.values()
			var gap: float = points[0].distance_to(points[1])
			var center: Vector2=(points[0]+points[1])*0.5
			if _centroid.is_finite(): _pan_camera(_centroid,center)
			_centroid=center
			if _pinch>0: world.zoom=clampf(world.zoom*gap/_pinch,0.8,1.8)
			_pinch=gap
			world.camera_update()
			return true
	return false

func _pan_camera(from: Vector2, to: Vector2) -> void:
	var a := StellarWorld.world(world.ground_at(from-box.position))
	var b := StellarWorld.world(world.ground_at(to-box.position))
	world.camera_target+=(a-b)
	world.camera_target.x=clampf(world.camera_target.x,-3,3)
	world.camera_target.z=clampf(world.camera_target.z,-3,3)
	world.camera_update()

func camera_button(id: String) -> bool:
	if world==null: return false
	match id:
		"camera:left": world.yaw-=0.18
		"camera:right": world.yaw+=0.18
		"camera:in": world.zoom=clampf(world.zoom*1.13,0.8,1.8)
		"camera:out": world.zoom=clampf(world.zoom/1.13,0.8,1.8)
		"camera:reset":
			world.yaw=-0.12
			world.zoom=1
			world.camera_target=Vector3.ZERO
		_: return false
	world.camera_update()
	return true

func controls(ci: CanvasItem, ui: Ui, at: Vector2) -> void:
	var labels := ["<","-","o","+",">"]
	var ids := ["camera:left","camera:out","camera:reset","camera:in","camera:right"]
	# ASCII camera symbols avoid relying on unbundled glyphs.
	for i in range(ids.size()): ui.button(ci,Rect2(at+Vector2(i*34,0),Vector2(30,28)),labels[i],ids[i],true,Look.PANEL_EDGE,18)
