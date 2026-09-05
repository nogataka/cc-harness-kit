---
name: harness-skills
description: 第3層。CLAUDE.md に残っている手順やチェックリストを、必要なときだけ読み込まれるスキル（.claude/skills）と、対象ファイルを読んだときだけ読み込まれる paths 付き rules（.claude/rules）に切り出す。提案・承認・書込。
argument-hint: "[起動ディレクトリ]"
disable-model-invocation: true
---

# 第3層: 手順をスキルへ、領域の規約を rules へ

対象: `$ARGUMENTS`（空ならカレントディレクトリ）

CLAUDE.md は毎セッション読まれます。数十種類の作業手順を全部そこに書くと、関係ない手順で毎回コンテキストを使います。手順はスキルにすると、本文はタスクで必要になったときだけ読み込まれます。特定のディレクトリだけの規約は、`paths` 付きの rules にすると、一致するファイルを Claude が読んだときだけ読み込まれます。

## 探索

1. Skill ツールで `harness-audit` を呼び、第3層の節（スキル本数、rules 本数、CLAUDE.md 内の番号付き手順の行数）を確認します。
2. 起動時に読み込まれる CLAUDE.md から、次を抜き出します。
   - 番号付きの手順（リリース、レビュー、検証、デプロイ、セットアップ）
   - 「〜のときは〜する」の形で、特定の場面にしか要らない知識
   - 特定のディレクトリやファイル種別にだけ当たる規約（`src/api/` の応答形式、`migrations/` の扱い）
3. 既存の `.claude/skills/` と `.claude/rules/` を読み、重複しそうなものを把握します。
4. 領域（`packages/*` など）が分かれているなら、手順がどの領域に属するかを分けます。

## 提案書

`harness-proposal-skills.md` を起動ディレクトリに書き出します。書式は `templates/proposal.md` です。

| 切り出し先 | 使う場面 | テンプレート | 置き場所 |
|---|---|---|---|
| スキル | 手順・チェックリスト。人が `/名前` で呼ぶか、Claude が場面で開く | `templates/skills/SKILL.md` | 全体に関わるものはルートの `.claude/skills/<名前>/`、領域固有のものはその領域の `.claude/skills/<名前>/` |
| paths 付き rules | 特定ファイル種別・ディレクトリの規約 | `templates/rules/path-rule.md` | `.claude/rules/<名前>.md`（`paths` に glob） |

各項目について、提案書に次を書きます。

- 新規ファイルの全文（テンプレートの `<...>` を CLAUDE.md の元の文で埋める）
- CLAUDE.md から削除する行の diff
- CLAUDE.md に残す1行（例: 「リリースは `release` スキルに従ってください」）

スキルの `description` は、Claude がそれを開くかどうかを判断する材料です。依頼文に含まれそうな語を先頭に置き、120 文字以内にします。スキルが増えると説明文は短く切られるためです。

## 承認待ち

提案書を書いたら止まります。

> `harness-proposal-skills.md` を書きました。採用する項目を `[x]` にして「承認」と言ってください。

## 書込

1. 変更する CLAUDE.md を `.claude/harness-kit/backup/<YYYYMMDD-HHMMSS>/` に退避します。
2. `[x]` のスキルと rules を作成し、対応する CLAUDE.md の行を削除して参照の1行に置き換えます。
3. `/harness-claudemd` から申し送られた移動項目があれば、それも同じ提案書に含めて処理します。

## 確認

- 新しいセッションで `/名前` と打ち、作ったスキルが一覧に出ることを人に確認してもらいます。
- rules は、`paths` に一致するファイルを1つ読ませ、規約が効いた振る舞いになるかを見ます。
- CLAUDE.md の行数が減ったことを `harness-audit` の第1層で確認します。

## 補助ファイル

- `templates/proposal.md`: 提案書の書式
- `templates/skills/SKILL.md`: スキルの雛形
- `templates/rules/path-rule.md`: paths 付き rules の雛形
