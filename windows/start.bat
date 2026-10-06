@echo off
setlocal EnableExtensions
cd /d "%~dp0"
chcp 65001 >nul

echo SimpleTuner を起動します。
echo.

set "GHCR_IMAGE=ghcr.io/huagya/simpletuner-template"
set "IMAGE_TAG=v0.1.0"
if exist "%~dp0..\versions.env" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~dp0..\versions.env") do (
    if /I "%%A"=="GHCR_IMAGE" set "GHCR_IMAGE=%%B"
    if /I "%%A"=="IMAGE_TAG" set "IMAGE_TAG=%%B"
  )
)

docker info >nul 2>&1
if errorlevel 1 goto docker_down

for /f "delims=" %%C in ('docker context show 2^>nul') do set "STT_CTX=%%C"
if /I not "%STT_CTX%"=="desktop-linux" goto not_wsl

powershell -NoProfile -Command "$t = wsl -l -v | Out-String; if ($t -notmatch 'docker-desktop') { exit 1 }; if ($t -notmatch 'docker-desktop[^\r\n]*\s2(\s|$)') { exit 2 }"
if errorlevel 2 goto wsl_not_v2
if errorlevel 1 goto wsl_missing

echo GPU を確認しています（docker run --gpus all ubuntu:24.04 nvidia-smi）。
docker run --rm --gpus all ubuntu:24.04 nvidia-smi
if errorlevel 1 goto gpu_fail

if not exist ".env" goto make_env
goto check_env

:make_env
echo.
echo はじめての起動です。WebUI と Jupyter のパスワードを決めます。
echo 英数字だけ、12 文字以上。何も入力せず Enter なら、自動で作ります。
for /f "delims=" %%P in ('powershell -NoProfile -Command "$p = Read-Host 'パスワード'; if ([string]::IsNullOrEmpty($p)) { 'GENERATE' } else { $p }"') do set "WEB_PASSWORD=%%P"
if "%WEB_PASSWORD%"=="GENERATE" goto gen_password
goto validate_password

:gen_password
for /f "delims=" %%P in ('powershell -NoProfile -Command "-join ((48..57 + 65..90 + 97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ })"') do set "WEB_PASSWORD=%%P"
echo パスワードを自動で作り、.env に保存します。この画面には出しません。
goto write_env

:validate_password
powershell -NoProfile -Command "if ($env:WEB_PASSWORD -notmatch '^[A-Za-z0-9]{12,}$') { exit 1 }"
if errorlevel 1 goto bad_password
goto write_env

:write_env
(
  echo WEB_USERNAME=admin
  echo WEB_PASSWORD=%WEB_PASSWORD%
  echo GHCR_IMAGE=%GHCR_IMAGE%
  echo IMAGE_TAG=%IMAGE_TAG%
) > ".env"
goto pull_image

:check_env
powershell -NoProfile -Command "$t = Get-Content -Raw -Encoding UTF8 .env; if ($t -notmatch '(?m)^WEB_PASSWORD=[A-Za-z0-9]{12,}\s*$') { exit 1 }"
if errorlevel 1 goto bad_existing
goto pull_image

:pull_image
set "STT_IMAGE=%GHCR_IMAGE%:%IMAGE_TAG%"
echo イメージ %STT_IMAGE% を取得します。
docker pull "%STT_IMAGE%"
if not errorlevel 1 goto up
docker image inspect "%STT_IMAGE%" >nul 2>&1
if not errorlevel 1 (
  echo レジストリにはまだこのタグがありません。前回この PC で作ったイメージを使います。
  goto up
)
echo 公開イメージがまだ無いので、この PC でビルドします。初回は長くかかります。
docker compose build
if errorlevel 1 goto build_fail

:up
echo コンテナを起動します。
docker compose up -d
if errorlevel 1 goto up_fail

echo WebUI の応答を待っています（最大 3 分）。
set /a STT_N=0
:wait_loop
set /a STT_N+=1
if %STT_N% GTR 90 goto wait_fail
curl.exe -s -o nul -w "%%{http_code}" "http://127.0.0.1:8001/web/trainer" > "%TEMP%\stt-http.txt" 2>nul
set "STT_CODE="
set /p STT_CODE=<"%TEMP%\stt-http.txt"
if "%STT_CODE%"=="401" goto ready
ping -n 3 127.0.0.1 >nul
goto wait_loop

:ready
echo.
echo 起動しました。
echo   WebUI   http://127.0.0.1:8001
echo   Jupyter http://127.0.0.1:8888
echo   ユーザー名 admin
echo   パスワードの場所: %CD%\.env の WEB_PASSWORD
echo パスワードはこの画面には出しません。
start "" "http://127.0.0.1:8001"
echo.
echo 何かキーを押すと閉じます。
pause >nul
exit /b 0

:docker_down
echo 失敗: Docker が動いていません。
echo 直し方: スタートメニューから Docker Desktop を起動し、左下が Running になるまで待ってから、もう一度 start.bat を実行してください。
goto fail

:not_wsl
echo 失敗: Docker の Linux エンジン（WSL2）になっていません。いまの context は %STT_CTX% です。
echo 直し方: Docker Desktop の Settings、General、「Use the WSL 2 based engine」にチェックを入れて Apply してください。
goto fail

:wsl_missing
echo 失敗: WSL に docker-desktop が見つかりません。
echo 直し方: 管理者の PowerShell で wsl --install を実行して再起動し、Docker Desktop で WSL2 エンジンを有効にしてください。
goto fail

:wsl_not_v2
echo 失敗: docker-desktop が WSL2 ではありません。
echo 直し方: PowerShell で wsl --set-version docker-desktop 2 を実行し、Docker Desktop を再起動してください。
goto fail

:gpu_fail
echo 失敗: GPU がコンテナから見えません（nvidia-smi）。
echo 直し方: NVIDIA のドライバを入れ直し、Docker Desktop を最新にして再起動してください。RTX 4060 Ti では、別途 NVIDIA Container Toolkit を入れる必要はありません。
goto fail

:bad_password
echo 失敗: パスワードは英数字 12 文字以上にしてください。記号は使えません。
goto fail

:bad_existing
echo 失敗: .env の WEB_PASSWORD が無いか、12 文字未満か、英数字以外です。
echo 直し方: %CD%\.env を直し、WEB_PASSWORD を英数字 12 文字以上にするか、.env を削除して start.bat をやり直してください。
goto fail

:build_fail
echo 失敗: イメージのビルドに失敗しました。上の英語ログを残してください。
echo 直し方: Docker Desktop の Settings、Resources でディスク空きが 40GB 以上あるか確認してください。
goto fail

:up_fail
echo 失敗: コンテナを起動できませんでした。
echo 直し方: logs.bat を実行して最後の行を確認してください。ポート 8001 と 8888 を他のソフトが使っていないかも見てください。
goto fail

:wait_fail
echo 失敗: 3 分待っても WebUI が応答しませんでした。
echo 直し方: logs.bat を開き、[stt の行を確認してください。パスワードが短いと画面は出ません。
goto fail

:fail
echo.
echo 何かキーを押すと閉じます。
pause >nul
exit /b 1
