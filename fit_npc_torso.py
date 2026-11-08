"""Build damaged variants from NPC2's actual Roblox UpperTorso mesh.

Run: blender -b -t 2 --python fit_npc_torso.py
"""

import bpy
import bmesh
import math
import struct
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE_URL = "https://assetdelivery.roblox.com/v1/asset/?id=8650495328"
raw = urllib.request.urlopen(SOURCE_URL, timeout=20).read()
assert raw.startswith(b"version 2.00\n")
vertex_size = raw[15]
count, face_count = struct.unpack_from("<II", raw, 17)
assert vertex_size == 40
vertices = []
uvs = []
for index in range(count):
    offset = 25 + index * vertex_size
    vertices.append(struct.unpack_from("<3f", raw, offset))
    uvs.append(struct.unpack_from("<2f", raw, offset + 24))
face_offset = 25 + count * vertex_size
faces = [struct.unpack_from("<III", raw, face_offset + i * 12)
         for i in range(face_count)]


def source_object():
    mesh = bpy.data.meshes.new("npc_upper_torso")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="OriginalUV")
    for polygon in mesh.polygons:
        for loop in polygon.loop_indices:
            uv_layer.data[loop].uv = uvs[mesh.loops[loop].vertex_index]
    obj = bpy.data.objects.new("npc_upper_torso", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def export_filemesh(obj, path):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    mesh.calc_loop_triangles()
    layer = mesh.uv_layers.active
    rows = []
    for triangle in mesh.loop_triangles:
        for loop_index in triangle.loops:
            loop = mesh.loops[loop_index]
            vertex = mesh.vertices[loop.vertex_index]
            point = vertex.co
            normal = vertex.normal.normalized()
            if layer:
                uv = layer.data[loop_index].uv
                u, v = uv.x, uv.y
            else:
                u, v = point.x + 0.5, point.y + 0.5
            rows.append((point.x, point.y, point.z,
                         normal.x, normal.y, normal.z, u, v, 0.0))
    with path.open("wb") as file:
        file.write(b"version 2.00\n")
        file.write(bytes((0x0C, 0x00, 0x24, 0x0C)))
        file.write(struct.pack("<II", len(rows), len(rows) // 3))
        for row in rows:
            file.write(struct.pack("<9f", *row))
        for face in range(len(rows) // 3):
            file.write(struct.pack("<III", 3 * face, 3 * face + 1, 3 * face + 2))
    evaluated.to_mesh_clear()
    print(path.name, len(rows) // 3, "faces")


def make_hole(tag, x, y):
    body = source_object()
    body.name = tag
    bpy.ops.mesh.primitive_cylinder_add(vertices=72, radius=1, depth=2.0,
                                        location=(x, y, 0))
    cutter = bpy.context.object
    cutter.name = "temporary cutter"
    cutter.scale = (0.36, 0.41, 1)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    modifier = body.modifiers.new("actual body opening", "BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.solver = "EXACT"
    modifier.object = cutter
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    export_filemesh(body, ROOT / ("fitted-torso-" + tag + ".mesh"))

    # A narrow irregular lining gives the cut edge depth without extending
    # beyond the original torso silhouette.
    rings = []
    ring_count = 4
    segments = 72
    for ring in range(ring_count):
        z = -0.50 + ring * (1.0 / (ring_count - 1))
        for index in range(segments):
            angle = 2 * math.pi * index / segments
            edge = 1 + 0.04 * math.sin(7 * angle + ring * 0.4)
            rings.append((x + 0.357 * math.cos(angle) * edge,
                          y + 0.405 * math.sin(angle) * edge,
                          z))
    lining_faces = []
    for ring in range(ring_count - 1):
        for index in range(segments):
            next_index = (index + 1) % segments
            lining_faces.append((ring * segments + index,
                                 ring * segments + next_index,
                                 (ring + 1) * segments + next_index,
                                 (ring + 1) * segments + index))
    mesh = bpy.data.meshes.new("tissue_lining")
    mesh.from_pydata(rings, [], lining_faces)
    mesh.update()
    layer = mesh.uv_layers.new(name="TissueAtlas")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            vertex_index = mesh.loops[loop_index].vertex_index
            ring_index = vertex_index // segments
            angle_index = vertex_index % segments
            layer.data[loop_index].uv = (
                0.5 + 0.5 * angle_index / segments,
                0.5 + 0.5 * ring_index / (ring_count - 1),
            )
    obj = bpy.data.objects.new("tissue_lining", mesh)
    bpy.context.collection.objects.link(obj)
    export_filemesh(obj, ROOT / ("fitted-lining-" + tag + ".mesh"))
    bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.objects.remove(body, do_unlink=True)


for tag, x, y in (("center", 0, 0),
                  ("left", -0.22, 0),
                  ("right", 0.22, 0),
                  ("upper", 0, 0.22),
                  ("lower", 0, -0.22)):
    make_hole(tag, x, y)
