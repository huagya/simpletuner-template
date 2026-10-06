# Handoff

Date: 2026-10-06. Nothing was published to a registry. No GPU was passed through. No RunPod or Vast instance was started. No git tag was pushed.

## Step 3 — smaller image and a CI build path

### 日本語（短い結論）

- 30.8GB の正体は、RunPod ベース（12.7GB、中に CUDA の開発ツールと Nsight）と、その上の Python 環境 18.1GB。その 18.1GB のうち 8.6GB は、ベースイメージが `UV_CACHE_DIR` を `/workspace/.cache/uv` にしているせいでイメージに焼き付いた uv のキャッシュ。残りの 8.7GB が本体で、その中の 4.2GB は torch 用の `nvidia-*` ライブラリ。ベース側の CUDA と二重だった。
- ベースを `nvidia/cuda:12.8.1-base-ubuntu24.04`（Docker Hub 上の圧縮サイズ約 101MB、イメージ内の `/usr/local/cuda-12.8` は 194MB）に変えた。cu128 イメージは 9.75GB、CPU 版は 3.36GB。GPU なしのスモークは両方とも成功。
- RunPod のホストが `runpod/base` を持っていても得するのはそのベースの約 6.65GB（圧縮）だけ。以前のイメージは、その上に 18.1GB（非圧縮）の層が載っていた。新しいイメージ全体（9.75GB、非圧縮）の方が、その追加層より小さい。
- GitHub Actions は `ubuntu-24.04`。公式の表は SSD 14GB。プルリクエストと手動実行は CPU 版をスモークして push しない。`v*` タグのときだけ cu128 をスモークして GHCR に push する。タグはまだ打っていない。

### Where the 30.8GB went (before)

`docker image inspect` Size of `stt-runpod:cu128` from step 2: **30,840,988,478** bytes. CPU smoke image: **18,063,304,171**. Base `runpod/base@sha256:e6eb5a38…`: **12,694,186,412**. Docker Hub `full_size` for that tag: **6,649,948,587** bytes (compressed registry size, 2026-10-06).

`docker history` on the cu128 image, the layers we added:

| Layer | Size |
|---|---|
| `uv pip sync` (the venv) | 18.1GB |
| Caddy | 52MB |
| both lock files | 890kB |

`du` inside that container:

| Path | Size | What it is |
|---|---|---|
| `/workspace/.cache/uv` | 8.6GB | uv download cache. `runpod/base` sets `UV_CACHE_DIR=/workspace/.cache/uv/`. The BuildKit mount was `/root/.cache/uv`, so uv never used it. gzip -6 of this directory: **4,611,997,469** bytes. |
| `/opt/stt/venv` | 8.7GB | The install. 8.6 + 8.7 = 17.3GB, matching the 18.1GB layer. |
| `site-packages/nvidia` | 4.2GB | pip wheels: cudnn 951MB, cublas 830MB, cusparselt 432MB, cusolver 387MB, nccl 383MB, cusparse 371MB, cufft 269MB, nvrtc 212MB, nvshmem 195MB, curand 133MB, nvjitlink 90MB, cupti 41MB. |
| `site-packages/torch` | 1.6GB | `2.11.0+cu128` |
| `site-packages/triton` | 640MB | Includes its own `ptxas`. |
| `/usr/local/cuda-12.8` | 6.6GB | System CUDA from the base, including devel files under `targets/`. |
| `/opt/nvidia/nsight-compute` | 1.2GB | Nsight, not used at training time. |
| `/root` | 2.6MB | No pip cache left in the image. |

`docker history` of the base itself (uncompressed layer sizes): cuda runtime libraries **3.11GB**, cuda devel (**cuda-libraries-dev**, nvcc, nsight package) **5.99GB**, cuDNN plus cuDNN dev **1.05GB**, the apt tool layer (compilers, ffmpeg dev, nginx, ssh, slurm, …) **1.51GB**, five Python versions **286MB**, the base's own pip stack including Jupyter **264MB**, uv binary **56.5MB**, Ubuntu rootfs **78.1MB**.

