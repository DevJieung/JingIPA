# 7-b — 「월드 1유닛 = 정수 픽셀」을 자로 재서 증명한다.
# 정확히 1.0 x 1.0 유닛짜리 판을 정면으로 놓고 렌더해서 불투명 픽셀 폭을 센다.
#   px_per_unit = RES / ortho_scale  → ortho_scale = RES / k (k 정수) 여야 딱 떨어진다.
import sys, os, math, json
import bpy
argv=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
outdir=argv[0]; os.makedirs(outdir,exist_ok=True)
RES=96

def run(ortho, size, tag):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc=bpy.context.scene; sc.render.engine='BLENDER_EEVEE'; sc.eevee.taa_render_samples=1
    sc.render.resolution_x=sc.render.resolution_y=RES; sc.render.resolution_percentage=100
    sc.render.image_settings.file_format='PNG'; sc.render.image_settings.color_mode='RGBA'
    sc.render.film_transparent=True; sc.render.filter_size=0.0; sc.render.dither_intensity=0.0
    sc.view_settings.view_transform='Standard'
    cd=bpy.data.cameras.new("C"); cd.type='ORTHO'; cd.ortho_scale=ortho
    cam=bpy.data.objects.new("C",cd); cam.location=(0,-8,0)
    cam.rotation_euler=(math.radians(90),0,0)
    sc.collection.objects.link(cam); sc.camera=cam
    # 정확히 size x size 유닛짜리 평면, 카메라 정면. 자체발광이라 빛이 필요없다
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0,0,0))
    pl=bpy.context.object; pl.rotation_euler=(math.radians(90),0,0)
    m=bpy.data.materials.new("E"); m.use_nodes=True; nt=m.node_tree; nt.nodes.clear()
    o=nt.nodes.new("ShaderNodeOutputMaterial"); e=nt.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value=(1,1,1,1); nt.links.new(e.outputs[0],o.inputs["Surface"])
    pl.data.materials.append(m)
    p=os.path.abspath("%s/ruler_%s.png"%(outdir,tag)); sc.render.filepath=p
    bpy.ops.render.render(write_still=True)
    return {"png":p,"ortho":ortho,"size":size,"px_per_unit":RES/ortho,
            "expect_px":size*RES/ortho}

R={}
for ortho,k in ((3.0,32),(2.0,48),(1.5,64),(2.6,None),(2.5,None)):
    for size in (1.0,2.0):
        if size>ortho: continue
        R["o%.2f_s%.1f"%(ortho,size)]=run(ortho,size,"o%.2f_s%.1f"%(ortho,size))
print("SMOKE7B_JSON "+json.dumps(R))
