# Builds the release package: extract it into the game root (the folder with StarlitSeason.exe).
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build.ps1 -Version 1.0.0
# Requires: Windows, .NET Framework csc (built in), Python with pip (for the pinned Zig compiler), git.
[CmdletBinding()]
param([string]$Version = '0.0.0-dev')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$deps = Get-Content -LiteralPath (Join-Path $repo 'deps.json') -Raw | ConvertFrom-Json
$cache = Join-Path $repo '.cache'
$build = Join-Path $repo 'build'
$dist = Join-Path $repo 'dist'
foreach ($d in @($cache, $build, $dist)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
if (Test-Path -LiteralPath (Join-Path $build 'stage')) { Remove-Item -LiteralPath (Join-Path $build 'stage') -Recurse -Force }

function Get-Pinned([string]$Url, [string]$Sha, [string]$Name) {
    $file = Join-Path $cache $Name
    if (!(Test-Path -LiteralPath $file)) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Url -OutFile $file -UseBasicParsing
    }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $Sha) {
        Remove-Item -LiteralPath $file
        throw "Checksum mismatch: $Name"
    }
    $out = Join-Path $build ([IO.Path]::GetFileNameWithoutExtension($Name))
    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
    Expand-Archive -LiteralPath $file -DestinationPath $out
    return $out
}
function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed with exit code $LASTEXITCODE" }
}

$ue4ss = Get-Pinned $deps.ue4ss.url $deps.ue4ss.sha256 "UE4SS_$($deps.ue4ss.version).zip"
$smoke = Get-Pinned $deps.smokeApi.url $deps.smokeApi.sha256 "SmokeAPI-v$($deps.smokeApi.version).zip"

# TextAutoToggle is maintained in its own repository; take its mod files at a pinned commit.
$auto = Join-Path $build 'text-auto-toggle'
if (!(Test-Path -LiteralPath (Join-Path $auto '.git'))) {
    Invoke-Checked 'git' @('clone', '--quiet', "https://github.com/$($deps.textAutoToggle.repository).git", $auto)
}
Invoke-Checked 'git' @('-C', $auto, 'fetch', '--quiet', 'origin')
Invoke-Checked 'git' @('-C', $auto, 'checkout', '--quiet', $deps.textAutoToggle.commit)

# Native helper for the save/load mod.
$zig = Join-Path $build 'zig'
if (!(Test-Path -LiteralPath (Join-Path $zig 'ziglang\zig.exe'))) {
    Invoke-Checked 'python' @('-m', 'pip', 'install', '--quiet', '--disable-pip-version-check', '--target', $zig, "ziglang==$($deps.zig)")
}
$nativeDll = Join-Path $build 'DialogueMenu.dll'
Invoke-Checked (Join-Path $zig 'ziglang\zig.exe') @('cc', '-target', 'x86_64-windows-gnu', '-shared', '-O2', '-nostdlib',
    '-fno-stack-protector', '-o', $nativeDll, (Join-Path $repo 'mods\DialogueMenu\native\dialogue-menu-native.c'),
    '-lkernel32', '-Wl,--entry=DllMain')

# Manager.
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$managerExe = Join-Path $build 'StarlitMods.exe'
Invoke-Checked $csc @('/nologo', '/target:winexe', '/codepage:65001', '/optimize+', "/out:$managerExe",
    '/r:System.Web.Extensions.dll', '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll',
    (Join-Path $repo 'manager\StarlitMods.cs'))