`ldd` on the torch and `nvidia/*` libraries found `libcuda.so.1` missing (that comes from the host driver) and a handful of optional nvshmem transports (`libmpi`, `libfabric`, `libibverbs`). The devel toolkit is not required for those libraries to load. The CPU image's venv was **2.7GB** plus a **2.6GB** uv cache, which is the 5.32GB history layer.

### Decision

Use **`nvidia/cuda:12.8.1-base-ubuntu24.04`**, digest `sha256:e711c99333fdfe8ae1e677b4972be6c5021f0128a1d31f775c7e58d88921b6a9`.

Docker Hub amd64 `size` for that tag: **100,999,123** bytes. Inside the built image, `du` of `/usr/local/cuda-12.8` is **194MB**. Compared bases, same API, same day, amd64 `size`:

| Tag | Hub amd64 size |
|---|---|
| `nvidia/cuda:12.8.1-base-ubuntu24.04` | 100,999,123 |
| `nvidia/cuda:12.8.1-runtime-ubuntu24.04` | 2,159,070,331 |
| `nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04` | 2,862,565,896 |
| `nvidia/cuda:12.8.1-devel-ubuntu24.04` | 5,161,997,061 |
| `runpod/base:1.4.0-cuda1281-ubuntu2404` | 6,649,948,587 (`full_size`) |

The runtime and devel tags would add the same libraries the torch wheel already vendors. The base tag is the driver-compat layer (`libcuda` comes from the host). Torch keeps the pip `nvidia-*` wheels. `UV_CACHE_DIR` is `/root/.cache/uv` on a BuildKit cache mount, and the layer deletes `/workspace/.cache`. `build-essential` is installed only so deepspeed's sdist can build, then purged in that same layer (`deepspeed` on disk is 11MB).

RunPod conventions that `runpod/base` used to provide are in `image/start.sh`: `/pre_start.sh`, SSH only when `PUBLIC_KEY` is set (key auth, no password), `/etc/rp_environment`, `/post_start.sh`, then `sleep infinity`. nginx is not started. JupyterLab 4.5.10 is installed from `locks/jupyter.txt` into the venv and still sits behind Caddy on port 8888. `JUPYTER_PASSWORD` is not used, so nothing binds 8888 in the clear.

A multi-stage copy off `runpod/base` was rejected. It would still download and unpack the 12.7GB base during the build, which is the disk problem on a free runner, and the final image would not share that base with other templates anyway.

### RunPod layer-cache trade-off

A host that already has `runpod/base@sha256:e6eb5a38…` skips the **6,649,948,587** byte registry blob. It still has to fetch every layer we add. That added layer was **18.1GB uncompressed**, and **4,611,997,469** bytes of that was the uv cache after gzip -6 (the 8.6GB directory). The new image is **9,747,387,413** bytes uncompressed in total, which is smaller than the old added layer alone, and its base blob is **100,999,123** bytes. Keeping `runpod/base` so some hosts can skip 6.65GB does not offset shipping an 18.1GB extra layer.

### After

| Image | `docker image inspect` Size | Largest added layer |
|---|---|---|
| step 2 cu128 | 30,840,988,478 | 18.1GB venv + uv cache |
| step 3 cu128 | 9,747,387,413 | 9.28GB venv (torch + nvidia wheels + Jupyter) |
| step 2 CPU | 18,063,304,171 | 5.32GB venv + uv cache |
| step 3 CPU | 3,357,084,783 | 2.89GB venv |

`/root/.cache` in the new cu128 image is 32KB. `/workspace/.cache` is absent. `build-info.json`: cu128 is `torch 2.11.0+cu128`, `torch_cuda 12.8`; CPU is `2.11.0+cpu`, `torch_cuda null`.

gzip -6 of `/opt/stt/venv` in the new cu128 image: **4,675,746,836** bytes. That is the bulk of what a registry pull compresses. The old image's uv cache alone was already 4,611,997,469 bytes after the same gzip, before counting the venv.

