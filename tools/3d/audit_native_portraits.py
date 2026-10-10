#!/usr/bin/env python3
"""Read final portrait alpha bounds and pin them to reviewed native GLB hashes."""
import argparse, hashlib, json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('--ids', required=True)
p.add_argument('--output', required=True)
a = p.parse_args()
result = {}
for cid in a.ids.split(','):
    if cid == 'limne':
        raise ValueError('Accepted Limne portraits are protected')
    folder = ROOT / 'art/models/portraits' / cid
    files = sorted(folder.glob('*.png'))
    if len(files) != 11:
        raise ValueError(cid + ': expected ten grades and the existing awakened rank')
    rows = []
    for path in files:
        im = Image.open(path).convert('RGBA')
        box = im.getchannel('A').getbbox()
        if box is None:
            raise ValueError(str(path) + ': empty portrait')
        margin = min(box[0], box[1], im.width - box[2], im.height - box[3])
        rows.append({'path': str(path.relative_to(ROOT)),
                     'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                     'alpha_margin': margin})
    result[cid] = {'portrait_count': len(rows),
                   'minimum_margin': min(v['alpha_margin'] for v in rows),
                   'edge_failures': sum(v['alpha_margin'] < 4 for v in rows),
                   'glb_sha256': hashlib.sha256((ROOT / 'art/models' / cid / (cid + '.glb')).read_bytes()).hexdigest(),
                   'portraits': rows}
out = Path(a.output)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(result, indent=2) + '\n')
print({cid: {k: v for k, v in row.items() if k != 'portraits'} for cid, row in result.items()})
if any(row['edge_failures'] for row in result.values()):
    raise SystemExit(1)
