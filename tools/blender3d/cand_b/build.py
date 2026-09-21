# -*- coding: utf-8 -*-
"""후보 B — **스킨드 휴머노이드.** 2·3·4단계를 한 프로세스에서 돌리고 .blend 를 남긴다.

    env -u DISPLAY bl -b --factory-startup --python tools/blender3d/cand_b/build.py

## 왜 이렇게 만들었나
* **한 덩어리 메시** — Skin 모디파이어로 「막대 인간」(정점+엣지)에 살을 붙여
  **이어진 하나의 메시**를 굽는다. 상자를 여러 개 놓고 합치는 길과 달리 어깨·허리·
  무릎이 실제로 이어져 있어 자동 웨이트가 접을 면이 있다.
* **소품(대검·눈)만 강체** — 뼈 하나에 웨이트 1.0 으로 매단다. 부모 관계(`parent_type`)
  대신 **Armature 모디파이어 + 정점 그룹**을 쓴다. 뼈 부모는 원점이 tail 이라
  헤드리스에서 행렬을 손으로 맞춰야 하는데, 정점 그룹은 그런 것이 없다.
  ★ 매다는 뼈는 반드시 `use_deform=True` 여야 한다 — Armature 모디파이어는
    변형하지 않는 뼈의 정점 그룹을 **조용히 무시**한다. 첫 판에서 대검이 손을 따라가지
    않고 허공에 못 박혀 있던 것이 이것이었다.
* **다리는 root 직속** — pelvis 밑에 두면 상체를 비틀 때 발이 같이 돌아
  `foot_y_spread` 가 깨진다. 게임 리그에서 흔히 쓰는 갈래다.
* 재질은 **가장 가까운 뼈대 마디**로 정한다. 좌표 구간으로 나누면 팔을 움직이는 순간
  경계가 몸을 가로지른다 — 마디로 나누면 경계가 몸을 따라간다.

## 96px 옆모습에서 실루엣을 지는 것 넷
후드 덩어리(위·뒤) · 수염(앞) · 곰가죽 망토(뒤로 불룩) · 대검의 대각선.
**어깨 폭은 이 방향에서 안 보인다** — E 는 순수 옆모습이라 화면 가로가 캐릭터의 Y 축이다.
그래서 「떡 벌어진 어깨」를 **몸통의 앞뒤 두께**로 옮겨 놓았다.
"""
import bpy, math, os, sys, json
from mathutils import Vector, Quaternion, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import spec  # noqa: E402

OUT = os.path.join(spec.ROOT.as_posix(), "build", "b3d", "cand_b")
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------- 팔레트 → 재질
# 재질당 3톤 (sprite_design.md §2-1). 전부 spec.palette_for("ice") 15색 안이다.
# ★ 밴드 위치도 재질마다 다르다. 전부 0.30/0.68 로 두었더니 화면이 통째로 창백해졌다 —
#   해가 위·앞에서 오므로 넓은 면이 죄다 「빛」 칸에 앉았기 때문이다. 문턱을 올리면
#   같은 세 색으로도 어두운 칸이 넓어진다.
MATS = {
    #                그늘        중간        빛          (밴드 문턱 둘)
    "plate":   ("#24568c", "#3f8fc9", "#6fb8e6", 0.30, 0.80),   # 강청색 판금·겉옷
    "fur":     ("#8fd0ef", "#dff4ff", "#f4fcff", 0.26, 0.62),   # 후드·수염 (눈처럼 흰 털)
    "pelt":    ("#3f8fc9", "#6fb8e6", "#8fd0ef", 0.28, 0.70),   # ★곰가죽 망토 — 후드보다 두 칸 어둡다
    "skin":    ("#7a5136", "#b9835a", "#eec49a", 0.14, 0.42),   # 살결 (얼굴이 밝게 앉게 문턱을 낮췄다)
    "metal":   ("#3a3740", "#8d8a95", "#ccc8d4", 0.34, 0.78),   # 건틀릿·정강이·손잡이
    "cloak":   ("#000000", "#3a3740", "#8d8a95", 0.36, 0.86),   # ★어두운 곰가죽 망토·바지
    "leather": ("#2b1a12", "#7a5136", "#b9835a", 0.30, 0.78),   # 허리띠
    "blade":   ("#3f8fc9", "#6fb8e6", "#b8e6f8", 0.24, 0.62),   # ★얼음 칼날 — 흰 털보다 한 칸 어둡게
    "dark":    ("#000000", "#000000", "#000000", 0.30, 0.70),   # 눈 두 점
}
MAT_ORDER = ["plate", "fur", "pelt", "skin", "metal", "cloak", "leather", "blade", "dark"]

