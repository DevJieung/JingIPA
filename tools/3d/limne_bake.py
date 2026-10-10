"""Bake real high surface albedo/ORM/normal onto the reduced game UV atlas."""
import bpy
from pathlib import Path


def bake_surface(target, high_mesh, directory):
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=True)
    source=bpy.data.objects.new('Limne_high_bake_source',high_mesh)
    bpy.context.collection.objects.link(source)
    source_indices=[f.material_index for f in source.data.polygons]
    source.data.materials.clear()
    original_materials=list(target.data.materials)
    for m in original_materials:source.data.materials.append(m.copy())
    for i,f in enumerate(source.data.polygons):f.material_index=source_indices[i]
    bpy.ops.object.select_all(action='DESELECT');target.select_set(True)
    bpy.context.view_layer.objects.active=target
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=.70,island_margin=.003,area_weight=.3)
    bpy.ops.object.mode_set(mode='OBJECT')
    material=bpy.data.materials.new('Limne_baked_mobile_surface');material.use_nodes=True
    target.data.materials.clear();target.data.materials.append(material)
    for face in target.data.polygons:face.material_index=0
    nodes=material.node_tree.nodes;links=material.node_tree.links
    tex=nodes.new('ShaderNodeTexImage');nodes.active=tex
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU'
    scene.cycles.use_denoising=False
    bpy.context.view_layer.cycles.use_denoising=False
    scene.cycles.samples=4
    scene.render.bake.use_selected_to_active=True
    scene.render.bake.cage_extrusion=.021;scene.render.bake.max_ray_distance=.065
    scene.render.bake.margin=12;scene.render.bake.use_clear=True
    # Keep references to the original input sockets before changing output shaders.
    shaders=[]
    for m in source.data.materials:
        p=m.node_tree.nodes.get('Principled BSDF');output=m.node_tree.nodes.get('Material Output')
        emit=m.node_tree.nodes.new('ShaderNodeEmission');emit.inputs['Strength'].default_value=1
        m.node_tree.links.new(emit.outputs[0],output.inputs['Surface'])
        shaders.append((m,p,emit))
    images={}
    for channel,size in [('Albedo',2048),('ORM',2048),('Normal',1024)]:
        image=bpy.data.images.new('Limne_'+channel,size,size,alpha=False)
        image.colorspace_settings.name='sRGB' if channel=='Albedo' else 'Non-Color'
        tex.image=image
        if channel!='Normal':
            for m,p,emit in shaders:
                tree=m.node_tree
                for link in list(emit.inputs['Color'].links):tree.links.remove(link)
                if channel=='Albedo':
                    inp=p.inputs['Base Color']
                    if inp.links:tree.links.new(inp.links[0].from_socket,emit.inputs['Color'])
                    else:emit.inputs['Color'].default_value=inp.default_value
                else:
                    combine=tree.nodes.new('ShaderNodeCombineColor');combine.mode='RGB'
                    combine.inputs['Red'].default_value=1
                    for dst,src in [('Green','Roughness'),('Blue','Metallic')]:
                        inp=p.inputs[src]
                        if inp.links:tree.links.new(inp.links[0].from_socket,combine.inputs[dst])
                        else:combine.inputs[dst].default_value=inp.default_value
                    tree.links.new(combine.outputs[0],emit.inputs['Color'])
        bpy.ops.object.select_all(action='DESELECT');source.select_set(True);target.select_set(True)
        bpy.context.view_layer.objects.active=target
        bpy.ops.object.bake(type='NORMAL' if channel=='Normal' else 'EMIT')
        image.filepath_raw=str(directory/(channel.lower()+'.png'));image.file_format='PNG';image.save()
        images[channel]=image
        print('LIMNE_BAKE',channel,image.filepath_raw,flush=True)
    source_data=source.data;bpy.data.objects.remove(source,do_unlink=True)
    bpy.data.meshes.remove(source_data)
    p=nodes.get('Principled BSDF');tex.image=images['Albedo'];links.new(tex.outputs['Color'],p.inputs['Base Color'])
    orm=nodes.new('ShaderNodeTexImage');orm.image=images['ORM']
    separate=nodes.new('ShaderNodeSeparateColor');separate.mode='RGB'
    links.new(orm.outputs['Color'],separate.inputs[0])
    links.new(separate.outputs['Green'],p.inputs['Roughness']);links.new(separate.outputs['Blue'],p.inputs['Metallic'])
    norm=nodes.new('ShaderNodeTexImage');norm.image=images['Normal']
    normal=nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.70
    links.new(norm.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs[0],p.inputs['Normal'])
    # Complexion is now baked into albedo, so COLOR_0 must not multiply it again.
    for color in list(target.data.color_attributes):target.data.color_attributes.remove(color)
    target.data.update();target.data.calc_loop_triangles()
    scene.render.bake.use_selected_to_active=False
    return images