# Stage the game-root layout.
$stage = Join-Path $build 'stage'
$bin = 'StarlitSeason/Binaries/Win64'
$files = [ordered]@{}
function Add-File([string]$Source, [string]$Relative) { $script:files[$Relative] = $Source }
Add-File (Join-Path $ue4ss 'dwmapi.dll') "$bin/dwmapi.dll"
Add-File (Join-Path $ue4ss 'ue4ss\UE4SS.dll') "$bin/ue4ss/UE4SS.dll"
Add-File (Join-Path $ue4ss 'ue4ss\LICENSE') "$bin/ue4ss/LICENSE"
Add-File (Join-Path $ue4ss 'ue4ss\UE4SS_SDK_Backends\UE4SS.json') "$bin/ue4ss/UE4SS_SDK_Backends/UE4SS.json"
Add-File (Join-Path $ue4ss 'ue4ss\Mods\shared\UEHelpers\UEHelpers.lua') "$bin/ue4ss/Mods/shared/UEHelpers/UEHelpers.lua"
Add-File (Join-Path $repo 'ue4ss\UE4SS-settings.ini') "$bin/ue4ss/UE4SS-settings.ini"
Add-File (Join-Path $repo 'ue4ss\mods.txt') "$bin/ue4ss/Mods/mods.txt"
Get-ChildItem -LiteralPath (Join-Path $auto 'mod\ue4ss') -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring((Join-Path $auto 'mod\ue4ss').Length + 1).Replace('\', '/')
    Add-File $_.FullName "$bin/ue4ss/$rel"
}
Add-File (Join-Path $repo 'mods\DialogueMenu\Scripts\main.lua') "$bin/ue4ss/Mods/DialogueMenu/Scripts/main.lua"
Add-File (Join-Path $repo 'mods\DialogueMenu\README.md') "$bin/ue4ss/Mods/DialogueMenu/README.md"
Add-File $nativeDll "$bin/ue4ss/Mods/DialogueMenu/DialogueMenu.dll"
foreach ($name in @('Scripts/main.lua', 'durations.tsv', 'README.md')) {
    Add-File (Join-Path $repo "mods/VoiceWatchdog/$name") "$bin/ue4ss/Mods/VoiceWatchdog/$name"
}

$manifestFiles = @()
foreach ($rel in $files.Keys) {
    foreach ($root in @($stage, (Join-Path $stage 'StarlitModsData\payload'))) {
        $dest = Join-Path $root $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
        Copy-Item -LiteralPath $files[$rel] -Destination $dest
    }
    $manifestFiles += [ordered]@{ Path = $rel; Sha256 = (Get-FileHash -LiteralPath $files[$rel] -Algorithm SHA256).Hash }
}
$payloadDlc = Join-Path $stage 'StarlitModsData\payload\dlc'
New-Item -ItemType Directory -Path $payloadDlc -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $smoke 'smoke_api64.dll') -Destination $payloadDlc
Copy-Item -LiteralPath (Join-Path $repo 'dlc\SmokeAPI.config.json') -Destination $payloadDlc
$licenses = Join-Path $stage 'StarlitModsData\licenses'
New-Item -ItemType Directory -Path $licenses -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination (Join-Path $licenses 'StarlitMods-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $ue4ss 'ue4ss\LICENSE') -Destination (Join-Path $licenses 'UE4SS-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $auto 'LICENSE') -Destination (Join-Path $licenses 'TextAutoToggle-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $smoke 'README.txt') -Destination (Join-Path $licenses 'SmokeAPI-README.txt')
Set-Content -LiteralPath (Join-Path $licenses 'SmokeAPI-LICENSE.txt') -Value 'SmokeAPI by acidicoala is released under The Unlicense: https://github.com/acidicoala/SmokeAPI' -Encoding ASCII

$manifest = [ordered]@{
    Version = $Version
    GameExeSha256 = $deps.gameExeSha256
    SmokeSha256 = (Get-FileHash -LiteralPath (Join-Path $smoke 'smoke_api64.dll') -Algorithm SHA256).Hash
    Files = $manifestFiles
}
[IO.File]::WriteAllText((Join-Path $stage 'StarlitModsData\manifest.json'), ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath $managerExe -Destination (Join-Path $stage 'StarlitMods.exe')

$zip = Join-Path $dist "StarlitSeasonMods-$Version.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
# Explicit entry names: .NET Framework would otherwise store backslash separators.
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName | ForEach-Object {
        $name = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $name, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose() }
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
Write-Output "Built $zip"
Write-Output "SHA-256 $hash"
