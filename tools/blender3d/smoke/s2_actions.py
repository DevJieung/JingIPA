# 2번 — 액션. Action 두 개를 만들고 갈아 끼우며 렌더가 실제로 달라지는가.
# 증명: 같은 프레임에서 액션만 바꿔 렌더한 PNG 의 픽셀이 다른가 (해시 + 불투명 픽셀 수)
import sys, os, math, json, hashlib
import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
outdir = argv[0] if argv else "build/b3d/smoke/s2"
os.makedirs(outdir, exist_ok=True)
R = {}

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene; vl = bpy.context.view_layer
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = sc.render.resolution_y = 96
sc.render.resolution_percentage = 100
sc.render.image_settings.file_format = 'PNG'
sc.render.image_settings.color_mode = 'RGBA'
sc.render.film_transparent = True
sc.render.filter_size = 0.0
sc.render.dither_intensity = 0.0
sc.eevee.taa_render_samples = 16

# 카메라 · 빛
cd = bpy.data.cameras.new("C"); cd.type = 'ORTHO'; cd.ortho_scale = 4.0
cam = bpy.data.objects.new("C", cd); cam.location = (0, -8, 1.5)
cam.rotation_euler = (math.radians(90), 0, 0)
sc.collection.objects.link(cam); sc.camera = cam
ld = bpy.data.lights.new("S", 'SUN'); ld.energy = 4.0
lo = bpy.data.objects.new("S", ld); lo.rotation_euler = (math.radians(50), 0, math.radians(35))
sc.collection.objects.link(lo)

# 메시 + 리그 (1번과 같은 길)
bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=3.0, vertices=16, location=(0, 0, 1.5))
mesh = bpy.context.object
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.subdivide(number_cuts=11); bpy.ops.object.mode_set(mode='OBJECT')
mat = bpy.data.materials.new("M"); mat.use_nodes = True
mesh.data.materials.append(mat)

ad = bpy.data.armatures.new("Rig"); arm = bpy.data.objects.new("Rig", ad)
sc.collection.objects.link(arm); vl.objects.active = arm; arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
prev = None
for i, n in enumerate(["hips", "spine", "head"]):
    b = ad.edit_bones.new(n); b.head = (0, 0, i * 1.0); b.tail = (0, 0, (i + 1) * 1.0)
    if prev is not None: b.parent = prev; b.use_connect = True
    prev = b
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT')
mesh.select_set(True); arm.select_set(True); vl.objects.active = arm
bpy.ops.object.parent_set(type='ARMATURE_AUTO')

for pb in arm.pose.bones:
    pb.rotation_mode = 'XYZ'

def make_action(name, keys):
    """keys = [(frame, {bone: (rx,ry,rz)deg})]  — 액션을 손으로 만든다(ops 없이)."""
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    old = arm.animation_data.action
    arm.animation_data.action = act
    for fr, poses in keys:
        for bn, rot in poses.items():
            pb = arm.pose.bones[bn]
            pb.rotation_euler = tuple(math.radians(v) for v in rot)
            pb.keyframe_insert("rotation_euler", frame=fr)
    arm.animation_data.action = old
    return act

idle = make_action("idle", [
    (1, {"spine": (0, 0, 0), "head": (0, 0, 0)}),
    (5, {"spine": (4, 0, 0), "head": (-3, 0, 0)}),
    (9, {"spine": (0, 0, 0), "head": (0, 0, 0)}),
])
wave = make_action("wave", [
    (1, {"spine": (0, 0, 0), "head": (0, 0, 0)}),
    (5, {"spine": (-25, 0, 40), "head": (55, 0, -35)}),
    (9, {"spine": (0, 0, 0), "head": (0, 0, 0)}),
])
R["actions"] = [a.name for a in bpy.data.actions]
R["fcurves"] = {a.name: len(a.fcurves) for a in bpy.data.actions}

def render(path):
    sc.render.filepath = os.path.abspath(path)
    bpy.ops.render.render(write_still=True)
    with open(path, "rb") as f:
        return hashlib.sha1(f.read()).hexdigest()[:12]

# --- (A) action 을 갈아 끼우며 렌더
hashes = {}
for act in (idle, wave):
    arm.animation_data.action = act
    for fr in (1, 5):
        sc.frame_set(fr)
        p = "%s/act_%s_f%d.png" % (outdir, act.name, fr)
        hashes["%s_f%d" % (act.name, fr)] = render(p)
R["swap_hashes"] = hashes
R["swap_differs_at_f5"] = hashes["idle_f5"] != hashes["wave_f5"]
R["swap_same_at_f1"] = hashes["idle_f1"] == hashes["wave_f1"]

# --- (B) NLA 트랙으로도 되는가: 두 액션을 스트립으로 얹고 mute 로 고른다
arm.animation_data.action = None
tracks = {}
for i, act in enumerate((idle, wave)):
    tr = arm.animation_data.nla_tracks.new()
    tr.name = act.name
    st = tr.strips.new(act.name, 1, act)
    st.frame_start = 1
    st.frame_end = 9
    tracks[act.name] = tr
R["nla_tracks"] = [t.name for t in arm.animation_data.nla_tracks]
nla_h = {}
for pick in ("idle", "wave"):
    for n, tr in tracks.items():
        tr.mute = (n != pick)
    sc.frame_set(5)
    p = "%s/nla_%s_f5.png" % (outdir, pick)
    nla_h[pick] = render(p)
R["nla_hashes"] = nla_h
R["nla_differs"] = nla_h["idle"] != nla_h["wave"]
R["nla_matches_action_swap"] = (nla_h["wave"] == hashes["wave_f5"] and nla_h["idle"] == hashes["idle_f5"])

print("SMOKE2_JSON " + json.dumps(R))
