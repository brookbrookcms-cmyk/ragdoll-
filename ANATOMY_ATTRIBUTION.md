# V10 anatomy mesh attribution

The `v10-anatomy-*.mesh` and `v10-*-chip.mesh` files are adapted from
**Écorché** by Charleeh: https://github.com/Charleeh/ecorche . That work
uses **BodyParts3D**, © The Database Center for Life Science, CC BY 4.0,
and **Z-Anatomy** by Gauthier Kervyn, CC BY-SA 4.0.

The derived anatomy meshes in this repository are shared under
**Creative Commons Attribution-ShareAlike 4.0**. The full license is in
`LICENSE-ANATOMY.txt`.

Changes made here: grouped structures into Roblox R15 body regions, scaled
them to the game's NPC dimensions, simplified geometry for mobile rendering,
added approximate geometry for the hyoid, coccyx, six ear ossicles and two
triquetra, and exported Roblox FileMesh assets. The upstream Écorché work
models the sternum as three separate mesh pieces; standard adult bone counting
treats those pieces as one bone. The result represents 206 anatomical bones
through 208 bone mesh pieces. This is a stylized visual adaptation and is not
a medical or diagnostic model.

`v10-anatomy-manifest.json` lists each source structure and its assigned
Roblox body part. The `v10-hole-*.mesh` files are derived from the R15 mesh
assets identified in the game's NPC. Other artwork and code in the repository
have their own provenance and are not covered by this anatomy asset license.
