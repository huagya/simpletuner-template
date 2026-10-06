# SimpleTuner on RunPod / Vast.ai: custom image and template design proposal

- Status: design only. Nothing built, nothing launched, no money spent.
- Date: 2026-10-06 (JST)
- Proposed repo: `huagya/simpletuner-template` (GitHub account `huagya` confirmed via `get_me`; no public repo with that name exists yet. Private repos could not be checked.)
- Proposed image: `ghcr.io/huagya/simpletuner-template`
- Legend: **[verified]** = read in a primary source or observed in this repo's step-1 spike. **[unverified]** = inferred or not confirmed. Check it during implementation.

## Corrections from the step-1 spike (2026-10-06)

These override the original sentences below when they disagree. The experiment transcript is in `HANDOFF.md`. Anything still marked UNVERIFIED was not run here (no GPU, no RunPod/Vast launch).

1. **`simpletuner server` starts with no GPU.** Pinned install: Python 3.12.3, `simpletuner[cpu]==4.9.3` (commit `82a589d99875e7284bb1abe1ca5479f327b78dcf`), `torch==2.11.0+cpu` (`torch.cuda.is_available()` is false). Flags that work: `--host 127.0.0.1 --port 18001`. Default host in source is still `0.0.0.0`, default port `8001`. On this CPU VM, `/web/trainer` returned HTTP 200 in **10790 ms** (a previous run of the same check was 9774 ms). The HTML title is `SimpleTuner Training Studio` (`lang="en"`). That time is not a GPU-host number.
2. **Caddy basic auth in front of that server works** for 401 vs authenticated HTML, and SSE (`GET /api/events`) streams with `flush_interval -1`. A config create (`POST /api/configs/environments`) succeeds through the proxy with `Origin: https://abc123-8001.proxy.runpod.net` and with no CSRF token.
3. **CSRF is not the risk the first draft guessed.** `CSRFMiddleware` in `simpletuner/simpletuner_sdk/server/middleware/csrf.py` is a double-submit cookie (`csrf_token` cookie vs `X-CSRF-Token` / form field). It does **not** compare `Origin` and `Host`. It is also **not mounted**: nothing calls `add_middleware(CSRFMiddleware)`. A foreign `Origin` does not block a state-changing POST. Do not spend step 2 on an Origin/Host workaround unless a later SimpleTuner version mounts this middleware.
4. **Auto-admin is real, and the proxy is the mitigation — with a catch.** While no real user exists, the first request creates username `local` / password `local` (password unused) and every request is that admin (`AuthMiddleware._ensure_single_user_mode`). Binding the app to `127.0.0.1` and requiring Caddy basic auth means the public port returns 401 before the app sees the request. **Do not run `simpletuner auth setup` in v1.** Creating a real admin deletes the `local` user, turns single-user mode off, and the API then returns 401 until a second SimpleTuner login. The HTML shell at `/web/trainer` does not itself require a user, but `/api/users/me`, SSE, and config routes do. One password works only while single-user mode stays on.
5. **`simpletuner auth setup` does not discover `--port`.** The CLI calls `SIMPLETUNER_HOST` / `SIMPLETUNER_PORT` (default `localhost:8001`), not the server's bind port. If the app listens on `18001`, set those variables or the setup command talks to the wrong port.
6. **PixArt Sigma and Stable Cascade are still in v4.9.3.** Neither is removed. Cascade is labeled **Abandonware** in `documentation/quickstart/index.md` (footnote 7: the vendor left it behind; the user accepts that license risk). The trainer, examples, and `STABLE_CASCADE_C.md` are still there. Closest alternative is not required.
7. **Family id footgun for PixArt.** `ModelRegistry.register("pixart_sigma", ...)` and `documentation/quickstart/SIGMA.md` say `pixart_sigma`. `model_metadata.json`, the shipped example `pixart.lycoris-lokr`, and some WebUI field lists say `pixart`. `ModelRegistry.get("pixart")` resolves via metadata. `get("pixart_sigma")` resolves only after the module has been imported and registered. `collate.py` special-cases `pixart_sigma` only. Step 2 must try both ids on a real train, and the Japanese guide should name the id the GUI actually saves.
8. **Documented VRAM (v4.9.3), not measured here.** PixArt Sigma is 0.6–0.9B. `SIGMA.md` recommends `model_type: full` because it is small, and does **not** give a GB number. Stable Cascade Stage C (`STABLE_CASCADE_C.md`): LoRA 20–24 GB; full fine-tune 48 GB+; `stage-c-lite` if you only have ~18 GB; system RAM 32 GB recommended; gradient checkpointing saves 3–4 GB. `mixed_precision` must be `no` unless `i_know_what_i_am_doing=true`.
9. **No Japanese GUI.** Templates and `simpletuner/static` contain no kana/CJK. Japanese exists in `README.ja.md` and `documentation/**/*.ja.md` only. The WebUI the user clicks is English.
10. **PyPI 4.9.3 ships a wheel and an sdist**, not an sdist only (`simpletuner-4.9.3-py3-none-any.whl`). `python_requires` is `>=3.12,<3.15`. Quickstart pages still mention Python 3.10–3.13; ignore that and keep 3.12.
11. **Torch pin is `2.11.0`, not "latest 2.11 patch".** The cu128 and CPU indexes for cp312 manylinux have `2.11.0` and no `2.11.1`. cu128 has `2.10.0` and `2.11.0` only. cu130 has `2.10.0` through `2.14.1`. There is no `2.12+cu128` wheel, which matches the draft's "2.12 dropped cu128" claim. This spike installed the **CPU** wheel (`2.11.0+cpu`) because the VM has no GPU. The image must still use cu128; that wheel was not installed here.
12. **Base image tags looked up on Docker Hub (not pulled).** `runpod/base:1.4.0-cuda1281-ubuntu2404` digest `sha256:e6eb5a38bd3b321f41e7c584334c9ebc15e1e529574c7f2c866d148990cfb817`, updated 2026-09-30, about 6.6 GB. The undated Vast tag `vastai/base-image:cuda-12.8.1-cudnn-devel-ubuntu24.04-py312` **does exist** but was last updated 2026-01-08 (`sha256:91fcc42b33f0688d476f16a9cae63bc701cad9c77fab41d3ea2b7e47c28a15cd`). Prefer the dated tag `vastai/base-image:cuda-12.8.1-cudnn-devel-ubuntu24.04-py312-2026-09-07` (`sha256:c63434109989a5736181bd1c2ad0a0f12c84e24b73b3bce6b3d604932745b410`, 2026-09-07, about 8.4 GB).
13. **No official SimpleTuner container image was found.** `https://github.com/bghira/SimpleTuner/pkgs/container/simpletuner` returns 404. The repo workflows are docs, PyPI, Replicate, and tests — no image publish. `https://hub.docker.com/v2/repositories/bghira/simpletuner/` returns 404. A private GHCR package would also 404 anonymously, so "no public image" is the verified claim.
14. **Caddy pin for the spike:** `v2.11.7` (2026-10-03). The official `checksums.txt` line for `caddy_2.11.7_linux_amd64.tar.gz` is SHA-512 (`a7a433a1b133efc3c8d10eb0b99d52a24b5ef5c322dc77f5282182b1c0402139ab83f3a99f0c52409df77d20123fb0b523edad8a66d8f5e49136197bf61ef0e7`), not SHA-256. Bcrypt hashes contain `$`. Writing the hash into the Caddyfile as a quoted literal worked in the spike. Do not assume `{$WEB_PASSWORD_HASH}` expansion is safe until step 2 tries it; this spike inlined the hash.

---

## 0. 日本語サマリー（ユーザー向け）

**やりたいこと**: RunPod または Vast.ai で GPU を借りて、ブラウザで SimpleTuner の公式 WebUI を開き、JupyterLab でファイルを扱い、ターミナルで Hugging Face からモデルやデータセットを取ってきて学習します。

