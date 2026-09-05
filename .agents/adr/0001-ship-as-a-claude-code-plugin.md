# ADR-0001: Claude Code プラグインとして配布する

日付: 2026-09-05 / 状態: 採用

## 背景

このスキル集の生成物は Claude Code 固有の設定（`.claude/settings.json` のフック、`permissions.deny`、`enabledPlugins`、公式マーケットプレイスの LSP プラグイン）です。Codex など他のハーネスでは生成物が意味を持ちません。

## 決定

- Claude Code プラグイン（`.claude-plugin/plugin.json`）として配布します。`skills` 配列に promoted スキルを明示列挙し、それ以外は含めません。
- `.claude-plugin/marketplace.json` を置き、このリポジトリ自身を単一プラグインのマーケットプレイスにします。利用者は `/plugin marketplace add <owner>/cc-harness-kit` の後に `/plugin install cc-harness-kit@cc-harness-kit` で入れられます。
- 開発中のローカル導入は `scripts/link-skills.sh` で `~/.claude/skills` にシンボリックリンクを張ります。
- Codex など他ハーネスへの対応は行いません。スキル本文は Agent Skills 規格に沿うので読むことはできますが、`!` による動的コンテキスト注入と生成物は Claude Code でしか動きません。

## 帰結

- `plugin.json` の `version` は `package.json` と同じ値に保ちます。`scripts/sync-plugin-version.mjs` が揃えます。
- スキルを追加・削除したら `plugin.json` と `README.md` の両方を更新します。
- 公開（GitHub public 化、公式マーケットプレイスへの申請）はこの ADR の範囲外で、所有者の判断で行います。
