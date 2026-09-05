---
name: harness-hooks
description: 第2層。CLAUDE.md の「必ず〜」「〜しないこと」のうち譲れないものをフックで機械的に強制する。編集後のフォーマットと型チェック、不可逆操作の停止、応答終了時の CLAUDE.md 追記候補の収集、セッション開始時の文脈注入を、起動ディレクトリの .claude/settings.json に提案・承認・書込する。
argument-hint: "[起動ディレクトリ]"
disable-model-invocation: true
---

# 第2層: フックで譲れないものを強制する

対象: `$ARGUMENTS`（空ならカレントディレクトリ。**このディレクトリの `.claude/settings.json` に書きます。親の設定は継承されません**）

CLAUDE.md の指示は行動を誘導するもので、強制ではありません。毎回守らせたいことはフックに移します。Anthropic は、フックの価値は「誤りを防ぐ」より「継続的に改善する」ことにあると述べています。このスキルは両方を入れます。

**注意**: 4本のフックはいずれも stdin の JSON を解釈するために python3 または node を使い、どちらも無い環境、または存在しても実行に失敗する環境（例: pyenv shim が未導入バージョンを指す）では sed/grep による簡易抽出（tier3）にフォールバックします。特に `guard-irreversible.sh` は、tier3 になった時点、および command を取り出せなかった場合（不正な JSON・command 空を含む）に、常に stderr に警告を出します。その上で通常と同じパターン照合を続けて行うため、`rm -rf` のような危険なコマンドは tier3 でも変わらず止めます。見逃すのはネストした引用符など一部の複雑なケースに限られます（複数行のコマンドは `\n`・`\t` を実際の改行・タブに復元してから判定するため、tier3 でも通常どおり止まります）。対象リポに python3 も node も無い場合は、この制約を人に伝えてください。

## 探索

1. Skill ツールで `harness-audit` を呼び、第2層の節を確認します。「ルートの設定はこのディレクトリから起動した場合には読み込まれません」の注意が出ていれば、人に伝えます。
2. 起動時に読み込まれる CLAUDE.md から、次に当たる行を抜き出します。
   - 「必ず〜を実行する」（フォーマット、lint、テスト、型チェック）
   - 「〜してはいけない」（削除、強制 push、本番反映、外部送信、課金）
   - 「〜のときは〜を読む」（領域ごとの案内）
3. 既存の `.claude/settings.json` と `.claude/hooks/` があれば読み、既に何が入っているかを把握します。
4. リポのフォーマッタと型チェックのコマンドを設定ファイルから特定します（`package.json` の scripts、`pyproject.toml` など）。

## 提案書

`harness-proposal-hooks.md` を起動ディレクトリに書き出します。書式は `templates/proposal.md` です。

| 追加するもの | テンプレート | 探索結果で埋める箇所 |
|---|---|---|
| `.claude/hooks/format-and-check.sh`（PostToolUse, Edit\|Write） | `templates/hooks/format-and-check.sh` | `case` の各言語のフォーマッタ・チェックコマンド |
| `.claude/hooks/guard-irreversible.sh`（PreToolUse, Bash） | `templates/hooks/guard-irreversible.sh` | 止める操作のパターン。CLAUDE.md の禁止文から起こす。本番反映のコマンドはリポ固有。既定の `kubectl` 判定はコマンド文字列に `prod` を含むかどうかの簡易一致のため、対象リポでは `--context`/`-n` の実値（例: `--context prod-cluster`、`-n production`）を列挙する形に置き換えることを検討する。既定の DB クライアント判定に含む `DELETE FROM` は DML で頻度が高く、WHERE 句付きのスコープされた正当な削除も止まるため、頻繁に実行するリポではこの選択肢だけ外して構わない |
| `.claude/hooks/stop-propose-claudemd.sh`（Stop） | `templates/hooks/stop-propose-claudemd.sh` | 変更不要（候補の出力先は `.claude/harness-kit/`） |
| `.claude/hooks/session-start-context.sh`（SessionStart） | `templates/hooks/session-start-context.sh` | `case` の領域ごとの一言 |
| `.claude/settings.json` の `hooks` | `templates/settings/hooks.json` | 既存の settings があれば diff でマージ案を示す |

あわせて、フックに移した CLAUDE.md の行を「CLAUDE.md からは削除する」提案として並べます（強制に移した文を CLAUDE.md にも残すと、二重管理になります）。

提案書の「承認後の確認手順」には、次の3つを書きます。

1. `chmod +x .claude/hooks/*.sh`
2. 新しいセッションを開き、SessionStart の出力が最初に表示されること
3. 適当なファイルを1つ編集し、フォーマットが掛かること。故意に型エラーを入れて、フックの指摘が返ること

## 承認待ち

提案書を書いたら止まります。

> `harness-proposal-hooks.md` を書きました。採用する項目を `[x]` にして「承認」と言ってください。止める操作のパターンは、リポの実態に合わせて提案書の中で編集して構いません。

## 書込

1. 既存の `.claude/settings.json` と `.claude/hooks/` を `.claude/harness-kit/backup/<YYYYMMDD-HHMMSS>/` に退避します。
2. `[x]` の項目だけを書き込みます。`settings.json` は既存のキーを残し、`hooks` だけを追加・更新します。
3. スクリプトに実行権限を付けます。
4. フックのコマンドパスは `${CLAUDE_PROJECT_DIR}/.claude/hooks/...` のまま使います。起動ディレクトリを基準に解決されます。

## 確認

提案書の確認手順を人に案内し、結果を聞きます。型チェックの指摘が返らなければ、`format-and-check.sh` の `case` を見直します。

## 補助ファイル

- `templates/proposal.md`: 提案書の書式
- `templates/settings/hooks.json`: `hooks` の断片
- `templates/hooks/*.sh`: 4本のフック
