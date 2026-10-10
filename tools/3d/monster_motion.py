#!/usr/bin/env python3
"""Shared native-monster motion authoring for Blender 4.0 (30 fps).

Every creature rig is a small set of independent absolute-transform control
bones (``finish_native_monster.py``). This module writes production clip sets
on top of that rig without touching geometry, weights or bone layout:

    IdleLoop  loop   breathing, weight shift, body-specific fidgets
    MoveLoop  loop   body-specific locomotion; one cycle = ``move_frames``/30 s of
                     the simulator clock = 82 logical units of travel
    Attack    loop   crystal siege strike: hold → anticipation → strike → recovery,
                     mapped by the runtime so the strike lands when the siege
                     phase wraps (clip time = (phase - 0.3) mod 1)
    Die       once   body collapse; the runtime adds topple/sink/dissolve

Motion parameters live in ``tools/3d/native_monster_specs.json`` under each
monster's ``motion`` block (shape defaults below are the fallback and the
generator for that block). Blender axes: +Y forward, +Z up, +X right.
"""
import math

from mathutils import Matrix, Vector

TAU = math.tau
FPS = 30
IDLE_FRAMES = 90
ATTACK_FRAMES = 30
DIE_FRAMES = 24
TRAVEL_PER_CLIP_SECOND = 82.0 / 50.0  # Balance.PATH_SPEED logical/s over StellarWorld.UNIT

# --------------------------------------------------------------------------- #
# Easing and cycle helpers
# --------------------------------------------------------------------------- #
def S(t, k=1.0, ph=0.0):
    return math.sin(TAU * (k * t + ph))


def C(t, k=1.0, ph=0.0):
    return math.cos(TAU * (k * t + ph))


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def seg(t, a, b):
    if b <= a:
        return 1.0 if t >= b else 0.0
    return clamp((t - a) / (b - a))


def smooth(x):
    x = clamp(x)
    return x * x * (3.0 - 2.0 * x)


def ease_in(x, p=2.0):
    return clamp(x) ** p


def ease_out(x, p=2.0):
    return 1.0 - (1.0 - clamp(x)) ** p


def back_out(x, s=1.5):
    x = clamp(x) - 1.0
    return 1.0 + x * x * ((s + 1.0) * x + s)


def bump(t, a, b, power=1.0):
    """Sine bump 0→1→0 over [a, b], zero outside."""
    if t <= a or t >= b:
        return 0.0
    return math.sin(math.pi * (t - a) / (b - a)) ** power


def wrap(t):
    return t % 1.0


def leg_cycle(u, stance):
    """Planted-foot cycle. Returns (swing s: +1 forward … -1 back, lift 0..1).

    During the stance fraction the foot travels back at constant speed (so the
    body slides forward over it); during the swing it returns with an eased arc.
    """
    u = wrap(u)
    if u < stance:
        return 1.0 - 2.0 * (u / stance), 0.0
    v = (u - stance) / (1.0 - stance)
    return -1.0 + 2.0 * smooth(v), math.sin(math.pi * v)


def footfall(t, k=2.0, sharpness=0.55):
    """Heavy stomp profile, 1 at each footfall (k per cycle), fast drop and slow rise."""
    x = max(0.0, C(t, k))
    return x ** sharpness


# --------------------------------------------------------------------------- #
# Pose DSL: per bone T · Rpivot · Spivot, optional rigid follow of another bone
# --------------------------------------------------------------------------- #
class Pose:
    def __init__(self, starts, height):
        self.starts = starts
        self.H = height
        self.ops = {}

    def _b(self, bone):
        if bone not in self.starts:
            return None
        return self.ops.setdefault(bone, {"move": Vector((0.0, 0.0, 0.0)), "rots": [],
                                          "scale": Vector((1.0, 1.0, 1.0)), "pivot": None, "follow": None})

    def move(self, bone, v):
        """Translate in height units."""
        b = self._b(bone)
        if b is not None:
            b["move"] += Vector(v) * self.H

    def rot(self, bone, axis, angle):
        """Rotate about the bone pivot. +X nose/top up(back), +Y top to the right, +Z turn left."""
        b = self._b(bone)
        if b is not None and abs(angle) > 1e-9:
            b["rots"].append((axis, angle))

    def scale(self, bone, sx, sy=None, sz=None, pivot=None):
        b = self._b(bone)
        if b is None:
            return
        if sy is None:
            sy = sz = sx
        b["scale"] = Vector((b["scale"].x * sx, b["scale"].y * sy, b["scale"].z * sz))
        if pivot is not None:
            b["pivot"] = Vector(pivot) * self.H

    def pivot(self, bone, p):
        b = self._b(bone)
        if b is not None:
            b["pivot"] = Vector(p) * self.H

    def follow(self, bone, parent):
        b = self._b(bone)
        if b is not None and parent in self.starts:
            b["follow"] = parent

    def shift(self, v):
        """Translate the whole creature: every bone that does not follow another."""
        for bone in self.starts:
            b = self.ops.get(bone)
            if b is None or b["follow"] is None:
                self.move(bone, v)

    def _own(self, bone, with_scale=True):
        b = self.ops.get(bone)
        if b is None:
            return Matrix.Identity(4)
        p = b["pivot"] if b["pivot"] is not None else self.starts[bone]
        rotation = Matrix.Identity(4)
        for axis, angle in b["rots"]:
            rotation = rotation @ Matrix.Rotation(angle, 4, axis)
        scale = Matrix.Identity(4)
        if with_scale:
            scale = Matrix.Diagonal((b["scale"].x, b["scale"].y, b["scale"].z, 1.0))
        return Matrix.Translation(b["move"]) @ Matrix.Translation(p) @ rotation @ scale @ Matrix.Translation(-p)

    def matrices(self):
        memo = {}

        def frame(bone):
            if bone in memo:
                return memo[bone]
            b = self.ops.get(bone)
            m = self._own(bone, with_scale=False)
            if b is not None and b["follow"]:
                m = frame(b["follow"]) @ m
            memo[bone] = m
            return m

        result = {}
        for bone in self.starts:
            b = self.ops.get(bone)
            m = self._own(bone)
            if b is not None and b["follow"]:
                m = frame(b["follow"]) @ m
            result[bone] = m
        return result


class K:
    """Key-pose writer whose every op is scaled by a weight, so key poses blend."""

    def __init__(self, pose, w):
        self.p = pose
        self.w = w

    def move(self, bone, v):
        self.p.move(bone, (v[0] * self.w, v[1] * self.w, v[2] * self.w))

    def rot(self, bone, axis, angle):
        self.p.rot(bone, axis, angle * self.w)

    def scale(self, bone, sx, sy, sz, pivot=None):
        self.p.scale(bone, 1.0 + (sx - 1.0) * self.w, 1.0 + (sy - 1.0) * self.w, 1.0 + (sz - 1.0) * self.w, pivot)

    def shift(self, v):
        self.p.shift((v[0] * self.w, v[1] * self.w, v[2] * self.w))


# --------------------------------------------------------------------------- #
# Parameters
# --------------------------------------------------------------------------- #
FOLLOW = {
    "blob": {"Crown": "Body"},
    "quadruped": {"Head": "Body", "Tail": "Body"},
    "biped": {"Head": "Body", "ArmL": "Body", "ArmR": "Body"},
    "tree": {"Head": "Body", "ArmL": "Body", "ArmR": "Body"},
    "mushroom": {"Head": "Body", "ArmL": "Body", "ArmR": "Body"},
    "dragon": {"Head": "Body", "WingL": "Body", "WingR": "Body", "Tail": "Body", "ArmL": "Body", "ArmR": "Body"},
    "ray": {"Head": "Body", "WingL": "Body", "WingR": "Body", "Tail": "Body"},
    "serpent": {"Neck": "Body", "Head": "Neck", "Tail": "Body", "FinL": "Body", "FinR": "Body"},
    "jelly": {"Cap": "Body", "TentacleL": "Body", "TentacleR": "Body"},
    "idol": {"Crown": "Body"},
    "plant": {"Maw": "Body", "VineL": "Body", "VineR": "Body"},
}

