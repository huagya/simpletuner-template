# Windows で SimpleTuner を開く

Windows 10 または 11、RTX 4060 Ti（16GB）、メモリ 32GB を想定しています。プログラミングは不要です。使うファイルは `start.bat`、`stop.bat`、`logs.bat`、`doctor.bat` です。

画面は `http://127.0.0.1:8001`、Jupyter は `http://127.0.0.1:8888` です。どちらもこの PC の中だけから開きます。ユーザー名は `admin`。パスワードは `windows\.env` の `WEB_PASSWORD` です。

## 1. Docker Desktop を入れる

1. ブラウザで https://docs.docker.com/desktop/setup/install/windows-install/ を開き、Docker Desktop for Windows をダウンロードします。
2. インストーラを実行します。「Use WSL 2 instead of Hyper-V」にチェックが入っていることを確認して進みます（最初からチェックされています）。
3. 再起動を求められたら再起動します。
4. スタートメニューから Docker Desktop を起動し、左下が **Running** になるまで待ちます。

## 2. WSL2 にする

Windows 11 と、新しい Windows 10 では、Docker Desktop のインストール時に WSL2 も入ります。入らなかったときは、スタートメニューで「PowerShell」を右クリックして「管理者として実行」し、次を実行して再起動します。

```powershell
wsl --install
```

再起動後、Docker Desktop の **Settings → General** で **Use the WSL 2 based engine** にチェックを入れ、**Apply & restart** を押します。

`start.bat` は、Docker の context が `desktop-linux` であることと、`wsl -l -v` の `docker-desktop` の VERSION が 2 であることを確認します。違うときは、直し方を表示して画面を閉じません。

## 3. WSL に渡すメモリを 24GB にする

32GB の PC では、何もしないと WSL2 が使えるメモリが少なすぎることがあります。学習の前に一度だけ設定します。

1. エクスプローラのアドレスバーに `%UserProfile%` と入力して Enter します。
2. メモ帳で新しいファイルを作り、次の 3 行だけを書きます。

```ini
[wsl2]
memory=24GB
swap=8GB
```

3. 「名前を付けて保存」で、ファイル名を `.wslconfig` にします。種類は「すべてのファイル」です。`.wslconfig.txt` にしないでください。保存場所は `%UserProfile%`（例: `C:\Users\あなたの名前\.wslconfig`）です。
4. PowerShell で次を実行します。

```powershell
wsl --shutdown
```

5. Docker Desktop を終了し、もう一度起動して Running になるまで待ちます。

## 4. 起動する

`windows` フォルダの `start.bat` をダブルクリックします。

初回はパスワードを聞きます。英数字 12 文字以上を入力するか、何も入力せず Enter すると自動で作ります。パスワードは画面に出さず、`windows\.env` に保存します。

次に GPU を `nvidia-smi` で確認し、イメージを取得します。公開タグは `versions.env` の `IMAGE_TAG`（いまは `v0.1.0`）です。レジストリにまだ無いときは、この PC でイメージを作ります。初回の作成は長くかかります。

起動するとブラウザが開きます。ユーザー名 `admin`、パスワードは `.env` です。

## 5. データの場所

速さのため、モデルのキャッシュと学習結果は Docker の名前付きボリューム `stt-data` に置きます。中身は WSL2 の Linux 側のディスクなので、Windows のフォルダに直接置くより速くなります。

データセットだけは、このフォルダの `datasets` です。エクスプローラで `windows\datasets` を開き、画像を入れてください。コンテナからは `/workspace/datasets` に見えます。

ボリュームの中（モデルや診断 zip）をエクスプローラで見たいときは、Jupyter（`http://127.0.0.1:8888`）で `/workspace` を開くのが確実です。`\\wsl$\docker-desktop\mnt\docker-desktop-disk\data\docker\volumes\` にボリュームがある版と、`\\wsl$\docker-desktop-data\data\docker\volumes\` にある版があります。Docker Desktop の更新でパスが変わるので、普段は Jupyter を使ってください。

全部を Windows のフォルダにしたい場合は、`docker-compose.yml` の `volumes` を次のように変えます。小さいファイルをたくさん読む学習は遅くなります。

```yaml
volumes:
  - C:\SimpleTuner:/workspace
```

`C:\SimpleTuner` は先に作っておきます。`datasets` の行と `stt-data` の行は消します。

## 6. 止める、ログ、診断

- `stop.bat` はコンテナを止めます。ボリュームと `datasets` は残します。
- `logs.bat` はログを表示します。止めるときは Ctrl+C です。
- `doctor.bat` は GPU、パスワード、ディスクを確認します。zip は `/workspace/diagnostics` にできます。Jupyter の `diagnostics` フォルダからダウンロードしてください。

失敗したときは、黒い画面に「失敗」と「直し方」が出ます。キーを押すまで閉じません。

## 7. 新しいイメージに更新する

1. `versions.env` の `IMAGE_TAG` を、公開されたタグ（例: `v0.2.0`）に変えます。
2. `start.bat` を実行します。そのタグを取得します。取得できないときは、この PC でビルドします。
3. ボリューム `stt-data` と `datasets` はそのまま残ります。

まだ一度もタグを公開していない間は、取得に失敗してからローカルビルドに落ちます。それが正常です。