### CI

GitHub's runner table lists **14 GB SSD** for `ubuntu-24.04` / `ubuntu-latest` (public repos, 4 CPU, 16 GB RAM): https://docs.github.com/en/actions/reference/runners/github-hosted-runners . That is the free path. Larger runners are paid. The workflow `.github/workflows/image.yml` deletes the preinstalled dotnet, Android SDK, GHC, Swift, and `AGENT_TOOLSDIRECTORY` before the build and prints `df -h` before and after, so the run log is the measurement for this repo. A published cleanup example measured an 84GB root that went from about 24GB free to about 43GB free after a similar deletion (https://github.com/ultralytics/actions/blob/main/cleanup-disk/README.md). That is their number, not ours, until this workflow runs.

- `pull_request` and `workflow_dispatch`: CPU image, `scripts/smoke_container.sh`, no push.
- `push` of a `v*` tag: cu128 image, smoke, then push `ghcr.io/huagya/simpletuner-template:<tag>` and `:latest`.

No tag was created and nothing was pushed to GHCR.

### Smoke (no GPU)

| Check | CPU 3.36GB | cu128 9.75GB |
|---|---|---|
| Image builds, no pip at start | **PASS** | **PASS** |
| GUI 401 / 200 | **PASS** | **PASS** |
| Jupyter 401 / 200 | **PASS** | **PASS** |
| SSE through the proxy | **PASS** | **PASS** |
| Missing `WEB_PASSWORD` keeps the container up and hides the GUI | **PASS** | **PASS** |
| Data dirs and server env under `/workspace` | **PASS** | **PASS** |
| Restart keeps `/workspace` data | **PASS** | **PASS** |

Commands: `sudo STT_TORCH_VARIANT=cpu bash scripts/smoke_container.sh` exit 0, `image_bytes=3357084783`. `sudo STT_TORCH_VARIANT=cu128 bash scripts/smoke_container.sh` exit 0, `image_bytes=9747387413`. Both printed `ALL CHECKS PASSED`.

### UNVERIFIED

- The GitHub Actions run itself, until the workflow on this branch finishes. See the dry-run note at the bottom of this section once it has been updated.
- A real RunPod pull, warm or cold, and whether SSH accepts `PUBLIC_KEY` on their proxy. The script matches their key setup. It was not connected to RunPod.
- GPU training. `libcuda.so.1` is still supplied by the host.
- Windows Docker Desktop.

## Step 2 — the RunPod image boots

### 日本語（短い結論）

- イメージはビルドできた。中身は SimpleTuner 4.9.3 と torch 2.11.0+cu128。GPU のないこの VM でも、パスワード付きの WebUI と Jupyter が起動した。
- ベースイメージの nginx が 8001 番を先に使っていた。最初の起動では Caddy がポートを取れず、RunPod の 502 案内ページが返った。起動スクリプトで nginx を止めてから Caddy を出すように直した。
- `WEB_PASSWORD` が無いと、画面は出さず、案内ページだけ出して、コンテナは落ちない。
- 学習データ用のフォルダは `/workspace` に作り、コンテナを再起動しても残った。
- cu128 のイメージは約 30.8GB、CPU 版は約 18.1GB。GitHub の無料ランナー（ディスク約 14GB）には、ベースイメージ単体（約 12.7GB）の時点で入りきらない。

### Decisions

