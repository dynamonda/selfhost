# scripts

ホスト側で動かすスクリプト。いずれも `/selfhost/systemd/` の unit から呼ばれる。

| スクリプト | unit | 役割 |
| --- | --- | --- |
| `backup.sh` | `restic-backup.timer` (毎日 02:00) | `compose/*/backup.conf` を置いたサービスを restic でバックアップ |
| `media-sync.sh` | `media-sync.timer` (15 分ごと) | Seafile のライブラリを Jellyfin のメディアディレクトリに一方向コピー |

unit はリポジトリに置いてあるだけなので、`/etc/systemd/system/` にリンクして
有効化するまでは動かない。

## media-sync のセットアップ

Seafile はライブラリの中身をブロック単位の content-addressed ストアに持っていて、
ディスク上に実ファイルとして存在しない。Jellyfin に見せるには実ファイルの見た目を
作る必要があり、ここではコピーを選んでいる。なぜマウント (seaf-fuse / rclone mount)
ではないのかは `media-sync.sh` の冒頭に書いてある。

### 1. Seafile 側

同期元のライブラリ (例: `Videos`) を作り、そこに動画を置く。

同期に使うアカウントは、管理者ではなく**そのライブラリを共有した専用アカウント**を
作るのが望ましい。認証情報が `media-sync.env` に平文相当で載るため。

### 2. 設定ファイル

```sh
cd /selfhost/scripts
cp media-sync.env.example media-sync.env
chmod 600 media-sync.env
```

`SEAFILE_USER` と `SEAFILE_LIBRARY` を書く。パスワードは平文ではなく難読化した
文字列を `SEAFILE_PASS` に入れる。**コマンドラインに直接書かないこと** —
`!` `$` `'` などが混ざっているとシェルに食われ、意図と違う文字列が難読化される。
標準入力から渡せば確実で、履歴にも残らない:

```sh
read -rsp 'Seafile のログインパスワード: ' p; echo
printf '%s' "$p" | docker run --rm -i rclone/rclone:1.68 obscure -
```

**入れるのは Seafile の「ログインパスワード」**。ユーザー設定にある
**WebDAV パスワードではない**。別物で、rclone の seafile バックエンドが使うのは
前者 (`/api2/auth-token/` を叩く) の方。

貼る前に、そのパスワードで本当にログインできるか確かめておくと早い
(`200` なら正しい。`400` なら違う):

```sh
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST http://server26.mullet-tiyanki.ts.net:10102/api2/auth-token/ \
  --data-urlencode "username=<SEAFILE_USER と同じ値>" \
  --data-urlencode "password=$p"
unset p
```

分からなくなったら管理画面 > ユーザー から当該アカウントのパスワードを
リセットして作り直すのが早い。

### 3. 手で 1 回流して確かめる

```sh
sudo /selfhost/scripts/media-sync.sh
```

`--max-delete 25` の安全弁が入っているので、設定を取り違えて同期先を丸ごと
消すことはない (その場合はここで失敗する)。

### 4. タイマーを有効にする

unit は `/etc/systemd/system/` に**コピーして**使う (`restic-backup` と同じ流儀)。
timer だけをパス指定で enable すると `media-sync.service` が解決できないので、
両方を置いてから enable すること。

```sh
sudo cp /selfhost/systemd/media-sync.service /selfhost/systemd/media-sync.timer \
        /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now media-sync.timer
systemctl list-timers media-sync.timer
```

コピーなので、リポジトリ側の unit を直しただけでは反映されない。直したら
`cp` と `daemon-reload` をやり直すこと。

確認は `sudo journalctl -u media-sync.service -n 50`。

## 注意

- **一方向コピーである**。Jellyfin 側 (`media/seafile/`) で消したり動かしたりしても
  次の同期で Seafile の状態に戻される。原本は常に Seafile の方。
- 毎晩 02:00 の `restic-backup.service` は seafile コンテナを止める。その間に
  タイマーが当たったら `media-sync.sh` は何もせず終了し、次回に回す。
- ディスクは Seafile のブロックと同期コピーで二重に食う。足りなくなったら
  `media-sync.env` の `DEST` を外付けに向け、`compose/jellyfin/compose.yaml` の
  マウントも合わせて直す。
