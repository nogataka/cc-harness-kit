---
name: harness-exclusions
description: 生成物・ビルド成果物・サードパーティコードを Claude の探索から外す。検索除外は .gitignore、チェックイン済みファイルの読み取り拒否は permissions.deny の Read ルールで行う。.claudeignore は正式機能ではないので使わない。提案・承認・書込。
argument-hint: "[起動ディレクトリ]"
disable-model-invocation: true
---

# 除外: 検索除外と読み取り拒否

対象: `$ARGUMENTS`（空ならカレントディレクトリ。`permissions.deny` は**このディレクトリの `.claude/settings.json`** に書きます）

Claude が生成コードや vendored SDK を読むと、コンテキストを無駄にし、検索結果に雑音が混ざります。除外は2つの仕組みを役割で分けて使います。

| 仕組み | 効く範囲 | 使う対象 |
|---|---|---|
| `.gitignore`（検索除外） | Claude の検索結果から外れる。既定で尊重される | `node_modules/`、`dist/`、`build/` など、そもそも Git 管理外のもの |
| `permissions.deny` の `Read(...)`（読み取り拒否） | ファイルの読み取り自体が止まる。`cat`、`head`、`grep` などの Bash 経由も対象 | チェックイン済みの生成コード、vendored SDK、大きなデータ |

`.claudeignore` は Claude Code の正式機能ではありません（2026年9月時点）。対象リポにあれば「効いていない」と伝えます。

## 探索

1. Skill ツールで `harness-audit` を呼び、除外の節（`.gitignore` の主要項目、読み取り拒否の件数、`.claudeignore` の警告、候補ディレクトリ）を確認します。
2. リポルートで大きいディレクトリを把握します。`du -sh */ 2>/dev/null | sort -rh | head -20` と、`git ls-files | sed 's|/.*||' | sort | uniq -c | sort -rn | head -20` を実行し、ファイル数の多いトップレベルを見ます。
3. 次に当たるものを候補にします。
   - `vendor/`、`third_party/`、`node_modules/` 相当でチェックインされているもの
   - `*.generated.*`、`__generated__/`、`*.pb.go` などの生成コード
   - `fixtures/` や `snapshots/` の大きなデータ、画像・バイナリの束
4. 例外が要るもの（コードジェネレータを触る人が読む必要があるファイル）を人に確認します。deny はスコープ間でマージされ、個人設定で打ち消せないため、例外が要るパスは共有の deny に入れません。

## 提案書

`harness-proposal-exclusions.md` を起動ディレクトリに書き出します。書式は `templates/proposal.md` です。

- `.gitignore` に足す行（あれば）
- `permissions.deny` の `Read(...)` ルール一覧（`templates/settings/deny.json` を元に、候補ごとに1行）。各行に「なぜ読ませないか」と「おおよそのファイル数」を添えます
- `.claudeignore` があれば削除の提案と、その理由
- 例外が要るために deny から外したパスと、その扱い（読み取りは許すが CLAUDE.md で「編集しない」と案内する、など）

## 承認待ち

提案書を書いたら止まります。

> `harness-proposal-exclusions.md` を書きました。採用する項目を `[x]` にして「承認」と言ってください。

## 書込

1. `.claude/settings.json` と `.gitignore` を `.claude/harness-kit/backup/<YYYYMMDD-HHMMSS>/` に退避します。
2. `[x]` の項目を書き込みます。`settings.json` の既存キーは残し、`permissions.deny` に追記します。
3. `.claudeignore` の削除が承認されていれば削除します。

## 確認

- 拒否したパスのファイルを Claude に読ませようとして、拒否されることを確認します。
- `/context` で、拒否したディレクトリの CLAUDE.md や rules が読み込まれていないことを見ます。
- 検索（Grep）の結果に拒否したパスが出ないことを1回確かめます。

## 補助ファイル

- `templates/proposal.md`: 提案書の書式
- `templates/settings/deny.json`: `permissions.deny` の断片
