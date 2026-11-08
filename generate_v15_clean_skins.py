"""Export clean R15 source skins and a procedural cuttable head for v15.

The 14 game meshes were downloaded from the IDs listed in V10_ASSETS.md.
Keep the generated meshes in the repository; the runtime cannot fetch the
original head mesh because that asset is private.
"""

import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCE = Path("/workspace/anatomy-source")


def write_mesh(path, vertices, faces):
    with path.open("wb") as file:
        file.write(b"version 2.00\n")
        file.write(bytes((12, 0, 36, 12)))
        file.write(struct.pack("<II", len(vertices), len(faces)))
        for vertex in vertices:
            file.write(struct.pack("<9f", *vertex))
        for face in faces:
            file.write(struct.pack("<III", *face))


for source in sorted(SOURCE.glob("*.mesh")):
    data = source.read_bytes()
    assert data.startswith(b"version 2.00\n")
    stride = data[15]
    vertex_count, face_count = struct.unpack_from("<II", data, 17)
    vertices = [struct.unpack_from("<9f", data, 25 + index * stride)
                for index in range(vertex_count)]
    face_start = 25 + vertex_count * stride
    faces = [struct.unpack_from("<III", data, face_start + index * 12)
             for index in range(face_count)]
    assert all(max(face) < vertex_count for face in faces)
    write_mesh(ROOT / f"v15-clean-{source.stem}.mesh", vertices, faces)


# A rounded rectangular head matches the reported dimensions more closely
# than a sphere. Separate face vertices preserve correct outward normals.
half = (1.1962 / 2, 1.2029 / 2, 1.1979 / 2)
rounding = 0.18
grid = 12
vertices = []
faces = []
for axis in range(3):
    other = [index for index in range(3) if index != axis]
    for sign in (-1, 1):
        lookup = {}
        for iy in range(grid + 1):
            for ix in range(grid + 1):
                p = [0.0, 0.0, 0.0]
                p[axis] = sign * half[axis]
                p[other[0]] = (ix / grid * 2 - 1) * half[other[0]]
                p[other[1]] = (iy / grid * 2 - 1) * half[other[1]]
                inner = [max(-half[k] + rounding,
                             min(half[k] - rounding, p[k]))
                         for k in range(3)]
                delta = [p[k] - inner[k] for k in range(3)]
                length = math.sqrt(sum(value * value for value in delta))
                normal = [value / length for value in delta]
                position = [inner[k] + normal[k] * rounding
                            for k in range(3)]
                # Keep face art on the front of the substitute head. Other
                # sides sample its edge colour rather than repeating the face.
                u = ix / grid if axis == 2 and sign == -1 else 0.02
                v = 1 - iy / grid if axis == 2 and sign == -1 else 0.02
                lookup[ix, iy] = len(vertices)
                vertices.append((*position, *normal, u, v, 0.0))
        for iy in range(grid):
            for ix in range(grid):
                a = lookup[ix, iy]
                b = lookup[ix + 1, iy]
                c = lookup[ix + 1, iy + 1]
                d = lookup[ix, iy + 1]
                # Cross product of the grid axes determines winding.
                cross = (1 if (other[0], other[1]) in
                         ((0, 1), (1, 2), (2, 0)) else -1)
                if cross == sign:
                    faces.extend(((a, b, c), (a, c, d)))
                else:
                    faces.extend(((a, c, b), (a, d, c)))

write_mesh(ROOT / "v15-clean-head.mesh", vertices, faces)
print("Generated 15 clean body meshes")
