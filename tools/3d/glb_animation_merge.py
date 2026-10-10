#!/usr/bin/env python3
"""Replace only the animations of a reviewed runtime GLB with freshly exported clips.

The reviewed GLB keeps every mesh, skin, material and texture byte; the fresh
export (same node layout) contributes its animation samplers. Used by
tools/3d/author_native_motion.py (49 heroes) and tools/3d/style_animate_limne.py.
"""
import json, struct

def _read_glb(payload: bytes):
    length = struct.unpack_from('<I', payload, 12)[0]
    gltf = json.loads(payload[20:20 + length])
    offset = 20 + length
    bin_length, _ = struct.unpack_from('<II', payload, offset)
    return gltf, bytearray(payload[offset + 8:offset + 8 + bin_length])


def _write_glb(gltf: dict, binary: bytes) -> bytes:
    text = json.dumps(gltf, separators=(',', ':')).encode('utf-8')
    text += b' ' * (-len(text) % 4)
    binary = bytes(binary) + b'\0' * (-len(binary) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    return (struct.pack('<III', 0x46546C67, 2, total) + struct.pack('<II', len(text), 0x4E4F534A) + text
            + struct.pack('<II', len(binary), 0x004E4942) + binary)


def merge_animations(base_payload: bytes, fresh_payload: bytes) -> bytes:
    base, base_bin = _read_glb(base_payload)
    fresh, fresh_bin = _read_glb(fresh_payload)
    base_names = [n.get('name') for n in base.get('nodes', [])]
    fresh_names = [n.get('name') for n in fresh.get('nodes', [])]
    if base_names != fresh_names:
        raise ValueError('node layout changed; refusing to merge animations')
    # Accessors/buffer views used by anything except the old animations stay.
    used_accessors = set()
    for mesh in base.get('meshes', []):
        for prim in mesh.get('primitives', []):
            used_accessors.update(prim.get('attributes', {}).values())
            if 'indices' in prim: used_accessors.add(prim['indices'])
            for target in prim.get('targets', []): used_accessors.update(target.values())
    for skin in base.get('skins', []):
        if 'inverseBindMatrices' in skin: used_accessors.add(skin['inverseBindMatrices'])
    keep_accessors = sorted(used_accessors)
    accessor_map = {old: new for new, old in enumerate(keep_accessors)}
    used_views = set()
    for i in keep_accessors:
        acc = base['accessors'][i]
        if 'bufferView' in acc: used_views.add(acc['bufferView'])
    for image in base.get('images', []):
        if 'bufferView' in image: used_views.add(image['bufferView'])
    keep_views = sorted(used_views)
    view_map = {old: new for new, old in enumerate(keep_views)}
    out_bin = bytearray()
    views = []
    for old in keep_views:
        view = dict(base['bufferViews'][old])
        start = view.get('byteOffset', 0); size = view['byteLength']
        out_bin += b'\0' * (-len(out_bin) % 4)
        view['byteOffset'] = len(out_bin); view['buffer'] = 0
        out_bin += base_bin[start:start + size]
        views.append(view)
    accessors = []
    for old in keep_accessors:
        acc = dict(base['accessors'][old])
        if 'bufferView' in acc: acc['bufferView'] = view_map[acc['bufferView']]
        accessors.append(acc)
    for mesh in base.get('meshes', []):
        for prim in mesh.get('primitives', []):
            prim['attributes'] = {k: accessor_map[v] for k, v in prim['attributes'].items()}
            if 'indices' in prim: prim['indices'] = accessor_map[prim['indices']]
            prim['targets'] = [{k: accessor_map[v] for k, v in t.items()} for t in prim.get('targets', [])] or prim.get('targets')
            if prim.get('targets') is None: prim.pop('targets', None)
    for skin in base.get('skins', []):
        if 'inverseBindMatrices' in skin: skin['inverseBindMatrices'] = accessor_map[skin['inverseBindMatrices']]
    for image in base.get('images', []):
        if 'bufferView' in image: image['bufferView'] = view_map[image['bufferView']]
    # Append the fresh animation data.
    fresh_accessor_map = {}
    def import_accessor(index: int) -> int:
        if index in fresh_accessor_map: return fresh_accessor_map[index]
        acc = dict(fresh['accessors'][index])
        view = dict(fresh['bufferViews'][acc['bufferView']])
        start = view.get('byteOffset', 0); size = view['byteLength']
        out_bin.extend(b'\0' * (-len(out_bin) % 4))
        view['byteOffset'] = len(out_bin); view['buffer'] = 0
        out_bin.extend(fresh_bin[start:start + size])
        views.append(view)
        acc['bufferView'] = len(views) - 1
        accessors.append(acc)
        fresh_accessor_map[index] = len(accessors) - 1
        return fresh_accessor_map[index]
    animations = []
    for anim in fresh.get('animations', []):
        samplers = []
        for sampler in anim['samplers']:
            samplers.append({'input': import_accessor(sampler['input']), 'output': import_accessor(sampler['output']),
                             'interpolation': sampler.get('interpolation', 'LINEAR')})
        channels = []
        for channel in anim['channels']:
            target = dict(channel['target'])
            channels.append({'sampler': channel['sampler'], 'target': target})
        animations.append({'name': anim['name'], 'samplers': samplers, 'channels': channels})
    base['bufferViews'] = views
    base['accessors'] = accessors
    base['animations'] = animations
    base['buffers'] = [{'byteLength': len(out_bin) + (-len(out_bin) % 4)}]
    return _write_glb(base, out_bin)