**おすすめの構成（ハイブリッド方式）**
- プログラム一式（SimpleTuner、PyTorch など）は全部 **Docker イメージに焼き込みます**。起動のたびに `pip install` をしないので、毎回同じ状態で確実に起動します。
- **モデルとデータセットはイメージに入れません**。起動後に `/workspace`（永続ストレージ）へダウンロードします。
- 同じ Dockerfile から 2 種類のイメージを作ります。
  - **RunPod 用**: RunPod 公式の base イメージを土台にします。
  - **Vast 用**: Vast 公式の base-image を土台にします。
  
  中身の SimpleTuner 部分とスクリプトは 100% 共通です。違うのは「入口」の部分だけです。
- WebUI はインターネットに直接さらしません。**パスワード付きの入口（リバースプロキシ）経由でだけ**開けます。パスワードは `WEB_PASSWORD` という環境変数で 1 つだけ設定します。ユーザー名は `admin` です。
- 困ったときは、ターミナルで `stt-doctor` を実行します。GPU、PyTorch、WebUI、ディスク容量、HF トークンを自動でチェックし、合格・不合格を日本語で表示します。あわせて、診断ログの zip（パスワードやトークンは自動で伏せ字）を作ります。その zip をそのまま送ってもらえれば原因を調べられます。
- 便利コマンドを用意します。
  - `hf-model <モデルID>` / `hf-dataset <データセットID>` / `get-url <URL>`: ダウンロード用です。空き容量を事前にチェックし、Gated モデルにも対応します。
  - `stt-help`: 使い方を日本語で表示します。

**ユーザーにしか決められないこと** は §14 にまとめています（アカウント、学習したいモデル、予算など）。

---

## 1. Research findings (with sources)

### 1.1 SimpleTuner itself
| Item | Finding | Source |
|---|---|---|
| Official WebUI | **Yes [verified].** `simpletuner server` starts a FastAPI/uvicorn web UI. Default port is **8001** and default host is `0.0.0.0`. It supports `--ssl`. The WebUI tutorial covers onboarding: workspace dir, GPU detection, model/dataset config, HF Hub/W&B integration. | `simpletuner/cli/server.py`, `documentation/webui/TUTORIAL.md`, https://docs.simpletuner.io/quickstart/ZIMAGE/ |
| Auth | **Risk [verified in code].** `AuthMiddleware` has a "single-user mode": while **no users exist**, it auto-creates and auto-authenticates a `local` **admin** for every request. Exposing the port publicly before setup gives anyone admin. A CLI `simpletuner auth setup --email --username [--password]` (POST `/api/auth/setup/first-admin`) creates the first admin. There is also CSRF middleware. | `simpletuner/simpletuner_sdk/server/services/cloud/auth/middleware.py`, `simpletuner/cli/__init__.py`, `simpletuner/simpletuner_sdk/server/middleware/csrf.py` |
| State dir | Server SQLite state goes to `SIMPLETUNER_STATE_DIR`. It defaults to a local, non-`/workspace` dir, so **override it to persist** users and jobs. `SIMPLETUNER_CONFIG_DIR` and `SIMPLETUNER_WORKSPACE` are also honored. | `simpletuner/cli/server.py`, `.../cloud/storage/base.py` |
| Latest release | **v4.9.3**, published 2026-10-02 07:05 JST. Releases are frequent (v4.8.0 → v4.9.3 in ~6 weeks), and v4.9.0 had **breaking changes**, so pinning is mandatory. | https://github.com/bghira/SimpleTuner/releases/tag/v4.9.3 |
| PyPI | `simpletuner` 4.9.3 is on PyPI as a **wheel and an sdist** (`simpletuner-4.9.3-py3-none-any.whl`), with Python `>=3.12,<3.15`. License: **AGPL-3.0-or-later**. **[verified 2026-10-06 via the PyPI JSON API; the original draft said sdist only.]** | https://pypi.org/project/simpletuner/ |
| Install extras | `pip install 'simpletuner[cuda]'` installs `torch>=2.11`, torchvision>=0.26, torchaudio>=2.11, triton, bitsandbytes>=0.45, deepspeed>=0.17.2, torchao `>=0.17,<0.18`, `nvidia-cudnn-cu12`, `nvidia-nccl-cu12`, nvidia-ml-py and lm-eval. `[cuda13]` needs `--extra-index-url .../cu130`. `[jxl]` adds the JPEG-XL plugin. Optional extras: captioning (vLLM), transformerengine. | `setup.py` @ v4.9.3 |
| Official Dockerfile | `nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04`, Python 3.12 venv `/opt/venv`, git clone of **branch `main`** (unpinned), `pip install -e ".[jxl]"` plus an explicit dependency list (hf cli, wandb, mpi4py, bitsandbytes, deepspeed, torchao, lm-eval, ramtorch, `sageattention==1.0.6`). EXPOSE 22, 8001. `HF_HOME=/workspace/huggingface`, `SIMPLETUNER_WORKSPACE=/workspace/simpletuner`. It also puts the CUDA **stubs** dir on `LD_LIBRARY_PATH`. | https://github.com/bghira/SimpleTuner/blob/main/Dockerfile |
| Official start script | Writes env to `/etc/rp_environment`, handles SSH keys (`PUBLIC_KEY` for RunPod, `SSH_PUBLIC_KEY` for Vast), runs `huggingface-cli login`, `wandb login`, then `simpletuner server --host 0.0.0.0 --port 8001`. **No auth protection, no Jupyter, no supervision.** | https://github.com/bghira/SimpleTuner/blob/main/docker-start.sh |
| Docker docs | `documentation/DOCKER.md` mentions RunPod/Vast, the SSH key variables, and CUDA mismatch troubleshooting. | repo `documentation/DOCKER.md` |
| Published official image | **No public image found [verified 2026-10-06].** The GHCR package page returns HTTP 404, `.github/workflows` has no container publish (docs, PyPI, Replicate, tests only), and Docker Hub `bghira/simpletuner` returns 404. A private package would also 404 to an anonymous request. | GHCR page, repo workflows, Docker Hub API |
| Inferred problem with the official Dockerfile | **[unverified, inferred]** It does not set a torch index. torch ≥2.11 from PyPI is the **CUDA 13.0 build**, which needs driver ≥580, inside a CUDA 12.8 base. A self-built official image therefore probably needs ≥580 drivers, and the 12.8 base adds nothing. | PyTorch 2.11 release notes (below) |
| Community templates | (a) **StableLlama/SimpleTunerDocker** (Docker Hub `stablellama/simpletuner`): CUDA 12.8–13.3 matrix, built on **standard GitHub runners** with a disk cleanup step, base and final image split, Caddy with `WEB_USER`/`WEB_PASSWORD` in front of the WebUI on port 8000, logs in `/var/log/portal/`. It tracks **`main` (unpinned)**. (b) HartsyAI/Runpod-Serverless-SimpleTuner (serverless, not GUI). (c) GitHub discussion #725, where the community asked for a RunPod template ("spent the entire day…"). (d) An old Civitai RunPod guide pinned to an old commit (obsolete). | https://github.com/StableLlama/SimpleTunerDocker · https://github.com/HartsyAI/Runpod-Serverless-SimpleTuner · https://github.com/bghira/SimpleTuner/discussions/725 · https://civitai.com/articles/6678 |

