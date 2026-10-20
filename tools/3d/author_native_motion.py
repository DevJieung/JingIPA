#!/usr/bin/env python3
"""Author production locomotion and attack clips for the native hero rigs.

Driver (system python, runs Blender per chunk in parallel):
    python3 tools/3d/author_native_motion.py --ids echo,kari --jobs 4
    python3 tools/3d/author_native_motion.py --all --jobs 4
Inside Blender (what the driver spawns):
    bl -b --factory-startup --python tools/3d/author_native_motion.py -- --ids echo

Each hero's editable source build/character-3d/source/<id>/game.blend is opened.
Geometry, UVs, materials, skin weights, the independent root-bone rig and the
release sockets are left untouched; only the old actions/NLA strips are removed
and three new clips are written and exported to art/models/<id>/<id>.glb:

    IdleLoop  6.0 s   breathing (0.015 h, fast in / slow out), weight shift (0.025 h,
              unloaded leg lifts, 0.04 rad roll), one weapon-led fidget at 3.0-3.6 s
              (bow tilt, rifle shoulder, sword re-grip, staff lift, wrench shoulder;
              tip travel >= 0.2 u), feet planted, zero at 0 and 6 s
    WalkLoop  1 cycle run/walk, left contact at 0 %, right at 50 %, authored at
              full speed; the runtime scrubs it by travelled distance / stride
    Attack    0.0-1.0 s anticipation (time-warped by the actual aim wind) easing IN
              (power 2) to a hold from HOLD_START (0.78-0.80; the rifle shoulders at
              0.25), body dip 0.025 h at the hold, release pose at 1.0 s, then a bigger
              ease-out kick with a pitch kick and back-out returns, settle by 1.5 s

Motion version 4 (2026-10-19, B1 arm twist; v3 2026-10-18 casual overhaul HA1/HA2 beats
kept). Arms: hinge-consistent two-bone IK (the forearm is the upper arm turned about
the elbow hinge, so it never spins about itself; the elbow plane comes from a pole on
top of a twist-free body-carried base, fading out near the reach axis), every hand a
forearm-relative wrist inside soft limits (twist 80 / bend 88 deg), aimed hands pick
the elbow swivel that spares the wrist (with key-to-key memory), bows ride the bow
hand (socket faces the shot at the release), gun holds are searched once per hero so
the forearm carries the aim, blade/tool keys are solved once and slerped, hand paths
arc about the shoulder, the hold is dead still. QA: tools/3d/audit_native_twist.py.
Skin webs (follow-up): Rig.skin_web() poses the shoulder/elbow skin by linear blend
skinning; the free arm of a sword swivels its elbow on it, and a sword hero whose front
guard webs that skin badly (jokull's coat) gets the side guard (sword_guard()).
provenance.json and the native manifest glb_sha256 (+ motion parameters) are updated
under the shared manifest lock. The first run keeps a copy of the previous editable
source as game.motion-v1.blend.

    --candidate DIR   author into a COPY of game.blend under DIR/<id>/ and write the
                      merged GLB to DIR/<id>/<id>.glb + candidate.json; nothing under
                      art/models, the manifest or the editable source is touched
                      (review a clip change before the real batch)
"""
import argparse, json, math, os, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPECS = ROOT / 'tools/3d/native_visual_specs.json'
MANIFEST = ROOT / 'art/models/native_heroes.json'
MOTION_VERSION = 4
FPS = 30
IDLE_SECONDS = 6.0
WALK_FRAMES = 30          # one cycle; frame 30 repeats frame 0
ATTACK_RELEASE = 1.0      # seconds; anticipation is 0..1, release pose at 1.0
ATTACK_SECONDS = 1.5
# HA1: clip time where the anticipation is complete and the hold starts (the runtime's
# HOLD_T per kind must stay inside this hold: bow 0.86, sword/tool 0.85, cast/artillery 0.90).
HOLD_START = {'bow': 0.78, 'sword': 0.78, 'tool': 0.78, 'cast': 0.80, 'artillery': 0.80, 'rifle': 0.25}
HOLD_DIP = 0.025          # body dip (fraction of the height) at the hold
# HA2: idle amplitudes and the fidget window (seconds into the 6 s loop).
BREATH_H = 0.015
SWAY_H = 0.025
SWAY_ROLL = 0.04
LEG_UNLOAD_H = 0.01
IDLE_FIDGET = (3.0, 3.6)
# B1 (motion v4, 2026-10-19): arm solver. Wrist budgets are soft limits (the knee starts
# at 75 % of the value); the audit gate (tools/3d/audit_native_twist.py) allows elbow
# twist <= 30, wrist twist <= 90 and wrist bend <= 100 deg.
WRIST_TWIST_MAX = math.radians(80.0)
WRIST_BEND_MAX = math.radians(88.0)
WRIST_TWIST_SCALE = math.radians(60.0)   # cost scales for the elbow swivel search
WRIST_BEND_SCALE = math.radians(45.0)
SWIVEL_RANGE = math.radians(75.0)        # elbow swivel search window about the pole
SWIVEL_STEP = math.radians(2.0)
SWIVEL_SCALE = math.radians(45.0)        # pole prior: 45 deg of swivel costs one wrist scale
# Tuning aids: NATIVE_MOTION_DEBUG_SIDE=L|R prints the elbow-plane solve per key, with
# NATIVE_MOTION_DEBUG_T=<clip seconds> also the swivel landscape of that attack key.
DEBUG_SIDE = os.environ.get('NATIVE_MOTION_DEBUG_SIDE', '')
DEBUG_T = float(os.environ['NATIVE_MOTION_DEBUG_T']) if os.environ.get('NATIVE_MOTION_DEBUG_T') else None
CURRENT_T = [0.0]
POLE_FADE = (0.15, 0.45)                 # pole share off the reach axis over which it takes over the elbow plane
REST_BEND_GEOMETRIC = math.radians(20.0) # rest elbows bent more than this keep their modelled hinge
# How far each aimed hand lets the elbow swivel off its pole to spare the wrist (0..1).
BOW_AUTO = 0.55
SWORD_AUTO = 0.6
GUN_AUTO = 0.85
SUPPORT_AUTO = 0.6
GUN_ROLL = 0.8            # free roll of a gun about its barrel (rad)
SWIVEL_MEMORY = 3.0       # weight of the previous key's elbow plane in the swivel search
HAND_MEMORY = 0.8         # weight of the previous key's hand rotation (aimed hands)
TWIST_MEMORY = 1.5        # weight of the previous key's wrist twist (aimed hands)
SHOULDER_TWIST_SOFT = math.radians(60.0)  # upper-arm roll against the body the swivel search tolerates freely
# B1 follow-up (2026-10-19): skin webs. Linear blend skinning sheets the skin shared by the
# body and an upper arm (or by the upper arm and its forearm) into a web when the arm turns
# far from where that skin was weighted: jokull's coat hung a sheet below the sword in v4's
# cut, whose upper arm rose in front, and the deformation check's six frames never sampled
# it. Rig.skin_web() measures a pose: the shoulder/elbow skin edges stretched past SKIN_STRETCH.
SKIN_STRETCH = 1.6
SKIN_SCALE = 200.0         # skin web cost units (mean squared overstretch of that skin)
SKIN_WEIGHT = 1.0          # weight of the skin web in the free (off) arm's elbow swivel search
SIDE_GUARD_MARGIN = 0.7    # the side sword guard replaces the front one when its cut stretches the skin this much less
SIDE_GUARD_FRONT_MIN = 120.0   # ... and only where the front guard's mean skin web per sampled pose is this bad
# Bow arm at the draw: reaches along the bladed shoulder line, this far off the shot
# toward the bow side (rad), so the wrist can keep the bow standing with its release
# socket facing the shot (a forearm pointing at the target needs a 90 deg wrist fold).
BOW_ARM_OUT = 0.60
BOW_REACH = 0.97          # share of the bow arm's length at the draw (soft elbow)
BOW_ROLL = 0.30           # free bow roll about the shot axis (rad) the wrist may use
BOW_ANCHOR_Y = 0.72       # draw anchor height (fraction of h): the chibi cheek (v3 0.80 = eye line, inside the head)
BOW_ANCHOR_FRONT = 0.20   # anchor in front of the body axis (fraction of h): clear of the big chibi face

# ----------------------------------------------------------------------------
# Driver mode: plain python spawns Blender processes.
# ----------------------------------------------------------------------------
def _driver() -> None:
    import os, subprocess, concurrent.futures
    p = argparse.ArgumentParser()
    p.add_argument('--ids', default='')
    p.add_argument('--all', action='store_true')
    p.add_argument('--jobs', type=int, default=4)
    p.add_argument('--blender', default=str(Path.home() / '.local/bin/bl'))
    p.add_argument('--candidate', default='', help='author into a copy under DIR/<id>/ (no art/models, manifest or source write)')
    a = p.parse_args()
    specs = json.loads(SPECS.read_text())['heroes']
    ids = [i for i in a.ids.split(',') if i] if a.ids else []
    if a.all:
        ids = [i for i in json.loads(MANIFEST.read_text())['ready_ids'] if i in specs]
    if not ids:
        raise SystemExit('give --ids a,b or --all')
    env = dict(os.environ)
    env.pop('DISPLAY', None)
    log_dir = ROOT / 'build/motion-overhaul/author-logs'
    log_dir.mkdir(parents=True, exist_ok=True)

    def run(cid: str) -> tuple:
        cmd = [a.blender, '-b', '--factory-startup', '--python', str(Path(__file__).resolve()), '--', '--ids', cid]
        if a.candidate: cmd += ['--candidate', str(Path(a.candidate).resolve())]
        result = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=1800)
        log = result.stdout + '\n' + result.stderr
        (log_dir / f'{cid}.log').write_text(log)
        ok = result.returncode == 0 and 'NATIVE_MOTION' in log and 'Traceback' not in log
        summary = next((line for line in log.splitlines() if line.startswith('NATIVE_MOTION')), '')
        return cid, ok, summary

    failures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, a.jobs)) as pool:
        for cid, ok, summary in pool.map(run, ids):
            print(('ok   ' if ok else 'FAIL ') + cid + ' ' + summary, flush=True)
            if not ok: failures.append(cid)
    if failures:
        raise SystemExit('failed: ' + ','.join(failures))


try:
    import bpy  # noqa: F401
    IN_BLENDER = True
except ImportError:
    IN_BLENDER = False

if not IN_BLENDER:
    _driver()
    sys.exit(0)

# ----------------------------------------------------------------------------
# Blender mode
# ----------------------------------------------------------------------------
import bpy, hashlib, shutil, struct, fcntl, os, time
import numpy as np
from mathutils import Vector, Matrix, Quaternion, Euler

TAU = math.tau
C = Matrix.Rotation(math.pi / 2, 4, 'X')   # Godot (x, y up, z back) -> Blender (x, -z, y)
CI = C.inverted()
I4 = Matrix.Identity(4)
FORWARD = Vector((0, 0, -1))


def V(x, y=None, z=None) -> Vector:
    if y is None: return Vector(x)
    return Vector((x, y, z))

def T(v) -> Matrix:
    return Matrix.Translation(Vector(v))

def Rx(a) -> Matrix: return Matrix.Rotation(a, 4, 'X')
def Ry(a) -> Matrix: return Matrix.Rotation(a, 4, 'Y')
def Rz(a) -> Matrix: return Matrix.Rotation(a, 4, 'Z')

def around(point, rotation: Matrix) -> Matrix:
    """Rotate about a model-space point (rotation is a 4x4)."""
    p = Vector(point)
    return T(p) @ rotation @ T(-p)

def rot_between(a: Vector, b: Vector) -> Matrix:
    a = Vector(a); b = Vector(b)
    if a.length < 1e-9 or b.length < 1e-9: return I4
    return a.normalized().rotation_difference(b.normalized()).to_matrix().to_4x4()

def clamp(x, lo, hi): return lo if x < lo else hi if x > hi else x
def clamp01(x): return clamp(x, 0.0, 1.0)
def smooth(t): t = clamp01(t); return t * t * (3 - 2 * t)
def smoother(t): t = clamp01(t); return t * t * t * (t * (6 * t - 15) + 10)
def ease_in(t, p=2.0): return clamp01(t) ** p
def ease_out(t, p=3.0): return 1 - (1 - clamp01(t)) ** p
def back_out(t, k=1.6):
    t = clamp01(t) - 1
    return 1 + t * t * ((k + 1) * t + k)
def linear(t): return clamp01(t)
def damp(t, freq, decay):
    """Damped oscillation starting at 0 with positive velocity."""
    if t <= 0: return 0.0
    return math.exp(-decay * t) * math.sin(TAU * freq * t)
def bump(t):
    """0 -> 1 -> 0 over [0,1], zero slope at both ends."""
    t = clamp01(t); return math.sin(math.pi * t) ** 2
def ant(t): return ease_in(t, 2.0)    # HA1: anticipation keys ease IN to the hold (slow start, snap into the pose)
def breathe(t, period=3.0):
    """HA2 breath: fast inhale, slow exhale; 0 at every period boundary (loop-safe)."""
    u = (t % period) / period
    return math.sin(math.pi * (u ** 0.7))
def fidget(t):
    """HA2: one weapon-led fidget per loop, a bump over IDLE_FIDGET, zero elsewhere."""
    a, b = IDLE_FIDGET
    if t <= a or t >= b: return 0.0
    return math.sin(math.pi * (t - a) / (b - a)) ** 2

def soft_limit(x, m):
    """Identity up to 75 % of m, then a tanh knee that never exceeds m (C1)."""
    ax = abs(x)
    if ax <= 0.75 * m: return x
    return math.copysign(m * (0.75 + 0.25 * math.tanh((ax / m - 0.75) / 0.25)), x)

