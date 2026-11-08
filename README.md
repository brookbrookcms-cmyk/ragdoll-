# Ragdoll Physics visual scripts

The latest version is [`blood-visuals-v15.lua`](blood-visuals-v15.lua). It is a
client-side Delta script with a small ON/OFF switch. It detects the game's
`WoundMark` effects and cuts the corresponding NPC2 R15 body mesh. A single
shot makes a small opening; grouped hits make wider openings. Bone and muscle
structures are loaded for the wounded part and exposed within the cut.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/brookbrookcms-cmyk/ragdoll-/main/blood-visuals-v15.lua"))()
```

Delta needs `writefile` and `getcustomasset` (or `getsynasset`) to load the
mesh and texture files. The first hit to a body region may take a moment while
its assets download. ON/OFF restores the original body appearance.

The anatomy mesh provenance and license are in
[`ANATOMY_ATTRIBUTION.md`](ANATOMY_ATTRIBUTION.md). `v10-anatomy-manifest.json`
lists the 206 anatomical bones and all other adapted structures. The game's
private head mesh cannot be downloaded, so damaged heads use a rounded
replacement mesh sized to the reported NPC head. The replacement may not
match every custom head texture exactly. The anatomy is location-specific
geometry, not 206 separately simulated rigid bones. This is a visual script
and does not change the game's hit detection or damage.
