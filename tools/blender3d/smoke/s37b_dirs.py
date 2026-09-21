# 3번 + 7번 (고침) — 앞 판에서 내가 낸 함정:
#   ARMATURE_AUTO 로 부모를 붙이면 **메시가 아마추어의 자식**이 된다(ch.parent == arm).
#   그래서 ch 와 arm 을 둘 다 돌리면 **두 번 돈다** — 45도를 시켰는데 90도가 됐다.
#   ★ 캐릭터를 돌릴 때는 **아마추어(루트)만** 돌린다.
#
# 그리고 7번의 본론: 기준점(월드 원점)이 정확히 정수 픽셀에 앉게 카메라를 맞춘다.
import sys, os, math, json
import bpy
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
outdir = argv[0]; os.makedirs(outdir, exist_ok=True)
RES = 96
TONES=[(0.10,0.13,0.32),(0.35,0.48,0.82),(0.86,0.92,1.00)]

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

def build(ortho_scale, elev_deg, snap_anchor, outline_px=1.0):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc=bpy.context.scene; vl=bpy.context.view_layer
    sc.render.engine='BLENDER_EEVEE'; sc.eevee.taa_render_samples=1
    sc.render.resolution_x=sc.render.resolution_y=RES; sc.render.resolution_percentage=100
    sc.render.image_settings.file_format='PNG'; sc.render.image_settings.color_mode='RGBA'
    sc.render.film_transparent=True; sc.render.filter_size=0.0; sc.render.dither_intensity=0.0
    sc.view_settings.view_transform='Standard'; sc.view_settings.look='None'
    w=bpy.data.worlds.new("W"); sc.world=w; w.use_nodes=True
    w.node_tree.nodes["Background"].inputs[0].default_value=(0,0,0,1)
    parts=[]
    bpy.ops.mesh.primitive_cylinder_add(radius=0.30,depth=1.30,vertices=16,location=(0,0,0.95))
    body=bpy.context.object; parts.append(body)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.subdivide(number_cuts=6); bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.34,segments=20,ring_count=10,location=(0,0,1.90))
    bpy.ops.object.shade_smooth(); parts.append(bpy.context.object)
    for sx in (-1,1):
        bpy.ops.mesh.primitive_cube_add(size=1.0,location=(sx*0.19,0.05,0.075))
        f=bpy.context.object; f.scale=(0.16,0.30,0.075); parts.append(f)
    bpy.ops.mesh.primitive_cube_add(size=1.0,location=(0.46,-0.10,1.30))
    a=bpy.context.object; a.scale=(0.10,0.34,0.10); a.rotation_euler=(0,0,math.radians(-18)); parts.append(a)
    tm,om=toon(),omat()
    for o in parts: o.data.materials.append(tm)
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts: o.select_set(True)
    vl.objects.active=body; bpy.ops.object.join()
    ch=bpy.context.object; ch.name="Char"
    ad=bpy.data.armatures.new("Rig"); arm=bpy.data.objects.new("Rig",ad)
    sc.collection.objects.link(arm); vl.objects.active=arm; arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    prev=None
    for n,z0,z1 in [("hips",0.0,0.9),("spine",0.9,1.55),("head",1.55,2.25)]:
        b=ad.edit_bones.new(n); b.head=(0,0,z0); b.tail=(0,0,z1)
        if prev is not None: b.parent=prev; b.use_connect=True
        prev=b
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    ch.select_set(True); arm.select_set(True); vl.objects.active=arm
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    ch.data.materials.append(om)
    px=ortho_scale/RES
    md=ch.modifiers.new("Hull",'SOLIDIFY'); md.thickness=outline_px*px; md.offset=1.0
    md.use_flip_normals=True; md.use_rim=False; md.material_offset=1; md.material_offset_rim=1

    piv=bpy.data.objects.new("Pivot",None); sc.collection.objects.link(piv); piv.location=(0,0,0)
    cd=bpy.data.cameras.new("C"); cd.type='ORTHO'; cd.ortho_scale=ortho_scale
    cam=bpy.data.objects.new("C",cd); sc.collection.objects.link(cam); cam.parent=piv
    dist=10.0; el=math.radians(elev_deg)
    cam.location=(0,-dist*math.cos(el), 1.1+dist*math.sin(el))
    cam.rotation_euler=(math.radians(90)-el,0,0)
    sc.camera=cam
    ld=bpy.data.lights.new("S",'SUN'); ld.energy=3.0
    lo=bpy.data.objects.new("S",ld); lo.rotation_euler=(math.radians(50),0,math.radians(35))
    sc.collection.objects.link(lo)
    vl.update()

    snap_info=None
    if snap_anchor:
        # ★ 기준점(월드 원점)을 **정수 픽셀 경계**에 앉힌다.
        #    직교 투영이라 카메라를 제 로컬 up 으로 d 만큼 밀면 화면이 정확히 d*(RES/ortho) px 만큼 내려간다.
        co=world_to_camera_view(sc,cam,Vector((0,0,0)))
        y_px=(1.0-co.y)*RES
        want=round(y_px)                      # 가장 가까운 정수 픽셀 경계
        dy_px=y_px-want
        d_units=dy_px*ortho_scale/RES         # 화면 px → 월드 유닛
        up=cam.matrix_world.to_quaternion() @ Vector((0,1,0))   # 카메라 로컬 up 의 월드 방향
        cam.location = cam.location + (cam.matrix_basis.to_quaternion() @ Vector((0,1,0))) * (-d_units)
        vl.update()
        co2=world_to_camera_view(sc,cam,Vector((0,0,0)))
        snap_info={"before_y_px":round(y_px,4),"want":want,
                   "after_y_px":round((1.0-co2.y)*RES,6),
                   "after_x_px":round(co2.x*RES,6)}
    return sc,ch,arm,piv,cam,snap_info

R={"res":RES,"cases":{}}
for tag, ortho, elev, snap in (("level_s3.0_snap",  3.0, 0.0,  True),
                               ("tilt30_s3.0_snap", 3.0, 30.0, True),
                               ("tilt30_s3.0_raw",  3.0, 30.0, False),
                               ("tilt30_s2.6_snap", 2.6, 30.0, True)):
    sc,ch,arm,piv,cam,snap_info = build(ortho, elev, snap)
    R["cases"][tag]={"ortho_scale":ortho,"elev_deg":elev,"px_per_unit":RES/ortho,
                     "snap":snap_info,"frames":{}}
    for mode in ("rot_object","orbit_camera"):
        for i in range(8):
            ang=math.radians(45*i)
            if mode=="rot_object":
                arm.rotation_euler=(0,0,ang); piv.rotation_euler=(0,0,0)   # ★ 루트만 돌린다
            else:
                arm.rotation_euler=(0,0,0);   piv.rotation_euler=(0,0,-ang)
            bpy.context.view_layer.update()
            p=os.path.abspath("%s/%s_%s_%d.png"%(outdir,tag,mode,i))
            sc.render.filepath=p; bpy.ops.render.render(write_still=True)
            co=world_to_camera_view(sc,cam,Vector((0,0,0)))
            R["cases"][tag]["frames"]["%s_%d"%(mode,i)]={
                "png":p,"anchor_px":[round(co.x*RES,5),round((1.0-co.y)*RES,5)]}
print("SMOKE37B_JSON "+json.dumps(R))
