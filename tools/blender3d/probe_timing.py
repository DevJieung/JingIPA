# 실전 크기 타이밍 + 디더 A/B. 툰 구 하나를 여러 해상도로 렌더한다.
import sys, os, math, time
import bpy
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
outdir = argv[0]
os.makedirs(outdir, exist_ok=True)


def scene(engine, res, dither, samples=64):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = engine
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.film_transparent = True
    sc.render.filter_size = 0.0
    sc.render.dither_intensity = dither
    if engine == 'BLENDER_EEVEE':
        sc.eevee.taa_render_samples = samples
    if engine == 'CYCLES':
        sc.cycles.device = 'CPU'; sc.cycles.samples = samples; sc.cycles.use_denoising = False
    cd = bpy.data.cameras.new("C"); cd.type = 'ORTHO'; cd.ortho_scale = 2.6
    cam = bpy.data.objects.new("C", cd); cam.location = (0, -6, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.collection.objects.link(cam); sc.camera = cam
    ld = bpy.data.lights.new("S", 'SUN'); ld.energy = 4.0
    lo = bpy.data.objects.new("S", ld); lo.rotation_euler = (math.radians(50), 0, math.radians(35))
    sc.collection.objects.link(lo)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=32, ring_count=16)
    ob = bpy.context.object
    bpy.ops.object.shade_smooth()
    m = bpy.data.materials.new("Toon"); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = 'CONSTANT'
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0;  cr.elements[0].color = (0.12, 0.16, 0.38, 1)
    cr.elements[1].position = 0.35; cr.elements[1].color = (0.35, 0.48, 0.85, 1)
    cr.elements.new(0.70).color = (0.85, 0.92, 1.0, 1)
    emi = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(dif.outputs[0], s2r.inputs[0]); nt.links.new(s2r.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], emi.inputs[0]); nt.links.new(emi.outputs[0], out.inputs["Surface"])
    ob.data.materials.append(m)
    return sc


def go(engine, res, dither, name, samples=64):
    sc = scene(engine, res, dither, samples)
    sc.render.filepath = os.path.join(outdir, name)
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    print(f"TIME {name:32s} engine={engine:16s} res={res:4d} dither={dither} secs={time.time()-t0:.2f}")


go('BLENDER_EEVEE', 128, 1.0, "dither_on.png")
go('BLENDER_EEVEE', 128, 0.0, "dither_off.png")
go('BLENDER_EEVEE', 512, 0.0, "t_eevee_512.png")
go('BLENDER_EEVEE', 1024, 0.0, "t_eevee_1024.png")
go('CYCLES', 64, 0.0, "t_cycles_64.png", samples=16)
go('CYCLES', 512, 0.0, "t_cycles_512.png", samples=64)
go('BLENDER_WORKBENCH', 512, 0.0, "t_workbench_512.png")
print("TIME_DONE")
