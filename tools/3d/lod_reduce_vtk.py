#!/usr/bin/env python3
"""Geometry stage of tools/3d/optimize_native_lod.py: outer hull, quadric decimation, atlas.

Runs in the TRELLIS venv, which already carries VTK 9.7, scipy, scikit-image and xatlas (the
same CPU environment that rebuilt TitanBloom's surface, docs/NATIVE_MONSTER_PRODUCTION.md):

    ~/.local/opt/trellis/venv/bin/python tools/3d/lod_reduce_vtk.py in.npz out.npz \
        --triangles 5800 --resolution 1024 --padding 8 --pitch 0.003

in.npz   v (N,3) positions, f (M,3) triangles, skin (N,G) bone weights,
         extra (N,E) other per-vertex fields to carry (material membership)
out.npz  v, f, skin, extra, corner_uv (M',3,2) and the atlas statistics

--pitch (outer hull) is an opt-in experiment, NOT used for the shipped models: real openings
connect cavities to the outside (Frost imp's eye holes, DropSlime's eye holes), so the fill
cannot close them and the hull grows inner surfaces again (6.7M marching-cubes triangles for
DropSlime). optimize_native_lod.py instead deletes the faces no camera can see before this
stage. The notes below explain what the hull would solve.

Why an outer hull: the reconstructed surfaces are not one sheet. A cross-section of
DropSlime shows the visible outer sheet, a ~1.7 cm wall, then a doubled inner cavity sheet;
94-99 % of all faces have a twin within 1 % of the height (Brasa, Frost imp, DropSlime).
Decimating that keeps every sheet, so about half of any budget is spent on surfaces nobody
sees, and the welded charts leave ~1,500 pinched vertices that stall Blender's collapse at
10.2k triangles for a 6k request. Here the sheets are voxelized (--pitch), closed by one
voxel, every enclosed cavity is filled and marching cubes takes the single outer boundary:
a watertight two-manifold surface that is exactly what the camera sees.

Skin weights and material membership are carried from the source: each hull vertex takes
the inverse-distance mean of its 4 nearest dense source samples (barycentric samples of
the reviewed game surface, so a vertex inherits the weights of the surface it covers). The
quadric decimation (vtkQuadricDecimation, MapPointData) then interpolates them along every
collapse. A sole never sinks: vertices below the source's lowest point are lifted to it.
Without --pitch the source is decimated as it is (used for clean authored meshes).
"""
import argparse
import numpy as np
import vtk
from vtk.util import numpy_support as ns
import xatlas

p = argparse.ArgumentParser()
p.add_argument('src')
p.add_argument('dst')
p.add_argument('--triangles', type=int, required=True)
p.add_argument('--resolution', type=int, default=1024)
p.add_argument('--padding', type=int, default=8)
p.add_argument('--pitch', type=float, default=0.0, help='voxel size of the outer hull (m); 0 keeps the source sheets')
p.add_argument('--level', type=float, default=0.5, help='marching cubes level of the smoothed occupancy')
a = p.parse_args()

d = np.load(a.src)
V = d['v'].astype(np.float64)
F = d['f'].astype(np.int64)
skin = d['skin'].astype(np.float32)
extra = d['extra'].astype(np.float32) if 'extra' in d and d['extra'].size else np.zeros((len(V), 0), np.float32)
floor = float(V[:, 2].min())
stats = {}


def dense_samples(V, F, fields, spacing):
    """Barycentric samples of every triangle (and its corners) with interpolated fields."""
    a, b, c = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    area = 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)
    count = np.clip(np.ceil(area / (spacing * spacing)), 1, 4000).astype(np.int64)
    tri = np.repeat(np.arange(len(F)), count)
    rng = np.random.default_rng(1015)
    r1 = np.sqrt(rng.random(len(tri))); r2 = rng.random(len(tri))
    w = np.stack([1 - r1, r1 * (1 - r2), r1 * r2], axis=1)
    pts = (w[:, :, None] * V[F[tri]]).sum(axis=1)
    vals = (w[:, :, None] * fields[F[tri]]).sum(axis=1)
    return np.concatenate([pts, V]), np.concatenate([vals, fields])


if a.pitch > 0:
    from scipy import ndimage
    from scipy.spatial import cKDTree
    from skimage import measure
    fields = np.concatenate([skin, extra], axis=1)
    pts, vals = dense_samples(V, F, fields, a.pitch * 0.35)
    origin = pts.min(axis=0) - a.pitch * 4
    idx = np.floor((pts - origin) / a.pitch).astype(np.int64)
    shape = idx.max(axis=0) + 5
    grid = np.zeros(shape, bool)
    grid[idx[:, 0], idx[:, 1], idx[:, 2]] = True
    # Close sub-voxel cracks between the reconstruction's sheets, then fill every cavity that
    # is not connected to the outside: what remains is bounded by the outermost sheet only.
    closed = ndimage.binary_closing(grid, iterations=1)
    solid = ndimage.binary_fill_holes(closed)
    field = ndimage.gaussian_filter(solid.astype(np.float32), sigma=0.7)
    verts, faces, _, _ = measure.marching_cubes(field, level=a.level, spacing=(a.pitch,) * 3)
    verts = verts + origin + a.pitch * 0.5          # grid index i is the voxel centre
    faces = faces.astype(np.int64)
    tri = verts[faces]
    if np.einsum('ij,ij->i', tri[:, 0], np.cross(tri[:, 1], tri[:, 2])).sum() < 0:
        faces = faces[:, ::-1]                         # outward winding (positive volume)
    tree = cKDTree(pts)
    dist, near = tree.query(verts, k=4)
    wts = 1.0 / np.maximum(dist, a.pitch * 0.05)
    carried = (vals[near] * wts[:, :, None]).sum(axis=1) / wts.sum(axis=1, keepdims=True)
    stats.update(hull_vertices=len(verts), hull_triangles=len(faces), grid=list(map(int, shape)),
                 hull_source_distance_p99=float(np.percentile(dist[:, 0], 99)))
    V, F = verts.astype(np.float64), faces
    skin, extra = carried[:, :skin.shape[1]].astype(np.float32), carried[:, skin.shape[1]:].astype(np.float32)

