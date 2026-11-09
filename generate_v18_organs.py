"""Fit the existing torso heart and lung meshes into NPC2 R15 torso units."""

import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SCALE = (1.8154, 1.7732, 1.1102)

for organ in ("heart", "lungs"):
    source = (ROOT / f"torso-{organ}.mesh").read_bytes()
    assert source[:13] == b"version 2.00\n" and source[15] == 36
    vertex_count, face_count = struct.unpack_from("<II", source, 17)
    rows = []
    for index in range(vertex_count):
        values = struct.unpack_from("<9f", source, 25 + index * 36)
        position = [values[axis] * SCALE[axis] for axis in range(3)]
        normal = [values[axis + 3] / SCALE[axis] for axis in range(3)]
        length = math.sqrt(sum(value * value for value in normal))
        normal = [value / length for value in normal]
        rows.append((*position, *normal, *values[6:]))
    face_start = 25 + vertex_count * 36
    output = ROOT / f"v18-organ-{organ}.mesh"
    with output.open("wb") as file:
        file.write(source[:25])
        for row in rows:
            file.write(struct.pack("<9f", *row))
        file.write(source[face_start:face_start + face_count * 12])
    print(output.name, face_count, "faces")
