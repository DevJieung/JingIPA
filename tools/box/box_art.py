"""Jewel-box art for the arena summon (F10/F11): five chests, 1-star wood crate to
5-star prismatic casket, modelled procedurally and rendered with EEVEE.

Run through the driver (it crops, builds the seam glow and writes the manifest):

    python3 tools/box/build_box_art.py            # all five tiers -> art/ui/box/
    python3 tools/box/build_box_art.py --preview  # closed boxes only, a quick look

Direct use (the driver does this):

    blender -b --factory-startup -P tools/box/box_art.py -- --out DIR --tiers 1,2,3,4,5

Why 3D renders and not painted sprites: the boxes open on a hinge, and the lid frames,
the lit interior and the light that leaks through the seam have to agree pixel for pixel
with the body. One model per tier gives that for free. Image generation was not used:
another project held 11.3 GB of the GPU on 2026-10-19 (tools/gpu_guard.py status), and the
task rules say to wait or choose a 3D render or code drawing instead.

Layers per tier (all from one fixed camera, transparent background):
    body.png         the body with its lid removed; the interior glows in the tier light
    lid_AAA.png      the lid alone at hinge angle AAA, the body as a holdout
    full_lit.png / full_dark.png   lid at 6 degrees with the interior light on / off;
                     the driver subtracts them into seam.png (light through the seam)
    closed.png       the whole closed box (contact sheets and the menu guide)
Lights match the portrait rig (tests/3d/render_portraits.gd): warm key from the camera
side above, cool fill, cool rim so the box separates from the dark modal glass.
"""
from __future__ import annotations

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name: str, default: str) -> str:
    if name in ARGS:
        return ARGS[ARGS.index(name) + 1]
    return default


OUT = arg("--out", "/tmp/box_art")
TIERS = [int(t) for t in arg("--tiers", "1,2,3,4,5").split(",")]
RES = int(arg("--res", "1024"))
PREVIEW = "--preview" in ARGS
ANGLES = [0, 6, 18, 40, 70, 100, 118]
SAMPLES = int(arg("--samples", "64"))

# Box body (Blender units). Front faces -Y, the hinge runs along X at the back top edge.
W, D, H = 1.0, 0.68, 0.50
WALL = 0.075


# --------------------------------------------------------------------------- #
# colour + materials
# --------------------------------------------------------------------------- #
def lin(hex_color: str) -> tuple:
    hex_color = hex_color.lstrip("#")
    out = []
    for i in range(3):
        c = int(hex_color[i * 2:i * 2 + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def _set(bsdf, names, value):
    for n in names:
        if n in bsdf.inputs:
            bsdf.inputs[n].default_value = value
            return


def material(name, color, metal=0.0, rough=0.5, emit=None, strength=0.0, spec=0.5,
             coat=0.0, flat_noise=0.0, noise_scale=6.0, dark=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    base = lin(color) if isinstance(color, str) else color
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    _set(bsdf, ["Specular IOR Level", "Specular"], spec)
    _set(bsdf, ["Coat Weight", "Clearcoat"], coat)
    if emit is not None:
        e = lin(emit) if isinstance(emit, str) else emit
        _set(bsdf, ["Emission Color", "Emission"], (*e, 1.0))
        _set(bsdf, ["Emission Strength"], strength)
    if flat_noise > 0.0:
        # A quiet painted variation so large faces do not read as plastic.
        tex = nt.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = noise_scale
        tex.inputs["Detail"].default_value = 3.0
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        lo = lin(dark) if isinstance(dark, str) else (dark if dark else tuple(c * 0.72 for c in base))
        ramp.color_ramp.elements[0].color = (*lo, 1.0)
        ramp.color_ramp.elements[1].color = (*base, 1.0)
        ramp.color_ramp.elements[0].position = 0.5 - flat_noise * 0.5
        ramp.color_ramp.elements[1].position = 0.5 + flat_noise * 0.5
        nt.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def wood(name, light, darkc, grain=7.0, rings=0.35, along_y=False):
    """Stylised wood: soft grain bands stretched along the plank (local X)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.72
    _set(bsdf, ["Specular IOR Level", "Specular"], 0.25)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (grain, 1.0, grain) if along_y else (1.0, grain, grain)
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "X" if along_y else "Y"
    wave.inputs["Scale"].default_value = 1.6
    wave.inputs["Distortion"].default_value = 3.0
    wave.inputs["Detail"].default_value = 2.0
    nt.links.new(mapping.outputs["Vector"], wave.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*lin(darkc), 1)
    ramp.color_ramp.elements[1].color = (*lin(light), 1)
    ramp.color_ramp.elements[0].position = 0.5 - rings * 0.5
    ramp.color_ramp.elements[1].position = 0.5 + rings * 0.5
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return m


# --------------------------------------------------------------------------- #
# geometry helpers
# --------------------------------------------------------------------------- #
def smooth(o, angle=38.0):
    if o.type != "MESH":
        return
    for p in o.data.polygons:
        p.use_smooth = True
    if hasattr(o.data, "use_auto_smooth"):
        o.data.use_auto_smooth = True
        o.data.auto_smooth_angle = math.radians(angle)


def link(o, mat, parent=None, bevel=0.0, seg=3, flat=False, angle=38.0):
    if mat is not None:
        o.data.materials.clear()
        o.data.materials.append(mat)
    if bevel > 0.0:
        b = o.modifiers.new("bevel", "BEVEL")
        b.width = bevel
        b.segments = seg
        b.limit_method = "ANGLE"
        b.angle_limit = math.radians(35)
    if not flat:
        smooth(o, angle)
    if parent is not None:
        o.parent = parent
    return o


def mesh_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def box(name, size, loc, mat, parent=None, bevel=0.02, seg=3):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    o = mesh_obj(name, bm)
    o.location = loc
    return link(o, mat, parent, bevel, seg)


def cylinder(name, r, depth, loc, mat, parent=None, axis="Z", seg=24, r2=None, bevel=0.0,
             rot=None, flat=False):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r,
                          radius2=r if r2 is None else r2, depth=depth)
    if axis == "X":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    elif axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
    o = mesh_obj(name, bm)
    o.location = loc
    if rot is not None:
        o.rotation_euler = rot
    return link(o, mat, parent, bevel, 2, flat)


def half_cylinder(name, r, length, loc, mat, parent=None, seg=40, bevel=0.012, scale_z=1.0):
    """A barrel lid: half a cylinder along X, flat face down, from z=0 up to r."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r, depth=length)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=(0, 0, 0), plane_no=(0, 0, -1), clear_outer=True)
    bmesh.ops.holes_fill(bm, edges=bm.edges[:], sides=0)
    if scale_z != 1.0:
        bmesh.ops.scale(bm, vec=Vector((1, 1, scale_z)), verts=bm.verts)
    o = mesh_obj(name, bm)
    o.location = loc
    return link(o, mat, parent, bevel, 3)


def band_arc(name, r, width, thick, loc, mat, parent=None, seg=40, scale_z=1.0):
    """A metal band that follows a barrel lid: a half ring of width `width` (along X)."""
    bm = bmesh.new()
    rings = []
    for i in range(seg + 1):
        a = math.pi * i / seg
        y, z = math.cos(a), math.sin(a) * scale_z
        ring = []
        for (rr, x) in ((r + thick, -width / 2), (r + thick, width / 2), (r, width / 2), (r, -width / 2)):
            ring.append(bm.verts.new((x, y * rr, z * rr)))
        rings.append(ring)
    for i in range(seg):
        a, b = rings[i], rings[i + 1]
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm)
    o.location = loc
    return link(o, mat, parent, 0.006, 2)


def stud(name, r, loc, mat, parent=None, normal=(0, -1, 0), squash=0.5):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=8, radius=r)
    bmesh.ops.scale(bm, vec=Vector((1, 1, squash)), verts=bm.verts)
    o = mesh_obj(name, bm)
    o.location = loc
    n = Vector(normal).normalized()
    o.rotation_euler = n.to_track_quat("Z", "Y").to_euler()
    return link(o, mat, parent)


def gem(name, r, loc, mat, parent=None, normal=(0, -1, 0), seg=8, crown=0.42, pavilion=0.62, table=0.55):
    """A brilliant-ish cut: a flat table, a sloped crown and a pointed pavilion. Flat facets."""
    bm = bmesh.new()
    top = []
    girdle = []
    for i in range(seg):
        a = math.tau * (i + 0.5) / seg
        top.append(bm.verts.new((math.cos(a) * r * table, math.sin(a) * r * table, r * crown)))
    for i in range(seg * 2):
        a = math.tau * i / (seg * 2)
        girdle.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, 0.0)))
    tip = bm.verts.new((0, 0, -r * pavilion))
    bm.faces.new(top)
    for i in range(seg):
        a, b = top[i], top[(i + 1) % seg]
        g0, g1, g2 = girdle[(2 * i + 1) % (2 * seg)], girdle[(2 * i + 2) % (2 * seg)], girdle[(2 * i + 3) % (2 * seg)]
        bm.faces.new((a, g0, g1))
        bm.faces.new((a, g1, b))
        bm.faces.new((b, g1, g2))
    for i in range(2 * seg):
        bm.faces.new((girdle[(i + 1) % (2 * seg)], girdle[i], tip))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm)
    o.location = loc
    n = Vector(normal).normalized()
    o.rotation_euler = n.to_track_quat("Z", "Y").to_euler()
    return link(o, mat, parent, flat=True)