11. Keep RunPod's `/start.sh` as PID 1. `/pre_start.sh` only creates `/workspace` and exits 0. `/post_start.sh` runs `/opt/stt/bin/stt-start` and **always exits 0**, because `/start.sh` uses `set -e` and a failing hook skips `sleep infinity`.
12. Do not set `JUPYTER_PASSWORD` or `JUPYTER_DISABLE_AUTH`. The base start script would otherwise bind Jupyter to `0.0.0.0:8888` before our proxy. JupyterLab 4.5.10 from the base image listens on `127.0.0.1:18888` with an empty token. Caddy on `8888` is the only login.
13. One password for the GUI and Jupyter. `WEB_USERNAME` defaults to `admin` and must match `[A-Za-z0-9_-]+`. `WEB_PASSWORD` must be at least 12 characters. If it is missing or too short, Caddy serves a static warning page and SimpleTuner and Jupyter are not started.
14. Do not call `simpletuner auth setup`.
15. Public ports are Caddy `8001` (GUI) and `8888` (Jupyter). The app binds `127.0.0.1:18001` and `127.0.0.1:18888`. Override with `STT_GUI_PORT`, `STT_JUPYTER_PORT`, `STT_APP_PORT`, `STT_JUPYTER_APP_PORT` so a later Windows compose file can move them.
16. Stop the base image's nginx before Caddy starts. Its config listens on `8001` as a placeholder for code-server (`proxy_pass` to `localhost:8000`). `service nginx stop` is a no-op when nginx is absent.
17. Caddy site addresses are `http://:8001` and `http://:8888` with `bind 0.0.0.0`. `http://0.0.0.0:8001` is a hostname match, not a bind. The bcrypt hash is written into the Caddyfile with `caddy hash-password` (mode 600). `{$WEB_PASSWORD_HASH}` is still unused.
18. Data layout on `/workspace`: `huggingface` (`HF_HOME`), `models`, `datasets`, `simpletuner/config`, `simpletuner/output`, `simpletuner/.state`, `logs`, `.cache/torchinductor`, `.cache/triton`. This overrides the base image default `HF_HOME=/workspace/.cache/huggingface/`. The same paths are exported on the SimpleTuner process and appended for later root shells via `/etc/profile.d/stt.sh`.
19. RunPod env vars are optional. With `RUNPOD_POD_ID` unset, the banner prints `http://localhost:8001` and `http://localhost:8888`. `STT_GUI_URL` and `STT_JUPYTER_URL` override the printed URLs. No Windows compose file in this step.
20. Dependencies are installed only at build time from `locks/cu128.txt` or `locks/cpu.txt` (`uv pip sync`, hashes, `--index-strategy unsafe-best-match` because the PyTorch extra index publishes an old `requests`). Default `TORCH_VARIANT` is `cu128`. Container start does not run pip. SimpleTuner is retried up to 5 times and then left stopped; the pod stays up.
21. Jupyter is not duplicated into the venv. The base image already has `jupyterlab==4.5.10`.

### Image size

| Image | `docker image inspect` Size | What it is |
|---|---|---|
| `runpod/base@sha256:e6eb5a38…` | 12,694,186,412 bytes (~12.7GB) | Pulled digest. Shared by both builds. |
| `stt-runpod:smoke-cpu` | 18,063,304,171 bytes (~18.1GB) | Base plus ~5.4GB app layer (CPU torch). |
| `stt-runpod:cu128` | 30,840,988,478 bytes (~30.8GB) | Default image. Base plus the cu128 lock (torch wheel, `nvidia-*-cu12`, deepspeed, bitsandbytes). |

GitHub-hosted free runners have about 14GB of disk. The base image alone is ~12.7GB uncompressed, so a job that pulls it and then builds either variant will not fit. That is a later CI-publishing problem, not a reason to drop cu128 from the Dockerfile default.

`/opt/stt/build-info.json` in the cu128 image: `simpletuner 4.9.3`, `torch 2.11.0+cu128`, `torch_cuda 12.8`. The CPU image: `torch 2.11.0+cpu`, `torch_cuda null`.

### Verified on this VM (no GPU)

Docker: 29.1.3 with BuildKit (`docker-buildx` 0.30.1) and storage driver `fuse-overlayfs`. Commands:

- `sudo docker build --build-arg TORCH_VARIANT=cpu -t stt-runpod:smoke-cpu .` — exit 0.
- `sudo docker build --build-arg TORCH_VARIANT=cu128 -t stt-runpod:cu128 .` — exit 0.
- `sudo bash scripts/smoke_container.sh` — exit 0, `ALL CHECKS PASSED`, `image_bytes=18063304171`.
- `sudo STT_TORCH_VARIANT=cu128 bash scripts/smoke_container.sh` — exit 0, `ALL CHECKS PASSED`, `image_bytes=30840988478`.

