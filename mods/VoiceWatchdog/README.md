# Stuck voice fix (VoiceWatchdog) — experimental

Windows Steam v1.61 only, loaded by UE4SS 3.0.1-1170. Off by default; turn it on in the manager.

## The problem

Now and then a dialogue line's voice never starts: its CRI player stays in the *Prep* state, so the line is silent
and the dialogue keeps waiting for the voice to finish, which also stops auto-advance. It happens in several kinds of
scenes and most often in WORK dialogues. It also happens with every other mod turned off, and it comes and goes with
the state of the machine, so its exact trigger is not known.

## What the mod does

Every 250 ms it checks the voices of the running dialogues (through `CommuScriptSound._VoiceList`). A voice that has
been in Prep for 1 s, while the game is not paused, is handled in steps:

1. pause and resume it (the same thing a window focus change does);
2. restart it, at most twice. A restarted voice does not end by itself, so it is stopped when it reaches the cue's
   length from `durations.tsv`;
3. if it still does not start, stop it, so the dialogue goes on without that line's voice.

Normal voices leave Prep within about 0.2 s and are never touched. Each step is written to `watchdog.log` in this
folder; please include that file when reporting a problem.

`durations.tsv` holds the length of every cue in `CueSheet_Voice` for v1.61. It is made by
`scripts/voice-durations.py`, which reads the cue sheet from the running game.

## Tests

`tests/simulate.py` runs the script against mocked UE4SS objects (Python with `lupa`) and covers the cases above.
