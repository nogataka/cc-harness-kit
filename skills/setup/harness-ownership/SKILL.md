---
name: harness-ownership
description: ハーネスの所有者（DRI）と構成レビューの周期を文書に残す。3〜6か月ごと、または主要モデルのリリース後に見直す運用を、docs/agents/harness-owner.md として提案・承認・書込する。
argument-hint: "[起動ディレクトリ]"
disable-model-invocation: true
---

# オーナーシップ: 所有者と見直しの周期を決める

対象: `$ARGUMENTS`（空ならカレントディレクトリ）

技術的な構成だけでは導入は進みません。Anthropic は、専任チームが無い組織でも最低1人の DRI（直接責任者）を置くこと、3〜6か月ごとに構成を見直すことを勧めています。現行モデル向けに書いた指示や、旧モデルの制約を回避するために入れたフックは、将来のモデルでは足かせになるからです。

一人で使うリポでも、次回の見直し日を1行残す価値はあります。日付が無いと見直しは起きません。

## 探索

1. Skill ツールで `harness-audit` を呼び、オーナーシップの節を確認します。
2. 人に2つ確認します。

   > このリポのハーネス（CLAUDE.md、フック、権限、プラグイン）を決めて保つのは誰ですか。
   > 次に構成を見直すのはいつにしますか。（推奨: 3か月後。新しい主要モデルが出て性能が頭打ちだと感じたら前倒し）

3. `git log --since='6 months ago' -- CLAUDE.md .claude/ | head` で、最近ハーネスを触った人と頻度を見ます。DRI の候補の参考にします。

## 提案書

`harness-proposal-ownership.md` を起動ディレクトリに書き出します。書式は `templates/proposal.md` です。

- `docs/agents/harness-owner.md` の全文（`templates/harness-owner.md` を探索結果で埋める）
- ルートの CLAUDE.md の「必要時に読むもの」に1行足す提案: 「ハーネスの所有と見直し予定は `docs/agents/harness-owner.md` にあります」
- 規制業種や大きな組織なら、承認済みスキルの一覧、コードレビューの必須化、限定的な初期アクセスから始める案を「追加の提案」として添えます

## 承認待ち

提案書を書いたら止まります。

> `harness-proposal-ownership.md` を書きました。DRI と次回見直し日を確認し、「承認」と言ってください。

## 書込

1. 既存の `docs/agents/harness-owner.md` と CLAUDE.md を `.claude/harness-kit/backup/<YYYYMMDD-HHMMSS>/` に退避します。
2. `[x]` の項目を書き込みます。

## 確認

- `harness-audit` を再実行し、オーナーシップが「充足」になることを確認します。
- 次回見直し日をカレンダーなど、リポの外のリマインダーにも入れることを人に勧めます。文書だけでは通知が来ません。

## 補助ファイル

- `templates/proposal.md`: 提案書の書式
- `templates/harness-owner.md`: オーナー文書の雛形
