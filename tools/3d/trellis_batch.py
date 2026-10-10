#!/usr/bin/env python3
"""Generate raw native character GLBs with an existing local ComfyUI server.

Visual source selection and finishing belong to the graphic design manager.
This runner copies approved inputs, records exact prompts, and resumes raw jobs.
It never edits runtime game assets or downloads/installs model weights.
"""
from __future__ import annotations

import argparse
import copy
import fcntl
import hashlib
import json
import re
import shutil
import struct
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def sha(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def save(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix+'.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')
    temporary.replace(path)


def api(url: str, path: str, body=None):
    payload = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url.rstrip('/')+path, data=payload,
                                     headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f'ComfyUI {path}: {error.code} {error.read().decode()[:1600]}') from error


def valid_glb(path: Path) -> bool:
    if not path.is_file(): return False
    with path.open('rb') as stream:
        head = stream.read(12)
    return len(head) == 12 and struct.unpack('<4sII', head) == (b'glTF', 2, path.stat().st_size)


def glb_names(value):
    if isinstance(value, str) and value.lower().endswith('.glb'):
        yield value
    elif isinstance(value, list):
        for child in value: yield from glb_names(child)
    elif isinstance(value, dict):
        if str(value.get('filename', '')).lower().endswith('.glb'):
            yield str(Path(value.get('subfolder', ''))/value['filename'])
        else:
            for child in value.values(): yield from glb_names(child)


def prepare(source: dict, template: dict, inputs: Path):
    identity = source['id']
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,63}', identity):
        raise ValueError('Invalid roster identity')
    image = (ROOT/Path(source['image'])).resolve()
    if not image.is_file() or image.suffix.lower() != '.png':
        raise ValueError(f'Missing source PNG: {image}')
    image_sha = sha(image)
    if source.get('image_sha256') and source['image_sha256'] != image_sha:
        raise ValueError(f'{identity}: reference SHA does not match the reviewed input')
    filename = f'{identity}_{image_sha[:12]}.png'
    staged = inputs/filename
    if not staged.exists() or sha(staged) != image_sha:
        shutil.copyfile(image, staged)
    workflow = copy.deepcopy(template)
    overrides = source.get('workflow_overrides', {})
    for node_id, values in overrides.items():
        if str(node_id) not in workflow or not isinstance(values, dict):
            raise ValueError(f'Unknown workflow node or invalid overrides: {node_id}')
        workflow[str(node_id)]['inputs'].update(values)
    loaders = [node for node in workflow.values() if node['class_type'] == 'LoadImage']
    outputs = [node for node in workflow.values() if node['class_type'] == 'Save3DAdvanced']
    if len(loaders) != 1 or len(outputs) != 1:
        raise ValueError('Expected one image loader and one GLB output')
    loaders[0]['inputs']['image'] = filename
    outputs[0]['inputs']['filename_prefix'] = f'{identity}_native_{image_sha[:12]}'
    recipe_sha = hashlib.sha256(json.dumps(workflow, sort_keys=True).encode()).hexdigest()
    return image, image_sha, workflow, recipe_sha


