param(
    [Parameter(Mandatory=$true)][string]$Godot,
    [string]$OutputDirectory = "$PSScriptRoot/../build",
    [switch]$SkipAndroid
)
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path "$PSScriptRoot/..").Path
New-Item -ItemType Directory -Force "$OutputDirectory/windows" | Out-Null
$outputPath = (Resolve-Path $OutputDirectory).Path
& $Godot --headless --path $projectPath --editor --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Resource import failed' }
& $Godot --headless --path $projectPath --script res://tests/test_sim.gd
if ($LASTEXITCODE -ne 0) { throw 'Simulation tests failed' }
& $Godot --headless --path $projectPath --export-release 'Windows Desktop' "$outputPath/windows/FightParty.exe"
if ($LASTEXITCODE -ne 0) { throw 'Windows export failed' }
if (-not $SkipAndroid) {
    & $Godot --headless --path $projectPath --export-debug Android "$outputPath/FightParty-android-test.apk"
    if ($LASTEXITCODE -ne 0) { throw 'Android export failed' }
}
Compress-Archive -Path "$outputPath/windows/*" -DestinationPath "$outputPath/FightParty-Windows.zip" -Force
Get-ChildItem -LiteralPath $outputPath -File | Get-FileHash -Algorithm SHA256
