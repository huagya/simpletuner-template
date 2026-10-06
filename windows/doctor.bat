@echo off
setlocal EnableExtensions
cd /d "%~dp0"
chcp 65001 >nul

echo SimpleTuner の自己診断（stt-doctor）を実行します。
echo.

docker info >nul 2>&1
if errorlevel 1 goto docker_down

docker compose ps --status running --services | findstr /I /X "simpletuner" >nul
if errorlevel 1 goto not_running

docker compose exec simpletuner stt-doctor
set "STT_DOC=%ERRORLEVEL%"
echo.
echo 診断 zip の場所: コンテナの /workspace/diagnostics
echo 取り出し方: ブラウザで http://127.0.0.1:8888 を開きます。
echo ユーザー名は admin。パスワードは %CD%\.env の WEB_PASSWORD です。
echo 左の diagnostics フォルダを開き、stt-diag で始まる zip を右クリックして Download してください。
if not "%STT_DOC%"=="0" goto doctor_fail
echo.
echo 診断は FAIL なしで終わりました。WARN がある場合は、その行の日本語を読んでください。
echo 何かキーを押すと閉じます。
pause >nul
exit /b 0

:docker_down
echo 失敗: Docker が動いていません。
echo 直し方: Docker Desktop を起動してから、もう一度 doctor.bat を実行してください。
goto fail

:not_running
echo 失敗: SimpleTuner は動いていません。
echo 直し方: 先に start.bat を実行してください。
goto fail

:doctor_fail
echo 失敗: 上に FAIL があります。各行の日本語が直し方です。
echo zip は失敗したときも作られます。上の手順でダウンロードして送ってください。
goto fail

:fail
echo.
echo 何かキーを押すと閉じます。
pause >nul
exit /b 1
