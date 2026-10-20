#!/usr/bin/env python3
"""Arm twist QA gate for the native hero clips (no Godot, no Blender).

Parses art/models/<id>/<id>.glb (or a candidate GLB) and measures, for every key of
the IdleLoop / WalkLoop / Attack clips and each arm side:

  elbow_twist   spin of the forearm about its own axis relative to the upper arm:
                twist of q_forearm * q_arm^-1 about the arm-carried forearm axis
                (a hinge elbow is 0; the B1 "chicken wing" was 170-180 deg)
  wrist_twist   twist of q_hand * q_forearm^-1 about the posed forearm axis
  wrist_bend    swing of the same relative rotation (the hand's rest forearm axis
                against the posed forearm axis: a folded wrist)
  flip          largest frame-to-frame flip between two consecutive 1/30 s keys: a jump
                of the elbow or wrist twist across the joint, or a roll of the upper arm,
                forearm or hand about its own axis that its swing in the same key does not
                explain (roll > FLIP_SWING x swing, both against the torso: an elbow plane
                flipping through the
                shoulder-target axis, an absolute hand flipping its minimal arc). A fast
                swing that carries its own roll (an overhead cut) and a fast hinge flexion
                (the release snap) do not count; their raw roll is reported as `spin`
  shoulder_twist / weapon_rel   informative only: upper arm twist against the body,
                rotation of the weapon bone against its hand

The bones are parentless absolute controls, so every relative rotation is taken
between the bones' rest-relative (model space) deltas. Thresholds default to the
B1 phase-1 gate (elbow <= 30, wrist twist <= 90, wrist bend <= 100, flip <= 45 deg
per key). Exit code 0 when every selected hero passes (or is a known failure no worse
than its baseline), 1 otherwise.

    python3 tools/3d/audit_native_twist.py --quiet               # the verify gate: every manifest hero
    python3 tools/3d/audit_native_twist.py --scope b1 --baseline ''   # the 23 B1 heroes, strict
    python3 tools/3d/audit_native_twist.py --ids niamh,jokull --glb-dir build/.../candidates
    python3 tools/3d/audit_native_twist.py --json out.json
    python3 tools/3d/audit_native_twist.py --write-baseline tools/3d/twist_baseline.json   # after an accepted change

--baseline FILE (default tools/3d/twist_baseline.json, tracked; '' = strict): a hero that
already failed in FILE and is not worse than it by more than --tol degrees is reported as
'known' and does not fail the exit code (the heroes outside a fix); heroes that passed in
FILE, and heroes missing from it, must pass the thresholds. --write-baseline FILE stores
this run's per-hero worst values (compact) as the next baseline.
"""
import argparse, hashlib, json, math, struct, sys, time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'art/models/native_heroes.json'
BASELINE = ROOT / 'tools/3d/twist_baseline.json'   # accepted state: the known failures and the heroes that must pass
SPECS = ROOT / 'tools/3d/native_visual_specs.json'
# B1 (feedback 2026-10-19): every bow, sword, the tool and three rifles.
B1_IDS = ['brigid', 'echo', 'eira', 'isa', 'keto', 'niamh', 'null', 'protea', 'saeta', 'solana',
          'caden', 'estoque', 'finn', 'glaukos', 'helga', 'igni', 'jokull', 'nerea', 'phantom',
          'pip', 'kari', 'phorkys', 'ceniza']
CLIPS = ['Attack', 'WalkLoop', 'IdleLoop']
GATED = ['elbow_twist', 'wrist_twist', 'wrist_bend', 'flip']
FLIP_SWING = 1.5      # a roll larger than this many times the bone's own swing in the key is a flip

COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


# ---------------------------------------------------------------------------- GLB
def read_glb(path: Path):
    data = path.read_bytes()
    length = struct.unpack_from('<I', data, 12)[0]
    gltf = json.loads(data[20:20 + length])
    offset = 20 + length
    bin_length = struct.unpack_from('<I', data, offset)[0]
    return gltf, data[offset + 8:offset + 8 + bin_length], hashlib.sha256(data).hexdigest()


