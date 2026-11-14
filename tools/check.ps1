# 中文导读：一条命令跑完全部自动测试：资源导入、规则模拟、兵种编辑器、界面冒烟、战报重放、Excel 导入器与兵种总表同步检查。
# 用法：powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Godot 'C:\Godot\Godot_v4.7.2-stable_win64_console.exe' [-Perf]
# 也可先设置环境变量 GODOT。-Perf 额外运行 crowd_perf（满兵营 3 波，约 3 分钟）与 render_perf（打开渲染窗口采样 10 秒）。
# 每项日志写到 build\check-logs\；ui_smoke 会覆盖本机 user:// 下的最近阵容与战报，replay 随后重放这份战报。
param(
    [string]$Godot = $env:GODOT,
    [string]$Python = $env:PYTHON,
    [switch]$Perf
)
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path "$PSScriptRoot/..").Path
$logs = Join-Path $projectPath 'build/check-logs'
New-Item -ItemType Directory -Force $logs | Out-Null
if (-not $Godot) { throw '找不到 Godot：请用 -Godot 传入 Godot 控制台版 exe 路径，或设置环境变量 GODOT。' }
$pythonArgs = @()
if (-not $Python) {
    if (Get-Command python -ErrorAction SilentlyContinue) { $Python = 'python' }
    elseif (Get-Command py -ErrorAction SilentlyContinue) { $Python = 'py'; $pythonArgs = @('-3') }
    else { throw '找不到 Python 3：请用 -Python 传入路径，或设置环境变量 PYTHON。' }
}
$failed = @()

# Godot 的 --script 运行时错误不一定改变退出码，所以同时检查日志里的错误与失败标记。
function Invoke-Suite([string]$Name, [int]$TimeoutSeconds, [string]$File, [string[]]$Arguments) {
    $log = Join-Path $logs "$Name.log"
    $errorLog = Join-Path $logs "$Name.err.log"
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $quoted = $Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
    $process = Start-Process -FilePath $File -ArgumentList $quoted -WorkingDirectory $projectPath -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError $errorLog
    $null = $process.Handle
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill()
        Write-Host ('{0,-17} TIMEOUT ({1}s)  {2}' -f $Name, $TimeoutSeconds, $log)
        $script:failed += $Name
        return
    }
    $process.WaitForExit()
    $text = ((Get-Content -Raw $log -ErrorAction SilentlyContinue), (Get-Content -Raw $errorLog -ErrorAction SilentlyContinue)) -join "`n"
    $seconds = [int]$watch.Elapsed.TotalSeconds
    if ($process.ExitCode -ne 0 -or $text -match '(?m)SCRIPT ERROR|^(UI )?FAIL') {
        Write-Host ('{0,-17} FAIL ({1}s)  {2}' -f $Name, $seconds, $log)
        ($text -split "`n" | Where-Object { $_ -match 'SCRIPT ERROR|^(UI )?FAIL|Error' } | Select-Object -First 8) | ForEach-Object { Write-Host "    $_" }
        $script:failed += $Name
    } else {
        $summary = ($text -split "`n" | Where-Object { $_ -match '^(RESULT|UI SMOKE|REPLAY|Unit editor|CROWD|RENDER PERF|Ran |OK)' } | Select-Object -Last 1)
        Write-Host ('{0,-17} ok ({1}s)  {2}' -f $Name, $seconds, $summary)
    }
}

Invoke-Suite 'import' 600 $Godot @('--headless', '--path', $projectPath, '--editor', '--import', '--quit')
Invoke-Suite 'test_sim' 900 $Godot @('--headless', '--path', $projectPath, '--script', 'res://tests/test_sim.gd')
Invoke-Suite 'unit_editor' 300 $Godot @('--headless', '--path', $projectPath, '--script', 'res://tests/test_unit_editor.gd')
Invoke-Suite 'ui_smoke' 600 $Godot @('--headless', '--path', $projectPath, '--script', 'res://tests/ui_smoke.gd')
Invoke-Suite 'replay' 600 $Godot @('--headless', '--path', $projectPath, '--script', 'res://tests/replay.gd')
Invoke-Suite 'importer' 300 $Python ($pythonArgs + @('-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py'))
Invoke-Suite 'unit_table' 60 $Python ($pythonArgs + @('tools/unit_table.py', '--check'))
if ($Perf) {
    Invoke-Suite 'crowd_perf' 900 $Godot @('--headless', '--path', $projectPath, '--script', 'res://tests/crowd_perf.gd')
    Invoke-Suite 'render_perf' 300 $Godot @('--path', $projectPath, '--script', 'res://tests/render_perf.gd')
}

if ($failed.Count -gt 0) {
    Write-Host "CHECK: FAIL ($($failed -join ', '))"
    exit 1
}
Write-Host 'CHECK: PASS'
