# Notes for coding agents

## Releases

- **Never publish a release on your own.** Do not push a `v*` tag, start the release workflow with a version, or
  create / edit a GitHub Release unless the maintainer explicitly asks for that specific version in the current
  conversation. A pushed `v*` tag publishes immediately ([release workflow](.github/workflows/release.yml)).
- Finishing a feature or fix, merging it, or pushing `main` is not a request to release. Several changes are
  normally collected, played and checked by the maintainer before one release.
- When a change is ready, say what a release would contain and leave it unreleased. Draft notes may go in
  `.github/releases/<version>.md` but stay user-facing: no test logs or development history.
- To check packaging, run `scripts/build.ps1` locally with a test version (for example `0.0.0-test`) and delete the
  test zip afterwards. The full procedure is in [docs/build.md](docs/build.md).

## Keeping a change complete

A user-visible change also updates, in the same commit:

- `README.md` and `README_zh.md` (the mod table and the Features section, in both languages);
- the mod's own `mods/<Mod>/README.md` (English, like the other mod READMEs);
- the manager card text in `manager/StarlitMods.cs` (Chinese and English) when a mod is added or its behaviour
  changes, and `scripts/build.ps1` / `ue4ss/mods.txt` when files or mods are added.

Optional mods ship disabled (`<Mod> : 0` in `ue4ss/mods.txt`). Experimental or diagnostic mods stay out of the
repository and the package; keep them local (for example under the game folder's `.codex-tools`).

## Testing in the game

Steam v1.61 with UE4SS 3.0.1-1170. Back up `%LOCALAPPDATA%\StarlitSeason\Saved\SaveGames\<steamid>` before
loading any save and restore it afterwards (loading autosaves over AUTO; Steam Cloud keeps the newer copy, so give
restored files a current modification time). Never confirm NEW PRODUCE on the title screen.
