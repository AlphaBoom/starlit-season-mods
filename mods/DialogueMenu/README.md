# Save / load in dialogue (DialogueMenu)

Windows Steam v1.61 only, loaded by UE4SS 3.0.1-1170.

## Features

- The dialogue menu (Esc / gamepad menu button) gets **SAVE / LOAD** above 戻る (Back). They open the game's own
  save / load screens; when you return, the menu is left as it was, cursor on the same item.
  The buttons use the game's button widget, cursor sound and keyboard / gamepad / mouse handling.
- A separate **QUICK** slot shown under AUTO. It never overwrites AUTO or slots 01–15.
- In a dialogue, **F5** saves to QUICK and **F6** loads QUICK, also while the dialogue menu is open.
- QUICK also appears on the game's other save / load screens (title LOAD, SYSTEM menu).

### Where a dialogue save resumes

A manual save inside a dialogue would normally resume at the start of the current phase's previous step
(for example PRODUCE TIME while the dialogue is in FREE TIME). The game takes an AUTO checkpoint when a dialogue starts,
which is the latest point the game can resume from. Saves made from a dialogue (menu SAVE or F5) therefore store a copy
of that checkpoint in the chosen slot. Dialogue progress inside the scene itself cannot be saved by the game.

## Implementation

- `Scripts/main.lua`: menu buttons, QUICK row (inserted below AUTO, tinted, labelled QS), navigation order
  AUTO → QUICK → 01 …, F5 / F6, and returning to the dialogue menu. All Unreal calls run on one game-thread timer or in hooks.
- `native/dialogue-menu-native.c` → `DialogueMenu.dll`:
  - opens the game's save / load screen over a dialogue and pauses / resumes the dialogue;
  - restores the dialogue's pause state and input mode when that screen closes (it clears them);
  - saves live in `MasterSaveData.GameSaveDataObjects` keyed by name (`slot0` = AUTO, `slot1`–`slot15`).
    The DLL appends `slotQuick` (index 16) to the game's slot-name table and adds a native slot row, so the QUICK slot's
    display, saving, loading and overwrite prompts all run through the game's own code and live in `MasterSave.sav`;
  - after a save made from a dialogue, stores the AUTO checkpoint under that slot through the game's own save function.
  - Every native entry point is checked against its first bytes before use; a different game build is refused.
- After uninstalling, the `slotQuick` entry stays in the save file; the game ignores it and other saves are unaffected.

Log: `ue4ss/UE4SS.log`, search for `[DialogueMenu]`.
