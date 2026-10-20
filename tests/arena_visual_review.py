#!/usr/bin/env python3
"""Capture the arena using actual Godot OpenGL at both mobile review sizes.

    python3 tests/arena_visual_review.py                      # every HUD/flow screen
    python3 tests/arena_visual_review.py --only spiral        # one older scenario
    python3 tests/arena_visual_review.py --only box           # the jewel box over the field ("rite" = old name)
    python3 tests/arena_visual_review.py --only biome --out-root build/biomes/after \
        --before build/biomes/before                          # battlefield biome review

Every mode draws into an off-screen picture (--film) when the login session's GPU display
is up (about 30 fps, serialised with the other GPU captures through
build/casual-overhaul/gpu.lock) and falls back to a software Xvfb window otherwise
(REVIEW_DISPLAY=xvfb forces it). The biome review (2026-10-13) writes, per resolution:

    screen_<theme>.png   the live battle as the player sees it (HUD on)
    world_<theme>.png    the same moment without the HUD
    empty_<theme>.png    the field before the first monster (gates must already read)
    shape_*.png          the five road shapes on one battlefield
    detail_*.png         close views of the plaza junction, every gate, every T-join
    switch_NNN.png       one real stage change, plus switch.gif and switch_strip.jpg
    sheet_*.jpg          contact sheets (the 320 px one is the thumbnail test)
    biome-report.json    actor positions, build time and draw cost
    contrast.json        colour distance between every actor and the ground under it
"""
import argparse
import contextlib
import json
import os
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from godot_env import ROOT, GODOT, xvfb

BIOME_FIELDS = ["calm_lake", "tidal_flats", "maelstrom_sea",
                "kiln_yard", "sulfur_springs", "volcano_crater",
                "spring_grove", "misty_cedar", "worldtree_roots",
                "gravel_hills", "broken_wall", "rift_chasm",
                "first_snow_hills", "drift_ice_sea", "polar_night"]
SHAPES = ["spiral", "pinwheel", "blades", "coil", "fork"]
# Roster order (biome by biome, rank rising); read from the game table so it never drifts.
THEME_ORDER = __import__("re").findall(r'\{"id": "([a-z_]+)", "ko": "[^"]+", "main_body"', (ROOT / "core/roster.gd").read_text())


GPU_LOCK = ROOT / "build/casual-overhaul/gpu.lock"


def gpu_env() -> dict | None:
    """The login session's GPU X server's environment when it answers, else None."""
    auth = Path(f"/run/user/{os.getuid()}/gdm/Xauthority")
    if os.environ.get("REVIEW_DISPLAY", "auto") != "xvfb" and auth.exists():
        env = dict(os.environ, DISPLAY=":1", XAUTHORITY=str(auth), STELLARDEFENSE_NO_SAVE="1")
        probe = subprocess.run(["xdpyinfo", "-queryExtensions"], env=env, capture_output=True, text=True)
        if probe.returncode == 0 and "NV-GLX" in probe.stdout:
            return env
    return None


def gpu_display(res: str, base: int):
    """The login session's GPU X server when it is there, else a software Xvfb."""
    env = gpu_env()
    return contextlib.nullcontext(env) if env is not None else xvfb(base, res)


def locked(command: list, env: dict) -> list:
    """GPU runs wait for the shared GPU lock (one capture on the display at a time)."""
    if env.get("DISPLAY") == ":1":
        GPU_LOCK.parent.mkdir(parents=True, exist_ok=True)
        return ["flock", str(GPU_LOCK), *command]
    return command


def sheet(paths, labels, columns, cell_w, out, label_h=0):
    """Grid of pictures scaled to `cell_w`; `label_h` > 0 writes the label under each."""
    shots = [Image.open(p).convert("RGB") for p in paths]
    if not shots:
        return
    cell_h = round(cell_w * shots[0].height / shots[0].width)
    rows = (len(shots) + columns - 1) // columns
    gap = 4
    canvas = Image.new("RGB", (columns * cell_w + (columns - 1) * gap, rows * (cell_h + label_h) + (rows - 1) * gap), (8, 12, 16))
    draw = ImageDraw.Draw(canvas)
    for n, shot in enumerate(shots):
        x = n % columns * (cell_w + gap)
        y = n // columns * (cell_h + label_h + gap)
        canvas.paste(shot.resize((cell_w, cell_h), Image.LANCZOS), (x, y))
        if label_h:
            draw.text((x + 4, y + cell_h + 2), labels[n], fill=(214, 222, 226))
    canvas.save(out, quality=93)


