# 6-c — 실전 캐릭터(합친 메시 + 리그)에서 아웃라인이 **끊긴다.**
# 무엇이 그것을 메우는가를 재서 고른다. 자: 실루엣 경계 픽셀 중 검은 비율.
import sys, os, math, json, time
import bpy
argv=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
outdir=argv[0]; os.makedirs(outdir,exist_ok=True)
RES=96; ORTHO=3.0; PX=ORTHO/RES
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

def character(smooth=False):
    sc=bpy.context.scene; vl=bpy.context.view_layer
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
    if smooth:
        bpy.ops.object.shade_smooth()
        ch.data.use_auto_smooth = True                 # 4.0: 각도로 부드럽게
        ch.data.auto_smooth_angle = math.radians(30)
    return ch

def scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc=bpy.context.scene; sc.render.engine='BLENDER_EEVEE'; sc.eevee.taa_render_samples=1
    sc.render.resolution_x=sc.render.resolution_y=RES
    sc.render.image_settings.file_format='PNG'; sc.render.image_settings.color_mode='RGBA'
    sc.render.film_transparent=True; sc.render.filter_size=0.0; sc.render.dither_intensity=0.0
    sc.view_settings.view_transform='Standard'; sc.view_settings.look='None'
    w=bpy.data.worlds.new("W"); sc.world=w; w.use_nodes=True
    w.node_tree.nodes["Background"].inputs[0].default_value=(0,0,0,1)
    cd=bpy.data.cameras.new("C"); cd.type='ORTHO'; cd.ortho_scale=ORTHO
    cam=bpy.data.objects.new("C",cd); sc.collection.objects.link(cam)
    cam.location=(0,-10,1.1); cam.rotation_euler=(math.radians(90),0,0); sc.camera=cam
    ld=bpy.data.lights.new("S",'SUN'); ld.energy=3.0
    lo=bpy.data.objects.new("S",ld); lo.rotation_euler=(math.radians(50),0,math.radians(35))
    sc.collection.objects.link(lo)
    return sc

def hull(ch, px, even=False, rim=False):
    ch.data.materials.append(omat())
    md=ch.modifiers.new("H",'SOLIDIFY'); md.thickness=px*PX; md.offset=1.0
    md.use_flip_normals=True; md.use_rim=rim
    md.material_offset=1; md.material_offset_rim=1
    if even: md.use_even_offset=True
    return md

def freestyle(sc, th):
    sc.render.use_freestyle=True
    vl=bpy.context.view_layer; vl.use_freestyle=True
    fss=vl.freestyle_settings
    ls=fss.linesets.new("O") if not len(fss.linesets) else fss.linesets[0]
    if ls.linestyle is None: ls.linestyle=bpy.data.linestyles.new("LS")
    ls.linestyle.thickness=th; ls.linestyle.color=(0,0,0)

CASES = {
 "hull_1.0":        dict(px=1.0),
 "hull_1.5":        dict(px=1.5),
 "hull_2.0":        dict(px=2.0),
 "hull_1.0_rim":    dict(px=1.0, rim=True),
 "hull_1.0_even":   dict(px=1.0, even=True),
 "hull_1.0_smooth": dict(px=1.0, smooth=True),
 "hull_1.5_smooth_rim": dict(px=1.5, smooth=True, rim=True),
 "fs_1.0":          dict(fs=1.0),
 "fs_1.5":          dict(fs=1.5),
}
R={}
for tag,cfg in CASES.items():
    sc=scene()
    ch=character(smooth=cfg.get("smooth",False))
    if "fs" in cfg: freestyle(sc, cfg["fs"])
    else: hull(ch, cfg["px"], even=cfg.get("even",False), rim=cfg.get("rim",False))
    outs={}
    bpy.ops.render.render(write_still=False)   # 워밍업
    t=time.time()
    for i in (0,2,5):
        ch.rotation_euler=(0,0,math.radians(45*i))
        bpy.context.view_layer.update()
        p=os.path.abspath("%s/%s_d%d.png"%(outdir,tag,i)); sc.render.filepath=p
        bpy.ops.render.render(write_still=True); outs[i]=p
    R[tag]={"pngs":outs,"sec_per_frame":round((time.time()-t)/3,4)}
print("SMOKE6C_JSON "+json.dumps(R))
