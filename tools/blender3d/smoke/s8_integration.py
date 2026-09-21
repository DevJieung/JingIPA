# 8 — 권장안을 한 판에 다 얹어 돌린다.
#   리그(ARMATURE_AUTO) · 액션 2종 · 8방향(오브젝트 회전) · 툰 3톤(EEVEE+Standard+samples1)
#   · 인버티드 헐(even offset, 1px) · 기준점 스냅 · filter0 이진 알파
# 나오는 것: 8방향 x 2액션 x 8프레임 시트 + 처리량.
import sys, os, math, json, time
import bpy
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

argv=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
outdir=argv[0]; os.makedirs(outdir,exist_ok=True)

RES=96; K=32; ORTHO=RES/K          # ★ 3.0 — 월드 1유닛 = 정확히 32px
PX=ORTHO/RES
ELEV=30.0
FRAMES=8
TONES=[(0.10,0.13,0.32),(0.35,0.48,0.82),(0.86,0.92,1.00)]

sc=None
def setup():
    global sc
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc=bpy.context.scene; vl=bpy.context.view_layer
    sc.render.engine='BLENDER_EEVEE'
    sc.eevee.taa_render_samples=1                 # ★ 1 이 아니면 톤이 번진다
    sc.render.resolution_x=sc.render.resolution_y=RES
    sc.render.resolution_percentage=100
    sc.render.image_settings.file_format='PNG'; sc.render.image_settings.color_mode='RGBA'
    sc.render.film_transparent=True
    sc.render.filter_size=0.0                     # ★ 이진 알파
    sc.render.dither_intensity=0.0
    sc.view_settings.view_transform='Standard'    # ★ AgX 면 팔레트가 어긋난다
    sc.view_settings.look='None'
    w=bpy.data.worlds.new("W"); sc.world=w; w.use_nodes=True
    w.node_tree.nodes["Background"].inputs[0].default_value=(0,0,0,1)
    return sc,vl

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

sc,vl=setup()
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
tm=toon()
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

ch.data.materials.append(omat())
md=ch.modifiers.new("Hull",'SOLIDIFY')
md.thickness=1.0*PX; md.offset=1.0
md.use_flip_normals=True; md.use_rim=False
md.use_even_offset=True                       # ★ 이게 없으면 모서리에 구멍이 난다
md.material_offset=1; md.material_offset_rim=1

for pb in arm.pose.bones: pb.rotation_mode='XYZ'
def mk(name,keys):
    act=bpy.data.actions.new(name); arm.animation_data_create()
    old=arm.animation_data.action; arm.animation_data.action=act
    for fr,poses in keys:
        for bn,rot in poses.items():
            pb=arm.pose.bones[bn]; pb.rotation_euler=tuple(math.radians(v) for v in rot)
            pb.keyframe_insert("rotation_euler",frame=fr)
    arm.animation_data.action=old; return act
idle=mk("idle",[(1,{"spine":(0,0,0),"head":(0,0,0)}),
                (5,{"spine":(5,0,0),"head":(-4,0,0)}),
                (9,{"spine":(0,0,0),"head":(0,0,0)})])
wave=mk("wave",[(1,{"spine":(0,0,0),"head":(0,0,0)}),
                (3,{"spine":(-14,0,26),"head":(30,0,-20)}),
                (6,{"spine":(-22,0,38),"head":(52,0,-32)}),
                (9,{"spine":(0,0,0),"head":(0,0,0)})])

cd=bpy.data.cameras.new("C"); cd.type='ORTHO'; cd.ortho_scale=ORTHO
cam=bpy.data.objects.new("C",cd); sc.collection.objects.link(cam)
el=math.radians(ELEV); dist=10.0
cam.location=(0,-dist*math.cos(el),1.1+dist*math.sin(el))
cam.rotation_euler=(math.radians(90)-el,0,0); sc.camera=cam
ld=bpy.data.lights.new("S",'SUN'); ld.energy=3.0
lo=bpy.data.objects.new("S",ld); lo.rotation_euler=(math.radians(50),0,math.radians(35))
sc.collection.objects.link(lo)
vl.update()

# ★ 기준점 스냅 — 월드 원점이 정확한 정수 픽셀 행에 앉게 카메라를 로컬 up 으로 민다
co=world_to_camera_view(sc,cam,Vector((0,0,0)))
y=(1.0-co.y)*RES
d_units=(y-round(y))*ORTHO/RES
cam.location = cam.location + (cam.matrix_basis.to_quaternion() @ Vector((0,1,0)))*(-d_units)
vl.update()
co=world_to_camera_view(sc,cam,Vector((0,0,0)))
ANCHOR=[round(co.x*RES,6), round((1.0-co.y)*RES,6)]

bpy.ops.render.render(write_still=False)   # 워밍업 (GPU 컨텍스트)
t0=time.time(); n=0
man={"res":RES,"ortho_scale":ORTHO,"px_per_unit":K,"elev_deg":ELEV,
     "anchor_px":ANCHOR,"outline_px":1.0,"frames":FRAMES,"clips":{}}
for act in (idle,wave):
    arm.animation_data.action=act
    man["clips"][act.name]={}
    for d in range(8):
        arm.rotation_euler=(0,0,math.radians(45*d))
        fl=[]
        for f in range(FRAMES):
            sc.frame_set(1+f)
            bpy.context.view_layer.update()
            p=os.path.abspath("%s/%s_d%d_f%d.png"%(outdir,act.name,d,f))
            sc.render.filepath=p; bpy.ops.render.render(write_still=True)
            fl.append(p); n+=1
        man["clips"][act.name]["d%d"%d]=fl
el_t=time.time()-t0
man["render_sec_total"]=round(el_t,3); man["render_sec_per_frame"]=round(el_t/n,4); man["n_frames"]=n
json.dump(man,open(os.path.join(outdir,"manifest.json"),"w"),indent=1)
print("SMOKE8_JSON "+json.dumps({k:v for k,v in man.items() if k!="clips"}))
