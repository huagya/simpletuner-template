# simpletuner-template

RunPod 向け（次に Vast.ai）の SimpleTuner 公式 WebUI 用 Docker イメージとテンプレートです。プログラミングなしで、ブラウザから学習を始められるようにします。

このリポジトリはまだ骨格だけです。イメージはビルドしておらず、公開もしていません。

## いま入っているもの

- `docs/DESIGN.md` — 設計案。先頭に、調査で直した点を書いてあります。
- `HANDOFF.md` — 決めたこと、確認できた事実、未確認、失敗。
- `versions.env` — 固定するバージョン（SimpleTuner のコミット、Python、torch、ベースイメージ）。
- `scripts/feasibility_proxy_test.sh` — GPU なしのマシンで、WebUI が起動するか、パスワード付きプロキシ越しにページ・ログ配信・設定保存ができるかを試します。失敗すると終了コードが 0 以外になります。

## What this is

A custom image and templates so a non-programmer can run the official SimpleTuner WebUI (`simpletuner server`, port 8001) on RunPod first and Vast.ai second.

Nothing is published yet. Step 1 only checks the risky assumptions and leaves this skeleton.

## Run the feasibility check

Needs Python 3.12 with the `venv` module, `curl`, and `sha256sum`. It installs `simpletuner[cpu]==4.9.3` and Caddy into `/tmp/stt-feasibility` (override with `STT_WORK`).

```bash
bash scripts/feasibility_proxy_test.sh
```

## License

SimpleTuner is AGPL-3.0-or-later: https://github.com/bghira/SimpleTuner
Scripts added in this repo are MIT unless a file says otherwise.