def lerp(a, b, u):
    if isinstance(a, Vector) or isinstance(b, Vector):
        return Vector(a).lerp(Vector(b), u)
    return a + (b - a) * u

def track(t, keys, mix=None):
    """Piecewise interpolation. keys: [(time, value, ease_into_this_key), ...]."""
    mix = mix or lerp
    if t <= keys[0][0]: return keys[0][1]
    for i in range(1, len(keys)):
        t0, v0, _ = keys[i - 1]
        t1, v1, fn = keys[i]
        if t <= t1:
            if t1 <= t0: return v1
            return mix(v0, v1, (fn or smooth)((t - t0) / (t1 - t0)))
    return keys[-1][1]


def arc(a, b, u):
    """v4: hand offsets about the shoulder travel on an arc (direction slerp, length lerp)
    instead of the chord, so a hand swinging over the shoulder never cuts past the joint
    (v3's guard -> wind-up chord passed 9 cm from the shoulder and folded the elbow 160 deg)."""
    a = Vector(a); b = Vector(b)
    la, lb = a.length, b.length
    if la < 1e-6 or lb < 1e-6: return a.lerp(b, u)
    return turn(a.normalized(), b.normalized(), u) * (la + (lb - la) * u)


def turn(a: Vector, b: Vector, u: float) -> Vector:
    """Rotate unit a toward unit b by the fraction u of their angle (u may overshoot)."""
    q = a.rotation_difference(b)
    if q.angle < 1e-7: return a.copy()
    return Quaternion(q.axis, q.angle * u) @ a


def qslerp(a: Quaternion, b: Quaternion, u: float) -> Quaternion:
    """Quaternion slerp on the short path; u may overshoot (back-out keys)."""
    d = a.inverted() @ b
    if d.w < 0: d.negate()
    if d.angle < 1e-7: return a.copy()
    return a @ Quaternion(d.axis, d.angle * u)


def keyed_hand(rig, side: str, name: str, keys: list, parts, t: float, auto: float, solve=None) -> Matrix:
    """v4: world hand rotation at t for a blade/tool aim. Each choreography key is solved
    once, in order (elbow swivel + forearm-relative wrist for its tip target, with memory),
    and its hand rotation is kept in body space; between keys the hand slerps with the key's
    ease, so the blade never re-solves its roll per frame (v3 and a per-frame solve flipped
    the hand 140-180 deg in the cut). parts(t) -> (B, target, pole, rest_tip, tip); solve(t) -> the
    key's hand matrix for an FK arm (default: the IK arm aimed at the tip)."""
    cache_key = ('keyed', name, side)
    if cache_key not in rig.cache:
        saved = (rig.prev_hinge, rig.prev_hand, rig.prev_twist)
        rig.prev_hinge, rig.prev_hand, rig.prev_twist = {}, {}, {}
        solved = []
        last = None
        for tk, ease in keys:
            B, target, pole, rest_tip, tip = parts(tk)
            sig = (tuple(round(c, 7) for row in B for c in row), tuple(round(c, 7) for c in target), tuple(round(c, 7) for c in pole),
                   tuple(round(c, 7) for c in tip))
            if last is not None and sig == last[0]:
                solved.append((tk, last[1].copy(), ease))      # a hold: the same pose, not a re-solve
                continue
            H = solve(tk) if solve is not None else rig.arm_ik(side, B, target, pole, 'tip', aim=(rest_tip, tip), auto=auto)[2]
            Rb = B.to_3x3().normalized()
            q = (Rb.transposed() @ H.to_3x3().normalized()).to_quaternion()
            if solved and q.dot(solved[-1][1]) < 0: q.negate()
            solved.append((tk, q, ease))
            last = (sig, q)
        # The attack starts and ends on the same guard: reuse the first key's solution.
        if len(solved) > 1 and abs(solved[-1][0] - (ATTACK_RELEASE + 0.5)) < 1e-6 and abs(solved[0][0]) < 1e-6:
            q0 = solved[0][1].copy()
            if q0.dot(solved[-2][1]) < 0: q0.negate()
            solved[-1] = (solved[-1][0], q0, solved[-1][2])
        rig.prev_hinge, rig.prev_hand, rig.prev_twist = saved
        rig.cache[cache_key] = solved
    solved = rig.cache[cache_key]
    q = track(t, solved, qslerp)
    B, _, _, rest_tip, tip = parts(t)
    G = B.to_3x3().normalized() @ q.to_matrix()
    # The slerped hand keeps its roll; the blade itself is swung onto the authored arc (the
    # cut passes through forward instead of wherever the shortest hand rotation goes).
    return (G @ Vector(rest_tip)).normalized().rotation_difference(Vector(tip).normalized()).to_matrix() @ G


def slerp_dir(a, b, u):
    """Unit direction slerp (blade / tool tip targets); back-out overshoot extrapolates."""
    return turn(Vector(a).normalized(), Vector(b).normalized(), u)


