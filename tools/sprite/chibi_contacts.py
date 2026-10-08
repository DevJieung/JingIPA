from pathlib import Path
import argparse
import math

from PIL import Image, ImageDraw, ImageFont


def contact(paths, destination, columns=5, cell=256):
    canvas = Image.new("RGB", (columns * cell, math.ceil(len(paths) / columns) * (cell + 28)), "#202831")
    drawing = ImageDraw.Draw(canvas)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16)
    for index, path in enumerate(paths):
        source = Image.open(path).convert("RGBA")
        source = source.crop(source.getbbox())
        factor = min((cell - 20) / source.width, (cell - 12) / source.height)
        source = source.resize((round(source.width * factor), round(source.height * factor)), Image.Resampling.NEAREST)
        column, row = index % columns, index // columns
        canvas.paste(source, (column * cell + (cell - source.width) // 2, row * (cell + 28) + cell - source.height), source)
        drawing.text((column * cell + 10, row * (cell + 28) + cell + 4), path.stem, font=font, fill="white")
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("destination")
    options = parser.parse_args()
    contact(sorted(Path(options.source).glob("*.png")), Path(options.destination))