SHAPE_DEFAULTS = {
    "biped": dict(move_frames=13, stance=0.5, leg_swing=0.42, leg_lift=0.07, leg_reach=0.04, bounce=0.035,
                  roll=0.08, yaw=0.08, lean=0.03, arm_swing=0.50, arm_out=0.05, head_bob=0.06, impact=False,
                  attack="smash", death="sink", spawn="rise", hover=0.0, turn_rate=9.0, turn_max=7.0, bank=0.08),
    "quadruped": dict(move_frames=15, gait="gallop", stance=0.35, front_swing=0.45, rear_swing=0.50, leg_lift=0.09,
                      leg_reach=0.11, pitch=0.09, bounce=0.045, stretch=0.05, roll=0.03, yaw=0.02, head_nod=0.07,
                      tail_v=0.25, tail_h=0.10, splay=0.0, undulate=0.0,
                      attack="pounce", death="sink", spawn="rise", hover=0.0, turn_rate=12.0, turn_max=10.0, bank=0.16),
    "blob": dict(move_frames=14, jump=0.30, squash=0.16, lean=0.05,
                 attack="slam", death="splat", spawn="drop", hover=0.0, turn_rate=9.0, turn_max=7.0, bank=0.06),
    "dragon": dict(move_frames=30, stance=0.5, leg_swing=0.28, leg_lift=0.05, leg_reach=0.05, flap=0.30, twist=0.08,
                   bounce=0.04, pitch=0.03, tail_h=0.15, tail_v=0.08,
                   attack="bite", death="sink", spawn="drop", hover=0.0, turn_rate=4.0, turn_max=2.5, bank=0.12),
    "ray": dict(move_frames=21, flap=0.28, twist=0.10, bounce=0.05, pitch=0.06, tail_h=0.22, tail_v=0.12,
                attack="dive", death="sink", spawn="descend", hover=0.12, turn_rate=12.0, turn_max=10.0, bank=0.35),
    "jelly": dict(move_frames=36, pulse=0.14, thrust=0.05, trail=0.25,
                  attack="burst", death="sink", spawn="descend", hover=0.10, turn_rate=6.0, turn_max=4.0, bank=0.10),
    "idol": dict(move_frames=48, bob=0.04, tilt=0.06, sway=0.12,
                 attack="burst", death="topple_side", spawn="descend", hover=0.08, turn_rate=6.0, turn_max=4.0, bank=0.08),
    "serpent": dict(move_frames=33, sway=0.04, weave=0.10, fin=0.20, tail_h=0.28,
                    attack="strike", death="sink", spawn="rise", hover=0.0, turn_rate=4.0, turn_max=2.5, bank=0.04),
    "tree": dict(move_frames=33, stance=0.6, leg_lift=0.03, leg_reach=0.07, leg_swing=0.12, roll=0.08, bounce=0.02,
                 attack="smash", death="topple_back", spawn="rise", hover=0.0, turn_rate=4.5, turn_max=3.0, bank=0.02),
    "mushroom": dict(move_frames=17, stance=0.5, leg_swing=0.30, leg_lift=0.05, leg_reach=0.03, roll=0.10, bounce=0.02,
                     cap=0.08, arm_swing=0.20,
                     attack="capslam", death="sink", spawn="drop", hover=0.0, turn_rate=7.0, turn_max=5.0, bank=0.05),
    "plant": dict(move_frames=36, stance=0.55, root_lift=0.04, root_reach=0.08, heave=0.04, writhe=0.15,
                  attack="maw", death="sink", spawn="rise", hover=0.0, turn_rate=4.0, turn_max=2.5, bank=0.02),
}

KIND_TWEAKS = {
    ("biped", "tank"): dict(move_frames=30, leg_swing=0.34, leg_lift=0.05, leg_reach=0.05, bounce=0.05, roll=0.11,
                            yaw=0.05, lean=0.02, arm_swing=0.22, head_bob=0.05, impact=True, death="topple",
                            turn_rate=5.0, turn_max=3.5, bank=0.03),
    ("biped", "boss"): dict(move_frames=36, leg_swing=0.32, leg_lift=0.05, leg_reach=0.06, bounce=0.055, roll=0.12,
                            yaw=0.05, lean=0.02, arm_swing=0.20, head_bob=0.05, impact=True, death="topple",
                            turn_rate=4.0, turn_max=2.5, bank=0.02),
    ("biped", "caster"): dict(move_frames=23, leg_swing=0.25, leg_lift=0.04, leg_reach=0.03, bounce=0.02, roll=0.04,
                              yaw=0.04, lean=0.02, arm_swing=0.28, head_bob=0.03, attack="staff",
                              turn_rate=7.0, turn_max=5.0, bank=0.05),
    ("quadruped", "tank"): dict(move_frames=26, gait="trot", stance=0.5, front_swing=0.26, rear_swing=0.26, leg_lift=0.06,
                                leg_reach=0.06, pitch=0.02, bounce=0.03, stretch=0.0, roll=0.04, yaw=0.03, head_nod=0.05,
                                tail_v=0.06, tail_h=0.12, attack="ram", turn_rate=5.0, turn_max=3.5, bank=0.04),
}


def motion_params(spec):
    """Merged motion parameters: shape defaults → kind tweaks → spec['motion']."""
    shape = spec["shape"]
    params = dict(SHAPE_DEFAULTS[shape])
    params.update(KIND_TWEAKS.get((shape, spec.get("kind", "")), {}))
    params.update(spec.get("motion", {}))
    return params


def runtime_motion(spec, params=None):
    """The subset the Godot adapter needs (stored in native_monsters.json)."""
    params = params or motion_params(spec)
    return {
        "cycle": round(params["move_frames"] / FPS, 4),
        "death": params["death"],
        "spawn": params["spawn"],
        "hover": params["hover"],
        "turn_rate": params["turn_rate"],
        "turn_max": params["turn_max"],
        "bank": params["bank"],
    }


