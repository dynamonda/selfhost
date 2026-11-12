# leantime

Leantime 3.13 系 (leantime + MySQL 8.4)。プロジェクト管理。構成の意図は
`compose.yaml` と `backup.conf` のコメントに書いてある。

## 初期セットアップ

```sh
cd /selfhost/compose/leantime
cp .env.example .env
openssl rand -hex 24   # DB_PASSWORD
openssl rand -hex 32   # SESSION_PASSWORD
chmod 600 .env

docker compose up -d
docker compose logs -f leantime
```

`data/` 配下の bind mount 先はリポジトリに `.gitkeep` 入りで含めてあるので作る手順は
いらない (docker に作らせると root 所有になり、`user: "1000:1000"` で動くコンテナが
書けない)。

### 最初のユーザー (管理者)

起動したらすぐに `http://server26.mullet-tiyanki.ts.net:10107/install` を開き、
DB のテーブル作成と管理者アカウントの登録を済ませること。**済ませるまでは、
この URL を開けた人が誰でも管理者を作れる**。

2 人目以降は管理画面 > ユーザー管理 から招待する。メール送信 (SMTP) は
設定していないので、招待メールは届かない。必要になったら `compose.yaml` に
`LEAN_EMAIL_*` (公式の sample.env 参照) を足す。

## バックアップ

`backup.conf` があるので `restic-backup.timer`(毎日 02:00) が自動で拾う。
両コンテナを止めてから `./data` (DB・添付ファイル・プラグイン) と `./.env` を取る。
`data/logs` は外している。停止は 2 秒ほどで終わることを確認した。

復元は `scripts/README.md` の「リストア手順」どおり。DB (`data/mysql`) と
添付ファイル (`data/userfiles`) は同じスナップショットから戻すこと。

## アップグレード

`compose.yaml` でイメージを `3.13.2` に固定してある (マイナー版のタグが無いので
パッチ版まで書いている)。上げるときは

1. <https://github.com/Leantime/leantime/releases> のリリースノートを読む
2. <https://github.com/Leantime/docker-leantime> の `docker-compose.yml` と
   見比べ、MySQL のバージョンや必要な設定が変わっていないか確かめる
3. バックアップを取ってから `leantime` のタグを書き換え、
   `docker compose pull && docker compose up -d`

起動後、DB の更新が必要な版では画面に更新ボタンが出るので押す。戻すには
バックアップから戻すしかない。
