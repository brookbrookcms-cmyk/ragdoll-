"""Generate client-side Roblox FileMesh v2 assets with Blender 4.x.

Run: blender -b -t 2 --python generate_anatomy_meshes.py
All coordinates are normalized to a torso bounding box of one unit per axis.
"""

import bpy
import bmesh
import math
import struct
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parent
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def raw_mesh(name, vertices, faces):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


N = 64
outer_front = []
outer_back = []
inner_front = []
inner_back = []
for i in range(N):
    a = 2 * math.pi * i / N
    c, s = math.cos(a), math.sin(a)
    d = max(abs(c), abs(s))
    ox, oy = 0.5 * c / d, 0.5 * s / d
    jag = 1 + 0.045 * math.sin(7 * a) + 0.025 * math.sin(13 * a + 0.4)
    ix, iy = 0.29 * c * jag, 0.34 * s * jag
    outer_front.append((ox, oy, -0.5))
    outer_back.append((ox, oy, 0.5))
    inner_front.append((ix, iy, -0.5 + 0.014 * math.sin(9 * a)))
    inner_back.append((ix, iy, 0.5 + 0.014 * math.sin(11 * a)))

verts = outer_front + inner_front + outer_back + inner_back
faces = []
for i in range(N):
    j = (i + 1) % N
    faces.extend([
        (i, j, N + j, N + i),
        (2 * N + j, 2 * N + i, 3 * N + i, 3 * N + j),
        (i, 2 * N + i, 2 * N + j, j),
    ])
shell = raw_mesh("torso_shell", verts, faces)
shell_uv = shell.data.uv_layers.new(name="TorsoFront")
for polygon in shell.data.polygons:
    for loop_index in polygon.loop_indices:
        co = shell.data.vertices[shell.data.loops[loop_index].vertex_index].co
        shell_uv.data[loop_index].uv = (co.x + 0.5, co.y + 0.5)
bevel = shell.modifiers.new("soft outer edges", "BEVEL")
bevel.width = 0.018
bevel.segments = 2

inner_verts = []
for ring, z in enumerate((-0.5, -0.24, 0.24, 0.5)):
    for i in range(N):
        a = 2 * math.pi * i / N
        c, s = math.cos(a), math.sin(a)
        jag = 1 + 0.045 * math.sin(7 * a) + 0.025 * math.sin(13 * a + 0.4)
        pinch = 0.84 if ring in (1, 2) else 1
        inner_verts.append((0.29 * c * jag * pinch,
                            0.34 * s * jag * pinch,
                            z + 0.012 * math.sin(a * 11 + ring)))
inner_faces = []
for ring in range(3):
    for i in range(N):
        j = (i + 1) % N
        inner_faces.append((ring * N + i, ring * N + j,
                            (ring + 1) * N + j, (ring + 1) * N + i))
inner = raw_mesh("inner_tissue", inner_verts, inner_faces)
for poly in inner.data.polygons:
    poly.use_smooth = True


def organ_sphere(name, location, scale, seed):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=24, location=location)
    obj = bpy.context.object
    obj.name = name
    for vertex in obj.data.vertices:
        x, y, z = vertex.co
        ripple = 1 + 0.035 * math.sin(8 * x + seed) * math.cos(10 * y - seed)
        vertex.co.x *= scale[0] * ripple
        vertex.co.y *= scale[1] * ripple
        vertex.co.z *= scale[2] * ripple
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


lungs = []
for side in (-1, 1):
    for index, y in enumerate((0.10, -0.12)):
        lungs.append(organ_sphere("lung_lobe", (side * 0.18, y, 0.03),
                                  (0.15, 0.23 if index == 0 else 0.17, 0.22),
                                  side * 1.4 + index))
heart = [organ_sphere("heart_body", (-0.035, 0.04, -0.12),
                      (0.105, 0.145, 0.13), 3.2)]


def tube(name, points, radius, resolution=4):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 16
    curve.bevel_depth = radius
    curve.bevel_resolution = resolution
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for bp, point in zip(spline.bezier_points, points):
        bp.co = point
        bp.handle_left_type = "AUTO"
        bp.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    return bpy.context.object


heart.extend([
    tube("aorta", [(-0.02, 0.13, -0.10), (0.02, 0.26, -0.07),
                   (0.08, 0.29, 0.01)], 0.026),
    tube("vessel", [(-0.06, 0.12, -0.13), (-0.17, 0.22, -0.08),
                    (-0.24, 0.25, 0.02)], 0.014),
])

ribs = []
for side in (-1, 1):
    for index in range(5):
        y = 0.30 - index * 0.14
        ribs.append(tube("rib", [(side * 0.04, y, -0.25),
                                 (side * 0.19, y - 0.035, -0.33),
                                 (side * 0.39, y - 0.075, -0.22)],
                         0.013 + index * 0.001))
ribs.append(tube("spine", [(0, -0.43, 0.33), (0, 0, 0.35),
                            (0, 0.43, 0.33)], 0.034))


def export_filemesh(name, objects, quadrant=None):
    rows = []
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in objects:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        uv_layer = mesh.uv_layers.active
        matrix = obj.matrix_world
        for triangle in mesh.loop_triangles:
            for loop_index in triangle.loops:
                loop = mesh.loops[loop_index]
                vertex = mesh.vertices[loop.vertex_index]
                co = matrix @ vertex.co
                normal = vertex.normal.normalized()
                if uv_layer:
                    uv = uv_layer.data[loop_index].uv
                    u, v = float(uv.x), float(uv.y)
                else:
                    u = (math.atan2(co.y, co.x) / (2 * math.pi)) % 1
                    v = co.z + 0.5
                if quadrant is not None:
                    u = quadrant[0] * 0.5 + u * 0.5
                    v = quadrant[1] * 0.5 + v * 0.5
                rows.append((co.x, co.y, co.z, normal.x, normal.y, normal.z,
                             u, v, 0.0))
        evaluated.to_mesh_clear()
    path = ROOT / (name + ".mesh")
    with path.open("wb") as file:
        file.write(b"version 2.00\n")
        file.write(bytes((0x0C, 0x00, 0x24, 0x0C)))
        file.write(struct.pack("<II", len(rows), len(rows) // 3))
        for row in rows:
            file.write(struct.pack("<9f", *row))
        for face in range(len(rows) // 3):
            file.write(struct.pack("<III", face * 3, face * 3 + 1, face * 3 + 2))
    print(name, len(rows) // 3, "faces", path.stat().st_size, "bytes")


export_filemesh("torso-shell", [shell])
export_filemesh("torso-inner", [inner], (1, 1))
export_filemesh("torso-lungs", lungs, (1, 0))
export_filemesh("torso-heart", heart, (0, 0))
export_filemesh("torso-ribs", ribs, (0, 1))