# --------------------------------------------------------------------------- #
# Choreography
# --------------------------------------------------------------------------- #
class Choreographer:
    def __init__(self, spec, starts, height, params=None):
        self.spec = spec
        self.shape = spec["shape"]
        self.kind = spec.get("kind", "")
        self.starts = starts
        self.H = height
        self.P = params or motion_params(spec)
        self.fixed = list(spec.get("fixed_bones", []))
        self.staff_arm = self.fixed[0] if self.fixed and "Staff" in starts else None
        self.free_arm = None
        if self.staff_arm:
            self.free_arm = "ArmL" if self.staff_arm == "ArmR" else "ArmR"

    # ---- shared ------------------------------------------------------------
    def pose(self, hover_factor=1.0):
        pose = Pose(self.starts, self.H)
        for bone, parent in FOLLOW.get(self.shape, {}).items():
            pose.follow(bone, parent)
        if self.staff_arm:
            pose.follow("Staff", self.staff_arm)
        hover = self.P.get("hover", 0.0) * hover_factor
        if hover:
            for bone in self.starts:
                if bone not in ("Staff",) and pose.ops.get(bone, {}).get("follow") is None:
                    pose.move(bone, (0.0, 0.0, hover))
        return pose

    def arms(self):
        return [b for b in ("ArmL", "ArmR") if b in self.starts and b not in self.fixed]

    def breath(self, pose, t, amount=0.012):
        pose.scale("Body", 1.0, 1.0, 1.0 + amount * S(t, 2))
        pose.move("Body", (0.0, 0.0, amount * 0.35 * S(t, 2)))

    # ---- clip entry points -------------------------------------------------
    def move_pose(self, t):
        pose = self.pose()
        getattr(self, "gait_" + self.shape)(pose, t)
        return pose

    def idle_pose(self, t):
        pose = self.pose()
        getattr(self, "idle_" + self.shape)(pose, t)
        return pose

    def attack_pose(self, t):
        """0–0.3 hold, 0.3–0.62 anticipation, 0.62–0.70 strike, 0.70–1.0 recovery."""
        pose = self.pose()
        if t < 0.30:
            w_a, w_s = 0.0, 0.0
        elif t < 0.62:
            w_a, w_s = smooth((t - 0.30) / 0.32), 0.0
        elif t < 0.70:
            u = (t - 0.62) / 0.08
            w_a, w_s = 1.0 - ease_in(u, 2.2), ease_in(u, 2.2)
        else:
            u = (t - 0.70) / 0.30
            w_s = 1.0 - ease_out(u, 2.6)
            w_a = -0.12 * bump(u, 0.15, 0.85)  # slight settle past neutral
        self.breath(pose, t, 0.008)
        fn = getattr(self, "attack_" + self.P["attack"])
        if abs(w_a) > 1e-6:
            fn(K(pose, w_a), True)
        if w_s > 1e-6:
            fn(K(pose, w_s), False)
        return pose

    def die_pose(self, t):
        keys = getattr(self, "die_" + self.shape)
        times = (0.14, 0.50, 0.76)
        # Fliers fall out of their hover while they collapse.
        hover_factor = 1.0 - smooth(seg(t, 0.12, 0.50))
        pose = self.pose(hover_factor)
        if t < times[0]:
            keys(K(pose, ease_out(t / times[0], 2.0)), 0)
        elif t < times[1]:
            u = smooth((t - times[0]) / (times[1] - times[0]))
            keys(K(pose, 1.0 - u), 0)
            keys(K(pose, u), 1)
        elif t < times[2]:
            u = smooth((t - times[1]) / (times[2] - times[1]))
            keys(K(pose, 1.0 - u), 1)
            keys(K(pose, u), 2)
        else:
            keys(K(pose, 1.0), 2)
        return pose

    # ---- BIPED (imps, giants, casters) -------------------------------------
    def _biped_legs(self, pose, t, swing, lift, reach, stance):
        for side, phase in (("L", 0.0), ("R", 0.5)):
            s, z = leg_cycle(t + phase, stance)
            leg = "Leg" + side
            pose.rot(leg, "X", swing * s)
            pose.move(leg, (0.0, reach * s, lift * z))

    def gait_biped(self, pose, t):
        P = self.P
        self._biped_legs(pose, t, P["leg_swing"], P["leg_lift"], P["leg_reach"], P["stance"])
        if P["impact"]:
            pose.move("Body", (0.0, 0.0, -P["bounce"] * footfall(t)))
        else:
            pose.move("Body", (0.0, 0.0, -P["bounce"] * C(t, 2)))
        pose.rot("Body", "Y", -P["roll"] * S(t))
        pose.rot("Body", "Z", P["yaw"] * S(t, 1, 0.25))
        pose.rot("Body", "X", -P["lean"] - 0.015 * C(t, 2, 0.1))
        for arm in self.arms():
            sign = 1.0 if arm.endswith("L") else -1.0
            pose.rot(arm, "X", -sign * P["arm_swing"] * C(t, 1, -0.04))
            pose.rot(arm, "Y", -sign * P["arm_out"] * (0.5 + 0.5 * S(t, 2)))
        pose.rot("Head", "X", P["head_bob"] * C(t, 2, -0.12))
        pose.rot("Head", "Z", 0.02 * S(t, 1, 0.2))

    def idle_biped(self, pose, t):
        self.breath(pose, t)
        pose.move("Body", (0.008 * S(t), 0.0, 0.0))
        pose.rot("Body", "Y", -0.02 * S(t))
        pose.rot("Head", "Z", 0.10 * (0.6 * S(t, 1, -0.06) + 0.4 * S(t, 3, 0.1)))
        pose.rot("Head", "X", 0.03 * S(t, 2, -0.1))
        for arm in self.arms():
            sign = 1.0 if arm.endswith("L") else -1.0
            pose.rot(arm, "X", 0.03 * S(t, 2))
            pose.rot(arm, "Y", -sign * 0.02 * S(t, 2))
        if self.staff_arm:
            pose.rot("Staff", "X", 0.01 * S(t, 2, 0.1))

    def attack_smash(self, k, anticipation):
        arms = self.arms()
        if anticipation:
            k.shift((0.0, -0.07, -0.04))
            k.rot("Body", "X", 0.18)
            k.rot("Head", "X", 0.15)
            for arm in arms:
                k.rot(arm, "X", -1.0)
                k.move(arm, (0.0, -0.01, 0.03))
        else:
            k.shift((0.0, 0.18, -0.02))
            k.rot("Body", "X", -0.38)
            k.move("Body", (0.0, 0.03, -0.04))
            k.rot("Head", "X", -0.30)
            for arm in arms:
                k.rot(arm, "X", 0.95)
                k.move(arm, (0.0, 0.03, -0.02))
            k.move("LegL", (0.0, 0.05, 0.0))
            k.rot("LegL", "X", 0.25)
            k.move("LegR", (0.0, -0.03, 0.0))
            k.rot("LegR", "X", -0.15)

    def attack_staff(self, k, anticipation):
        arm = self.staff_arm or "ArmR"
        free = self.free_arm or "ArmL"
        if anticipation:
            k.shift((0.0, -0.07, -0.02))
            k.rot("Body", "X", 0.16)
            k.rot("Head", "X", 0.08)
            k.rot(arm, "X", -0.22)
            k.move(arm, (0.0, -0.01, 0.02))
            k.rot(free, "X", 0.35)
        else:
            k.shift((0.0, 0.17, 0.0))
            k.rot("Body", "X", -0.28)
            k.move("Body", (0.0, 0.02, -0.02))
            k.rot("Head", "X", -0.12)
            k.rot(arm, "X", 0.28)
            k.move(arm, (0.0, 0.02, 0.01))
            k.rot(free, "X", -0.55)
            k.move("LegL", (0.0, 0.05, 0.0))

    def die_biped(self, k, key):
        arms = [b for b in ("ArmL", "ArmR") if b in self.starts]
        # A rigid staff hangs on its holding arm: that arm only drifts.
        def arm_amount(arm):
            return 0.2 if arm == self.staff_arm else 1.0
        if key == 0:
            k.rot("Body", "X", 0.15)
            k.move("Body", (0.0, -0.03, 0.02))
            k.rot("Head", "X", 0.25)
            for arm in arms:
                sign = 1.0 if arm.endswith("L") else -1.0
                k.rot(arm, "X", -0.6 * arm_amount(arm))
                k.rot(arm, "Y", -sign * 0.3 * arm_amount(arm))
        elif key == 1:
            k.rot("Body", "X", -0.6)
            k.move("Body", (0.0, 0.05, -0.13))
            k.rot("Head", "X", -0.4)
            for arm in arms:
                k.rot(arm, "X", 0.7 * arm_amount(arm))
            for leg in ("LegL", "LegR"):
                k.rot(leg, "X", 0.4)
                k.move(leg, (0.0, 0.03, -0.07))
        else:
            k.rot("Body", "X", -1.0)
            k.move("Body", (0.0, 0.08, -0.18))
            k.rot("Head", "X", -0.5)
            for arm in arms:
                sign = 1.0 if arm.endswith("L") else -1.0
                k.rot(arm, "X", 0.8 * arm_amount(arm))
                k.rot(arm, "Y", sign * 0.3 * arm_amount(arm))
            for leg in ("LegL", "LegR"):
                sign = 1.0 if leg.endswith("L") else -1.0
                k.rot(leg, "X", 0.5)
                k.rot(leg, "Y", -sign * 0.2)
                k.move(leg, (0.0, 0.04, -0.10))

    # ---- QUADRUPED -----------------------------------------------------------
    def gait_quadruped(self, pose, t):
        P = self.P
        gait = P["gait"]
        if gait == "gallop":
            phases = {"RearL": 0.0, "RearR": 0.14, "FrontL": 0.50, "FrontR": 0.64}
        else:
            phases = {"FrontL": 0.0, "RearR": 0.0, "FrontR": 0.5, "RearL": 0.5}
        for leg, phase in phases.items():
            s, z = leg_cycle(t + phase, P["stance"])
            swing = P["front_swing"] if leg.startswith("Front") else P["rear_swing"]
            pose.rot(leg, "X", swing * s)
            pose.move(leg, (0.0, P["leg_reach"] * s, P["leg_lift"] * z))
            if P["splay"]:
                sign = 1.0 if leg.endswith("R") else -1.0
                pose.rot(leg, "Y", sign * P["splay"] * (0.5 + 0.5 * z))
        if gait == "gallop":
            pose.rot("Body", "X", -P["pitch"] * C(t, 1, -0.55))
            pose.move("Body", (0.0, 0.0, P["bounce"] * C(t, 1, -0.90)))
            pose.scale("Body", 1.0, 1.0 + P["stretch"] * S(t, 1, -0.10), 1.0)
            pose.rot("Body", "Y", -P["roll"] * S(t, 1, 0.1))
            pose.rot("Head", "X", -P["head_nod"] * C(t, 1, -0.65))
            pose.move("Head", (0.0, 0.0, 0.01 * S(t, 1, -0.3)))
            pose.rot("Tail", "X", -P["tail_v"] * S(t, 1, -0.35))
            pose.rot("Tail", "Z", P["tail_h"] * S(t, 1, -0.5))
        else:
            pose.move("Body", (0.0, 0.0, -P["bounce"] * footfall(t)))
            pose.rot("Body", "Y", -P["roll"] * S(t))
            pose.rot("Body", "Z", P["yaw"] * S(t))
            pose.rot("Body", "X", -0.02 * C(t, 2, -0.1))
            pose.rot("Head", "X", -P["head_nod"] * C(t, 2, -0.15))
            pose.rot("Head", "Z", 0.03 * S(t))
            pose.rot("Tail", "Z", P["tail_h"] * S(t, 1, -0.8))
            pose.rot("Tail", "X", -P["tail_v"] * S(t, 2, -0.3))
        if P["undulate"]:
            u = P["undulate"]
            pose.rot("Body", "Z", u * S(t))
            pose.move("Body", (0.25 * u * S(t), 0.0, 0.0))
            pose.rot("Head", "Z", -0.8 * u * S(t, 1, 0.05))
            pose.rot("Tail", "Z", 2.2 * u * S(t, 1, 0.5))

    def idle_quadruped(self, pose, t):
        self.breath(pose, t)
        pose.move("Body", (0.006 * S(t), 0.0, 0.0))
        pose.rot("Head", "Z", 0.12 * (0.6 * S(t, 1, -0.05) + 0.4 * S(t, 3)))
        pose.rot("Head", "X", 0.03 * S(t, 2))
        pose.rot("Tail", "Z", 0.14 * S(t) + 0.05 * S(t, 3))
        pose.rot("Tail", "X", -0.05 * S(t, 2))
        paw = bump(t, 0.55, 0.72)
        pose.move("FrontL", (0.0, 0.02 * paw, 0.03 * paw))
        pose.rot("FrontL", "X", 0.15 * paw)

    def attack_pounce(self, k, anticipation):
        if anticipation:
            k.shift((0.0, -0.10, -0.04))
            k.rot("Body", "X", 0.12)
            k.rot("Head", "X", 0.28)
            k.move("Head", (0.0, -0.02, 0.02))
            for leg in ("RearL", "RearR"):
                k.rot(leg, "X", 0.25)
            for leg in ("FrontL", "FrontR"):
                k.rot(leg, "X", -0.15)
            k.rot("Tail", "X", -0.35)
        else:
            k.shift((0.0, 0.24, 0.04))
            k.rot("Body", "X", -0.22)
            k.rot("Head", "X", -0.48)
            k.move("Head", (0.0, 0.04, -0.02))
            for leg in ("FrontL", "FrontR"):
                k.rot(leg, "X", 0.45)
                k.move(leg, (0.0, 0.04, 0.05))
            for leg in ("RearL", "RearR"):
                k.rot(leg, "X", -0.35)
            k.rot("Tail", "X", 0.15)

    def attack_ram(self, k, anticipation):
        if anticipation:
            k.shift((0.0, -0.08, 0.0))
            k.rot("Body", "X", 0.14)
            k.rot("Head", "X", 0.32)
            k.move("Head", (0.0, -0.02, 0.03))
            for leg in ("FrontL", "FrontR"):
                k.rot(leg, "X", -0.15)
        else:
            k.shift((0.0, 0.20, -0.02))
            k.rot("Body", "X", -0.22)
            k.rot("Head", "X", -0.42)
            k.move("Head", (0.0, 0.04, -0.04))
            for leg in ("FrontL", "FrontR"):
                k.rot(leg, "X", 0.35)
                k.move(leg, (0.0, 0.04, 0.02))
            k.rot("Tail", "X", -0.25)

    def die_quadruped(self, k, key):
        if key == 0:
            k.rot("Body", "X", 0.12)
            k.move("Body", (0.0, 0.0, 0.02))
            k.rot("Head", "X", 0.2)
            k.rot("Tail", "X", -0.2)
        elif key == 1:
            k.rot("Body", "X", -0.35)
            k.move("Body", (0.0, 0.03, -0.14))
            k.rot("Head", "X", -0.5)
            k.move("Head", (0.0, 0.02, -0.04))
            for leg in ("FrontL", "FrontR"):
                k.rot(leg, "X", -0.5)
                k.move(leg, (0.0, -0.03, -0.06))
            k.rot("Tail", "X", 0.3)
        else:
            k.rot("Body", "X", -0.25)
            k.rot("Body", "Y", 0.45)
            k.move("Body", (0.0, 0.03, -0.20))
            k.rot("Head", "Y", 0.3)
            k.move("Head", (0.0, 0.0, -0.05))
            for leg in ("FrontL", "FrontR", "RearL", "RearR"):
                sign = 1.0 if leg.endswith("R") else -1.0
                k.rot(leg, "Y", sign * 0.3)
                k.move(leg, (0.0, 0.0, -0.09))
            k.rot("Tail", "Z", 0.3)
            k.rot("Tail", "X", 0.2)

    # ---- BLOB ------------------------------------------------------------------
    def gait_blob(self, pose, t):
        P = self.P
        origin = (0.0, 0.0, 0.0)
        crouch = bump(t, 0.0, 0.22)
        crouch_crown = bump(wrap(t - 0.04), 0.0, 0.22)
        air = seg(t, 0.22, 0.72)
        height = P["jump"] * math.sin(math.pi * air)
        height_crown = P["jump"] * math.sin(math.pi * seg(wrap(t - 0.05), 0.22, 0.72))
        stretch = bump(t, 0.20, 0.45)
        land = bump(t, 0.70, 0.90)
        sq = P["squash"]
        for bone, lag_crouch in (("Body", crouch), ("Crown", crouch_crown), ("Base", crouch)):
            pose.scale(bone, 1.0 + sq * 0.9 * lag_crouch + sq * 1.1 * land - 0.08 * stretch,
                       1.0 + sq * 0.9 * lag_crouch + sq * 1.1 * land - 0.08 * stretch,
                       1.0 - sq * 1.1 * lag_crouch - sq * 1.4 * land + 0.14 * stretch, origin)
        for bone, h in (("Body", height), ("Base", height), ("Crown", height_crown)):
            pose.move(bone, (0.0, P["lean"] * math.sin(math.pi * air), h))
        pose.rot("Crown", "X", -0.15 * math.sin(math.pi * air) + 0.06 * land)
        pose.rot("Body", "X", -0.05 * math.sin(math.pi * air))

    def idle_blob(self, pose, t):
        origin = (0.0, 0.0, 0.0)
        for bone in ("Body", "Crown", "Base"):
            pose.scale(bone, 1.0 + 0.03 * S(t, 2), 1.0 + 0.03 * S(t, 2), 1.0 - 0.03 * S(t, 2), origin)
        pose.move("Crown", (0.015 * S(t, 3), 0.0, -0.01 * S(t, 2)))
        pose.rot("Crown", "Z", 0.04 * S(t))
        pose.rot("Body", "Z", 0.02 * S(t, 1, 0.1))

    def attack_slam(self, k, anticipation):
        origin = (0.0, 0.0, 0.0)
        if anticipation:
            k.shift((0.0, -0.08, 0.0))
            for bone in ("Body", "Crown", "Base"):
                k.scale(bone, 1.16, 1.16, 0.76, origin)
            k.move("Crown", (0.0, -0.04, 0.0))
            k.rot("Crown", "X", 0.2)
        else:
            k.shift((0.0, 0.22, 0.04))
            for bone in ("Body", "Crown", "Base"):
                k.scale(bone, 0.92, 0.92, 1.12, origin)
            k.move("Crown", (0.0, 0.06, -0.03))
            k.rot("Crown", "X", -0.40)

    def die_blob(self, k, key):
        origin = (0.0, 0.0, 0.0)
        if key == 0:
            for bone in ("Body", "Crown", "Base"):
                k.scale(bone, 0.85, 0.85, 1.25, origin)
        elif key == 1:
            for bone in ("Body", "Crown", "Base"):
                k.scale(bone, 1.45, 1.45, 0.32, origin)
            k.move("Crown", (0.0, 0.03, -0.10))
        else:
            for bone in ("Body", "Crown", "Base"):
                k.scale(bone, 1.6, 1.6, 0.22, origin)
            k.move("Crown", (0.0, 0.04, -0.12))

    # ---- DRAGON ------------------------------------------------------------
    def _flap(self, pose, angle, twist=0.0):
        pose.rot("WingL", "Y", angle)
        pose.rot("WingR", "Y", -angle)
        if twist:
            pose.rot("WingL", "X", twist)
            pose.rot("WingR", "X", twist)

    def gait_dragon(self, pose, t):
        P = self.P
        self._biped_legs(pose, t, P["leg_swing"], P["leg_lift"], P["leg_reach"], P["stance"])
        for arm in ("ArmL", "ArmR"):
            sign = 1.0 if arm.endswith("L") else -1.0
            pose.rot(arm, "X", -sign * 0.15 * C(t))
        self._flap(pose, P["flap"] * C(t, 1, 0.08), P["twist"] * S(t, 1, -0.05))
        pose.move("Body", (0.0, 0.0, P["bounce"] * S(t, 1, -0.30) - 0.012 * C(t, 2)))
        pose.rot("Body", "X", -P["pitch"] * C(t))
        pose.rot("Body", "Y", 0.02 * S(t))
        pose.rot("Head", "X", 0.05 * S(t, 1, -0.4))
        pose.rot("Head", "Z", 0.03 * S(t, 1, 0.2))
        pose.rot("Tail", "Z", P["tail_h"] * S(t, 1, -0.9))
        pose.rot("Tail", "X", P["tail_v"] * S(t, 1, -0.75))

    def idle_dragon(self, pose, t):
        self.breath(pose, t, 0.015)
        self._flap(pose, 0.13 * S(t), 0.05 * S(t, 1, -0.1))
        pose.move("Body", (0.0, 0.0, 0.012 * S(t, 1, -0.2)))
        pose.rot("Head", "Z", 0.10 * (0.6 * S(t, 1, -0.05) + 0.4 * S(t, 3)))
        pose.rot("Head", "X", 0.03 * S(t, 2))
        pose.rot("Tail", "Z", 0.12 * S(t) + 0.04 * S(t, 3))
        pose.move("Body", (0.006 * S(t), 0.0, 0.0))

    def attack_bite(self, k, anticipation):
        if anticipation:
            k.shift((0.0, -0.09, 0.03))
            k.rot("Body", "X", 0.16)
            k.rot("Head", "X", 0.12)
            k.rot("WingL", "Y", 0.5)
            k.rot("WingR", "Y", -0.5)
            for arm in ("ArmL", "ArmR"):
                k.rot(arm, "X", -0.4)
        else:
            k.shift((0.0, 0.22, -0.05))
            k.rot("Body", "X", -0.34)
            k.move("Body", (0.0, 0.02, -0.02))
            k.rot("Head", "X", -0.14)
            k.rot("WingL", "Y", -0.4)
            k.rot("WingR", "Y", 0.4)
            for arm in ("ArmL", "ArmR"):
                k.rot(arm, "X", 0.6)
            k.move("LegL", (0.0, 0.04, 0.0))
            k.rot("LegL", "X", 0.2)

    def die_dragon(self, k, key):
        if key == 0:
            k.rot("Body", "X", 0.15)
            k.move("Body", (0.0, 0.0, 0.04))
            k.rot("Head", "X", 0.12)
            k.rot("WingL", "Y", 0.5)
            k.rot("WingR", "Y", -0.5)
        elif key == 1:
            k.rot("Body", "X", -0.3)
            k.move("Body", (0.0, 0.04, -0.16))
            k.rot("Head", "X", -0.12)
            k.rot("WingL", "Y", -0.5)
            k.rot("WingR", "Y", 0.5)
            k.rot("WingL", "X", 0.3)
            k.rot("WingR", "X", 0.3)
            for arm in ("ArmL", "ArmR"):
                k.rot(arm, "X", 0.3)
            for leg in ("LegL", "LegR"):
                sign = 1.0 if leg.endswith("R") else -1.0
                k.rot(leg, "X", -0.3)
                k.rot(leg, "Y", sign * 0.25)
                k.move(leg, (0.0, 0.0, -0.08))
        else:
            k.rot("Body", "X", -0.22)
            k.rot("Body", "Y", 0.3)
            k.move("Body", (0.0, 0.04, -0.22))
            k.rot("Head", "X", -0.14)
            k.rot("Head", "Y", 0.1)
            k.rot("WingL", "Y", -0.7)
            k.rot("WingR", "Y", 0.7)
            for leg in ("LegL", "LegR"):
                k.move(leg, (0.0, 0.0, -0.12))
            k.rot("Tail", "Z", 0.3)

    # ---- RAY ------------------------------------------------------------------
    def gait_ray(self, pose, t):
        P = self.P
        self._flap(pose, P["flap"] * C(t), P["twist"] * S(t, 1, -0.1))
        pose.move("Body", (0.0, 0.0, P["bounce"] * S(t, 1, -0.25)))
        pose.rot("Body", "X", -P["pitch"] * S(t, 1, -0.10))
        pose.rot("Body", "Y", 0.02 * S(t, 1, 0.3))
        pose.rot("Tail", "Z", P["tail_h"] * S(t, 1, -0.35))
        pose.rot("Tail", "X", P["tail_v"] * S(t, 1, -0.30))

    def idle_ray(self, pose, t):
        pose.move("Body", (0.0, 0.0, 0.03 * S(t)))
        self._flap(pose, 0.08 * S(t, 2), 0.05 * S(t, 2, -0.08))
        pose.rot("Tail", "Z", 0.12 * S(t))
        pose.rot("Tail", "X", 0.05 * S(t, 2, -0.1))
        pose.rot("Body", "Z", 0.03 * S(t))

    def attack_dive(self, k, anticipation):
        if anticipation:
            k.shift((0.0, -0.08, 0.14))
            k.rot("Body", "X", 0.2)
            k.rot("WingL", "Y", 0.5)
            k.rot("WingR", "Y", -0.5)
            k.rot("Tail", "X", -0.2)
        else:
            k.shift((0.0, 0.24, -0.10))
            k.rot("Body", "X", -0.35)
            k.rot("WingL", "Y", -0.4)
            k.rot("WingR", "Y", 0.4)
            k.rot("Tail", "X", 0.3)

    def die_ray(self, k, key):
        if key == 0:
            k.move("Body", (0.0, 0.0, 0.05))
            k.rot("WingL", "Y", 0.5)
            k.rot("WingR", "Y", -0.5)
        elif key == 1:
            k.move("Body", (0.0, 0.02, -0.02))
            k.rot("Body", "X", -0.1)
            k.rot("WingL", "Y", -0.35)
            k.rot("WingR", "Y", 0.35)
            k.rot("Tail", "Z", 0.2)
        else:
            k.move("Body", (0.0, 0.02, -0.03))
            k.rot("Body", "Y", 0.25)
            k.rot("WingL", "Y", -0.45)
            k.rot("WingR", "Y", 0.45)
            k.rot("Tail", "Z", 0.3)

    # ---- JELLY -------------------------------------------------------------
    @staticmethod
    def _pulse(p):
        p = wrap(p)
        if p < 0.18:
            return ease_out(p / 0.18, 2.0)
        if p < 0.85:
            return 1.0 - smooth((p - 0.18) / 0.67)
        return 0.0

    def gait_jelly(self, pose, t):
        P = self.P
        c = self._pulse(t)
        c_body = self._pulse(t - 0.08)
        c_tent = self._pulse(t - 0.18)
        pose.scale("Cap", 1.0 - P["pulse"] * c, 1.0 - P["pulse"] * c, 1.0 + P["pulse"] * c)
        pose.rot("Cap", "X", -0.05 * c)
        pose.move("Body", (0.0, P["thrust"] * c_body, P["thrust"] * c_body + 0.02 * S(t, 1, -0.2)))
        for tent in ("TentacleL", "TentacleR"):
            pose.move(tent, (0.0, -0.06 * c_tent, 0.03 * c_tent))
            pose.rot(tent, "X", -P["trail"] * c_tent + 0.08 * S(t, 1, -0.5))
            pose.rot(tent, "Z", 0.04 * S(t, 1, -0.3))

    def idle_jelly(self, pose, t):
        pose.move("Body", (0.01 * S(t), 0.0, 0.03 * S(t)))
        c = 0.5 + 0.5 * S(t, 2)
        pose.scale("Cap", 1.0 - 0.04 * c, 1.0 - 0.04 * c, 1.0 + 0.04 * c)
        for tent in ("TentacleL", "TentacleR"):
            pose.rot(tent, "X", 0.08 * S(t, 1, 0.1))
            pose.rot(tent, "Z", 0.06 * S(t, 1, 0.3))

    def attack_burst(self, k, anticipation):
        shape = self.shape
        if shape == "idol":
            if anticipation:
                k.shift((0.0, -0.08, 0.12))
                k.rot("Body", "X", 0.20)
                k.move("Crown", (0.0, 0.0, 0.12))
                k.rot("Crown", "Z", 2.5)
            else:
                k.shift((0.0, 0.20, -0.08))
                k.rot("Body", "X", -0.34)
                k.move("Crown", (0.0, 0.04, -0.06))
            return
        if anticipation:
            k.shift((0.0, -0.08, 0.08))
            k.scale("Cap", 0.84, 0.84, 1.18)
            for tent in ("TentacleL", "TentacleR"):
                k.rot(tent, "X", -0.35)
                k.move(tent, (0.0, -0.03, 0.02))
        else:
            k.shift((0.0, 0.20, -0.06))
            k.scale("Cap", 1.18, 1.18, 0.86)
            k.move("Cap", (0.0, 0.02, -0.03))
            for tent in ("TentacleL", "TentacleR"):
                k.rot(tent, "X", 0.6)
                k.move(tent, (0.0, 0.06, 0.0))

    def die_jelly(self, k, key):
        if key == 0:
            k.scale("Cap", 0.88, 0.88, 1.10)
            k.move("Body", (0.0, 0.0, 0.03))
        elif key == 1:
            k.scale("Cap", 1.30, 1.30, 0.50)
            k.move("Body", (0.0, 0.0, -0.12))
            for tent in ("TentacleL", "TentacleR"):
                k.rot(tent, "X", 0.3)
                k.move(tent, (0.0, 0.02, -0.04))
        else:
            k.scale("Cap", 1.40, 1.40, 0.42)
            k.move("Body", (0.0, 0.0, -0.15))
            for tent in ("TentacleL", "TentacleR"):
                k.rot(tent, "X", 0.4)
                k.move(tent, (0.0, 0.03, -0.05))

    # ---- IDOL ---------------------------------------------------------------
    def gait_idol(self, pose, t):
        P = self.P
        pose.move("Body", (0.0, 0.0, P["bob"] * S(t)))
        pose.rot("Body", "X", -0.05 + P["tilt"] * S(t, 1, 0.25))
        pose.rot("Body", "Y", P["tilt"] * 0.8 * C(t))
        pose.rot("Body", "Z", P["sway"] * S(t))
        pose.rot("Crown", "Z", TAU * t)
        pose.move("Crown", (0.02 * C(t, 2), 0.02 * S(t, 2), 0.03 * S(t, 1, -0.15)))

    def idle_idol(self, pose, t):
        pose.move("Body", (0.0, 0.0, 0.03 * S(t)))
        pose.rot("Body", "X", 0.03 * S(t))
        pose.rot("Body", "Y", 0.03 * C(t))
        pose.rot("Body", "Z", 0.08 * S(t))
        pose.rot("Crown", "Z", TAU * t)
        pose.move("Crown", (0.0, 0.0, 0.02 * S(t, 2)))

    def die_idol(self, k, key):
        if key == 0:
            k.rot("Body", "Z", 0.15)
            k.move("Body", (0.0, 0.0, 0.03))
            k.move("Crown", (0.0, 0.0, 0.06))
        elif key == 1:
            k.move("Crown", (0.08, 0.03, -0.30))
            k.rot("Crown", "Y", 0.5)
            k.rot("Body", "Y", 0.20)
        else:
            k.move("Crown", (0.12, 0.04, -0.42))
            k.rot("Crown", "Y", 0.8)
            k.rot("Body", "Y", 0.30)
            k.move("Body", (0.0, 0.0, -0.02))

    # ---- SERPENT -----------------------------------------------------------
    def gait_serpent(self, pose, t):
        P = self.P
        pose.move("Body", (P["sway"] * S(t), 0.0, 0.02 * S(t, 2)))
        pose.rot("Body", "Z", P["weave"] * S(t))
        pose.rot("Body", "Y", 0.03 * S(t, 1, 0.25))
        pose.rot("Neck", "Z", 0.12 * S(t, 1, -0.2))
        pose.move("Neck", (0.03 * S(t, 1, -0.2), 0.0, 0.0))
        pose.rot("Neck", "X", 0.04 * S(t, 2, -0.3))
        pose.rot("Head", "Z", 0.10 * S(t, 1, -0.4))
        pose.rot("Head", "X", 0.06 * S(t, 2, -0.5))
        pose.rot("Tail", "Z", P["tail_h"] * S(t, 1, 0.5))
        pose.move("Tail", (0.03 * S(t, 1, 0.5), 0.0, 0.0))
        pose.rot("FinL", "Y", P["fin"] * S(t, 2, -0.1))
        pose.rot("FinR", "Y", -P["fin"] * S(t, 2, -0.1))

    def idle_serpent(self, pose, t):
        self.breath(pose, t, 0.015)
        pose.move("Body", (0.02 * S(t), 0.0, 0.0))
        pose.rot("Neck", "Z", 0.08 * S(t, 1, -0.15))
        pose.rot("Head", "Z", 0.06 * S(t, 1, -0.3))
        pose.rot("Head", "X", 0.03 * S(t, 2))
        pose.rot("FinL", "Y", 0.10 * S(t, 2))
        pose.rot("FinR", "Y", -0.10 * S(t, 2))
        pose.rot("Tail", "Z", 0.10 * S(t))

    def attack_strike(self, k, anticipation):
        if anticipation:
            k.shift((0.0, -0.09, 0.03))
            k.rot("Neck", "X", 0.30)
            k.move("Neck", (0.0, -0.02, 0.03))
            k.rot("Head", "X", 0.25)
            k.move("Head", (0.0, -0.03, 0.04))
            k.rot("Body", "X", 0.08)
            k.rot("FinL", "Y", 0.35)
            k.rot("FinR", "Y", -0.35)
            k.rot("Tail", "Z", 0.2)
        else:
            k.shift((0.0, 0.22, -0.05))
            k.rot("Neck", "X", -0.55)
            k.move("Neck", (0.0, 0.05, -0.05))
            k.rot("Head", "X", -0.45)
            k.move("Head", (0.0, 0.06, -0.08))
            k.rot("Body", "X", -0.14)
            k.rot("FinL", "Y", -0.2)
            k.rot("FinR", "Y", 0.2)

    def die_serpent(self, k, key):
        if key == 0:
            k.rot("Neck", "X", 0.3)
            k.rot("Head", "X", 0.3)
            k.move("Neck", (0.0, 0.0, 0.05))
        elif key == 1:
            k.rot("Neck", "X", -0.5)
            k.move("Neck", (0.0, 0.04, -0.14))
            k.rot("Head", "X", -0.5)
            k.move("Head", (0.0, 0.06, -0.18))
            k.move("Body", (0.0, 0.0, -0.12))
            k.rot("Body", "Y", 0.2)
            k.rot("FinL", "Y", -0.4)
            k.rot("FinR", "Y", 0.4)
            k.rot("Tail", "Z", 0.3)
        else:
            k.rot("Neck", "X", -0.6)
            k.move("Neck", (0.0, 0.05, -0.20))
            k.rot("Head", "X", -0.55)
            k.move("Head", (0.0, 0.08, -0.26))
            k.move("Body", (0.0, 0.0, -0.16))
            k.rot("Body", "Y", 0.35)
            k.rot("FinL", "Y", -0.5)
            k.rot("FinR", "Y", 0.5)
            k.rot("Tail", "Z", 0.4)

    # ---- TREE ---------------------------------------------------------------
    def gait_tree(self, pose, t):
        P = self.P
        self._biped_legs(pose, t, P["leg_swing"], P["leg_lift"], P["leg_reach"], P["stance"])
        pose.rot("Body", "Y", -P["roll"] * S(t))
        pose.move("Body", (0.0, 0.0, -P["bounce"] * C(t, 2)))
        pose.rot("Body", "Z", 0.03 * S(t))
        pose.rot("Body", "X", 0.015 * S(t, 2))
        for arm in ("ArmL", "ArmR"):
            sign = 1.0 if arm.endswith("L") else -1.0
            pose.rot(arm, "X", -sign * 0.10 * C(t, 1, -0.10))
            pose.rot(arm, "Y", -sign * 0.04 * S(t, 1, -0.15))
        pose.rot("Head", "Y", 0.06 * S(t, 1, -0.18))
        pose.rot("Head", "X", 0.03 * S(t, 2, -0.2))
        pose.scale("Head", 1.0 + 0.01 * S(t, 3), 1.0 + 0.01 * S(t, 3), 1.0)

    def idle_tree(self, pose, t):
        self.breath(pose, t, 0.008)
        pose.rot("Head", "Y", 0.04 * S(t) + 0.015 * S(t, 3))
        pose.rot("Head", "X", 0.02 * S(t, 2))
        for arm in ("ArmL", "ArmR"):
            pose.rot(arm, "X", 0.03 * S(t, 1, -0.1))
        pose.rot("Body", "Y", 0.012 * S(t))

    def die_tree(self, k, key):
        if key == 0:
            for arm in ("ArmL", "ArmR"):
                k.rot(arm, "X", -0.6)
            k.rot("Body", "X", 0.1)
        elif key == 1:
            for arm in ("ArmL", "ArmR"):
                sign = 1.0 if arm.endswith("L") else -1.0
                k.rot(arm, "X", -0.4)
                k.rot(arm, "Y", -sign * 0.3)
            k.rot("Head", "Z", 0.1)
            k.rot("Body", "X", 0.15)
        else:
            for arm in ("ArmL", "ArmR"):
                k.rot(arm, "X", -0.3)
            k.rot("Head", "X", 0.1)

    # ---- MUSHROOM ---------------------------------------------------------
    def gait_mushroom(self, pose, t):
        P = self.P
        self._biped_legs(pose, t, P["leg_swing"], P["leg_lift"], P["leg_reach"], P["stance"])
        pose.rot("Body", "Y", -P["roll"] * S(t))
        pose.move("Body", (0.0, 0.0, -P["bounce"] * C(t, 2)))
        pose.rot("Body", "Z", 0.05 * S(t))
        pose.rot("Head", "Y", P["cap"] * S(t, 1, -0.12))
        pose.rot("Head", "X", 0.04 * S(t, 2, -0.15))
        for arm in ("ArmL", "ArmR"):
            sign = 1.0 if arm.endswith("L") else -1.0
            pose.rot(arm, "X", -sign * P["arm_swing"] * C(t))

    def idle_mushroom(self, pose, t):
        self.breath(pose, t)
        pose.rot("Head", "Y", 0.05 * S(t, 2) + 0.02 * S(t, 3, 0.2))
        pose.rot("Head", "X", 0.03 * S(t))
        for arm in ("ArmL", "ArmR"):
            pose.rot(arm, "X", 0.03 * S(t, 2))

    def attack_capslam(self, k, anticipation):
        if anticipation:
            k.shift((0.0, -0.07, -0.06))
            k.rot("Body", "X", 0.12)
            k.rot("Head", "X", 0.25)
            k.move("Head", (0.0, -0.03, 0.04))
            for arm in ("ArmL", "ArmR"):
                k.rot(arm, "X", -0.5)
        else:
            k.shift((0.0, 0.20, 0.05))
            k.rot("Body", "X", -0.2)
            k.rot("Head", "X", -0.40)
            k.move("Head", (0.0, 0.03, -0.02))
            for arm in ("ArmL", "ArmR"):
                k.rot(arm, "X", 0.7)
            for leg in ("LegL", "LegR"):
                sign = 1.0 if leg.endswith("L") else -1.0
                k.move(leg, (0.0, 0.0, 0.03))
                k.rot(leg, "X", sign * 0.2)

    def die_mushroom(self, k, key):
        origin = (0.0, 0.0, 0.0)
        if key == 0:
            k.move("Body", (0.0, 0.0, 0.04))
            k.move("Head", (0.0, 0.0, 0.03))
        elif key == 1:
            k.scale("Head", 1.3, 1.3, 0.5)
            k.move("Head", (0.0, 0.0, -0.25))
            k.scale("Body", 1.1, 1.1, 0.7, origin)
            k.move("Body", (0.0, 0.0, -0.10))
            for arm in ("ArmL", "ArmR"):
                sign = 1.0 if arm.endswith("L") else -1.0
                k.rot(arm, "Y", -sign * 0.5)
        else:
            k.scale("Head", 1.4, 1.4, 0.42)
            k.move("Head", (0.0, 0.0, -0.32))
            k.scale("Body", 1.15, 1.15, 0.62, origin)
            k.move("Body", (0.0, 0.0, -0.14))
            for arm in ("ArmL", "ArmR"):
                sign = 1.0 if arm.endswith("L") else -1.0
                k.rot(arm, "Y", -sign * 0.6)

    # ---- PLANT ----------------------------------------------------------------
    def gait_plant(self, pose, t):
        P = self.P
        for side, phase in (("L", 0.0), ("R", 0.5)):
            s, z = leg_cycle(t + phase, P["stance"])
            root = "Root" + side
            pose.rot(root, "X", 0.15 * s)
            pose.move(root, (0.0, P["root_reach"] * s, P["root_lift"] * z))
        pose.move("Body", (0.0, 0.0, -P["heave"] * C(t, 2)))
        pose.rot("Body", "X", -0.05 * S(t, 2, -0.1))
        pose.rot("Body", "Y", -0.05 * S(t))
        w = P["writhe"]
        pose.rot("VineL", "X", w * S(t, 1, 0.1))
        pose.rot("VineL", "Z", -0.8 * w * S(t, 2, 0.3))
        pose.rot("VineR", "X", w * S(t, 1, 0.55))
        pose.rot("VineR", "Z", 0.8 * w * S(t, 2, 0.8))
        pose.rot("Maw", "Y", 0.06 * S(t, 1, -0.15))
        pose.rot("Maw", "X", 0.05 * S(t, 2, -0.25))
        pose.scale("Maw", 1.0 + 0.02 * S(t, 2), 1.0 + 0.02 * S(t, 2), 1.0 + 0.02 * S(t, 2))

    def idle_plant(self, pose, t):
        pose.move("Body", (0.0, 0.0, 0.01 * S(t, 2)))
        pose.rot("VineL", "X", 0.12 * S(t, 1, 0.1))
        pose.rot("VineL", "Z", -0.08 * S(t, 2, 0.35))
        pose.rot("VineR", "X", 0.12 * S(t, 1, 0.6))
        pose.rot("VineR", "Z", 0.08 * S(t, 2, 0.85))
        pose.rot("Maw", "Y", 0.05 * S(t))
        pose.rot("Maw", "X", 0.04 * S(t, 2, -0.1))
        pose.scale("Maw", 1.0 + 0.015 * S(t, 2), 1.0 + 0.015 * S(t, 2), 1.0 + 0.015 * S(t, 2))

    def attack_maw(self, k, anticipation):
        if anticipation:
            k.rot("Maw", "X", 0.10)
            k.rot("VineL", "X", 0.4)
            k.rot("VineR", "X", 0.4)
            k.rot("VineL", "Z", -0.2)
            k.rot("VineR", "Z", 0.2)
            k.rot("Body", "X", 0.12)
            k.shift((0.0, -0.08, 0.03))
        else:
            k.rot("Maw", "X", -0.16)
            k.rot("VineL", "X", -0.6)
            k.rot("VineR", "X", -0.6)
            k.rot("Body", "X", -0.28)
            k.shift((0.0, 0.20, -0.05))
            k.move("RootL", (0.0, 0.04, 0.0))

    def die_plant(self, k, key):
        origin = (0.0, 0.0, 0.0)
        if key == 0:
            k.rot("Maw", "X", 0.10)
            k.rot("Body", "X", 0.08)
            k.move("Body", (0.0, 0.0, 0.03))
            k.rot("VineL", "X", 0.3)
            k.rot("VineR", "X", 0.3)
        elif key == 1:
            k.rot("Maw", "X", -0.14)
            k.rot("Body", "X", -0.35)
            k.rot("VineL", "X", -0.5)
            k.rot("VineR", "X", -0.5)
            k.rot("VineL", "Z", -0.3)
            k.rot("VineR", "Z", 0.3)
            k.move("Body", (0.0, 0.06, -0.12))
            k.scale("Body", 1.06, 1.06, 0.88, origin)
            for root in ("RootL", "RootR"):
                k.move(root, (0.0, 0.0, -0.06))
        else:
            k.rot("Maw", "X", -0.16)
            k.rot("Body", "X", -0.5)
            k.rot("VineL", "X", -0.6)
            k.rot("VineR", "X", -0.6)
            k.rot("VineL", "Z", -0.4)
            k.rot("VineR", "Z", 0.4)
            k.move("Body", (0.0, 0.08, -0.16))
            k.scale("Body", 1.10, 1.10, 0.82, origin)
            for root in ("RootL", "RootR"):
                k.move(root, (0.0, 0.0, -0.09))


