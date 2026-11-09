# Ragdoll Physics visual scripts

The latest version is [`blood-visuals-v22.lua`](blood-visuals-v22.lua). It is a
client-side Delta script with a small ON/OFF switch. It detects the game's
`WoundMark` effects and cuts the corresponding NPC2 R15 body mesh. A single
shot makes a small opening; grouped hits make wider openings. Bone and muscle
structures are loaded for the wounded part and exposed within the cut.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/brookbrookcms-cmyk/ragdoll-/main/blood-visuals-v22.lua"))()
```

Delta needs `writefile` and `getcustomasset` (or `getsynasset`) to load the
mesh and texture files. The first hit to a body region may take a moment while
its assets download. ON/OFF restores the original body appearance.

The anatomy mesh provenance and license are in
[`ANATOMY_ATTRIBUTION.md`](ANATOMY_ATTRIBUTION.md). `v10-anatomy-manifest.json`
lists the 206 anatomical bones and all other adapted structures. The game's
private head mesh cannot be downloaded, so v21 shows a fitted skull, facial
muscle, and folded brain assembly when a head is hit. It locally hides the
game head at that point and cuts an opening through the visible anatomy.
An index identifies the named bones under each hit and renders their geometry
separately. The bones are visual
meshes, not simulated rigid bodies. This is a visual script and does not
change the game's hit detection or damage.

V22 uses one deep body-conforming tissue backing to reduce gaps without
covering bones with several layers. A head hit shows the full anatomical
assembly and the brain mesh is fitted closer to the skull. The small UI
displays `H:1` after the first processed head hit and the detected weapon
class. The script reads wound attributes or an equipped Tool when available;
pistols, rifles, shotguns, explosives, and blades produce different local
cut depths, sizes, and sprays. `BULLET` means no weapon class was available.
Torso cuts include fitted heart and lung meshes. The script suppresses known
pink blood textures wherever the game creates them and darkens its blood
emitters, bounds visible splats, and provides a short gravity-influenced
impact spray and LOW/MED/HIGH quality switch. The
[asset pipeline](ASSET_PIPELINE.md) explains the source meshes and the
current client-side rendering limits.