def accessor(gltf, binary, index):
    acc = gltf['accessors'][index]
    view = gltf['bufferViews'][acc['bufferView']]
    dtype = COMP[acc['componentType']]; n = NCOMP[acc['type']]
    start = view.get('byteOffset', 0) + acc.get('byteOffset', 0)
    stride = view.get('byteStride', 0)
    item = np.dtype(dtype).itemsize * n
    if stride and stride != item:
        raw = np.frombuffer(binary, dtype=np.uint8, count=stride * acc['count'], offset=start)
        arr = np.frombuffer(raw.reshape(acc['count'], stride)[:, :item].tobytes(), dtype=dtype).reshape(acc['count'], n)
    else:
        arr = np.frombuffer(binary, dtype=dtype, count=acc['count'] * n, offset=start).reshape(acc['count'], n)
    arr = arr.astype(np.float64)
    if acc.get('normalized'):
        arr = arr / float(np.iinfo(dtype).max)
    return arr


# ---------------------------------------------------------------------------- quaternions (x, y, z, w)
def qmul(a, b):
    x1, y1, z1, w1 = a; x2, y2, z2, w2 = b
    return np.array([w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
                     w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
                     w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2,
                     w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2])


def qinv(q):
    return np.array([-q[0], -q[1], -q[2], q[3]]) / float(np.dot(q, q))


def qnorm(q):
    q = np.asarray(q, float)
    q = q / np.linalg.norm(q)
    return -q if q[3] < 0 else q


def qrot(q, v):
    p = np.array([v[0], v[1], v[2], 0.0])
    return qmul(qmul(q, p), qinv(q))[:3]


def qangle(q):
    q = qnorm(q)
    return 2.0 * math.degrees(math.atan2(np.linalg.norm(q[:3]), q[3]))


def twist_deg(q, axis):
    """Signed twist (deg, -180..180] of rotation q about axis (swing-twist, twist first)."""
    q = qnorm(q)
    a = np.asarray(axis, float); a = a / np.linalg.norm(a)
    proj = float(np.dot(q[:3], a))
    if abs(proj) < 1e-12 and abs(q[3]) < 1e-12:
        return 180.0
    return 2.0 * math.degrees(math.atan2(proj, q[3]))


def vangle(a, b):
    a = np.asarray(a, float); b = np.asarray(b, float)
    c = float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))
    return math.degrees(math.acos(max(-1.0, min(1.0, c))))


def mat_to_quat(m):
    m = np.asarray(m, float)[:3, :3]
    # Remove scale (columns).
    m = m / np.linalg.norm(m, axis=0)
    t = np.trace(m)
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    return qnorm(q)


def slerp_keys(times, values, t):
    i = int(np.searchsorted(times, t))
    if i <= 0: return values[0]
    if i >= len(times): return values[-1]
    t0, t1 = times[i - 1], times[i]
    u = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
    a, b = values[i - 1], values[i]
    if values.shape[1] == 4:
        if np.dot(a, b) < 0: b = -b
        r = a * (1 - u) + b * u
        return r / np.linalg.norm(r)
    return a * (1 - u) + b * u


