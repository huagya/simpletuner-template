# Handoff — step 1 (feasibility spike + repo skeleton)

Date: 2026-10-06. Nothing was published. No GPU was used. No RunPod or Vast instance was started.

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