# ---------------------------------------------------------------- 뼈대(막대 인간)
# 캐릭터는 **-Y 를 본다**(= 방향 S). 캐릭터의 오른쪽은 -X (E 에서 카메라 쪽)다.
# yaw +90(E)이면 -Y 가 화면 오른쪽(+X)으로 가므로 총구 x 가 양수가 된다.
# 키 ≈ 1.83m · 맨머리 지름 0.34m → **5.4등신**.
#: ★ 껍질 수축(RSCALE)만으로는 **키**가 안 돌아온다 — 캡도 같이 줄어서 그림 높이가
#:   설계 1.70m 인데 화면에서 62px(=1.55m)로 나왔다. 뼈대 전체를 여기서 한 번 키운다.
SCALE = 1.10

J_RAW = {
    "pelvis":  (0.00,  0.00, 0.74),
    "waist":   (0.00, -0.01, 0.89),
    "chest":   (0.00, -0.02, 1.05),
    "neck":    (0.00,  0.00, 1.24),
    "head":    (0.00, -0.05, 1.44),
    "hoodb":   (0.00,  0.12, 1.53),   # 뒤로 젖혀진 후드
    "hoodt":   (0.00,  0.07, 1.635),
    "hoodf":   (0.00, -0.09, 1.525),  # 이마 위로 내려온 후드 챙
    "beard1":  (0.00, -0.21, 1.25),   # ★얼굴 창을 비우려고 아래·앞으로 내렸다
    "beard2":  (0.00, -0.18, 1.10),
    "mantle":  (0.00,  0.22, 0.95),   # 곰가죽이 등 뒤로 불룩
    "cape":    (0.00,  0.18, 0.74),   # 그 자락 (어둡다)
    "skirt":   (0.00, -0.02, 0.52),   # 겉옷 자락 (무릎까지 덮는다)
    # --- 마디 중간점: 폴리를 1200~2000 안으로 올리고 어깨·허리·무릎을 부드럽게 접는다
    "chest0":  (0.00, -0.015, 0.97),
    "neck0":   (0.00,  0.00, 1.345),
    "faR":     (-0.27, -0.26, 1.00), "faL": (0.27, -0.235, 0.99),
    "shinR":   (-0.145, -0.085, 0.25), "shinL": (0.145, 0.045, 0.25),
    "skirt0":  (0.00, -0.01, 0.62),
    "mant0":   (0.00,  0.13, 0.99),

    "shR":  (-0.27, -0.01, 1.14), "uaR": (-0.31, -0.10, 1.02),
    "elbR": (-0.33, -0.20, 0.99), "hndR": (-0.19, -0.31, 1.01),
    "shL":  ( 0.27, -0.01, 1.14), "uaL": ( 0.31, -0.09, 1.03),
    "elbL": ( 0.33, -0.18, 0.94), "hndL": ( 0.20, -0.28, 1.04),

    "hipR": (-0.13, -0.02, 0.72), "thR": (-0.14, -0.06, 0.56),
    "kneR": (-0.145, -0.10, 0.40), "ankR": (-0.145, -0.07, 0.10),
    "toeR": (-0.145, -0.20, 0.055),
    "hipL": ( 0.13,  0.02, 0.72), "thL": ( 0.14,  0.04, 0.56),
    "kneL": ( 0.145, 0.03, 0.40), "ankL": ( 0.145, 0.05, 0.10),
    "toeL": ( 0.145, -0.06, 0.055),
}
J = {k: tuple(c * SCALE for c in v) for k, v in J_RAW.items()}


def S3(t):
    return tuple(c * SCALE for c in t)


