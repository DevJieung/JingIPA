# Blender 헤드리스 렌더 점검용. `bl -b --factory-startup --python probe_render.py -- <engine> <out.png>`
import sys, time, os
import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
engine = argv[0] if argv else "CYCLES"
out = argv[1] if len(argv) > 1 else "/tmp/probe.png"
res = int(argv[2]) if len(argv) > 2 else 64

sc = bpy.context.scene
sc.render.engine = engine
sc.render.resolution_x = res
sc.render.resolution_y = res
sc.render.resolution_percentage = 100
sc.render.image_settings.file_format = 'PNG'
sc.render.image_settings.color_mode = 'RGBA'
sc.render.filepath = out

if engine == "CYCLES":
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 16
    sc.cycles.use_denoising = False

t0 = time.time()
bpy.ops.render.render(write_still=True)
dt = time.time() - t0
print(f"PROBE_OK engine={engine} res={res} secs={dt:.2f} out={out}")
