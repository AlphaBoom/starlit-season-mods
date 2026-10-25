# Choice result hints (ChoiceHints)

Windows Steam v1.61 only, loaded by UE4SS 3.0.1-1170. Off by default; turn it on in the manager, or set
`ChoiceHints : 1` in `ue4ss/Mods/mods.txt` and restart the game.

## Features

- When the choices on screen lead to different evaluations, each choice gets a coloured label
  (**PERFECT** / **GOOD** / **NORMAL** / **BAD**) on the top edge of its plate.
- The label is a separate widget on the choice plate; the choice text, its wrapping and the plate layout are not
  changed, so long choices do not overlap.
- Labels follow the matching text, so they stay correct when the game shuffles the choice positions.
- The labels never take input; the timer, the selection and the result stay native.

## Coverage

Only evaluations the script makes certain are shown. The mod reads the dialogue's loaded `MD_CommuScript` table and
its localization tables and follows `selectButton` / `select`, `if` / `elseIf` / `else` / `endIf` and label jumps up
to the native `uiResult` command. Only conditions on the current `select` value with `==` / `!=` are resolved.

Nothing is shown when a condition is unknown, a label is missing, the branches loop, a further choice comes first,
all choices give the same evaluation, or the on-screen text cannot be matched to one choice unambiguously.
It previews the game's explicit evaluation only, not other plot consequences, hidden flags or exact rewards.
No script rows, variables, choices or save data are changed; the labels are removed when the choice closes.

## Implementation

- `Scripts/analyze.lua`: pure script analysis (choice groups, branch resolution, text matching).
- `Scripts/main.lua`: finds the active choice widget on a game-thread timer and adds or removes the labels.
- Log: `ue4ss/UE4SS.log`, lines starting with `[ChoiceHints]`.
- Tests: `tests/choice-hints.lua` (run from the repository root with Lua 5.4) covers differing and equal results,
  unknown conditions, missing targets, cycles, shuffled localized choices and ambiguous text.
