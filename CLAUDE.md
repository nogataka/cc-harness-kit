# cc-harness-kit

Claude Code のハーネス（CLAUDE.md、フック、スキル、プラグイン、LSP、MCP、サブエージェント）を、既存リポジトリに構築順で組み立てるスキル集です。生成物は Claude Code 専用です。構成の全体像は `README.md`、語彙は `CONTEXT.md` を見てください。

## スキルの配置

- `skills/setup/`: 各層を組み立てる user-invoked スキル（`harness-init` と `harness-*`）。人が `/名前` で起動します。
- `skills/audit/`: 現状を採点する model-invoked スキル（`harness-audit`）。Claude が自分で開いてよい唯一のスキルです。
- どちらのバケットも promoted です。`.claude-plugin/plugin.json` の `skills` 配列に全スキルを明示列挙し、`README.md` のスキル一覧に載せます。片方だけ更新した状態を残さないでください。

## 変更時に必ず守ること

- 新しい判断は `.agents/adr/` に ADR として残します。既存 ADR と矛盾する変更は、先に ADR を改訂してから行います。
- スキルの user-invoked / model-invoked は `.agents/invocation.md` の規約に従います。`disable-model-invocation: true` の有無で判定します。
- スキルは「探索→提案書→承認→書込」の順を崩しません（ADR-0002）。対象リポの既存ファイルを黙って上書きしないでください。
- 生成する設定の置き場所は、対象リポで Claude Code を起動するディレクトリの `.claude/settings.json` です（ADR-0003）。親ディレクトリの設定は継承されません。
- `.claudeignore` を生成しません（ADR-0004）。除外は `.gitignore` と `permissions.deny` です。
- `scripts/*.sh` は bash 3.2（macOS 既定）で動くように書きます。連想配列、`mapfile`、`${var,,}`、`**` glob は使いません。変更後は `shellcheck -S warning` と `tests/run.sh` を通します。
- manifest を触ったら `bash scripts/validate.sh`（`claude plugin validate . --strict`）を実行します。
- JSON の解釈には python3 または node が必要です。どちらも無い、またはあっても実行に失敗する環境では、監査は該当項目を「未着手」ではなく「不明」と表示します。フックは sed/grep へのフォールバック後も通常と同じパターン照合を続けるため大半の危険なコマンドは変わらず止まりますが、判定できなかった場合（ネストした引用符など一部の複雑なケースを含む）は警告を出した上で実行を止めない側に倒します。python3 → node → sed/grep の順でフォールバックする既存の実装パターンに従ってください。
- `templates/` を編集したら `bash scripts/sync-templates.sh` を実行し、各スキル配下の複製を更新します（プラグインは単体配布のため、各スキルはリポ直下の `templates/` を直接参照できません）。`bash scripts/validate.sh` の一部として `--check` が実行されるので、同期を忘れると検知されます。
- `harness-audit.sh` の実体は `skills/audit/harness-audit/scripts/harness-audit.sh` です。`scripts/harness-audit.sh`（リポ直下）は同じ理由（プラグイン単体配布）でこれを `exec` するだけのラッパです。変更するのは実体側です。
- 文章は日本語のです・ます調です。英略語の見出し、絵文字、記事末の呼びかけは使いません。

## 開発フロー

- ローカルで試すときは `bash scripts/link-skills.sh` で `~/.claude/skills` にシンボリックリンクを張ります。
- 検証は `bash tests/run.sh` です。`tests/fixtures/monorepo/` の架空リポに対して監査スクリプトを実行し、期待どおりの採点表が出ることを確認します。実リポでの通し検証は行いません。
- リリースは changesets です。`npm run version` が `package.json` と `.claude-plugin/plugin.json` の版を揃えます。
