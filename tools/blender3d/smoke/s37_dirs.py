# 3번 + 7번 — 8방향과 픽셀 떨림. 둘은 같은 문제라 한 판에서 잰다.
#
#   3번: 캐릭터를 Z 로 45도씩 돌리는 것 vs 카메라를 도는 것 — 어느 쪽이 발이 안 흔들리는가
#   7번: 직교 카메라의 ortho_scale 과 해상도를 어떻게 맞춰야 「월드 1유닛 = 정수 픽셀」인가
#
# 리깅(1번)·툰(5번)·인버티드 헐(6번)을 다 얹은 실전 장면에서 잰다 —
# Armature 모디파이어와 Solidify 가 같이 도는가도 여기서 같이 확인된다.
import sys, os, math, json
import bpy
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
outdir = argv[0]; os.makedirs(outdir, exist_ok=True)

RES = 96
TONES = [(0.10,0.13,0.32),(0.35,0.48,0.82),(0.86,0.92,1.00)]

def toon():
    m=bpy.data.materials.new("T"); m.use_nodes=True; nt=m.node_tree; nt.nodes.clear()
    o=nt.nodes.new("ShaderNodeOutputMaterial"); d=nt.nodes.new("ShaderNodeBsdfDiffuse")
    s=nt.nodes.new("ShaderNodeShaderToRGB"); r=nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.interpolation='CONSTANT'; cr=r.color_ramp
    cr.elements[0].position=0.0;  cr.elements[0].color=TONES[0]+(1,)
    cr.elements[1].position=0.28; cr.elements[1].color=TONES[1]+(1,)
    cr.elements.new(0.62).color=TONES[2]+(1,)
    e=nt.nodes.new("ShaderNodeEmission")
    nt.links.new(d.outputs[0],s.inputs[0]); nt.links.new(s.outputs[0],r.inputs[0])
    nt.links.new(r.outputs[0],e.inputs[0]); nt.links.new(e.outputs[0],o.inputs["Surface"])
    return m

def omat():
    m=bpy.data.materials.new("O"); m.use_nodes=True; nt=m.node_tree; nt.nodes.clear()
    o=nt.nodes.new("ShaderNodeOutputMaterial"); e=nt.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value=(0,0,0,1); nt.links.new(e.outputs[0],o.inputs["Surface"])
    m.use_backface_culling=True; return m

