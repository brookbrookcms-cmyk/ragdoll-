# Ragdoll Physics NPC mesh sources

The source IDs below came from the user's in-game `NPC_BODY_REPORT` for the
R15 `NPC2` model in place `121868512253414`. The local build downloads these
Roblox FileMesh assets, then cuts small openings into copies of their
geometry. Source meshes are kept outside the repository; only derived mesh
files are published here.

| Body part | Mesh asset ID |
| --- | ---: |
| UpperTorso | 8650495328 |
| LowerTorso | 8650495385 |
| RightUpperArm | 8650495303 |
| RightLowerArm | 8650495271 |
| RightHand | 8650495280 |
| LeftUpperArm | 8650495273 |
| LeftLowerArm | 8650495270 |
| LeftHand | 8650495301 |
| LeftUpperLeg | 8650495362 |
| LeftLowerLeg | 8650495364 |
| LeftFoot | 8650495382 |
| RightUpperLeg | 8650495376 |
| RightLowerLeg | 8650495379 |
| RightFoot | 8650495330 |

The reported head mesh (`123480233606534`) returned an authorization error
from asset delivery. V10 therefore keeps the original head mesh and uses a
small skull fragment at the wound instead of swapping the whole head.
