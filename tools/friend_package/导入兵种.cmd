@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
  py -3 tools\import_units.py %*
) else (
  where python >nul 2>nul
  if errorlevel 1 (
    echo 未找到 Python。请安装 Python 3.13.x 标准版 64 位。
    echo 安装时勾选 Add python.exe to PATH。详见“先读我-运行与兵种调试.txt”。
    pause
    exit /b 1
  )
  python tools\import_units.py %*
)
set "import_result=%errorlevel%"
echo.
if "%import_result%"=="0" (echo 已完成。请双击“开始游戏.cmd”重新启动游戏。) else (echo 未导入。请截图上方错误，或参照说明修正后重试。)
pause
exit /b %import_result%
