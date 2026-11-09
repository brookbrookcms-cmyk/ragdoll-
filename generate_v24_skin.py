"""Create a cuttable head skin shell and a subtle seamless skin color map.

The shell is only a substitute after severe damage; normal heads retain the
game's own mesh and face. This diffuse texture is an authored approximation,
not a PBR skin material.
"""

import struct
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
source = (ROOT / "v17-head.mesh").read_bytes()
vertex_count, face_count = struct.unpack_from("<II", source, 17)
rows = []
for index in range(vertex_count):
    value = list(struct.unpack_from("<9f", source, 25 + index * 36))
    for axis in range(3):
        value[axis] /= 1.18
    y = value[1]
    value[6] = (index % 41) / 40 if index < 369 else .5
    value[7] = 1 - (y * 1.18 + 1.2029 / 2) / 1.2029
    rows.append(value)

with (ROOT / "v24-head-skin.mesh").open("wb") as file:
    file.write(source[:25])
    for row in rows:
        file.write(struct.pack("<9f", *row))
    file.write(source[25 + vertex_count * 36:
                      25 + vertex_count * 36 + face_count * 12])

rng = np.random.default_rng(24)
resolution = 512


def periodic_noise(cells):
    small = rng.random((cells, cells), dtype=np.float32)
    tile = np.tile(small, (2, 2))
    image = Image.fromarray(np.uint8(tile * 255), "L")
    image = image.resize((resolution * 2, resolution * 2),
                         Image.Resampling.BICUBIC)
    return np.asarray(image, dtype=np.float32)[:resolution, :resolution] / 255


large = periodic_noise(6) - .5
medium = periodic_noise(26) - .5
fine = periodic_noise(92) - .5
pores = rng.random((resolution, resolution)) < .012
variation = large * 15 + medium * 8 + fine * 4 - pores * 12
base = np.array([215, 176, 148], dtype=np.float32)
skin = np.clip(base + variation[:, :, None]
               * np.array([1, .82, .73], dtype=np.float32), 0, 255)
Image.fromarray(skin.astype(np.uint8), "RGB").save(
    ROOT / "v24-skin.png", optimize=True)
print("Generated v24 head shell and seamless diffuse texture")