def generate(args, source: dict, template: dict, available: dict):
    identity = source['id']
    image, image_sha, workflow, recipe_sha = prepare(source, template, args.runtime/'inputs')
    missing = sorted({node['class_type'] for node in workflow.values()}-set(available))
    if missing: raise ValueError('Missing ComfyUI nodes: '+', '.join(missing))
    out = args.output/identity
    out.mkdir(parents=True, exist_ok=True)
    destination = out/'model.glb'
    provenance_path = out/'provenance.json'
    if provenance_path.exists() and valid_glb(destination):
        existing = json.loads(provenance_path.read_text())
        if existing.get('recipe_sha256') == recipe_sha and existing.get('glb_sha256') == sha(destination):
            if existing.get('source_record') != source:
                existing['source_record'] = source
                save(provenance_path, existing)
            print(f'SKIP {identity}: matching raw GLB already generated', flush=True)
            return existing
    state_path = out/'submission.json'
    previous = json.loads(state_path.read_text()) if state_path.exists() else {}
    if previous.get('recipe_sha256') != recipe_sha and previous:
        raise ValueError(f'{identity}: existing recipe differs; preserve the old raw branch and choose a new output directory')
    if previous.get('state') == 'failed' and not args.retry_failed:
        raise ValueError(f'{identity}: previous job failed; inspect history/server log before --retry-failed')
    save(out/'workflow.json', workflow)
    if args.dry_run:
        print(f'DRY {identity}: source {image.name}, workflow {recipe_sha[:12]}', flush=True)
        return {'id': identity, 'state': 'dry_run', 'recipe_sha256': recipe_sha}
    if previous.get('state') == 'submitted':
        submission = previous
        print(f'RESUME {identity}: {submission["prompt_id"]}', flush=True)
    else:
        response = api(args.url, '/prompt', {'prompt': workflow, 'client_id': 'stellardefense-native-characters'})
        if 'prompt_id' not in response:
            raise RuntimeError(f'Prompt rejected: {response}')
        submission = {'id': identity, 'state': 'submitted', 'prompt_id': response['prompt_id'],
                      'source_sha256': image_sha, 'recipe_sha256': recipe_sha,
                      'submitted_at': time.time(), 'server': args.url}
        save(state_path, submission)
        print(f'SUBMIT {identity}: {submission["prompt_id"]}', flush=True)
    prompt_id = submission['prompt_id']
    started = time.monotonic()
    progress = 0
    while time.monotonic()-started < args.timeout:
        history = api(args.url, '/history/'+prompt_id).get(prompt_id)
        if history is not None:
            save(out/'history.json', history)
            status = history.get('status', {})
            if status.get('status_str') == 'error':
                submission['state'] = 'failed'; save(state_path, submission)
                raise RuntimeError(f'{identity}: native inference failed; inspect {out}/history.json')
            if status.get('completed'):
                candidates = list(glb_names(history.get('outputs', {})))
                output_root = (args.runtime/'outputs').resolve()
                found = None
                for name in candidates:
                    candidate = (output_root/name).resolve()
                    if candidate.is_relative_to(output_root) and valid_glb(candidate):
                        found = candidate; break
                if found is None:
                    raise RuntimeError(f'{identity}: completed prompt contains no valid GLB')
                shutil.copyfile(found, destination)
                record = {'id': identity, 'state': 'raw_generated_needs_design_review',
                          'image': str(image.relative_to(ROOT)) if image.is_relative_to(ROOT) else str(image),
                          'source_sha256': image_sha, 'recipe_sha256': recipe_sha,
                          'prompt_id': prompt_id, 'generated_at': time.time(),
                          'glb_bytes': destination.stat().st_size, 'glb_sha256': sha(destination),
                          'raw_glb': str(destination), 'identity_reference': source.get('identity', '')}
                record['source_record'] = source
                save(provenance_path, record)
                submission['state'] = 'completed'; save(state_path, submission)
                print(f'DONE {identity}: {destination.stat().st_size} bytes -> {destination}', flush=True)
                return record
        elapsed = int(time.monotonic()-started)
        if elapsed >= progress:
            print(f'WAIT {identity}: {elapsed}s', flush=True)
            progress = elapsed+60
        time.sleep(args.poll)
    raise TimeoutError(f'{identity}: {args.timeout}s elapsed; submission retained for resume')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sources', type=Path, required=True)
    parser.add_argument('--template', type=Path, default=ROOT/'tools/3d/limne_trellis.json')
    parser.add_argument('--url', default='http://127.0.0.1:8208')
    parser.add_argument('--runtime', type=Path, default=ROOT/'build/character-3d/runtime')
    parser.add_argument('--output', type=Path, default=ROOT/'build/character-3d/raw')
    parser.add_argument('--ids', default='')
    parser.add_argument('--poll', type=float, default=5)
    parser.add_argument('--timeout', type=int, default=1800)
    parser.add_argument('--retry-failed', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--follow', action='store_true', help='Consume new approved references as their manifest grows')
    parser.add_argument('--expected-count', type=int, default=0, help='Required terminal roster count with --follow')
    parser.add_argument('--idle-timeout', type=int, default=1800, help='Stop if no new approved reference arrives')
    args = parser.parse_args()
    if args.follow and (args.expected_count <= 0 or args.dry_run):
        parser.error('--follow requires positive --expected-count and actual generation')
    args.runtime = args.runtime.resolve(); args.output = args.output.resolve()
    for directory in [args.runtime/'inputs', args.runtime/'outputs', args.output]:
        directory.mkdir(parents=True, exist_ok=True)
    with (args.runtime/'batch.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        available = api(args.url, '/object_info')
        template = json.loads(args.template.read_text())
        wanted = set(args.ids.split(',')) if args.ids else None
        results = {}
        failures = 0
        last_new = time.monotonic()
        next_notice = 0
        while True:
            sources = json.loads(args.sources.read_text())
            identities = [source['id'] for source in sources]
            if len(set(identities)) != len(identities):
                raise ValueError('Duplicate character identities in source manifest')
            if wanted is not None:
                sources = [source for source in sources if source['id'] in wanted]
            if not args.follow and not sources:
                raise ValueError('No selected character references')
            for source in sources:
                identity = source['id']
                if identity in results: continue
                try:
                    results[identity] = generate(args, source, template, available)
                except Exception as error:
                    failures += 1
                    results[identity] = {'id': identity, 'state': 'error', 'error': str(error)}
                    print(f'ERROR {identity}: {error}', flush=True)
                last_new = time.monotonic()
                save(args.runtime/'batch_status.json', results)
            if not args.follow or len(results) >= args.expected_count: break
            idle = time.monotonic()-last_new
            if idle >= args.idle_timeout:
                raise TimeoutError(f'Waiting for approved references: {len(results)}/{args.expected_count}; resume from the recorded GLBs')
            if time.monotonic() >= next_notice:
                print(f'REFERENCES {len(results)}/{args.expected_count}; waiting for design-reviewed inputs', flush=True)
                next_notice = time.monotonic()+60
            time.sleep(args.poll)
        print(f'BATCH {len(results)} characters, {failures} failures', flush=True)
        return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
