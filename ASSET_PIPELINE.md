# Asset pipeline and rendering limits

The current anatomy starts from the named Écorché structures credited in
`ANATOMY_ATTRIBUTION.md`. `generate_v10_anatomy.py` imports the source GLB in
Blender, decimates each structure for mobile, fits it to each R15 body region,
and exports FileMesh v2 files. `v15-bone-index.json` preserves the named bone
boundaries. `generate_v15_clean_skins.py` converts the game's available R15
meshes into clean FileMesh assets; the game's private head asset requires a
rounded substitute. The script clips these meshes at hit positions and welds
the results to the matching body part.

For a higher fidelity asset set, sculpt skin, fat, muscle, bone, and damaged
surface variants in Blender. Retopologize for mobile, preserve matching bind
poses, unwrap UVs, bake color/normal/roughness maps from the high resolution
sculpt, and check silhouette and seams at game scale. Export separate LODs and
test each R15 pose, clothing combination, and ragdoll rotation before release.
Wound edges should be authored as part of the damaged skin mesh, with tissue
layers fitted beneath them. Avoid a reusable red ring or planar cap.

Roblox `SurfaceAppearance` normal and roughness maps require suitable
`MeshPart` assets uploaded through Roblox's asset pipeline. The runtime
FileMesh plus `SpecialMesh` route used by this client script supports a color
texture but does not provide that PBR stack. A client script cannot extract
the game's private head mesh or reliably replace server-owned ragdoll physics.
Uploaded, accessible replacement assets and supported runtime loading would
be necessary to reach the requested sculpted/PBR look. V16 changes only local
visuals and keeps the game's hit and damage systems authoritative.
