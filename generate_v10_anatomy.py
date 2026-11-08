"""Fit named Écorché anatomy structures inside the game's R15 body parts.

Model source: github.com/Charleeh/ecorche (CC BY-SA 4.0). This derived
geometry is also CC BY-SA 4.0; see ANATOMY_ATTRIBUTION.md.
Run: blender -b -t 2 --python generate_v10_anatomy.py
"""

import bpy
import json
import math
import struct
from collections import defaultdict
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parent
SOURCE = Path('/workspace/ecorche-source/model')
META = {entry['name']: entry for entry in
        json.loads((SOURCE / 'ecorche.structures.json').read_text())}

SIZES = {
    'Head': (1.1962, 1.2029, 1.1979),
    'UpperTorso': (1.8154, 1.7732, 1.1102),
    'LowerTorso': (1.6962, 0.5661, 0.9525),
    'RightUpperArm': (0.5699, 1.0948, 0.7828),
    'RightLowerArm': (0.6271, 0.9477, 0.6166),
    'RightHand': (0.6933, 1.1018, 0.7443),
    'LeftUpperArm': (0.5699, 1.0948, 0.7828),
    'LeftLowerArm': (0.6271, 0.9477, 0.6166),
    'LeftHand': (0.6933, 1.1018, 0.7443),
    'RightUpperLeg': (0.7597, 1.3789, 0.7694),
    'RightLowerLeg': (0.7420, 1.0774, 0.8213),
    'RightFoot': (0.8362, 0.6279, 1.2425),
    'LeftUpperLeg': (0.7597, 1.3789, 0.7694),
    'LeftLowerLeg': (0.7420, 1.0774, 0.8213),
    'LeftFoot': (0.8362, 0.6279, 1.2425),
}

bpy.ops.import_scene.gltf(filepath=str(SOURCE / 'ecorche.glb'))

supplements = [
    ('Hyoid bone', (0, -0.07, 1.46)),
    ('Coccyx', (0, 0.02, 0.83)),
]
for side, x in (('Left', 0.07), ('Right', -0.07)):
    for name, offset in (('malleus', -0.008), ('incus', 0),
                         ('stapes', 0.008)):
        supplements.append((f'{side} {name}', (x, -0.015 + offset, 1.55)))
for side, x in (('Left', 0.26), ('Right', -0.26)):
    supplements.append((f'{side} triquetrum', (x, -0.02, 0.88)))

for name, location in supplements:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8,
                                         radius=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (0.015, 0.012, 0.018) if 'bone' not in name.lower() \
        else (0.03, 0.015, 0.012)
    META[name] = {'name': name, 'layer': 'skeleton', 'tissue': 'bone',
                  'source': 'supplemental approximation'}

TORSO_WORDS = ('sternum', 'rib', 'clavicle', 'scapula', 'pectoralis',
               'trapezius', 'latissimus', 'serratus', 'oblique', 'abdominis',
               'intercostal', 'vertebra', 'sacrum', 'hip bone', 'iliacus',
               'psoas')


def center(obj):
    points = [obj.matrix_world @ Vector(p) for p in obj.bound_box]
    return sum(points, Vector()) / len(points)


def group_for(obj, meta):
    name = obj.name.lower()
    point = center(obj)
    x, z = point.x, point.z
    side = 'Left' if meta.get('side') == 'left' or x > 0.01 else 'Right'
    if z >= 1.47 or any(word in name for word in
                        ('hyoid', 'malleus', 'incus', 'stapes')):
        return 'Head'
    if any(word in name for word in TORSO_WORDS):
        return 'UpperTorso' if z >= 1.08 else 'LowerTorso'
    if z >= 0.65 and abs(x) > 0.16:
        if z >= 1.13:
            return side + 'UpperArm'
        if z >= 0.95:
            return side + 'LowerArm'
        return side + 'Hand'
    if z >= 1.08:
        return 'UpperTorso'
    if z >= 0.84 and abs(x) < 0.17:
        return 'LowerTorso'
    if z >= 0.51:
        return side + 'UpperLeg'
    if z >= 0.14:
        return side + 'LowerLeg'
    return side + 'Foot'


groups = defaultdict(lambda: {'bone': [], 'muscle': []})
manifest = []
for obj in bpy.data.objects:
    if obj.type != 'MESH' or obj.name not in META:
        continue
    meta = META[obj.name]
    group = group_for(obj, meta)
    tissue = 'bone' if meta['layer'] == 'skeleton' else 'muscle'
    groups[group][tissue].append(obj)
    manifest.append({'name': obj.name, 'part': group,
                     'tissue': meta.get('tissue', tissue),
                     'source': meta['source']})

bones = [row for row in manifest if row['tissue'] == 'bone']
# The atlas models the sternum as three mesh pieces (manubrium, body,
# xiphoid); standard adult bone counting treats them as one bone.
assert len(bones) == 208, len(bones)


def bounds_for(objects):
    points = []
    for obj in objects:
        points.extend(obj.matrix_world @ Vector(p) for p in obj.bound_box)
    return ([min(p[i] for p in points) for i in range(3)],
            [max(p[i] for p in points) for i in range(3)])


