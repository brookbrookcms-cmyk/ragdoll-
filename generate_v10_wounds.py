"""Cut small, body-fitted openings in the game's R15 mesh assets.

Run with Blender. Source meshes are downloaded to /workspace/anatomy-source.
The source IDs and dimensions are recorded in V10_ASSETS.md.
"""

import bpy
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = Path('/workspace/anatomy-source')

PARTS = [
    'upper_torso', 'lower_torso',
    'left_upper_arm', 'left_lower_arm', 'left_hand',
    'right_upper_arm', 'right_lower_arm', 'right_hand',
    'left_upper_leg', 'left_lower_leg', 'left_foot',
    'right_upper_leg', 'right_lower_leg', 'right_foot',
]


def read_source(name):
    data = (SOURCE / (name + '.mesh')).read_bytes()
    assert data.startswith(b'version 2.00\n')
    stride = data[15]
    vertex_count, face_count = struct.unpack_from('<II', data, 17)
    verts = [struct.unpack_from('<3f', data, 25 + i * stride)
             for i in range(vertex_count)]
    uvs = [struct.unpack_from('<2f', data, 25 + i * stride + 24)
           for i in range(vertex_count)]
    face_offset = 25 + vertex_count * stride
    faces = [struct.unpack_from('<III', data, face_offset + i * 12)
             for i in range(face_count)]
    return verts, uvs, faces


def mesh_object(name, verts, uvs, faces):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    layer = mesh.uv_layers.new(name='OriginalUV')
    for polygon in mesh.polygons:
        for loop in polygon.loop_indices:
            layer.data[loop].uv = uvs[mesh.loops[loop].vertex_index]
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def export(obj, path):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    mesh.calc_loop_triangles()
    layer = mesh.uv_layers.active
    rows = []
    for tri in mesh.loop_triangles:
        for loop_index in tri.loops:
            loop = mesh.loops[loop_index]
            vertex = mesh.vertices[loop.vertex_index]
            pos = vertex.co
            normal = vertex.normal.normalized()
            uv = layer.data[loop_index].uv if layer else (0, 0)
            rows.append((pos.x, pos.y, pos.z, normal.x, normal.y,
                         normal.z, uv[0], uv[1], 0.0))
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
    return len(rows) // 3


def variants(name, dims):
    sx, sy, sz = dims
    if 'foot' in name:
        return [('top_center', 'Y', 0, 0),
                ('top_toes', 'Y', 0, -sz * 0.26),
                ('top_heel', 'Y', 0, sz * 0.26),
                ('front_center', 'Z', 0, 0)]
    if 'hand' in name:
        return [('top_center', 'Y', 0, 0),
                ('front_center', 'Z', 0, 0),
                ('front_fingers', 'Z', 0, -sy * 0.24)]
    if 'torso' in name:
        return [('front_center', 'Z', 0, 0),
                ('front_left', 'Z', -sx * 0.22, 0),
                ('front_right', 'Z', sx * 0.22, 0),
                ('front_upper', 'Z', 0, sy * 0.22),
                ('front_lower', 'Z', 0, -sy * 0.22),
                ('side_center', 'X', 0, 0)]
    return [('front_center', 'Z', 0, 0),
            ('front_upper', 'Z', 0, sy * 0.24),
            ('front_lower', 'Z', 0, -sy * 0.24),
            ('side_center', 'X', 0, 0)]


total = 0
for name in PARTS:
    verts, uvs, faces = read_source(name)
    dims = [max(v[i] for v in verts) - min(v[i] for v in verts)
            for i in range(3)]
    for tag, axis, a, b in variants(name, dims):
        body = mesh_object(name, verts, uvs, faces)
        radius = min(dims) * (0.13 if 'torso' in name else 0.15)
        bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=radius,
                                            depth=max(dims) * 3)
        cutter = bpy.context.object
        if axis == 'Z':
            cutter.location = (a, b, 0)
        elif axis == 'X':
            cutter.location = (0, a, b)
            cutter.rotation_euler[1] = math.pi / 2
        else:
            cutter.location = (a, 0, b)
            cutter.rotation_euler[0] = math.pi / 2
        modifier = body.modifiers.new('small damage opening', 'BOOLEAN')
        modifier.operation = 'DIFFERENCE'
        modifier.solver = 'EXACT'
        modifier.object = cutter
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        bpy.data.objects.remove(cutter, do_unlink=True)
        output = ROOT / ('v10-hole-' + name + '-' + tag + '.mesh')
        count = export(body, output)
        bpy.data.objects.remove(body, do_unlink=True)
        print(output.name, count)
        total += 1

print('GENERATED', total, 'BODY-FITTED DAMAGE MESHES')