# ---------------------------------------------------------------------------- rig
class Rig:
    def __init__(self, path: Path):
        self.path = path
        self.gltf, self.bin, self.sha = read_glb(path)
        g = self.gltf
        nodes = g['nodes']
        self.parent = {}
        for i, n in enumerate(nodes):
            for c in n.get('children', []): self.parent[c] = i
        skin = g['skins'][0]
        self.joint_nodes = skin['joints']
        self.names = [nodes[j].get('name', '') for j in self.joint_nodes]
        ibm = accessor(g, self.bin, skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
        self.heads = {self.names[k]: np.linalg.inv(ibm[k])[:3, 3] for k in range(len(self.names))}
        self.node_of = {nodes[j].get('name', ''): j for j in self.joint_nodes}
        self.rest_q = {name: qnorm(nodes[j].get('rotation', [0, 0, 0, 1])) for name, j in self.node_of.items()}
        # Static global rotation of each joint's parent chain (armature, scene roots).
        self.parent_q = {}
        for name, j in self.node_of.items():
            q = np.array([0.0, 0.0, 0.0, 1.0])
            p = self.parent.get(j)
            chain = []
            while p is not None:
                chain.append(p); p = self.parent.get(p)
            for p in reversed(chain):
                q = qmul(q, self._local_q(p))
            self.parent_q[name] = qnorm(q)

    def _local_q(self, index):
        n = self.gltf['nodes'][index]
        if 'matrix' in n:
            return mat_to_quat(np.array(n['matrix'], float).reshape(4, 4).T)
        return qnorm(n.get('rotation', [0, 0, 0, 1]))

    def clip(self, suffix):
        g = self.gltf
        anims = [a for a in g.get('animations', []) if a.get('name', '').endswith(suffix)]
        if not anims: return None
        anim = anims[0]
        channels = {}
        times = set()
        for c in anim['channels']:
            node = c['target'].get('node')
            if node is None: continue
            name = g['nodes'][node].get('name', '')
            if c['target']['path'] != 'rotation': continue
            s = anim['samplers'][c['sampler']]
            t = accessor(g, self.bin, s['input'])[:, 0]
            v = accessor(g, self.bin, s['output'])
            channels[name] = (t, v)
            times.update(np.round(t, 6).tolist())
        return channels, np.array(sorted(times))

    def delta(self, channels, name, t):
        """Model-space rotation that carries the joint's rest frame to its pose at t."""
        local = slerp_keys(*channels[name], t) if name in channels else self.rest_q[name]
        pq = self.parent_q[name]
        posed = qmul(pq, local)
        rest = qmul(pq, self.rest_q[name])
        return qnorm(qmul(posed, qinv(rest)))


def measure(rig: Rig, clips=CLIPS) -> dict:
    out = {}
    for clip in clips:
        data = rig.clip(clip)
        if data is None: continue
        channels, times = data
        per_side = {}
        for side in 'LR':
            A, F, H = 'SkinArm' + side, 'SkinForearm' + side, 'SkinHand' + side
            Wp = 'SkinWeapon' + side
            if not all(n in rig.heads for n in (A, F, H)): continue
            fa = rig.heads[H] - rig.heads[F]
            ua = rig.heads[F] - rig.heads[A]
            m = {'elbow_twist': 0.0, 'wrist_twist': 0.0, 'wrist_bend': 0.0, 'shoulder_twist': 0.0,
                 'weapon_rel': 0.0, 'flip': 0.0, 'spin': 0.0, 'over90_s': 0.0,
                 'at': {}}
            prev = None
            dt = float(times[1] - times[0]) if len(times) > 1 else 1 / 30
            for t in times:
                dA = rig.delta(channels, A, t); dF = rig.delta(channels, F, t); dH = rig.delta(channels, H, t)
                elbow = qmul(dF, qinv(dA))
                wrist = qmul(dH, qinv(dF))
                e_tw = twist_deg(elbow, qrot(dA, fa))
                w_tw = twist_deg(wrist, qrot(dF, fa))
                w_bend = vangle(qrot(dF, fa), qrot(dH, fa))
                for key, value in (('elbow_twist', abs(e_tw)), ('wrist_twist', abs(w_tw)), ('wrist_bend', w_bend)):
                    if value > m[key]:
                        m[key] = value; m['at'][key] = round(float(t), 4)
                if 'SkinBody' in rig.heads:
                    dB = rig.delta(channels, 'SkinBody', t)
                    m['shoulder_twist'] = max(m['shoulder_twist'], abs(twist_deg(qmul(dA, qinv(dB)), qrot(dB, ua))))
                if Wp in rig.heads:
                    dW = rig.delta(channels, Wp, t)
                    m['weapon_rel'] = max(m['weapon_rel'], qangle(qmul(dW, qinv(dH))))
                if max(abs(e_tw), abs(w_tw)) > 90: m['over90_s'] += dt
                twists = (e_tw, w_tw)
                # Rolls are judged against the torso: a body turn rolls every vertical bone with it.
                dBi = qinv(rig.delta(channels, 'SkinBody', t)) if 'SkinBody' in rig.heads else np.array([0.0, 0.0, 0.0, 1.0])
                bones = ((qmul(dBi, dA), ua), (qmul(dBi, dF), fa), (qmul(dBi, dH), fa))
                if prev is not None:
                    jump = max(abs((now - before + 180.0) % 360.0 - 180.0) for now, before in zip(twists, prev[0]))
                    for (d_now, axis), (d_before, _) in zip(bones, prev[1]):
                        # Roll of the bone about its own posed axis between the two keys,
                        # against how far that axis itself swung.
                        roll = abs(twist_deg(qmul(d_now, qinv(d_before)), qrot(d_now, axis)))
                        swing = vangle(qrot(d_now, axis), qrot(d_before, axis))
                        m['spin'] = max(m['spin'], roll)
                        if roll > FLIP_SWING * swing: jump = max(jump, roll)
                    if jump > m['flip']:
                        m['flip'] = jump; m['at']['flip'] = round(float(t), 4)
                prev = (twists, bones)
            for key in ('elbow_twist', 'wrist_twist', 'wrist_bend', 'shoulder_twist', 'weapon_rel', 'flip', 'spin', 'over90_s'):
                m[key] = round(float(m[key]), 2)
            per_side[side] = m
        out[clip] = per_side
    return out


def worst(clips: dict) -> dict:
    w = {k: 0.0 for k in ('elbow_twist', 'wrist_twist', 'wrist_bend', 'flip', 'spin', 'shoulder_twist', 'weapon_rel', 'over90_s')}
    where = {}
    for clip, sides in clips.items():
        for side, m in sides.items():
            for k in w:
                if m[k] > w[k]:
                    w[k] = m[k]; where[k] = f'{clip}:{side}@{m["at"].get(k, "")}'
    w['where'] = where
    return w


def judge(w: dict, limits: dict) -> list:
    return [f'{k} {w[k]:.0f} > {limits[k]:.0f}' for k in GATED if w[k] > limits[k] + 1e-6]


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    p.add_argument('--ids', default='')
    p.add_argument('--scope', choices=['all', 'b1'], default='all')
    p.add_argument('--glb-dir', default='', help='candidate root: DIR/<id>/<id>.glb is used when it exists')
    p.add_argument('--clips', default=','.join(CLIPS))
    p.add_argument('--elbow', type=float, default=30.0)
    p.add_argument('--wrist-twist', type=float, default=90.0)
    p.add_argument('--wrist-bend', type=float, default=100.0)
    p.add_argument('--flip', type=float, default=45.0)
    p.add_argument('--baseline', default=str(BASELINE) if BASELINE.exists() else '',
                   help="known failures (default tools/3d/twist_baseline.json; '' = strict)")
    p.add_argument('--tol', type=float, default=5.0)
    p.add_argument('--json', default='')
    p.add_argument('--write-baseline', default='', help='write the compact per-hero worst values of this run to FILE')
    p.add_argument('--quiet', action='store_true')
    a = p.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    specs = json.loads(SPECS.read_text()).get('heroes', {})
    if a.ids:
        ids = [i for i in a.ids.split(',') if i]
    elif a.scope == 'b1':
        ids = list(B1_IDS)
    else:
        ids = [i for i in manifest.get('ready_ids', []) if i in manifest['heroes']]
    limits = {'elbow_twist': a.elbow, 'wrist_twist': a.wrist_twist, 'wrist_bend': a.wrist_bend, 'flip': a.flip}
    baseline = json.loads(Path(a.baseline).read_text()).get('heroes', {}) if a.baseline else {}
    clips = [c for c in a.clips.split(',') if c]
    report = {'tool': 'tools/3d/audit_native_twist.py', 'generated_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
              'thresholds_deg': limits, 'clips': clips, 'glb_dir': a.glb_dir, 'baseline': a.baseline, 'heroes': {}}
    failed = []
    for cid in ids:
        row = manifest['heroes'].get(cid)
        if row is None:
            print(f'unknown hero {cid}', file=sys.stderr); failed.append(cid); continue
        path = ROOT / f'art/models/{cid}/{cid}.glb'
        if a.glb_dir:
            cand = Path(a.glb_dir) / cid / f'{cid}.glb'
            if cand.exists(): path = cand
        rig = Rig(path)
        clips_m = measure(rig, clips)
        w = worst(clips_m)
        reasons = judge(w, limits)
        status = 'pass' if not reasons else 'fail'
        if reasons and cid in baseline:
            old = baseline[cid].get('worst', {})
            old_fail = bool(judge(old, limits)) if old else False
            if old_fail and all(w[k] <= old.get(k, 0.0) + a.tol for k in GATED):
                status = 'known'
        if status == 'fail': failed.append(cid)
        spec = specs.get(cid, {})
        report['heroes'][cid] = {'kind': row.get('attack'), 'lead': spec.get('swing_lead_side', spec.get('lead_side', 'R')),
                                 'glb': str(path.relative_to(ROOT) if path.is_relative_to(ROOT) else path), 'glb_sha256': rig.sha,
                                 'status': status, 'reasons': reasons, 'worst': w, 'clips': clips_m}
    report['summary'] = {'heroes': len(ids), 'pass': sum(1 for r in report['heroes'].values() if r['status'] == 'pass'),
                         'known': sum(1 for r in report['heroes'].values() if r['status'] == 'known'),
                         'fail': failed}
    if a.json:
        Path(a.json).parent.mkdir(parents=True, exist_ok=True)
        Path(a.json).write_text(json.dumps(report, indent=1) + '\n')
    if a.write_baseline:
        keep = list(GATED) + ['spin', 'shoulder_twist']
        compact = {'tool': report['tool'], 'generated_utc': report['generated_utc'], 'thresholds_deg': limits,
                   'note': "accepted twist state: 'fail' heroes are known failures (allowed up to --tol worse), "
                           "'pass' heroes must keep passing",
                   'heroes': {cid: {'kind': r['kind'], 'glb_sha256': r['glb_sha256'],
                                    'status': 'fail' if r['reasons'] else 'pass',
                                    'worst': {k: round(float(r['worst'][k]), 2) for k in keep}}
                              for cid, r in report['heroes'].items()}}
        Path(a.write_baseline).parent.mkdir(parents=True, exist_ok=True)
        Path(a.write_baseline).write_text(json.dumps(compact, indent=1, sort_keys=False) + '\n')
    if not a.quiet:
        print('%-9s %-9s %-4s | %6s %6s %6s %6s | %6s %6s %6s %6s | %s' % ('id', 'kind', 'lead', 'elbow', 'wTwist', 'wBend', 'flip',
                                                                        'spin', 'shTw', 'wpnRel', '>90s', 'status'))
        for cid, r in report['heroes'].items():
            w = r['worst']
            print('%-9s %-9s %-4s | %6.0f %6.0f %6.0f %6.0f | %6.0f %6.0f %6.0f %6.2f | %s %s' % (
                cid, r['kind'], r['lead'], w['elbow_twist'], w['wrist_twist'], w['wrist_bend'], w['flip'],
                w['spin'], w['shoulder_twist'], w['weapon_rel'], w['over90_s'], r['status'], '; '.join(r['reasons'])))
        s = report['summary']
        print(f"thresholds elbow<={limits['elbow_twist']:.0f} wrist twist<={limits['wrist_twist']:.0f} "
              f"bend<={limits['wrist_bend']:.0f} flip<={limits['flip']:.0f} deg/key | "
              f"{s['pass']} pass, {s['known']} known, {len(s['fail'])} fail" + (': ' + ','.join(s['fail']) if s['fail'] else ''))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
