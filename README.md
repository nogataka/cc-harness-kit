# cc-harness-kit

Claude Code のハーネス（CLAUDE.md、フック、スキル、プラグイン、LSP、MCP、サブエージェント）を、既存のリポジトリに **構築順** で組み立てるスキル集です。現状を採点する監査スキル1本と、各層を「探索、提案書、承認、書込」の順で整える setup スキル8本から成ります。

Anthropic のブログ「How Claude Code works in large codebases」と、Claude Code 公式ドキュメント「Set up Claude Code in a monorepo or large codebase」で示された実践を、そのまま手を動かせる形にしたものです。生成物は Claude Code 専用です。

## 何をしてくれるか

| 層 | スキル | 起動 | すること |
|---|---|---|---|
| 全体 | `harness-init` | 人 | 監査を実行し、未充足の層から順に次のスキルを案内する司令塔 |
| 監査 | `harness-audit` | 人 / Claude | 7層の充足度を採点する。読み取り専用 |
| 第1層 | `harness-claudemd` | 人 | CLAUDE.md をルートとサブディレクトリの2段に整え、各 200 行未満に。自明な記述の削除、禁止ルールの判断基準化、手順のスキル化を提案 |
| 第2層 | `harness-hooks` | 人 | 譲れないものをフックで強制。編集後のフォーマットと型チェック、不可逆操作の停止、応答終了時の CLAUDE.md 追記候補の収集、セッション開始時の文脈注入 |
| 第3層 | `harness-skills` | 人 | CLAUDE.md の手順をスキルへ、領域の規約を paths 付き rules へ切り出す |
| 第4層 | `harness-plugin` | 人 | 公式プラグインの有効化と、社内マーケットプレイスの登録 |
| 第5層 | `harness-lsp` | 人 | 言語を検出し、公式のコードインテリジェンスプラグインを有効化。バイナリ未導入なら手順を案内して止まる |
| 除外 | `harness-exclusions` | 人 | `.gitignore` の点検と `permissions.deny` の読み取り拒否ルール |
| 運用 | `harness-ownership` | 人 | DRI と構成レビューの周期を文書に残す |

第6層 MCP と第7層 サブエージェントは専用スキルを持ちません。監査が現状を報告し、`harness-init` が運用上の判断として案内します。

## 導入

Claude Code のセッション内で次を実行します。

```
/plugin marketplace add nogataka/cc-harness-kit
/plugin install cc-harness-kit@cc-harness-kit
```

開発中の版を手元で試すには、このリポジトリをクローンして `bash scripts/link-skills.sh` を実行します。`~/.claude/skills` にシンボリックリンクが張られます。

## 使い方

対象リポで、普段 `claude` を起動するディレクトリから始めます。

```
/harness-init
```

監査結果と、次に実行するスキルが1つ案内されます。案内されたスキルを実行すると、そのスキルは対象リポを探索し、`harness-proposal-<層>.md` に変更案を書いて止まります。採用する項目を `[x]` にして「承認」と伝えると、その項目だけが書き込まれます。既存ファイルは `.claude/harness-kit/backup/` に退避されます。

現状だけ知りたいときは `/harness-audit` を実行します。書き込みはしません。

## 設計上の約束

- 既存の CLAUDE.md や `.claude/settings.json` を、提案書なしに上書きしません（[ADR-0002](.agents/adr/0002-propose-then-write.md)）。
- 設定は、対象リポで `claude` を起動するディレクトリの `.claude/settings.json` に置きます。親ディレクトリの設定は継承されないためです（[ADR-0003](.agents/adr/0003-settings-live-in-the-start-directory.md)）。
- `.claudeignore` を作りません。除外は `.gitignore` と `permissions.deny` です（[ADR-0004](.agents/adr/0004-no-claudeignore.md)）。
- 言語サーバのバイナリは人が入れます。スキルは検出と案内までです。

## 各スキルの説明

- [harness-init](docs/setup/harness-init.md)
- [harness-audit](docs/audit/harness-audit.md)
- [harness-claudemd](docs/setup/harness-claudemd.md)
- [harness-hooks](docs/setup/harness-hooks.md)
- [harness-skills](docs/setup/harness-skills.md)
- [harness-plugin](docs/setup/harness-plugin.md)
- [harness-lsp](docs/setup/harness-lsp.md)
- [harness-exclusions](docs/setup/harness-exclusions.md)
- [harness-ownership](docs/setup/harness-ownership.md)

## 開発

```bash
bash scripts/validate.sh   # manifest、テンプレート同期、起動方式、shellcheck
bash tests/run.sh          # fixture に対する監査とフックのテスト
bash scripts/sync-templates.sh   # templates/ を各スキルへ配る（templates/ を編集したら実行）
```

JSON の解釈（監査スクリプトと4本のフックテンプレート）には python3 または node が必要です。どちらも無い、またはあっても実行に失敗する環境では、監査は該当項目を「不明」と表示します。フックは sed/grep による簡易抽出に落ちても通常と同じパターン照合を続けるため、大半の危険なコマンドは変わらず止まります。判定できなかった場合（ネストした引用符など一部の複雑なケースを含む）は警告を出した上で操作を通します（誤って安全側と誤判定しません）。

検証環境は macOS（bash 3.2、`bash --version` で確認したホスト環境。python3 あり）と、Docker の `debian:12`（素の状態。python3 も node も無い環境として使用）・`python:3.12-slim-bookworm`（python3 ありの環境）です。いずれも `bash tests/run.sh` を実行して確認しています。Claude Code は 2.1.261 で確認しています。リポジトリの規約は [CLAUDE.md](CLAUDE.md)、語彙は [CONTEXT.md](CONTEXT.md)、設計判断は [.agents/adr/](.agents/adr/) にあります。

## 参考

- Anthropic, "How Claude Code works in large codebases: Best practices and where to start"（2026年5月14日）
  https://claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start
- Claude Code 公式ドキュメント「Set up Claude Code in a monorepo or large codebase」
  https://code.claude.com/docs/en/large-codebases
- Claude Code 公式ドキュメント「How Claude remembers your project」「Hooks reference」「Extend Claude with skills」「Discover and install prebuilt plugins」
- リポジトリの構成は mattpocock/skills（MIT）の流儀を参考にしています。文章は独自に書いています。

## ライセンス

MIT。詳細は [LICENSE](LICENSE) を見てください。