| Check | CPU smoke | cu128 smoke | Evidence |
|---|---|---|---|
| Image builds, no pip at start | **PASS** | **PASS** | Both builds exit 0. Start logs show numbered steps and no pip. `build-info.json` matches the pins above. |
| Unauthenticated GUI is 401 | **PASS** | **PASS** | Script: `PASS: unauthenticated GUI request gets 401`. |
| Authenticated GUI is 200 | **PASS** | **PASS** | Script: `PASS: authenticated GUI page is HTTP 200 and is the SimpleTuner trainer`. Saved HTML title: `SimpleTuner Training Studio`. |
| Unauthenticated Jupyter is 401 | **PASS** | **PASS** | Script: `PASS: unauthenticated Jupyter request gets 401`. |
| Authenticated Jupyter is 200 | **PASS** | **PASS** | Script: `PASS: authenticated Jupyter page is HTTP 200`. Saved HTML title: `JupyterLab`. |
| SSE through the proxy | **PASS** | **PASS** | `GET /api/events` body started with `event: connection` / `data: {"type": "connected", "message": "Connected to SimpleTuner"}`. |
| `WEB_PASSWORD` unset exits gracefully and does not expose the GUI | **PASS** | **PASS** | Script: `PASS: WEB_PASSWORD missing: start script exits 0, container stays up, GUI is not exposed`. Requires log line `forcing exit 0`, body marker `STT_PASSWORD_REQUIRED`, and no listener on `127.0.0.1:18001`. |
| Data dirs land in `/workspace` and the server env matches | **PASS** | **PASS** | Script checks `huggingface`, `models`, `datasets`, `simpletuner/config`, `simpletuner/output`, `simpletuner/.state`, `.stt-layout-version`, and the SimpleTuner process env (`HF_HOME`, `SIMPLETUNER_CONFIG_DIR`, `SIMPLETUNER_STATE_DIR`). |
| Restart keeps `/workspace` data | **PASS** | **PASS** | Script writes `/workspace/datasets/smoke-marker.txt`, `docker restart`s, waits for GUI 200, reads the marker back. |
| Starts with no RunPod env vars | **PASS** | **PASS** | Container log: `detecting platform …… local`. Banner: `http://localhost:8001` and `http://localhost:8888`. Base `/start.sh` reached `sleep infinity` (`Pod is ready to use`). |
| Real GPU training, RunPod proxy URL, Windows Docker Desktop | **UNVERIFIED** | **UNVERIFIED** | Not run. See below. |

An earlier CPU container log (before the nginx fix was retested) showed `[stt 7/7] … ready in 24 s` with no GPU. The green cu128 smoke also returned the trainer page inside the 180s wait. Exact cu128 startup milliseconds were not captured.

### Failures

1. This VM's first dockerd (containerd snapshotter + overlayfs) could not extract the base image: `failed to convert whiteout file … operation not permitted` (`mknod` of a whiteout returns EPERM). `hello-world` and `ubuntu:24.04` pulled. Restarted dockerd with `--storage-driver fuse-overlayfs --feature containerd-snapshotter=false --data-root /var/lib/docker-fuse`. The digest then pulled. This is a limitation of this VM, not of the Dockerfile.
2. `docker build` failed immediately with `BuildKit is enabled but the buildx component is missing`. Installed `docker-buildx` 0.30.1. The Dockerfile uses `RUN --mount=type=cache`, so BuildKit is required. Docker Desktop and GitHub Actions builders have it.
3. First CPU smoke (image `18063303559`, container `stt-smoke-cpu-14572`) never got a 401. Host `curl` to `127.0.0.1:18081/web/trainer` was HTTP 200 from `nginx/1.24.0` with title `502 | README | Runpod`. Caddy's log: `listening on :8001: listen tcp :8001: bind: address already in use`. `ss` showed nginx on `0.0.0.0:8001` and SimpleTuner already on `127.0.0.1:18001`. Fixed in `image/stt-start` by stopping nginx and binding Caddy with `http://:port`. The smoke script was killed and rerun. Both later runs exited 0.

