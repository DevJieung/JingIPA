"""Blender finishing of the real reconstructed character surface.

The hair, clothes and body retain the real image-to-3D surface. The face and
neck are authored as one continuous Hermite surface fitted to its proportions.
Eyes, lids, machinery and connected hoses are authored Blender mesh finishing.
No scene/camera or battle state is owned here.
"""
import bpy
import bmesh
import math
import numpy as np
from mathutils import Vector


def material(name, color, roughness=.4, metal=0, alpha=1):
    m=bpy.data.materials.new(name);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,alpha)
    p.inputs['Roughness'].default_value=roughness
    p.inputs['Metallic'].default_value=metal
    p.inputs['Alpha'].default_value=alpha
    if alpha<1:
        m.blend_method='BLEND';m.use_screen_refraction=True
        m.show_transparent_back=False
    return m


def mesh(name, vertices, faces, mat, control='Body'):
    data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.update()
    ob=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(ob)
    data.materials.append(mat)
    for p in data.polygons:p.use_smooth=True
    if mat.name=='Skin_soft_warm_volume':
        col=data.color_attributes.new(name='SkinComplexion',type='FLOAT_COLOR',domain='CORNER')
        for v in col.data:v.color=(.59,.345,.245,1)
    ob['limne_control']=control
    return ob


def lathe(name, profile, mat, center, control='Body', sides=64):
    """Machined axial profile: axial distances/radii, axis along Blender +Y."""
    verts=[];faces=[]
    for y,r in profile:
        for j in range(sides):
            t=math.tau*j/sides
            verts.append((center[0]+r*math.cos(t),center[1]+y,center[2]+r*math.sin(t)))
    for i in range(len(profile)-1):
        for j in range(sides):
            k=i*sides+j;l=i*sides+(j+1)%sides
            faces.append((k,l,l+sides,k+sides))
    return mesh(name,verts,faces,mat,control)


def tube(name, points, radius, mat, control='Body', sides=8):
    verts=[];faces=[]
    points=[Vector(p) for p in points]
    for i,p in enumerate(points):
        d=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
        right=d.cross(Vector((0,0,1)))
        if right.length<.01:right=d.cross(Vector((1,0,0)))
        right.normalize();up=right.cross(d).normalized()
        for j in range(sides):
            t=math.tau*j/sides
            rad=radius[i] if isinstance(radius,list) else radius
            verts.append(tuple(p+rad*(math.cos(t)*right+math.sin(t)*up)))
    for i in range(len(points)-1):
        for j in range(sides):
            a=i*sides+j;b=i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    return mesh(name,verts,faces,mat,control)