poly = vtk.vtkPolyData()
pts_v = vtk.vtkPoints(); pts_v.SetData(ns.numpy_to_vtk(V, deep=True)); poly.SetPoints(pts_v)
cells = vtk.vtkCellArray()
offsets = np.arange(0, 3 * len(F) + 1, 3, dtype=np.int64)
cells.SetData(ns.numpy_to_vtkIdTypeArray(offsets, deep=True), ns.numpy_to_vtkIdTypeArray(F.ravel().copy(), deep=True))
poly.SetPolys(cells)
arr = ns.numpy_to_vtk(skin, deep=True); arr.SetName('skin'); poly.GetPointData().AddArray(arr)
if extra.shape[1]:
    arr2 = ns.numpy_to_vtk(extra, deep=True); arr2.SetName('extra'); poly.GetPointData().AddArray(arr2)

dec = vtk.vtkQuadricDecimation()
dec.SetInputData(poly)
dec.SetTargetReduction(max(0.0, 1.0 - a.triangles / max(len(F), 1)))
dec.VolumePreservationOn()
dec.SetMapPointData(True)
dec.Update()
out = dec.GetOutput()
v2 = ns.vtk_to_numpy(out.GetPoints().GetData()).astype(np.float64)
f2 = ns.vtk_to_numpy(out.GetPolys().GetConnectivityArray()).astype(np.int64).reshape(-1, 3)
skin2 = ns.vtk_to_numpy(out.GetPointData().GetArray('skin')).astype(np.float32).reshape(len(v2), -1)
extra2 = ns.vtk_to_numpy(out.GetPointData().GetArray('extra')).astype(np.float32).reshape(len(v2), -1) \
    if extra.shape[1] else np.zeros((len(v2), 0), np.float32)

# Drop collapsed (repeated index / zero area) and duplicate triangles, then unused points.
ok = (f2[:, 0] != f2[:, 1]) & (f2[:, 1] != f2[:, 2]) & (f2[:, 0] != f2[:, 2])
area = np.linalg.norm(np.cross(v2[f2[:, 1]] - v2[f2[:, 0]], v2[f2[:, 2]] - v2[f2[:, 0]]), axis=1)
ok &= area > 1e-12
f2 = f2[ok]
_, first = np.unique(np.sort(f2, axis=1), axis=0, return_index=True)
f2 = f2[np.sort(first)]
used = np.unique(f2)
remap = -np.ones(len(v2), np.int64); remap[used] = np.arange(len(used))
v2, skin2, extra2, f2 = v2[used], skin2[used], extra2[used], remap[f2]
skin2 = np.clip(skin2, 0, None)
skin2 /= np.maximum(skin2.sum(axis=1, keepdims=True), 1e-8)
lifted = int((v2[:, 2] < floor).sum())
v2[:, 2] = np.maximum(v2[:, 2], floor)
stats['floor_lifted_vertices'] = lifted
# Already reduced parts (Limne's eyes, lashes, lip) join here so one atlas holds everything
# at one texel density.
if 'lock_v' in d and len(d['lock_v']):
    base = len(v2)
    v2 = np.concatenate([v2, d['lock_v'].astype(np.float64)])
    f2 = np.concatenate([f2, d['lock_f'].astype(np.int64) + base])
    skin2 = np.concatenate([skin2, d['lock_skin'].astype(np.float32)])
    extra2 = np.concatenate([extra2, d['lock_extra'].astype(np.float32).reshape(len(d['lock_v']), -1)])
    stats['locked_triangles'] = int(len(d['lock_f']))

# New atlas. xatlas keeps the triangle order; vmapping points back to the welded vertex.
atlas = xatlas.Atlas()
atlas.add_mesh(v2.astype(np.float32), f2.astype(np.uint32))
chart = xatlas.ChartOptions()
pack = xatlas.PackOptions()
pack.resolution = a.resolution
pack.padding = a.padding
pack.bilinear = True
pack.rotate_charts = True
atlas.generate(chart, pack)
vmapping, indices, uvs = atlas.get_mesh(0)
indices = indices.reshape(-1, 3)
if len(indices) != len(f2) or not np.array_equal(vmapping[indices], f2):
    raise SystemExit('xatlas changed the triangle order')
corner_uv = uvs[indices]
utilization = atlas.utilization
utilization = float(utilization[0] if hasattr(utilization, '__len__') else utilization)
np.savez(a.dst, v=v2.astype(np.float32), f=f2.astype(np.int32), skin=skin2, extra=extra2,
         corner_uv=corner_uv.astype(np.float32), charts=np.int32(atlas.chart_count), utilization=np.float32(utilization),
         width=np.int32(atlas.width), height=np.int32(atlas.height), stats=np.array([str(stats)]))
print('LOD_REDUCE', len(d['v']), len(d['f']), '->', len(v2), len(f2), 'charts', atlas.chart_count, 'stats', stats)