def lab(rgb):
    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(v) for v in rgb)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)), y


def mean_colour(image, box):
    x0, y0, x1, y1 = (int(round(v)) for v in box)
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(image.width, max(x0 + 1, x1)), min(image.height, max(y0 + 1, y1))
    pixels = list(image.crop((x0, y0, x1, y1)).getdata())
    count = max(1, len(pixels))
    return tuple(sum(p[c] for p in pixels) / count for c in range(3))


def contrast(out: Path, fields: dict, picture_width: float = 0.0) -> dict:
    """Colour distance (CIE76) and luminance ratio between each actor's body and the ground
    it stands on. Monsters are compared against the same pixels of the empty field; heroes
    stand in both pictures, so their ground is the strip beside their feet."""
    result = {}
    for label, field in fields.items():
        world_path = out / f"world_{label}.png"
        empty_path = out / f"empty_{label}.png"
        if not world_path.exists() or not empty_path.exists():
            continue
        world = Image.open(world_path).convert("RGB")
        empty = Image.open(empty_path).convert("RGB")
        # Actor and floor coordinates are reported in the 1280x800 logical picture; a
        # 1000x625 film is that picture scaled, so every sample scales with the PNG.
        scale = world.width / picture_width if picture_width else 1.0
        rows = []
        for actor in field["actors"]:
            fx, fy = (v * scale for v in actor["foot"])
            hx, hy = (v * scale for v in actor["head"])
            tall = max(6.0, fy - hy)
            if not (20 < fx < world.width - 20 and 20 < hy and fy < world.height - 8):
                continue
            body_box = (fx - tall * 0.16, hy + tall * 0.25, fx + tall * 0.16, fy - tall * 0.18)
            body = mean_colour(world, body_box)
            if actor["kind"] == "monster":
                ground = mean_colour(empty, body_box)
            else:
                left = mean_colour(world, (fx - tall * 0.75, fy - tall * 0.10, fx - tall * 0.42, fy + tall * 0.10))
                right = mean_colour(world, (fx + tall * 0.42, fy - tall * 0.10, fx + tall * 0.75, fy + tall * 0.10))
                ground = tuple((a + b) / 2 for a, b in zip(left, right))
            lb, gb = lab(body), lab(ground)
            delta = sum((a - b) ** 2 for a, b in zip(lb[:3], gb[:3])) ** 0.5
            ratio = (max(lb[3], gb[3]) + 0.05) / (min(lb[3], gb[3]) + 0.05)
            rows.append({"kind": actor["kind"], "id": actor["id"], "dE": round(delta, 1), "ratio": round(ratio, 2),
                         "ground_L": round(gb[0], 1), "body_L": round(lb[0], 1)})
        # Lightness of the bare floor and the bare road, sampled where nothing stands.
        # The value is the lightness of the mean luminance (what effects add their light to);
        # the 90th percentile shows how bright the brightest patches of the floor get.
        for key, name in [("floor_points", "floor_L"), ("road_points", "road_L")]:
            samples = [lab(mean_colour(empty, (x - 3, y - 3, x + 4, y + 4))) for x, y in ((px * scale, py * scale) for px, py in field.get(key, []))
                       if 8 < x < empty.width - 8 and 8 < y < empty.height - 8]
            if samples:
                mean_y = sum(sample[3] for sample in samples) / len(samples)
                lightness = sorted(sample[0] for sample in samples)
                result.setdefault(label, {})[name] = round(116.0 * mean_y ** (1 / 3) - 16.0, 1)
                result[label][name + "_p90"] = round(lightness[int(len(lightness) * 0.9)], 1)
        for key in ["baked_floor_l", "wash"]:
            if key in field:
                result.setdefault(label, {})[key] = round(field[key], 2)
        for kind in ["hero", "monster"]:
            values = sorted(r["dE"] for r in rows if r["kind"] == kind)
            if not values:
                continue
            worst = min((r for r in rows if r["kind"] == kind), key=lambda r: r["dE"])
            result.setdefault(label, {})[kind] = {"median_dE": values[len(values) // 2], "min_dE": values[0],
                                                   "worst": worst["id"], "count": len(values),
                                                   "ground_L": round(sum(r["ground_L"] for r in rows if r["kind"] == kind) / len(values), 1)}
        result.setdefault(label, {})["actors"] = rows
    return result


def biome_review(args) -> None:
    summary = {"renderer": "gl_compatibility", "device_fps_measured": False, "resolutions": {}}
    for index, resolution in enumerate(args.res or ["1280x800", "1000x625"]):
        out = args.out_root / resolution
        out.mkdir(parents=True, exist_ok=True)
        extra = ["--biome-only", "--film", resolution]
        for key in ["sets", "themes", "shape_theme", "detail_themes", "switch_from", "switch_to", "vfx_themes", "locale"]:
            value = getattr(args, key)
            if value:
                extra += ["--" + key.replace("_", "-"), value]
        log_path = out / "biome-render.log"
        if not args.sheets_only:
            with gpu_display(resolution, 133 + index) as env:
                with log_path.open("w") as stream:
                    result = subprocess.run(
                        locked([str(GODOT), "--path", str(ROOT), "--resolution", "96x60", "--disable-vsync",
                                "res://tests/arena_visual_preview.tscn", "--", "--out", str(out), *extra], env),
                        env=env, stdout=stream, stderr=subprocess.STDOUT, text=True, timeout=1800)
            log = log_path.read_text()
            # An audio stream still held when the process quits is reported as an error line
            # at exit; it is not a rendering or script failure.
            errors = [line for line in log.splitlines() if "ERROR:" in line and "still in use at exit" not in line]
            if result.returncode or errors or "!! " in log:
                print("\n".join(log.splitlines()[-80:]))
                sys.exit(1)
        report = json.loads((out / "biome-report.json").read_text())
        fields = list(report["fields"].keys())
        # Rows are ranks, columns are biomes when the default fifteen were shot; the full
        # roster runs ten to a row (one biome per two rows, rank rising left to right).
        order = fields
        columns = 5
        if set(fields) == set(BIOME_FIELDS):
            order = [BIOME_FIELDS[b * 3 + r] for r in range(3) for b in range(5)]
        elif len(fields) == len(THEME_ORDER):
            order = THEME_ORDER
            columns = 10
        elif fields:
            order = [name for name in THEME_ORDER if name in fields]
        if order:
            paths = [out / f"screen_{name}.png" for name in order]
            sheet(paths, order, columns, 320, out / "sheet_fields_320.jpg")
            sheet(paths, order, columns, 640, out / "sheet_fields_640.jpg", 16)
            sheet([out / f"world_{name}.png" for name in order], order, columns, 640, out / "sheet_fields_world.jpg", 16)
            sheet([out / f"empty_{name}.png" for name in order], order, columns, 640, out / "sheet_fields_empty.jpg", 16)
        shapes = sorted(out.glob("world_shape_*.png"), key=lambda p: SHAPES.index(p.stem.rsplit("_", 1)[1]))
        if shapes:
            sheet(shapes, [p.stem for p in shapes], 3, 640, out / "sheet_shapes_world.jpg", 16)
            sheet([p.with_name(p.name.replace("world_", "screen_")) for p in shapes], [p.stem for p in shapes], 5, 320, out / "sheet_shapes_320.jpg")
            sheet([p.with_name(p.name.replace("world_", "empty_")) for p in shapes], [p.stem for p in shapes], 3, 640, out / "sheet_shapes_empty.jpg", 16)
        details = {}
        for name in report["detail"]:
            details.setdefault(name.split("_plaza")[0].split("_gate")[0].split("_join")[0], []).append(name)
        for group, names in details.items():
            sheet([out / f"{name}.png" for name in names], [name.replace("detail_", "") for name in names], 3, 640, out / f"sheet_{group}.jpg", 16)
        frames = sorted(out.glob("ko_switch_[0-9][0-9][0-9].png")) or sorted(out.glob("switch_[0-9][0-9][0-9].png"))
        if frames:
            previews = []
            for path in frames:
                preview = Image.open(path).convert("RGB")
                preview.thumbnail((640, 400))
                previews.append(preview.quantize(colors=160, method=Image.Quantize.FASTOCTREE))
            previews[0].save(out / "switch.gif", save_all=True, append_images=previews[1:], duration=100, loop=0, optimize=False)
            step = max(1, len(frames) // 15)
            sheet(frames[::step][:15], [p.stem for p in frames[::step][:15]], 5, 512, out / "switch_strip.jpg", 16)
        vfx = sorted(out.glob("vfx_*_volley.png"))
        for volley in vfx:
            name = volley.stem[len("vfx_"):-len("_volley")]
            shots = [volley] + [out / f"vfx_{name}_{skill}_{n}.png" for skill in ["blast", "freeze", "ward"] for n in [1, 3]]
            sheet([p for p in shots if p.exists()], [p.stem for p in shots if p.exists()], 4, 640, out / f"sheet_vfx_{name}.jpg", 16)
        measured = contrast(out, report["fields"], float(report["picture"][0]))
        (out / "contrast.json").write_text(json.dumps(measured, indent=1) + "\n")
        if args.before:
            before = args.before / resolution
            pairs, labels = [], []
            for name in order:
                if (before / f"screen_{name}.png").exists():
                    pairs += [before / f"screen_{name}.png", out / f"screen_{name}.png"]
                    labels += [f"before {name}", f"after {name}"]
            if pairs:
                sheet(pairs, labels, 6, 426, out / "compare_fields.jpg", 16)
        summary["resolutions"][resolution] = {
            "checks": report["checks"], "failures": report["failures"], "picture": report["picture"],
            "screenshots": len(list(out.glob("*.png"))), "timing": report["timing"], "switch": report["switch"],
            "contrast": {name: {kind: row[kind] for kind in ["hero", "monster", "floor_L", "floor_L_p90", "road_L", "baked_floor_l", "wash"] if kind in row} for name, row in measured.items()},
        }
        print(f"{resolution}: {summary['resolutions'][resolution]['screenshots']} screenshots, {report['checks']} checks, {report['failures']} failures")
        for name, row in measured.items():
            hero, monster = row.get("hero", {}), row.get("monster", {})
            print(f"  {name:18s} floor L {row.get('floor_L', 0):5.1f} road L {row.get('road_L', 0):5.1f} wash {row.get('wash', 0):.2f}"
                  f" | hero dE median {hero.get('median_dE', 0):5.1f} min {hero.get('min_dE', 0):5.1f} ({hero.get('worst', '')})"
                  f" | monster dE median {monster.get('median_dE', 0):5.1f} min {monster.get('min_dE', 0):5.1f} ({monster.get('worst', '')})")
        # The stage rule (game/3d/arena_biome.gd): floor lightness within 40..66, and the
        # table the effects hint is derived from must match what was just measured.
        floors = {name: row["floor_L"] for name, row in measured.items() if "floor_L" in row and not name.startswith("shape_")}
        outside = {name: value for name, value in floors.items() if not 40.0 <= value <= 66.0}
        drifted = {name: (measured[name].get("baked_floor_l", -1.0), value) for name, value in floors.items()
                   if abs(measured[name].get("baked_floor_l", -1.0) - value) > 5.0}
        if outside:
            print("  !! floor lightness outside 40..66: " + ", ".join(f"{name} {value}" for name, value in outside.items()))
        if drifted:
            print("  !! FLOOR_L in game/3d/arena_biome.gd differs from the capture by more than 5 for: "
                  + ", ".join(f"{name} (table {table}, measured {value})" for name, (table, value) in drifted.items()))
        # The actor rule (2026-10-18 casual overhaul): heroes are the brightest figures on the
        # stage, a torso at least 15 L* above the road under its feet. A warning for now; it
        # becomes a failure once every field has been re-lit.
        lift = {}
        for name, row in measured.items():
            heroes = [actor["body_L"] for actor in row.get("actors", []) if actor["kind"] == "hero"]
            if heroes and "road_L" in row:
                heroes.sort()
                lift[name] = round(heroes[len(heroes) // 2] - row["road_L"], 1)
        dim = {name: value for name, value in lift.items() if value < 15.0}
        if dim:
            print("  !! hero torso less than 15 L* above the road (median body L* - road L*): "
                  + ", ".join(f"{name} {value:+.1f}" for name, value in dim.items()))
        summary.setdefault("actor_rule", {})[resolution] = lift
        if len(floors) == len(THEME_ORDER):
            rows = ["\t" + ", ".join(f'"{name}": {floors[name]:.0f}' for name in THEME_ORDER[n:n + 5]) + "," for n in range(0, len(THEME_ORDER), 5)]
            (out / "floor_l_table.txt").write_text("const FLOOR_L := {\n" + "\n".join(rows) + "\n}\n")
        summary.setdefault("stage_rule", {})[resolution] = {"outside": outside, "drifted": {name: list(pair) for name, pair in drifted.items()}}
        for name, row in report["timing"].items():
            print(f"  build {name:18s} {row['build_ms']:.1f} ms  map {row['terrain_triangles']} tris in {row['terrain_meshes']} draws"
                  f" ({row.get('scenery_instances', 0)} instances)  map frame {row.get('map_primitives', 0)} prims {row.get('map_draw_calls', 0)} draws"
                  f" gpu {row.get('map_gpu_ms', 0):.2f} ms  |  with actors {row['frame_primitives']} prims {row['frame_draw_calls']} draws gpu {row['gpu_ms']:.2f} ms")
    (args.out_root / "biome-report.json").write_text(json.dumps(summary, indent=2) + "\n")
    # The stage rule is part of the result: a floor outside the window, or a FLOOR_L table
    # that no longer matches the pictures, fails the review.
    if any(rule["outside"] or rule["drifted"] for rule in summary.get("stage_rule", {}).values()):
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--res", action="append")
    parser.add_argument("--out-root", type=Path, default=None)
    parser.add_argument("--only", choices=["polish", "help", "box", "rite", "style", "look", "circle", "hud", "road", "motion", "spiral", "biome"])
    parser.add_argument("--sets", help="biome: comma list of fields,shapes,detail,switch,timing")
    parser.add_argument("--themes", help="biome: comma list of theme ids for the fields set, or 'all'")
    parser.add_argument("--shape-theme", dest="shape_theme")
    parser.add_argument("--detail-themes", dest="detail_themes")
    parser.add_argument("--switch-from", dest="switch_from")
    parser.add_argument("--switch-to", dest="switch_to")
    parser.add_argument("--vfx-themes", dest="vfx_themes", help="biome: theme ids for the vfx set (effects over each ground)")
    parser.add_argument("--locale")
    parser.add_argument("--before", type=Path, help="biome: an earlier out-root to pair against in compare_fields.jpg")
    parser.add_argument("--sheets-only", action="store_true", help="biome: rebuild sheets and measurements from existing captures")
    args = parser.parse_args()
    if args.only == "rite":
        args.only = "box"          # the star rite became the jewel box (2026-10-19)
    if args.only == "biome":
        args.out_root = args.out_root or ROOT / "build/biomes/review"
        biome_review(args)
        return
    args.out_root = args.out_root or ROOT / "build/arena-visual"
    report = {"renderer": "gl_compatibility", "device_fps_measured": False, "resolutions": {}}
    failed = False
    for index, resolution in enumerate(args.res or ["1280x800", "1000x625"]):
        out = args.out_root / resolution
        out.mkdir(parents=True, exist_ok=True)
        with gpu_display(resolution, 113 + index) as env:
            extra = [f"--{args.only}-only"] if args.only else []
            # On the GPU display the game draws into an off-screen film of the review size
            # behind a tiny window; on Xvfb the window itself is the picture.
            window = ["--resolution", "96x60", "--disable-vsync"] if env.get("DISPLAY") == ":1" else ["--resolution", resolution]
            film = ["--film", resolution] if env.get("DISPLAY") == ":1" else []
            live_log = out / (f"{args.only}-render.log" if args.only else "render.log")
            with live_log.open("w") as stream:
                result = subprocess.run(
                    locked([str(GODOT), "--path", str(ROOT), *window,
                            "res://tests/arena_visual_preview.tscn", "--", "--out", str(out), *film, *extra], env),
                    env=env, stdout=stream, stderr=subprocess.STDOUT, text=True, timeout=1800,
                )
        log = live_log.read_text()
        bad = [line for line in log.splitlines() if "ERROR:" in line and "still in use at exit" not in line]
        flagged = [line for line in log.splitlines() if line.startswith("!! ")]
        report_path = out / (f"{args.only}-report.json" if args.only else "report.json")
        if bad or not report_path.exists():
            # The run itself broke (no report): show the end of its log and stop.
            print("\n".join(log.splitlines()[-100:]))
            sys.exit(1)
        if result.returncode or flagged:
            # Checks failed but the pictures are there: say which, keep going (sheets, next size).
            failed = True
            counts: dict = {}
            for line in flagged:
                key = line.split(": ")[0] if "readable text size" in line else line
                counts[key] = counts.get(key, 0) + 1
            print(f"{resolution}: {len(flagged)} failed checks")
            for key, count in sorted(counts.items(), key=lambda item: -item[1])[:12]:
                print(f"   {count:4d} x {key}")
        for locale in ["ko", "en"]:
            names = ["spiral_field", "speed_1", "speed_2", "speed_3", "ward_cast", "ward_4s", "ward_6s", "uses_210", "uses_200", "boss_warn_04", "boss_warn_01", "boss_spawn_03", "boss_bar", "road_field_six", "road_center_guardians", "road_pass_10", "road_pass_20", "road_pass_31", "road_entry_00", "road_entry_01", "road_entry_02", "road_entry_03", "circle", "circle_edge_00", "circle_edge_02", "circle_edge_04", "circle_edge_06", "joystick_start_00", "joystick_drag_00", "joystick_drag_01", "joystick_drag_02", "joystick_drag_03", "joystick_released", "reference", "edge_-1_0", "edge_1_0", "edge_0_-1", "edge_0_1", "edge_1_1", "biome_00", "biome_20", "biome_30", "biome_40", "stage_card", "box_free", "box_spent", "box_result", "box_paid", "summon_new", "field_six", "help", "growth_result",
                     "growth_maxed", "talents", "reserves_selected", "boss", "victory",
                     "defeat", "title", "title_resume", "collection_water", "collection_fire", "collection_elec", "menu_menu", "menu_rules", "menu_box", "menu_elements"]
            names = [name for name in names if (out / f"{locale}_{name}.png").exists()]
            contact = Image.new("RGB", (1280, 267 * max(1, (len(names) + 2) // 3)), (10, 20, 29))
            for n, name in enumerate(names):
                if not (out / f"{locale}_{name}.png").exists():
                    continue
                shot = Image.open(out / f"{locale}_{name}.png").convert("RGB")
                shot.thumbnail((426, 267))
                contact.paste(shot, (n % 3 * 426, n // 3 * 267))
            contact.save(out / f"{locale}_contact.jpg", quality=94)
            for motion in ["move", "limne_move", "skill_blast", "skill_freeze", "skill_ward", "box_open", "follow", "echo_attack", "lane", "long_walk", "road_pass", "motion", "boss_warn", "boss_spawn"]:
                files = sorted(out.glob(f"{locale}_{motion}_[0-9][0-9].png"))
                frames = []
                for path in files:
                    preview = Image.open(path).convert("RGB")
                    preview.thumbnail((640, 400))
                    frames.append(preview.quantize(colors=128, method=Image.Quantize.FASTOCTREE))
                if frames:
                    frames[0].save(out / f"{locale}_{motion}.gif", save_all=True,
                                   append_images=frames[1:], duration={"road_pass": 300, "motion": 67, "boss_warn": 700}.get(motion, 100),
                                   loop=0, optimize=False)
        checks = json.loads(report_path.read_text())
        if "resolution" in checks:
            checks["layout_resolution"] = checks.pop("resolution")
        reference = {"circle": "ko_circle.png", "road": "ko_road_field_six.png", "motion": "ko_motion_start.png", "spiral": "ko_spiral_field.png"}.get(args.only, "ko_box_free.png")
        # Modes that never open the box (help) have no such picture: any capture gives the size.
        reference_path = out / reference
        if not reference_path.exists():
            reference_path = sorted(out.glob("ko_*.png"))[0]
        checks["window_resolution"] = list(Image.open(reference_path).size)
        checks["screenshots"] = len(list(out.glob("*.png")))
        checks["render_errors"] = 0
        report["resolutions"][resolution] = checks
        print(f"{resolution}: {checks['screenshots']} screenshots, {checks['checks']} checks, {checks.get('failures', 0)} failures")
    (args.out_root / (f"{args.only}-report.json" if args.only else "report.json")).write_text(json.dumps(report, indent=2) + "\n")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
