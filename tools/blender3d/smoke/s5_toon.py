# 5번 — 툰. Shader to RGB → ColorRamp(CONSTANT) 로 **딱 3톤**이 나오는가.
# 그리고 뷰 변환(AgX vs Standard)이 색을 얼마나 비트는가 — 팔레트를 맞추려면 이게 관건이다.
import sys, os, math, json
import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
outdir = argv[0] if argv else "build/b3d/smoke/s5"
os.makedirs(outdir, exist_ok=True)

# 3톤 — 선형 색. Standard 뷰 변환이면 sRGB 로 인코딩된 값이 PNG 에 그대로 찍혀야 한다.
TONES = [(0.10, 0.13, 0.32), (0.35, 0.48, 0.82), (0.86, 0.92, 1.00)]

def toon_mat(name="Toon"):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = 'CONSTANT'
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0;  cr.elements[0].color = TONES[0] + (1,)
    cr.elements[1].position = 0.28; cr.elements[1].color = TONES[1] + (1,)
    cr.elements.new(0.62).color = TONES[2] + (1,)
    emi = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], emi.inputs[0])
    nt.links.new(emi.outputs[0], out.inputs["Surface"])
    return m

def build(engine, view_transform, res=96):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = engine
    if engine == 'CYCLES':
        sc.cycles.use_denoising = False      # 우분투 빌드에 OIDN 이 없다
        sc.cycles.samples = 32
        sc.cycles.device = 'CPU'
    else:
        sc.eevee.taa_render_samples = 16
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.film_transparent = True
    sc.render.filter_size = 0.0
    sc.render.dither_intensity = 0.0
    sc.view_settings.view_transform = view_transform
    sc.view_settings.look = 'None'
    # 월드를 새까맣게 — 앰비언트가 섞이면 밴드가 흐려진다
    w = bpy.data.worlds.new("W"); sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0, 0, 0, 1)
    cd = bpy.data.cameras.new("C"); cd.type = 'ORTHO'; cd.ortho_scale = 2.6
    cam = bpy.data.objects.new("C", cd); cam.location = (0, -8, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.collection.objects.link(cam); sc.camera = cam
    ld = bpy.data.lights.new("S", 'SUN'); ld.energy = 3.0
    lo = bpy.data.objects.new("S", ld)
    lo.rotation_euler = (math.radians(55), 0, math.radians(40))
    sc.collection.objects.link(lo)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=48, ring_count=24)
    bpy.ops.object.shade_smooth()
    bpy.context.object.data.materials.append(toon_mat())
    return sc

R = {"tones_linear": TONES}
for tag, eng, vt in (("eevee_agx", 'BLENDER_EEVEE', 'AgX'),
                     ("eevee_standard", 'BLENDER_EEVEE', 'Standard'),
                     ("cycles_standard", 'CYCLES', 'Standard')):
    sc = build(eng, vt)
    p = os.path.abspath("%s/%s.png" % (outdir, tag))
    sc.render.filepath = p
    bpy.ops.render.render(write_still=True)
    R[tag] = p

# 선형 -> sRGB 8bit 로 손으로 바꿔 본 기대값 (Standard 뷰 변환의 기대치)
def lin2srgb(c):
    return round(255 * (12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055))
R["expect_srgb"] = [[lin2srgb(c) for c in t] for t in TONES]
print("SMOKE5_JSON " + json.dumps(R))
