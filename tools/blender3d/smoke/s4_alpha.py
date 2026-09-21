# 4번 — 규격. 96x96 · filter_size=0 · film_transparent=True 로
# **반투명 가장자리가 하나도 없는** PNG 가 나오는가.
# 대각선 모서리가 있어야 안티에일리어싱이 있으면 반드시 드러나므로 큐브를 비스듬히 돌려 놓는다.
import sys, os, math, json
import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
outdir = argv[0] if argv else "build/b3d/smoke/s4"
os.makedirs(outdir, exist_ok=True)

def scene(filter_size, freestyle, samples=16):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x = sc.render.resolution_y = 96
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.film_transparent = True
    sc.render.filter_size = filter_size
    sc.render.dither_intensity = 0.0
    sc.eevee.taa_render_samples = samples
    cd = bpy.data.cameras.new("C"); cd.type = 'ORTHO'; cd.ortho_scale = 4.0
    cam = bpy.data.objects.new("C", cd); cam.location = (0, -8, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.collection.objects.link(cam); sc.camera = cam
    ld = bpy.data.lights.new("S", 'SUN'); ld.energy = 4.0
    lo = bpy.data.objects.new("S", ld)
    lo.rotation_euler = (math.radians(50), 0, math.radians(35))
    sc.collection.objects.link(lo)
    # 대각선 모서리를 만들려고 비스듬히 돌린 큐브 + 구
    bpy.ops.mesh.primitive_cube_add(size=1.6, location=(-0.7, 0, 0))
    bpy.context.object.rotation_euler = (0, math.radians(27), math.radians(19))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.85, location=(0.9, 0, 0), segments=20, ring_count=10)
    bpy.ops.object.shade_smooth()
    if freestyle:
        sc.render.use_freestyle = True
        vl = bpy.context.view_layer; vl.use_freestyle = True
        fs = vl.freestyle_settings
        ls = fs.linesets.new("Outline") if not len(fs.linesets) else fs.linesets[0]
        if ls.linestyle is None:
            ls.linestyle = bpy.data.linestyles.new("LS")
        ls.linestyle.thickness = 1.0
        ls.linestyle.color = (0, 0, 0)
    return sc

R = {}
for name, fsz, fst in (("filter0_nofs", 0.0, False),
                       ("filter1p5_nofs", 1.5, False),
                       ("filter0_fs", 0.0, True)):
    sc = scene(fsz, fst)
    p = os.path.abspath("%s/%s.png" % (outdir, name))
    sc.render.filepath = p
    bpy.ops.render.render(write_still=True)
    R[name] = p
print("SMOKE4_JSON " + json.dumps(R))
