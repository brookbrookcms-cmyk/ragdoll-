# Ragdoll Physics visual scripts

The latest version is [`blood-visuals-v10.lua`](blood-visuals-v10.lua). It is a
client-side Delta script with a small ON/OFF switch. It detects the game's
`WoundMark` effects and fits a small 3D opening to the corresponding NPC2 R15
body mesh. Bone and muscle structures are loaded only for the wounded part.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/brookbrookcms-cmyk/ragdoll-/main/blood-visuals-v10.lua"))()
```

Delta needs `writefile` and `getcustomasset` (or `getsynasset`) to load the
mesh and texture files. The first hit to a body region may take a moment while
its assets download. ON/OFF restores the original body appearance.

The anatomy mesh provenance and license are in
[`ANATOMY_ATTRIBUTION.md`](ANATOMY_ATTRIBUTION.md). `v10-anatomy-manifest.json`
lists the 206 anatomical bones and all other adapted structures. The private
head mesh cannot be downloaded, so head hits use a small 3D skull fragment on
the original head; other body regions use body-fitted openings. This is a
visual script and does not change the game's hit detection or damage.
