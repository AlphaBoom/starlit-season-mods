# Choice result hints / 选项结果提示

Optional dialogue spoilers for Starlit Season Steam v1.61 and UE4SS.

When the visible choices lead to different confirmed evaluations, the mod adds a second line such as
`[PERFECT]`, `[GOOD]`, `[NORMAL]` or `[BAD]` under each choice. It matches the localized choice text,
so shuffled button positions do not change the association. The timer, input and actual results remain native.

默认关闭。在管理器中开启“选项结果提示”，或将 `ue4ss/Mods/mods.txt` 中的 `ChoiceHints : 0` 改为
`ChoiceHints : 1`，重启游戏生效。本机开发环境单独保持 `ChoiceHints : 1`；发布配置始终为 0。

## Coverage

Reads the currently loaded `MD_CommuScript` and localization tables. Follows `selectButton` / `select`,
`if` / `elseIf` / `else` / `endIf` and label jumps until the native `uiResult` command.
Only conditions on the current `select` value with `==` / `!=` are resolved. Unknown conditions,
missing labels, cycles, ambiguous text, incomplete groups, identical evaluations and further choices suppress hints.
This version previews the game's explicit evaluation, not arbitrary plot consequences, hidden flags or exact rewards.
No script rows, variables, choices or save data are changed. Text is restored when the selection ends.

`Scripts/analyze.lua` is a pure analyzer; `Scripts/main.lua` applies the display on the game thread.
Log: `ue4ss/UE4SS.log`, search `[ChoiceHints]`.

## Verification

Tested in game with `CM_idolchr_0101_A_04_00`: the three randomized choices show their actual PERFECT / GOOD /
NORMAL evaluations. The script's label branches and final `uiResult` commands agree with those annotations.
The analyzer tests cover divergent and identical results, unknown conditions, missing targets, cycles,
localized/shuffled choices and ambiguity.