#: 마디 = (a, b, 반지름a, 반지름b, 재질)
LIMBS = [
    ("pelvis", "waist",  0.235, 0.225, "plate"),
    ("waist",  "chest0", 0.225, 0.265, "plate"),
    ("chest0", "chest",  0.265, 0.295, "plate"),
    ("chest",  "neck",   0.295, 0.100, "plate"),
    ("neck",   "neck0",  0.100, 0.115, "skin"),
    ("neck0",  "head",   0.115, 0.150, "skin"),
    ("head",   "hoodb",  0.150, 0.175, "fur"),
    ("hoodb",  "hoodt",  0.175, 0.115, "fur"),
    ("head",   "hoodf",  0.150, 0.130, "fur"),
    ("head",   "beard1", 0.125, 0.120, "fur"),
    ("beard1", "beard2", 0.120, 0.090, "fur"),
    ("chest",  "mant0",  0.295, 0.200, "pelt"),    # 어깨의 곰가죽
    ("mant0",  "mantle", 0.200, 0.180, "pelt"),
    ("mantle", "cape",   0.180, 0.150, "cloak"),   # 그 아래 자락만 어둡다
    ("pelvis", "skirt0", 0.235, 0.225, "plate"),   # 겉옷 자락 — 무릎까지 덮어 다리를 가린다
    ("skirt0", "skirt",  0.225, 0.200, "plate"),

    ("chest",  "shR",    0.295, 0.180, "pelt"),     # 곰가죽 어깨
    ("shR",    "uaR",    0.170, 0.120, "plate"),
    ("uaR",    "elbR",   0.120, 0.100, "plate"),
    ("elbR",   "faR",    0.100, 0.100, "metal"),
    ("faR",    "hndR",   0.100, 0.105, "metal"),
    ("chest",  "shL",    0.295, 0.180, "pelt"),
    ("shL",    "uaL",    0.170, 0.120, "plate"),
    ("uaL",    "elbL",   0.120, 0.100, "plate"),
    ("elbL",   "faL",    0.100, 0.098, "metal"),
    ("faL",    "hndL",   0.098, 0.100, "metal"),

    ("pelvis", "hipR",   0.235, 0.150, "plate"),
    ("hipR",   "thR",    0.150, 0.135, "plate"),
    ("thR",    "kneR",   0.135, 0.115, "plate"),
    ("kneR",   "shinR",  0.115, 0.105, "cloak"),
    ("shinR",  "ankR",   0.105, 0.095, "metal"),
    ("ankR",   "toeR",   0.095, 0.075, "cloak"),
    ("pelvis", "hipL",   0.235, 0.150, "plate"),
    ("hipL",   "thL",    0.150, 0.135, "plate"),
    ("thL",    "kneL",   0.135, 0.115, "plate"),
    ("kneL",   "shinL",  0.115, 0.105, "cloak"),
    ("shinL",  "ankL",   0.105, 0.095, "metal"),
    ("ankL",   "toeL",   0.095, 0.075, "cloak"),
]

#: 뼈 — (이름, head, tail, 부모, 변형하는가)
#: ★ 다리는 pelvis 가 아니라 root 밑이다 (머리말 참고).
BONES = [
    ("root",     S3((0, 0, 0)),     S3((0, -0.25, 0)),None,       False),
    ("pelvis",   J["pelvis"],      J["waist"],      "root",     True),
    ("spine",    J["waist"],       J["chest"],      "pelvis",   True),
    ("chest",    J["chest"],       J["neck"],       "spine",    True),
    ("neck",     J["neck"],        J["head"],       "chest",    True),
    ("head",     J["head"],        S3((0, 0.01, 1.67)), "neck",     True),
    ("shoulder.R", S3((0, -0.01, 1.12)), J["shR"],      "chest",    True),
    ("upperarm.R", J["shR"],       J["elbR"],       "shoulder.R", True),
    ("forearm.R",  J["elbR"],      J["hndR"],       "upperarm.R", True),
    ("hand.R",     J["hndR"],      S3((-0.16, -0.38, 1.00)), "forearm.R", True),
    ("shoulder.L", S3((0, -0.01, 1.12)), J["shL"],      "chest",    True),
    ("upperarm.L", J["shL"],       J["elbL"],       "shoulder.L", True),
    ("forearm.L",  J["elbL"],      J["hndL"],       "upperarm.L", True),
    ("hand.L",     J["hndL"],      S3((0.18, -0.35, 1.08)), "forearm.L", True),
    ("thigh.R",  J["hipR"],        J["kneR"],       "root",     True),
    ("shin.R",   J["kneR"],        J["ankR"],       "thigh.R",  True),
    ("foot.R",   J["ankR"],        J["toeR"],       "shin.R",   True),
    ("thigh.L",  J["hipL"],        J["kneL"],       "root",     True),
    ("shin.L",   J["kneL"],        J["ankL"],       "thigh.L",  True),
    ("foot.L",   J["ankL"],        J["toeL"],       "shin.L",   True),
    ("sword",    S3((-0.18, -0.29, 1.04)), S3((-0.18, -0.29, 1.36)), "hand.R", False),
]

# ---------------------------------------------------------------- 대검
#: 손잡이 밑동 G 에서 칼끝 T 로.
#: ★★ 칼날의 **넓은 면이 카메라를 봐야 한다.** E 에서 카메라는 캐릭터 로컬 +X 를 따라
#:   들여다보므로, 칼날 폭은 **화면 안쪽 수직축(up)**에 실어야 한다. 첫 판에서 폭을
#:   `side`(= 로컬 X ≈ 시선축)에 실었더니 칼이 **날 세운 바늘**로 찍혔다.
#: ★ Subdivision Surface 는 Catmull-Clark 이라 **껍질을 안쪽으로 당긴다**(실측 약 0.82배).
#:   막대 인간에 적어 둔 반지름을 그대로 두면 화면에서 통째로 홀쭉해진다 — 네 판을 그렇게
#:   날렸다. 여기서 한 번에 갚는다.
RSCALE = 1.20

