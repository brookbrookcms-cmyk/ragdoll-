# Ragdoll Physics visual scripts

The latest version is [`blood-visuals-v17.lua`](blood-visuals-v17.lua). It is a
client-side Delta script with a small ON/OFF switch. It detects the game's
`WoundMark` effects and cuts the corresponding NPC2 R15 body mesh. A single
shot makes a small opening; grouped hits make wider openings. Bone and muscle
structures are loaded for the wounded part and exposed within the cut.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/brookbrookcms-cmyk/ragdoll-/main/blood-visuals-v17.lua"))()
```

Delta needs `writefile` and `getcustomasset` (or `getsynasset`) to load the
mesh and texture files. The first hit to a body region may take a moment while
its assets download. ON/OFF restores the original body appearance.

The anatomy mesh provenance and license are in
[`ANATOMY_ATTRIBUTION.md`](ANATOMY_ATTRIBUTION.md). `v10-anatomy-manifest.json`
lists the 206 anatomical bones and all other adapted structures. The game's
private head mesh cannot be downloaded, so damaged heads use a rounded
replacement mesh sized to the reported NPC head. The replacement may not
match every custom head texture exactly. An index identifies the named bones
under each hit and renders their geometry separately. The bones are visual
meshes, not simulated rigid bodies. This is a visual script and does not
change the game's hit detection or damage.

V17 uses a rounded replacement head, smaller fitted cuts, and suppresses
the game's pink wound and blood surfaces. It also darkens the game's blood
emitters, bounds visible splats, and provides a short gravity-influenced
impact spray and LOW/MED/HIGH quality switch. The
[asset pipeline](ASSET_PIPELINE.md) explains the source meshes and the
current client-side rendering limits.
