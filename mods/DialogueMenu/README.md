# Save / load enhancement (DialogueMenu)

Windows Steam v1.61 only, loaded by UE4SS 3.0.1-1170.

## Features

- The dialogue menu (Esc / gamepad menu button) gets **SAVE / LOAD** above 戻る (Back). They open the game's own
  save / load screens and use the game's button widget, cursor sound and keyboard / gamepad / mouse handling.
- A separate **QUICK** slot under AUTO, shown in the game's gold row style. It never overwrites AUTO or slots 01–15.
- **F5** saves to QUICK, **F6** loads QUICK:
  - in a dialogue (also while the dialogue menu is open);
  - on the home and map screens, through the game's SYSTEM menu, so the game decides whether saving is allowed there.
- QUICK also appears on the game's other save / load screens (title LOAD, SYSTEM menu).
- A save made during a dialogue resumes from the checkpoint the game takes when the dialogue starts
  (progress inside the scene itself cannot be saved by the game).

## Implementation

- `Scripts/main.lua`: menu buttons, QUICK row (inserted below AUTO, labelled QS, using the row style switch the game
  uses for its own rows), navigation order AUTO → QUICK → 01 …, and F5 / F6.
  Outside a dialogue, F5 / F6 call the scene's own SYSTEM button (`OnClickedSystem` / `OnClickSystem`), choose
  セーブ / ロード in the SYSTEM menu (`OnClickedCursor`), pick QUICK, and close the menu with its `OnCancel`.
  All Unreal calls run on one game-thread timer or in hooks.
  The added pause buttons register their HitAreaWidget with an independent native HitAreaChecker and handle
  hover/click callbacks on the game thread. This binds the dynamically created buttons without dispatching
  the original pause menu's Skip/Back actions or depending on controller mouse-key polling.
- `native/dialogue-menu-native.c` → `DialogueMenu.dll`:
  - opens the game's save / load screen over a dialogue and pauses / resumes the dialogue, restoring its pause state
    and input mode when that screen closes;
  - saves live in `MasterSaveData.GameSaveDataObjects` keyed by name (`slot0` = AUTO, `slot1`–`slot15`).
    The DLL appends `slotQuick` (index 16) to the game's slot-name table and adds a native slot row, so the QUICK slot's
    display, saving, loading and overwrite prompts all run through the game's own code and live in `MasterSave.sav`;
  - after a save made from a dialogue, stores the dialogue's start checkpoint under that slot through the game's own
    save function.
  - Every native entry point is checked against its first bytes before use; a different game build is refused.
- After uninstalling, the `slotQuick` entry stays in the save file; the game ignores it and other saves are unaffected.

Log: `ue4ss/UE4SS.log`, search for `[DialogueMenu]`.