def crystal(name, r, length, loc, direction, mat, parent=None, tip=0.9):
    """A hexagonal crystal with a pointed tip, growing along `direction`."""
    bm = bmesh.new()
    bottom, top = [], []
    for i in range(6):
        a = math.tau * i / 6
        bottom.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, 0.0)))
        top.append(bm.verts.new((math.cos(a) * r * 0.92, math.sin(a) * r * 0.92, length)))
    apex = bm.verts.new((0, 0, length + r * tip * 1.6))
    bm.faces.new(tuple(reversed(bottom)))
    for i in range(6):
        bm.faces.new((bottom[i], bottom[(i + 1) % 6], top[(i + 1) % 6], top[i]))
        bm.faces.new((top[i], top[(i + 1) % 6], apex))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm)
    o.location = loc
    o.rotation_euler = Vector(direction).normalized().to_track_quat("Z", "Y").to_euler()
    return link(o, mat, parent, flat=True)


def star_gem(name, r, depth, loc, mat, parent=None, normal=(0, -1, 0), inner=0.48):
    """A five-point star cut as a faceted double pyramid (the 5-star crown)."""
    bm = bmesh.new()
    rim = []
    for i in range(10):
        a = math.pi / 2 + math.tau * i / 10
        rr = r if i % 2 == 0 else r * inner
        rim.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, 0.0)))
    front = bm.verts.new((0, 0, depth))
    back = bm.verts.new((0, 0, -depth * 0.6))
    for i in range(10):
        bm.faces.new((rim[i], rim[(i + 1) % 10], front))
        bm.faces.new((rim[(i + 1) % 10], rim[i], back))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm)
    o.location = loc
    n = Vector(normal).normalized()
    o.rotation_euler = n.to_track_quat("Z", "Y").to_euler()
    return link(o, mat, parent, flat=True)


def shield_plate(name, w, h, thick, loc, mat, parent=None, point=0.35):
    """A lock plate: a rounded-top shield pointing down, facing -Y."""
    bm = bmesh.new()
    pts = []
    n = 10
    for i in range(n + 1):
        a = math.pi * i / n
        pts.append((math.cos(a) * w / 2, h / 2 - (1 - math.sin(a)) * h * 0.08))
    pts.append((-w / 2, -h * (0.5 - point)))
    pts.append((0, -h / 2))
    pts.append((w / 2, -h * (0.5 - point)))
    front = [bm.verts.new((x, -thick / 2, z)) for (x, z) in pts]
    back = [bm.verts.new((x, thick / 2, z)) for (x, z) in pts]
    bm.faces.new(front)
    bm.faces.new(tuple(reversed(back)))
    m = len(pts)
    for i in range(m):
        bm.faces.new((front[i], front[(i + 1) % m], back[(i + 1) % m], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm)
    o.location = loc
    return link(o, mat, parent, 0.008, 2, angle=30)


def keyhole(name, loc, mat, parent=None, s=1.0):
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=16, radius=0.022 * s)
    for v in bm.verts:
        v.co = Vector((v.co.x, 0.0, v.co.y + 0.012 * s))
    o = mesh_obj(name, bm)
    o.location = loc
    link(o, mat, parent, flat=True)
    slot = box(name + "_slot", (0.016 * s, 0.004, 0.04 * s), (loc[0], loc[1], loc[2] - 0.012 * s), mat, parent, 0.0)
    return o


