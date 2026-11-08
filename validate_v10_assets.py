"""Check generated FileMesh assets and the adult bone counting manifest."""

import json
import math
import struct
from pathlib import Path

root = Path(__file__).resolve().parent
files = list(root.glob('v10-*.mesh'))
assert len(files) == 93, len(files)  # 58 wounds + 30 regions + 4 chips + rim

for path in files:
    data = path.read_bytes()
    assert data.startswith(b'version 2.00\n'), path
    assert data[13:17] == bytes((0x0C, 0, 0x24, 0x0C)), path
    vertices, faces = struct.unpack_from('<II', data, 17)
    assert vertices == faces * 3 and faces > 0, path
    assert len(data) == 25 + vertices * 36 + faces * 12, path
    start = 25 + vertices * 36
    for index in range(0, vertices, max(1, vertices // 50)):
        values = struct.unpack_from('<9f', data, 25 + index * 36)
        assert all(math.isfinite(value) for value in values), path
    for index in range(0, faces, max(1, faces // 50)):
        triangle = struct.unpack_from('<III', data, start + index * 12)
        assert max(triangle) < vertices, path

manifest = json.loads((root / 'v10-anatomy-manifest.json').read_text())
assert manifest['bone_count'] == 206
assert manifest['bone_mesh_count'] == 208
assert len(manifest['supplemental_bones']) == 10
assert len(manifest['structures']) == 644
for name in ('RightFoot', 'LeftFoot'):
    bones = [item['name'].lower() for item in manifest['structures']
             if item['part'] == name and item['tissue'] == 'bone']
    assert len(bones) == 26, (name, len(bones))
    assert any('metatarsal' in bone for bone in bones)
for name in ('RightHand', 'LeftHand'):
    bones = [item for item in manifest['structures']
             if item['part'] == name and item['tissue'] == 'bone']
    assert len(bones) == 27, (name, len(bones))

print(f'Validated {len(files)} meshes, 206 anatomical bones, hands and feet.')
