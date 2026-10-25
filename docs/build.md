# Build and release

## Requirements

Build on Windows with Git, Python with pip, and the .NET Framework C# compiler
(`csc.exe`, included with Windows). The build script downloads the pinned dependencies,
including the Zig compiler used for the save/load mod's native DLL.

Run the commands below from the repository root.

## Local build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build.ps1 -Version 1.0.4
```

Use the version you intend to build. The package is written to
`dist/StarlitSeasonMods-<version>.zip`.

## Dependencies

[deps.json](../deps.json) records the dependency versions and the AUTO mod's source commit:

- UE4SS 3.0.1-1170 and SmokeAPI 4.1.3 downloads are checked against SHA-256 hashes.
- UE4SS is mirrored in this repository's `deps-ue4ss-3.0.1-1170` release because the
  upstream `experimental-latest` release no longer provides that file.
- TextAutoToggle is checked out at a pinned commit from its separate repository.
  Update that commit in `deps.json` when including an AUTO fix in the mod pack.
- Zig is installed at the pinned version to compile the native save/load helper.

## Publish a release

Only the maintainer decides when to release; agents must not tag or publish on their own
(see [AGENTS.md](../AGENTS.md)).

1. Write the version's changes in `.github/releases/<version>.md`.
2. Commit and push the intended changes, including any dependency updates and the
   release notes.
3. Push a matching `v<version>` Git tag at that commit.
4. Wait for the [release workflow](../.github/workflows/release.yml) to complete.

The workflow checks that the version's release notes exist, builds the package on
Windows, uploads a workflow artifact, and publishes a GitHub Release with the ZIP.
The release body is the version's notes exactly as written.

Download the published ZIP and verify its contents and checksum. Confirm that its
AUTO script matches the pinned commit and that local experimental mods, logs, and
save files are absent.

The workflow can also be started manually with a test version. Manual runs upload
a build artifact without publishing a release.