SW_G = Vector((-0.18, -0.24, 1.08)) * SCALE
SW_T = Vector((-0.06, -0.96, 0.70)) * SCALE
SW_BLADE_W = 0.175 * SCALE  # 7.7px — 과장했다. 얇으면 양자화가 끊는다
SW_THICK = 0.05 * SCALE


def toon_material(name, tones):
    """Diffuse → ShaderToRGB → ColorRamp(CONSTANT) → Emission.

    ★ 램프 색을 **팔레트 그 값**으로 넣고 view_transform 을 Standard 로 두면
      렌더 PNG 픽셀이 팔레트 색 그대로 찍힌다 — 양자화가 아무것도 안 바꾼다.
    """
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    dif.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = 'CONSTANT'
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0
    cr.elements[0].color = spec.hex2linear(tones[0]) + (1,)
    cr.elements[1].position = tones[3]
    cr.elements[1].color = spec.hex2linear(tones[1]) + (1,)
    cr.elements.new(tones[4]).color = spec.hex2linear(tones[2]) + (1,)
    emi = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], emi.inputs[0])
    nt.links.new(emi.outputs[0], out.inputs["Surface"])
    return m


def seg_dist(p, a, b):
    ab = b - a
    L2 = ab.dot(ab)
    t = 0.0 if L2 < 1e-12 else max(0.0, min(1.0, (p - a).dot(ab) / L2))
    return (p - (a + ab * t)).length


def build_body(mats):
    """막대 인간 → Skin → Subsurf → 한 덩어리 메시."""
    names = sorted({n for l in LIMBS for n in l[:2]})
    idx = {n: i for i, n in enumerate(names)}
    verts = [J[n] for n in names]
    edges = [(idx[a], idx[b]) for a, b, *_ in LIMBS]
    me = bpy.data.meshes.new("BodyMesh")
    me.from_pydata(verts, edges, [])
    me.update()
    ob = bpy.data.objects.new("Body", me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)

    sk = ob.modifiers.new("Skin", 'SKIN')
    sk.use_smooth_shade = True
    sk.branch_smoothing = 0.30
    rad = {n: 0.0 for n in names}
    for a, b, ra, rb, _ in LIMBS:
        rad[a] = max(rad[a], ra)
        rad[b] = max(rad[b], rb)
    d = me.skin_vertices[0].data
    for n, i in idx.items():
        r = rad[n] * RSCALE * SCALE
        d[i].radius = (r, r)
    d[idx["pelvis"]].use_root = True

    ss = ob.modifiers.new("SS", 'SUBSURF')
    ss.levels = ss.render_levels = 1
    bpy.ops.object.modifier_apply(modifier="Skin")
    bpy.ops.object.modifier_apply(modifier="SS")

    for n in MAT_ORDER:
        ob.data.materials.append(mats[n])
    mi = {n: i for i, n in enumerate(MAT_ORDER)}

    segs = [(Vector(J[a]), Vector(J[b]), m) for a, b, _, _, m in LIMBS]
    for poly in ob.data.polygons:
        c = poly.center
        best, bm = 1e9, "plate"
        for a, b, m in segs:
            dd = seg_dist(c, a, b)
            if dd < best:
                best, bm = dd, m
        # 얼굴은 **머리 앞아래**의 좁은 창 하나뿐이다. 나머지는 후드가 덮는다.
        if bm == "skin":
            bm = "fur"                       # 머리 겉은 통째로 후드다. 얼굴은 build_face 가 얹는다
        if bm == "plate" and 0.85 * SCALE <= c.z <= 0.93 * SCALE and abs(c.x) < 0.28 * SCALE:
            bm = "leather"                   # 허리띠
        poly.material_index = mi[bm]
    from collections import Counter
    hist = Counter(MAT_ORDER[p.material_index] for p in ob.data.polygons)
    print("MATHIST " + json.dumps(dict(hist)))
    bpy.ops.object.shade_smooth()
    return ob