# ----------------------------------------------------------------------------
# Rig description from the actual blend file
# ----------------------------------------------------------------------------
class Rig:
    def __init__(self, cid: str, spec: dict, row: dict, rig_ob, meshes):
        self.cid = cid
        self.spec = spec
        self.row = row
        self.ob = rig_ob
        self.h = float(spec.get('height', 1.65))
        self.kind = spec['attack']
        self.build = spec.get('build', 'normal')
        self.lead = spec.get('swing_lead_side', spec.get('lead_side', 'R'))
        self.off = 'L' if self.lead == 'R' else 'R'
        self.P = {}
        for bone in rig_ob.data.bones:
            name = bone.name.removeprefix('Skin')
            hl = bone.head_local
            self.P[name] = Vector((hl.x, hl.z, -hl.y))   # Blender -> Godot
        self.hip = self.h * 0.29
        self.sides = [s for s in ['L', 'R'] if 'Arm' + s in self.P and 'Forearm' + s in self.P and 'Hand' + s in self.P]
        self.weapon = {s: ('Weapon' + s) in self.P for s in ['L', 'R']}
        # Geometry statistics per dominant vertex group (Godot coordinates).
        bounds = {}
        groups = {}
        for ob in meshes:
            names = {g.index: g.name for g in ob.vertex_groups}
            for v in ob.data.vertices:
                if not v.groups: continue
                g = max(v.groups, key=lambda g: g.weight)
                if g.weight < 0.5: continue
                n = names[g.group].removeprefix('Skin')
                p = Vector((v.co.x, v.co.z, -v.co.y))
                b = bounds.setdefault(n, [Vector((1e9,) * 3), Vector((-1e9,) * 3)])
                for i in range(3):
                    b[0][i] = min(b[0][i], p[i]); b[1][i] = max(b[1][i], p[i])
                groups.setdefault(n, []).append(p)
        self.bounds = bounds
        # B1 diagnostic (phase 2 rig fit): how far the hand pivot sits from the visible wrist
        # (the centroid of skin shared by the forearm and the hand, else the forearm and the
        # weapon). Template rigs put it 0.2-0.35 m off, so any wrist turn still stretches the
        # cuff there; recorded in provenance, not used to cut the wrist (the blade must aim).
        self.wrist_offset = {}
        for side in ['L', 'R']:
            if ('Hand' + side) not in self.P: continue
            pts = []
            for ob in meshes:
                names = {g.index: g.name.removeprefix('Skin') for g in ob.vertex_groups}
                for pair in (('Forearm' + side, 'Hand' + side), ('Forearm' + side, 'Weapon' + side)):
                    for v in ob.data.vertices:
                        w = {names[g.group]: g.weight for g in v.groups if g.group in names}
                        if w.get(pair[0], 0.0) > 0.15 and w.get(pair[1], 0.0) > 0.15:
                            pts.append(Vector((v.co.x, v.co.z, -v.co.y)))
                    if len(pts) >= 3: break
                if len(pts) >= 3: break
            if len(pts) >= 3:
                c = sum(pts, Vector((0, 0, 0))) / len(pts)
                self.wrist_offset[side] = (c - self.P['Hand' + side]).length
            else:
                self.wrist_offset[side] = 0.25
        leg_tops = [bounds[n][1].y for n in ['LegL', 'LegR'] if n in bounds]
        self.leg_top = (max(leg_tops) / self.h) if leg_tops else 0.3
        # Weapon tip direction from the hand pivot (sword/tool arcs).
        self.tip = {}
        for s in ['L', 'R']:
            name = 'Weapon' + s
            if name in groups and ('Hand' + s) in self.P:
                hand = self.P['Hand' + s]
                far = max(groups[name], key=lambda p: (p - hand).length)
                d = far - hand
                self.tip[s] = d.normalized() if d.length > 1e-6 else Vector((0, 1, 0))
        # Release sockets (rest model space) per side; artillery sockets sit on the body.
        self.muzzle = {}
        for socket in row.get('sockets', []):
            bone = str(socket['bone']).removeprefix('Skin')
            side = bone[-1] if bone[-1] in 'LR' else None
            if side and side not in self.muzzle:
                self.muzzle[side] = Vector(socket['point'])
        # Aim rotation per side (gun axis -> forward) for rifles.
        self.aim_rot = {}
        for s in ['L', 'R']:
            axis = spec.get('muzzle_axes_xyz', {}).get(s, spec.get('muzzle_axis_xyz'))
            if axis is not None and (s == self.lead or s in spec.get('muzzle_axes_xyz', {})):
                self.aim_rot[s] = rot_between(Vector(axis), FORWARD)
            elif spec.get('weapon_aim_x') and s == self.lead:
                self.aim_rot[s] = Rx(float(spec['weapon_aim_x']))
            else:
                self.aim_rot[s] = I4
        gun_sides = [s for s in ['L', 'R'] if self.kind == 'rifle' and (s == self.lead or s in spec.get('muzzle_axes_xyz', {}))]
        self.gun_sides = gun_sides
        motion = dict(spec.get('motion', {}))
        if self.kind == 'rifle':
            default_grip = 'dual' if len(gun_sides) > 1 else 'two_hand'
            if cid == 'kari': default_grip = 'one_hand'
            self.grip = motion.get('grip', default_grip)
        else:
            self.grip = motion.get('grip', 'none')
        self.relax = float(spec.get('idle_inward_angle', 0.28))
        self.motion = motion
        # Locomotion parameters derived from the leg geometry.
        short_legs = self.leg_top < 0.25
        swing = 0.40 if short_legs else 0.56 if self.build == 'heavy' else 0.66 if self.build == 'slim' else 0.62
        self.leg_swing = float(motion.get('leg_swing', swing))
        stride = clamp(5.2 * self.hip * math.sin(self.leg_swing), 1.30, 1.70)
        self.stride = float(motion.get('stride', stride))
        self.bounce_scale = float(motion.get('bounce', 0.7 if self.kind == 'artillery' else 0.85 if self.build == 'heavy' else 1.0))
        self._arm_geometry()
        self._skin_setup(meshes)
        self.cache = {}
        self.prev_hinge = {}
        self.prev_hand = {}
        self.prev_twist = {}

    def side_sign(self, side: str) -> float:
        return -1.0 if side == 'L' else 1.0

    def reverse_grip(self, side: str) -> bool:
        """The weapon runs back along the forearm (more than 135 deg off the rest forearm axis;
        phantom's 113 deg blade is a forward grip with a cocked wrist and keeps the forward cut)."""
        if side not in self.tip: return False
        f0 = (self.P['Hand' + side] - self.P['Forearm' + side]).normalized()
        return self.tip[side].angle(f0) > math.radians(135.0)

    def arm_length(self, side: str) -> float:
        return (self.P['Forearm' + side] - self.P['Arm' + side]).length + (self.P['Hand' + side] - self.P['Forearm' + side]).length

    def shoulder(self, side, B: Matrix) -> Vector:
        return B @ self.P['Arm' + side]

    # ---- limb construction (motion v4, B1 2026-10-19) ---------------------------
    # The bones are parentless absolute controls, so nothing makes a forearm agree with
    # its upper arm except the solver. v3 turned each segment by its own minimal arc
    # (elbow twist up to 180 deg, the "chicken wing") and drove sword/tool/rifle hands
    # in world space (wrist folds up to 179 deg). v4: the forearm is always the upper
    # arm composed with a rotation about the elbow hinge, the upper arm's twist is set
    # by the elbow plane (pole), and every hand is a forearm-relative wrist rotation
    # inside soft anatomical limits. Aimed hands pick the elbow swivel that leaves the
    # wrist the least work, so blades and guns are pointed by the elbow and forearm.
    def _arm_geometry(self):
        self.hinge, self.rest_bend = {}, {}
        for s in self.sides:
            S, E, W = self.P['Arm' + s], self.P['Forearm' + s], self.P['Hand' + s]
            a0 = (E - S).normalized(); f0 = (W - E).normalized()
            bend = a0.angle(f0)
            m = (a0 + f0).normalized()
            p = FORWARD - m * FORWARD.dot(m)
            # Anatomical hinge: flexion carries the forearm toward the front of the body. The axis
            # is kept square to the forearm, so flexing never spins the forearm about itself
            # (a slight rest carrying angle stays with the upper arm).
            n = m.cross(p).normalized() if p.length > 1e-6 else Vector((1, 0, 0))
            n = (n - f0 * n.dot(f0)).normalized()
            if bend > REST_BEND_GEOMETRIC:
                # A rest arm modelled clearly bent (a gun arm) keeps the plane its elbow
                # crease was modelled in.
                n = a0.cross(f0).normalized()
            self.hinge[s] = n
            self.rest_bend[s] = bend
        self.clamped = {}


    # ---- skin webs (B1 follow-up, 2026-10-19) ------------------------------------------
    def _skin_setup(self, meshes):
        """The shoulder/elbow skin of each arm: mesh edges between vertices weighted only to
        the body, that upper arm and its forearm, with at least one end on the upper arm and
        not both rigid on one bone. skin_web() poses them by linear blend skinning."""
        self.skin = {}
        for side in self.sides:
            keep = {'Body': 0, 'Arm' + side: 1, 'Forearm' + side: 2}
            pts, wts, ii, jj = [], [], [], []
            for ob in meshes:
                names = {g.index: g.name.removeprefix('Skin') for g in ob.vertex_groups}
                local = {}
                for v in ob.data.vertices:
                    w = [0.0, 0.0, 0.0]; other = 0.0
                    for g in v.groups:
                        k = keep.get(names.get(g.group))
                        if k is None: other += g.weight
                        else: w[k] += g.weight
                    tot = w[0] + w[1] + w[2]
                    if tot <= 1e-6 or other > 0.02 * (tot + other): continue
                    local[v.index] = len(pts)
                    pts.append((v.co.x, v.co.z, -v.co.y)); wts.append([c / tot for c in w])
                for e in ob.data.edges:
                    a, b = e.vertices
                    if a not in local or b not in local: continue
                    wa, wb = wts[local[a]], wts[local[b]]
                    if max(wa[1], wb[1]) < 0.02: continue
                    if max(wa) > 0.98 and max(wb) > 0.98 and wa.index(max(wa)) == wb.index(max(wb)): continue
                    ii.append(local[a]); jj.append(local[b])
            if not ii: continue
            P = np.array(pts, dtype=np.float64); W = np.array(wts, dtype=np.float64)
            I = np.array(ii); J = np.array(jj)
            r = np.linalg.norm(P[I] - P[J], axis=1)
            ok = r > 1e-6
            self.skin[side] = {'p': P, 'w': W, 'i': I[ok], 'j': J[ok], 'r': r[ok]}

    def skin_web(self, side, B: Matrix, A: Matrix, F: Matrix) -> tuple:
        """(cost, stretched-edge count) of a side's shoulder/elbow skin for body/arm/forearm
        matrices: cost = SKIN_SCALE * mean squared stretch past SKIN_STRETCH; the count is the
        web probe's (edges over 2.2x and 3 % of the height)."""
        sk = self.skin.get(side)
        if sk is None: return 0.0, 0
        out = None
        for k, M in enumerate((B, A, F)):
            m = np.array(M, dtype=np.float64)
            q = sk['w'][:, k:k + 1] * (sk['p'] @ m[:3, :3].T + m[:3, 3])
            out = q if out is None else out + q
        d = np.linalg.norm(out[sk['i']] - out[sk['j']], axis=1)
        ratio = d / sk['r']
        cost = SKIN_SCALE * float(np.mean(np.square(np.maximum(0.0, ratio - SKIN_STRETCH))))
        return cost, int(np.count_nonzero((ratio > 2.2) & (d > 0.03 * self.h)))

    def arm_key(self, side, az: float, el: float, roll: float, bend: float) -> tuple:
        """FK arm key: (body-space upper-arm rotation, elbow flexion in rad) from the upper-arm
        direction (az deg from straight out toward the front, el deg up from hanging), its roll
        about itself (deg, left-arm sense, mirrored on the right) and the hinge flexion (deg)."""
        sg = self.side_sign(side)
        a, e = math.radians(az), math.radians(el)
        u = Vector((sg * math.cos(a) * math.sin(e), -math.cos(e), -math.sin(a) * math.sin(e)))
        a0 = (self.P['Forearm' + side] - self.P['Arm' + side]).normalized()
        return Quaternion(u, -sg * math.radians(roll)) @ a0.rotation_difference(u), math.radians(bend)

    def arm_key_of(self, side, B: Matrix, A: Matrix, F: Matrix) -> tuple:
        """The FK key (body-space upper-arm rotation, hinge flexion) of solved arm matrices."""
        RA = A.to_3x3().normalized()
        q = (RA.transposed() @ F.to_3x3().normalized()).to_quaternion()
        theta = 2.0 * math.atan2(Vector((q.x, q.y, q.z)).dot(self.hinge[side]), q.w)
        return (B.to_3x3().normalized().transposed() @ RA).to_quaternion(), theta

    def elbow_rot(self, side, angle: float) -> Matrix:
        """Elbow flexion about the hinge (FK limbs); positive bends toward the front."""
        return Matrix.Rotation(angle, 4, self.hinge[side])

    def arm_fk(self, side, B: Matrix, shoulder_rot: Matrix, elbow_rot: Matrix, hand_mode='follow', hand_rot: Matrix = None,
               aim: Matrix = None, twist_max=None, bend_max=None):
        S, E, W = self.P['Arm' + side], self.P['Forearm' + side], self.P['Hand' + side]
        A = B @ around(S, shoulder_rot)
        F = A @ around(E, elbow_rot)
        return A, F, self._hand(side, F, F.to_3x3().normalized(), hand_mode, hand_rot, aim, twist_max, bend_max)

    def _reach(self, side, d: float):
        """Hinge angle (about the rest hinge) that puts the wrist d from the shoulder."""
        S, E, W = self.P['Arm' + side], self.P['Forearm' + side], self.P['Hand' + side]
        a = (E - S).length; b = (W - E).length
        a0 = (E - S) / a; f0 = (W - E) / b; n0 = self.hinge[side]
        e = f0.dot(n0); fp = f0 - n0 * e
        K = e * a0.dot(n0); Ac = a0.dot(fp); Bs = a0.dot(n0.cross(fp))
        M = max(1e-9, math.hypot(Ac, Bs)); phi = math.atan2(Bs, Ac)
        dmax = math.sqrt(max(1e-9, a * a + b * b + 2 * a * b * (K + M)))
        dmin = math.sqrt(max(1e-9, a * a + b * b + 2 * a * b * (K - M)))
        d = clamp(d, dmin + 0.004, dmax - 0.004)
        c = clamp(((d * d - a * a - b * b) / (2 * a * b) - K) / M, -1.0, 1.0)
        theta = phi + math.acos(c)          # flexion branch (the straight arm is theta == phi)
        wl = a0 * a + (Matrix.Rotation(theta, 3, n0) @ f0) * b
        return theta, wl

    def _swivel_frame(self, side, wl: Vector, u: Vector, pole: Vector, B: Matrix) -> Matrix:
        """Upper-arm rotation (3x3) sending the rest wrist offset wl along u. Base: the
        body-carried rest arm swung onto u without twist (continuous through any reach);
        the pole then turns the elbow plane about u so the elbow points at the pole. The
        pole's say fades out as it nears the reach axis, so the plane never flips there."""
        w = wl.normalized(); n0 = self.hinge[side]
        Rb = B.to_3x3().normalized()
        wb = Rb @ w
        R = wb.rotation_difference(u).to_matrix() @ Rb
        if pole is None: return R          # free arm: the twist-free plane (no upper-arm roll)
        pp = pole - u * pole.dot(u)
        k = smooth((pp.length / max(pole.length, 1e-6) - POLE_FADE[0]) / (POLE_FADE[1] - POLE_FADE[0]))
        if k <= 0.0: return R
        n_base = R @ n0
        n_base = n_base - u * n_base.dot(u)
        if n_base.length < 1e-6: return R
        n_base.normalize()
        n_star = pp.cross(u).normalized()
        psi = math.atan2(u.dot(n_base.cross(n_star)), n_base.dot(n_star))
        if DEBUG_SIDE == side: print('SWIVEL', side, 'share %.2f k %.2f psi %6.1f u %s pole %s' % (pp.length / max(pole.length, 1e-6), k, math.degrees(psi), tuple(round(c, 2) for c in u), tuple(round(c, 2) for c in pole)))
        return Matrix.Rotation(k * psi, 3, u) @ R

    def arm_ik(self, side, B: Matrix, target: Vector, pole: Vector, hand_mode='follow', hand_rot: Matrix = None,
               aim=None, auto: float = 0.0, twist_max=None, bend_max=None, roll_axis: Vector = None, roll_max: float = 0.0,
               aim_weight: float = 1.0, skin: float = 0.0):
        """Hinge-consistent two-bone arm. hand_mode:
          'follow'  wrist = hand_rot (forearm-relative, rest frame)
          'aim'     aim is a world rotation delta (4x4/3x3) for the hand (+ an optional free
                    roll about roll_axis within roll_max); the wrist takes what the forearm leaves
          'tip'     aim = (rest_dir, world_dir): the hand carries rest_dir to world_dir, roll free
        auto in 0..1 lets the elbow swivel away from the pole to spare the wrist; aim_weight in
        0..1 eases the aimed wrist in from a straight wrist (0) to the full aim (1); skin weighs the
        shoulder/elbow skin web (skin_web) into the swivel search."""
        S, E, W = self.P['Arm' + side], self.P['Forearm' + side], self.P['Hand' + side]
        S2 = B @ S
        to = Vector(target) - S2
        u = to.normalized() if to.length > 1e-6 else Vector((0, -1, 0))
        theta, wl = self._reach(side, to.length)
        R_A = self._swivel_frame(side, wl, u, Vector(pole) if pole is not None else None, B)
        R_F = R_A @ Matrix.Rotation(theta, 3, self.hinge[side])
        aimed = auto > 0.0 and aim_weight > 0.0 and hand_mode in ('aim', 'tip')
        psi = self._best_swivel(side, B, S2, u, R_A, R_F, hand_mode if aimed else 'none', aim, auto * aim_weight if aimed else 0.0,
                                twist_max, bend_max, roll_axis, roll_max, skin)
        if psi:
            Rs = Matrix.Rotation(psi, 3, u)
            R_A = Rs @ R_A; R_F = Rs @ R_F
        E2 = S2 + R_A @ (E - S)
        A = T(S2) @ R_A.to_4x4() @ T(-S)
        F = T(E2) @ R_F.to_4x4() @ T(-E)
        return A, F, self._hand(side, F, R_F, hand_mode, hand_rot, aim, twist_max, bend_max, roll_axis, roll_max, aim_weight)

    # ---- wrist ---------------------------------------------------------------------
    def _wrist_needed(self, side, R_F: Matrix, mode, aim, roll_axis=None, roll_max=0.0) -> Quaternion:
        """Forearm-relative rotation (rest frame) the hand needs for its aim."""
        if mode == 'tip':
            rest_dir, world_dir = aim
            local = R_F.transposed() @ Vector(world_dir)
            q = Vector(rest_dir).normalized().rotation_difference(local.normalized())
        else:
            G = Matrix(aim).to_3x3().normalized()
            if roll_axis is not None and roll_max > 0.0:
                # Free roll about roll_axis (world) chosen in closed form for the smallest wrist.
                P = (G @ R_F.transposed()).to_quaternion()
                if P.w < 0: P.negate()
                z = Vector(roll_axis).normalized()
                gamma = clamp(-2.0 * math.atan2(z.dot(Vector((P.x, P.y, P.z))), P.w), -roll_max, roll_max)
                G = Matrix.Rotation(gamma, 3, z) @ G
            q = (R_F.transposed() @ G).to_quaternion()
        if q.w < 0: q.negate()
        return q

    def _wrist_parts(self, side, q: Quaternion):
        f0 = (self.P['Hand' + side] - self.P['Forearm' + side]).normalized()
        proj = Vector((q.x, q.y, q.z)).dot(f0)
        twist = 2.0 * math.atan2(proj, q.w)
        tq = Quaternion((q.w, f0.x * proj, f0.y * proj, f0.z * proj))
        tq = tq.normalized() if tq.magnitude > 1e-9 else Quaternion()
        sw = q @ tq.inverted()
        if sw.w < 0: sw.negate()
        return sw, twist, f0

    def _wrist_cost(self, side, R_F, mode, aim, twist_max, bend_max, roll_axis, roll_max) -> float:
        sw, twist, _ = self._wrist_parts(side, self._wrist_needed(side, R_F, mode, aim, roll_axis, roll_max))
        tm = twist_max or WRIST_TWIST_MAX; bm = bend_max or WRIST_BEND_MAX
        bend = sw.angle
        cost = (bend / WRIST_BEND_SCALE) ** 2 + (twist / WRIST_TWIST_SCALE) ** 2
        cost += 8.0 * (max(0.0, bend - bm) / WRIST_BEND_SCALE) ** 2 + 8.0 * (max(0.0, abs(twist) - tm) / WRIST_TWIST_SCALE) ** 2
        return cost

    def shoulder_twist(self, side, B: Matrix, R_A: Matrix) -> float:
        """Roll of the upper arm against the body (rad) about the body-carried rest arm axis
        (the audit's shoulder_twist)."""
        Rb = B.to_3x3().normalized()
        q = (R_A @ Rb.transposed()).to_quaternion()
        if q.w < 0: q.negate()
        axis = (Rb @ (self.P['Forearm' + side] - self.P['Arm' + side])).normalized()
        return 2.0 * math.atan2(Vector((q.x, q.y, q.z)).dot(axis), q.w)

    def _elbow_penalty(self, side, B: Matrix, E2: Vector) -> float:
        """Keep the elbow out of the torso (body space)."""
        Eb = B.inverted() @ E2
        S = self.P['Arm' + side]
        inside = (abs(S.x) - 0.03) - Eb.x * self.side_sign(side)
        if inside <= 0 or abs(Eb.z) > 0.16 * self.h or Eb.y > S.y + 0.05 or Eb.y < self.hip: return 0.0
        return (inside / 0.05) ** 2

    def _best_swivel(self, side, B, S2, u, R_A0, R_F0, mode, aim, auto, twist_max, bend_max, roll_axis, roll_max, skin=0.0) -> float:
        E = self.P['Forearm' + side]; S = self.P['Arm' + side]
        prev = self.prev_hinge.get(side)
        prev_hand = self.prev_hand.get(side) if auto > 0.0 else None
        prev_twist = self.prev_twist.get(side) if auto > 0.0 else None
        n0 = self.hinge[side]
        def cost(psi):
            Rs = Matrix.Rotation(psi, 3, u)
            c = auto * self._wrist_cost(side, Rs @ R_F0, mode, aim, twist_max, bend_max, roll_axis, roll_max) if auto > 0.0 else 0.0
            if prev_hand is not None:
                # Hand memory: of the swivels that serve the aim, keep the one that turns the hand
                # least since the last key, and above all the one that keeps the wrist's own twist
                # (no pronation snapping across the forearm between two keys).
                qw = self._wrist_needed(side, Rs @ R_F0, mode, aim, roll_axis, roll_max)
                hand = (Rs @ R_F0) @ qw.to_matrix()
                c += HAND_MEMORY * (prev_hand.rotation_difference(hand.to_quaternion()).angle / math.radians(60.0)) ** 2
                if prev_twist is not None:
                    c += TWIST_MEMORY * ((self._wrist_parts(side, qw)[1] - prev_twist) / math.radians(30.0)) ** 2
            c += (1.0 - auto) * (psi / SWIVEL_SCALE) ** 2
            c += self._elbow_penalty(side, B, S2 + Rs @ R_A0 @ (E - S))
            over = abs(self.shoulder_twist(side, B, Rs @ R_A0)) - SHOULDER_TWIST_SOFT
            if over > 0: c += (over / math.radians(20.0)) ** 2
            if skin > 0.0:
                RA = Rs @ R_A0
                E2 = S2 + RA @ (E - S)
                c += skin * self.skin_web(side, B, T(S2) @ RA.to_4x4() @ T(-S), T(E2) @ (Rs @ R_F0).to_4x4() @ T(-E))[0]
            if prev is not None:
                # Frame-to-frame memory of the elbow plane: breaks the tie between mirror
                # solutions of a nearly straight arm (otherwise a 150 deg flip per key).
                c += SWIVEL_MEMORY * ((Rs @ R_A0 @ n0).angle(prev) / math.radians(30.0)) ** 2
            return c
        n = int(round(SWIVEL_RANGE / SWIVEL_STEP))
        grid = [(cost(k * SWIVEL_STEP), k * SWIVEL_STEP) for k in range(-n, n + 1)]
        if DEBUG_SIDE == side and DEBUG_T is not None and abs(CURRENT_T[0] - DEBUG_T) < 1e-6:
            for k in range(-90, 91, 6):
                psi = math.radians(2 * k)
                Rs = Matrix.Rotation(psi, 3, u)
                q = self._wrist_needed(side, Rs @ R_F0, mode, aim, roll_axis, roll_max) if mode in ('aim', 'tip') else Quaternion()
                sw, tw, _ = self._wrist_parts(side, q)
                Eb = B.inverted() @ (S2 + Rs @ R_A0 @ (E - S))
                print('LANDSCAPE psi %5.0f wrist bend %5.1f twist %6.1f cost %.2f elbow_body %s' % (2 * k, math.degrees(sw.angle), math.degrees(tw), cost(psi), tuple(round(c, 2) for c in Eb)))
        best_cost, best = min(grid)
        # Parabolic refinement between the neighbours.
        lo, hi = cost(best - SWIVEL_STEP), cost(best + SWIVEL_STEP)
        den = lo - 2 * best_cost + hi
        if den > 1e-12 and abs(best) < SWIVEL_RANGE:
            best += 0.5 * SWIVEL_STEP * (lo - hi) / den
        self.prev_hinge[side] = Matrix.Rotation(best, 3, u) @ R_A0 @ n0
        if auto > 0.0:
            Rb = Matrix.Rotation(best, 3, u) @ R_F0
            qw = self._wrist_needed(side, Rb, mode, aim, roll_axis, roll_max)
            self.prev_hand[side] = (Rb @ qw.to_matrix()).to_quaternion()
            self.prev_twist[side] = self._wrist_parts(side, qw)[1]
        return best

    def _hand(self, side, F: Matrix, R_F: Matrix, mode, hand_rot=None, aim=None, twist_max=None, bend_max=None,
              roll_axis=None, roll_max=0.0, aim_weight=1.0) -> Matrix:
        W = self.P['Hand' + side]
        if mode == 'follow':
            return F @ around(W, hand_rot or I4)
        if mode == 'upright':          # legacy name: keep the rest orientation if the wrist allows
            mode, aim = 'aim', I4
        q = self._wrist_needed(side, R_F, mode, aim, roll_axis, roll_max)
        if aim_weight < 1.0: q = Quaternion().slerp(q, clamp01(aim_weight))
        sw, twist, f0 = self._wrist_parts(side, q)
        tm = twist_max or WRIST_TWIST_MAX; bm = bend_max or WRIST_BEND_MAX
        prev = self.prev_twist.get(side)
        if prev is not None:
            # Unwrap against the last key: a need crossing +-180 deg must not throw a saturated
            # wrist to the opposite limit (the blade deviates instead of flipping over).
            while twist - prev > math.pi: twist -= TAU
            while twist - prev < -math.pi: twist += TAU
        twist_c = soft_limit(twist, tm)
        bend = sw.angle
        bend_c = soft_limit(bend, bm)
        key = side
        self.clamped[key] = max(self.clamped.get(key, 0.0), max(0.0, bend - bend_c), max(0.0, abs(twist) - abs(twist_c)))
        sw_c = Quaternion(sw.axis, bend_c) if bend > 1e-6 else Quaternion()
        Wr = (sw_c @ Quaternion(f0, twist_c)).to_matrix().to_4x4()
        return F @ around(W, Wr)

    def weapon_matrix(self, side, H: Matrix, extra: Matrix = None) -> Matrix:
        """Rigid weapon bone from its hand. v4: bows ride the hand too (only staffs and
        anchors of casters stay translation-only)."""
        W = self.P['Hand' + side]
        follows = self.kind in ['sword', 'tool', 'rifle', 'bow'] or self.spec.get('weapon_follow_hand')
        M = H if follows else T(H @ W - W)
        if extra is not None: M = M @ around(W, extra)
        return M

    def leg_matrix(self, side, swing: float, lift: float = 0.0, splay: float = 0.0) -> Matrix:
        R = Rx(swing) @ Rz(splay)
        return T((0, lift, 0)) @ around(self.P['Leg' + side], R)

    def body_matrix(self, t=(0, 0, 0), yaw=0.0, pitch=0.0, roll=0.0) -> Matrix:
        return T(t) @ around((0, self.hip, 0), Ry(yaw) @ Rx(pitch) @ Rz(roll))