# --------------------------------------------------------------------------- #
# Blender keying
# --------------------------------------------------------------------------- #
def clear_clips(rig):
    """Remove previous actions/NLA from the rig only (geometry and weights untouched)."""
    import bpy
    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = None
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    for action in list(bpy.data.actions):
        if action.users == 0 or action.name in ("IdleLoop", "MoveLoop", "Attack", "Die"):
            bpy.data.actions.remove(action, do_unlink=True)
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)


def write_clip(rig, name, frames, pose_fn):
    import bpy
    action = bpy.data.actions.new(name)
    rig.animation_data.action = action
    rest = {bone.name: bone.matrix_local.copy() for bone in rig.data.bones}
    for frame in range(frames + 1):
        matrices = pose_fn(frame / frames).matrices()
        for bone in rig.pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
        for bone in rig.pose.bones:
            bone.matrix = matrices[bone.name] @ rest[bone.name]
        for bone in rig.pose.bones:
            bone.rotation_mode = "QUATERNION"
            for prop in ("location", "rotation_quaternion", "scale"):
                bone.keyframe_insert(data_path=prop, frame=frame, group=bone.name)
    for curve in action.fcurves:
        for key in curve.keyframe_points:
            key.interpolation = "LINEAR"
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 0, action)
    track.mute = True
    return action


