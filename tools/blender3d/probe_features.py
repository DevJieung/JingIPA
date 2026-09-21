# 툰 스프라이트 파이프라인이 실제로 기대는 네 기능을 하나씩 렌더해서 확인한다.
#   (a) Shader to RGB + ColorRamp(CONSTANT)  = 툰 밴딩
#   (b) Freestyle                            = 외곽선
#   (c) film_transparent                     = 알파 PNG
#   (d) filter_size = 0                      = 안티에일리어싱 끄기(도트용)
# 쓰기: bl -b --factory-startup --python probe_features.py -- <outdir>
import sys, os, math, time
import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
outdir = argv[0] if argv else "/tmp/b3d"
os.makedirs(outdir, exist_ok=True)

RES = 128


def fresh():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.resolution_x = RES
    sc.render.resolution_y = RES
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    # 카메라
    cam_d = bpy.data.cameras.new("Cam")
    cam_d.type = 'ORTHO'          # ★ 직교 투영 — 스프라이트의 전제
    cam_d.ortho_scale = 3.0
    cam = bpy.data.objects.new("Cam", cam_d)
    cam.location = (0, -6, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.collection.objects.link(cam)
    sc.camera = cam
    # 광원
    lt = bpy.data.lights.new("Sun", 'SUN')
    lt.energy = 4.0
    lo = bpy.data.objects.new("Sun", lt)
    lo.location = (3, -3, 4)
    lo.rotation_euler = (math.radians(50), 0, math.radians(35))
    sc.collection.objects.link(lo)
    return sc


def add_sphere():
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=32, ring_count=16)
    ob = bpy.context.object
    bpy.ops.object.shade_smooth()
    return ob


def toon_material(ob):
    """Diffuse -> Shader to RGB -> ColorRamp(CONSTANT) -> Emission. EEVEE 전용 경로."""
    m = bpy.data.materials.new("Toon")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    dif.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")     # ★ EEVEE 전용
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = 'CONSTANT'       # ★ 하드 밴딩
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0
    cr.elements[0].color = (0.12, 0.16, 0.38, 1)
    cr.elements[1].position = 0.35
    cr.elements[1].color = (0.35, 0.48, 0.85, 1)
    e2 = cr.elements.new(0.70)
    e2.color = (0.85, 0.92, 1.0, 1)
    emi = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], emi.inputs[0])
    nt.links.new(emi.outputs[0], out.inputs["Surface"])
    ob.data.materials.append(m)
    return m


def freestyle_lineset(vl, name="Outline"):
    """★ 빈 파일에서 linesets.new() 는 linestyle 이 None 이다 — 직접 만들어 붙인다."""
    fs = vl.freestyle_settings
    ls = fs.linesets[0] if len(fs.linesets) else fs.linesets.new(name)
    if ls.linestyle is None:
        ls.linestyle = bpy.data.linestyles.new(name + "Style")
    return ls, fs


def render(sc, name):
    p = os.path.join(outdir, name)
    sc.render.filepath = p
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    print(f"FEAT_RENDER {name} secs={time.time()-t0:.2f}")
    return p


# ---------------------------------------------------------------- (a) toon
sc = fresh()
sc.render.engine = 'BLENDER_EEVEE'
ob = add_sphere()
try:
    toon_material(ob)
    print("FEAT_A_NODES ok (ShaderNodeShaderToRGB + ValToRGB CONSTANT)")
except Exception as e:
    print("FEAT_A_NODES FAIL", e)
render(sc, "a_shader_to_rgb.png")

# ---------------------------------------------------------------- (b) freestyle
sc = fresh()
sc.render.engine = 'BLENDER_EEVEE'
ob = add_sphere()
bpy.ops.mesh.primitive_cube_add(size=1.2, location=(1.1, 0.6, -0.6))
sc.render.use_freestyle = True
vl = bpy.context.view_layer
vl.use_freestyle = True
fs = vl.freestyle_settings
fs.as_render_pass = False
ls, fs = freestyle_lineset(vl)
ls.select_silhouette = True
ls.select_border = True
ls.select_crease = True
lst = ls.linestyle
lst.thickness = 3.0
lst.color = (0, 0, 0)
print(f"FEAT_B_FREESTYLE use_freestyle={sc.render.use_freestyle} linesets={len(fs.linesets)} thickness={lst.thickness}")
render(sc, "b_freestyle.png")

# ---------------------------------------------------------------- (c) alpha
sc = fresh()
sc.render.engine = 'BLENDER_EEVEE'
ob = add_sphere()
toon_material(ob)
sc.render.film_transparent = True
print(f"FEAT_C_ALPHA film_transparent={sc.render.film_transparent}")
render(sc, "c_alpha.png")

# ---------------------------------------------------------------- (d) filter_size
for fsz, nm in ((1.5, "d_filter_1p5.png"), (0.0, "d_filter_0.png")):
    sc = fresh()
    sc.render.engine = 'BLENDER_EEVEE'
    ob = add_sphere()
    toon_material(ob)
    sc.render.film_transparent = True
    sc.render.filter_size = fsz
    print(f"FEAT_D_FILTER asked={fsz} got={sc.render.filter_size}")
    render(sc, nm)

# ---------------------------------------------------------------- Cycles 대조군
sc = fresh()
sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = 32
# ★ 우분투 blender 4.0.2 는 OpenImageDenoise 없이 빌드돼 있다 — 켜 두면 렌더가 통째로 실패한다.
sc.cycles.use_denoising = False
ob = add_sphere()
sc.render.film_transparent = True
sc.render.use_freestyle = True
bpy.context.view_layer.use_freestyle = True
ls, fs = freestyle_lineset(bpy.context.view_layer)
ls.linestyle.thickness = 3.0
ls.linestyle.color = (0, 0, 0)
render(sc, "e_cycles_freestyle_alpha.png")
print("FEAT_DONE")