### UNVERIFIED after step 2

- Boot on a real RunPod pod, including `https://$RUNPOD_POD_ID-8001.proxy.runpod.net` and the 100s Cloudflare timeout.
- NVIDIA driver ≥ 570, `nvidia-smi`, and any training step. Both smokes logged `WARN GPU が見えません`.
- Windows Docker Desktop (WSL2, RTX 4060 Ti). The image does not require RunPod variables, and the same start path ran on Linux Docker. Nobody has run it on Windows yet. No compose file and no `.bat`.
- Vast.ai image.
- A GitHub Actions build or push. Estimated size above.
- `{$WEB_PASSWORD_HASH}` as a Caddy env placeholder. The hash is inlined instead.
- Which PixArt id the GUI dropdown writes (`pixart` vs `pixart_sigma`). Not part of this step.

## Step 1 — feasibility spike + repo skeleton

## 日本語（短い結論）

- GPU がなくても `simpletuner server` は起動する。この VM では約 10 秒で画面が返った。
- Caddy のパスワードを通さないと 401。通すと WebUI が開く。ログの SSE も、設定の保存も、プロキシ越しに動いた。
- ユーザーが一人もいない間、SimpleTuner は自分で `local` という管理者を作り、パスワードなしで管理者になる。インターネットに直接出すと危険。対策は「アプリは 127.0.0.1 だけ」「外向けはパスワード付きプロキシだけ」。
- 公式の `simpletuner auth setup` で本物の管理者を作ると、その自動管理者は消える。その後はプロキシのパスワードに加えて、SimpleTuner 自身のログインが必要になる。v1 では `auth setup` を呼ばない。
- PixArt Sigma も Stable Cascade も v4.9.3 に残っている。Cascade は削除されていない。ドキュメントは「Abandonware（提供元が放置、ライセンスは自己判断）」と書いている。
- WebUI に日本語はない。説明書（`README.ja.md` や `documentation/**/*.ja.md`）だけ日本語がある。

## Decisions

