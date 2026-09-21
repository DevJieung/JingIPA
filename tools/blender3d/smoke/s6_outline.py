# 6번 — 아웃라인. (a) Inverted Hull(Solidify + 노멀 뒤집기 + 백페이스 컬링)
#                (b) Freestyle
# 96x96 에서 어느 쪽이 1px 로 또렷하게 나오는가. 두께 숫자를 실측으로 뽑는다.
import sys, os, math, json
import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
outdir = argv[0]; os.makedirs(outdir, exist_ok=True)
RES = 96
ORTHO = 2.6                       # px/유닛 = 96/2.6 = 36.923
PX = ORTHO / RES                  # 1픽셀이 몇 월드 유닛인가 = 0.027083

TONES = [(0.10, 0.13, 0.32), (0.35, 0.48, 0.82), (0.86, 0.92, 1.00)]

def toon_mat():
    m = bpy.data.materials.new("Toon"); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    s2r = nt.nodes.new("ShaderNodeShaderToRGB"); ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = 'CONSTANT'; cr = ramp.color_ramp
    cr.elements[0].position = 0.0;  cr.elements[0].color = TONES[0] + (1,)
    cr.elements[1].position = 0.28; cr.elements[1].color = TONES[1] + (1,)
    cr.elements.new(0.62).color = TONES[2] + (1,)
    emi = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(dif.outputs[0], s2r.inputs[0]); nt.links.new(s2r.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], emi.inputs[0]); nt.links.new(emi.outputs[0], out.inputs["Surface"])
    return m

def outline_mat():
    """새까만 Emission + 백페이스 컬링. 컬링이 없으면 껍데기가 캐릭터를 통째로 덮는다."""
    m = bpy.data.materials.new("Outline"); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); emi = nt.nodes.new("ShaderNodeEmission")
    emi.inputs[0].default_value = (0, 0, 0, 1)
    nt.links.new(emi.outputs[0], out.inputs["Surface"])
    m.use_backface_culling = True
    return m

def base_scene(samples=1):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.eevee.taa_render_samples = samples
    sc.render.resolution_x = sc.render.resolution_y = RES
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.film_transparent = True
    sc.render.filter_size = 0.0
    sc.render.dither_intensity = 0.0
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0, 0, 0, 1)
    cd = bpy.data.cameras.new("C"); cd.type = 'ORTHO'; cd.ortho_scale = ORTHO
    cam = bpy.data.objects.new("C", cd); cam.location = (0, -8, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.collection.objects.link(cam); sc.camera = cam
    ld = bpy.data.lights.new("S", 'SUN'); ld.energy = 3.0
    lo = bpy.data.objects.new("S", ld); lo.rotation_euler = (math.radians(55), 0, math.radians(40))
    sc.collection.objects.link(lo)
    # 몸통(구) + 팔(상자) — 곡면과 평면 모서리를 둘 다 본다
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.75, segments=32, ring_count=16, location=(-0.25, 0, 0.15))
    body = bpy.context.object; bpy.ops.object.shade_smooth()
    bpy.ops.mesh.primitive_cube_add(size=0.42, location=(0.55, 0, -0.35))
    limb = bpy.context.object
    limb.rotation_euler = (0, math.radians(18), 0)
    limb.scale = (1.0, 1.0, 2.0)
    return sc, [body, limb]

R = {"px_per_unit": RES / ORTHO, "one_px_in_units": PX}

# ---------- (a) Inverted Hull : 두께를 픽셀 단위로 걸어 본다 ----------
hull = {}
for px_want in (0.5, 1.0, 1.5, 2.0, 3.0):
    sc, objs = base_scene(samples=1)
    tm, om = toon_mat(), outline_mat()
    for o in objs:
        o.data.materials.append(tm)
        o.data.materials.append(om)
        md = o.modifiers.new("Hull", 'SOLIDIFY')
        md.thickness = px_want * PX
        md.offset = 1.0                 # 바깥으로만 부풀린다
        md.use_flip_normals = True      # 껍데기 노멀을 뒤집는다
        md.use_rim = False
        md.material_offset = 1          # 껍데기는 슬롯 1(검정)
        md.material_offset_rim = 1
    p = os.path.abspath("%s/hull_%0.1fpx.png" % (outdir, px_want))
    sc.render.filepath = p
    bpy.ops.render.render(write_still=True)
    hull[px_want] = p
R["hull"] = hull

# 껍데기 없는 기준판 (실루엣만)
sc, objs = base_scene(samples=1)
tm = toon_mat()
for o in objs: o.data.materials.append(tm)
p = os.path.abspath("%s/plain.png" % outdir); sc.render.filepath = p
bpy.ops.render.render(write_still=True)
R["plain"] = p

# ---------- (b) Freestyle : thickness 를 픽셀 단위로 걸어 본다 ----------
fs = {}
for th in (0.5, 1.0, 1.5, 2.0, 3.0):
    sc, objs = base_scene(samples=1)
    tm = toon_mat()
    for o in objs: o.data.materials.append(tm)
    sc.render.use_freestyle = True
    vl = bpy.context.view_layer; vl.use_freestyle = True
    fss = vl.freestyle_settings
    ls = fss.linesets.new("Outline") if not len(fss.linesets) else fss.linesets[0]
    if ls.linestyle is None:
        ls.linestyle = bpy.data.linestyles.new("LS")
    ls.linestyle.thickness = th
    ls.linestyle.color = (0, 0, 0)
    ls.select_silhouette = True
    ls.select_border = True
    ls.select_crease = True
    p = os.path.abspath("%s/fs_%0.1fpx.png" % (outdir, th))
    sc.render.filepath = p
    bpy.ops.render.render(write_still=True)
    fs[th] = p
    if th == 1.0:
        R["fs_lineset"] = {"silhouette": ls.select_silhouette, "border": ls.select_border,
                           "crease": ls.select_crease, "crease_angle_deg": round(math.degrees(fss.crease_angle), 1)}
R["freestyle"] = fs
print("SMOKE6_JSON " + json.dumps(R))
