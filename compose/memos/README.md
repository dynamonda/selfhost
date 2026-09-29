# memos

Memos 0.31 系 (公式イメージ 1 コンテナ、DB は SQLite)。メモを書き溜める。
構成の意図は `compose.yaml` と `backup.conf` のコメントに書いてある。

## 初期セットアップ

```sh
cd /selfhost/compose/memos
docker compose up -d
docker compose logs -f memos
```

`data/` はリポジトリに `.gitkeep` 入りで含めてあるので作る手順はいらない
(docker に作らせると root 所有になり、`user: "1000:1000"` で動くコンテナが
DB を書けない)。秘密情報は無いので `.env` も無い。

## 最初のユーザー (管理者)

**最初に登録したユーザーが管理者になる**。起動したらすぐに
`http://server26.mullet-tiyanki.ts.net:10105/` を開いて自分のアカウントを作ること。

作ったら 設定 > 一般 (インスタンス設定) で **ユーザー登録を無効** にする。
そのままだと tailnet に入れる人なら誰でもアカウントを作れる。

## バックアップ

`backup.conf` があるので `restic-backup.timer`(毎日 02:00) が自動で拾う。
止めてから `./data` (`memos_prod.db` と添付ファイル) を取る。

添付ファイルの保存先を S3 などに変えた場合、その中身はここでは取れない。

## アップグレード

`compose.yaml` でイメージを `0.31` に固定してある。0.31.x のパッチ更新は

```sh
docker compose pull && docker compose up -d
```

で入る。次のマイナー版 (0.32 など) は起動時に DB マイグレーションが走り、
**ダウングレードできない**。リリースノート
(<https://github.com/usememos/memos/releases>) を読み、バックアップを取ってから
タグを書き換える。
