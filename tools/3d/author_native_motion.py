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

    IdleLoop  6.0 s   breathing, weight shift, weapon micro adjustments, feet planted
    WalkLoop  1 cycle run/walk, left contact at 0 %, right at 50 %, authored at
              full speed; the runtime scrubs it by travelled distance / stride
    Attack    0.0-1.0 s anticipation (time-warped by the actual aim wind),
              release pose at 1.0 s, 1.0-1.5 s release action, recoil, settle

provenance.json and the native manifest glb_sha256 (+ motion parameters) are
updated under the shared manifest lock. The first run keeps a copy of the previous
editable source as game.motion-v1.blend.
"""
import argparse, json, math, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPECS = ROOT / 'tools/3d/native_visual_specs.json'
MANIFEST = ROOT / 'art/models/native_heroes.json'
MOTION_VERSION = 2
FPS = 30
IDLE_SECONDS = 6.0
WALK_FRAMES = 30          # one cycle; frame 30 repeats frame 0
ATTACK_RELEASE = 1.0      # seconds; anticipation is 0..1, release pose at 1.0
ATTACK_SECONDS = 1.5

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
from mathutils import Vector, Matrix, Quaternion

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

def lerp(a, b, u):
    if isinstance(a, Vector) or isinstance(b, Vector):
        return Vector(a).lerp(Vector(b), u)
    return a + (b - a) * u

def track(t, keys):
    """Piecewise interpolation. keys: [(time, value, ease_into_this_key), ...]."""
    if t <= keys[0][0]: return keys[0][1]
    for i in range(1, len(keys)):
        t0, v0, _ = keys[i - 1]
        t1, v1, fn = keys[i]
        if t <= t1:
            if t1 <= t0: return v1
            return lerp(v0, v1, (fn or smooth)((t - t0) / (t1 - t0)))
    return keys[-1][1]


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

    def side_sign(self, side: str) -> float:
        return -1.0 if side == 'L' else 1.0

    def shoulder(self, side, B: Matrix) -> Vector:
        return B @ self.P['Arm' + side]

    # ---- limb construction ---------------------------------------------------
    def arm_fk(self, side, B: Matrix, shoulder_rot: Matrix, elbow_rot: Matrix, hand_mode='follow', hand_rot: Matrix = None):
        S, E, W = self.P['Arm' + side], self.P['Forearm' + side], self.P['Hand' + side]
        A = B @ around(S, shoulder_rot)
        F = A @ around(E, elbow_rot)
        return A, F, self._hand(side, F, hand_mode, hand_rot)

    def arm_ik(self, side, B: Matrix, target: Vector, pole: Vector, hand_mode='follow', hand_rot: Matrix = None, roll: float = 0.0):
        S, E, W = self.P['Arm' + side], self.P['Forearm' + side], self.P['Hand' + side]
        S2 = B @ S
        a = (E - S).length; b = (W - E).length
        to = Vector(target) - S2
        d = clamp(to.length, abs(a - b) + 0.004, a + b - 0.004)
        u = to.normalized() if to.length > 1e-6 else Vector((0, -1, 0))
        pole = Vector(pole)
        v = pole - u * pole.dot(u)
        if v.length < 1e-5:
            v = Vector((0, -1, 0)) - u * Vector((0, -1, 0)).dot(u)
            if v.length < 1e-5: v = Vector((1, 0, 0)) - u * u.x
        v.normalize()
        cos_a = clamp((a * a + d * d - b * b) / (2 * a * d), -1.0, 1.0)
        sin_a = math.sqrt(max(0.0, 1 - cos_a * cos_a))
        E2 = S2 + a * (u * cos_a + v * sin_a)
        W2 = S2 + u * d
        Ra = rot_between(E - S, E2 - S2)
        if roll: Ra = Matrix.Rotation(roll, 4, (E2 - S2).normalized()) @ Ra
        A = T(S2 - S) @ around(S, Ra)
        Rf = rot_between(W - E, W2 - E2)
        F = T(E2 - E) @ around(E, Rf)
        return A, F, self._hand(side, F, hand_mode, hand_rot)

    def _hand(self, side, F: Matrix, mode, hand_rot):
        W = self.P['Hand' + side]
        posed = F @ W
        if mode == 'follow':
            return F @ around(W, hand_rot or I4)
        if mode == 'absolute':
            return T(posed - W) @ around(W, hand_rot or I4)
        return T(posed - W)   # 'upright': keep the rest orientation (bows, staffs)

    def weapon_matrix(self, side, H: Matrix, extra: Matrix = None) -> Matrix:
        """Rigid weapon bone from its hand (translation only for upright bows/staffs)."""
        W = self.P['Hand' + side]
        follows = self.kind in ['sword', 'tool', 'rifle'] or self.spec.get('weapon_follow_hand')
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
    breath = math.sin(TAU * t / 3) * 0.006 * h
    sway = math.sin(TAU * t / 6)
    look = 0.07 * bump((t - 2.4) / 2.2)
    B = rig.body_matrix((sway * 0.010 * h, breath, 0),
                        yaw=0.025 * math.sin(TAU * t / 6 + 1.0) + look,
                        pitch=0.008 * math.sin(TAU * t / 3 + 0.6),
                        roll=-0.018 * sway)
    poses = {'Body': B}
    for side in rig.sides:
        s = rig.side_sign(side)
        phase = 0.0 if side == 'L' else 0.9
        hold = rig.kind == 'rifle' and side in rig.gun_sides
        relax = rig.relax * (1 - 0.08 * math.sin(TAU * t / 3 + phase))
        swing = 0.03 * math.sin(TAU * t / 3 + phase)
        shoulder_rot = Rz(-s * relax) @ Rx(swing + (0.10 if hold else 0.0))
        elbow_rot = Rx(0.06 + 0.04 * math.sin(TAU * t / 3 + phase + 0.5) + (0.18 if hold else 0.0))
        hand_rot = I4
        if rig.kind == 'sword' and side == rig.lead:
            hand_rot = Rx(0.03 * math.sin(TAU * t / 3 + 1.4))
        if rig.kind == 'rifle' and side in rig.gun_sides:
            hand_rot = Rx(0.02 * math.sin(TAU * t / 3 + 0.3))
        A, F, H = rig.arm_fk(side, B, shoulder_rot, elbow_rot, 'follow', hand_rot)
        poses['Arm' + side] = A; poses['Forearm' + side] = F; poses['Hand' + side] = H
        if rig.weapon[side]:
            extra = None
            if rig.kind == 'bow' and side == rig.lead:
                extra = Rz(0.015 * math.sin(TAU * t / 6 + 0.8))
            poses['Weapon' + side] = rig.weapon_matrix(side, H, extra)
    for side in ['L', 'R']:
        if 'Leg' + side in rig.P: poses['Leg' + side] = I4
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
        bend = 0.85 + 0.25 * max(0.0, math.cos(TAU * phi) * (1.0 if side == 'R' else -1.0))
        hand_mode = 'upright' if (rig.kind == 'bow' and side == rig.lead) else 'follow'
        hand_rot = I4
        if rig.kind == 'rifle' and side in rig.gun_sides:
            hand_rot = Rx(0.35) @ rig.aim_rot[side]   # carried gun angles forward-up
        A, F, H = rig.arm_fk(side, B, shoulder_rot, Rx(bend), hand_mode, hand_rot)
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
        A, F, H = rig.arm_ik(lead, B, target, pole, 'absolute', hand_rot)
        poses['Arm' + lead] = A; poses['Forearm' + lead] = F; poses['Hand' + lead] = H
        poses['Weapon' + lead] = rig.weapon_matrix(lead, H)
        if off in rig.sides:
            grip = grip_target(rig, lead, H)
            A2, F2, H2 = rig.arm_ik(off, B, grip, Vector((-s * 0.6, -0.75, 0.1)), 'absolute', hand_rot)
            poses['Arm' + off] = A2; poses['Forearm' + off] = F2; poses['Hand' + off] = H2
            if rig.weapon[off]: poses['Weapon' + off] = rig.weapon_matrix(off, H2)
    return poses


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
    return amp * math.sin(TAU * f * t) * (1 if 0.82 <= t <= 1.0 else 0)


def attack_pose(rig: Rig, t: float) -> dict:
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
    # Nock with the bow close to the chest, then push the bow out while the string
    # hand pulls to the anchor (push-pull draw); the torso blades side-on.
    yaw = track(t, [(0.0, s * 0.35, None), (0.30, s * 0.50, smooth), (0.86, s * 1.0, smooth), (R, s * 1.0, smooth),
                    (R + .06, s * 1.06, ease_out), (R + .30, s * 0.95, smooth), (R + .5, s * 0.35, smooth)])
    pitch = track(t, [(0.0, 0.02, None), (0.86, 0.045, smooth), (R, 0.045, smooth), (R + .05, -0.005, ease_out),
                      (R + .22, 0.05, smooth), (R + .5, 0.02, smooth)])
    dip = track(t, [(0.0, 0.0, None), (0.86, -0.006 * h, smooth), (R, -0.006 * h, smooth), (R + .5, 0.0, smooth)])
    B = rig.body_matrix((0, dip, 0), yaw=yaw, pitch=pitch)
    poses = {'Body': B}
    S_lead = rig.shoulder(lead, B); S_off = rig.shoulder(off, B)
    ready = Vector((s * 0.02, -0.10, -0.16)) * h
    nocked = Vector((s * 0.02, 0.0, -0.17)) * h
    drawn = Vector((s * 0.02, 0.02, -0.31)) * h
    bow_off = track(t, [(0.0, ready, None), (0.30, nocked, smooth), (0.86, drawn, smooth), (R, drawn, smooth),
                        (R + .04, drawn + Vector((0, 0, -0.015 * h)), ease_out),
                        (R + .18, drawn + Vector((s * 0.01 * h, 0.025 * h, 0.02 * h)), smooth), (R + .5, ready, smooth)])
    bow_target = S_lead + bow_off
    bow_kick = Rx(-0.22 * (damp(t - R, 2.2, 6.0) if t > R else 0.0))
    A, F, H = rig.arm_ik(lead, B, bow_target, Vector((-s * 0.3, -0.7, -0.2)), 'upright')
    finish_arms(rig, poses, B, lead, A, F, H, bow_kick)
    nock = bow_target + Vector((-s * 0.02 * h, 0.01 * h, 0.05 * h))
    anchor = Vector((-s * 0.05 * h, 0.80 * h, -0.01 * h))
    draw = track(t, [(0.0, nock, None), (0.30, nock, smooth), (0.86, anchor, smooth), (R, anchor, smooth),
                     (R + .06, anchor + Vector((-s * 0.10 * h, 0.03 * h, 0.07 * h)), ease_out),
                     (R + .30, anchor + Vector((-s * 0.08 * h, -0.02 * h, 0.05 * h)), smooth), (R + .5, nock, smooth)])
    draw += Vector((0, tremble(t, 0.003 * h), 0))
    pole = track(t, [(0.0, Vector((-s * 0.5, -0.4, 0.2)), None), (0.86, Vector((-s * 0.9, 0.35, 0.5)), smooth),
                     (R + .5, Vector((-s * 0.5, -0.4, 0.2)), smooth)])
    A2, F2, H2 = rig.arm_ik(off, B, draw, pole, 'follow')
    finish_arms(rig, poses, B, off, A2, F2, H2)
    legs_rest(rig, poses)
    return poses


def rifle_pose(rig: Rig, t: float) -> dict:
    h = rig.h; lead, off = rig.lead, rig.off; s = rig.side_sign(lead)
    R = ATTACK_RELEASE
    yaw = track(t, [(0.0, -s * 0.10, None), (0.25, -s * 0.26, smooth), (R, -s * 0.26, smooth), (R + .05, -s * 0.30, ease_out),
                    (R + .25, -s * 0.26, smooth), (R + .5, -s * 0.10, smooth)])
    pitch = track(t, [(0.0, 0.03, None), (0.25, 0.055, smooth), (R, 0.055, smooth), (R + .05, 0.005, ease_out),
                      (R + .20, 0.065, smooth), (R + .5, 0.03, smooth)])
    dip = track(t, [(0.0, 0.0, None), (0.25, -0.008 * h, smooth), (R + .05, -0.012 * h, ease_out), (R + .5, 0.0, smooth)])
    B = rig.body_matrix((0, dip, 0), yaw=yaw, pitch=pitch)
    poses = {'Body': B}
    sway_pitch = 0.008 * math.sin(TAU * t / 0.55); sway_yaw = 0.006 * math.cos(TAU * t / 0.7)

    def gun(side, delay, shouldered_offset, ready_offset, pole):
        sg = rig.side_sign(side)
        S2 = rig.shoulder(side, B)
        tr = t - delay
        offset = track(tr, [(0.0, ready_offset, None), (0.25, shouldered_offset, smooth), (R, shouldered_offset, smooth),
                            (R + .04, shouldered_offset + Vector((0, 0.012 * h, 0.04 * h)), ease_out),
                            (R + .20, shouldered_offset, back_out), (R + .5, ready_offset, smooth)])
        muzzle_pitch = track(tr, [(0.0, -0.40, None), (0.25, 0.0, smooth), (R, 0.0, smooth), (R + .04, 0.11, ease_out),
                                  (R + .22, 0.0, back_out), (R + .5, -0.40, smooth)])
        hold = smooth((tr - 0.25) / 0.2) if tr > 0.25 else 0.0
        rot = Rx(muzzle_pitch + sway_pitch * hold) @ Ry(sway_yaw * hold) @ rig.aim_rot[side]
        A, F, H = rig.arm_ik(side, B, S2 + offset, pole, 'absolute', rot)
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
            free = track(t, [(0.0, S_off + Vector((-s * 0.05, -0.20, -0.06)) * h, None), (0.25, S_off + Vector((-s * 0.02, -0.16, -0.10)) * h, smooth),
                             (R, S_off + Vector((-s * 0.02, -0.16, -0.10)) * h, smooth), (R + .05, S_off + Vector((-s * 0.03, -0.17, -0.07)) * h, ease_out),
                             (R + .5, S_off + Vector((-s * 0.05, -0.20, -0.06)) * h, smooth)])
            A2, F2, H2 = rig.arm_ik(off, B, free, Vector((-s * 0.7, -0.5, 0.2)), 'follow')
            finish_arms(rig, poses, B, off, A2, F2, H2)
    else:
        H, rot = gun(lead, 0.0, Vector((-s * 0.08, -0.07, -0.14)) * h, Vector((-s * 0.05, -0.15, -0.13)) * h, Vector((s * 0.6, -0.6, 0.35)))
        if off in rig.sides:
            A2, F2, H2 = rig.arm_ik(off, B, grip_target(rig, lead, H), Vector((-s * 0.6, -0.75, 0.1)), 'absolute', rot)
            finish_arms(rig, poses, B, off, A2, F2, H2)
    legs_rest(rig, poses)
    return poses


def sword_pose(rig: Rig, t: float) -> dict:
    h = rig.h; lead, off = rig.lead, rig.off; s = rig.side_sign(lead)
    R = ATTACK_RELEASE
    yaw = track(t, [(0.0, -s * 0.10, None), (0.85, -s * 0.45, smooth), (R, -s * 0.45, smooth), (R + .07, s * 0.45, ease_out),
                    (R + .15, s * 0.62, smooth), (R + .30, s * 0.40, smooth), (R + .5, -s * 0.10, smooth)])
    pitch = track(t, [(0.0, 0.03, None), (0.85, -0.035, smooth), (R, -0.035, smooth), (R + .08, 0.12, ease_out),
                      (R + .18, 0.14, smooth), (R + .5, 0.03, smooth)])
    shift = track(t, [(0.0, Vector((0, 0, 0)), None), (0.85, Vector((s * 0.012 * h, 0, 0.01 * h)), smooth), (R, Vector((s * 0.012 * h, 0, 0.01 * h)), smooth),
                      (R + .08, Vector((-s * 0.02 * h, -0.02 * h, -0.025 * h)), ease_out), (R + .25, Vector((-s * 0.015 * h, -0.015 * h, -0.02 * h)), smooth),
                      (R + .5, Vector((0, 0, 0)), smooth)])
    B = rig.body_matrix(shift, yaw=yaw, pitch=pitch)
    poses = {'Body': B}
    S_lead = rig.shoulder(lead, B); S_off = rig.shoulder(off, B)
    guard = Vector((-s * 0.06, -0.12, -0.16)) * h
    windup = Vector((s * 0.10, 0.19, 0.09)) * h
    strike = Vector((-s * 0.30, -0.13, -0.22)) * h
    follow = Vector((-s * 0.34, -0.19, -0.17)) * h
    offset = track(t, [(0.0, guard, None), (0.85, windup, smooth), (R, windup, smooth), (R + .09, strike, ease_out),
                       (R + .20, follow, smooth), (R + .5, guard, smooth)])
    offset += Vector((0, tremble(t, 0.002 * h, 9.0), 0))
    tip_guard = Vector((-s * 0.1, 0.55, -0.83)); tip_wind = Vector((s * 0.25, 0.75, 0.6))
    tip_mid = Vector((-s * 0.1, 0.1, -0.99)); tip_strike = Vector((-s * 0.75, -0.55, -0.37)); tip_follow = Vector((-s * 0.8, -0.5, -0.3))
    tip = track(t, [(0.0, tip_guard, None), (0.85, tip_wind, smooth), (R, tip_wind, smooth), (R + .045, tip_mid, ease_out),
                    (R + .09, tip_strike, ease_out), (R + .20, tip_follow, smooth), (R + .5, tip_guard, smooth)])
    pole = track(t, [(0.0, Vector((s * 0.6, -0.4, 0.1)), None), (0.85, Vector((s * 0.7, 0.3, 0.4)), smooth), (R, Vector((s * 0.7, 0.3, 0.4)), smooth),
                     (R + .09, Vector((s * 0.5, -0.6, -0.2)), ease_out), (R + .5, Vector((s * 0.6, -0.4, 0.1)), smooth)])
    rest_tip = rig.tip.get(lead, Vector((0, 1, 0)))
    A, F, H = rig.arm_ik(lead, B, S_lead + offset, pole, 'absolute', rot_between(rest_tip, tip))
    finish_arms(rig, poses, B, lead, A, F, H)
    if off in rig.sides:
        off_guard = S_off + Vector((s * 0.04, -0.16, -0.10)) * h
        off_wind = S_off + Vector((s * 0.02, -0.10, -0.15)) * h
        off_strike = S_off + Vector((-s * 0.0, -0.14, 0.07)) * h
        target = track(t, [(0.0, off_guard, None), (0.85, off_wind, smooth), (R, off_wind, smooth), (R + .09, off_strike, ease_out),
                           (R + .5, off_guard, smooth)])
        A2, F2, H2 = rig.arm_ik(off, B, target, Vector((-s * 0.7, -0.4, 0.2)), 'follow')
        finish_arms(rig, poses, B, off, A2, F2, H2)
    legs_rest(rig, poses)
    return poses


def cast_pose(rig: Rig, t: float) -> dict:
    h = rig.h; lead, off = rig.lead, rig.off; s = rig.side_sign(lead)
    R = ATTACK_RELEASE
    pitch = track(t, [(0.0, -0.02, None), (0.9, -0.06, smooth), (R, -0.06, smooth), (R + .08, 0.12, ease_out),
                      (R + .25, 0.085, smooth), (R + .5, -0.02, smooth)])
    shift = track(t, [(0.0, Vector((0, 0, 0)), None), (0.9, Vector((0, -0.01 * h, 0.012 * h)), smooth), (R, Vector((0, -0.01 * h, 0.012 * h)), smooth),
                      (R + .08, Vector((0, -0.016 * h, -0.03 * h)), ease_out), (R + .5, Vector((0, 0, 0)), smooth)])
    B = rig.body_matrix(shift, pitch=pitch, yaw=0.02 * math.sin(TAU * t / 0.8) * (1 if t < R else 0))
    poses = {'Body': B}
    charge = clamp01((t - 0.3) / 0.6)
    orbit = Vector((math.cos(TAU * 1.5 * charge), math.sin(TAU * 1.5 * charge), 0)) * 0.02 * h * bump(charge)
    for side in rig.sides:
        sg = rig.side_sign(side)
        S2 = rig.shoulder(side, B)
        ready = Vector((-sg * 0.12, -0.12, -0.14)) * h
        gather = Vector((-sg * 0.08, -0.03, -0.17)) * h
        push = Vector((-sg * 0.06, 0.02, -0.30)) * h
        recoil = Vector((-sg * 0.07, 0.01, -0.27)) * h
        offset = track(t, [(0.0, ready, None), (0.9, gather, smooth), (R, gather, smooth), (R + .08, push, ease_out),
                           (R + .14, recoil, smooth), (R + .24, push, smooth), (R + .5, ready, smooth)])
        offset += orbit * (1 if side == lead else -1) + Vector((0, tremble(t, 0.003 * h, 13.0), 0))
        pole = Vector((sg * 0.7, -0.5, 0.1))
        A, F, H = rig.arm_ik(side, B, S2 + offset, pole, 'follow', Rx(-0.5 * clamp01((t - R) / 0.08)) if t > R else I4)
        finish_arms(rig, poses, B, side, A, F, H)
    legs_rest(rig, poses)
    return poses


def artillery_pose(rig: Rig, t: float) -> dict:
    h = rig.h
    R = ATTACK_RELEASE
    dip = track(t, [(0.0, -0.010 * h, None), (0.9, -0.030 * h, smooth), (R, -0.030 * h, smooth), (R + .04, -0.058 * h, ease_out),
                    (R + .12, -0.020 * h, smooth), (R + .20, -0.036 * h, smooth), (R + .30, -0.028 * h, smooth), (R + .5, -0.010 * h, smooth)])
    pitch = track(t, [(0.0, 0.06, None), (0.9, 0.10, smooth), (R, 0.10, smooth), (R + .04, 0.17, ease_out), (R + .12, 0.06, smooth),
                      (R + .20, 0.10, smooth), (R + .5, 0.06, smooth)])
    back = track(t, [(0.0, 0.0, None), (R, 0.0, smooth), (R + .04, 0.02 * h, ease_out), (R + .18, 0.0, smooth)])
    B = rig.body_matrix((0, dip + tremble(t, 0.002 * h, 14.0), back), pitch=pitch)
    poses = {'Body': B}
    for side in rig.sides:
        sg = rig.side_sign(side)
        S2 = rig.shoulder(side, B)
        brace = Vector((sg * 0.02, -0.24, -0.08)) * h
        deep = Vector((sg * 0.0, -0.27, -0.11)) * h
        jolt = Vector((sg * 0.05, -0.29, -0.06)) * h
        offset = track(t, [(0.0, brace, None), (0.9, deep, smooth), (R, deep, smooth), (R + .05, jolt, ease_out), (R + .22, deep, smooth), (R + .5, brace, smooth)])
        A, F, H = rig.arm_ik(side, B, S2 + offset, Vector((sg * 0.8, -0.3, 0.3)), 'follow')
        finish_arms(rig, poses, B, side, A, F, H)
    legs_rest(rig, poses)
    return poses


def tool_pose(rig: Rig, t: float) -> dict:
    h = rig.h; lead, off = rig.lead, rig.off; s = rig.side_sign(lead)
    R = ATTACK_RELEASE
    yaw = track(t, [(0.0, 0.0, None), (0.85, s * 0.30, smooth), (R, s * 0.30, smooth), (R + .07, -s * 0.35, ease_out),
                    (R + .16, -s * 0.42, smooth), (R + .5, 0.0, smooth)])
    pitch = track(t, [(0.0, 0.02, None), (0.85, -0.05, smooth), (R, -0.05, smooth), (R + .08, 0.12, ease_out), (R + .5, 0.02, smooth)])
    dip = track(t, [(0.0, 0.0, None), (R, 0.0, smooth), (R + .08, -0.02 * h, ease_out), (R + .5, 0.0, smooth)])
    B = rig.body_matrix((0, dip, 0), yaw=yaw, pitch=pitch)
    poses = {'Body': B}
    S_lead = rig.shoulder(lead, B); S_off = rig.shoulder(off, B)
    ready = Vector((-s * 0.04, 0.02, -0.16)) * h; windup = Vector((s * 0.06, 0.24, 0.04)) * h
    strike = Vector((-s * 0.08, -0.16, -0.26)) * h; rebound = Vector((-s * 0.08, -0.11, -0.24)) * h
    offset = track(t, [(0.0, ready, None), (0.85, windup, smooth), (R, windup, smooth), (R + .08, strike, ease_out),
                       (R + .20, rebound, smooth), (R + .5, ready, smooth)])
    tip = track(t, [(0.0, Vector((0, 0.7, -0.7)), None), (0.85, Vector((s * 0.2, 0.8, 0.55)), smooth), (R, Vector((s * 0.2, 0.8, 0.55)), smooth),
                    (R + .08, Vector((-s * 0.1, -0.5, -0.85)), ease_out), (R + .20, Vector((-s * 0.1, -0.2, -0.97)), smooth), (R + .5, Vector((0, 0.7, -0.7)), smooth)])
    pole = track(t, [(0.0, Vector((s * 0.6, -0.3, 0.1)), None), (0.85, Vector((s * 0.8, 0.4, 0.3)), smooth), (R, Vector((s * 0.8, 0.4, 0.3)), smooth),
                     (R + .08, Vector((s * 0.5, -0.6, -0.1)), ease_out), (R + .5, Vector((s * 0.6, -0.3, 0.1)), smooth)])
    rest_tip = rig.tip.get(lead, Vector((0, 1, 0)))
    A, F, H = rig.arm_ik(lead, B, S_lead + offset, pole, 'absolute', rot_between(rest_tip, tip))
    finish_arms(rig, poses, B, lead, A, F, H)
    if off in rig.sides:
        target = track(t, [(0.0, S_off + Vector((s * 0.04, -0.18, -0.08)) * h, None), (0.85, S_off + Vector((s * 0.03, -0.14, -0.12)) * h, smooth),
                           (R, S_off + Vector((s * 0.03, -0.14, -0.12)) * h, smooth), (R + .08, S_off + Vector((s * 0.02, -0.16, 0.0)) * h, ease_out),
                           (R + .5, S_off + Vector((s * 0.04, -0.18, -0.08)) * h, smooth)])
        A2, F2, H2 = rig.arm_ik(off, B, target, Vector((-s * 0.7, -0.4, 0.2)), 'follow')
        finish_arms(rig, poses, B, off, A2, F2, H2)
    legs_rest(rig, poses)
    return poses


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


def author(cid: str) -> dict:
    specs = json.loads(SPECS.read_text())['heroes']
    manifest = json.loads(MANIFEST.read_text())
    spec = specs[cid]; row = manifest['heroes'][cid]
    work = ROOT / 'build/character-3d/source' / cid
    source = work / 'game.blend'
    if not source.exists(): raise FileNotFoundError(source)
    backup = work / 'game.motion-v1.blend'
    if not backup.exists(): shutil.copy2(source, backup)
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
    idle = [idle_pose(rig, f / FPS) for f in range(int(IDLE_SECONDS * FPS) + 1)]
    walk = [walk_pose(rig, (f % WALK_FRAMES) / WALK_FRAMES) for f in range(WALK_FRAMES + 1)]
    attack = [attack_pose(rig, f / FPS) for f in range(int(ATTACK_SECONDS * FPS) + 1)]
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
    dest.write_bytes(payload)
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
        'stride': round(rig.stride, 4), 'leg_swing': round(rig.leg_swing, 4), 'leg_top': round(rig.leg_top, 4),
        'grip': rig.grip, 'lead': rig.lead, 'kind': rig.kind, 'bounce_scale': rig.bounce_scale,
        'previous_glb_sha256': previous_sha, 'editable_backup': str(backup),
        'geometry_base_sha256': hashlib.sha256(base).hexdigest(), 'geometry_bytes_preserved': True,
    }
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
          'stride=%.3f' % rig.stride, 'grip=' + rig.grip, 'leg_top=%.3f' % rig.leg_top, flush=True)
    return motion


def _blender_main() -> None:
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument('--ids', required=True)
    a = p.parse_args(argv)
    for cid in [i for i in a.ids.split(',') if i]:
        if cid == 'limne': raise ValueError('Limne is authored by tools/3d/style_animate_limne.py')
        author(cid)


_blender_main()
