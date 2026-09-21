# 5-b — 「딱 3톤」을 막는 것이 무엇인가. filter_size=0 인데도 색이 9개 나왔다.
# 가설: 픽셀 **안에서** TAA 표본 여러 개가 밴드 경계를 걸쳐 평균되어 중간색이 생긴다.
# 그렇다면 taa_render_samples 를 줄이면 색 수가 줄어야 한다.
import sys, os, math, json
import bpy
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
outdir = argv[0]; os.makedirs(outdir, exist_ok=True)
TONES = [(0.10, 0.13, 0.32), (0.35, 0.48, 0.82), (0.86, 0.92, 1.00)]

def run(samples, res=96):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.eevee.taa_render_samples = samples
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.film_transparent = True
    sc.render.filter_size = 0.0
    sc.render.dither_intensity = 0.0
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0, 0, 0, 1)
    cd = bpy.data.cameras.new("C"); cd.type = 'ORTHO'; cd.ortho_scale = 2.6
    cam = bpy.data.objects.new("C", cd); cam.location = (0, -8, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.collection.objects.link(cam); sc.camera = cam
    ld = bpy.data.lights.new("S", 'SUN'); ld.energy = 3.0
    lo = bpy.data.objects.new("S", ld); lo.rotation_euler = (math.radians(55), 0, math.radians(40))
    sc.collection.objects.link(lo)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=48, ring_count=24)
    bpy.ops.object.shade_smooth()
    m = bpy.data.materials.new("T"); m.use_nodes = True
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
    bpy.context.object.data.materials.append(m)
    p = os.path.abspath("%s/samples_%02d.png" % (outdir, samples))
    sc.render.filepath = p
    bpy.ops.render.render(write_still=True)
    return p

R = {}
for s in (1, 2, 4, 16, 64):
    R[s] = run(s)
print("SMOKE5B_JSON " + json.dumps(R))