def torus(name, major, minor, loc, mat, parent=None, seg=48, ring=8, normal=(0, -1, 0)):
    bm = bmesh.new()
    rings = []
    for i in range(seg):
        a = math.tau * i / seg
        c = Vector((math.cos(a) * major, math.sin(a) * major, 0.0))
        out = Vector((math.cos(a), math.sin(a), 0.0))
        rr = []
        for j in range(ring):
            b = math.tau * j / ring
            rr.append(bm.verts.new(c + out * math.cos(b) * minor + Vector((0, 0, math.sin(b) * minor))))
        rings.append(rr)
    for i in range(seg):
        a, b = rings[i], rings[(i + 1) % seg]
        for j in range(ring):
            bm.faces.new((a[j], b[j], b[(j + 1) % ring], a[(j + 1) % ring]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm)
    o.location = loc
    o.rotation_euler = Vector(normal).normalized().to_track_quat("Z", "Y").to_euler()
    return link(o, mat, parent)


def strip(name, p, q, width, thick, mat, parent=None):
    """A thin bar from p to q lying on a plane facing -Y (rune strokes, filigree)."""
    p, q = Vector(p), Vector(q)
    seg = q - p
    b = box(name, (seg.length + width * 0.6, thick, width), tuple((p + q) / 2), mat, parent, 0.0)
    b.rotation_euler = (0, -math.atan2(seg.z, seg.x), 0)
    return b


def hollow_body(prefix, w, d, h, wall, outer, inner, floor_glow, parent=None, bevel=0.025,
                plank_rows=0, gap_mat=None):
    """The chest body as four walls and a floor so the inside is a real cavity."""
    parts = []
    t = wall
    if plank_rows > 0:
        # Stacked planks: the crate's walls read as boards with dark joints between.
        ph = h / plank_rows
        for row in range(plank_rows):
            z = ph * row + ph / 2
            hh = ph - 0.012
            parts.append(box(f"{prefix}_front{row}", (w, t, hh), (0, -d / 2 + t / 2, z), outer, parent, 0.012))
            parts.append(box(f"{prefix}_back{row}", (w, t, hh), (0, d / 2 - t / 2, z), outer, parent, 0.012))
            side_mat = bpy.data.materials.get(outer.name + "_side", outer)
            parts.append(box(f"{prefix}_left{row}", (t, d - 2 * t + 0.002, hh), (-w / 2 + t / 2, 0, z), side_mat, parent, 0.010))
            parts.append(box(f"{prefix}_right{row}", (t, d - 2 * t + 0.002, hh), (w / 2 - t / 2, 0, z), side_mat, parent, 0.010))
        # The dark core behind the joints.
        box(f"{prefix}_core_f", (w - 0.02, t * 0.4, h - 0.01), (0, -d / 2 + t * 0.55, h / 2), gap_mat, parent, 0.0)
        box(f"{prefix}_core_b", (w - 0.02, t * 0.4, h - 0.01), (0, d / 2 - t * 0.55, h / 2), gap_mat, parent, 0.0)
        box(f"{prefix}_core_l", (t * 0.4, d - 0.02, h - 0.01), (-w / 2 + t * 0.55, 0, h / 2), gap_mat, parent, 0.0)
        box(f"{prefix}_core_r", (t * 0.4, d - 0.02, h - 0.01), (w / 2 - t * 0.55, 0, h / 2), gap_mat, parent, 0.0)
    else:
        parts.append(box(f"{prefix}_front", (w, t, h), (0, -d / 2 + t / 2, h / 2), outer, parent, bevel))
        parts.append(box(f"{prefix}_back", (w, t, h), (0, d / 2 - t / 2, h / 2), outer, parent, bevel))
        parts.append(box(f"{prefix}_left", (t, d - 2 * t + 0.004, h), (-w / 2 + t / 2, 0, h / 2), outer, parent, bevel * 0.6))
        parts.append(box(f"{prefix}_right", (t, d - 2 * t + 0.004, h), (w / 2 - t / 2, 0, h / 2), outer, parent, bevel * 0.6))
    # Inner lining (a little lighter than the shell so the cavity has form when lit).
    box(f"{prefix}_lining_f", (w - 2 * t, 0.01, h - 0.06), (0, -d / 2 + t + 0.005, h / 2 + 0.02), inner, parent, 0.0)
    box(f"{prefix}_lining_b", (w - 2 * t, 0.01, h - 0.06), (0, d / 2 - t - 0.005, h / 2 + 0.02), inner, parent, 0.0)
    box(f"{prefix}_lining_l", (0.01, d - 2 * t, h - 0.06), (-w / 2 + t + 0.005, 0, h / 2 + 0.02), inner, parent, 0.0)
    box(f"{prefix}_lining_r", (0.01, d - 2 * t, h - 0.06), (w / 2 - t - 0.005, 0, h / 2 + 0.02), inner, parent, 0.0)
    box(f"{prefix}_floor", (w - 0.01, d - 0.01, 0.07), (0, 0, 0.035), outer, parent, 0.01)
    # The treasure light: an emissive bed inside, a little below the rim.
    box(f"{prefix}_glow", (w - 2 * t - 0.02, d - 2 * t - 0.02, 0.02), (0, 0, h * 0.42), floor_glow, parent, 0.0)
    return parts


# --------------------------------------------------------------------------- #
# the five boxes
# --------------------------------------------------------------------------- #
class Kit:
    """What one tier's build hands back: the body root, the lid hinge and the lights."""

    def __init__(self):
        self.body: list = []
        self.lid: list = []
        self.hinge = None
        self.light_color = (1, 1, 1)
        self.light_power = 60.0
        self.top = H


def new_hinge(z_hinge, d):
    e = bpy.data.objects.new("hinge", None)
    bpy.context.scene.collection.objects.link(e)
    e.location = (0, d / 2, z_hinge)
    return e


def collect(prefix_list):
    return [o for o in bpy.context.scene.objects if any(o.name.startswith(p) for p in prefix_list)]


def build_tier1(k: Kit):
    """1-star: a plain oak crate with iron corners and straps, a green glass stud."""
    oak = wood("oak", "#b9773e", "#86522a", grain=3.0, rings=0.6)
    wood("oak_side", "#b07038", "#7d4b25", grain=3.0, rings=0.6, along_y=True)
    oak2 = wood("oak2", "#a96c36", "#7a4824", grain=3.4, rings=0.6)
    gap = material("gap", "#2a1a10", rough=0.9)
    inner = material("inner1", "#5a3a22", rough=0.85)
    iron = material("iron", "#6f7680", metal=0.9, rough=0.38)
    iron_dark = material("iron_dark", "#3c4047", metal=0.8, rough=0.5)
    glow = material("glow1", "#000000", emit="#b8f0a8", strength=5.0)
    green = material("gem1", "#58c66a", rough=0.12, emit="#79c07a", strength=1.2, spec=0.9)
    w, d, h = 0.96, 0.66, 0.46
    hollow_body("b1", w, d, h, 0.07, oak, inner, glow, plank_rows=3, gap_mat=gap)
    # Iron L corners on the four vertical edges.
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(f"b1_corner{sx}{sy}a", (0.11, 0.02, h + 0.02), (sx * (w / 2 - 0.045), sy * (d / 2 + 0.006), h / 2), iron, None, 0.008)
            box(f"b1_corner{sx}{sy}b", (0.02, 0.11, h + 0.02), (sx * (w / 2 + 0.006), sy * (d / 2 - 0.045), h / 2), iron, None, 0.008)
            for zz in (0.08, h - 0.08):
                stud(f"b1_rv{sx}{sy}{zz}", 0.014, (sx * (w / 2 - 0.05), sy * (d / 2 + 0.018), zz), iron_dark, None, (0, sy, 0))
    # Two straps down the front.
    for sx in (-1, 1):
        box(f"b1_strap{sx}", (0.075, 0.018, h - 0.02), (sx * 0.24, -d / 2 - 0.006, h / 2), iron, None, 0.006)
        for zz in (0.1, 0.24, 0.38):
            stud(f"b1_srv{sx}{zz}", 0.013, (sx * 0.24, -d / 2 - 0.017, zz), iron_dark, None, (0, -1, 0))
    # Hasp plate on the body front, under the lid's tongue.
    box("b1_hasp", (0.13, 0.02, 0.15), (0, -d / 2 - 0.008, h - 0.09), iron_dark, None, 0.01)
    keyhole("b1_key", (0, -d / 2 - 0.019, h - 0.10), gap)
    k.hinge = new_hinge(h, d)
    lid_d = d + 0.03
    # Flat lid of three boards (along X) with an iron rim and the straps continued.
    for i in range(3):
        bw = lid_d / 3
        y = -lid_d + bw * (i + 0.5)
        box(f"l1_board{i}", (w + 0.03, bw - 0.01, 0.12), (0, y + 0.015, 0.06), oak2 if i % 2 else oak, k.hinge, 0.014)
    box("l1_core", (w + 0.0, lid_d - 0.03, 0.10), (0, -lid_d / 2 + 0.015, 0.055), gap, k.hinge, 0.0)
    for sx in (-1, 1):
        box(f"l1_strap{sx}", (0.075, lid_d + 0.01, 0.018), (sx * 0.24, -lid_d / 2 + 0.015, 0.125), iron, k.hinge, 0.006)
        box(f"l1_strapf{sx}", (0.075, 0.018, 0.13), (sx * 0.24, -lid_d + 0.008, 0.06), iron, k.hinge, 0.006)
        for yy in (-0.12, -0.36, -0.6):
            stud(f"l1_rv{sx}{yy}", 0.013, (sx * 0.24, yy + 0.015, 0.136), iron_dark, k.hinge, (0, 0, 1))
    # The hasp tongue hanging over the lock, with the green glass stud.
    box("l1_tongue", (0.09, 0.022, 0.12), (0, -lid_d + 0.004, 0.005), iron, k.hinge, 0.008)
    gem("l1_gem", 0.045, (0, -lid_d - 0.016, 0.035), green, k.hinge, (0, -1, 0.1))
    k.light_color = lin("#b8f0a8")
    k.light_power = 55.0
    k.top = h + 0.13


def build_tier2(k: Kit):
    """2-star: blue-painted chest with a barrel lid, steel bands and a sapphire lock."""
    paint = material("paint2", "#3a6ac0", rough=0.48, flat_noise=0.35, noise_scale=9.0, dark="#2c529a", coat=0.35)
    inner = velvet("inner2", "#27508f")
    steel = material("steel2", "#c4ced9", metal=1.0, rough=0.28)
    steel_dark = material("steel2d", "#7d8a99", metal=1.0, rough=0.35)
    glow = material("glow2", "#000000", emit="#9cc4ff", strength=5.0)
    gap = material("gap2", "#0d1626", rough=0.9)
    sapphire = material("gem2", "#2f6fe8", rough=0.06, emit="#4a7fe0", strength=1.6, spec=1.0)
    w, d, h = 1.0, 0.68, 0.48
    hollow_body("b2", w, d, h, 0.075, paint, inner, glow, bevel=0.03)
    # Vertical plank grooves on the front.
    for x in (-0.3, -0.1, 0.1, 0.3):
        box(f"b2_groove{x}", (0.008, 0.006, h - 0.1), (x, -d / 2 - 0.001, h / 2), gap, None, 0.0)
    # Steel trims: bottom band, top rim band, corner caps.
    box("b2_base", (w + 0.03, d + 0.03, 0.07), (0, 0, 0.035), steel_dark, None, 0.02)
    box("b2_rimf", (w + 0.02, 0.03, 0.05), (0, -d / 2 - 0.004, h - 0.025), steel, None, 0.012)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(f"b2_cap{sx}{sy}", (0.1, 0.1, h + 0.04), (sx * (w / 2 - 0.035), sy * (d / 2 - 0.035), h / 2 + 0.005), steel, None, 0.03)
            for zz in (0.12, 0.26, 0.4):
                stud(f"b2_rv{sx}{sy}{zz}", 0.012, (sx * (w / 2 - 0.035), sy * (d / 2 + 0.017) if sy < 0 else sy * (d / 2 + 0.017), zz), steel_dark, None, (0, sy, 0))
    # Lock plate.
    shield_plate("b2_lock", 0.2, 0.22, 0.03, (0, -d / 2 - 0.012, h - 0.11), steel, None)
    keyhole("b2_key", (0, -d / 2 - 0.03, h - 0.135), gap)
    k.hinge = new_hinge(h, d)
    r = (d + 0.02) / 2
    lid_y = -r + 0.01
    half_cylinder("l2_lid", r, w + 0.02, (0, lid_y, 0.0), paint, k.hinge, bevel=0.02, scale_z=0.78)
    lid_lining("l2", w - 0.08, 2 * r - 0.08, lid_y, -0.007, inner, k.hinge)
    for x in (-0.34, 0.0, 0.34):
        band_arc(f"l2_band{x}", r, 0.07, 0.022, (x, lid_y, 0.0), steel, k.hinge, scale_z=0.78)
    # Front lip band and the lid's lock tongue with the sapphire.
    box("l2_lip", (w + 0.03, 0.035, 0.05), (0, lid_y - r - 0.004, 0.025), steel, k.hinge, 0.012)
    shield_plate("l2_tongue", 0.14, 0.13, 0.026, (0, lid_y - r - 0.014, 0.0), steel_dark, k.hinge, point=0.4)
    gem("l2_gem", 0.058, (0, lid_y - r - 0.036, 0.02), sapphire, k.hinge, (0, -1, 0.15))
    for x in (-0.42, 0.42):
        stud(f"l2_rv{x}", 0.013, (x, lid_y - r - 0.022, 0.025), steel_dark, k.hinge, (0, -1, 0))
    k.light_color = lin("#9cc4ff")
    k.light_power = 60.0
    k.top = h + r * 0.78 + 0.03


def build_tier3(k: Kit):
    """3-star: violet lacquer with silver filigree, glowing runes and amethyst clusters."""
    lacquer = material("lacq3", "#6534a6", rough=0.32, coat=0.6, flat_noise=0.3, noise_scale=7.0, dark="#4a2380")
    inner = velvet("inner3", "#6a34a8")
    silver = material("silver3", "#e2e6f2", metal=1.0, rough=0.22)
    silver_dark = material("silver3d", "#9aa0b8", metal=1.0, rough=0.3)
    rune = material("rune3", "#000000", emit="#e58cff", strength=4.0)
    glow = material("glow3", "#000000", emit="#e2a0ff", strength=5.5)
    gap = material("gap3", "#14091f", rough=0.9)
    amethyst = material("gem3", "#b04ee0", rough=0.05, emit="#c15ce0", strength=1.4, spec=1.0)
    amethyst2 = material("gem3b", "#8f3dcc", rough=0.08, emit="#a54ad8", strength=0.9, spec=1.0)
    w, d, h = 1.02, 0.7, 0.5
    hollow_body("b3", w, d, h, 0.075, lacquer, inner, glow, bevel=0.035)
    box("b3_base", (w + 0.04, d + 0.04, 0.075), (0, 0, 0.037), silver_dark, None, 0.025)
    box("b3_rimf", (w + 0.02, 0.03, 0.045), (0, -d / 2 - 0.004, h - 0.022), silver, None, 0.012)
    # Silver filigree frame on the front panel + a rune circle inside it.
    for x in (-0.36, 0.36):
        box(f"b3_fv{x}", (0.03, 0.02, h - 0.17), (x, -d / 2 - 0.006, h / 2 + 0.01), silver, None, 0.008)
    box("b3_fh", (0.72, 0.02, 0.03), (0, -d / 2 - 0.006, 0.105), silver, None, 0.008)
    for x in (-0.22, 0.22):
        c = Vector((x, -d / 2 - 0.006, 0.245))
        torus(f"b3_rune_ring{x}", 0.105, 0.007, tuple(c), rune, None)
        torus(f"b3_rune_ring_in{x}", 0.05, 0.0045, tuple(c), rune, None)
        # A four-point sparkle: the game's star motif, drawn as four slim rhombi.
        for a in range(4):
            ang = math.tau * a / 4 + math.pi / 2
            tip = c + Vector((math.cos(ang) * 0.088, 0, math.sin(ang) * 0.088))
            side = Vector((math.cos(ang + math.pi / 2), 0, math.sin(ang + math.pi / 2))) * 0.018
            strip(f"b3_rune_s{x}{a}a", c + side, tip, 0.007, 0.004, rune)
            strip(f"b3_rune_s{x}{a}b", c - side, tip, 0.007, 0.004, rune)
            dot = c + Vector((math.cos(ang + math.pi / 4) * 0.128, 0, math.sin(ang + math.pi / 4) * 0.128))
            stud(f"b3_rune_dot{x}{a}", 0.009, tuple(dot), rune, None, (0, -1, 0), 0.6)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(f"b3_cap{sx}{sy}", (0.1, 0.1, h + 0.05), (sx * (w / 2 - 0.035), sy * (d / 2 - 0.035), h / 2 + 0.01), silver, None, 0.035)
            stud(f"b3_capgem{sx}{sy}", 0.022, (sx * (w / 2 - 0.035), sy * (d / 2 + 0.018), h * 0.55), amethyst2, None, (0, sy, 0), squash=0.7)
    shield_plate("b3_lock", 0.22, 0.24, 0.032, (0, -d / 2 - 0.013, h - 0.12), silver, None)
    keyhole("b3_key", (0, -d / 2 - 0.031, h - 0.15), gap)
    k.hinge = new_hinge(h, d)
    r = (d + 0.02) / 2
    lid_y = -r + 0.01
    half_cylinder("l3_lid", r, w + 0.02, (0, lid_y, 0.0), lacquer, k.hinge, bevel=0.025, scale_z=0.85)
    lid_lining("l3", w - 0.08, 2 * r - 0.08, lid_y, -0.007, inner, k.hinge)
    for x in (-0.36, 0.36):
        band_arc(f"l3_band{x}", r, 0.06, 0.024, (x, lid_y, 0.0), silver, k.hinge, scale_z=0.85)
    box("l3_lip", (w + 0.03, 0.036, 0.05), (0, lid_y - r - 0.004, 0.025), silver, k.hinge, 0.012)
    gem("l3_gem", 0.068, (0, lid_y - r - 0.036, 0.034), amethyst, k.hinge, (0, -1, 0.2))
    shield_plate("l3_tongue", 0.15, 0.14, 0.024, (0, lid_y - r - 0.012, 0.01), silver_dark, k.hinge, point=0.4)
    # Amethyst clusters breaking out of the lid top.
    top_z = r * 0.85
    cl = [
        (0.0, -0.02, 0.075, 0.26, (0.0, -0.2, 1.0)), (-0.1, 0.03, 0.055, 0.19, (-0.55, 0.1, 1.0)),
        (0.105, 0.02, 0.058, 0.2, (0.6, 0.05, 1.0)), (0.0, 0.09, 0.05, 0.16, (0.05, 0.6, 1.0)),
        (-0.06, -0.09, 0.042, 0.13, (-0.35, -0.7, 1.0)), (0.07, -0.08, 0.04, 0.12, (0.5, -0.6, 1.0)),
    ]
    for i, (x, y, rr, ln, dirv) in enumerate(cl):
        crystal(f"l3_cr{i}", rr, ln, (x, lid_y + y, top_z - 0.03), dirv, amethyst if i % 2 == 0 else amethyst2, k.hinge)
    for sx in (-1, 1):
        for i, (x, y, rr, ln, dirv) in enumerate(cl[:3]):
            crystal(f"l3_crs{sx}{i}", rr * 0.7, ln * 0.6, (sx * 0.43 + x * 0.6, lid_y + y * 0.8, top_z * 0.62), (dirv[0] + sx * 0.6, dirv[1], 1.0), amethyst2, k.hinge)
    k.light_color = lin("#e2a0ff")
    k.light_power = 70.0
    k.top = h + r * 0.85 + 0.3


def build_tier4(k: Kit):
    """4-star: a royal chest plated in gold, ember-orange enamel insets, amber gems, a crown."""
    gold = material("gold4", "#ffc34f", metal=1.0, rough=0.22)
    gold_dark = material("gold4d", "#c98a2a", metal=1.0, rough=0.28)
    enamel = material("enamel4", "#d9521f", rough=0.22, coat=1.0)
    inner = velvet("inner4", "#b3262a")
    glow = material("glow4", "#000000", emit="#ffc068", strength=6.0)
    gap = material("gap4", "#200a05", rough=0.9)
    amber = material("gem4", "#ff8a1e", rough=0.04, emit="#ff9a3c", strength=1.5, spec=1.0, coat=1.0)
    ruby = material("gem4r", "#ff4a2a", rough=0.05, emit="#ff5a3a", strength=0.8, spec=1.0, coat=1.0)
    w, d, h = 1.06, 0.72, 0.52
    hollow_body("b4", w, d, h, 0.08, gold_dark, inner, glow, bevel=0.03)
    # Enamel insets on the front and the visible side, framed in raised gold.
    for x in (-0.25, 0.25):
        box(f"b4_inset{x}", (0.36, 0.012, h - 0.2), (x, -d / 2 - 0.004, h / 2 + 0.01), enamel, None, 0.01)
        box(f"b4_frameT{x}", (0.4, 0.024, 0.032), (x, -d / 2 - 0.01, h - 0.085), gold, None, 0.01)
        box(f"b4_frameB{x}", (0.4, 0.024, 0.032), (x, -d / 2 - 0.01, 0.105), gold, None, 0.01)
        for xx in (x - 0.185, x + 0.185):
            box(f"b4_frameS{x}{xx}", (0.032, 0.024, h - 0.16), (xx, -d / 2 - 0.01, h / 2 + 0.01), gold, None, 0.01)
    for y in (-0.15, 0.15):
        box(f"b4_sinset{y}", (0.012, 0.24, h - 0.2), (w / 2 + 0.004, y, h / 2 + 0.01), enamel, None, 0.01)
        box(f"b4_sframeT{y}", (0.024, 0.28, 0.032), (w / 2 + 0.01, y, h - 0.085), gold, None, 0.01)
        box(f"b4_sframeB{y}", (0.024, 0.28, 0.032), (w / 2 + 0.01, y, 0.105), gold, None, 0.01)
    box("b4_base", (w + 0.07, d + 0.07, 0.085), (0, 0, 0.04), gold, None, 0.032)
    box("b4_rimf", (w + 0.03, 0.038, 0.06), (0, -d / 2 - 0.008, h - 0.03), gold, None, 0.016)
    for x in (-0.25, 0.25):
        gem(f"b4_medgem{x}", 0.04, (x, -d / 2 - 0.02, 0.27), ruby, None, (0, -1, 0))
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(f"b4_cap{sx}{sy}", (0.12, 0.12, h + 0.06), (sx * (w / 2 - 0.035), sy * (d / 2 - 0.035), h / 2 + 0.02), gold, None, 0.045)
            stud(f"b4_foot{sx}{sy}", 0.068, (sx * (w / 2 - 0.035), sy * (d / 2 - 0.035), -0.03), gold_dark, None, (0, 0, 1), squash=0.85)
            stud(f"b4_capgem{sx}{sy}", 0.024, (sx * (w / 2 - 0.035), sy * (d / 2 + 0.026), h * 0.6), amber, None, (0, sy, 0), squash=0.7)
    shield_plate("b4_lock", 0.27, 0.29, 0.04, (0, -d / 2 - 0.018, h - 0.13), gold, None)
    keyhole("b4_key", (0, -d / 2 - 0.04, h - 0.18), gap, None, 1.1)
    k.hinge = new_hinge(h, d)
    r = (d + 0.02) / 2
    lid_y = -r + 0.01
    half_cylinder("l4_lid", r, w + 0.02, (0, lid_y, 0.0), enamel, k.hinge, bevel=0.025, scale_z=0.92)
    lid_lining("l4", w - 0.08, 2 * r - 0.08, lid_y, -0.007, inner, k.hinge)
    for x in (-0.42, -0.14, 0.14, 0.42):
        band_arc(f"l4_band{x}", r, 0.085 if abs(x) > 0.2 else 0.07, 0.03, (x, lid_y, 0.0), gold, k.hinge, scale_z=0.92)
    box("l4_lip", (w + 0.05, 0.045, 0.065), (0, lid_y - r - 0.008, 0.032), gold, k.hinge, 0.016)
    for x in (-0.28, 0.28):
        stud(f"l4_cab{x}", 0.03, (x, lid_y - r - 0.034, 0.034), amber, k.hinge, (0, -1, 0), squash=0.7)
    shield_plate("l4_tongue", 0.18, 0.17, 0.03, (0, lid_y - r - 0.02, 0.014), gold_dark, k.hinge, point=0.4)
    gem("l4_gem", 0.075, (0, lid_y - r - 0.046, 0.044), amber, k.hinge, (0, -1, 0.2))
    # The crown crest: a gold ring with five points and an amber heart.
    top_z = r * 0.92
    cylinder("l4_crest_base", 0.1, 0.05, (0, lid_y, top_z + 0.01), gold_dark, k.hinge, axis="Z", seg=24, bevel=0.012)
    torus("l4_crest_ring", 0.095, 0.018, (0, lid_y, top_z + 0.04), gold, k.hinge, normal=(0, 0, 1))
    for i in range(5):
        a = math.pi * (0.1 + 0.8 * i / 4.0)
        x = math.cos(a) * 0.09
        y = -math.sin(a) * 0.05
        tall = 0.15 if i == 2 else (0.12 if i % 2 == 0 else 0.1)
        cylinder(f"l4_crest_spike{i}", 0.02, tall, (x, lid_y + y, top_z + 0.04 + tall / 2), gold, k.hinge,
                 axis="Z", seg=8, r2=0.004)
        stud(f"l4_crest_ball{i}", 0.02 if i != 2 else 0.032, (x, lid_y + y, top_z + 0.045 + tall), amber if i == 2 else gold, k.hinge, (0, -1, 0.3), squash=1.0)
    k.light_color = lin("#ffc068")
    k.light_power = 80.0
    k.top = h + top_z + 0.22


def build_tier5(k: Kit):
    """5-star: a white-gold casket with prismatic crystal panels and a star-cut crown."""
    plat = material("plat5", "#ffe6b3", metal=1.0, rough=0.14)
    plat_dark = material("plat5d", "#e0c387", metal=1.0, rough=0.2)
    inner = velvet("inner5", "#c9b48c", sheen=0.5, rough=0.5)
    glow = material("glow5", "#000000", emit="#ffe9b8", strength=5.0)
    # Mostly clear facets of different depth, a few spectral ones ("fire"): a crystal, not a quilt.
    tints = [("#dcecfb", 0.10), ("#9db8dd", 0.04), ("#6f8fbf", 0.02), ("#f4f9ff", 0.16), ("#b9d3f0", 0.06),
             ("#ff8fd0", 0.30), ("#ffd86a", 0.30), ("#6fd2ff", 0.30), ("#8ea6d6", 0.03), ("#b89aff", 0.26)]
    crystals = [material(f"cr5_{i}", t, rough=0.03, emit=t, strength=e, spec=1.0, coat=1.0) for i, (t, e) in enumerate(tints)]
    diamond = material("gem5", "#efe2b4", rough=0.04, emit="#fff0b8", strength=0.12, spec=1.0, coat=1.0)
    w, d, h = 1.06, 0.72, 0.54
    hollow_body("b5", w, d, h, 0.08, plat_dark, inner, glow, bevel=0.03)
    box("b5_base", (w + 0.08, d + 0.08, 0.085), (0, 0, 0.04), plat, None, 0.036)
    box("b5_rimf", (w + 0.03, 0.038, 0.055), (0, -d / 2 - 0.008, h - 0.027), plat, None, 0.016)

    def facet_panel(name, cx, cy, cz, pw, ph, normal, offset):
        bm = bmesh.new()
        hw, hh = pw / 2, ph / 2
        corners = [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]
        mids = [(0, -hh), (hw, 0), (0, hh), (-hw, 0)]
        vs_c = [bm.verts.new((x, 0, z)) for (x, z) in corners]
        vs_m = [bm.verts.new((x, 0, z)) for (x, z) in mids]
        apex = bm.verts.new((0, -0.05, 0))
        inner_pts = [bm.verts.new((x * 0.5, -0.03, z * 0.5)) for (x, z) in corners]
        for i in range(4):
            c0, m0, c1 = vs_c[i], vs_m[i], vs_c[(i + 1) % 4]
            ip0, ip1 = inner_pts[i], inner_pts[(i + 1) % 4]
            bm.faces.new((c0, m0, ip0))
            bm.faces.new((m0, c1, ip1))
            bm.faces.new((m0, ip1, ip0))
            bm.faces.new((ip0, ip1, apex))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        o = mesh_obj(name, bm)
        o.location = (cx, cy, cz)
        o.rotation_euler = Vector((0, -1, 0)).rotation_difference(Vector(normal)).to_euler()
        for mat in crystals:
            o.data.materials.append(mat)
        # Same rule as the dome: mostly clear facets of three depths, the odd spectral one.
        for fi, poly in enumerate(o.data.polygons):
            pick = ((fi * 7 + offset * 3 + 1) * 2654435761 >> 7) % 10
            if pick >= 8:
                poly.material_index = (5, 6, 7, 9)[(fi + offset) % 4]
            elif fi % 4 == 3:
                poly.material_index = (0, 3)[pick % 2]          # the raised centre facets catch light
            else:
                poly.material_index = (1, 4, 2, 8)[pick % 4]
        return o
    for i, x in enumerate((-0.27, 0.0, 0.27)):
        facet_panel(f"b5_panel{i}", x, -d / 2 - 0.004, h * 0.5 + 0.01, 0.22, h - 0.2, (0, -1, 0), i * 2)
    for i, y in enumerate((-0.15, 0.15)):
        facet_panel(f"b5_side{i}", w / 2 + 0.004, y, h * 0.5 + 0.01, 0.24, h - 0.2, (1, 0, 0), i * 3 + 1)
        facet_panel(f"b5_sidel{i}", -w / 2 - 0.004, y, h * 0.5 + 0.01, 0.24, h - 0.2, (-1, 0, 0), i + 4)
    for x in (-0.135, 0.135):
        box(f"b5_mull{x}", (0.034, 0.03, h - 0.14), (x, -d / 2 - 0.01, h / 2 + 0.01), plat, None, 0.012)
    box("b5_mullh", (w - 0.1, 0.03, 0.034), (0, -d / 2 - 0.01, 0.095), plat, None, 0.012)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(f"b5_cap{sx}{sy}", (0.11, 0.11, h + 0.07), (sx * (w / 2 - 0.03), sy * (d / 2 - 0.03), h / 2 + 0.025), plat, None, 0.05)
            gem(f"b5_capgem{sx}{sy}", 0.032, (sx * (w / 2 - 0.03), sy * (d / 2 + 0.03), h * 0.62), diamond, None, (0, sy, 0))
            cylinder(f"b5_foot{sx}{sy}", 0.055, 0.09, (sx * (w / 2 - 0.03), sy * (d / 2 - 0.03), -0.045), plat_dark, None, axis="Z", seg=16, r2=0.032, bevel=0.012)
    cylinder("b5_lock", 0.11, 0.035, (0, -d / 2 - 0.02, h - 0.14), plat, None, axis="Y", seg=32, bevel=0.012)
    star_gem("b5_lockstar", 0.085, 0.035, (0, -d / 2 - 0.04, h - 0.14), diamond, None, (0, -1, 0))
    k.hinge = new_hinge(h, d)
    r = (d + 0.02) / 2
    lid_y = -r + 0.01
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=6, radius=1.0)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=(0, 0, 0), plane_no=(0, 0, -1), clear_outer=True)
    bmesh.ops.holes_fill(bm, edges=bm.edges[:], sides=0)
    bmesh.ops.scale(bm, vec=Vector(((w - 0.03) / 2, r, r * 1.08)), verts=bm.verts)
    dome = mesh_obj("l5_dome", bm)
    dome.location = (0, lid_y, 0.03)
    dome.parent = k.hinge
    for mat in crystals:
        dome.data.materials.append(mat)
    for fi, poly in enumerate(dome.data.polygons):
        hz = poly.center.z / (r * 1.08)
        pick = ((fi * 13 + 5) * 2654435761 >> 9) % 10
        if pick >= 7:
            poly.material_index = (5, 6, 7, 9)[pick % 4]       # spectral "fire"
        elif hz < 0.3:
            poly.material_index = (2, 8)[pick % 2]             # deep periwinkle at the girdle
        elif hz < 0.7:
            poly.material_index = (1, 4)[pick % 2]
        else:
            poly.material_index = (0, 3)[pick % 2]             # bright crown
    box("l5_frame", (w + 0.05, d + 0.05, 0.065), (0, lid_y, 0.03), plat, k.hinge, 0.022)
    lid_lining("l5", w - 0.06, d - 0.04, lid_y, -0.009, inner, k.hinge)
    for x in (-0.27, 0.27):
        band_arc(f"l5_band{x}", r * 1.0, 0.04, 0.022, (x, lid_y, 0.03), plat, k.hinge, scale_z=1.08)
    band_arc("l5_bandc", r * 1.0, 0.05, 0.026, (0.0, lid_y, 0.03), plat, k.hinge, scale_z=1.08)
    top_z = 0.03 + r * 1.08
    cylinder("l5_ped", 0.07, 0.06, (0, lid_y, top_z + 0.015), plat_dark, k.hinge, axis="Z", seg=20, r2=0.045, bevel=0.012)
    star_gem("l5_star", 0.16, 0.06, (0, lid_y - 0.01, top_z + 0.19), diamond, k.hinge, (0, -1, 0.12))
    for sx in (-1, 1):
        crystal(f"l5_spire{sx}", 0.026, 0.09, (sx * 0.1, lid_y, top_z - 0.01), (sx * 0.55, 0, 1.0), crystals[6 if sx > 0 else 5], k.hinge)
        crystal(f"l5_spire2{sx}", 0.018, 0.05, (sx * 0.16, lid_y + 0.03, top_z - 0.04), (sx * 0.9, 0.2, 1.0), crystals[7 if sx > 0 else 9], k.hinge)
    box("l5_lip", (w + 0.05, 0.04, 0.055), (0, lid_y - r - 0.014, 0.03), plat, k.hinge, 0.016)
    star_gem("l5_lipstar", 0.055, 0.025, (0, lid_y - r - 0.04, 0.032), diamond, k.hinge, (0, -1, 0))
    k.light_color = lin("#ffe7b5")
    k.light_power = 55.0
    k.top = top_z + 0.36