def _box(acc, ctr, size):
    cx, cy, cz = ctr
    sx, sy, sz = (s * 0.5 for s in size)
    base = len(acc[0])
    for dx in (-1, 1):
        for dy in (-1, 1):
            for dz in (-1, 1):
                acc[0].append((cx + dx * sx, cy + dy * sy, cz + dz * sz))
    for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
              (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        acc[1].append(tuple(base + i for i in f))


def build_sword(mats):
    """캐논 좌표 = (x 두께 · y 길이 · z 폭). x 가 시선축이 되도록 옮긴다."""
    acc = ([], [], [])
    L = (SW_T - SW_G).length
    T, W = SW_THICK, SW_BLADE_W
    _box(acc, (0, -0.155, 0), (T * 1.1, 0.31, 0.075))                  # 손잡이
    _box(acc, (0, -0.325, 0), (T * 1.4, 0.06, 0.115))                  # 폼멜
    _box(acc, (0, 0.015, 0), (T * 1.3, 0.06, 0.34))                    # 크로스가드
    guard_n = len(acc[1])
    _box(acc, (0, L * 0.45, 0), (T, L * 0.86, W))                      # 칼날 몸통
    _box(acc, (0, L * 0.93, 0), (T * 0.8, L * 0.16, W * 0.52))         # 칼끝
    blade = set(range(guard_n, len(acc[1])))

    ax = (SW_T - SW_G).normalized()
    side = ax.cross(Vector((0, 0, 1)))
    if side.length < 1e-5:
        side = Vector((1, 0, 0))
    side.normalize()
    up = side.cross(ax).normalized()
    M = Matrix(((side.x, ax.x, up.x, SW_G.x),
                (side.y, ax.y, up.y, SW_G.y),
                (side.z, ax.z, up.z, SW_G.z),
                (0, 0, 0, 1)))
    vs = [tuple(M @ Vector(v)) for v in acc[0]]
    me = bpy.data.meshes.new("SwordMesh")
    me.from_pydata(vs, [], acc[1])
    me.update()
    ob = bpy.data.objects.new("Sword", me)
    bpy.context.scene.collection.objects.link(ob)
    for n in MAT_ORDER:
        ob.data.materials.append(mats[n])
    mi = {n: i for i, n in enumerate(MAT_ORDER)}
    for i, poly in enumerate(me.polygons):
        poly.material_index = mi["blade"] if i in blade else mi["metal"]
    return ob


def build_face(mats):
    """★ 얼굴은 **따로 만든 판때기**다 — 한 덩어리 메시 위에 좌표 규칙으로 재질을 찍는
    길로는 한 폴리도 못 잡았다(실측: 얼굴 창에 든 폴리 0개). Skin 모디파이어의 머리는
    지름이 7px 인데 폴리 하나가 3~4px 이라, 「이 구간은 살결」이 격자에 안 걸린다.
    눈 두 점(sprite_design.md §5)·후드 챙 그늘도 같은 까닭으로 여기서 만든다.

    셋 다 머리 뼈에 강체로 매단다."""
    parts = []
    acc = ([], [], [])
    # ★ 크기는 **머리 지름(약 6.5px)** 에 맞춘다. 처음에 얼굴 판을 머리보다 넓게(7.6px)
    #   만들었더니 후드 밖으로 삐져나와 「부리」로 읽혔다.
    _box(acc, S3((0.0, -0.185, 1.428)), S3((0.115, 0.075, 0.115)))     # 얼굴 (화면 약 5x4px)
    parts.append(("skin", len(acc[1])))
    for sx in (-1, 1):                                                  # 눈 두 점 (약 2x1px)
        _box(acc, S3((sx * 0.045, -0.216, 1.442)), S3((0.055, 0.028, 0.030)))
    parts.append(("dark", len(acc[1])))
    _box(acc, S3((0.0, -0.222, 1.333)), S3((0.165, 0.100, 0.140)))     # 수염 앞턱 (흰 쐐기)
    parts.append(("fur", len(acc[1])))
    me = bpy.data.meshes.new("FaceMesh")
    me.from_pydata(acc[0], [], acc[1])
    me.update()
    ob = bpy.data.objects.new("Face", me)
    bpy.context.scene.collection.objects.link(ob)
    for n in MAT_ORDER:
        ob.data.materials.append(mats[n])
    mi = {n: i for i, n in enumerate(MAT_ORDER)}
    lo = 0
    for name, hi in parts:
        for i in range(lo, hi):
            me.polygons[i].material_index = mi[name]
        lo = hi
    return ob


def build_rig():
    ad = bpy.data.armatures.new("Rig")
    arm = bpy.data.objects.new("Rig", ad)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for name, h, t, par, deform in BONES:
        b = ad.edit_bones.new(name)
        b.head, b.tail = h, t
        b.use_deform = deform
    for name, h, t, par, deform in BONES:
        if par:
            ad.edit_bones[name].parent = ad.edit_bones[par]
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm


def bind_rigid(ob, arm, bone):
    """소품을 뼈 하나에 강체로. ★ 그 뼈는 use_deform=True 여야 한다."""
    ob.parent = arm
    ob.matrix_parent_inverse = arm.matrix_world.inverted()
    g = ob.vertex_groups.new(name=bone)
    g.add(list(range(len(ob.data.vertices))), 1.0, 'REPLACE')
    m = ob.modifiers.new("Arm", 'ARMATURE')
    m.object = arm
    m.use_vertex_groups = True


def manual_weights(ob, arm):
    """되돌림 길 — 자동 웨이트가 실패했을 때 **뼈 마디까지의 거리**로 직접 칠한다."""
    segs = [(b.name, b.head_local.copy(), b.tail_local.copy())
            for b in arm.data.bones if b.use_deform]
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    gs = {n: ob.vertex_groups.new(name=n) for n, _, _ in segs}
    for v in ob.data.vertices:
        ds = sorted(((seg_dist(v.co, a, b), n) for n, a, b in segs))
        near = [(d, n) for d, n in ds if d <= ds[0][0] * 1.9 + 0.05][:3]
        ws = [(1.0 / (d + 0.02) ** 3, n) for d, n in near]
        tot = sum(w for w, _ in ws)
        for w, n in ws:
            gs[n].add([v.index], w / tot, 'REPLACE')


# ---------------------------------------------------------------- 동작
# 회전은 **캐릭터 로컬 세계축** 기준이다 (+X 왼쪽 · -Y 앞 · +Z 위).
# 뼈 로컬축은 roll 에 따라 제각각이라, 세계축을 뼈 공간으로 바꿔서 넣는다.
#   +X 회전 = 앞으로 숙이기 / 팔을 아래로 휘두르기
#   -X 회전 = 뒤로 젖히기 / 팔을 위로 되감기      (X 축이 곧 화면의 회전축이다)
#   +Z 회전 = 왼쪽으로(카메라 반대쪽으로) 비틀기
AX = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1))}


