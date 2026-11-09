# Ragdoll Physics visual scripts

The latest version is [`blood-visuals-v24.lua`](blood-visuals-v24.lua). It is a
client-side Delta script with a small ON/OFF switch. It detects the game's
`WoundMark` effects and cuts the corresponding NPC2 R15 body mesh. A single
shot makes a small opening; repeated hits widen and deepen it. Muscles show
first, bones after further damage, and torso organs after more hits.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/brookbrookcms-cmyk/ragdoll-/main/blood-visuals-v24.lua"))()
```

Delta needs `writefile` and `getcustomasset` (or `getsynasset`) to load the
mesh and texture files. The first hit to a body region may take a moment while
its assets download. ON/OFF restores the original body appearance.

The anatomy mesh provenance and license are in
[`ANATOMY_ATTRIBUTION.md`](ANATOMY_ATTRIBUTION.md). `v10-anatomy-manifest.json`
lists the 206 anatomical bones and all other adapted structures. The game's
private head mesh cannot be downloaded, so v24 keeps it visible for ordinary
head hits and exposes only localized skull and facial muscle geometry.
After at least three head hits and enough accumulated damage, a cuttable skin
shell locally replaces the game head. The skull, facial muscle, and brain show
through the damaged areas while intact areas remain covered.
An index identifies the named bones under each hit and renders their geometry
separately. The bones are visual
meshes, not simulated rigid bodies. This is a visual script and does not
change the game's hit detection or damage.

V24 uses one deep body-conforming tissue backing to reduce gaps without
covering bones with several layers. The small UI
displays `H:1` after the first processed head hit and the detected weapon
class. The script reads wound attributes or an equipped Tool when available;
pistols, rifles, shotguns, explosives, and blades produce different local
cut depths, sizes, and sprays. `BULLET` means no weapon class was available.
Torso cuts include fitted heart and lung meshes. The script suppresses known
pink blood textures wherever the game creates them and darkens its blood
emitters, bounds visible splats, and provides a directional spray with a brief
mist and delayed droplets on HIGH quality. LOW/MED/HIGH controls the effect
budget. The
[asset pipeline](ASSET_PIPELINE.md) explains the source meshes and the
current client-side rendering limits.
