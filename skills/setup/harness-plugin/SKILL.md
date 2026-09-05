---
name: harness-plugin
description: 第4層。チームで共有するスキル・フック・MCP 設定をプラグインとして配る準備をする。公式マーケットプレイスのプラグイン有効化（enabledPlugins）と、社内マーケットプレイスの登録（extraKnownMarketplaces）を起動ディレクトリの .claude/settings.json に提案・承認・書込する。
argument-hint: "[起動ディレクトリ]"
disable-model-invocation: true
---

# 第4層: プラグインで配布する

対象: `$ARGUMENTS`（空ならカレントディレクトリ。設定は**このディレクトリの `.claude/settings.json`** に書きます）

良い構成を作っても、一部の人の環境にしか無ければ組織の生産性は上がりません。プラグインはスキル、フック、MCP 設定を1つに束ねて配る手段です。ただし、一人で使うリポなら `~/.claude/skills` に置くほうが早いので、このスキルは最初に「共有するか」を聞きます。

## 探索

1. Skill ツールで `harness-audit` を呼び、第4層の節（`enabledPlugins`、`extraKnownMarketplaces`）を確認します。
2. 人に1つ確認します。

   > このリポのハーネスを、他の人の環境にも同じ状態で配りますか。（配らないなら、このスキルは公式プラグインの有効化だけを提案して終わります）

3. `.claude/skills/` と `.claude/hooks/` に、他リポでも使えそうな汎用のものがあるかを見ます。

## 提案書

`harness-proposal-plugin.md` を起動ディレクトリに書き出します。書式は `templates/proposal.md` です。

**共有しない場合**は、`enabledPlugins` に公式マーケットプレイスのプラグインを列挙する提案だけを出します。対象は `/harness-lsp` が選んだ LSP プラグインと、必要なら `github` などの外部連携プラグインです。

**共有する場合**は、加えて次を提案します。

- `extraKnownMarketplaces` に社内マーケットプレイス（GitHub リポ）を登録する断片（`templates/settings/plugins.json`）
- 社内マーケットプレイスの作り方の手順（`.claude-plugin/marketplace.json` と `plugin.json` を持つリポを1つ作る。中身は公式ドキュメント「Create and distribute a plugin marketplace」に従う）
- 汎用のスキル・フックをそのリポへ移す候補の一覧

提案書に、次の事実を明記します。

- `extraKnownMarketplaces` と `enabledPlugins` を書いても、外部ソースのプラグインは各メンバーがインストールしないと入りません。Claude Code が未インストールを検知してコマンドを案内します。
- 全員に強制したい場合は、管理者が管理設定（managed settings）で配ります。

## 承認待ち

提案書を書いたら止まります。

> `harness-proposal-plugin.md` を書きました。採用する項目を `[x]` にして「承認」と言ってください。

## 書込

1. `.claude/settings.json` を `.claude/harness-kit/backup/<YYYYMMDD-HHMMSS>/` に退避します。
2. `[x]` の項目を `settings.json` に追加します。既存のキーは残します。
3. 社内マーケットプレイスの作成は、このリポの外の作業なので手順の案内だけにします。

## 確認

- 新しいセッションで `/plugin` を開き、Installed タブに有効化したプラグインが載っているか、Errors タブに何も無いかを人に確認してもらいます。
- 「Run /reload-plugins to activate.」と出たら、その通り実行してもらいます。

## 補助ファイル

- `templates/proposal.md`: 提案書の書式
- `templates/settings/plugins.json`: `extraKnownMarketplaces` と `enabledPlugins` の断片