def face_finish(o):
    """Select actual reconstructed face/hair with the retained source atlas."""
    mat=o.data.materials[0]
    images=[n.image for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and n.image
            and n.image.colorspace_settings.name=='sRGB']
    if not images:raise RuntimeError('Expected actual TRELLIS base-color atlas')
    image=images[0];w,h=image.size
    pixels=np.asarray(image.pixels[:],dtype=np.float32).reshape(h,w,4)
    orm_images=[n.image for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and n.image
                and n.image.colorspace_settings.name=='Non-Color']
    orm=np.asarray(orm_images[0].pixels[:],dtype=np.float32).reshape(h,w,4)
    # Adding a color attribute reallocates CustomData. Copy UV coordinates
    # first; a retained RNA UV-data view would then read the new color layer.
    uv=np.asarray([d.uv[:] for d in o.data.uv_layers.active.data],dtype=np.float32)
    skin=material('Skin_soft_warm_volume',(.59,.345,.245),.45)
    skin.node_tree.nodes['Principled BSDF'].inputs['Subsurface Weight'].default_value=.055
    hair=material('Navy_bob_coherent_clumps',(.012,.033,.064),.49)
    hair.node_tree.nodes['Principled BSDF'].inputs['Specular IOR Level'].default_value=.26
    sk_index=len(o.data.materials);o.data.materials.append(skin)
    hair_index=len(o.data.materials);o.data.materials.append(hair)
    repair_indices={}
    for name,col,rough in [('Cobalt_seam_repair',(.025,.145,.265),.63),
                           ('Teal_apron_seam_repair',(.012,.18,.21),.65),
                           ('Navy_work_pants_repair',(.006,.029,.063),.65),
                           ('Harness_seam_repair',(.022,.031,.035),.54)]:
        repair_indices[name]=len(o.data.materials)
        o.data.materials.append(material(name,col,rough))
    skin_vertices=set();hair_vertices=set();remove=set()
    # Face corners retain soft blush through vertex colour, not flat cheek discs.
    color=o.data.color_attributes.new(name='SkinComplexion',type='FLOAT_COLOR',domain='CORNER')
    for datum in color.data:datum.color=(1,1,1,1)
    for face in o.data.polygons:
        pos=sum((o.data.vertices[v].co for v in face.vertices),Vector())/len(face.vertices)
        u=np.mean(uv[list(face.loop_indices)],axis=0)
        c=pixels[max(0,min(h-1,int(u[1]*h))),max(0,min(w-1,int(u[0]*w))),:3]
        mr=orm[max(0,min(h-1,int(u[1]*h))),max(0,min(w-1,int(u[0]*w))),:3]
        metal=mr[2];rough=mr[1]
        x,y,z=pos
        navy=c[2]>c[0]*1.20 and c[2]>c[1]*1.04
        # Remove the duplicate reservoir (not the navy hair overlapping above it).
        is_hair=navy and c[0]<.26 and c[2]<.59 and z>1.205
        is_cobalt=c[2]>c[1]*1.25 and c[2]>c[0]*1.35
        is_skin=c[0]>c[1]*1.12 and c[0]>c[2]*1.32
        tank_region=y<.16 and .64<z<1.36 and abs(x)<.47
        keep_sleeve=z<1.25 and is_cobalt
        keep_arm=.51<z<.97 and abs(x)>.265 and y>-.022
        keep_jacket=.72<z<1.24 and y>-.04 and abs(x)<.335
        keep_shoulder=.84<z<1.20 and y>-.035 and abs(x)<.39
        warm=c[0]>c[1]*1.08 and c[0]>c[2]*1.35
        if tank_region and abs(x)>.28 and warm and metal>.33 and not is_hair:
            remove.add(face.index);continue
        if tank_region and not(is_hair or keep_sleeve or keep_arm or keep_jacket or keep_shoulder):
            remove.add(face.index);continue
        hose_blue=c[0]<c[1]*.95 and c[2]>c[1]*1.10 and rough<.74
        hose_region=(y<.07 and .43<z<.90 and abs(x)>.25) or (y<.31 and .43<z<.80 and abs(x)>.37)
        if hose_region and hose_blue:
            remove.add(face.index);continue
        # Nozzle tips are rebuilt with exact circular bores, retaining the hands.
        if .45<z<.72 and abs(x)>.25 and y>.16 and metal>.36 and warm:
            remove.add(face.index);continue
        head_skin=1.12<z<1.405 and y>.11 and abs(x)<.205 and not navy
        limb_skin=(.56<z<.91 and abs(x)>.265 and y>-.04 and
                   c[0]>c[1]*1.12 and c[0]>c[2]*1.32)
        original_neck=1.00<z<1.17 and abs(x)<.12 and is_skin
        if head_skin or original_neck:
            remove.add(face.index);continue
        if limb_skin:
            face.material_index=sk_index;skin_vertices.update(face.vertices)
            for l in face.loop_indices:
                v=o.data.vertices[o.data.loops[l].vertex_index].co
                blush=math.exp(-((abs(v.x)-.126)/.045)**2-((v.z-1.28)/.036)**2)
                color.data[l].color=(.59,.345*(1-.13*blush),.245*(1-.12*blush),1)
        elif z>1.155 and navy:
            face.material_index=hair_index;hair_vertices.update(face.vertices)
    # Vertex colour only modulates skin. It is carried into glTF COLOR_0.
    nodes=skin.node_tree.nodes;links=skin.node_tree.links
    attr=nodes.new('ShaderNodeVertexColor');attr.layer_name='SkinComplexion'
    links.new(attr.outputs['Color'],nodes['Principled BSDF'].inputs['Base Color'])
    print('LIMNE_SURFACE_REGIONS',len(skin_vertices),len(hair_vertices),'removed_faces',len(remove))
    bm=bmesh.new();bm.from_mesh(o.data);bm.faces.ensure_lookup_table()
    dead=[bm.faces[i] for i in remove]
    dead_set=set(dead)
    cut_edges={e for e in bm.edges if any(f in dead_set for f in e.link_faces)
               and any(f not in dead_set for f in e.link_faces)}
    bmesh.ops.delete(bm,geom=dead,context='FACES')
    isolated=[v for v in bm.verts if not v.link_faces]
    if isolated:bmesh.ops.delete(bm,geom=isolated,context='VERTS')
    # Drop floating remnants of removed hardware, retaining large real garment
    # and hair surfaces. This is connectivity-based, not a texture-color guess.
    unseen=set(bm.verts);small=[]
    while unseen:
        start=unseen.pop();component={start};stack=[start]
        while stack:
            v=stack.pop()
            for e in v.link_edges:
                other=e.other_vert(v)
                if other in unseen:unseen.remove(other);component.add(other);stack.append(other)
        center=sum((v.co for v in component),Vector())/len(component)
        # Never discard a small valid hair, boot, finger or garment patch simply
        # because the reconstruction stored it as a separate connected chart.
        remnant=center.y<-.10 and .67<center.z<1.35 and abs(center.x)<.46
        face_indices={f.material_index for v in component for f in v.link_faces}
        near_nozzle=.42<center.z<.74 and abs(center.x)>.29 and center.y>.23
        changed=any(e in cut_edges for v in component for e in v.link_edges)
        remnant|=near_nozzle and changed and sk_index not in face_indices
        if len(component)<70 and remnant:small.extend(component)
    if small:bmesh.ops.delete(bm,geom=small,context='VERTS')
    # Close newly cut skin/cuff boundaries with real faces. Preserve each corner
    # UV from adjacent source faces; no zero-UV black triangle is introduced.
    remaining={e for e in bm.edges if e.is_boundary}
    uv_layer=bm.loops.layers.uv.active
    while remaining:
        first=remaining.pop();edges={first};stack=[first]
        while stack:
            edge=stack.pop()
            for v in edge.verts:
                for linked in v.link_edges:
                    if linked in remaining:remaining.remove(linked);edges.add(linked);stack.append(linked)
        verts={v for e in edges for v in e.verts}
        center=sum((v.co for v in verts),Vector())/len(verts)
        extent=max((v.co-center).length for v in verts)
        neighbors=[f for e in edges for f in e.link_faces]
        if not neighbors:continue
        hair_gap=center.z>1.18 and extent<.085 and all(f.material_index==hair_index for f in neighbors)
        body_gap=bool(edges&cut_edges) and center.z<=1.16 and center.y>=-.01 and extent<=.15
        if not(hair_gap or body_gap):continue
        counts={i:sum(f.material_index==i for f in neighbors) for i in set(f.material_index for f in neighbors)}
        index=max(counts,key=counts.get)
        if hair_gap:index=hair_index
        elif index==0:
            if center.z<.74 and abs(center.x)>.27:index=sk_index
            elif center.z>.95 and .12<abs(center.x)<.26:index=repair_indices['Harness_seam_repair']
            elif center.z>.80:index=repair_indices['Cobalt_seam_repair']
            elif abs(center.x)<.31:index=repair_indices['Teal_apron_seam_repair']
            else:index=repair_indices['Navy_work_pants_repair']
        vertex_uv={v:next((loop[uv_layer].uv.copy() for f in v.link_faces if f not in dead_set for loop in f.loops if loop.vert==v),Vector((0,0))) for v in verts}
        result=bmesh.ops.holes_fill(bm,edges=list(edges),sides=0)
        for face in result['faces']:
            face.material_index=index;face.smooth=True
            for loop in face.loops:loop[uv_layer].uv=vertex_uv[loop.vert]
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(o.data);bm.free();o.data.update()
    # Taubin-like alternating smoothing retains face and clump volume. Smoothing
    # selected material regions keeps authored garment folds and hems intact.
    for index,iterations,factor in [(sk_index,12,.42),(hair_index,16,.40)]:
        group_name='finish_region_'+str(index)
        group=o.vertex_groups.new(name=group_name)
        vertices={v for f in o.data.polygons if f.material_index==index for v in f.vertices}
        if vertices:group.add(list(vertices),1,'REPLACE')
        for step in range(2):
            bpy.context.view_layer.objects.active=o
            mod=o.modifiers.new('surface_relax','SMOOTH');mod.vertex_group=group_name
            mod.factor=factor if step==0 else -factor*.84
            mod.iterations=iterations
            bpy.ops.object.modifier_apply(modifier=mod.name)
        if group_name in o.vertex_groups:o.vertex_groups.remove(o.vertex_groups[group_name])
    return skin,hair