def lid_lining(prefix, w, depth, y_center, z, mat, hinge):
    """The inside of the lid: a soft lining the treasure light falls on when it opens."""
    box(prefix + "_lining", (w, depth, 0.012), (0, y_center, z), mat, hinge, 0.004)
    return


def velvet(name, color, sheen=0.8, rough=0.9):
    m = material(name, color, rough=rough, spec=0.2)
    _set(m.node_tree.nodes["Principled BSDF"], ["Sheen Weight", "Sheen"], sheen)
    return m


BUILDERS = {1: build_tier1, 2: build_tier2, 3: build_tier3, 4: build_tier4, 5: build_tier5}


# --------------------------------------------------------------------------- #
# scene, camera, lights
# --------------------------------------------------------------------------- #
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = RES
    sc.render.resolution_y = RES
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    ee = sc.eevee
    ee.taa_render_samples = SAMPLES
    ee.use_gtao = True
    ee.gtao_distance = 0.25
    ee.gtao_factor = 1.0
    ee.use_ssr = True
    ee.use_soft_shadows = True
    ee.shadow_cube_size = "2048"
    ee.shadow_cascade_size = "2048"
    ee.use_bloom = False
    # A night-studio world: cool blue overhead, a warm low band to put a glint on metal.
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes["Background"]
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(coord.outputs["Generated"], sep.inputs["Vector"])
    half = nt.nodes.new("ShaderNodeMath")
    half.operation = "MULTIPLY_ADD"
    half.inputs[1].default_value = 0.5
    half.inputs[2].default_value = 0.5
    nt.links.new(sep.outputs["Z"], half.inputs[0])
    nt.links.new(half.outputs["Value"], ramp.inputs["Fac"])
    els = ramp.color_ramp.elements
    # The lower half is a lit floor, not a void: front-facing metal (lock plates, bands) reflects
    # it, and a black floor turned every steel or gold plate into a hole.
    els[0].position = 0.18
    els[0].color = (*lin("#3c4552"), 1)
    els[1].position = 1.0
    els[1].color = (*lin("#cfe0f2"), 1)
    for pos, col in ((0.40, "#8a8f98"), (0.47, "#c9b9a2"), (0.52, "#efc994"), (0.6, "#93a9c2")):
        e = els.new(pos)
        e.color = (*lin(col), 1)
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
    return sc