def wrot(pb, pairs):
    M = pb.bone.matrix_local.to_3x3()
    Mi = M.inverted()
    q = Quaternion((1, 0, 0, 0))
    for ax, deg in pairs:
        q = q @ Quaternion((Mi @ AX[ax]).normalized(), math.radians(deg))
    return q


def make_action(arm, name, keys):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True      # ★ 사용자가 0 이면 저장할 때 조용히 사라진다
    if arm.animation_data is None:
        arm.animation_data_create()
    old = arm.animation_data.action
    arm.animation_data.action = act
    for fr, poses in keys:
        for bn, pairs in poses.items():
            pb = arm.pose.bones[bn]
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = wrot(pb, pairs)
            pb.keyframe_insert("rotation_quaternion", frame=fr)
    arm.animation_data.action = old
    return act


#: ★★ **머리는 늘 카메라 쪽으로 36도 돌려 둔다.**
#:   spec.GAME_DIR 가 "E"(yaw 90 = 순수 옆모습)인데, 옆모습에서 얼굴 면의 법선은
#:   시선축과 **나란해서** 화면에 한 픽셀도 안 남는다 — 얼굴을 아무리 크게 만들어도
#:   보이지 않는다(다섯 판을 그렇게 날렸다). 몸은 옆모습으로 두고 목만 돌리는 것은
#:   2D 스프라이트가 늘 쓰는 속임수이고, 3D 에서는 뼈 하나로 끝난다.
HEAD_TURN = -36.0     # -Z 쪽 = 카메라 쪽
NECK_TURN = -12.0

Z = []      # 중립
UPPER = ["pelvis", "spine", "chest", "neck", "head",
         "shoulder.R", "upperarm.R", "forearm.R", "hand.R",
         "shoulder.L", "upperarm.L", "forearm.L", "hand.L"]


def full(d):
    """안 적은 뼈는 중립으로 — 키가 빠지면 앞 키가 끌려와 동작이 흐른다.
    ★ 목·머리에는 카메라 쪽 돌림을 언제나 얹는다(HEAD_TURN 머리말)."""
    out = {b: d.get(b, Z) for b in UPPER}
    out["head"] = list(out["head"]) + [("Z", HEAD_TURN)]
    out["neck"] = list(out["neck"]) + [("Z", NECK_TURN)]
    return out


#: 숨쉬기 — 다리는 한 톨도 안 움직인다(발밑 y 를 못 박는다).
IDLE_KEYS = [
    (1, full({})),
    (4, full({"spine": [("X", -3.5)], "chest": [("X", -4.5)], "head": [("X", 4.0)],
              "neck": [("X", 2.0)], "pelvis": [("X", 2.0)],
              "shoulder.R": [("X", 5.0)], "upperarm.R": [("X", 8.0)], "forearm.R": [("X", -6.0)],
              "shoulder.L": [("X", 5.0)], "upperarm.L": [("X", 6.0)], "forearm.L": [("X", -5.0)]})),
    (7, full({})),
]

