## What it does

`harness-exclusions` は、生成物・ビルド成果物・サードパーティコードを Claude の探索から外します。検索除外は `.gitignore`、チェックイン済みファイルの読み取り拒否は `permissions.deny` の `Read(...)` ルールで行い、2つの役割を分けて提案します。`.claudeignore` は正式機能ではないため生成せず、対象リポにあれば効いていないと伝えます。

## When to reach for it

`/harness-exclusions` と打ちます。Claude が自分で開くことはありません。

- `vendor/`、生成コード、大きなフィクスチャがチェックインされているときに使います。
- 監査で `.claudeignore` の警告や候補ディレクトリが出たときに使います。

## Common questions

**`.gitignore` に入れれば十分ではありませんか。**
Git 管理外のものはそれで十分です。チェックインされている生成コードや vendored SDK は `.gitignore` に入れられないので、読み取り拒否が要ります。

**一部の人だけ拒否を外したいです。**
deny はスコープ間でマージされ、個人設定で打ち消せません。例外が要るパスは共有の deny に入れず、CLAUDE.md で「編集しない」と案内するなど別の手段にします。

## It's working if

- 拒否したパスのファイルを読ませようとすると、拒否されます。
- 検索結果に拒否したパスが出ません。
- `/context` に、拒否したディレクトリの CLAUDE.md や rules が載っていません。
