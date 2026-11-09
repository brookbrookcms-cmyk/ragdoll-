"""Build a rounded cylindrical substitute for the private NPC2 head mesh."""

import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent
hx, hy, hz = 1.1962 / 2, 1.2029 / 2, 1.1979 / 2
rings = [(-hy, .84), (-hy + .045, .92), (-hy + .14, 1),
         (-.28, 1), (0, 1), (.28, 1), (hy - .14, 1),
         (hy - .045, .92), (hy, .84)]
segments = 40
rows = []
faces = []

for ring, (y, radius) in enumerate(rings):
    previous = rings[max(0, ring - 1)]
    following = rings[min(len(rings) - 1, ring + 1)]
    slope = (following[1] - previous[1]) / max(following[0] - previous[0], .001)
    for step in range(segments + 1):
        angle = step * 2 * math.pi / segments
        x = hx * radius * math.sin(angle)
        z = -hz * radius * math.cos(angle)
        nx, ny, nz = math.sin(angle) / hx, -slope, -math.cos(angle) / hz
        length = math.sqrt(nx * nx + ny * ny + nz * nz)
        nx, ny, nz = nx / length, ny / length, nz / length
        front = math.cos(angle) >= 0
        u = .5 + .48 * math.sin(angle) if front else .02
        v = 1 - (y + hy) / (2 * hy)
        rows.append((x, y, z, nx, ny, nz, u, v, 0))

for ring in range(len(rings) - 1):
    for step in range(segments):
        a = ring * (segments + 1) + step
        b = a + 1
        c = a + segments + 1
        d = c + 1
        faces.extend(((a, c, b), (b, c, d)))

for sign, ring in ((-1, 0), (1, len(rings) - 1)):
    y = sign * hy
    center = len(rows)
    rows.append((0, y, 0, 0, sign, 0, .02, .02, 0))
    for step in range(segments):
        a = ring * (segments + 1) + step
        b = a + 1
        if sign > 0:
            faces.append((center, b, a))
        else:
            faces.append((center, a, b))

path = ROOT / "v17-head.mesh"
with path.open("wb") as file:
    file.write(b"version 2.00\n")
    file.write(bytes((12, 0, 36, 12)))
    file.write(struct.pack("<II", len(rows), len(faces)))
    for row in rows:
        file.write(struct.pack("<9f", *row))
    for face in faces:
        file.write(struct.pack("<III", *face))
print(path.name, len(rows), "vertices", len(faces), "faces")
