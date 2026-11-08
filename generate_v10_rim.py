"""Create a small textured 3D tissue rim for localized body openings."""

import bpy
import struct
from pathlib import Path

bpy.ops.mesh.primitive_torus_add(major_segments=40, minor_segments=8,
                                 location=(0, 0, 0),
                                 major_radius=1.0, minor_radius=0.17)
obj = bpy.context.object
mesh = obj.data
mesh.calc_loop_triangles()
rows = []
for tri in mesh.loop_triangles:
    for loop_index in tri.loops:
        loop = mesh.loops[loop_index]
        point = mesh.vertices[loop.vertex_index].co
        normal = mesh.vertices[loop.vertex_index].normal.normalized()
        rows.append((point.x, point.y, point.z,
                     normal.x, normal.y, normal.z,
                     0.5 + (point.x + 1) * 0.25,
                     0.5 + (point.y + 1) * 0.25, 0.0))
path = Path(__file__).parent / 'v10-tissue-rim.mesh'
with path.open('wb') as file:
    file.write(b'version 2.00\n')
    file.write(bytes((0x0C, 0, 0x24, 0x0C)))
    file.write(struct.pack('<II', len(rows), len(rows) // 3))
    for row in rows:
        file.write(struct.pack('<9f', *row))
    for index in range(len(rows) // 3):
        file.write(struct.pack('<III', index * 3, index * 3 + 1,
                               index * 3 + 2))
print(path, len(rows) // 3)