HEAD_PROFILE=[(.985,.063,.057),(1.035,.064,.060),(1.10,.072,.065),
              (1.145,.086,.079),(1.18,.127,.107),(1.225,.161,.129),
              (1.285,.181,.145),(1.34,.176,.141),(1.395,.167,.130),
              (1.445,.146,.116),(1.475,.088,.075),(1.493,.001,.001)]


def head_dimensions(z):
    # C1 Hermite profile: chin, jaw, cheek and forehead volumes form one surface.
    for i in range(len(HEAD_PROFILE)-1):
        p=HEAD_PROFILE[i];q=HEAD_PROFILE[i+1]
        if p[0]<=z<=q[0]:
            t=(z-p[0])/(q[0]-p[0]);res=[]
            before=HEAD_PROFILE[max(0,i-1)];after=HEAD_PROFILE[min(len(HEAD_PROFILE)-1,i+2)]
            for axis in [1,2]:
                a=(q[axis]-before[axis])/(q[0]-before[0]);b=(after[axis]-p[axis])/(after[0]-p[0])
                res.append((2*t**3-3*t*t+1)*p[axis]+(t**3-2*t*t+t)*a*(q[0]-p[0])+(-2*t**3+3*t*t)*q[axis]+(t**3-t*t)*b*(q[0]-p[0]))
            return res
    return HEAD_PROFILE[0][1:] if z<HEAD_PROFILE[0][0] else HEAD_PROFILE[-1][1:]


