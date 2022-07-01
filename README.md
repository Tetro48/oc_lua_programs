Tetro48's OpenComputers programs
================================

List of programs (May not work in MineOS):

- clockt - Literally a clone of someone else's code showcasing the difference between different timing techniques.
- executeautobuild - It'll build a 3x3 cube with the intent to be used with Compact Machines mod. This MUST be executed on a robot with inventory.
- executeautobuildcompactwalls - It'll build a structure of iron block with redstone dust on top and then throwing redstone into it. This MUST be executed on a robot with inventory.
- oc_tetra - A block-stacking OpenOS game with frame-independent timer. Its called "OC Tetra", short for "OpenComputers Tetra".
- oc_tgm3_shi - Based upon "OC Tetra", with the goal of trying to imitate TGM3's Shirase mode in gameplay. This has accuracy and speed issues plaguing this. Once again, does not depend on frames taking the same amount of time.
- truthmachine - You know what it is if you're in the community of esoteric languages.

ExecuteAutoBuild structure showcase to avoid trying to figure it out yourself the hard way:

- [R] - robot
- [C] - center block chest
- [O] - outside block chest
- [D] - catalyst chest
- [I] - iron block chest

Chests must be separated, or else it won't work.

```
[I][R][D][C][O]
```