#: 베기 — 0-based 3번 칸(= blender 4번 프레임)이 「놓는 칸」.
#:   1 준비 → 2·3 되감기(칼을 뒤·위로) → **4 타격(앞으로 뻗어 벤다)** → 5 따라감 → 6 회복
#: ★ 날을 머리 위로 치켜들지 않는다(CLAUDE.md 4-1-1 slash). 어깨 높이에서 뒤로 감는다.
ATTACK_KEYS = [
    # ★★ 세 번 고친 자리다.
    #   (1) -X 가 칼을 올리고 +X 가 내린다 — 부호를 거꾸로 잡았었다.
    #   (2) **spine·chest 도 팔 사슬의 부모다.** 몸통을 앞으로 숙인 각이 그대로 팔에 더해진다.
    #       그것을 안 세었더니 칼끝이 칸 아래로 잘렸다(바닥 96).
    #   (3) **Z 비틀기를 크게 주면 옆모습에서 칼이 짧아진다.** ±36도를 주었더니 칼이 카메라
    #       쪽으로 돌아 칼끝 x 가 89 → 73 으로 줄었다. 옆모습에서 Z 비틀기는 「무게」가
    #       아니라 그냥 **길이 손실**이다. ±20도 안쪽으로 눌렀다.
    #   지금 규칙(render.py 가 칼끝을 재서 찍어 준다): 팔+몸통 X 합 s 에 대해
    #       화면 각 ≈ -17 - 1.16 x s  (s 가 음수면 올라간다)
    (1, full({})),
    # 2 되감기 시작 (X합 -49 → 화면 +40도)
    (2, full({"pelvis": [("Z", 4)], "spine": [("Z", 5), ("X", -3)],
              "chest": [("Z", 7), ("X", -6)], "head": [("Z", -6), ("X", -3)],
              "shoulder.R": [("X", -7)], "upperarm.R": [("X", -20)],
              "forearm.R": [("X", -10)], "hand.R": [("X", -3)],
              "shoulder.L": [("X", -6)], "upperarm.L": [("X", -14)], "forearm.L": [("X", -10)]})),
    # 3 되감기 끝 — 날이 어깨 위로 곧추선다 (X합 -88 → 화면 +85도)
    (3, full({"pelvis": [("Z", 6)], "spine": [("Z", 8), ("X", -5)],
              "chest": [("Z", 11), ("X", -10)], "head": [("Z", -10), ("X", -5)],
              "shoulder.R": [("X", -13)], "upperarm.R": [("X", -36)],
              "forearm.R": [("X", -18)], "hand.R": [("X", -6)],
              "shoulder.L": [("X", -11)], "upperarm.L": [("X", -26)], "forearm.L": [("X", -18)]})),
    # 4 ★놓는 칸 — 곧추선 날이 한 칸에 92도를 돌아 **가슴 높이로 수평으로** 지나간다.
    #   (X합 -8 → 화면 -8도) 처음에 -34도짜리 내리치기로 잡았더니 칼끝이 무릎 높이라
    #   총구가 anchor 기준 y=-17 이었다 — 탄이 정강이에서 나가는 셈이다.
    (4, full({"pelvis": [("Z", -5)], "spine": [("Z", -6), ("X", 2)],
              "chest": [("Z", -9), ("X", 3)], "head": [("Z", 5), ("X", 4)],
              "shoulder.R": [("X", -3)], "upperarm.R": [("X", -6)],
              "forearm.R": [("X", -3)], "hand.R": [("X", -1)],
              "shoulder.L": [("X", 8)], "upperarm.L": [("X", 20)], "forearm.L": [("X", 14)]})),
    # 5 따라감 (X합 +18 → 화면 -38도). 칼끝이 발밑을 안 넘는 자리에서 멈춘다
    (5, full({"pelvis": [("Z", -6)], "spine": [("Z", -8), ("X", 4)],
              "chest": [("Z", -11), ("X", 7)], "head": [("Z", 7), ("X", 6)],
              "shoulder.R": [("X", 2)], "upperarm.R": [("X", 4)],
              "forearm.R": [("X", 1)], "hand.R": [("X", 0)],
              "shoulder.L": [("X", 11)], "upperarm.L": [("X", 26)], "forearm.L": [("X", 19)]})),
    # 6 회복 (X합 +4 → 화면 -22도)
    (6, full({"pelvis": [("Z", -2)], "spine": [("Z", -3), ("X", 2)],
              "chest": [("Z", -4), ("X", 3)], "head": [("Z", 2), ("X", 2)],
              "shoulder.R": [("X", 0)], "upperarm.R": [("X", -1)],
              "forearm.R": [("X", 0)], "hand.R": [("X", 0)],
              "shoulder.L": [("X", 3)], "upperarm.L": [("X", 8)], "forearm.L": [("X", 6)]})),
]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    vl = bpy.context.view_layer
    R = {"route": "skin-modifier(막대인간) + subsurf1 → 한 덩어리 메시"}

    mats = {n: toon_material("m_" + n, MATS[n]) for n in MAT_ORDER}
    body = build_body(mats)
    body.data.calc_loop_triangles()
    R["body_verts"] = len(body.data.vertices)
    R["body_polys"] = len(body.data.polygons)
    R["body_tris"] = len(body.data.loop_triangles)

    arm = build_rig()
    R["bones"] = len(arm.data.bones)

    # --- 자동 웨이트 (sword 뼈는 아직 use_deform=False → 몸이 그 그룹을 안 받는다)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    arm.select_set(True)
    vl.objects.active = arm
    err = None
    try:
        bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    except Exception as e:
        err = "%s: %s" % (type(e).__name__, e)
    R["auto_weight_error"] = err
    zero = sum(1 for v in body.data.vertices if sum(g.weight for g in v.groups) < 1e-6)
    R["vgroups"] = len(body.vertex_groups)
    R["verts_no_weight"] = zero
    if err or zero > 0 or len(body.vertex_groups) < 5:
        manual_weights(body, arm)
        if not any(m.type == 'ARMATURE' for m in body.modifiers):
            m = body.modifiers.new("Arm", 'ARMATURE')
            m.object = arm
        body.parent = arm
        R["weight_route"] = "manual (뼈 마디까지의 거리)"
        R["verts_no_weight_after"] = sum(
            1 for v in body.data.vertices if sum(g.weight for g in v.groups) < 1e-6)
    else:
        R["weight_route"] = "bpy.ops.object.parent_set(ARMATURE_AUTO)"

    # ★ 이제 소품 뼈를 변형 뼈로 올린다 (모디파이어가 무시하지 않게)
    arm.data.bones["sword"].use_deform = True
    R["deform_bones"] = sum(1 for b in arm.data.bones if b.use_deform)

    sword = build_sword(mats)
    sword.data.calc_loop_triangles()
    R["sword_tris"] = len(sword.data.loop_triangles)
    bind_rigid(sword, arm, "sword")
    face = build_face(mats)
    face.data.calc_loop_triangles()
    R["eye_tris"] = len(face.data.loop_triangles)
    bind_rigid(face, arm, "head")
    R["tris_total"] = R["body_tris"] + R["sword_tris"] + R["eye_tris"]

    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    make_action(arm, "idle", IDLE_KEYS)
    make_action(arm, "attack", ATTACK_KEYS)
    R["actions"] = [a.name for a in bpy.data.actions]

    # --- 실제로 접히는가 (smoke/s1 과 같은 증명)
    arm.animation_data.action = bpy.data.actions["attack"]
    sc.frame_set(1); vl.update()
    before = [v.co.copy() for v in body.evaluated_get(vl.depsgraph).to_mesh().vertices]
    swb = [v.co.copy() for v in sword.evaluated_get(vl.depsgraph).to_mesh().vertices]
    sc.frame_set(4); vl.update()
    after = [v.co.copy() for v in body.evaluated_get(vl.depsgraph).to_mesh().vertices]
    swa = [v.co.copy() for v in sword.evaluated_get(vl.depsgraph).to_mesh().vertices]
    dlt = [(a - b).length for a, b in zip(after, before)]
    R["verts_moved_f1_to_f4"] = sum(1 for d in dlt if d > 1e-4)
    R["max_vert_delta"] = round(max(dlt), 4)
    low = [d for v, d in zip(body.data.vertices, dlt) if v.co.z < 0.30]
    R["foot_region_max_delta"] = round(max(low), 5) if low else None
    R["sword_max_delta"] = round(max((a - b).length for a, b in zip(swa, swb)), 4)
    arm.animation_data.action = bpy.data.actions["idle"]
    sc.frame_set(1)

    blend = os.path.join(OUT, "jokull_b.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    R["blend"] = blend
    with open(os.path.join(OUT, "build_report.json"), "w") as f:
        json.dump(R, f, ensure_ascii=False, indent=1)
    print("BUILD_JSON " + json.dumps(R, ensure_ascii=False))


main()