# ----------------------------------------------------------------------------
# Idle
# ----------------------------------------------------------------------------
def idle_pose(rig: Rig, t: float) -> dict:
    h = rig.h
    breath = BREATH_H * h * breathe(t)
    sway = math.sin(TAU * t / 6)
    look = 0.07 * bump((t - 2.4) / 2.2)
    fid = fidget(t)
    # The fidget leans the body a little with the weapon arm (bows/staffs/tools/swords
    # lift the weapon, rifles shoulder it, artillery braces).
    B = rig.body_matrix((sway * SWAY_H * h, breath, 0),
                        yaw=0.025 * math.sin(TAU * t / 6 + 1.0) + look + (0.0 if rig.kind == 'artillery' else rig.side_sign(rig.lead) * 0.04 * fid),
                        pitch=0.008 * math.sin(TAU * t / 3 + 0.6) - (0.03 if rig.kind == 'artillery' else 0.015) * fid,
                        roll=-SWAY_ROLL * sway)
    poses = {'Body': B}
    for side in rig.sides:
        s = rig.side_sign(side)
        phase = 0.0 if side == 'L' else 0.9
        hold = rig.kind == 'rifle' and side in rig.gun_sides
        lead = side == rig.lead
        relax = rig.relax * (1 - 0.08 * math.sin(TAU * t / 3 + phase))
        swing = 0.03 * math.sin(TAU * t / 3 + phase)
        lift, bend, grip, out = 0.0, 0.0, 0.0, 0.0
        if rig.kind == 'bow' and lead: lift, bend = 0.30, 0.10          # bow tilt: the bow arm lifts, the bow tips forward
        elif rig.kind == 'rifle' and hold: lift, bend, grip = 0.35, 0.30, 0.30   # shoulder the rifle: muzzle up
        elif rig.kind == 'sword' and lead: lift, grip = 0.15, 0.50      # re-grip: the blade tip swings
        elif rig.kind == 'cast' and lead: lift, bend = 0.45, 0.20      # staff lift (translation-only weapon rides the hand)
        elif rig.kind == 'tool' and lead: lift, out, grip = 0.55, 0.20, 0.30    # shoulder the wrench
        elif rig.kind == 'artillery': lift = 0.35                       # brace / shrug with both arms
        shoulder_rot = Rz(-s * (relax + out * fid)) @ Rx(swing + (0.10 if hold else 0.0) - lift * fid)
        elbow_rot = Rx(0.06 + 0.04 * math.sin(TAU * t / 3 + phase + 0.5) + (0.18 if hold else 0.0) + bend * fid)
        hand_rot = I4
        if rig.kind == 'sword' and lead:
            hand_rot = Rx(0.03 * math.sin(TAU * t / 3 + 1.4) + grip * fid)
        elif rig.kind == 'rifle' and hold:
            hand_rot = Rx(0.02 * math.sin(TAU * t / 3 + 0.3) + grip * fid)
        elif grip:
            hand_rot = Rx(grip * fid)
        if rig.kind == 'bow' and lead:
            # v4: the bow rides the hand (no more translation-only bow); the wrist keeps it
            # standing as the v3 bow stood, and the fidget tilt is the hand's.
            bow_tilt = Rz(0.015 * math.sin(TAU * t / 6 + 0.8)) @ Rx(0.45 * fid)
            A, F, H = rig.arm_fk(side, B, shoulder_rot, elbow_rot, 'aim', aim=bow_tilt)
        else:
            A, F, H = rig.arm_fk(side, B, shoulder_rot, elbow_rot, 'follow', hand_rot)
        poses['Arm' + side] = A; poses['Forearm' + side] = F; poses['Hand' + side] = H
        if rig.weapon[side]:
            poses['Weapon' + side] = rig.weapon_matrix(side, H)
    # Weight shift: the body sways over the loaded leg, the unloaded leg lifts a little.
    for side in ['L', 'R']:
        if 'Leg' + side in rig.P:
            unload = max(0.0, sway if side == 'L' else -sway)
            poses['Leg' + side] = rig.leg_matrix(side, 0.0, LEG_UNLOAD_H * h * unload) if unload > 0 else I4
    return poses


# ----------------------------------------------------------------------------
# Walk / run cycle (phase 0..1, authored at full speed)
# ----------------------------------------------------------------------------
def walk_pose(rig: Rig, phi: float) -> dict:
    h = rig.h
    A_leg = rig.leg_swing
    L = rig.hip
    theta_L = A_leg * math.cos(TAU * phi)
    theta_R = -theta_L
    # Stance foot stays planted: the body drops when the legs are spread.
    geometric = L * (1 - math.cos(theta_L))
    bounce = -0.8 * geometric * rig.bounce_scale
    lean = (0.11 if rig.kind != 'artillery' else 0.15) * rig.bounce_scale
    yaw = 0.08 * math.cos(TAU * phi)
    roll = 0.03 * math.cos(TAU * (phi - 0.1))
    xshift = -0.012 * h * math.cos(TAU * (phi - 0.1))
    pitch = lean + 0.012 * math.cos(TAU * 2 * phi + 0.4)
    B = rig.body_matrix((xshift, bounce, 0), yaw=yaw, pitch=pitch, roll=roll)
    poses = {'Body': B}

    def swing_phase(side):
        # Left swings during phi in [0.5, 1.0]; right during [0.0, 0.5].
        local = (phi - 0.5) % 1.0 if side == 'L' else phi % 1.0
        return local / 0.5 if local < 0.5 else -1.0

    for side in ['L', 'R']:
        if 'Leg' + side not in rig.P: continue
        theta = theta_L if side == 'L' else theta_R
        sp = swing_phase(side)
        lift = 0.032 * h * bump(sp) if sp >= 0 else 0.0
        poses['Leg' + side] = rig.leg_matrix(side, theta, lift)

    multipliers = {'L': 1.0, 'R': 1.0}
    if rig.kind == 'bow': multipliers[rig.lead] = 0.45
    elif rig.kind == 'sword': multipliers[rig.lead] = 0.7
    elif rig.kind == 'rifle' and rig.grip == 'one_hand': multipliers[rig.lead] = 0.5
    elif rig.kind == 'rifle' and rig.grip == 'dual': multipliers = {'L': 0.7, 'R': 0.7}
    elif rig.kind == 'cast': multipliers = {'L': 0.9, 'R': 0.9}
    elif rig.kind == 'artillery': multipliers = {'L': 0.75, 'R': 0.75}
    elif rig.kind == 'tool': multipliers = {'L': 0.8, 'R': 0.8}
    A_arm = 0.48
    for side in rig.sides:
        s = rig.side_sign(side)
        arm_swing = -A_arm * math.cos(TAU * phi) * (1.0 if side == 'L' else -1.0) * multipliers[side]
        if rig.kind == 'rifle' and rig.grip == 'two_hand':
            continue
        shoulder_rot = Rz(-s * rig.relax * 0.6) @ Rx(arm_swing)
        pump = max(0.0, math.cos(TAU * phi) * (1.0 if side == 'R' else -1.0))
        bow_arm = rig.kind == 'bow' and side == rig.lead
        # v4: the elbow bends about its hinge (v3's model-X elbow spun the forearm 40-46 deg);
        # the bow arm carries the bow with a straighter elbow and the bow rides the hand,
        # the wrist keeping it near standing inside a small budget.
        bend = (0.35 + 0.10 * pump) if bow_arm else (0.85 + 0.25 * pump)
        hand_rot = I4
        gun_carry = rig.kind == 'rifle' and side in rig.gun_sides
        if bow_arm:
            A, F, H = rig.arm_fk(side, B, shoulder_rot, rig.elbow_rot(side, bend), 'aim', aim=I4,
                                 twist_max=math.radians(40), bend_max=math.radians(45))
        elif gun_carry:
            # v4: one-handed and dual guns are carried pointing forward-down (20 deg) through
            # the wrist solver; the forearm already points that way, so the wrist stays small
            # (v3 forced a fixed forward-up wrist: 93-99 deg folds on dual pistols).
            A, F, H = rig.arm_fk(side, B, shoulder_rot, rig.elbow_rot(side, bend), 'aim', aim=Rx(-0.35) @ rig.aim_rot[side],
                                 twist_max=math.radians(45), bend_max=math.radians(55))
        else:
            A, F, H = rig.arm_fk(side, B, shoulder_rot, rig.elbow_rot(side, bend), 'follow', hand_rot)
        poses['Arm' + side] = A; poses['Forearm' + side] = F; poses['Hand' + side] = H
        if rig.weapon[side]: poses['Weapon' + side] = rig.weapon_matrix(side, H)
    if rig.kind == 'rifle' and rig.grip == 'two_hand':
        lead, off = rig.lead, rig.off
        s = rig.side_sign(lead)
        S2 = rig.shoulder(lead, B)
        gun_bob = Vector((0, -0.25 * bounce, 0))
        target = S2 + Vector((-s * 0.10 * h, -0.17 * h, -0.13 * h)) + gun_bob
        hand_rot = Ry(s * 0.45) @ Rx(0.55) @ rig.aim_rot[lead]
        pole = Vector((s * 0.6, -0.6, 0.35))
        A, F, H = rig.arm_ik(lead, B, target, pole, 'aim', aim=hand_rot, auto=GUN_AUTO)
        poses['Arm' + lead] = A; poses['Forearm' + lead] = F; poses['Hand' + lead] = H
        poses['Weapon' + lead] = rig.weapon_matrix(lead, H)
        if off in rig.sides:
            grip = grip_target(rig, lead, H)
            A2, F2, H2 = rig.arm_ik(off, B, grip, Vector((-s * 0.6, -0.75, 0.1)), 'aim', aim=hand_rot, auto=SUPPORT_AUTO,
                                    roll_axis=gun_axis(rig, lead, hand_rot), roll_max=math.pi)
            poses['Arm' + off] = A2; poses['Forearm' + off] = F2; poses['Hand' + off] = H2
            if rig.weapon[off]: poses['Weapon' + off] = rig.weapon_matrix(off, H2)
    return poses


