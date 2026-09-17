# jellyfin

Jellyfin (公式イメージ 1 コンテナ)。構成の意図は `compose.yaml` と
`backup.conf` のコメントに書いてある。

## 初期セットアップ

```sh
cd /selfhost/compose/jellyfin
docker compose up -d
docker compose logs -f jellyfin
```

`data/config` `data/cache` と `media/{movies,shows,music}` はリポジトリに
`.gitkeep` 入りで含めてあるので、作る手順はいらない。docker に bind mount 先を
自動生成させると root 所有になり、`user: "1000:1000"` で動く Jellyfin が
書けなくなる (`/config` なら起動ループ)。clone した時点で clone した人の所有で
存在するようにしている。消してしまった場合は `docker compose up` の前に自分で
`mkdir` すること。ライブラリを増やすときは `.gitkeep` を置いて `.gitignore` の
否定行に 1 行足す。

`http://server26.mullet-tiyanki.ts.net:10103/` を開くとセットアップウィザードが
出るので、管理者アカウントを作ってライブラリを追加する。パスはコンテナ内のものを
指定すること:

| ホスト                            | コンテナ内      | 用途                         |
| --------------------------------- | --------------- | ---------------------------- |
| `compose/jellyfin/media/movies`   | `/media/movies` | 映画                         |
| `compose/jellyfin/media/shows`    | `/media/shows`  | TV 番組                      |
| `compose/jellyfin/media/music`    | `/media/music`  | 音楽                         |
| `compose/jellyfin/media/seafile`  | `/media/seafile`| Seafile から同期した動画     |
| `compose/ytzero/data/downloads`   | `/ytzero`       | ytzero の録画 (読み取り専用) |

ytzero だけ `/media` の外に置いてある。理由は `compose.yaml` のコメント参照
(`./media` 自体が bind mount なので、その下をマウント先にすると root 所有の
空ディレクトリがホスト側に生える)。

`/ytzero` は ytzero が書いた `<video-id>.mp4` が並ぶだけでメタデータの
命名規則に従っていないので、ライブラリ種別は「映画」や「TV 番組」ではなく
**ホームビデオと写真 (Home Videos & Photos)** にしておくとマッチングで
おかしな結果にならない。

## メディアの置き方

ファイル名から作品を特定するので、命名が雑だとメタデータが付かない。

```
media/movies/Some Movie (2019)/Some Movie (2019).mkv
media/shows/Some Show/Season 01/Some Show S01E01.mkv
```

詳細は <https://jellyfin.org/docs/general/server/media/movies/>。

## Seafile に置いた動画を見る

`media/seafile/` は `/selfhost/scripts/media-sync.sh` が Seafile のライブラリから
15 分ごとに一方向コピーしている。セットアップは `/selfhost/scripts/README.md` 参照。

Jellyfin 側は `/media/seafile` を指すライブラリを 1 つ作るだけでよい。Seafile に
置いたファイルがそのままの名前で並ぶので、命名が上の規則に従っていないなら
`/ytzero` と同じく **ホームビデオと写真** にしておくのが無難。

新しいファイルは Jellyfin のリアルタイム監視が拾うので、原則は自動で出てくる。
出てこないときは管理画面 > ライブラリ > **すべてのライブラリをスキャン**。

## バックアップ

`backup.conf` があるので `restic-backup.timer`(毎日 02:00) が自動で拾う。
サービスを止めてから `./data` を取り、終わったら再開する。

**`./media` はバックアップしていない**。理由と足し方は `backup.conf` のコメントを
読むこと。ライブラリの設定・ユーザー・視聴履歴 (`./data/config`) は戻せるが、
メディア本体は戻せない構成になっている。`./media/seafile` だけは例外で、原本が
seafile 側のバックアップに入っているので実質守られている。

手動実行は `sudo systemctl start restic-backup.service`、確認は
`sudo journalctl -u restic-backup.service -n 50`。

## アップグレード

`compose.yaml` でイメージを `10.10.7` に固定してある。

```sh
docker compose pull && docker compose up -d
```

の前にタグを上げる。Jellyfin はアップグレード時に `library.db` の
マイグレーションが走り、**ダウングレードはできない**。マイナー更新でも先に
`sudo systemctl start restic-backup.service` でバックアップを取ってからにすること。

## 入れていないもの

- **ハードウェアトランスコード**: このホストは NVIDIA GPU なので
  `nvidia-container-toolkit` が要る。Jellyfin は再生側が対応している形式なら
  そのまま流す (Direct Play) ので、まず CPU で困るか見てから足す。
- **リバースプロキシ / HTTPS**: ytzero・seafile と同じく Tailscale 内で
  HTTP 直結。
- **DLNA**: 既定で無効。有効にするならホストネットワークかポート 1900/udp が要る。
