# 6-b — 「Freestyle 은 filter_size=0 을 무시한다」가 정말인가.
# 앞 단계 보고는 samples=16 에서 잰 것이다. samples=1 에서 다시 잰다.
# 덤으로 렌더 시간도 잰다 (Inverted Hull vs Freestyle vs 맨몸).
import sys, os, math, json, time
import bpy
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
outdir = argv[0]; os.makedirs(outdir, exist_ok=True)
RES, ORTHO = 96, 2.6
PX = ORTHO / RES
TONES = [(0.10,0.13,0.32),(0.35,0.48,0.82),(0.86,0.92,1.00)]

def toon():
    m=bpy.data.materials.new("T"); m.use_nodes=True; nt=m.node_tree; nt.nodes.clear()
    o=nt.nodes.new("ShaderNodeOutputMaterial"); d=nt.nodes.new("ShaderNodeBsdfDiffuse")
    s=nt.nodes.new("ShaderNodeShaderToRGB"); r=nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.interpolation='CONSTANT'; cr=r.color_ramp
    cr.elements[0].position=0.0; cr.elements[0].color=TONES[0]+(1,)
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

def scene(samples):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc=bpy.context.scene; sc.render.engine='BLENDER_EEVEE'
    sc.eevee.taa_render_samples=samples
    sc.render.resolution_x=sc.render.resolution_y=RES
    sc.render.image_settings.file_format='PNG'; sc.render.image_settings.color_mode='RGBA'
    sc.render.film_transparent=True; sc.render.filter_size=0.0; sc.render.dither_intensity=0.0
    sc.view_settings.view_transform='Standard'; sc.view_settings.look='None'
    w=bpy.data.worlds.new("W"); sc.world=w; w.use_nodes=True
    w.node_tree.nodes["Background"].inputs[0].default_value=(0,0,0,1)
    cd=bpy.data.cameras.new("C"); cd.type='ORTHO'; cd.ortho_scale=ORTHO
    cam=bpy.data.objects.new("C",cd); cam.location=(0,-8,0); cam.rotation_euler=(math.radians(90),0,0)
    sc.collection.objects.link(cam); sc.camera=cam
    ld=bpy.data.lights.new("S",'SUN'); ld.energy=3.0
    lo=bpy.data.objects.new("S",ld); lo.rotation_euler=(math.radians(55),0,math.radians(40))
    sc.collection.objects.link(lo)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.75,segments=32,ring_count=16,location=(-0.25,0,0.15))
    b=bpy.context.object; bpy.ops.object.shade_smooth()
    bpy.ops.mesh.primitive_cube_add(size=0.42,location=(0.55,0,-0.35))
    l=bpy.context.object; l.rotation_euler=(0,math.radians(18),0); l.scale=(1,1,2)
    return sc,[b,l]

def add_fs(sc, th=1.0):
    sc.render.use_freestyle=True
    vl=bpy.context.view_layer; vl.use_freestyle=True
    fss=vl.freestyle_settings
    ls=fss.linesets.new("O") if not len(fss.linesets) else fss.linesets[0]
    if ls.linestyle is None: ls.linestyle=bpy.data.linestyles.new("LS")
    ls.linestyle.thickness=th; ls.linestyle.color=(0,0,0)

def add_hull(objs, om, px=1.0):
    for o in objs:
        o.data.materials.append(om)
        md=o.modifiers.new("H",'SOLIDIFY'); md.thickness=px*PX; md.offset=1.0
        md.use_flip_normals=True; md.use_rim=False
        md.material_offset=1; md.material_offset_rim=1

R={}
for samples in (1, 16):
    for mode in ("plain","hull","freestyle"):
        sc,objs=scene(samples)
        tm=toon()
        for o in objs: o.data.materials.append(tm)
        if mode=="hull": add_hull(objs, omat(), 1.0)
        if mode=="freestyle": add_fs(sc, 1.0)
        p=os.path.abspath("%s/ab_%s_s%02d.png"%(outdir,mode,samples))
        sc.render.filepath=p
        bpy.ops.render.render(write_still=True)   # 워밍업 (첫 렌더는 컨텍스트 비용)
        t=time.time()
        for _ in range(5): bpy.ops.render.render(write_still=True)
        R["%s_s%d"%(mode,samples)]={"png":p,"sec_per_frame":round((time.time()-t)/5,4)}
print("SMOKE6B_JSON "+json.dumps(R))