def gun_axis(rig: Rig, side: str, rot: Matrix) -> Vector:
    """World direction of the gun barrel for a hand rotation delta `rot`. The rest barrel is
    whatever the hero's aim rotation sends to FORWARD (the measured muzzle axis, or the
    weapon_aim_x tilt of a rifle without one)."""
    rest = (rig.aim_rot[side].to_3x3().inverted() @ FORWARD).normalized()
    return (rot.to_3x3() @ rest).normalized()


def grip_target(rig: Rig, lead: str, H: Matrix) -> Vector:
    """Point on the carried gun's fore-end, following the gun hand pose."""
    W = rig.P['Hand' + lead]
    muzzle = rig.muzzle.get(lead)
    if muzzle is None: muzzle = W + Vector((0, 0, -0.26 * rig.h))
    grip_rest = W + (muzzle - W) * 0.45
    return H @ grip_rest


# ----------------------------------------------------------------------------
# Attack choreography per weapon type. t in [0, 1.5]; release at 1.0.
# ----------------------------------------------------------------------------
def tremble(t, amp, f=11.0):
    # HA1 (2026-10-18): the hold is dead still. A 0.2-0.4 px tremble never read at 48 px
    # and only smeared the held frames; the amplitude is kept for the call sites, scaled to 0.
    return 0.0 * amp * math.sin(TAU * f * t) * (1 if 0.80 <= t <= 1.0 else 0)


def attack_pose(rig: Rig, t: float) -> dict:
    CURRENT_T[0] = t
    kind = rig.kind
    if kind == 'bow': return bow_pose(rig, t)
    if kind == 'rifle': return rifle_pose(rig, t)
    if kind == 'sword': return sword_pose(rig, t)
    if kind == 'cast': return cast_pose(rig, t)
    if kind == 'artillery': return artillery_pose(rig, t)
    if kind == 'tool': return tool_pose(rig, t)
    return idle_pose(rig, 0.0)


def finish_arms(rig: Rig, poses: dict, B: Matrix, side: str, A: Matrix, F: Matrix, H: Matrix, weapon_extra: Matrix = None):
    poses['Arm' + side] = A; poses['Forearm' + side] = F; poses['Hand' + side] = H
    if rig.weapon[side]: poses['Weapon' + side] = rig.weapon_matrix(side, H, weapon_extra)


def legs_rest(rig: Rig, poses: dict):
    for side in ['L', 'R']:
        if 'Leg' + side in rig.P: poses['Leg' + side] = I4


def bow_pose(rig: Rig, t: float) -> dict:
    h = rig.h; lead, off = rig.lead, rig.off; s = rig.side_sign(lead)
    R = ATTACK_RELEASE
    # Nock with the bow close to the chest, then push the bow out along the shoulder line
    # while the string hand pulls to the anchor (push-pull draw); the torso blades side-on.
    # v4: both arms are hinge-consistent; the bow rides the bow hand and the wrist holds it
    # standing (roll free within BOW_ROLL) so its release socket faces the shot; the draw
    # elbow rises behind the shoulder in line with the arrow instead of swinging out.
    Hs = HOLD_START['bow']
    yaw = track(t, [(0.0, s * 0.35, None), (0.30, s * 0.50, smooth), (Hs, s * 1.0, ant), (R, s * 1.0, smooth),
                    (R + .05, s * 1.08, ease_out), (R + .24, s * 0.92, back_out), (R + .5, s * 0.35, smooth)])
    pitch = track(t, [(0.0, 0.02, None), (Hs, 0.045, ant), (R, 0.045, smooth), (R + .04, -0.02, ease_out),
                      (R + .20, 0.06, back_out), (R + .5, 0.02, smooth)])
    dip = track(t, [(0.0, 0.0, None), (Hs, -HOLD_DIP * h, ant), (R, -HOLD_DIP * h, smooth), (R + .04, -0.045 * h, ease_out),
                    (R + .5, 0.0, smooth)])
    B = rig.body_matrix((0, dip, 0), yaw=yaw, pitch=pitch)
    poses = {'Body': B}
    S_lead = rig.shoulder(lead, B)
    reach = BOW_REACH * rig.arm_length(lead)
    out = math.sin(BOW_ARM_OUT); fwd = math.cos(BOW_ARM_OUT)
    ready = Vector((s * 0.06 * h, -0.12 * h, -0.13 * h))
    nocked = Vector((s * 0.07 * h, -0.02 * h, -0.15 * h))
    drawn = Vector((s * out, 0.06, -fwd)).normalized() * reach
    bow_off = track(t, [(0.0, ready, None), (0.30, nocked, smooth), (Hs, drawn, ant), (R, drawn, smooth),
                        (R + .04, drawn + Vector((0, 0, -0.02 * h)), ease_out),
                        (R + .18, drawn + Vector((s * 0.01 * h, 0.025 * h, 0.02 * h)), back_out), (R + .5, ready, smooth)])
    bow_target = S_lead + bow_off
    bow_kick = Rx(-0.22 * (damp(t - R, 2.2, 6.0) if t > R else 0.0))
    bow_pole = track(t, [(0.0, Vector((s * 0.5, -0.8, 0.2)), None), (Hs, Vector((s * 0.35, -0.85, 0.35)), ant),
                         (R, Vector((s * 0.35, -0.85, 0.35)), smooth), (R + .5, Vector((s * 0.5, -0.8, 0.2)), smooth)])
    stand = track(t, [(0.0, 0.25, None), (0.30, 0.45, smooth), (Hs, 1.0, ant), (R, 1.0, smooth), (R + .5, 0.25, smooth)])
    A, F, H = rig.arm_ik(lead, B, bow_target, bow_pole, 'aim', aim=I4, auto=BOW_AUTO,
                         roll_axis=FORWARD, roll_max=BOW_ROLL, aim_weight=stand)
    finish_arms(rig, poses, B, lead, A, F, H, bow_kick)
    # The string hand stays within its own reach: it rests low in front of the body, nocks in
    # front of the chest (toward the bow side) and draws to the anchor; push-pull separates
    # the hands instead of dragging the string hand out of reach after the bow.
    S_off = rig.shoulder(off, B)
    rest_draw = Vector((s * 0.08 * h, -0.20 * h, -0.12 * h))
    nock = Vector((s * 0.14 * h, -0.07 * h, -0.17 * h))
    # Anchor at the draw-side cheek, in front of the face (body space): v3 anchored at the
    # body's centre plane, i.e. inside the chibi head, and the hand popped up behind it.
    anchor = B @ Vector((-s * 0.06 * h, BOW_ANCHOR_Y * h, -BOW_ANCHOR_FRONT * h)) - S_off
    draw = S_off + track(t, [(0.0, rest_draw, None), (0.30, nock, smooth), (Hs, anchor, ant), (R, anchor, smooth),
                             (R + .05, anchor + Vector((-s * 0.12 * h, 0.03 * h, 0.08 * h)), ease_out),
                             (R + .28, anchor + Vector((-s * 0.08 * h, -0.02 * h, 0.05 * h)), back_out), (R + .5, rest_draw, smooth)], arc)
    draw += Vector((0, tremble(t, 0.003 * h), 0))
    # Draw elbow: down while the hand is at the nock, swung out, then up behind the
    # shoulder at the anchor; never through the shoulder-hand axis.
    pole = track(t, [(0.0, Vector((-s * 0.3, -1.0, 0.0)), None), (0.30, Vector((-s * 0.3, -1.0, 0.0)), smooth),
                     (0.55, Vector((-s * 1.0, -0.3, 0.2)), smooth), (Hs, Vector((-s * 0.7, 0.25, 0.65)), smooth),
                     (R, Vector((-s * 0.7, 0.25, 0.65)), smooth), (R + .28, Vector((-s * 0.8, -0.5, 0.3)), smooth),
                     (R + .5, Vector((-s * 0.3, -1.0, 0.0)), smooth)])
    pole = B.to_3x3().normalized() @ pole       # body space: the draw elbow stays behind the bladed shoulder
    A2, F2, H2 = rig.arm_ik(off, B, draw, pole, 'follow')
    finish_arms(rig, poses, B, off, A2, F2, H2)
    legs_rest(rig, poses)
    return poses


def gun_hold(rig: Rig, side: str, designed: Vector, pole: Vector, B: Matrix, rot: Matrix) -> Vector:
    """v4: hold offset (from the posed shoulder) near the designed one where the forearm can
    carry the gun aim with the least wrist (searched once per hero and side). The release
    socket must face the shot exactly, so the wrist would otherwise fold to deliver it."""
    key = ('gun_hold', side)
    if key in rig.cache: return rig.cache[key]
    h = rig.h
    S2 = rig.shoulder(side, B)
    reach = rig.arm_length(side)
    axis = gun_axis(rig, side, rot)
    E = rig.P['Forearm' + side]; S = rig.P['Arm' + side]
    support = rig.off if (side == rig.lead and rig.off in rig.sides) else None
    best = (1e9, Vector(designed))
    for ix in range(-4, 5):
        for iy in range(-6, 3):
            for iz in range(-4, 4):
                off = Vector(designed) + Vector((ix * 0.03, iy * 0.035, iz * 0.03)) * h
                d = off.length
                cost = 3.0 * ((off - Vector(designed)).length / (0.10 * h)) ** 2
                if d > 0.95 * reach: cost += 50.0 * ((d - 0.95 * reach) / (0.05 * h)) ** 2
                local = B.inverted() @ (S2 + off)
                if local.z > -0.06 * h: cost += 20.0                       # the gun hand stays in front
                if support and rig.grip == 'two_hand':
                    W = rig.P['Hand' + side]
                    muzzle = rig.muzzle.get(side, W + Vector((0, 0, -0.26 * h)))
                    grip = S2 + off + rot.to_3x3() @ ((muzzle - W) * 0.45)
                    gap = (grip - rig.shoulder(support, B)).length - 0.90 * rig.arm_length(support)
                    if gap > 0: cost += 30.0 * (gap / (0.05 * h)) ** 2
                if cost >= best[0]: continue
                u = off.normalized()
                theta, wl = rig._reach(side, d)
                R_A0 = rig._swivel_frame(side, wl, u, pole, B)
                R_F0 = R_A0 @ Matrix.Rotation(theta, 3, rig.hinge[side])
                wrist = min(rig._wrist_cost(side, Matrix.Rotation(math.radians(k), 3, u) @ R_F0, 'aim', rot, None, None, axis, GUN_ROLL)
                            + (math.radians(k) / SWIVEL_SCALE) ** 2 * 0.15 + rig._elbow_penalty(side, B, S2 + Matrix.Rotation(math.radians(k), 3, u) @ R_A0 @ (E - S))
                            for k in range(-150, 151, 10))
                cost += wrist
                if cost < best[0]: best = (cost, off)
    rig.cache[key] = best[1]
    return best[1]


