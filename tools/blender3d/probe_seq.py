# 실전에 가까운 한 판: 툰 머티리얼 + Freestyle + 알파 + filter 0 으로
# 96x96 스프라이트 프레임 여러 장을 애니메이션으로 뽑는다. 처리량을 잰다.
import sys, os, math, time
import bpy
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
outdir = argv[0]; os.makedirs(outdir, exist_ok=True)
FRAMES = int(argv[1]) if len(argv) > 1 else 8
RES = int(argv[2]) if len(argv) > 2 else 96

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = sc.render.resolution_y = RES
sc.render.resolution_percentage = 100
sc.render.image_settings.file_format = 'PNG'
sc.render.image_settings.color_mode = 'RGBA'
sc.render.film_transparent = True
sc.render.filter_size = 0.0
sc.render.dither_intensity = 0.0
sc.eevee.taa_render_samples = 32

cd = bpy.data.cameras.new("C"); cd.type = 'ORTHO'; cd.ortho_scale = 3.4
cam = bpy.data.objects.new("C", cd); cam.location = (0, -8, 0.4)
cam.rotation_euler = (math.radians(90), 0, 0)
sc.collection.objects.link(cam); sc.camera = cam
ld = bpy.data.lights.new("S", 'SUN'); ld.energy = 4.0
lo = bpy.data.objects.new("S", ld); lo.rotation_euler = (math.radians(50), 0, math.radians(35))
sc.collection.objects.link(lo)

# 몸통(구) + 팔(원기둥) — 팔을 회전시켜 「휘두르는」 동작을 만든다
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.9, segments=24, ring_count=12)
body = bpy.context.object; bpy.ops.object.shade_smooth()
bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=1.6, location=(0.9, 0, 0.2))
arm = bpy.context.object
arm.rotation_euler = (0, math.radians(60), 0)

m = bpy.data.materials.new("Toon"); m.use_nodes = True
nt = m.node_tree; nt.nodes.clear()
out = nt.nodes.new("ShaderNodeOutputMaterial"); dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
s2r = nt.nodes.new("ShaderNodeShaderToRGB"); ramp = nt.nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.interpolation = 'CONSTANT'
cr = ramp.color_ramp
cr.elements[0].position = 0.0;  cr.elements[0].color = (0.15, 0.20, 0.45, 1)
cr.elements[1].position = 0.35; cr.elements[1].color = (0.38, 0.52, 0.88, 1)
cr.elements.new(0.70).color = (0.88, 0.94, 1.0, 1)
emi = nt.nodes.new("ShaderNodeEmission")
nt.links.new(dif.outputs[0], s2r.inputs[0]); nt.links.new(s2r.outputs[0], ramp.inputs[0])
nt.links.new(ramp.outputs[0], emi.inputs[0]); nt.links.new(emi.outputs[0], out.inputs["Surface"])
for o in (body, arm):
    o.data.materials.append(m)

# 키프레임 — 팔을 60도에서 -40도로
arm.rotation_euler = (0, math.radians(60), 0); arm.keyframe_insert("rotation_euler", frame=1)
arm.rotation_euler = (0, math.radians(-40), 0); arm.keyframe_insert("rotation_euler", frame=FRAMES)

sc.render.use_freestyle = True
vl = bpy.context.view_layer; vl.use_freestyle = True
fs = vl.freestyle_settings
ls = fs.linesets[0] if len(fs.linesets) else fs.linesets.new("Outline")
if ls.linestyle is None:
    ls.linestyle = bpy.data.linestyles.new("OutlineStyle")
ls.select_silhouette = ls.select_border = ls.select_crease = True
ls.linestyle.thickness = 1.5; ls.linestyle.color = (0.05, 0.03, 0.08)

sc.frame_start = 1; sc.frame_end = FRAMES
sc.render.filepath = os.path.join(outdir, "f_")
t0 = time.time()
bpy.ops.render.render(animation=True)
dt = time.time() - t0
print(f"SEQ_OK frames={FRAMES} res={RES} total={dt:.2f}s per_frame={dt/FRAMES:.3f}s")
