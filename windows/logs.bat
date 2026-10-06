@echo off
setlocal EnableExtensions
cd /d "%~dp0"
chcp 65001 >nul

echo SimpleTuner のログです。止めるときは Ctrl+C を押してください。
echo.

docker info >nul 2>&1
if errorlevel 1 goto docker_down

docker compose ps --status running --services | findstr /I /X "simpletuner" >nul
if errorlevel 1 goto not_running

cmd /c "docker compose logs -f --tail 200"
echo.
echo ログの表示を終わりました。
echo 何かキーを押すと閉じます。
pause >nul
exit /b 0

:docker_down
echo 失敗: Docker が動いていません。
echo 直し方: Docker Desktop を起動してから、もう一度 logs.bat を実行してください。
goto fail

:not_running
echo 失敗: SimpleTuner は動いていません。
echo 直し方: 先に start.bat を実行してください。
goto fail

:fail
echo.
echo 何かキーを押すと閉じます。
pause >nul
exit /b 1
