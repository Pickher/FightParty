@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
if not exist "engine\Godot_v4.7.2-stable_win64_console.exe" goto missing
if not exist "engine\Godot_v4.7.2-stable_win64.exe" goto missing
if not exist "project.godot" goto missing
if not exist "logs" mkdir "logs"
echo 正在准备游戏资源，首次启动请耐心等待。无需打开 Godot 编辑器。
"engine\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --editor --import --quit > "logs\资源准备.log" 2>&1
if errorlevel 1 goto import_failed
echo 游戏即将打开。进入后先配置兵种，再点“开始准备”。
echo 请保留此窗口，退出游戏后它会自动关闭。
"engine\Godot_v4.7.2-stable_win64_console.exe" --path . %* > "logs\游戏运行.log" 2>&1
if errorlevel 1 goto game_failed
exit /b 0
:missing
echo 文件不完整。请右键 ZIP 选择“全部解压”，不要直接在压缩包里运行。
echo 请保留 engine 文件夹、project.godot 以及其他游戏文件。
pause
exit /b 1
:import_failed
echo 资源准备失败。请将 logs\资源准备.log 发给项目负责人。
pause
exit /b 1
:game_failed
echo 游戏运行失败。请将 logs\游戏运行.log 发给项目负责人。
pause
exit /b 1
