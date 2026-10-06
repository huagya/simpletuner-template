# Handoff

Date: 2026-10-06. Nothing was published to a registry. No GPU was passed through. No RunPod or Vast instance was started.

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