def face_y(x,z):
    rx,ry=head_dimensions(z)
    y=.126+ry*math.sqrt(max(0,1-(x/rx)**2))
    y+=.033*math.exp(-(x/.019)**2-((z-1.284)/.030)**2)
    y+=.007*math.exp(-((abs(x)-.115)/.038)**2-((z-1.270)/.04)**2)
    y+=.005*math.exp(-(x/.042)**2-((z-1.228)/.019)**2)
    y+=.010*math.exp(-(x/.055)**2-((z-1.182)/.025)**2)
    for ex in [-.080,.078]:
        y-=.012*math.exp(-((x-ex)/.043)**2-((z-1.334)/.030)**2)
    return y


def continuous_face_and_neck(skin):
    """Dense connected face retopology; nose/cheek/lip/jaw sculpt is integral."""
    verts=[];faces=[];rows=100;sides=96
    for i in range(rows):
        z=.985+(1.493-.985)*i/(rows-1);rx,ry=head_dimensions(z)
        for j in range(sides):
            t=math.tau*j/sides;x=rx*math.sin(t);y=.126+ry*math.cos(t)
            if math.cos(t)>0:y=face_y(x,z)
            verts.append((x,y,z))
    for i in range(rows-1):
        for j in range(sides):
            a=i*sides+j;b=i*sides+(j+1)%sides
            coords=[verts[k] for k in [a,b,b+sides,a+sides]]
            x=sum(p[0] for p in coords)/4;y=sum(p[1] for p in coords)/4;z=sum(p[2] for p in coords)/4
            aperture=y>.18 and any(((x-ex)/.0475)**2+((z-1.334)/.0315)**2<1 for ex in [-.080,.078])
            if not aperture:faces.append((a,a+sides,b+sides,b))
    ob=mesh('Retopologized_connected_face_neck',verts,faces,skin)
    colors=ob.data.color_attributes['SkinComplexion']
    for loop in ob.data.loops:
        x,y,z=ob.data.vertices[loop.vertex_index].co
        blush=math.exp(-((abs(x)-.124)/.042)**2-((z-1.27)/.035)**2)*max(0,(y-.13)/.10)
        colors.data[loop.index].color=(.59+.012*blush,.345-.040*blush,.245-.023*blush,1)
    return ob