def build(ortho_scale, elev_deg, outline_px=1.0):
    """캐릭터는 발바닥이 z=0 에 붙어 있고, 회전축은 월드 Z(원점)다."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc=bpy.context.scene; vl=bpy.context.view_layer
    sc.render.engine='BLENDER_EEVEE'; sc.eevee.taa_render_samples=1
    sc.render.resolution_x=sc.render.resolution_y=RES
    sc.render.resolution_percentage=100
    sc.render.image_settings.file_format='PNG'; sc.render.image_settings.color_mode='RGBA'
    sc.render.film_transparent=True; sc.render.filter_size=0.0; sc.render.dither_intensity=0.0
    sc.view_settings.view_transform='Standard'; sc.view_settings.look='None'
    w=bpy.data.worlds.new("W"); sc.world=w; w.use_nodes=True
    w.node_tree.nodes["Background"].inputs[0].default_value=(0,0,0,1)

    # --- 캐릭터: 몸통 + 발 둘 + 팔 하나 (좌우 비대칭이라야 방향이 읽힌다)
    parts=[]
    bpy.ops.mesh.primitive_cylinder_add(radius=0.30, depth=1.30, vertices=16, location=(0,0,0.95))
    body=bpy.context.object; parts.append(body)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.subdivide(number_cuts=6); bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.34, segments=20, ring_count=10, location=(0,0,1.90))
    head=bpy.context.object; bpy.ops.object.shade_smooth(); parts.append(head)
    for sx in (-1, 1):                      # 발 — 바닥이 정확히 z=0
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx*0.19, 0.05, 0.075))
        f=bpy.context.object; f.scale=(0.16,0.30,0.075); parts.append(f)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.46,-0.10,1.30))   # 앞으로 뻗은 팔
    a=bpy.context.object; a.scale=(0.10,0.34,0.10)
    a.rotation_euler=(0,0,math.radians(-18)); parts.append(a)

    tm, om = toon(), omat()
    for o in parts:
        o.data.materials.append(tm)

    # 한 덩어리로 합친다 (리깅·헐을 하나에 건다)
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts: o.select_set(True)
    vl.objects.active = body
    bpy.ops.object.join()
    ch = bpy.context.object; ch.name = "Char"

    # --- 리그 (1번과 같은 길)
    ad=bpy.data.armatures.new("Rig"); arm=bpy.data.objects.new("Rig",ad)
    sc.collection.objects.link(arm); vl.objects.active=arm; arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    prev=None
    for i,(n,z0,z1) in enumerate([("hips",0.0,0.9),("spine",0.9,1.55),("head",1.55,2.25)]):
        b=ad.edit_bones.new(n); b.head=(0,0,z0); b.tail=(0,0,z1)
        if prev is not None: b.parent=prev; b.use_connect=True
        prev=b
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    ch.select_set(True); arm.select_set(True); vl.objects.active=arm
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')

    # --- 인버티드 헐. ★Armature 뒤에 와야 변형된 몸을 따라 부푼다
    ch.data.materials.append(om)
    px = ortho_scale / RES
    md=ch.modifiers.new("Hull",'SOLIDIFY')
    md.thickness = outline_px * px
    md.offset=1.0; md.use_flip_normals=True; md.use_rim=False
    md.material_offset=1; md.material_offset_rim=1
    mod_order=[m.type for m in ch.modifiers]

    # --- 직교 카메라. 회전축(월드 Z)을 정확히 화면 가운데에 두려고
    #     카메라를 「원점을 도는 빈 오브젝트」에 매단다.
    piv=bpy.data.objects.new("Pivot",None); sc.collection.objects.link(piv)
    piv.location=(0,0,0)
    cd=bpy.data.cameras.new("C"); cd.type='ORTHO'; cd.ortho_scale=ortho_scale
    cam=bpy.data.objects.new("C",cd); sc.collection.objects.link(cam)
    cam.parent=piv
    # 카메라를 -Y 쪽 멀리 두고 elev 만큼 내려다본다. 화면 세로 가운데를 캐릭터 허리(z=1.1)에 맞춘다
    dist=10.0; el=math.radians(elev_deg)
    cam.location=(0, -dist*math.cos(el), 1.1 + dist*math.sin(el))
    cam.rotation_euler=(math.radians(90)-el, 0, 0)
    sc.camera=cam
    ld=bpy.data.lights.new("S",'SUN'); ld.energy=3.0
    lo=bpy.data.objects.new("S",ld); lo.rotation_euler=(math.radians(50),0,math.radians(35))
    sc.collection.objects.link(lo)
    return sc, ch, arm, piv, cam, mod_order

def anchor_px(sc, cam):
    """월드 원점(발밑 기준점)이 몇 번째 픽셀에 찍히는가 — 소수점까지."""
    co = world_to_camera_view(sc, cam, Vector((0,0,0)))
    return (co.x * sc.render.resolution_x, (1.0 - co.y) * sc.render.resolution_y)

R={"res":RES, "cases":{}}
for tag, ortho, elev in (("level_s3.0",   3.0, 0.0),
                         ("tilt30_s3.0",  3.0, 30.0),
                         ("tilt30_s2.6",  2.6, 30.0)):
    sc, ch, arm, piv, cam, mod_order = build(ortho, elev)
    R.setdefault("mod_order", mod_order)
    R["cases"][tag] = {"ortho_scale": ortho, "elev_deg": elev,
                       "px_per_unit": RES/ortho, "frames": {}}
    for mode in ("rot_object", "orbit_camera"):
        for i in range(8):
            ang = math.radians(45*i)
            if mode=="rot_object":
                ch.rotation_euler=(0,0,ang); arm.rotation_euler=(0,0,ang); piv.rotation_euler=(0,0,0)
            else:
                ch.rotation_euler=(0,0,0); arm.rotation_euler=(0,0,0); piv.rotation_euler=(0,0,ang)
            bpy.context.view_layer.update()
            p=os.path.abspath("%s/%s_%s_%d.png"%(outdir,tag,mode,i))
            sc.render.filepath=p
            bpy.ops.render.render(write_still=True)
            ax,ay = anchor_px(sc, cam)
            R["cases"][tag]["frames"]["%s_%d"%(mode,i)] = {
                "png":p, "anchor_px":[round(ax,4), round(ay,4)]}
print("SMOKE37_JSON "+json.dumps(R))