### 1.2 PyTorch / CUDA facts that drive pinning
- **[verified]** Since PyTorch **2.11**, `pip install torch` from PyPI installs the **CUDA 13.0** build. CUDA 13.0 needs driver ≥580 and supports Turing+ only. cu126 and cu128 wheels stay on `download.pytorch.org`. https://github.com/pytorch/pytorch/releases/tag/v2.11.0
- **[verified]** PyTorch **2.12 removed cu128 builds**. Only cu130 (default) and cu126 (old-driver fallback) remain. https://github.com/pytorch/pytorch/releases
- **[verified]** cu128 supports Volta/Turing/Ampere/Ada/Hopper/**Blackwell (sm_100/sm_120, e.g. RTX 5090)**. Volta was dropped from cu128 in 2.11. https://github.com/pytorch/pytorch/blob/v2.11.0/RELEASE.md
- **[verified]** CUDA minor-version compatibility: a 12.x image runs on any 12.x driver (≥525), with caveats for PTX JIT. 13.x needs driver ≥580. Forward-compat only works on datacenter GPUs. (Vast base-image README)

### 1.3 RunPod
| Item | Finding | Source |
|---|---|---|
| HTTP proxy | `https://[POD_ID]-[INTERNAL_PORT].proxy.runpod.net`. Path is user → Cloudflare → LB → pod. **100 s timeout (HTTP 524)**, HTTPS only, publicly reachable, so the app must do its own auth. Up to 10 HTTP ports. Services must bind `0.0.0.0` to be proxied. | https://docs.runpod.io/pods/configuration/expose-ports |
| TCP | "Expose TCP ports" gives public IP:random port (shown in Connect menu). Mappings change on reset. `RUNPOD_TCP_PORT_<n>` env vars exist for symmetric ports (>70000 trick). No UDP. | same |
| Secrets | Template env values can reference `{{ RUNPOD_SECRET_<name> }}`. Secrets are encrypted and never shown again. | https://docs.runpod.io/pods/templates/secrets |
| Base images | `runpod/base:<template-tag>-cuda1281-ubuntu2404` (also 12.8.0, 12.9.0, 13.0.0, 13.2.0). Built `FROM nvidia/cuda:<v>-cudnn-devel-ubuntu<v>`. Python 3.9–3.13 preinstalled (3.10 default), sshd, Jupyter. `runpod/pytorch` latest tags are on torch 2.9.1 (too old for SimpleTuner ≥2.11). | https://github.com/runpod/containers/tree/main/official-templates/base |
| start.sh convention | `set -e`. Order: start nginx → run **`/pre_start.sh`** → SSH setup if `PUBLIC_KEY` → Jupyter on **8888** only if `JUPYTER_PASSWORD` is set (it becomes the token) or `JUPYTER_DISABLE_AUTH=true` → export env to `/etc/rp_environment` → run **`/post_start.sh`** → `sleep infinity`. Jupyter uses `root_dir=/` and `preferred_dir=/workspace`. **A failing hook kills the container** because of `set -e`. | https://github.com/runpod/containers/blob/main/container-template/start.sh |
| Persistence | `/workspace` is the volume mount (pod volume or network volume). Container disk is wiped on reset. | RunPod docs / templates |
| Pricing (list, page dated 2026-09-27) | Community / Secure, $/h: RTX A5000 24GB **0.16**/0.27 · RTX 3090 **0.22**/0.50 · RTX 4090 **0.34**/0.74 · RTX A6000 48GB 0.33/0.53 · A40 48GB 0.35/0.49 · L4 0.44/0.49 · RTX 5090 0.69/0.99 · L40S 0.79/1.09 · A100 80GB 1.19–1.39/1.59. Storage: container disk $0.10/GB/mo; volume $0.10/GB/mo running and **$0.20/GB/mo idle**; network volume $0.07/GB/mo. | https://www.runpod.io/pricing |

### 1.4 Vast.ai
| Item | Finding | Source |
|---|---|---|
| Launch modes | **Jupyter**, **SSH**, **Entrypoint**. In Jupyter/SSH mode Vast **replaces the image entrypoint** and runs the template's **On-start script**. Env vars set in the template are visible to onstart but not to SSH/Jupyter sessions unless written to `/etc/environment`. Entrypoint mode runs the image as-is, with no Vast SSH/Jupyter. | https://docs.vast.ai/guides/templates/template-settings · https://docs.vast.ai/guides/instances/connect/overview · https://docs.vast.ai/guides/instances/docker-environment |
| Ports | `-p host:container` in docker options. `EXPOSE` is auto-mapped. External ports are random; `VAST_TCP_PORT_<n>` holds the mapping. | docker-environment page |
| vastai/base-image | Built on `nvidia/cuda:*-cudnn-devel-ubuntu*` (12.8, 12.9, 13.x…), with Python env `/venv/main`, uv, Supervisor (`/etc/supervisor/conf.d/`), Jupyter on 8080, Syncthing, Tensorboard, rclone, git-lfs. **Instance Portal** (Caddy) gives TLS (`ENABLE_HTTPS=true`, self-signed), **auth on by default** (Open-button cookie, basic auth `vastai`/`OPEN_BUTTON_TOKEN`, or `WEB_USERNAME`/`WEB_PASSWORD`, bearer token) and **Cloudflare quick tunnels** (`https://xxx.trycloudflare.com`). Tag format: `vastai/base-image:cuda-12.8.1-cudnn-devel-ubuntu24.04-py312`. Vast hosts **cache these base layers**, which makes pulls faster. | https://github.com/vast-ai/base-image |
| PORTAL_CONFIG | `hostname:external_port:internal_port:path:name|…`. When external ≠ internal, Caddy listens on the external port with TLS and auth and proxies to the app on the internal port. Written to `/etc/portal.yaml` on first boot. | same |
| Hooks | `PROVISIONING_SCRIPT` (URL, runs after Supervisor). `PROVISIONING_MANIFEST` (declarative YAML). `HOTFIX_SCRIPT` and `BOOT_SCRIPT`. Derived images can add `/etc/vast_boot.d/NN-*.sh` (scripts before 65 run before Supervisor, 75+ after) and `first_boot/`. `/opt/workspace-internal/` is copied to `/workspace` on first boot. | same |
| Persistence | `/workspace` (`$WORKSPACE`) is the persistent area. Stopped instances keep their disk, but storage is billed. | same |
| Pricing (marketplace, third-party snapshots Oct 2026) | Verified on-demand single-GPU **min / median** $/h: RTX 3090 **0.12 / 0.21** · RTX 4090 0.32 / 0.45 · RTX 5090 0.40 / 0.65 · RTX A6000 0.40 / 0.40 · A40 ~0.40. Storage and bandwidth are billed per host on top. **[third-party, approximate]** | https://sillectus.com/articles/cloud-gpu-pricing-for-llms/ · https://www.glamdringresearch.com/post/vast-ai-pricing |

### 1.5 Image hosting and CI limits
- **[verified]** Standard GitHub-hosted Linux runners provide **14 GB SSD** (4 vCPU/16 GB RAM on public repos, free and unlimited; 2 vCPU/8 GB on private repos, billed minutes). https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- **[verified, precedent]** StableLlama builds a full SimpleTuner CUDA image on `ubuntu-latest` after deleting `/usr/share/dotnet`, `/usr/local/lib/android`, `/opt/ghc` and CodeQL. It pushes to Docker Hub and uses `cache-from/to: type=gha`.
- **[unverified]** Azure runners usually also mount a large temp disk at `/mnt`. Moving the Docker data-root there is a common trick; measure it in CI.
- GHCR: public images are free. Private images count against the account's Packages storage quota, which is small on the Free plan **[unverified exact quota]**, and every RunPod/Vast template would then need registry credentials. Docker Hub: anonymous pulls from shared host IPs are rate-limited **[unverified current limits]**.
- The Hugging Face CLI is now **`hf`** (`hf auth login`, `hf download --repo-type dataset --local-dir …`, `--dry-run` shows sizes, `hf cache prune`, `HF_HUB_DOWNLOAD_TIMEOUT`). `huggingface-cli` is legacy. https://huggingface.co/docs/huggingface_hub/guides/cli

---

## 2. Architecture decision