1. RunPod first, Vast second. Unchanged.
2. v1 auth is one proxy password (`WEB_USERNAME=admin`, `WEB_PASSWORD`). Do not create a SimpleTuner user in v1.
3. App bind stays `127.0.0.1`. Public port is only the auth proxy.
4. Pin SimpleTuner **v4.9.3** commit `82a589d99875e7284bb1abe1ca5479f327b78dcf`.
5. Image torch pin is **2.11.0+cu128** (the only 2.11 cu128 wheel). The spike used **2.11.0+cpu** because this VM has no GPU.
6. Vast base image pin is the dated tag `cuda-12.8.1-cudnn-devel-ubuntu24.04-py312-2026-09-07`, not the undated tag (that one is the 2026-01-08 image).
7. RunPod base pin is `runpod/base:1.4.0-cuda1281-ubuntu2404`.
8. Caddy pin is **v2.11.7**. Verify the linux amd64 tarball with **SHA-512** (that is what upstream's `checksums.txt` contains).
9. Keep Stable Cascade in scope. It is still a registered family. Tell the user about the Abandonware / license note. Do not swap it for another model unless they ask.
10. Treat PixArt family id `pixart` and `pixart_sigma` as a step-2 test, not as two different models.

## Feasibility results

Command: `bash scripts/feasibility_proxy_test.sh`  
Last run exit code: **0** (`ALL CHECKS PASSED`).  
Work dir: `/tmp/stt-feasibility` (not in git). The script `cd`s there before starting the server, because SimpleTuner writes `debug.log` in the current directory.  
Earlier runs failed and were fixed in the script before this green run. See Failures.

| Question | Result | Evidence |
|---|---|---|
| Does `simpletuner server` start with no GPU? | **PASS** | `torch 2.11.0+cpu cuda_available False`. Ready: `PASS: simpletuner server ready on 127.0.0.1:18001 in 10790 ms`. Flags: `--host 127.0.0.1 --port 18001`. Source default is still `--host 0.0.0.0` and port 8001 (`simpletuner/cli/__init__.py`). |
| Unauthenticated proxy request is 401 | **PASS** | `PASS: unauthenticated proxy request gets 401`. Body was empty (0 bytes), which is Caddy's basic-auth response. |
| Authenticated page loads | **PASS** | `PASS: authenticated /web/trainer through proxy: HTTP 200`. Title in the HTML: `SimpleTuner Training Studio`. `<html lang="en">`. |
| Live log/event stream through the proxy | **PASS** | SSE, not WebSocket. `GET /api/events` returned `event: connection` / `data: {"type": "connected", "message": "Connected to SimpleTuner"}` within 8 seconds, through Caddy `flush_interval -1`. |
| Config save through the proxy, including Origin | **PASS** | `POST /api/configs/environments` with `Origin: https://abc123-8001.proxy.runpod.net` and no CSRF token: HTTP 200. File written: `/tmp/stt-feasibility/config/feas-pixart/config.json` with `"--model_family": "pixart_sigma"`. A second POST with `Origin: https://evil.example` was also HTTP 200. |
| Auto-admin when no users exist | **PASS** (behavior confirmed) | Direct `GET /api/users/me` with no credentials: HTTP 200, `username=local`, `is_admin=true`. Log: `Single-user mode: creating local admin user`. |
| Mitigation: proxy blocks that, and creating a real admin changes it | **PASS** | After `simpletuner auth setup --email admin@example.com --username sttadmin --password …` against `SIMPLETUNER_PORT=18001`: direct `/api/users/me` is 401, and proxy basic auth alone is also 401. Proxy basic auth plus `POST /api/auth/login` session: HTTP 200 as `sttadmin`. |
| PixArt Sigma still supported (LoRA and full) | **PASS** (support present; training not run) | Live `GET /api/models`: both `pixart` and `pixart_sigma`, display name PixArt Sigma, flavours `900M-1024-v0.6`, `900M-1024-v0.7-stage1`, `900M-1024-v0.7-stage2`, `600M-512`, `600M-1024`, `600M-2048`. Registry: `ModelRegistry.register("pixart_sigma", …)`. Example `pixart.lycoris-lokr` uses `model_family=pixart`, `model_type=lora`. `SIGMA.md` example uses `model_type: full`. |
| Stable Cascade still supported | **PASS** (not removed) | Live family `stable_cascade`, name `Stable Cascade (Stage C)`, flavours `stage-c`, `stage-c-lite`. `documentation/quickstart/index.md` calls it Abandonware (footnote 7). Guide `STABLE_CASCADE_C.md` still documents LoRA and full fine-tune. |
| Japanese GUI | **PASS** as a negative finding | No hiragana/katakana in the live trainer HTML. No CJK/kana in v4.9.3 `simpletuner/templates` or `simpletuner/static`. Japanese exists only in docs (`README.ja.md`, `documentation/**/*.ja.md`). |
| RunPod 100 s Cloudflare timeout | **UNVERIFIED** | Not run against RunPod. |
| Real training, VRAM measurement, driver ≥570 | **UNVERIFIED** | No GPU. |
| Base images pulled and booted | **UNVERIFIED** | Tags and digests were read from the Docker Hub API only. |
| `{$WEB_PASSWORD_HASH}` Caddy env expansion | **UNVERIFIED** | The spike wrote the bcrypt hash into the Caddyfile as a quoted literal. |

### VRAM from docs (not measured)

- PixArt Sigma: 0.6–0.9B (`documentation/quickstart/index.md`). `SIGMA.md` says use `full` because the model is small enough to fit, and gives **no GB figure**. Numeric VRAM for Sigma full or LoRA is **UNVERIFIED**.
- Stable Cascade Stage C (`STABLE_CASCADE_C.md`): LoRA **20–24 GB**; full **48 GB+**; `stage-c-lite` if you only have about **18 GB**; system RAM 32 GB recommended; gradient checkpointing saves 3–4 GB. `mixed_precision` must be `no` unless `i_know_what_i_am_doing=true`.

### Model-support notes that change the design

- Cascade is not deprecated in code. The index table says Abandonware: the vendor left the model, and there is no reliable permission path; the user decides. Do not hide that. No replacement is proposed.
- PixArt has two ids. After the server loads models, both `pixart` and `pixart_sigma` answer `GET /api/models/{id}` with the same flavours. `model_metadata.json` key is `pixart`. `ModelRegistry.register` and `SIGMA.md` use `pixart_sigma`. `collate.py` special-cases `pixart_sigma` only. The create-environment API stored the id we sent (`pixart_sigma`) under the CLI key `--model_family`. Step 2 should confirm which id the GUI dropdown writes, then train a few steps with that id.

## Failures (fixed before the green run)

1. First run: `python3.12 -m venv` failed because `python3.12-venv` was not installed (`ensurepip is not available`). The script exited 1. The package was installed on this VM with apt. The script still fails loudly if venv creation fails. A clean machine needs `python3.12-venv`.
2. Second run: Caddy check used `sha256sum` on a SHA-512 digest from upstream `checksums.txt` (`no properly formatted checksum lines found`). The script now uses `sha512sum` and the pin in `versions.env` is SHA-512. Exit was 1. SimpleTuner and CPU torch had already installed correctly.
3. Third run: HTML check looked for `SimpleTuner Training Interface` (the string in the route's Python context). The page title is `SimpleTuner Training Studio`. Exit was 1. The check now looks for `<title>SimpleTuner`. The server itself had already returned HTTP 200 in 10719 ms on that run.
4. That third run also left `debug.log` in the repo root, because the server writes it in the current directory. The script now `cd`s to the work dir first. The run of that script exited 0 in 10790 ms and wrote `debug.log` only under `/tmp/stt-feasibility`.

## Open questions

- Which id does the WebUI save for PixArt when a person uses the dropdown, `pixart` or `pixart_sigma`?
- What VRAM does a PixArt Sigma full fine-tune actually need? The docs do not say.
- Does the user accept Stable Cascade's Abandonware / license situation?
- Vast launch mode for their own base-image templates (still T0b).
- Will `{$WEB_PASSWORD_HASH}` survive Caddy's env replacer once the hash contains `$`?
- RunPod proxy behavior past 100 seconds.

## Recommended changes before step 2

1. Build the app layer with **cu128** `2.11.0`, not the CPU wheel and not PyPI's default CUDA wheel (cu130, currently up to 2.14.1).
2. Do not call `simpletuner auth setup` in `stt-start`. Proxy + localhost bind is the mitigation, and it only yields a one-password GUI while single-user mode stays on.
3. Point any future auth CLI at `SIMPLETUNER_HOST` and `SIMPLETUNER_PORT`. It defaults to `localhost:8001` and ignores the server's `--port`.
4. Do not add an Origin/Host CSRF workaround for v4.9.3. The middleware is not mounted. Re-check when the pin moves.
5. Pin Vast to the dated 2026-09-07 tag and digest in `versions.env`. The undated tag is stale.
6. Pin RunPod to `1.4.0-cuda1281-ubuntu2404` and its digest.
7. In the Japanese guide, say the GUI is English, and say Cascade is still trainable but marked abandonware.
8. Add a step-2 test that saves a PixArt environment from the GUI and checks the stored `--model_family`, then a CPU-side config check for both `lora` and `full`. Do not claim a VRAM number for Sigma until a GPU run measures it or upstream documents one.
9. CI smoke can follow `scripts/feasibility_proxy_test.sh`: CPU extra, Caddy, 401/200, SSE, config POST. Expect about 10 s to first HTML after import, plus a large pip install on a cold runner.
