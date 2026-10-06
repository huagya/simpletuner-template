# simpletuner-template

RunPod 向け（次に Vast.ai、その次に Windows の Docker Desktop）の SimpleTuner 公式 WebUI 用 Docker イメージです。プログラミングなしで、ブラウザから学習を始められるようにします。

イメージの中身はここにあります。公開（レジストリへの push）はまだしていません。確認できたことと未確認は `HANDOFF.md` に書いてあります。

## いま入っているもの

- `Dockerfile` — `nvidia/cuda:12.8.1-base-ubuntu24.04`（digest 固定）の上に SimpleTuner 4.9.3 と torch を入れます。既定は `2.11.0+cu128`。起動時に pip は走りません。SSH と `/start.sh` のフックはイメージ側で用意します。
- `locks/` — ビルドに使う依存関係のロックファイル。
- `image/` — 起動スクリプト、Caddy、パスワード未設定のときの案内ページ。
- `docs/DESIGN.md` — 設計案。先頭に、調査で直した点を書いてあります。
- `HANDOFF.md` — 決めたこと、確認できた事実、未確認、失敗。
- `versions.env` — 固定するバージョン。
- `scripts/feasibility_proxy_test.sh` — GPU なしで WebUI とプロキシだけを試します。
- `scripts/smoke_container.sh` — イメージをビルドして、パスワード、Jupyter、SSE、データフォルダ、再起動、ヘルパーのテストを確認します。失敗すると終了コードが 0 以外になります。
- `image/bin/` — コンテナの PATH にあるコマンド。`stt-help`（日本語の早見表）、`hf-model`、`hf-dataset`、`get-url`、`git-clone-hf`、`stt-doctor`（自己診断と、秘密を伏せた zip）。

## What this is

A custom image so a non-programmer can run the official SimpleTuner WebUI (`simpletuner server`) on RunPod first, Vast.ai second, and later on Windows Docker Desktop. The same image is meant to start without RunPod-only environment variables.

The image is defined here. It is not published to a registry yet. What was actually booted is in `HANDOFF.md`.

## Build

Default (the RunPod / GPU image, torch `2.11.0+cu128`):

```bash
docker build -t stt-runpod:cu128 .
```

CPU smoke variant (no NVIDIA wheel; used by the smoke script):

```bash
docker build --build-arg TORCH_VARIANT=cpu -t stt-runpod:smoke-cpu .
```

`WEB_PASSWORD` must be at least 12 characters. If it is missing, the container stays up and serves a warning page instead of the GUI.

```bash
docker run --gpus all -p 8001:8001 -p 8888:8888 \
  -e WEB_PASSWORD='change-me-please' \
  -v stt-data:/workspace \
  stt-runpod:cu128
```

WebUI: `http://localhost:8001` (user `admin`). JupyterLab: `http://localhost:8888`. Both use that one password. On RunPod the start script prints the proxy URLs instead.

Windows Docker Desktop: `windows/README.ja.md` と、同じフォルダの `start.bat`。イメージは `versions.env` の `GHCR_IMAGE` と `IMAGE_TAG` です。タグがまだ無いときは、その場でビルドします。

Inside the container, `stt-help` prints the Japanese cheat sheet. `stt-doctor` checks the GPU, the proxy, disk, and the HF token, and writes a redacted zip under `/workspace/diagnostics/`.

## Checks

```bash
bash scripts/feasibility_proxy_test.sh
sudo bash scripts/smoke_container.sh
```

`smoke_container.sh` builds the CPU variant unless `STT_TORCH_VARIANT=cu128`.

Image sizes and the GitHub Actions workflow (`.github/workflows/image.yml`) are in `HANDOFF.md`. A `v*` tag builds the cu128 image, runs the smoke test, and pushes to `ghcr.io/huagya/simpletuner-template`. Pull requests and manual runs build the CPU variant and do not push.

## License

SimpleTuner is AGPL-3.0-or-later: https://github.com/bghira/SimpleTuner
Scripts added in this repo are MIT unless a file says otherwise.
