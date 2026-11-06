@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not exist "data\兵种配置.xlsx" (
  echo 找不到 data\兵种配置.xlsx，请重新完整解压。
  pause
  exit /b 1
)
start "" "%~dp0data\兵种配置.xlsx"
