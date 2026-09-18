# filebrowser

FileBrowser Quantum 1.5 系 (公式イメージ 1 コンテナ)。ホストの `/home/dynamonda` を
ブラウザから読み書きする。構成の意図は `compose.yaml` `config.yaml` `backup.conf` の
コメントに書いてある。

## 初期セットアップ

```sh
cd /selfhost/compose/filebrowser
cp .env.example .env
openssl rand -hex 16   # FILEBROWSER_ADMIN_PASSWORD
openssl rand -hex 32   # FILEBROWSER_JWT_TOKEN_SECRET
chmod 600 .env

docker compose up -d
docker compose logs -f filebrowser
```

`data/` はリポジトリに `.gitkeep` 入りで含めてあるので作る手順はいらない
(docker に作らせると root 所有になり、`user: "1000:1000"` で動くコンテナが
`database.db` を書けない)。

`http://server26.mullet-tiyanki.ts.net:10104/` を開き、ユーザー名 `admin` と
`.env` の `FILEBROWSER_ADMIN_PASSWORD` でログインする。

## admin のパスワード

1.5 は起動のたびに admin のパスワードを `FILEBROWSER_ADMIN_PASSWORD` で上書きする。
UI から変えても、次の再起動 (毎晩 02:00 のバックアップでも止まる) で戻る。
変えるときは `.env` を書き換えて `docker compose up -d`。

## 見えないようにしているもの

ホームを丸ごと見せているので、二段で塞いでいる。

1. **`~/.ssh` と `~/.claude`**: コンテナ内で空の読み取り専用 tmpfs を被せてある。
   ファイルそのものがコンテナから見えないので、どの API からも取れない。
2. **その他のドットファイル** (`.bashrc` `.bash_history` `.claude.json` など):
   `config.yaml` のルールで一覧と通常の閲覧からは消してある。ただしこれは
   アプリ側の判定で、**1.5.6 では `/api/resources/download` にパスを直接
   渡すと取れてしまう**。ログインできる人から隠す手段にはなっていない。

秘密を持つディレクトリがホームに増えたら (例: `~/.aws` `~/.config/gh`)、
`compose.yaml` に tmpfs を 1 つ足す。足す前にホスト側にそのディレクトリが
存在することを確認すること (無いと docker が root 所有で作る)。
ファイル単体は塞げない (理由は `compose.yaml` のコメント)。

WebDAV も同じ理由で閉じてある (`config.yaml` の `disableWebDAV`)。

## バックアップ

`backup.conf` があるので `restic-backup.timer`(毎日 02:00) が自動で拾う。
止めてから `./data` (ユーザー・共有リンク・設定の `database.db`) と `./.env` を取る。

**見せているホーム自体はここでは取っていない**。filebrowser は窓口でしかないので。

## アップグレード

`compose.yaml` でイメージを `1.5-stable` に固定してある。1.5.x のパッチ更新は

```sh
docker compose pull && docker compose up -d
```

で入る。2.0 系は DB の形式と環境変数が変わるので、上げるときは
<https://filebrowserquantum.com/> の移行手順を読み、バックアップを取ってから
タグを書き換える。そのとき上の「見えないようにしているもの」の確認
(`~/.ssh/id_ed25519` を download API で取れないこと) もやり直すこと。