### 2.1 Options compared
| | **A. Fat image** (everything baked) | **B. Thin** (official base + on-start `pip install` script) | **C. Hybrid (recommended)** |
|---|---|---|---|
| First pull | Large (est. 10–14 GB compressed **[unverified]**). Base layers are often already cached on hosts, so only the ~4–5 GB app layer is new. | Small if the base is cached | Same as A |
| Time to GUI on a fresh pod | Pull + ~30 s | Pull + **5–15 min of pip install on every new pod** (~6–9 GB of wheels) | Pull + ~30 s |
| Reliability | Deterministic. No package-index dependency at boot. | Worst. PyPI or PyTorch-index outages, resolver drift, partial installs, Python mismatch with the base, and disk-full mid-install. This is the #1 failure source for non-programmers. | Deterministic |
| Fixing a bug | Rebuild (~30–60 min CI) and redeploy | Edit the script and redeploy (fast) | Python deps need a rebuild. **Scripts can be hot-fixed** (§2.3) without one. |
| Debuggability | Same bits everywhere. A version report is baked in. | "Works on my pod" drift | Same bits everywhere, plus a build-info file |
| CI disk pressure | High | None | High, mitigated (§9) |

**Decision: C, hybrid.**
- All code and dependencies are baked into the image and locked.
- Models and datasets are never baked. They are downloaded at runtime to `/workspace`.
- Platform-specific behavior is isolated in a thin adapter layer.

### 2.2 One Dockerfile, two flavors, one shared app layer
```
                ┌──────────── stage "app" (FROM ubuntu:24.04) ─────────────┐
                │ uv-managed CPython 3.12.x in /opt/stt/python              │
                │ venv /opt/stt/venv  ← uv pip sync locks/cu128.txt (hashes) │
                │ /opt/stt/bin/* scripts, /opt/stt/share/*, build-info.json  │
                └───────────────────────────────┬───────────────────────────┘
                     COPY --from=app /opt/stt /opt/stt   (byte-identical layer)
          ┌─────────────────────────┴──────────────────────────┐
FROM runpod/base:1.4.0-cuda1281-ubuntu2404       FROM vastai/base-image:cuda-12.8.1-cudnn-devel-ubuntu24.04-py312-2026-09-07
 + supervisor, pinned Caddy binary                   + supervisor program in /etc/supervisor/conf.d/
 + /post_start.sh → stt-start (never fails)          + /etc/vast_boot.d/70-stt.sh, PORTAL_CONFIG default
 → tag …-runpod                                      → tag …-vast
```
Why this shape:
- **The venv is self-contained** (uv's standalone Python, not the base's Python). The same `/opt/stt` layer is built once, stored once in the registry, and behaves identically on both platforms. RunPod's default Python is 3.10 and Vast's is 3.12; this choice makes that difference irrelevant.
- **Each platform runs on its own official base image.** That keeps its conventions working: RunPod's start.sh, SSH and console buttons; Vast's Instance Portal, TLS, Open-button auth, Cloudflare tunnels and SSH key handling. We never fight the platform, and both bases ship a CUDA 12.8.1 devel toolchain (gcc, nvcc, headers) that triton, torch.compile (inductor C++ wrapper) and DeepSpeed JIT need.
- **The two flavors differ only in the "front door"**: how services are started and which proxy adds auth. The scripts, venv and doctor are shared.
- Possible later simplification (spike task T0b): run the **Vast** flavor on RunPod as well, giving a single image. That depends on undocumented behavior, so it is not the default.

### 2.3 Hot-fix channel for scripts (debug aid, off by default)
If `STT_SCRIPTS_REF=<git commit sha>` is set, `stt-start` fetches `scripts/` from `github.com/huagya/simpletuner-template` at that exact commit into `/opt/stt/bin.override/` and puts it first on `PATH`.
- Only full 40-character SHAs are accepted, never branch names.
- It never touches Python deps.
- The doctor reports it as WARN, so overrides are never forgotten.

This lets a bug in a helper or start script be fixed in minutes without rebuilding 10 GB.

---

## 3. Pinned versions (initial proposal)

| Component | Pin | Why |
|---|---|---|
| SimpleTuner | tag **v4.9.3**, plus its commit SHA recorded in `versions.env` | Latest release. Avoid `main` (the official Dockerfile and StableLlama both track main, causing drift). |
| Python | CPython **3.12.x** (uv-managed, exact patch in lock) | Matches upstream Dockerfile, and `python_requires >=3.12,<3.15` |
| torch / torchvision / torchaudio | **2.11.0 + cu128** from `https://download.pytorch.org/whl/cu128` (`torch==2.11.0+cu128`, `torchvision==0.26.0+cu128`, `torchaudio==2.11.0+cu128`). The CPU index has the matching `2.11.0+cpu` wheel, which is what the step-1 spike installed. | **[verified]** cu128 and CPU indexes for cp312 list `2.11.0` and no newer 2.11 patch. cu128 also still has `2.10.0`. cu130 goes through `2.14.1` and has no reason to be the default here. Driver ≥570 for cu128 remains the draft's PyTorch-notes claim and was **not re-checked on a GPU host**. |
| torchao | as resolved within `>=0.17,<0.18` (SimpleTuner pin) | upstream constraint |
| Other deps | Mirror the **official Dockerfile set**: `simpletuner[jxl]==4.9.3` + bitsandbytes, deepspeed, torchao, nvidia-ml-py, lm-eval, ramtorch, `sageattention==1.0.6`, `huggingface_hub[cli]`, wandb. Fully resolved into **`locks/cu128.txt` with hashes** via `uv pip compile --python-platform x86_64-manylinux_2_28 --python-version 3.12` (runs on a CPU CI runner). | The most battle-tested upstream path, but frozen. Skip mpi4py (multi-node only) **[decide during impl]**. |
| CUDA base | `runpod/base:1.4.0-cuda1281-ubuntu2404` digest `sha256:e6eb5a38bd3b321f41e7c584334c9ebc15e1e529574c7f2c866d148990cfb817` (2026-09-30). Vast: **dated** `vastai/base-image:cuda-12.8.1-cudnn-devel-ubuntu24.04-py312-2026-09-07` digest `sha256:c63434109989a5736181bd1c2ad0a0f12c84e24b73b3bce6b3d604932745b410` (2026-09-07). The undated `…-py312` tag exists but is the 2026-01-08 image. | 12.8.1 matches cu128. Digests were read from the Docker Hub API. The images were **not pulled** in step 1, so layer contents and host caching stay **[unverified]**. |
| uv, Caddy, JupyterLab, supervisor | exact versions; Caddy binary pinned by **SHA256** | Supply chain |
| GitHub Actions | pinned by commit SHA | Supply chain |

Also bake in:
- `LD_LIBRARY_PATH` **without** the CUDA `stubs` dir. The upstream Dockerfile adds stubs; a stub `libcuda.so` can shadow the real driver and cause "no CUDA device" errors.
- `PIP_NO_CACHE_DIR=1`.
- `/opt/stt/build-info.json`: git SHA, build date, SimpleTuner version and SHA, torch/CUDA versions, base digests, and `pip freeze`.

A future **cu130 flavor** (torch 2.12+/13.x) can be added once SimpleTuner or the user needs it (e.g. TransformerEngine FP8 on B-series GPUs). For now it would only shrink the set of usable hosts.

---

## 4. Ports, proxy and authentication (most important security section)

Rule: **SimpleTuner and Jupyter never listen on a public interface.** They bind `127.0.0.1`, and only an auth proxy is public. This neutralizes SimpleTuner's "single-user auto-admin" behavior, because everyone who gets through the proxy is the owner.