def rifle_pose(rig: Rig, t: float) -> dict:
    h = rig.h; lead, off = rig.lead, rig.off; s = rig.side_sign(lead)
    R = ATTACK_RELEASE
    Hs = HOLD_START['rifle']
    yaw = track(t, [(0.0, -s * 0.10, None), (Hs, -s * 0.26, ant), (R, -s * 0.26, smooth), (R + .05, -s * 0.31, ease_out),
                    (R + .25, -s * 0.26, back_out), (R + .5, -s * 0.10, smooth)])
    pitch = track(t, [(0.0, 0.03, None), (Hs, 0.055, ant), (R, 0.055, smooth), (R + .05, -0.005, ease_out),
                      (R + .20, 0.075, back_out), (R + .5, 0.03, smooth)])
    dip = track(t, [(0.0, 0.0, None), (Hs, -HOLD_DIP * h, ant), (R, -HOLD_DIP * h, smooth), (R + .05, -0.040 * h, ease_out),
                    (R + .5, 0.0, smooth)])
    B = rig.body_matrix((0, dip, 0), yaw=yaw, pitch=pitch)
    poses = {'Body': B}
    sway_pitch = 0.008 * math.sin(TAU * t / 0.55); sway_yaw = 0.006 * math.cos(TAU * t / 0.7)

    B_hold = rig.body_matrix((0, -HOLD_DIP * h, 0), yaw=-s * 0.26, pitch=0.055)

    def gun(side, delay, shouldered_offset, ready_offset, pole):
        sg = rig.side_sign(side)
        S2 = rig.shoulder(side, B)
        shouldered_offset = gun_hold(rig, side, shouldered_offset, pole, B_hold, rig.aim_rot[side])
        tr = t - delay
        offset = track(tr, [(0.0, ready_offset, None), (Hs, shouldered_offset, ant), (R, shouldered_offset, smooth),
                            (R + .04, shouldered_offset + Vector((0, 0.015 * h, 0.05 * h)), ease_out),
                            (R + .20, shouldered_offset, back_out), (R + .5, ready_offset, smooth)])
        muzzle_pitch = track(tr, [(0.0, -0.40, None), (Hs, 0.0, ant), (R, 0.0, smooth), (R + .04, 0.13, ease_out),
                                  (R + .22, 0.0, back_out), (R + .5, -0.40, smooth)])
        hold = smooth((tr - 0.25) / 0.2) if tr > 0.25 else 0.0
        rot = Rx(muzzle_pitch + sway_pitch * hold) @ Ry(sway_yaw * hold) @ rig.aim_rot[side]
        # v4: the gun may roll about its own barrel (the release socket only needs the barrel
        # on the shot) so the wrist can stay nearly straight.
        A, F, H = rig.arm_ik(side, B, S2 + offset, pole, 'aim', aim=rot, auto=GUN_AUTO,
                             roll_axis=gun_axis(rig, side, rot), roll_max=GUN_ROLL)
        finish_arms(rig, poses, B, side, A, F, H)
        return H, rot

    if rig.grip == 'dual':
        for side, delay in [(lead, 0.0), (off, 0.05)]:
            sg = rig.side_sign(side)
            gun(side, delay, Vector((-sg * 0.03, -0.05, -0.17)) * h, Vector((-sg * 0.04, -0.15, -0.12)) * h, Vector((sg * 0.6, -0.6, 0.3)))
    elif rig.grip == 'one_hand':
        gun(lead, 0.0, Vector((-s * 0.03, -0.03, -0.22)) * h, Vector((-s * 0.04, -0.14, -0.13)) * h, Vector((s * 0.55, -0.65, 0.3)))
        if off in rig.sides:
            S_off = rig.shoulder(off, B)
            free = track(t, [(0.0, S_off + Vector((-s * 0.05, -0.20, -0.06)) * h, None), (Hs, S_off + Vector((-s * 0.02, -0.16, -0.10)) * h, ant),
                             (R, S_off + Vector((-s * 0.02, -0.16, -0.10)) * h, smooth), (R + .05, S_off + Vector((-s * 0.03, -0.17, -0.07)) * h, ease_out),
                             (R + .5, S_off + Vector((-s * 0.05, -0.20, -0.06)) * h, smooth)])
            A2, F2, H2 = rig.arm_ik(off, B, free, Vector((-s * 0.7, -0.5, 0.2)), 'follow')
            finish_arms(rig, poses, B, off, A2, F2, H2)
    else:
        H, rot = gun(lead, 0.0, Vector((-s * 0.08, -0.07, -0.14)) * h, Vector((-s * 0.05, -0.15, -0.13)) * h, Vector((s * 0.6, -0.6, 0.35)))
        if off in rig.sides:
            A2, F2, H2 = rig.arm_ik(off, B, grip_target(rig, lead, H), Vector((-s * 0.6, -0.75, 0.1)), 'aim', aim=rot,
                                    auto=SUPPORT_AUTO, roll_axis=gun_axis(rig, lead, rot), roll_max=math.pi)
            finish_arms(rig, poses, B, off, A2, F2, H2)
    legs_rest(rig, poses)
    return poses


# Side sword guard (B1 follow-up, 2026-10-19), FK keys of the sword arm: upper-arm direction
# (azimuth deg from straight out toward the front, elevation deg up from hanging), roll about
# itself (deg, left-arm sense) and elbow flexion (deg). The sword rises beside the head with
# the upper arm out to the side (v3's hold height; an upper arm raised in front is what webbed
# jokull's coat), the blade leaning forward so the wrist twists a third as much; the cut drops
# the elbow at the side, at most ~40 deg in the first key (a bigger drop under a forward-pointing
# forearm rolls it past the 45 deg/key flip budget), and only then swings the arm forward low.
# sword_guard() picks it per hero where the front guard's cut webs the shoulder skin.
SWORD_SIDE_KEYS = {
    'raised': (40.0, 50.0, 0.0, 95.0),
    'windup': (-20.0, 108.0, -40.0, 70.0),
    'mid':    (10.0, 70.0, -10.0, 65.0),
    'strike': (100.0, 30.0, 0.0, 50.0),
    'follow': (115.0, 30.0, -10.0, 40.0),
}


def sword_guard(rig: Rig) -> str:
    """'front' (v4) or 'side': the guard whose wind-up, hold and cut stretch the sword arm's
    shoulder/elbow skin less (sampled poses, skin_web); the side guard must win clearly."""
    key = ('sword_guard',)
    if key in rig.cache: return rig.cache[key]
    lead = rig.lead
    if lead not in rig.skin:
        rig.cache[key] = 'front'
        return 'front'
    R = ATTACK_RELEASE
    times = [0.42, 0.60, HOLD_START['sword'], R + 1.0 / 60, R + 1.0 / 30, R + 1.5 / 30, R + 2.0 / 30, R + 3.0 / 30,
             R + 0.15, R + 0.20, R + 0.30]
    saved = (rig.prev_hinge, rig.prev_hand, rig.prev_twist, dict(rig.clamped))
    totals = {}
    for family in ('front', 'side'):
        rig.prev_hinge, rig.prev_hand, rig.prev_twist = {}, {}, {}
        cost = count = 0.0
        for t in times:
            poses = sword_pose(rig, t, family=family)
            c, n = rig.skin_web(lead, poses['Body'], poses['Arm' + lead], poses['Forearm' + lead])
            cost += c; count += n
        totals[family] = (round(cost, 3), int(count))
    rig.prev_hinge, rig.prev_hand, rig.prev_twist, rig.clamped = saved
    front, side = totals['front'][0], totals['side'][0]
    choice = 'side' if front > SIDE_GUARD_FRONT_MIN * len(times) and side < SIDE_GUARD_MARGIN * front else 'front'
    rig.cache[key] = choice
    rig.cache[('sword_guard_cost',)] = totals
    return choice


def sword_side_arm(rig: Rig, t: float) -> tuple:
    """Side guard: the sword arm's FK track (body-space upper-arm rotation, elbow flexion),
    keyed on the front guard's times and starting/ending on the front guard's arm."""
    key = ('sword_side_keys',)
    if key not in rig.cache:
        lead = rig.lead; R = ATTACK_RELEASE; Hs = HOLD_START['sword']; Ra = 0.42
        K1, K2 = R + 1.0 / FPS, R + 3.0 / FPS
        B0, target, pole, rest_tip, tip = sword_pose(rig, 0.0, True, 'front')
        saved = (rig.prev_hinge, rig.prev_hand, rig.prev_twist)
        rig.prev_hinge, rig.prev_hand, rig.prev_twist = {}, {}, {}
        A0, F0, _ = rig.arm_ik(lead, B0, target, pole, 'tip', aim=(rest_tip, tip), auto=SWORD_AUTO)
        rig.prev_hinge, rig.prev_hand, rig.prev_twist = saved
        start = rig.arm_key_of(lead, B0, A0, F0)
        k = {n: rig.arm_key(lead, *v) for n, v in SWORD_SIDE_KEYS.items()}
        rig.cache[key] = [(0.0, start, None), (Ra, k['raised'], smooth), (Hs, k['windup'], ant), (R, k['windup'], smooth),
                          (K1, k['mid'], linear), (K2, k['strike'], linear), (R + .20, k['follow'], back_out), (R + .5, start, smooth)]
    return track(t, rig.cache[key], lambda a, b, u: (qslerp(a[0], b[0], u), a[1] + (b[1] - a[1]) * u))


