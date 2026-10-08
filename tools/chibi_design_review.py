from pathlib import Path
import argparse
import subprocess

from PIL import Image, ImageDraw

from godot_env import GODOT, ROOT, xvfb


def motion(folder, kind):
    frames = [Image.open(folder / f"{kind}_{index:02d}.png").convert("RGB") for index in range(16)]
    frames[0].save(folder / f"{kind}.gif", save_all=True, append_images=frames[1:], duration=160, loop=0)
    for group in range(5):
        sheet = Image.new("RGB", (1280, 16 * 172), "#101a22")
        drawing = ImageDraw.Draw(sheet)
        for index, frame in enumerate(frames):
            scale = frame.width / 1280
            top = (48 + group * 148) * scale
            strip = frame.crop((0, round(top), frame.width, round(top + 148 * scale)))
            sheet.paste(strip.resize((1280, 148), Image.Resampling.NEAREST), (0, index * 172))
            drawing.text((8, index * 172 + 151), f"{kind} {index:02d}", fill="#f6c445")
        sheet.save(folder / f"{kind}_motion_row_{group}.png")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--res", action="append")
    parser.add_argument("--out", default=str(ROOT / "build/chibi-review"))
    parser.add_argument("--reuse", action="store_true")
    options = parser.parse_args()
    output = Path(options.out)
    output.mkdir(parents=True, exist_ok=True)
    with xvfb(138, "1280x800") as environment:
        for resolution in options.res or ["1280x800", "1000x625"]:
            folder = output / resolution
            folder.mkdir(parents=True, exist_ok=True)
            if not options.reuse:
                result = subprocess.run([str(GODOT), "--path", str(ROOT), "--resolution", resolution,
                                         "res://tests/chibi_preview.tscn", "--", "--out", str(folder)],
                                        env=environment, capture_output=True, text=True, timeout=240)
                log = result.stdout + result.stderr
                (output / f"{resolution}.log").write_text(log)
                print(log, flush=True)
                if result.returncode or "ERROR:" in log or "Chibi visual preview complete:" not in log:
                    raise SystemExit(1)
            for kind in ["heroes", "monsters"]:
                motion(folder, kind)


if __name__ == "__main__":
    main()
