#!/usr/bin/env python3
"""CPU repair of actual Titan surface; existing TRELLIS scientific environment."""
import json,sys
from pathlib import Path
import numpy as np
import scipy.ndimage as nd
import trimesh

src=Path(sys.argv[1]);dest=Path(sys.argv[2]);pitch=float(sys.argv[3])
data=np.load(src)
mesh=trimesh.Trimesh(vertices=data['vertices'],faces=data['faces'],process=False)
voxel=mesh.voxelized(pitch,method='subdivide')
matrix=voxel.matrix
# Close sub-voxel reconstruction splits, then fill only genuinely enclosed
# volumes. The open mouth is connected to exterior and keeps its cavity.
closed=nd.binary_closing(np.pad(matrix,2),iterations=1)
filled=nd.binary_fill_holes(closed)
surface=trimesh.voxel.ops.matrix_to_marching_cubes(filled,pitch=pitch)
surface.vertices+=voxel.transform[:3,3]-pitch*2
surface.remove_unreferenced_vertices()
np.savez_compressed(dest,vertices=surface.vertices,faces=surface.faces)
print(json.dumps({'source_triangles':len(mesh.faces),'voxel_pitch_m':pitch,'grid':list(filled.shape),'surface_triangles':len(surface.faces),'vertices':len(surface.vertices),'watertight':bool(surface.is_watertight),'output':str(dest)}),flush=True)