def sword_pose(rig: Rig, t: float, parts_only: bool = False, family: str = None):
    h = rig.h; lead, off = rig.lead, rig.off; s = rig.side_sign(lead)
    family = family or sword_guard(rig)
    R = ATTACK_RELEASE
    Hs = HOLD_START['sword']
    yaw = track(t, [(0.0, -s * 0.10, None), (Hs, -s * 0.45, ant), (R, -s * 0.45, smooth), (R + .07, s * 0.45, ease_out),
                    (R + .15, s * 0.62, smooth), (R + .30, s * 0.40, back_out), (R + .5, -s * 0.10, smooth)])
    pitch = track(t, [(0.0, 0.03, None), (Hs, -0.035, ant), (R, -0.035, smooth), (R + .07, 0.16, ease_out),
                      (R + .22, 0.11, back_out), (R + .5, 0.03, smooth)])
    shift = track(t, [(0.0, Vector((0, 0, 0)), None), (Hs, Vector((s * 0.012 * h, -HOLD_DIP * h, 0.01 * h)), ant), (R, Vector((s * 0.012 * h, -HOLD_DIP * h, 0.01 * h)), smooth),
                      (R + .08, Vector((-s * 0.02 * h, -0.035 * h, -0.025 * h)), ease_out), (R + .25, Vector((-s * 0.015 * h, -0.015 * h, -0.02 * h)), back_out),
                      (R + .5, Vector((0, 0, 0)), smooth)])
    B = rig.body_matrix(shift, yaw=yaw, pitch=pitch)
    poses = {'Body': B}
    S_lead = rig.shoulder(lead, B); S_off = rig.shoulder(off, B)
    # v4: the hand travels on arcs about the shoulder (guard -> raise in front -> wind-up
    # over the shoulder -> overhead diagonal cut across), the blade direction is a target
    # the elbow swivel and forearm carry first and the wrist only finishes, and every
    # direction key is slerped (no blade flipping through a near-zero chord).
    Ra = 0.42
    guard = Vector((-s * 0.06, -0.12, -0.16)) * h
    raised = Vector((s * 0.04, 0.08, -0.22)) * h
    # The front guard holds the blade up in front of the shoulder, a hand above it (the
    # first v4 wind-up rose higher and further back and rolled the upper arm 77 deg against
    # the body); a blade cocked past square to the forearm (phantom, 113 deg) guards
    # overhead, where its wrist stays inside the budget.
    cocked = lead in rig.tip and rig.tip[lead].angle((rig.P['Hand' + lead] - rig.P['Forearm' + lead]).normalized()) > math.radians(100.0)
    windup = (Vector((s * 0.06, 0.24, -0.10)) if cocked else Vector((s * 0.06, 0.16, -0.15))) * h
    reach = rig.arm_length(lead)
    strike = Vector((-s * 0.30, -0.13, -0.22)).normalized() * (0.93 * reach)
    follow = Vector((-s * 0.34, -0.19, -0.17)).normalized() * (0.95 * reach)
    mid = Vector((-s * 0.10, -0.02, -0.25)).normalized() * (0.85 * reach)     # chest height in front: the cut comes down
    # The cut runs over the first keys after the release (mid at +1 key, strike at +3 keys,
    # 30 fps) instead of v3's 75 % of the sweep in the first key.
    K1, K2 = R + 1.0 / FPS, R + 3.0 / FPS
    offset = track(t, [(0.0, guard, None), (Ra, raised, smooth), (Hs, windup, ant), (R, windup, smooth), (K1, mid, linear), (K2, strike, linear),
                       (R + .20, follow, back_out), (R + .5, guard, smooth)], arc)
    offset += Vector((0, tremble(t, 0.002 * h, 9.0), 0))
    tip_guard = Vector((-s * 0.1, 0.55, -0.83)); tip_raise = Vector((s * 0.05, 0.7, -0.7)); tip_wind = Vector((s * 0.06, 0.98, 0.15))
    if family == 'side':
        tip_wind = Vector((s * 0.05, 0.9, -0.4))     # the side guard's blade leans forward: a third of the wrist twist
    tip_mid = Vector((-s * 0.1, 0.1, -0.99)); tip_strike = Vector((-s * 0.75, -0.55, -0.37)); tip_follow = Vector((-s * 0.8, -0.5, -0.3))
    tip = track(t, [(0.0, tip_guard, None), (Ra, tip_raise, smooth), (Hs, tip_wind, ant), (R, tip_wind, smooth), (K1, tip_mid, linear),
                    (K2, tip_strike, linear), (R + .20, tip_follow, back_out), (R + .5, tip_guard, smooth)], slerp_dir)
    pole = track(t, [(0.0, Vector((s * 0.6, -0.7, 0.2)), None), (Ra, Vector((s * 0.7, -0.5, -0.5)), smooth),
                     (Hs, Vector((s * 0.5, 0.25, -0.85)), ant), (R, Vector((s * 0.5, 0.25, -0.85)), smooth),
                     (K1, Vector((s * 0.5, 0.0, -0.85)), linear), (K2, Vector((s * 0.5, -0.7, -0.1)), linear),
                     (R + .20, Vector((s * 0.3, -0.8, 0.2)), smooth), (R + .5, Vector((s * 0.6, -0.7, 0.2)), smooth)])
    rest_tip = rig.tip.get(lead, Vector((0, 1, 0)))
    if rig.reverse_grip(lead):
        # A blade held point-back along the forearm runs the same cut with the point trailing:
        # every tip key flips, so the wrist does what a forward grip's does.
        tip = -tip
    if family == 'side':
        # Side guard: an FK sword arm (its upper arm never rises in front, see SWORD_SIDE_KEYS);
        # the blade keys are solved on it and slerped like the front guard's.
        q, theta = sword_side_arm(rig, t)
        shoulder_rot, elbow_rot = q.to_matrix().to_4x4(), rig.elbow_rot(lead, theta)
        if parts_only:
            A, F, _ = rig.arm_fk(lead, B, shoulder_rot, elbow_rot)
            return B, F @ rig.P['Hand' + lead], A @ rig.P['Forearm' + lead], rest_tip, tip
        def solve(tk):
            # The blade's roll about itself is free: keep the wrist twist of the last key
            # (the FK arm has no elbow swivel to spare it), so the cut out of the hold does
            # not unwind the wrist in one key.
            Bk, _, _, rt, tp = sword_pose(rig, tk, True, 'side')
            qk, thk = sword_side_arm(rig, tk)
            _, Fk, _ = rig.arm_fk(lead, Bk, qk.to_matrix().to_4x4(), rig.elbow_rot(lead, thk))
            RF = Fk.to_3x3().normalized()
            G0 = RF @ rig._wrist_needed(lead, RF, 'tip', (rt, tp)).to_matrix()
            axis = Vector(tp).normalized()
            prev = rig.prev_twist.get(lead)
            best = None
            for k in range(-45, 46):
                G = Matrix.Rotation(math.radians(2.0 * k), 3, axis) @ G0
                qw = (RF.transposed() @ G).to_quaternion()
                if qw.w < 0: qw.negate()
                tw = rig._wrist_parts(lead, qw)[1]
                if prev is not None:
                    while tw - prev > math.pi: tw -= TAU
                    while tw - prev < -math.pi: tw += TAU
                cost = rig._wrist_cost(lead, RF, 'aim', G, None, None, None, 0.0)
                if prev is not None: cost += TWIST_MEMORY * ((tw - prev) / math.radians(30.0)) ** 2
                if best is None or cost < best[0]: best = (cost, G, tw)
            H = rig.arm_fk(lead, Bk, qk.to_matrix().to_4x4(), rig.elbow_rot(lead, thk), 'aim', aim=best[1])[2]
            rig.prev_twist[lead] = best[2]
            return H
        G = keyed_hand(rig, lead, 'sword-side', [(0.0, None), (Ra, smooth), (Hs, ant), (R, smooth), (K1, linear), (K2, linear),
                                                 (R + .20, back_out), (R + .5, smooth)],
                       lambda tk: sword_pose(rig, tk, True, 'side'), t, 0.0, solve)
        A, F, H = rig.arm_fk(lead, B, shoulder_rot, elbow_rot, 'aim', aim=G)
    else:
        if parts_only:
            return B, S_lead + offset, pole, rest_tip, tip
        # The mid key is solved too (the blade points forward there): turning the hand evenly
        # hold -> strike left the blade arc to a per-frame swing that rolled the wrist 55 deg in
        # the first key of the chest-height cut (finn).
        cut = [(K1, linear), (K2, linear)]
        G = keyed_hand(rig, lead, 'sword', [(0.0, None), (Ra, smooth), (Hs, ant), (R, smooth)] + cut +
                       [(R + .20, back_out), (R + .5, smooth)],
                       lambda tk: sword_pose(rig, tk, True, 'front'), t, SWORD_AUTO)
        A, F, H = rig.arm_ik(lead, B, S_lead + offset, pole, 'aim', aim=G, auto=SWORD_AUTO)
    finish_arms(rig, poses, B, lead, A, F, H)
    if off in rig.sides:
        # The free hand counterbalances the cut on an arc about its shoulder (v3's chord threw
        # it from the chest to behind the hip in one key), relaxed low in front.
        off_guard = Vector((s * 0.05, -0.25, -0.10)) * h      # relaxed, low in front: a soft elbow
        off_wind = Vector((s * 0.04, -0.22, -0.13)) * h
        off_strike = Vector((-s * 0.05, -0.31, -0.02)) * h      # drops to the side (no swing behind)
        target = S_off + track(t, [(0.0, off_guard, None), (Hs, off_wind, ant), (R, off_wind, smooth), (K2, off_strike, smooth),
                                   (R + .5, off_guard, back_out)], arc)
        # No pole: the elbow starts from the twist-free plane and its swivel is chosen with the
        # shoulder/elbow skin web in the cost (a rolled upper arm stretched jokull's shoulder and
        # elbow skin into a web below the sword in the cut).
        A2, F2, H2 = rig.arm_ik(off, B, target, None, 'follow', skin=SKIN_WEIGHT)
        finish_arms(rig, poses, B, off, A2, F2, H2)
    legs_rest(rig, poses)
    return poses


def cast_pose(rig: Rig, t: float) -> dict:
    h = rig.h; lead, off = rig.lead, rig.off; s = rig.side_sign(lead)
    R = ATTACK_RELEASE
    Hs = HOLD_START['cast']
    pitch = track(t, [(0.0, -0.02, None), (Hs, -0.06, ant), (R, -0.06, smooth), (R + .08, 0.15, ease_out),
                      (R + .25, 0.085, back_out), (R + .5, -0.02, smooth)])
    shift = track(t, [(0.0, Vector((0, 0, 0)), None), (Hs, Vector((0, -HOLD_DIP * h, 0.012 * h)), ant), (R, Vector((0, -HOLD_DIP * h, 0.012 * h)), smooth),
                      (R + .08, Vector((0, -0.035 * h, -0.03 * h)), ease_out), (R + .5, Vector((0, 0, 0)), back_out)])
    B = rig.body_matrix(shift, pitch=pitch, yaw=0.02 * math.sin(TAU * t / 0.8) * (1 if t < R else 0))
    poses = {'Body': B}
    charge = clamp01((t - 0.3) / (Hs - 0.3))
    orbit = Vector((math.cos(TAU * 1.5 * charge), math.sin(TAU * 1.5 * charge), 0)) * 0.02 * h * bump(charge)
    for side in rig.sides:
        sg = rig.side_sign(side)
        S2 = rig.shoulder(side, B)
        ready = Vector((-sg * 0.12, -0.12, -0.14)) * h
        gather = Vector((-sg * 0.08, -0.03, -0.17)) * h
        push = Vector((-sg * 0.06, 0.02, -0.30)) * h
        recoil = Vector((-sg * 0.07, 0.01, -0.27)) * h
        offset = track(t, [(0.0, ready, None), (Hs, gather, ant), (R, gather, smooth), (R + .08, push, ease_out),
                           (R + .14, recoil, smooth), (R + .24, push, back_out), (R + .5, ready, smooth)])
        offset += orbit * (1 if side == lead else -1) + Vector((0, tremble(t, 0.003 * h, 13.0), 0))
        pole = Vector((sg * 0.7, -0.5, 0.1))
        A, F, H = rig.arm_ik(side, B, S2 + offset, pole, 'follow', Rx(-0.5 * clamp01((t - R) / 0.08)) if t > R else I4)
        finish_arms(rig, poses, B, side, A, F, H)
    legs_rest(rig, poses)
    return poses


def artillery_pose(rig: Rig, t: float) -> dict:
    h = rig.h
    R = ATTACK_RELEASE
    Hs = HOLD_START['artillery']
    dip = track(t, [(0.0, -0.010 * h, None), (Hs, -(0.010 + HOLD_DIP) * h, ant), (R, -(0.010 + HOLD_DIP) * h, smooth), (R + .04, -0.068 * h, ease_out),
                    (R + .12, -0.020 * h, back_out), (R + .20, -0.036 * h, smooth), (R + .30, -0.028 * h, smooth), (R + .5, -0.010 * h, smooth)])
    pitch = track(t, [(0.0, 0.06, None), (Hs, 0.10, ant), (R, 0.10, smooth), (R + .04, 0.20, ease_out), (R + .12, 0.06, back_out),
                      (R + .20, 0.10, smooth), (R + .5, 0.06, smooth)])
    back = track(t, [(0.0, 0.0, None), (R, 0.0, smooth), (R + .04, 0.025 * h, ease_out), (R + .18, 0.0, back_out)])
    B = rig.body_matrix((0, dip + tremble(t, 0.002 * h, 14.0), back), pitch=pitch)
    poses = {'Body': B}
    for side in rig.sides:
        sg = rig.side_sign(side)
        S2 = rig.shoulder(side, B)
        brace = Vector((sg * 0.02, -0.24, -0.08)) * h
        deep = Vector((sg * 0.0, -0.27, -0.11)) * h
        jolt = Vector((sg * 0.05, -0.29, -0.06)) * h
        offset = track(t, [(0.0, brace, None), (Hs, deep, ant), (R, deep, smooth), (R + .05, jolt, ease_out), (R + .22, deep, back_out), (R + .5, brace, smooth)])
        A, F, H = rig.arm_ik(side, B, S2 + offset, Vector((sg * 0.8, -0.3, 0.3)), 'follow')
        finish_arms(rig, poses, B, side, A, F, H)
    legs_rest(rig, poses)
    return poses


def tool_pose(rig: Rig, t: float, parts_only: bool = False):
    h = rig.h; lead, off = rig.lead, rig.off; s = rig.side_sign(lead)
    R = ATTACK_RELEASE
    Hs = HOLD_START['tool']
    yaw = track(t, [(0.0, 0.0, None), (Hs, s * 0.30, ant), (R, s * 0.30, smooth), (R + .07, -s * 0.38, ease_out),
                    (R + .16, -s * 0.42, smooth), (R + .5, 0.0, back_out)])
    pitch = track(t, [(0.0, 0.02, None), (Hs, -0.05, ant), (R, -0.05, smooth), (R + .08, 0.15, ease_out), (R + .22, 0.10, back_out), (R + .5, 0.02, smooth)])
    dip = track(t, [(0.0, 0.0, None), (Hs, -HOLD_DIP * h, ant), (R, -HOLD_DIP * h, smooth), (R + .08, -0.045 * h, ease_out), (R + .5, 0.0, back_out)])
    B = rig.body_matrix((0, dip, 0), yaw=yaw, pitch=pitch)
    poses = {'Body': B}
    S_lead = rig.shoulder(lead, B); S_off = rig.shoulder(off, B)
    ready = Vector((-s * 0.04, 0.02, -0.16)) * h; windup = Vector((s * 0.06, 0.24, 0.04)) * h
    strike = Vector((-s * 0.08, -0.16, -0.26)) * h; rebound = Vector((-s * 0.08, -0.11, -0.24)) * h
    # v4: the blow runs over three keys (overhead-front at +1 key, down at +3 keys) on an arc.
    K1, K2 = R + 1.0 / FPS, R + 3.0 / FPS
    mid = Vector((-s * 0.04, -0.04, -0.26)) * h       # in front at chest height: a straight downward blow
    offset = track(t, [(0.0, ready, None), (Hs, windup, ant), (R, windup, smooth), (K1, mid, linear), (K2, strike, linear),
                       (R + .20, rebound, back_out), (R + .5, ready, smooth)], arc)
    tip = track(t, [(0.0, Vector((0, 0.7, -0.7)), None), (Hs, Vector((s * 0.12, 0.95, 0.28)), ant), (R, Vector((s * 0.12, 0.95, 0.28)), smooth),
                    (K1, Vector((-s * 0.05, 0.2, -0.98)), linear), (K2, Vector((-s * 0.1, -0.5, -0.85)), linear),
                    (R + .20, Vector((-s * 0.1, -0.2, -0.97)), back_out), (R + .5, Vector((0, 0.7, -0.7)), smooth)],
                slerp_dir)
    pole = track(t, [(0.0, Vector((s * 0.6, -0.3, 0.1)), None), (Hs, Vector((s * 0.8, 0.4, 0.3)), ant), (R, Vector((s * 0.8, 0.4, 0.3)), smooth),
                     (K1, Vector((s * 0.8, -0.1, 0.0)), linear), (K2, Vector((s * 0.5, -0.6, -0.1)), linear),
                     (R + .5, Vector((s * 0.6, -0.3, 0.1)), smooth)])
    rest_tip = rig.tip.get(lead, Vector((0, 1, 0)))
    if parts_only:
        return B, S_lead + offset, pole, rest_tip, tip
    G = keyed_hand(rig, lead, 'tool', [(0.0, None), (Hs, ant), (R, smooth), (K2, linear), (R + .20, back_out),
                                       (R + .5, smooth)],
                   lambda tk: tool_pose(rig, tk, True), t, SWORD_AUTO)
    A, F, H = rig.arm_ik(lead, B, S_lead + offset, pole, 'aim', aim=G, auto=SWORD_AUTO)
    finish_arms(rig, poses, B, lead, A, F, H)
    if off in rig.sides:
        target = track(t, [(0.0, S_off + Vector((s * 0.04, -0.18, -0.08)) * h, None), (Hs, S_off + Vector((s * 0.03, -0.14, -0.12)) * h, ant),
                           (R, S_off + Vector((s * 0.03, -0.14, -0.12)) * h, smooth), (R + .08, S_off + Vector((s * 0.02, -0.16, 0.0)) * h, ease_out),
                           (R + .5, S_off + Vector((s * 0.04, -0.18, -0.08)) * h, smooth)])
        A2, F2, H2 = rig.arm_ik(off, B, target, Vector((-s * 0.7, -0.4, 0.2)), 'follow')
        finish_arms(rig, poses, B, off, A2, F2, H2)
    legs_rest(rig, poses)
    return poses


