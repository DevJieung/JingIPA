"""Focused surface repair of the retained high-UV Limne, without global cuts."""
import bpy,bmesh,numpy as np,math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from limne_surface_finish import material,mesh,tube


def polish(body,rig):
    base=body.data.materials[0]
    orm_image=next(n.image for n in base.node_tree.nodes if n.type=='TEX_IMAGE' and n.image and n.image.colorspace_settings.name=='Non-Color')
    w,h=orm_image.size;orm=np.asarray(orm_image.pixels[:],dtype=np.float32).reshape(h,w,4)
    color_image=next(n.image for n in base.node_tree.nodes if n.type=='TEX_IMAGE' and n.image and n.image.colorspace_settings.name!='Non-Color')
    cw,ch=color_image.size;rgb=np.asarray(color_image.pixels[:],dtype=np.float32).reshape(ch,cw,4)
    uv=np.asarray([v.uv[:] for v in body.data.uv_layers.active.data])
    remove=set()
    for face in body.data.polygons:
        p=face.center;u=np.mean(uv[list(face.loop_indices)],axis=0)
        metal=orm[min(h-1,max(0,int(u[1]*h))),min(w-1,max(0,int(u[0]*w))),2]
        color=rgb[min(ch-1,max(0,int(u[1]*ch))),min(cw-1,max(0,int(u[0]*cw))),:3]
        # True hand skin has zero metallic in the retained source atlas. Remove
        # only residual source nozzle material, not the hand's spatial volume.
        if .45<p.z<.72 and abs(p.x)>.25 and p.y>.16 and metal>.025:remove.add(face.index)
        # This small original filler chip is behind the hair, not the new cap.
        if 1.17<p.z<1.35 and p.y<.12 and .08<abs(p.x)<.28 and face.material_index==0 and metal>.06:remove.add(face.index)
        if .60<p.z<.88 and abs(p.x)>.445:remove.add(face.index)
        # Replace the damaged hand/wrist skin, not the sleeve or its UVs.
        if face.material_index==1 and .46<p.z<.85 and abs(p.x)>.265:remove.add(face.index)
        if .44<p.z<.72 and abs(p.x)>.265 and metal<.04 and color[0]>color[1]*1.10 and color[0]>color[2]*1.2:remove.add(face.index)
        if .48<p.z<.64 and p.y<.07 and abs(p.x)<.32 and metal>.12:remove.add(face.index)
        # Exact ray-hit location of the remaining isolated white hardware fleck.
        if .625<p.z<.665 and p.y<-.21 and .30<abs(p.x)<.35:remove.add(face.index)
    bm=bmesh.new();bm.from_mesh(body.data);bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[bm.faces[i] for i in remove],context='FACES')
    isolated=[v for v in bm.verts if not v.link_faces]
    if isolated:bmesh.ops.delete(bm,geom=isolated,context='VERTS')
    # A single isolated fleck beyond either forearm is not valid garment detail.
    unseen=set(bm.verts);small=[]
    while unseen:
        v=unseen.pop();component={v};stack=[v]
        while stack:
            v=stack.pop()
            for e in v.link_edges:
                other=e.other_vert(v)
                if other in unseen:unseen.remove(other);component.add(other);stack.append(other)
        c=sum((v.co for v in component),Vector())/len(component)
        if len(component)<28 and .48<c.z<.93 and (abs(c.x)>.40 or c.y<.04):small.extend(component)
    if small:bmesh.ops.delete(bm,geom=small,context='VERTS')
    todo={e for e in bm.edges if e.is_boundary};closed=0
    while todo:
        e=todo.pop();edges={e};stack=[e]
        while stack:
            e=stack.pop()
            for v in e.verts:
                for other in v.link_edges:
                    if other in todo:todo.remove(other);edges.add(other);stack.append(other)
        verts={v for e in edges for v in e.verts};c=sum((v.co for v in verts),Vector())/len(verts)
        radius=max((v.co-c).length for v in verts)
        index=None
        if abs(c.x)>.255 and .73<c.z<.97 and radius<.13:index=3 # cobalt cuff
        elif abs(c.x)>.19 and .97<c.z<1.18 and radius<.14:index=3 # shoulder
        elif abs(c.x)>.255 and .48<c.z<.74 and c.y>.08 and radius<.10:index=1 # hand
        elif c.z>1.20 and radius<.06 and all(f.material_index==2 for e in edges for f in e.link_faces):index=2
        if index is None:continue
        result=bmesh.ops.holes_fill(bm,edges=list(edges),sides=0)
        for f in result['faces']:f.material_index=index;f.smooth=True
        closed+=len(result['faces'])
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(body.data);bm.free()
    # Restore corner colour after new cap loops were allocated. Material colours
    # carry cloth/hair; only skin uses the complexion attribute directly.
    col=body.data.color_attributes['SkinComplexion'].data
    for f in body.data.polygons:
        for li in f.loop_indices:col[li].color=(.59,.345,.245,1) if f.material_index==1 else (1,1,1,1)
    body.data.validate(verbose=True,clean_customdata=True);body.data.update();body.data.calc_loop_triangles()
    # A coherent sewn waist facing follows the existing apron surface. It
    # bridges the reconstruction's dark torn seam with an actual cloth surface.
    bvh=BVHTree.FromPolygons([v.co for v in body.data.vertices],[list(p.vertices) for p in body.data.polygons])
    verts=[];faces=[];cols=65;rows=7
    for i in range(rows):
        z=.775+.055*i/(rows-1)
        for j in range(cols):
            width=.226+.006*math.sin(math.pi*i/(rows-1))
            x=-width+2*width*j/(cols-1)
            # Fit to intact cloth above/below the torn seam. Ray projection
            # inside the hole itself would reproduce the torn contour.
            intact=[bvh.ray_cast(Vector((x,1,level)),Vector((0,-1,0)),2)[0] for level in [.738,.885]]
            ys=[p.y for p in intact if p is not None]
            y=sum(ys)/len(ys) if ys else .025+.31*math.sqrt(max(0,1-(x/.30)**2))
            fold=.003*math.sin(x*37+.6)*math.sin(math.pi*i/(rows-1))
            verts.append((x,y+.012+fold,z))
    # Smooth only the facing's Y coordinate; retain the projected fit/width.
    for step in range(3):
        current=[v[1] for v in verts]
        for i in range(1,rows-1):
            for j in range(1,cols-1):
                k=i*cols+j;v=verts[k]
                verts[k]=(v[0],.55*current[k]+.1125*(current[k-1]+current[k+1]+current[k-cols]+current[k+cols]),v[2])
    for i in range(rows-1):
        for j in range(cols-1):
            a=i*cols+j;faces.append((a,a+cols,a+cols+1,a+1))
    cloth=material('Teal_sewn_waist_facing',(.025,.29,.38),.83)
    ob=mesh('Continuous_apron_waist_facing',verts,faces,cloth)
    created=[ob]
    stitch=material('Teal_small_topstitch',(.037,.255,.285),.72)
    for row in [0,rows-1]:
        points=[(verts[row*cols+j][0],verts[row*cols+j][1]+.001,verts[row*cols+j][2]) for j in range(cols)]
        created.append(tube('WaistTopstitch'+str(row),points,.00065,stitch,sides=5))
    cobalt=material('Cobalt_reinforced_seam',(.02,.112,.225),.73)
    for sign in [-1,1]:
        # A narrow closed cloth binding around the existing rolled cuff.
        v=[];f=[];profile=[(.766,.057,.089),(.777,.064,.102),(.827,.064,.105),(.869,.058,.092)]
        for z,rx,ry in profile:
            cx=sign*(.345-(z-.785)*.35)
            for j in range(48):
                t=math.tau*j/48;v.append((cx+rx*math.cos(t),.145+ry*math.sin(t),z))
        for row in range(3):
            for j in range(48):
                a=row*48+j;b=row*48+(j+1)%48;f.append((a,b,b+48,a+48))
        ob=mesh('Cuff_sewn_binding_'+str(sign),v,f,cobalt,'ArmL' if sign<0 else 'ArmR')
        ob['skin_binding']='ArmL' if sign<0 else 'ArmR';created.append(ob)
        # A full curved shoulder seam has a front, side and back; a front-only
        # projected patch cannot close a reconstructed shoulder opening.
        v=[];f=[];profile=[(.975,.321,.052,.064,.075),(1.015,.302,.030,.068,.080),
            (1.052,.280,.012,.064,.081),(1.075,.265,.011,.057,.078),
            (1.106,.245,.015,.043,.064),(1.125,.238,.015,.012,.030)]
        for z,cx,cy,rx,ry in profile:
            for j in range(64):
                t=math.tau*j/64;v.append((sign*cx+rx*math.cos(t),cy+ry*math.sin(t),z))
        for row in range(len(profile)-1):
            for j in range(64):
                a=row*64+j;b=row*64+(j+1)%64;f.append((a,b,b+64,a+64))
        f.append(tuple(reversed(range(64))));f.append(tuple((len(profile)-1)*64+j for j in range(64)))
        created.append(mesh('Continuous_shoulder_yoke_'+str(sign),v,f,cobalt))
        # Authored closed hand/wrist retopology replaces the damaged source
        # skin. The cuff and original garment remain in place.
        skin=body.data.materials[1];v=[];f=[]
        profile=[(.496,.347,.221,.003,.003),(.508,.347,.223,.046,.052),
            (.533,.349,.222,.061,.065),(.57,.348,.213,.062,.068),
            (.611,.350,.189,.053,.059),(.656,.352,.164,.048,.051),
            (.708,.348,.144,.046,.048),(.76,.336,.134,.046,.049),
            (.825,.315,.133,.044,.048)]
        for z,cx,cy,rx,ry in profile:
            for j in range(64):
                t=math.tau*j/64
                v.append((sign*cx+rx*math.cos(t),cy+ry*math.sin(t),z))
        for row in range(len(profile)-1):
            for j in range(64):
                a=row*64+j;b=row*64+(j+1)%64;f.append((a,b,b+64,a+64))
        f.append(tuple(reversed(range(64))));f.append(tuple((len(profile)-1)*64+j for j in range(64)))
        control='ArmL' if sign<0 else 'ArmR'
        ob=mesh('Closed_wrist_gripping_hand_'+str(sign),v,f,skin,control)
        ob['skin_binding']=control;created.append(ob)
        # Knuckle contours and opposed thumb lie within the continuous palm.
        for finger in range(4):
            x=sign*(.311+.024*finger)
            points=[(x,.245,.583),(x,.270,.574),(x,.276,.555),(x,.263,.539)]
            ob=tube('Curled_finger_'+str(sign)+'_'+str(finger),points,.011,skin,control,sides=12)
            ob['skin_binding']=control;created.append(ob)
        points=[(sign*.297,.200,.599),(sign*.289,.241,.584),(sign*.302,.266,.564)]
        ob=tube('Opposed_thumb_'+str(sign),points,.018,skin,control,sides=16)
        ob['skin_binding']=control;created.append(ob)
    for ob in created:
        group=ob.vertex_groups.new(name='Skin'+ob.get('skin_binding','Body'));group.add(list(range(len(ob.data.vertices))),1,'REPLACE')
        mod=ob.modifiers.new('body_skin','ARMATURE');mod.object=rig;ob.parent=rig
    print('LIMNE_LOCAL_POLISH','removed',len(remove),'filled',closed,'new_cloth_surfaces',len(created))
    return created