def author_clips(rig, spec, height, params=None):
    """Replace the rig's clips with the full production set. Returns clip metadata."""
    import bpy
    starts = {bone.name: Vector(bone.head_local) for bone in rig.data.bones}
    params = params or motion_params(spec)
    choreo = Choreographer(spec, starts, height, params)
    bpy.context.scene.render.fps = FPS
    clear_clips(rig)
    plan = [("IdleLoop", IDLE_FRAMES, choreo.idle_pose), ("MoveLoop", int(params["move_frames"]), choreo.move_pose),
            ("Attack", ATTACK_FRAMES, choreo.attack_pose), ("Die", DIE_FRAMES, choreo.die_pose)]
    for name, frames, fn in plan:
        write_clip(rig, name, frames, fn)
    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    bpy.context.scene.frame_set(0)
    return {
        "version": 2,
        "library": "tools/3d/monster_motion.py",
        "fps": FPS,
        "frames": {name: frames for name, frames, _ in plan},
        "move_cycle_seconds": round(params["move_frames"] / FPS, 4),
        "travel_per_move_cycle_world_units": round(TRAVEL_PER_CLIP_SECOND * params["move_frames"] / FPS, 4),
        "attack_phase_map": "clip_time = (siege_phase - 0.3) mod 1; strike frame 21/30 lands at the phase wrap",
        "params": params,
    }
