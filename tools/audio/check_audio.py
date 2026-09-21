#!/usr/bin/env python3
"""Check decoded delivery audio and write a reproducible provider/asset manifest."""
import hashlib
import json
from pathlib import Path
import subprocess
import numpy as np
from generate_elevenlabs import ROOT, MUSIC, SFX, source_for
from theme_music import THEME_MUSIC

def decode(path):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'f32le', '-ac', '2', '-ar', '44100', 'pipe:1'], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype='<f4').reshape(-1, 2)

def main():
    records = []
    theme_hashes = set()
    for kind, ids in [('bgm', MUSIC), ('sfx', SFX)]:
        for ident in ids:
            name = ident + ('.ogg' if kind == 'bgm' else '.wav')
            path = ROOT / 'art' / kind / name
            samples = decode(path)
            peak = float(np.max(np.abs(samples)))
            rms = float(np.sqrt(np.mean(samples ** 2)))
            assert len(samples) > 100 and .001 < peak < .99, (path, peak)
            assert rms > .0005 and np.isfinite(samples).all(), path
            if kind == 'bgm':
                assert len(samples) / 44100 > 40, path
                window = 4410
                chunk_rms = [float(np.sqrt(np.mean(samples[i:i + window] ** 2))) for i in range(0, len(samples) - window, window)]
                assert min(chunk_rms) > .0005, (path, 'silent gap')
                seam = float(np.max(np.abs(samples[-1] - samples[0])))
                assert seam < .04, (path, 'loop discontinuity', seam)
            else:
                seam = None
                assert float(np.max(np.abs(samples[0]))) < .001 and float(np.max(np.abs(samples[-1]))) < .001, (path, 'unfaded edge')
            source = source_for(ident, kind == 'bgm')
            assert path.read_bytes() == (source / name).read_bytes(), (path, 'unpublished generated asset')
            metadata = json.loads((source / (ident + '.json')).read_text())
            source_hash = hashlib.sha256((source / (ident + '.mp3')).read_bytes()).hexdigest()
            assert source_hash == metadata['source_sha256'], (path, 'source provenance mismatch')
            if ident in THEME_MUSIC:
                assert source_hash not in theme_hashes, (path, 'theme music must be unique')
                theme_hashes.add(source_hash)
                assert metadata['request']['force_instrumental'], (path, 'theme music must be instrumental')
            records.append({**metadata, 'path':str(path.relative_to(ROOT)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'seconds':round(len(samples) / 44100, 3), 'peak':round(peak, 4), 'rms':round(rms, 4), 'loop_seam':seam})
    (ROOT / 'art/audio-manifest.json').write_text(json.dumps({'provider':'ElevenLabs', 'assets':records}, ensure_ascii=False, indent=2))
    assert len(theme_hashes) == len(THEME_MUSIC)
    print(f'PASS: {len(MUSIC)} BGM loops ({len(theme_hashes)} unique theme tracks), {len(SFX)} effects; all decoded, non-silent, unclipped, source-matched.')

if __name__ == '__main__':
    main()