def area_light(name, loc, target, color, power, size):
    l = bpy.data.lights.new(name, "AREA")
    l.energy = power
    l.color = color
    l.size = size
    l.shape = "DISK"
    o = bpy.data.objects.new(name, l)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return o


def setup_camera_and_lights(sc):
    # The portrait rig's angle family: three-quarter from the front right, looking down.
    yaw = math.radians(24.0)
    elev = math.radians(25.0)
    target = Vector((0, 0, 0.47))
    dist = 6.2
    loc = target + Vector((math.sin(yaw) * math.cos(elev), -math.cos(yaw) * math.cos(elev), math.sin(elev))) * dist
    cam = bpy.data.cameras.new("cam")
    cam.lens = 85
    cam.sensor_width = 36
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    co.location = loc
    co.rotation_euler = (target - loc).to_track_quat("-Z", "Y").to_euler()
    sc.camera = co
    area_light("key", (-2.6, -3.2, 3.6), (0, 0, 0.4), lin("#fff0d9"), 900.0, 2.4)
    area_light("fill", (3.2, -2.2, 1.2), (0, 0, 0.4), lin("#a5cdff"), 170.0, 2.5)
    area_light("rim", (1.6, 3.0, 2.6), (0, 0, 0.5), lin("#9fdcff"), 800.0, 1.6)
    area_light("rim2", (-2.4, 2.4, 1.8), (0, 0, 0.5), lin("#c9b6ff"), 220.0, 1.6)
    return co