def export_group(part, tissue, objects):
    if not objects:
        return
    reference = groups[part]['bone'] or objects
    low, high = bounds_for(reference)
    mid = [(low[i] + high[i]) * 0.5 for i in range(3)]
    span = [max(high[i] - low[i], 0.02) for i in range(3)]
    sx, sy, sz = SIZES[part]
    rows = []
    for obj in objects:
        original_faces = len(obj.data.polygons)
        budget = 180 if tissue == 'bone' else 110
        if original_faces > budget and not obj.modifiers.get('mobile simplification'):
            modifier = obj.modifiers.new('mobile simplification', 'DECIMATE')
            modifier.ratio = max(0.0005, budget / original_faces)
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()

    for obj in objects:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        matrix = obj.matrix_world
        normal_matrix = matrix.to_3x3().inverted().transposed()
        for tri in mesh.loop_triangles:
            for loop_index in tri.loops:
                loop = mesh.loops[loop_index]
                vertex = mesh.vertices[loop.vertex_index]
                world = matrix @ vertex.co
                x = (world.x - mid[0]) / span[0] * sx * 0.75
                y_depth = 0.60 if part.endswith(('Foot', 'Hand')) else 0.76
                y = (world.z - mid[2]) / span[2] * sy * y_depth
                z = (world.y - mid[1]) / span[1] * sz * 0.66
                x = max(-sx * 0.45, min(sx * 0.45, x))
                y = max(-sy * 0.45, min(sy * 0.45, y))
                z = max(-sz * 0.44, min(sz * 0.44, z))
                n = (normal_matrix @ vertex.normal).normalized()
                normal = Vector((n.x / sx, n.z / sy, n.y / sz)).normalized()
                u = ((x / sx) + 0.5) * 0.5 + (0.0 if tissue == 'bone' else 0.5)
                v = ((y / sy) + 0.5) * 0.5 + 0.5
                rows.append((x, y, z, normal.x, normal.y, normal.z,
                             u, v, 0.0))
        evaluated.to_mesh_clear()

    path = ROOT / ('v10-anatomy-' + part.lower() + '-' + tissue + '.mesh')
    with path.open('wb') as file:
        file.write(b'version 2.00\n')
        file.write(bytes((0x0C, 0, 0x24, 0x0C)))
        file.write(struct.pack('<II', len(rows), len(rows) // 3))
        for row in rows:
            file.write(struct.pack('<9f', *row))
        for index in range(len(rows) // 3):
            file.write(struct.pack('<III', index * 3, index * 3 + 1,
                                   index * 3 + 2))
    print(part, tissue, len(objects), 'structures', len(rows) // 3,
          'triangles', path.stat().st_size, 'bytes')


for part in SIZES:
    for tissue in ('bone', 'muscle'):
        export_group(part, tissue, groups[part][tissue])

# Small fragments from actual source bones can peek through tiny wounds.
def export_chip(source_name, filename, extent):
    obj = bpy.data.objects.get(source_name)
    if not obj:
        return
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    mesh.calc_loop_triangles()
    matrix = obj.matrix_world
    points = [matrix @ vertex.co for vertex in mesh.vertices]
    center = sum(points, Vector()) / len(points)
    span = max(max(point[i] for point in points) -
               min(point[i] for point in points) for i in range(3))
    rows = []
    for tri in mesh.loop_triangles:
        for loop_index in tri.loops:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index]
            point = (matrix @ vertex.co - center) * (extent / span)
            normal = vertex.normal.normalized()
            rows.append((point.x, point.z, point.y,
                         normal.x, normal.z, normal.y,
                         0.25 + point.x, 0.75 + point.z, 0.0))
    path = ROOT / filename
    with path.open('wb') as file:
        file.write(b'version 2.00\n')
        file.write(bytes((0x0C, 0, 0x24, 0x0C)))
        file.write(struct.pack('<II', len(rows), len(rows) // 3))
        for row in rows:
            file.write(struct.pack('<9f', *row))
        for index in range(len(rows) // 3):
            file.write(struct.pack('<III', index * 3, index * 3 + 1,
                                   index * 3 + 2))
    evaluated.to_mesh_clear()


export_chip('Left parietal bone', 'v10-skull-chip.mesh', 0.18)
export_chip('Right third metatarsal bone', 'v10-foot-chip.mesh', 0.18)
export_chip('Right capitate', 'v10-hand-chip.mesh', 0.12)
export_chip('Right humerus', 'v10-limb-chip.mesh', 0.15)

(ROOT / 'v10-anatomy-manifest.json').write_text(
    json.dumps({'bone_count': 206,
                'bone_mesh_count': len(bones),
                'counting_note': 'Manubrium, body and xiphoid are one sternum in the 206-bone count.',
                'supplemental_bones': [name for name, _ in supplements],
                'structures': manifest}, indent=2))
print('anatomical bone count', 206, 'bone meshes', len(bones),
      'total structures', len(manifest))
