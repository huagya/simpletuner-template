@echo off
setlocal EnableExtensions
cd /d "%~dp0"
chcp 65001 >nul

echo SimpleTuner を止めます。モデルと学習結果は残します。
echo.

docker info >nul 2>&1
if errorlevel 1 goto docker_down

docker compose down
if errorlevel 1 goto fail

echo 止めました。
echo データは Docker のボリューム stt-data と、このフォルダの datasets に残っています。
echo.
echo 何かキーを押すと閉じます。
pause >nul
exit /b 0

:docker_down
echo 失敗: Docker が動いていません。
echo 直し方: Docker Desktop を起動してから、もう一度 stop.bat を実行してください。
goto fail

:fail
echo 失敗: 停止できませんでした。
echo 直し方: Docker Desktop が Running か確認してください。データ用ボリュームは消していません。
echo.
echo 何かキーを押すと閉じます。
pause >nul
exit /b 1