def eyes_and_expression(skin,hair):
    white=material('Eye_warm_sclera',(.77,.73,.63),.21)
    iris=material('Eye_brown_radial_iris',(.18,.065,.018),.17)
    pupil=material('Eye_deep_pupil',(.002,.0015,.001),.09)
    lash=material('Eye_upper_lash',(.021,.012,.009),.39)
    lip=material('Lip_soft_warm',(.37,.15,.10),.44)
    created=[]
    iris.node_tree.nodes['Principled BSDF'].inputs['Coat Weight'].default_value=.65
    iris.node_tree.nodes['Principled BSDF'].inputs['Coat Roughness'].default_value=.06
    for ex in [-.080,.078]:
        side='L' if ex<0 else 'R';ez=1.334;ey=.252
        def surface(dx,dz,extra=0):
            q=(dx/.0475)**2+(dz/.0325)**2
            return ey+.024*math.sqrt(max(0,1-q))-math.copysign(.34,ex)*dx+extra
        # A seated, convex eye cap: true volume and a continuous elliptical rim.
        verts=[];faces=[];rings=9;sides=48
        for i in range(rings):
            r=max(.0001,i/(rings-1))
            for j in range(sides):
                t=math.tau*j/sides;dx=.0475*r*math.cos(t)
                dz=(.025 if math.sin(t)>0 else .022)*r*math.sin(t)
                verts.append((ex+dx,surface(dx,dz),ez+dz))
        for i in range(rings-1):
            for j in range(sides):
                a=i*sides+j;b=i*sides+(j+1)%sides
                faces.append((a,b,b+sides,a+sides))
        created.append(mesh('EyeSclera'+side,verts,faces,white))
        # The iris conforms to the spherical eye, with a radial coloured mesh.
        verts=[];faces=[];iris_x=ex+.002;iris_z=ez+.003
        for i in range(7):
            r=max(.0001,i/6)
            for j in range(48):
                t=math.tau*j/48;dx=.027*r*math.cos(t);dz=.028*r*math.sin(t)
                verts.append((iris_x+dx,surface(dx+.002,dz+.003,.0008),iris_z+dz))
        for i in range(6):
            for j in range(48):
                a=i*48+j;b=i*48+(j+1)%48;faces.append((a,b,b+48,a+48))
        ob=mesh('Iris'+side,verts,faces,iris);created.append(ob)
        colors=ob.data.color_attributes.new(name='IrisRadial',type='FLOAT_COLOR',domain='CORNER')
        for f in ob.data.polygons:
            for li in f.loop_indices:
                v=ob.data.vertices[ob.data.loops[li].vertex_index].co
                dx=v.x-iris_x;dz=v.z-iris_z;angle=math.atan2(dz,dx)
                radial=min(1,math.sqrt((dx/.027)**2+(dz/.028)**2))
                streak=(math.sin(angle*43)+math.sin(angle*79+.3))*.045
                brightness=(.22+.53*math.sin(radial*math.pi))+streak
                colors.data[li].color=(.27*brightness,.105*brightness,.023*brightness,1)
        n=iris.node_tree.nodes.new('ShaderNodeVertexColor');n.layer_name='IrisRadial'
        iris.node_tree.links.new(n.outputs['Color'],iris.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
        verts=[];faces=[]
        for i in range(4):
            r=max(.0001,i/3)
            for j in range(40):
                t=math.tau*j/40;dx=.009*r*math.cos(t);dz=.011*r*math.sin(t)
                verts.append((iris_x+dx,surface(dx+.002,dz+.003,.0015),iris_z+dz))
        for i in range(3):
            for j in range(40):
                a=i*40+j;b=i*40+(j+1)%40;faces.append((a,b,b+40,a+40))
        created.append(mesh('Pupil'+side,verts,faces,pupil))
        for upper in [True,False]:
            pts=[]
            for i in range(33):
                t=math.pi*i/32+(0 if upper else math.pi)
                dx=.048*math.cos(t);dz=(.026 if upper else .023)*math.sin(t)
                pts.append((ex+dx,ey+.003-math.copysign(.34,ex)*dx,ez+dz))
            created.append(tube(('UpperLid' if upper else 'LowerLid')+side,pts,.004 if upper else .003,skin))
            if upper:
                created.append(tube('UpperLash'+side,[(x,y+.0035,z-.0022) for x,y,z in pts],.0012,lash))
        # Soft socket-to-face transition, covering the aperture without a black
        # outlined gap. The upper lid partially covers the enlarged iris.
        verts=[];faces=[]
        for i in range(5):
            r=i/4
            for j in range(64):
                t=math.tau*j/64
                rx=.048+.009*r;rz=(.026 if math.sin(t)>0 else .023)+.009*r
                x=ex+rx*math.cos(t);z=ez+rz*math.sin(t)
                inner_y=ey+.005-math.copysign(.34,ex)*(x-ex)
                verts.append((x,inner_y*(1-r)+(face_y(x,z)+.0005)*r,z))
        for i in range(4):
            for j in range(64):
                a=i*64+j;b=i*64+(j+1)%64;faces.append((a,b,b+64,a+64))
        created.append(mesh('SocketTransition'+side,verts,faces,skin))
        brow=[]
        for i in range(19):
            t=i/18;dx=(t-.5)*.083
            brow.append((ex+dx,.238,1.384+.013*math.sin(math.pi*t)))
        created.append(tube('Eyebrow'+side,brow,.004,lash))
    # Gentle volumetric lip line; the reconstructed nose/cheek/jaw remain intact.
    pts=[]
    for i in range(25):
        t=i/24;x=(t-.5)*.065;z=1.226-.004*math.sin(math.pi*t)
        pts.append((x,face_y(x,z)+.0015,z))
    created.append(tube('Natural_smile',pts,.0014,lip))
    return created


def equipment():
    brass=material('Equipment_brushed_brass',(.40,.235,.087),.29,.80)
    edge=material('Equipment_polished_edge',(.54,.35,.135),.21,.88)
    enamel=material('Reservoir_navy_enamel',(.012,.052,.071),.35,.18)
    rubber=material('Equipment_rubber_seal',(.006,.018,.022),.56)
    glass=material('Reservoir_clear_glass',(.21,.54,.59),.12,0,.34)
    water=material('Reservoir_cyan_water',(.011,.23,.29),.19,.12)
    bore=material('Nozzle_dark_bore',(.004,.006,.007),.55)
    hose_mat=material('Hose_blue_ribbed_rubber',(.009,.069,.119),.48)
    created=[];c=(0,-.19,.997)
    # One round, shallow reservoir, with a manufactured seam and a rear lens.
    created.append(lathe('SingleReservoirHousing',[(-.11,.003),(-.11,.286),(-.095,.325),(-.06,.338),(.07,.328),(.095,.295),(.10,.003)],enamel,c))
    created.append(lathe('ReservoirOuterBezel',[(-.12,.283),(-.13,.287),(-.131,.311),(-.126,.320),(-.113,.325),(-.096,.320),(-.096,.306),(-.106,.297),(-.12,.283)],brass,c))
    created.append(lathe('ReservoirLensSeal',[(-.125,.272),(-.128,.278),(-.126,.287),(-.118,.289),(-.115,.280),(-.125,.272)],rubber,c))
    # Closed cyan water volume has a genuinely horizontal water line in the lens.
    verts=[];faces=[];rows=33;cols=49;r=.277
    for i in range(rows):
        z=-r+1.45*r*i/(rows-1)
        width=math.sqrt(max(.00001,r*r-z*z))
        for j in range(cols):
            x=-width+2*width*j/(cols-1)
            bulge=.035*math.sqrt(max(0,1-(x*x+z*z)/(r*r)))
            verts.append((x,c[1]-.132-bulge,c[2]+z))
    for i in range(rows-1):
        for j in range(cols-1):
            a=i*cols+j;faces.append((a,a+1,a+1+cols,a+cols))
    created.append(mesh('ReservoirWaterVolume',verts,faces,water))
    # Curved glass above the water and across its surface, supported by the seal.
    profile=[]
    for i in range(13):
        t=(math.pi/2)*i/12
        profile.append((-.13-.041*math.cos(t),max(.0001,.276*math.sin(t))))
    created.append(lathe('ReservoirGlassLens',profile,glass,c))
    created.append(tube('HorizontalWaterMeniscus',[(-.247,c[1]-.155,1.12),(-.12,c[1]-.166,1.12),(0,c[1]-.169,1.12),(.12,c[1]-.166,1.12),(.247,c[1]-.155,1.12)],.0025,water))
    # Eight recessed precision fasteners sit on the circular flange.
    for i in range(8):
        t=math.tau*i/8;x=.308*math.cos(t);z=c[2]+.308*math.sin(t)
        created.append(lathe('ReservoirFastener%02d'%i,[(-.012,.001),(-.012,.008),(-.009,.010),(0,.010),(.002,.007),(.002,.001)],edge,(x,c[1]-.119,z),sides=12))
    # Fill neck is vertical and remains clearly separate from the hair.
    ob=lathe('ReservoirFillCap',[(0,.022),(.015,.029),(.021,.034),(.036,.034),(.040,.029),(.040,.001)],brass,(0,0,0),sides=40)
    ob.rotation_euler.x=math.pi/2;ob.location=(0,-.19,1.326);created.append(ob)
    for sign in [-1,1]:
        # Each nozzle is connected to the existing hand: lathed profile and an
        # actual open, circular discharge bore with a dark inner wall.
        control='ArmR' if sign>0 else 'ArmL'
        center=(sign*.347,.307,.565)
        profile=[(-.015,.025),(0,.027),(.010,.029),(.014,.043),(.025,.045),(.027,.040),(.069,.037),(.075,.044),(.084,.045),(.090,.041),(.090,.029),(.078,.029),(.044,.022),(.035,.020)]
        created.append(lathe('CircularNozzle'+control,profile,brass,center,control,sides=48))
        created.append(lathe('NozzlePolishedMouth'+control,[(.080,.040),(.083,.044),(.089,.044),(.093,.039),(.093,.029),(.089,.027),(.085,.029),(.080,.040)],edge,center,control,sides=48))
        created.append(lathe('NozzleInnerBore'+control,[(.092,.028),(.053,.021),(.051,.001)],bore,center,control,sides=48))
        p0=Vector((sign*.255,-.14,.79));p1=Vector((sign*.44,-.16,.51))
        p2=Vector((sign*.43,.17,.47));p3=Vector((sign*.347,.294,.565))
        points=[];radii=[]
        for i in range(49):
            t=i/48;points.append(tuple((1-t)**3*p0+3*(1-t)**2*t*p1+3*(1-t)*t*t*p2+t**3*p3))
            radii.append(.024*(1+.085*math.cos(math.tau*t*24)))
        ob=tube('ConnectedHose'+control,points,radii,hose_mat,sides=12)
        ob['limne_hose_side']=control
        attr=ob.data.attributes.new(name='HoseBend',type='FLOAT',domain='POINT')
        for i,value in enumerate(attr.data):value.value=(i//12)/48
        created.append(ob)
        created.append(lathe('ReservoirHoseSocket'+control,[(-.017,.015),(-.017,.027),(0,.029),(.016,.025),(.017,.015)],brass,tuple(p0)))
    return created


def finish_surface(objects):
    skin,hair=face_finish(objects[0])
    created=[continuous_face_and_neck(skin)]+eyes_and_expression(skin,hair)+equipment()
    return created