| Service | Internal | Public (RunPod) | Public (Vast) |
|---|---|---|---|
| SimpleTuner WebUI | `127.0.0.1:18001` | `:8001` via **our Caddy** (basic auth) → `https://<pod>-8001.proxy.runpod.net` | `:8001` via **Instance Portal Caddy** (`localhost:8001:18001:/:SimpleTuner`) |
| JupyterLab | `127.0.0.1:18888` (no token; protected by the proxy) | `:8888` via our Caddy (basic auth) | Vast's Jupyter on 8080 via the portal (`localhost:8080:18080:/:Jupyter`) |
| Instance Portal | — | — | `:1111` |
| SSH | `:22` | TCP 22, key from `PUBLIC_KEY` (RunPod start.sh) | Vast-managed |

- **One password for everything**: `WEB_PASSWORD`, with `WEB_USERNAME` defaulting to `admin` on both platforms (on Vast we set `WEB_USERNAME=admin` so it's consistent).
- **Fail closed**: if `WEB_PASSWORD` is unset or shorter than 12 characters on RunPod, Caddy serves a static Japanese/English page ("パスワード未設定: テンプレートの WEB_PASSWORD を設定して再起動してください") instead of proxying. On Vast, the portal's default auth (OPEN_BUTTON_TOKEN) still applies even without `WEB_PASSWORD`.
- Caddy (RunPod) sketch:
  ```
  { admin off
    auto_https off }
  :8001 {
    basic_auth { {$WEB_USERNAME} {$WEB_PASSWORD_HASH} }   # bcrypt hash made at boot via `caddy hash-password`
    reverse_proxy 127.0.0.1:18001 { flush_interval -1 }      # SSE/log streaming
  }
  :8888 {
    basic_auth { {$WEB_USERNAME} {$WEB_PASSWORD_HASH} }
    reverse_proxy 127.0.0.1:18888
  }
  ```
- We do **not** use SimpleTuner's own multi-user login in v1. **[verified]** `simpletuner auth setup` replaces the auto-created `local` admin and the API then returns 401 until a second login. That breaks the one-password plan. Leave `STT_GUI_ADMIN_PASSWORD` unimplemented in v1. If it is added later, the CLI must be pointed at the app with `SIMPLETUNER_HOST` and `SIMPLETUNER_PORT` (it does not read `--port`).
- Jupyter is started by **our** supervisor, not RunPod's start.sh. In the RunPod template, `JUPYTER_PASSWORD` stays unset, so RunPod's own Jupyter does not start. `JUPYTER_DISABLE_AUTH` is never set.
- Proxy compatibility checks (CI must exercise them):
  - (a) SSE log streams through Caddy with `flush_interval -1`.
  - (b) WebSockets (Jupyter terminals).
  - (c) **CSRF / Origin**: a state-changing POST through the proxy with `Origin: https://<pod>-8001.proxy.runpod.net` must succeed. **[verified in v4.9.3 source and in the CPU spike]** `CSRFMiddleware` is not mounted, and it would compare a cookie to a header, not Origin to Host. A foreign Origin is accepted. Re-check this when the SimpleTuner pin moves. Caddy passes Host through by default.
  - (d) RunPod's **100 s Cloudflare timeout**: long requests (e.g. a synchronous model download triggered from the GUI) may hit 524. SSE with keep-alives should be fine **[unverified]**.

---

## 5. Single start script and logging

`/opt/stt/bin/stt-start` is the only entry point.
- RunPod calls it from `/post_start.sh`.
- Vast calls it from `/etc/vast_boot.d/70-stt.sh`, before Supervisor reads our program file.

Steps, with numbered bilingual log lines:
```
[stt 1/7] 環境を確認 / detecting platform …… RunPod (pod abc123) | image 0.1.0-st4.9.3-cu128-runpod
[stt 2/7] 設定値チェック / validating env … WEB_PASSWORD: set(16 chars) HF_TOKEN: set(hf_****) WANDB: not set
[stt 3/7] フォルダ準備 / preparing /workspace … ok (first boot: README_JA.md copied)
[stt 4/7] GPU 簡易チェック / quick GPU check … NVIDIA RTX 4090, driver 575.x, torch cuda OK (2.1 s)
[stt 5/7] Hugging Face ログイン … ok (token stored in /root/.cache/hf_token, not on the volume)
[stt 6/7] サービス起動 / starting services … simpletuner, proxy, jupyter
[stt 7/7] 起動待ち / waiting for WebUI … ready in 23 s
============================================================
 SimpleTuner WebUI : https://abc123-8001.proxy.runpod.net   (user: admin)
 JupyterLab        : https://abc123-8888.proxy.runpod.net
 困ったら / trouble? → ターミナルで  stt-doctor
============================================================
```
Rules:
- **Fail visible, never fatal.** `stt-start` never exits non-zero and never kills the container. A crash-looping container is undebuggable for a non-programmer. When something fails, it prints the last 50 log lines, a hint, and keeps Jupyter and SSH up. This also matters because RunPod's start.sh runs with `set -e`, so `post_start.sh` must always `exit 0`.
- Secrets are never echoed. Only "set(N chars)" and an `hf_****` prefix are shown.
- Logs go to stdout (visible in the platform's log viewer) **and** to `/workspace/logs/`: `start-YYYYmmdd-HHMMSS.log`, `simpletuner.log`, `proxy.log`, `jupyter.log`. Size caps: supervisor `stdout_logfile_maxbytes=50MB`, 5 backups. On Vast, also symlink `/var/log/portal/simpletuner.log` so the portal log view works.
- SimpleTuner runs under supervisor with `autorestart=true`, `startretries=5` and `stopsignal=INT`. Restarting the server may kill a running training, and `stt-restart` warns about this.
- Env for the server:
  - `SIMPLETUNER_WORKSPACE=/workspace/simpletuner`
  - `SIMPLETUNER_CONFIG_DIR=/workspace/simpletuner/config`
  - `SIMPLETUNER_STATE_DIR=/workspace/simpletuner/.state` (persist the DB)
  - `HF_HOME=/workspace/huggingface`
  - `HF_TOKEN_PATH=/root/.cache/hf_token`
  - `TORCHINDUCTOR_CACHE_DIR=/workspace/.cache/torchinductor`
  - `TRITON_CACHE_DIR=/workspace/.cache/triton`
- Persist env for shells: `/etc/environment` + `/etc/profile.d/stt.sh`. **Exclude secrets** except `HF_TOKEN`, which is needed by the `hf` CLI in Jupyter terminals and is written with mode 600.

---

## 6. `/workspace` layout (persistent volume)
```
/workspace/
├── README_JA.md            # 1-page Japanese guide (copied on first boot if missing)
├── datasets/<name>/        # hf-dataset / uploads (images + .txt captions)
├── models/<name>/          # single-file checkpoints, local copies (e.g. Illustrious .safetensors)
├── huggingface/            # HF_HOME: hub cache SimpleTuner reuses when given a repo id
├── simpletuner/
│   ├── config/             # SIMPLETUNER_CONFIG_DIR: WebUI environments (config.json, multidatabackend.json…)
│   ├── output/             # checkpoints, LoRAs, validation images
│   └── .state/             # SIMPLETUNER_STATE_DIR (SQLite: users, jobs)
├── .cache/{torchinductor,triton}/
├── logs/
└── diagnostics/            # stt-doctor zips
```
- SimpleTuner downloads base models itself when given a HF repo id, into `HF_HOME`. Pre-fetching with `hf-model` puts them in the same cache, so nothing is downloaded twice.
- A layout version file, `/workspace/.stt-layout-version`, allows safe migrations.

---

## 7. Helper commands (installed in `/opt/stt/bin`, on PATH)

All helpers share these behaviors:
- They print Japanese and English messages.
- They **check free space before downloading**. `hf download --dry-run` reports the size; if there isn't enough space, the helper refuses and shows how to free some (`hf cache prune`, delete old outputs).
- They support resume.
- They never print tokens.
- They exit non-zero with a clear message on failure.

| Command | What it does |
|---|---|
| `stt-help` | Japanese menu of all commands, current URLs and typical recipes |
| `hf-model <repo_id> [--file F] [--to NAME]` | `hf download` into the HF cache (default; SimpleTuner reuses it) or `--to /workspace/models/NAME`. For gated repos: if the response is 401/403, it explains "Hugging Face のモデルページでライセンスに同意し、HF_TOKEN を設定してください" with the repo URL. |
| `hf-dataset <repo_id> [NAME] [--include PATTERN]` | `hf download --repo-type dataset --local-dir /workspace/datasets/NAME` |
| `get-url <url> [dest_dir]` | `wget -c` (or aria2c if added). Adds `Authorization: Bearer $HF_TOKEN` automatically **only** for `huggingface.co` URLs. Also handles zip/tar auto-extract with `--extract`. |
| `git-clone-hf <repo_id> [dest]` | git + git-lfs clone using the stored credential. **Warns that git-lfs keeps a second copy in `.git`** (doubles disk) and recommends `hf-model` instead. |
| `unpack <file.zip>` | Extract an uploaded archive into `/workspace/datasets/` (Jupyter drag-and-drop upload is the easy route for the user's own images). |
| `stt-doctor [--zip] [--json] [--model REPO]` | Diagnostics (§8) |
| `stt-logs [simpletuner|proxy|jupyter|start]` | Tail a log |
| `stt-restart [simpletuner|proxy|jupyter]` | Restart via supervisor, with a warning if training is running |
| `stt-disk` | Shows `/workspace` usage by folder, HF cache top items, and suggestions |

Plain `wget`, `git`, `git-lfs`, `hf`, `tmux`, `htop`, `nvtop`, `vim`/`nano`, `zip`/`unzip`, `rsync`, `rclone` are all available directly.

---

## 8. Health check: `stt-doctor`

The doctor prints a table of **PASS / WARN / FAIL / SKIP**, each with an ID, a one-line Japanese explanation and the fix. `--json` gives machine output (used by CI). `--zip` (default when anything FAILs) writes `/workspace/diagnostics/stt-diag-<JST timestamp>.zip`. The user downloads it from Jupyter (right-click → Download) and sends it.

| ID | Check | FAIL / WARN condition → hint |
|---|---|---|
| P01 | Platform, image version, build-info, hot-fix override active? | override → WARN |
| G01 | `nvidia-smi` lists a GPU | none → FAIL "GPU が見えません。GPU 付きのインスタンスか確認" |
| G02 | Driver version ≥ 570 (needed for cu128) | lower → FAIL "CUDA 12.8 以上のホストを選んでください（RunPod/Vast のフィルタ）" |
| G03 | torch imports; `torch.version.cuda`; `cuda.is_available()`; 256 MB matmul on GPU; bf16 supported | any error → FAIL, with the traceback in the zip |
| G04 | Free VRAM now; other processes using the GPU | <90% free at idle → WARN |
| L01 | Key imports: simpletuner (version matches build-info), diffusers, transformers, bitsandbytes (CUDA lib loads), torchao, deepspeed (import only) | FAIL |
| S01 | SimpleTuner answers on `127.0.0.1:18001` | FAIL → show last 30 log lines |
| S02 | Public proxy port returns **401 without credentials** and **200 with them** | 200 without credentials → **FAIL (GUI exposed!)** |
| S03 | Jupyter reachable through the proxy | FAIL |
| A01 | `WEB_PASSWORD` set and ≥12 chars; `JUPYTER_DISABLE_AUTH` not true | FAIL |
| D01 | `/workspace` is a separate mount (persistence) | same device as `/` → WARN "ここに保存したものは停止で消える可能性" |
| D02 | `/workspace` free: <50 GB WARN, <15 GB FAIL; container disk free | — |
| M01 | System RAM (<32 GB WARN for Flux-class models); cgroup `memory.events` `oom_kill` count | oom_kill>0 → FAIL "メモリ不足で強制終了された履歴があります" |
| M02 | `/dev/shm` size (Docker default 64 MB breaks DataLoader workers) | <1 GB → WARN |
| H01 | `HF_TOKEN` set; `hf auth whoami` works | unset → WARN (only needed for gated or private models) |
| H02 | `--model REPO`: HEAD on a file to test gated access | 403 → FAIL with the license URL |
| N01 | Reach huggingface.co (DNS + HTTPS) | FAIL |
| T01 | Scan the last 2,000 lines of simpletuner.log for `CUDA out of memory`, `Traceback`, `No space left`, `Killed` | match → WARN with a model-specific hint (lower batch/resolution, gradient checkpointing, quantize the base model, use 48 GB GPU) |

Zip contents:
- `doctor.txt/json`, `build-info.json`, `pip-freeze.txt`
- `nvidia-smi -q`, `df -h`, mounts, cgroup memory, `ulimit -a`
- logs (last 5,000 lines each)
- SimpleTuner config JSONs (small files only)
- the env

**Redaction** is applied to every file. Any variable or JSON key matching `TOKEN|KEY|SECRET|PASSWORD|PASS|AUTH|COOKIE`, and any `hf_[A-Za-z0-9]{20,}` pattern, becomes `***redacted(len=N)***`. Redaction is covered by CI tests.

---

## 9. Build and publish

- **Registry: GHCR, public** (`ghcr.io/huagya/simpletuner-template`). It's free, needs no extra secrets (`GITHUB_TOKEN`), and RunPod/Vast need no registry credentials. A Docker Hub mirror is optional later. This requires the user's consent to make the repo and image public. Note AGPL: the image contains SimpleTuner (AGPL-3.0), so the README links its source. Our own scripts can be MIT.
- Tags (immutable): `0.1.0-st4.9.3-cu128-runpod`, `0.1.0-st4.9.3-cu128-vast`. Convenience moving tags `runpod`/`vast` are promoted **only after GPU acceptance (§10.2)**. Templates always reference the immutable tag.
- Workflow (`.github/workflows/build.yml`):
  1. Free disk: remove dotnet, android, ghc, CodeQL, and move the Docker data-root to `/mnt` if present (measure).
  2. Buildx with **registry cache** (`type=registry,ref=…:buildcache,mode=max`). The GHA cache is limited in size, so it is not used here.
  3. Build stage `app` once, then both flavors.
  4. Push on tags and `main`. PRs build without pushing.
  5. Write the image size and digest to the job summary.
- Size budget **[unverified estimates]**: app layer (venv) ~7–9 GB uncompressed (~3.5–4.5 GB compressed), dominated by torch and NVIDIA wheels. The base cudnn-devel image is ~5–6 GB compressed (often cached on hosts). Keep the app layer as **one layer** so hosts download it in a single stream.
- Monthly bump workflow (later): a PR that updates the SimpleTuner tag and regenerates the lock. CI runs, then a manual GPU acceptance run, then promotion.

---

## 10. Verification strategy

### 10.1 Automated, no GPU (GitHub Actions and the Cursor cloud agent)
1. **Static**: shellcheck, hadolint, ruff (python helpers), `bats` unit tests.
2. **Lock integrity**: `uv pip compile` reproduces `locks/cu128.txt`; the job fails if the lock is stale. Assert torch is `+cu128`.
3. **Helper tests with mocks**: put fake `hf`, `wget`, `git`, `df` and `nvidia-smi` on `PATH`. Assert:
   - correct arguments and destinations
   - the disk preflight refuses when space is short
   - the auth header is added only for huggingface.co
   - gated 403 produces the Japanese hint
   - exit codes are right
4. **Doctor tests**: fake env (`HF_TOKEN=hf_FAKE…`, `WEB_PASSWORD=…`). Run `stt-doctor --zip --json` and assert the zip exists and **contains no secret strings**. GPU checks report FAIL/SKIP with correct codes.
5. **Container smoke test (CPU)**: run each flavor with `WEB_PASSWORD=ci-password-123456`, `STT_ALLOW_NO_GPU=1` (Vast flavor additionally with `OPEN_BUTTON_TOKEN`, `PORTAL_CONFIG`, `--no-update-portal --no-update-vast`). Wait up to 180 s, then check:
   - `curl :8001` → **401**; with credentials → **200** and the page looks like the SimpleTuner UI
   - Jupyter through the proxy → 200
   - one SSE endpoint streams through the proxy
   - a POST with a foreign Origin header behaves as expected (CSRF)
   - `stt-doctor --json` has S01/S02/S03/A01 = PASS
   
   **[verified in the step-1 spike]** `simpletuner server` starts without a GPU and serves `/web/trainer`. CI smoke tests do not need a GPU stub for process startup. GPU checks inside the UI will still report no GPU; that is expected on the runner.
6. **Stretch**: a CPU-only "training wiring" test with a tiny diffusers pipeline. Only if SimpleTuner accepts such a model; **[unverified]**.

### 10.2 Needs a real GPU (manual, run by the user or with their API key and approval)
Acceptance runbook (`docs/ACCEPTANCE.md` plus a `stt-selftest-train` script that drives the SimpleTuner CLI with a bundled 8-image dataset):
1. Deploy the template. `stt-doctor` must be all PASS.
2. Open the GUI and Jupyter through the platform URLs. Download a public model and a small dataset with the helpers.
3. **Smoke train**: SD 1.5 LoRA (`stable-diffusion-v1-5/stable-diffusion-v1-5`, non-gated, ~2 GB), 512 px, rank 4, batch 1, **10 steps**, no validation. Expect it to finish and produce a `.safetensors` file.
4. **Representative train** (if the user targets SDXL/Illustrious): SDXL LoRA, 1024 px, 20 steps, on a 24 GB GPU.
5. Restart the pod. Check that `/workspace` data, the SimpleTuner state and configs persist, and that the GUI comes back without a password prompt loop.
6. Confirm GUI log streaming stays alive for more than 5 minutes through the RunPod proxy (100 s timeout check).
7. Test gated access using a repo the user has accepted.

### 10.3 Cheapest GPUs and cost estimate for the acceptance run
| Platform | GPU | Price | Note |
|---|---|---|---|
| RunPod Community | RTX A5000 24 GB | $0.16/h | Cheapest 24 GB. Fine for SD1.5 and SDXL LoRA. |
| RunPod Community | RTX 3090 / 4090 24 GB | $0.22 / $0.34/h | — |
| RunPod Community | A40 / RTX A6000 48 GB | $0.35 / $0.33/h | Only needed for Flux-class tests |
| Vast (verified, on-demand) | RTX 3090 | ~$0.12–0.21/h | Plus storage and bandwidth (host-specific) |
| Vast | RTX 4090 | ~$0.32–0.45/h | — |

- One session per platform is ~1 h: image pull 5–15 min, model download, 10–20 training steps, restart test. That's ≈ **$0.20–0.50 per platform** of GPU time.
- Storage: a 100 GB RunPod volume costs ~$0.33/day while running and ~$0.67/day idle. **Delete test volumes afterwards.**
- **Budget ≈ $3 total including retries.** Use **on-demand** (not interruptible) instances and filter hosts for **CUDA ≥ 12.8**.

---

## 11. Template settings (what the user clicks)

### RunPod template
- Image: `ghcr.io/huagya/simpletuner-template:0.1.0-st4.9.3-cu128-runpod`
- Container disk: 40 GB. Volume: 100 GB at `/workspace` (SDXL) or 200 GB (Flux). A network volume is optional (keeps data between pods, $0.07/GB/mo, ties you to one datacenter).
- Expose HTTP ports: `8001,8888`. TCP: `22`.
- Env:
  - `WEB_PASSWORD={{ RUNPOD_SECRET_stt_password }}`
  - `HF_TOKEN={{ RUNPOD_SECRET_hf_token }}`
  - optional `WANDB_API_KEY`
  - `WEB_USERNAME=admin`
- Start command: empty (the image CMD runs RunPod's `/start.sh`, which calls our `/post_start.sh`).
- GPU filter: CUDA 12.8+.

### Vast template
- Easiest and safest path: **copy Vast's own recommended template built on vastai/base-image** (e.g. their PyTorch template) and change only the image and env. That keeps the launch mode and on-start exactly as Vast intends **[unverified which mode they use; check when implementing]**.
- Image: `ghcr.io/huagya/simpletuner-template:0.1.0-st4.9.3-cu128-vast` (built FROM the dated Vast base tag in §3, not the 2026-01 undated tag)
- Ports: `-p 1111:1111 -p 8080:8080 -p 8001:8001 -p 22:22`
- Env:
  - `PORTAL_CONFIG="localhost:1111:11111:/:Instance Portal|localhost:8080:18080:/:Jupyter|localhost:8001:18001:/:SimpleTuner"`
  - `WEB_USERNAME=admin`, `WEB_PASSWORD=…`, `HF_TOKEN=…`
  - `ENABLE_HTTPS=true` (optional)
- Make the template **private** if it contains secrets. Account-level env vars on Vast are an alternative **[unverified]**.
- Disk: 100–200 GB. Host filter: CUDA ≥ 12.8, verified, on-demand.

---

## 12. Secrets handling (summary)
| Secret | Passed as | Stored where | Notes |
|---|---|---|---|
| GUI/Jupyter password | `WEB_PASSWORD` (RunPod Secret / Vast template env) | RunPod: bcrypt hash in container memory/tmp. Vast: portal config. | Never logged. Doctor checks its length. |
| HF token | `HF_TOKEN` | `HF_TOKEN_PATH=/root/.cache/hf_token` (container disk, **not** the persistent volume); git credential store in `/root` | Recommend a **fine-grained read token** with "read access to public gated repos" |
| SSH | RunPod `PUBLIC_KEY` / Vast account keys | `~/.ssh/authorized_keys` | Platform-native |
| W&B | `WANDB_API_KEY` (optional) | wandb netrc in `/root` | — |

Never bake secrets into the image, never put them in `/workspace`, and always redact them in diagnostics.

---

## 13. Main risks and mitigations
| Risk | Mitigation |
|---|---|
| **GUI exposed to the internet** (SimpleTuner auto-admin when no users exist) | Bind to 127.0.0.1 only. Auth proxy on both platforms. Fail closed without a password. Doctor S02 checks for 401. CI asserts 401. |
| Jupyter = root shell exposed | Always behind the same auth. Never `JUPYTER_DISABLE_AUTH`. |
| **Version drift** (SimpleTuner releases weekly, with breaking changes; torch index defaults changed) | Pin tag and SHA, hash-locked deps, immutable image tags, monthly bump PR + GPU acceptance before promotion, keep old tags for rollback |
| **CUDA/driver mismatch** | cu128 build (driver ≥570), host filter "CUDA ≥ 12.8", doctor G02/G03 with a clear message. No CUDA stubs on `LD_LIBRARY_PATH`. Optional cu130 flavor later. |
| Port/proxy issues (Cloudflare 100 s, SSE buffering, WebSockets, CSRF/Origin, random Vast ports) | Caddy `flush_interval -1`, CI tests for SSE/WS/POST through the proxy, platform-native URLs printed in the banner, Vast portal links |
| **Disk full** (models 7–60 GB each, git-lfs doubling, checkpoints) | Helper preflight with `--dry-run` sizes, doctor D02, `stt-disk`, recommend checkpoint limits in the Japanese guide, log size caps, git-lfs warning |
| **GPU OOM / RAM OOM / small /dev/shm** | Doctor T01/M01/M02 hints. Japanese guide maps model → minimum VRAM (SDXL LoRA 24 GB OK; Flux/Qwen-Image → 48 GB or quantization). SimpleTuner ships measured VRAM presets for some models. |
| Container crash loop is undebuggable | "Fail visible, never fatal" start script; RunPod hooks always exit 0 |
| Image pull slow or failing | One big app layer, cached official bases, GHCR public (no auth), choose hosts with good bandwidth |
| Upstream behavior unknowns (CPU start, CSRF behind proxy, Vast launch mode) | Spike tasks first (T0a/T0b) and CI smoke tests before any GPU spend |
| Supply chain | Pin actions by SHA, Caddy by checksum, base images by digest, hash-locked pip |
| Cost leaks (forgotten pods, idle volumes billed at 2×) | Japanese guide section "止め方・消し方", banner reminder |
| Licensing | AGPL source link in README; model licenses (e.g. FLUX.1-dev is non-commercial) mentioned in the Japanese guide |

---

## 14. Open questions only the user can answer
1. Do you already have **RunPod** and/or **Vast.ai** accounts with credit? Which one should be supported and tested **first**?
2. May we create a **public** GitHub repo `huagya/simpletuner-template` and a **public** GHCR image? (Public avoids registry login and storage fees. Nothing secret goes in it.) Or do you prefer Docker Hub, and do you have an account?
3. Do you have a **Hugging Face account and token**? Which **gated** models will you use (e.g. FLUX.1-dev needs license acceptance on the HF website)?
4. **Which models do you want to train?** SDXL-family (Illustrious / NoobAI / Pony), Flux.1 / Flux.2, Qwen-Image, Z-Image, video (Wan/LTX)? This decides GPU size (24 GB vs 48 GB+) and disk size (100 vs 200+ GB).
5. LoRA only, or full fine-tunes too?
6. Rough **budget** per month and per training run? Is Vast's marketplace (cheaper, variable hosts) acceptable, or do you prefer RunPod Secure Cloud?
7. Where do your **training images** come from? Upload from your PC (drag-and-drop in Jupyter / zip), a HF dataset, or a URL?
8. Persistent storage preference: keep data between sessions (network volume, ongoing cost) or start fresh each time?
9. Is **one password** (user `admin`) for GUI and Jupyter OK?
10. Who runs the paid **GPU acceptance test** (~$3)? You, following a Japanese checklist, or should we use an API key you provide?
11. Do you use Weights & Biases? (Optional.)
12. Language: helper messages will be Japanese and English. The SimpleTuner GUI itself is English. **[verified]** v4.9.3 templates and `simpletuner/static` have no Japanese strings; `README.ja.md` and `documentation/**/*.ja.md` do. Is an English GUI OK?

---

## 15. Implementation task split (small tasks for a Cursor cloud agent)
Each task must be verifiable inside the agent's own environment (no GPU), per the team rule. GPU checks are a separate, user-approved step.

| # | Task | Done when (agent-verifiable) |
|---|---|---|
| **T0a** | **Spike: SimpleTuner server on CPU behind Caddy.** In a venv, install `simpletuner[cpu]==4.9.3`. Start the server on 127.0.0.1, put Caddy basic auth in front, then test 401/200, an SSE stream, a POST with an Origin header (CSRF), and the single-user behavior. | Short report with curl transcripts. Decides whether CI smoke tests need a GPU stub. |
| T0b | (Optional) Spike notes: how Vast's own templates on vastai/base-image set launch mode and on-start; whether the Vast flavor could also run on RunPod | Written findings; no paid launch without approval |
| T1 | Repo bootstrap (**needs user approval to create the repo**): layout, MIT license for our code + AGPL notice, README_JA skeleton, CI lint (shellcheck, hadolint, ruff, bats) | CI green on an empty skeleton |
| T2 | `versions.env` + lock generation (`uv pip compile` for cu128, Python 3.12, hashes) + CI staleness check | Lock resolves on a CPU runner; torch is `+cu128`; check job fails when the lock is edited by hand |
| T3 | Dockerfile stage `app` (uv Python, venv from lock, build-info.json) + CPU import smoke (`import simpletuner, torch, diffusers`) + size report | Builds in CI; imports OK; size recorded |
| T4 | Common scripts: `stt-start` (7 steps, never fatal), env defaults, `/workspace` layout init (idempotent), supervisor program files, log caps, banner | bats tests: idempotent layout, secrets never printed, exit 0 on failures |
| T5 | Helpers: `hf-model`, `hf-dataset`, `get-url`, `git-clone-hf`, `unpack`, `stt-disk`, `stt-help` (JA/EN) | bats with mocked `hf`/`wget`/`git`/`df`: arguments, preflight refusal, HF-only auth header, gated hint |
| T6 | `stt-doctor` (+ `--json`, `--zip`, redaction) | Tests: report codes on a fake env; zip contains no injected fake secrets |
| T7 | RunPod flavor: FROM pinned `runpod/base…cuda1281-ubuntu2404`, supervisor, pinned Caddy, `/post_start.sh`, fail-closed page | CPU container smoke test in CI: 401/200, Jupyter via proxy, SSE, doctor S01–S03/A01 PASS |
| T8 | Vast flavor: FROM pinned `vastai/base-image:cuda-12.8.1-cudnn-devel-ubuntu24.04-py312`, supervisor conf, `/etc/vast_boot.d/70-stt.sh`, default PORTAL_CONFIG | CPU container smoke test: portal auth 401/200 on 8001 → SimpleTuner; doctor PASS on service checks |
| T9 | CI/CD: build both flavors, disk cleanup / data-root on `/mnt`, registry cache, push to GHCR on tag, SHA-pinned actions, size and digest in the job summary | Tag build pushes both images; summary shows sizes |
| T10 | Templates + Japanese docs: RunPod template JSON and click guide, Vast template guide, `README_JA.md` (start, download, train, stop/delete), troubleshooting keyed by doctor IDs | Docs reviewed; links and commands match the scripts (doc-lint test greps command names) |
| T11 | `stt-selftest-train` + `docs/ACCEPTANCE.md` (SD1.5 10-step and SDXL 20-step LoRA) | Script dry-run mode tested on CPU (config generation only) |
| T12 | **GPU acceptance (manual, costs ~$3, needs user approval and account)** on RunPod and Vast, then promote the `runpod`/`vast` tags | Doctor all PASS + the two training runs + restart persistence, recorded in the repo |
| T13 | (Later) Monthly bump workflow; optional cu130 flavor | — |

Suggested order: T0a → T1 → T2 → T3 → (T4, T5, T6 in parallel) → T7 → T8 → T9 → T10 → T11 → T12.
Agent settings per team context: grok-4.7, reasoning medium, fast off.

---

## 16. Things still unconfirmed after the step-1 spike
Confirmed items moved to the corrections list at the top. Still open:
- SSE / long requests through RunPod's Cloudflare proxy beyond 100 s (the local Caddy spike only proves Caddy does not buffer `/api/events`).
- Whether RunPod hosts cache `runpod/base:1.4.0-cuda1281-ubuntu2404` layers. The tag and digest are known; caching is not.
- Which launch mode Vast's own base-image templates use (T0b). The dated tag exists; it was not pulled.
- Whether SimpleTuner upstream's own CI runs on torch 2.11 or a newer cu130 build. The package constraint is `torch>=2.11`.
- Image size estimates; free disk on current GitHub runners (incl. `/mnt`).
- That a self-built official Dockerfile actually resolves torch cu130 (inferred from PyTorch ≥2.11 PyPI defaults; not built here).
- Vast storage/bandwidth prices (host-specific) and Vast account-level env vars.
- GHCR private storage quota and Docker Hub anonymous pull limits.
- Numeric VRAM for a PixArt Sigma full fine-tune (the Sigma guide never states one) and whether `model_family=pixart` vs `pixart_sigma` both complete a real training step.
- Driver ≥570 on a live cu128 host (not tested; this VM has no GPU).
