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
    echo 请先安装 Python 3.8 或以上版本，并启用 Add Python to PATH。
    pause
    exit /b 1
  )
  python tools\import_units.py %*
)
set "import_result=%errorlevel%"
echo.
if "%import_result%"=="0" (echo 已完成。可以重新打开游戏查看数值。) else (echo 未导入，请根据上方错误修改 Excel 后重试。)
pause
exit /b %import_result%