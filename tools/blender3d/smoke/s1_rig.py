# 1번 — 리깅. 헤드리스 background 모드에서 자동 웨이트가 실제로 붙는가.
# 증명: (a) 버텍스 그룹이 뼈 이름으로 생기는가 (b) 웨이트가 0 이 아닌가
#       (c) 뼈를 돌렸을 때 evaluated mesh 의 버텍스가 실제로 움직이는가
import sys, os, math, json
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
outdir = argv[0] if argv else "build/b3d/smoke"
os.makedirs(outdir, exist_ok=True)
R = {}

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
vl = bpy.context.view_layer

# --- 원통 메시 (세로로 길게, 루프컷을 넉넉히 — 자동 웨이트가 나눌 면이 있어야 한다)
bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=3.0, vertices=16, location=(0, 0, 1.5))
mesh = bpy.context.object
mesh.name = "Body"
# 세로로 잘라 준다 (뼈 3개가 나눠 가질 링이 필요하다)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.subdivide(number_cuts=11)
bpy.ops.object.mode_set(mode='OBJECT')
R["mesh_verts"] = len(mesh.data.vertices)

# --- Armature 뼈 3개 (0~1, 1~2, 2~3)
arm_data = bpy.data.armatures.new("Rig")
arm = bpy.data.objects.new("Rig", arm_data)
sc.collection.objects.link(arm)
vl.objects.active = arm
arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
names = ["hips", "spine", "head"]
prev = None
for i, n in enumerate(names):
    b = arm_data.edit_bones.new(n)
    b.head = (0, 0, i * 1.0)
    b.tail = (0, 0, (i + 1) * 1.0)
    if prev is not None:
        b.parent = prev
        b.use_connect = True
    prev = b
bpy.ops.object.mode_set(mode='OBJECT')
R["bones"] = [b.name for b in arm_data.bones]

# --- 자동 웨이트: 메시 선택 + 아마추어 액티브
bpy.ops.object.select_all(action='DESELECT')
mesh.select_set(True)
arm.select_set(True)
vl.objects.active = arm
err = None
try:
    res = bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    R["parent_set_result"] = list(res)
except Exception as e:
    err = "%s: %s" % (type(e).__name__, e)
R["parent_set_error"] = err

# --- (a) 버텍스 그룹
R["vgroups"] = [g.name for g in mesh.vertex_groups]
R["modifiers"] = [(m.name, m.type, getattr(m, "object", None).name if getattr(m, "object", None) else None)
                  for m in mesh.modifiers]
R["parent"] = mesh.parent.name if mesh.parent else None

# --- (b) 웨이트 실측: 뼈마다 웨이트가 붙은 버텍스 수 · 합
wsum = {}
wcnt = {}
zero_w = 0
for v in mesh.data.vertices:
    tot = 0.0
    for g in v.groups:
        gn = mesh.vertex_groups[g.group].name
        wsum[gn] = wsum.get(gn, 0.0) + g.weight
        wcnt[gn] = wcnt.get(gn, 0) + (1 if g.weight > 1e-6 else 0)
        tot += g.weight
    if tot < 1e-6:
        zero_w += 1
R["weight_count_per_bone"] = wcnt
R["weight_sum_per_bone"] = {k: round(v, 3) for k, v in wsum.items()}
R["verts_with_no_weight"] = zero_w

# --- (c) 실제로 변형되는가: head 뼈를 60도 돌리고 evaluated mesh 를 비교
dg = vl.depsgraph
before = [mesh.evaluated_get(dg).to_mesh().vertices[i].co.copy() for i in range(len(mesh.data.vertices))]
pb = arm.pose.bones["head"]
pb.rotation_mode = 'XYZ'
pb.rotation_euler = (math.radians(60), 0, 0)
vl.update()
dg = vl.depsgraph
ev = mesh.evaluated_get(dg).to_mesh()
after = [ev.vertices[i].co.copy() for i in range(len(mesh.data.vertices))]
deltas = [(a - b).length for a, b in zip(after, before)]
moved = sum(1 for d in deltas if d > 1e-4)
R["verts_moved_by_pose"] = moved
R["max_vert_delta"] = round(max(deltas), 4)
R["mean_vert_delta"] = round(sum(deltas) / len(deltas), 4)
# 아래쪽(hips 구역) 은 안 움직여야 정상이다
low = [d for v, d in zip(mesh.data.vertices, deltas) if v.co.z < 0.2]
R["low_verts_max_delta"] = round(max(low), 5) if low else None

# --- 대안 경로도 같이 재 둔다: ARMATURE_NAME (빈 그룹) · ENVELOPE
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene; vl = bpy.context.view_layer
bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=3.0, vertices=16, location=(0, 0, 1.5))
m2 = bpy.context.object
ad2 = bpy.data.armatures.new("Rig2"); a2 = bpy.data.objects.new("Rig2", ad2)
sc.collection.objects.link(a2); vl.objects.active = a2; a2.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
prev = None
for i, n in enumerate(names):
    b = ad2.edit_bones.new(n); b.head = (0, 0, i * 1.0); b.tail = (0, 0, (i + 1) * 1.0)
    if prev is not None: b.parent = prev; b.use_connect = True
    prev = b
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT')
m2.select_set(True); a2.select_set(True); vl.objects.active = a2
alt = {}
for mode in ('ARMATURE_ENVELOPE', 'ARMATURE_NAME'):
    try:
        bpy.ops.object.parent_set(type=mode)
        alt[mode] = {"vgroups": len(m2.vertex_groups),
                     "mods": [mm.type for mm in m2.modifiers]}
    except Exception as e:
        alt[mode] = "ERR %s" % e
R["alt_modes"] = alt

print("SMOKE1_JSON " + json.dumps(R))
