#!/usr/bin/env python3
"""Assemble generated pixel art into labeled review sheets with FFmpeg."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art/concepts/last_refuge_v3'
OUT = ROOT / 'art/concepts/last_refuge_v3_pixel'
ELEMENTS = ['water', 'fire', 'ice', 'elec', 'none']


def run(args):
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-threads', '1',
                    '-filter_complex_threads', '1', '-filter_threads', '1', *args], check=True)


def main():
    chars = json.loads((SOURCE / 'characters.json').read_text())
    assert len(chars) == 50 and len({c['id'] for c in chars}) == 50
    missing = [c['id'] for c in chars if not (OUT / (c['id'] + '.png')).exists()]
    assert not missing, f'Missing images: {missing}'
    font = ROOT / 'core/fonts/DinoKR.ttf'
    with tempfile.TemporaryDirectory(prefix='pixel-review-') as tmp:
        temp = Path(tmp)
        for c in chars:
            ident = c['id']
            source = SOURCE / f'{ident}.png'
            target = OUT / f'{ident}.png'
            meta_path = OUT / f'{ident}.json'
            meta = json.loads(meta_path.read_text())
            meta['source_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
            meta['output_sha256'] = hashlib.sha256(target.read_bytes()).hexdigest()
            meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + '\n')
            label = temp / f'{ident}.txt'
            # Padding works around this FFmpeg build clipping trailing glyphs
            # on mixed Hangul/Latin lines; it does not affect visible text.
            label.write_text(f"{c['tier']:02}  {c['name']} / {ident}" + ' '*32 + '\n' + f"{c['element'].upper()}  /  {c['weapon']}" + ' '*32)
            vf = ("scale=384:384:force_original_aspect_ratio=decrease:flags=neighbor,"
                  "pad=384:448:(ow-iw)/2:0:color=0xeee9df,setsar=1,"
                  f"drawtext=fontfile='{font}':textfile='{label}':fontsize=17:fontcolor=0x243c3b:x=12:y=394:line_spacing=5")
            run(['-i', str(target), '-vf', vf, '-frames:v', '1', '-threads', '1', str(temp / f'{ident}.png')])

        def sheet(items, destination, header=None):
            rows = []
            for start in range(0, len(items), 5):
                row = temp / f'{destination.stem}-{start}.png'
                args = []
                for c in items[start:start+5]:
                    args += ['-i', str(temp / (c['id'] + '.png'))]
                run([*args, '-filter_complex', 'hstack=inputs=5', '-frames:v', '1', '-threads', '1', str(row)])
                rows.append(row)
            args = []
            for row in rows:
                args += ['-i', str(row)]
            graph = f'vstack=inputs={len(rows)}'
            if header:
                graph += ',pad=iw:ih+64:0:64:color=0x193b3c'
                for col, name in enumerate(header):
                    graph += f",drawtext=fontfile='{font}':text='{name}':fontsize=24:fontcolor=0xf9f4e8:x={col*384+20}:y=20"
            run([*args, '-filter_complex', graph, '-frames:v', '1', '-threads', '1', str(destination)])

        ordered = sorted(chars, key=lambda c: (c['tier'], ELEMENTS.index(c['element'])))
        sheet(ordered, OUT / 'overview.png', ['WATER', 'FIRE', 'ICE', 'ELECTRIC', 'NEUTRAL'])
        for element in ELEMENTS:
            sheet(sorted([c for c in chars if c['element'] == element], key=lambda c: c['tier']), OUT / f'review_{element}.png')
    run(['-i', str(OUT / 'overview.png'), '-q:v', '2', '-frames:v', '1', str(OUT / 'overview.jpg')])
    gallery = (SOURCE / 'index.html').read_text()
    gallery = gallery.replace('50 수호자 원화', '50 수호자 픽셀 아트')
    gallery = gallery.replace('WORLD & CHARACTER ART · REV.3', '2D PIXEL ART · 50 CHARACTERS')
    gallery = gallery.replace('50명 · 개별 정면 T포즈 · 1024 × 1024 · Krea 2 Turbo', '50명 · 개별 정면 T포즈 · 2D 픽셀 아트 · built-in image_gen')
    gallery = gallery.replace('</style>', 'img{image-rendering:pixelated}.overview{display:block;padding:14px 5vw;background:#eee9df}</style>')
    gallery = gallery.replace('<nav aria-label=', '<div class="overview"><a href="overview.png">50명 전체 overview PNG</a> · <a href="../last_refuge_v3/index.html">기존 원화 비교</a></div><nav aria-label=')
    for element in ELEMENTS:
        gallery = gallery.replace(f'review_{element}.jpg', f'review_{element}.png')
    for c in chars:
        ident = c['id']
        gallery = gallery.replace(f'<a href="{ident}.json">생성 기록</a>', f'<a href="{ident}.json">생성 기록</a><a href="../last_refuge_v3/{ident}.png" target="_blank" rel="noopener">기존 원화</a>')
    (OUT / 'index.html').write_text(gallery)
    (OUT / 'characters.json').write_text(json.dumps(chars, ensure_ascii=False, indent=2) + '\n')
    (OUT / 'prompts.jsonl').write_text(''.join(json.dumps(json.loads((OUT / (c['id'] + '.json')).read_text()), ensure_ascii=False) + '\n' for c in chars))
    print('50/50 PNGs and generation records verified; overview, five element sheets, and gallery built.')


if __name__ == '__main__':
    main()
