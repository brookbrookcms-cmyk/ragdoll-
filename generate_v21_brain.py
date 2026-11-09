"""Generate a compact folded brain mesh for the client head anatomy view.

This mesh is a visual approximation. It fits inside the existing R15 head
atlas and is intended to be seen through a local opening in the skull.
"""

import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent
vertices = []
faces = []


def lobe(center, radii, seed, longitude=48, latitude=30):
    start = len(vertices)
    for row in range(latitude + 1):
        phi = math.pi * row / latitude
        for column in range(longitude + 1):
            theta = 2 * math.pi * column / longitude
            sx = math.sin(phi) * math.cos(theta)
            sy = math.cos(phi)
            sz = math.sin(phi) * math.sin(theta)
            fold = (0.018 * math.sin(12 * theta + 6 * phi + seed)
                    * math.sin(9 * phi - 3 * theta + seed)
                    + 0.008 * math.cos(19 * theta - 11 * phi + seed * 2))
            fold *= max(0.15, math.sin(phi))
            x = center[0] + radii[0] * (1 + fold) * sx
            y = center[1] + radii[1] * (1 + fold) * sy
            z = center[2] + radii[2] * (1 + fold) * sz
            nx, ny, nz = sx / radii[0], sy / radii[1], sz / radii[2]
            length = math.sqrt(nx * nx + ny * ny + nz * nz)
            u = .76 + .17 * sx
            v = .75 + .17 * sy
            vertices.append((x, y, z, nx / length, ny / length,
                             nz / length, u, v, 0.0))
    for row in range(latitude):
        for column in range(longitude):
            a = start + row * (longitude + 1) + column
            b = a + 1
            c = a + longitude + 1
            d = c + 1
            faces.extend(((a, b, c), (b, d, c)))


# Two folded cerebral hemispheres, a lower cerebellum, and brainstem.
lobe((-.155, .14, .035), (.165, .205, .29), .6)
lobe((.155, .14, .035), (.165, .205, .29), 2.1)
lobe((-.09, -.15, .15), (.105, .11, .135), 3.4, 32, 20)
lobe((.09, -.15, .15), (.105, .11, .135), 4.2, 32, 20)
lobe((0, -.26, .07), (.065, .15, .07), 1.1, 28, 16)

path = ROOT / "v21-brain.mesh"
with path.open("wb") as file:
    file.write(b"version 2.00\n")
    file.write(bytes((12, 0, 36, 12)))
    file.write(struct.pack("<II", len(vertices), len(faces)))
    for vertex in vertices:
        file.write(struct.pack("<9f", *vertex))
    for face in faces:
        file.write(struct.pack("<III", *face))
print(path.name, len(vertices), "vertices", len(faces), "faces")
