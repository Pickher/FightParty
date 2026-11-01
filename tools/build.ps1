# 中文导读：Windows PowerShell 打包脚本，普通学习/试玩只要在 Godot 按 F5。
# Godot 参数要填写 Godot 控制台版 exe 的完整路径；-SkipAndroid 表示暂时只构建电脑版本。
# 每个阶段检查上一条外部命令的退出码；出现错误就停止，不把失败构建当作成功交付。
param(
    [Parameter(Mandatory=$true)][string]$Godot,
    [string]$OutputDirectory = "$PSScriptRoot/../build",
    [switch]$SkipAndroid
)
$ErrorActionPreference = 'Stop'
# 以脚本所在目录为基准寻找工程，不要求用户先切换到某个工作目录。
$projectPath = (Resolve-Path "$PSScriptRoot/..").Path
New-Item -ItemType Directory -Force "$OutputDirectory/windows" | Out-Null
$outputPath = (Resolve-Path $OutputDirectory).Path
# 先导入资源，生成 Godot 需要的本地缓存；--headless 表示不打开画面。
& $Godot --headless --path $projectPath --editor --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Resource import failed' }
# 打包前运行规则测试，失败会中止构建。
& $Godot --headless --path $projectPath --script res://tests/test_sim.gd
if ($LASTEXITCODE -ne 0) { throw 'Simulation tests failed' }
# 根据 export_presets.cfg 的 Windows Desktop 预设导出独立 EXE。
& $Godot --headless --path $projectPath --export-release 'Windows Desktop' "$outputPath/windows/FightParty.exe"
if ($LASTEXITCODE -ne 0) { throw 'Windows export failed' }
# 安卓打包需要事先配置 Java SDK、Android SDK 和对应版本导出模板。
if (-not $SkipAndroid) {
    & $Godot --headless --path $projectPath --export-debug Android "$outputPath/FightParty-android-test.apk"
    if ($LASTEXITCODE -ne 0) { throw 'Android export failed' }
}
# 将 Windows 产物压缩，最后输出 SHA256 哈希，便于核对下载文件是否完整。
Compress-Archive -Path "$outputPath/windows/*" -DestinationPath "$outputPath/FightParty-Windows.zip" -Force
Get-ChildItem -LiteralPath $outputPath -File | Get-FileHash -Algorithm SHA256