def release_checks(rig: Rig, row: dict, frames: list) -> dict:
    """Release socket facing at the hold (runtime HOLD_T), the release and 65 ms after it,
    and how far the attack wrists ran into their soft limits (rig.clamped, deg)."""
    out = {'attack_wrist_limit_excess_deg': {k: round(math.degrees(v), 1) for k, v in rig.clamped.items()}}
    dots = {}
    hold_t = {'bow': 0.86, 'sword': 0.85, 'tool': 0.85, 'cast': 0.90, 'artillery': 0.90, 'rifle': 0.25}.get(rig.kind, 0.86)
    for n, socket in enumerate(row.get('sockets', [])):
        bone = str(socket['bone']).removeprefix('Skin')
        r = socket.get('rotation_xyz', [0.0, 0.0, 0.0])
        rest = Euler((float(r[0]), float(r[1]), float(r[2])), 'XYZ').to_matrix()
        for label, t in (('hold', hold_t), ('release', ATTACK_RELEASE), ('release+65ms', ATTACK_RELEASE + 0.065)):
            M = frames[min(len(frames) - 1, int(round(t * FPS)))].get(bone, I4)
            fwd = (M.to_3x3().normalized() @ rest @ FORWARD).normalized()
            dots['%d:%s' % (n, label)] = round(fwd.dot(FORWARD), 4)
    out['socket_forward_dot'] = dots
    holds = {k[1]: [round(c / rig.h, 3) for c in v] for k, v in rig.cache.items() if k[0] == 'gun_hold'}
    if holds: out['gun_hold_offset_h'] = holds
    if ('sword_guard',) in rig.cache:
        out['sword_guard'] = rig.cache[('sword_guard',)]
        out['sword_guard_skin'] = {k: {'cost': v[0], 'edges': v[1]} for k, v in rig.cache[('sword_guard_cost',)].items()} \
            if ('sword_guard_cost',) in rig.cache else {}
    # Shoulder/elbow skin webs over the attack (source mesh edges stretched past 2.2x, skin_web).
    web = {}
    for side in rig.sides:
        counts = [rig.skin_web(side, f['Body'], f['Arm' + side], f['Forearm' + side])[1] for f in frames if ('Arm' + side) in f]
        if counts: web[side] = {'max': max(counts), 'mean': round(sum(counts) / len(counts), 1)}
    out['attack_skin_web_edges'] = web
    return out


# ----------------------------------------------------------------------------
# Action writing
# ----------------------------------------------------------------------------
def write_action(rig: Rig, name: str, frame_poses: list) -> None:
    ob = rig.ob
    action = bpy.data.actions.new(name)
    for bone in ob.pose.bones:
        bone.rotation_mode = 'QUATERNION'
        ml = ob.data.bones[bone.name].matrix_local
        mli = ml.inverted()
        key = bone.name.removeprefix('Skin')
        locs, quats, scales = [], [], []
        prev = None
        for poses in frame_poses:
            M = poses.get(key, I4)
            basis = mli @ C @ M @ CI @ ml
            loc, q, sc = basis.decompose()
            if prev is not None and q.dot(prev) < 0: q = -q
            prev = q
            locs.append(loc); quats.append(q); scales.append(sc)
        for path, values, n in [('location', locs, 3), ('rotation_quaternion', quats, 4), ('scale', scales, 3)]:
            for i in range(n):
                fc = action.fcurves.new(data_path=f'pose.bones["{bone.name}"].{path}', index=i, action_group=bone.name)
                fc.keyframe_points.add(len(values))
                co = []
                for f, v in enumerate(values): co.extend((float(f), float(v[i])))
                fc.keyframe_points.foreach_set('co', co)
                for kp in fc.keyframe_points: kp.interpolation = 'LINEAR'
                fc.update()
    track_ = ob.animation_data.nla_tracks.new()
    track_.name = name
    strip = track_.strips.new(name, 0, action)
    track_.mute = True
    strip.mute = False



sys.path.insert(0, str(Path(__file__).resolve().parent))
from glb_animation_merge import merge_animations  # noqa: E402


def base_glb(cid: str, dest: Path) -> bytes:
    """The reviewed runtime GLB whose geometry bytes are preserved across motion versions."""
    keep = ROOT / 'build/motion-overhaul/glb-base' / f'{cid}.glb'
    if keep.exists(): return keep.read_bytes()
    keep.parent.mkdir(parents=True, exist_ok=True)
    import subprocess
    result = subprocess.run(['git', '-C', str(ROOT), 'show', f'HEAD:art/models/{cid}/{cid}.glb'], capture_output=True)
    payload = result.stdout if result.returncode == 0 and len(result.stdout) > 1000 else dest.read_bytes()
    keep.write_bytes(payload)
    return payload


def author(cid: str, candidate: str = '') -> dict:
    specs = json.loads(SPECS.read_text())['heroes']
    manifest = json.loads(MANIFEST.read_text())
    spec = specs[cid]; row = manifest['heroes'][cid]
    work = ROOT / 'build/character-3d/source' / cid
    source = work / 'game.blend'
    if not source.exists(): raise FileNotFoundError(source)
    backup = work / 'game.motion-v1.blend'
    if candidate:
        # Review mode: author into a copy; the editable source, art/models and the
        # manifest are never written.
        cand_dir = Path(candidate) / cid
        cand_dir.mkdir(parents=True, exist_ok=True)
        copy = cand_dir / 'game.blend'
        shutil.copy2(source, copy)
        source = copy
    elif not backup.exists(): shutil.copy2(source, backup)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    rig_ob = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    rig = Rig(cid, spec, row, rig_ob, meshes)
    # Replace only the motion: actions and NLA.
    if rig_ob.animation_data is None: rig_ob.animation_data_create()
    rig_ob.animation_data.action = None
    for t in list(rig_ob.animation_data.nla_tracks): rig_ob.animation_data.nla_tracks.remove(t)
    for action in list(bpy.data.actions): bpy.data.actions.remove(action, do_unlink=True)
    for bone in rig_ob.pose.bones: bone.matrix_basis = Matrix.Identity(4)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start = 0
    scene.frame_end = int(IDLE_SECONDS * FPS)
    rig.prev_hinge = {}; rig.prev_hand = {}; rig.prev_twist = {}
    idle = [idle_pose(rig, f / FPS) for f in range(int(IDLE_SECONDS * FPS) + 1)]
    rig.prev_hinge = {}; rig.prev_hand = {}; rig.prev_twist = {}
    for f in range(WALK_FRAMES): walk_pose(rig, f / WALK_FRAMES)          # warm the elbow-plane memory round the loop
    walk = [walk_pose(rig, f / WALK_FRAMES) for f in range(WALK_FRAMES)]
    walk.append(walk[0])                                                    # exact loop seam
    rig.prev_hinge = {}; rig.prev_hand = {}; rig.prev_twist = {}
    rig.clamped = {}
    attack = []
    hold = HOLD_START.get(rig.kind, ATTACK_RELEASE)
    for f in range(int(ATTACK_SECONDS * FPS) + 1):
        t = f / FPS
        held = hold + 1e-9 < t <= ATTACK_RELEASE + 1e-9 and attack and (f - 1) / FPS >= hold - 1e-9
        # The hold (HOLD_START .. release) is dead still: every hold key repeats the first one,
        # so the elbow-plane memory cannot creep across it.
        attack.append(dict(attack[-1]) if held else attack_pose(rig, t))
    checks = release_checks(rig, row, attack)
    write_action(rig, 'IdleLoop', idle)
    write_action(rig, 'WalkLoop', walk)
    write_action(rig, 'Attack', attack)
    rig_ob.animation_data.action = None
    for bone in rig_ob.pose.bones: bone.matrix_basis = Matrix.Identity(4)
    scene.frame_set(0)
    bpy.ops.wm.save_as_mainfile(filepath=str(source))
    bpy.ops.object.select_all(action='SELECT')
    dest = ROOT / 'art/models' / cid / f'{cid}.glb'
    export_temp = work / 'runtime-export.glb'
    bpy.ops.export_scene.gltf(filepath=str(export_temp), export_format='GLB', export_apply=False,
        export_materials='EXPORT', export_extras=True, export_yup=True, export_animations=True,
        export_nla_strips=True, export_anim_single_armature=True, export_cameras=False, export_lights=False)
    fresh = export_temp.read_bytes()
    export_temp.unlink()
    base = base_glb(cid, dest)
    payload = merge_animations(base, fresh)
    previous_sha = hashlib.sha256(dest.read_bytes()).hexdigest() if dest.exists() else ''
    length = struct.unpack_from('<I', payload, 12)[0]
    gltf = json.loads(payload[20:20 + length])
    sha = hashlib.sha256(payload).hexdigest()
    clips = [v['name'] for v in gltf.get('animations', [])]
    motion = {
        'version': MOTION_VERSION,
        'tool': 'tools/3d/author_native_motion.py',
        'authored_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'clips': {'IdleLoop': IDLE_SECONDS, 'WalkLoop': WALK_FRAMES / FPS, 'Attack': ATTACK_SECONDS,
                  'attack_release_time': ATTACK_RELEASE},
        'beats': {'hold_start': HOLD_START.get(rig.kind), 'hold_dip_h': HOLD_DIP, 'breath_h': BREATH_H, 'sway_h': SWAY_H,
                  'fidget_window': list(IDLE_FIDGET)},
        'stride': round(rig.stride, 4), 'leg_swing': round(rig.leg_swing, 4), 'leg_top': round(rig.leg_top, 4),
        'grip': rig.grip, 'lead': rig.lead, 'kind': rig.kind, 'bounce_scale': rig.bounce_scale,
        'arms': {'solver': 'hinge two-bone IK, forearm-relative wrists (soft limits %.0f/%.0f deg), bow rides the hand'
                           % (math.degrees(WRIST_TWIST_MAX), math.degrees(WRIST_BEND_MAX)),
                 'hinge': {k: [round(c, 4) for c in v] for k, v in rig.hinge.items()},
                 'wrist_pivot_offset_m': {k: round(v, 3) for k, v in rig.wrist_offset.items()}, **checks},
        'previous_glb_sha256': previous_sha, 'editable_backup': str(backup),
        'geometry_base_sha256': hashlib.sha256(base).hexdigest(), 'geometry_bytes_preserved': True,
    }
    if candidate:
        out = Path(candidate) / cid / f'{cid}.glb'
        out.write_bytes(payload)
        (Path(candidate) / cid / 'candidate.json').write_text(json.dumps(
            {'id': cid, 'clips': clips, 'glb_bytes': len(payload), 'glb_sha256': sha, 'shipped_glb_sha256': previous_sha,
             'motion': motion, 'blend_copy': str(source)}, indent=2) + '\n')
        print('NATIVE_MOTION_CANDIDATE', cid, out, 'clips=' + ','.join(clips), 'bytes=%d' % len(payload), 'sha=' + sha,
              'socket_dot=%s' % checks.get('socket_forward_dot'), 'wrist_excess=%s' % checks.get('attack_wrist_limit_excess_deg'), flush=True)
        return motion
    dest.write_bytes(payload)
    prov_path = ROOT / 'art/models' / cid / 'provenance.json'
    provenance = json.loads(prov_path.read_text()) if prov_path.exists() else {'id': cid}
    provenance.update(clips=clips, glb_bytes=len(payload), glb_sha256=sha, motion=motion,
                      game_source=str(source))
    prov_path.write_text(json.dumps(provenance, indent=2) + '\n')
    lock = (ROOT / 'build/character-3d/native-manifest.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        current = json.loads(MANIFEST.read_text())
        entry = current['heroes'][cid]
        entry['glb_sha256'] = sha
        entry['motion'] = {'version': MOTION_VERSION, 'stride': round(rig.stride, 4), 'grip': rig.grip,
                           'clips': ['IdleLoop', 'WalkLoop', 'Attack'], 'attack_release_time': ATTACK_RELEASE}
        temp = MANIFEST.with_suffix('.tmp.' + str(os.getpid()))
        temp.write_text(json.dumps(current, indent=2) + '\n')
        temp.replace(MANIFEST)
    finally:
        fcntl.flock(lock, fcntl.LOCK_UN); lock.close()
    print('NATIVE_MOTION', cid, 'clips=' + ','.join(clips), 'bytes=%d' % len(payload), 'sha=' + sha,
          'stride=%.3f' % rig.stride, 'grip=' + rig.grip, 'leg_top=%.3f' % rig.leg_top,
          'socket_dot=%s' % checks.get('socket_forward_dot'), 'wrist_excess=%s' % checks.get('attack_wrist_limit_excess_deg'), flush=True)
    return motion


def _blender_main() -> None:
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument('--ids', required=True)
    p.add_argument('--candidate', default='')
    a = p.parse_args(argv)
    for cid in [i for i in a.ids.split(',') if i]:
        if cid == 'limne': raise ValueError('Limne is authored by tools/3d/style_animate_limne.py')
        author(cid, a.candidate)


_blender_main()
