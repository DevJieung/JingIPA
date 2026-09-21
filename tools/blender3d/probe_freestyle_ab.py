# Freestyle 이 실제로 선을 그리는지 A/B 로 잰다.
# 배경을 투명으로 두고(film_transparent) 「불투명한 거의-검정」 픽셀만 센다 —
# 배경이 검정이면 배경까지 세어져서 아무것도 증명 못 한다.
import sys, os, math
import bpy
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
outdir = argv[0]
os.makedirs(outdir, exist_ok=True)
RES = 128


def build(freestyle: bool, engine: str, name: str):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = engine
    sc.render.resolution_x = sc.render.resolution_y = RES
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.film_transparent = True
    sc.render.filter_size = 0.0
    sc.render.dither_intensity = 0.0      # ★ 도트에서는 디더를 꺼야 색이 안 번진다
    if engine == 'CYCLES':
        sc.cycles.device = 'CPU'
        sc.cycles.samples = 16
        sc.cycles.use_denoising = False   # ★ 우분투 빌드에 OIDN 이 없다
    cd = bpy.data.cameras.new("C"); cd.type = 'ORTHO'; cd.ortho_scale = 3.2
    cam = bpy.data.objects.new("C", cd); cam.location = (0, -6, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.collection.objects.link(cam); sc.camera = cam
    ld = bpy.data.lights.new("S", 'SUN'); ld.energy = 4.0
    lo = bpy.data.objects.new("S", ld); lo.rotation_euler = (math.radians(50), 0, math.radians(35))
    sc.collection.objects.link(lo)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=32, ring_count=16)
    bpy.ops.object.shade_smooth()
    bpy.ops.mesh.primitive_cube_add(size=1.1, location=(1.0, 0.5, -0.7))
    if freestyle:
        sc.render.use_freestyle = True
        vl = bpy.context.view_layer
        vl.use_freestyle = True
        fs = vl.freestyle_settings
        ls = fs.linesets[0] if len(fs.linesets) else fs.linesets.new("Outline")
        if ls.linestyle is None:
            ls.linestyle = bpy.data.linestyles.new("OutlineStyle")
        ls.select_silhouette = ls.select_border = ls.select_crease = True
        ls.linestyle.thickness = 3.0
        ls.linestyle.color = (0, 0, 0)
    sc.render.filepath = os.path.join(outdir, name)
    bpy.ops.render.render(write_still=True)
    print(f"AB_RENDER {name} freestyle={freestyle} engine={engine}")


build(False, 'BLENDER_EEVEE', "fs_off_eevee.png")
build(True,  'BLENDER_EEVEE', "fs_on_eevee.png")
build(False, 'CYCLES',        "fs_off_cycles.png")
build(True,  'CYCLES',        "fs_on_cycles.png")
print("AB_DONE")