def project(sc, cam, p):
    from bpy_extras.object_utils import world_to_camera_view
    co = world_to_camera_view(sc, cam, Vector(p))
    return [co.x * RES, (1.0 - co.y) * RES]


def render(sc, path):
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def build(tier):
    sc = reset_scene()
    cam = setup_camera_and_lights(sc)
    k = Kit()
    BUILDERS[tier](k)
    hinge = k.hinge
    lid_objs = [o for o in sc.objects if o.parent == hinge]
    body_objs = [o for o in sc.objects if o.type == "MESH" and o not in lid_objs]
    # The treasure light inside the cavity: lights the walls and the lid's inner face.
    pl = bpy.data.lights.new("inner", "POINT")
    pl.energy = k.light_power
    pl.color = k.light_color
    pl.shadow_soft_size = 0.12
    plo = bpy.data.objects.new("inner", pl)
    sc.collection.objects.link(plo)
    plo.location = (0, 0, H * 0.62)
    return sc, cam, k, hinge, lid_objs, body_objs, plo


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {"res": RES, "angles": ANGLES, "tiers": {}}
    for tier in TIERS:
        sc, cam, k, hinge, lid_objs, body_objs, plo = build(tier)
        d = os.path.join(OUT, f"tier{tier}")
        os.makedirs(d, exist_ok=True)
        glow_mats = [m for m in bpy.data.materials if m.name.startswith("glow")]
        def set_interior(on: bool):
            plo.hide_render = not on
            for m in glow_mats:
                bsdf = m.node_tree.nodes["Principled BSDF"]
                bsdf.inputs["Emission Strength"].default_value = (6.0 if on else 0.0)
        # Closed (the whole box) for contact sheets and the menu guide.
        set_interior(False)
        hinge.rotation_euler = (0, 0, 0)
        render(sc, os.path.join(d, "closed.png"))
        entry = {
            "anchor": project(sc, cam, (0, 0, 0)),
            "mouth": project(sc, cam, (0, 0, H * 0.9)),
            "top": project(sc, cam, (0, -0.05, k.top)),
            "light": [round(c, 4) for c in k.light_color],
        }
        if not PREVIEW:
            # Body: lid removed, the interior lit.
            set_interior(True)
            for o in lid_objs:
                o.hide_render = True
            render(sc, os.path.join(d, "body.png"))
            for o in lid_objs:
                o.hide_render = False
            # Lid frames: the body held out so the lid is cut where the body is in front.
            for o in body_objs:
                o.is_holdout = True
            for a in ANGLES:
                hinge.rotation_euler = (-math.radians(a), 0, 0)
                render(sc, os.path.join(d, f"lid_{a:03d}.png"))
            for o in body_objs:
                o.is_holdout = False
            # Seam light: the lid lifted a little, interior on and off.
            hinge.rotation_euler = (-math.radians(6), 0, 0)
            set_interior(True)
            render(sc, os.path.join(d, "full_lit.png"))
            set_interior(False)
            render(sc, os.path.join(d, "full_dark.png"))
            hinge.rotation_euler = (0, 0, 0)
        manifest["tiers"][str(tier)] = entry
        print(f"tier {tier} done", flush=True)
    with open(os.path.join(OUT, "render.json"), "w") as f:
        json.dump(manifest, f, indent=1)


main()
