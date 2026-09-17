# seafile

Seafile Community Edition 13 (seafile + MariaDB + Redis)。
構成の意図は `compose.yaml` と `backup.conf` のコメントに書いてある。

## 初期セットアップ

```sh
cd /selfhost/compose/seafile
cp .env.example .env
# 秘密情報を生成して .env に書く
openssl rand -hex 24   # SEAFILE_MYSQL_DB_PASSWORD
openssl rand -hex 24   # INIT_SEAFILE_MYSQL_ROOT_PASSWORD
openssl rand -hex 32   # JWT_PRIVATE_KEY
# 管理者アカウントとホスト名も埋める
chmod 600 .env

docker compose up -d
docker compose logs -f seafile   # 初回は DB 作成とマイグレーションで数分かかる
```

起動したら `http://server26.mullet-tiyanki.ts.net:10102/`(= `.env` の
`SEAFILE_SERVER_HOSTNAME`) に `INIT_SEAFILE_ADMIN_EMAIL` でログインする。

`INIT_*` は初回起動時にしか読まれない。以降の管理者追加やパスワード変更は
Seafile の管理画面から行う。

## バックアップ

`backup.conf` があるので `restic-backup.timer`(毎日 02:00) が自動で拾う。
逆に言うと、`.env` を作るまでは `docker compose` が必須変数不足で失敗し、
夜間バックアップが seafile の分だけエラーで終わる。

サービスを止めてから `./data` と `./.env` を取り、終わったら再開する。
手動実行は `sudo systemctl start restic-backup.service`、確認は
`sudo journalctl -u restic-backup.service -n 50`。

復元は「`./data` と `./.env` を戻してから `docker compose up -d`」。
DB (`data/mysql`) と実ファイル (`data/seafile`) は同じスナップショットから
戻すこと。別々の時点を混ぜるとライブラリのメタデータと実体がずれる。

## アップグレード

`compose.yaml` でイメージを `13.0-latest` に固定してある。マイナー更新は

```sh
docker compose pull && docker compose up -d
```

で足りる。メジャー(13 → 14)は DB マイグレーションが走り飛び級もできないので、
先に <https://manual.seafile.com/latest/upgrade/upgrade_docker/> の upgrade notes を
読み、バックアップを取ってからタグを書き換える。

## 入れていないもの

- **caddy**: 公式構成の自動 HTTPS。ホストの 80/443 と docker.sock を要求する。
  現状は Tailscale 内で HTTP 直結なので不要。
- **seadoc**: オンライン文書編集。caddy のパスルーティング前提なので、caddy を
  入れない限り動かない。必要になったら公式の `caddy.yml` / `seadoc.yml` を持ってきて
  `ENABLE_SEADOC=true` にする。
- **notification-server / Seafile AI**: いずれも既定で無効。
