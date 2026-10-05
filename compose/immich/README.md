# immich

Immich v3.2 系 (server + machine-learning + PostgreSQL + Valkey)。写真・動画の
バックアップと閲覧。構成の意図は `compose.yaml` と `backup.conf` のコメントに書いてある。

## 初期セットアップ

```sh
cd /selfhost/compose/immich
cp .env.example .env
openssl rand -hex 24   # DB_PASSWORD
chmod 600 .env

docker compose up -d
docker compose logs -f server
```

`data/` 配下の bind mount 先はリポジトリに `.gitkeep` 入りで含めてあるので作る手順は
いらない (docker に作らせると root 所有になり、`user: "1000:1000"` で動くコンテナが
書けない)。

### 最初のユーザー (管理者)

**最初に登録したユーザーが管理者になる**。起動したらすぐに
`http://server26.mullet-tiyanki.ts.net:10106/` を開いて自分のアカウントを作ること。
2 人目以降は管理画面 > ユーザー から管理者が作る (自分で登録する画面はない)。

### 管理画面で最初にやること

- **設定 > バックアップ (データベースのバックアップ)**: Immich 自身の DB ダンプの
  時刻を 02:00 から **01:00 などにずらす**。既定の 02:00 は `restic-backup.timer` が
  このスタックを止める時刻とぶつかる。
- **設定 > サーバー > 外部ドメイン**: `http://server26.mullet-tiyanki.ts.net:10106`
  を入れる。共有リンクの URL がこれで組み立てられる。

スマホアプリのサーバー URL も同じ `http://server26.mullet-tiyanki.ts.net:10106`。

## ディスク

写真・動画は `data/library` に溜まる。ここは `/` (98G の SSD) なので、本格的に
入れる前に空きを見ておくこと。足りなくなったら HDD に移して `compose.yaml` の
`./data/library` のマウントだけ書き換える (DB は SSD に残す)。

## バックアップ

`backup.conf` があるので `restic-backup.timer`(毎日 02:00) が自動で拾う。
全コンテナを止めてから `./data` (DB・写真の原本・サムネイル) と `./.env` を取る。
ML モデルとジョブキューは外している。

**写真の原本がまるごと restic に入る**ので、リポジトリも同じだけ大きくなる。

復元は `scripts/README.md` の「リストア手順」どおり。DB (`data/postgres`) と
写真 (`data/library`) は同じスナップショットから戻すこと。別々の時点を混ぜると
DB に載っているのにファイルが無い写真ができる。

## アップグレード

`compose.yaml` でイメージを `v3.2.4` に固定してある (マイナー版のタグが無いので
パッチ版まで書いている)。上げるときは

1. <https://github.com/immich-app/immich/releases> のリリースノートを読む
   (Immich はマイナー版でも破壊的変更を入れる)
2. 新しいリリースの `docker-compose.yml` と見比べ、`database` / `redis` の
   イメージ (digest) が変わっていれば合わせる
3. バックアップを取ってから `server` と `machine-learning` のタグを書き換え、
   `docker compose pull && docker compose up -d`

起動時に DB マイグレーションが走り、戻すにはバックアップから戻すしかない。
