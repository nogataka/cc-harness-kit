---
name: harness-lsp
description: 第5層。対象リポの言語を検出し、公式マーケットプレイスのコードインテリジェンス（LSP）プラグインを有効化する。言語サーバのバイナリは人が入れるものなので、未検出なら導入手順を案内して止まる。
argument-hint: "[起動ディレクトリ]"
disable-model-invocation: true
---

# 第5層: LSP でシンボル単位に辿る

対象: `$ARGUMENTS`（空ならカレントディレクトリ）

大きなコードベースで定義や呼び出し元を探すと、多数のファイル読み取りと grep が要ります。LSP があれば文字列ではなくシンボルで解決でき、編集直後に型エラーや import 漏れの診断が返ります。Claude Code では公式マーケットプレイスのコードインテリジェンスプラグインを入れると、内蔵の LSP ツールが有効になります。

重要な前提が1つあります。**プラグインは接続設定だけで、言語サーバ本体は含みません。** バイナリは人が PATH に入れます。このスキルは検出と案内までを行い、勝手に `npm install -g` などを実行しません。

## 探索

1. Skill ツールで `harness-audit` を呼び、第5層の表（言語、ファイル数、公式プラグイン、必要なバイナリ、バイナリの有無、enabledPlugins の有無）を確認します。
2. ファイル数が多い順に、対象にする言語を決めます。少数のスクリプトしか無い言語は対象から外して構いません。
3. `.claude/settings.json` の `enabledPlugins` を読み、既に有効なものを把握します。

## 対応表

| 言語 | プラグイン | 必要なバイナリ | 導入の例 |
|---|---|---|---|
| TypeScript / JavaScript | `typescript-lsp` | `typescript-language-server` | `npm install -g typescript-language-server typescript` |
| Python | `pyright-lsp` | `pyright-langserver` | `pip install pyright` または `npm install -g pyright` |
| Go | `gopls-lsp` | `gopls` | `go install golang.org/x/tools/gopls@latest` |
| Rust | `rust-analyzer-lsp` | `rust-analyzer` | `rustup component add rust-analyzer` |
| Java | `jdtls-lsp` | `jdtls` | Eclipse JDT Language Server を配布物から導入 |
| Kotlin | `kotlin-lsp` | `kotlin-language-server` | 配布物から導入 |
| PHP | `php-lsp` | `intelephense` | `npm install -g intelephense` |
| C / C++ | `clangd-lsp` | `clangd` | LLVM 配布物、または OS のパッケージ |
| C# | `csharp-lsp` | `csharp-ls` | `dotnet tool install -g csharp-ls` |
| Swift | `swift-lsp` | `sourcekit-lsp` | Xcode / Swift toolchain に同梱 |
| Lua | `lua-lsp` | `lua-language-server` | 配布物から導入 |

導入の例は代表的なものです。組織の配布手段（社内パッケージ、devcontainer、セットアップスクリプト）があればそれに合わせてください。

## 提案書

`harness-proposal-lsp.md` を起動ディレクトリに書き出します。書式は `templates/proposal.md` です。言語ごとに次を書きます。

- バイナリが **ある** 言語: `/plugin install <プラグイン>@claude-plugins-official` の実行と、`enabledPlugins` への追記（チームで共有する場合）
- バイナリが **ない** 言語: 導入コマンドの案内。「導入後にこのスキルをもう一度実行してください」と書き、この言語のプラグイン有効化は提案に含めません

注意として、次を明記します。

- 公式マーケットプレイスが見つからない場合は `/plugin marketplace add anthropics/claude-plugins-official` を先に実行する
- クラウドセッションではプラグインの言語サーバは起動しない
- rust-analyzer や pyright は大きなプロジェクトでメモリを多く使う。問題が出たら `/plugin disable` で外せる
- 同じ拡張子を扱うプラグインを複数入れると、先に登録された1つだけが動く

## 承認待ち

提案書を書いたら止まります。

> `harness-proposal-lsp.md` を書きました。バイナリの導入は人の作業です。導入してから「承認」と言ってください。

## 書込

1. `[x]` の言語について、人に `/plugin install <プラグイン>@claude-plugins-official` の実行を案内します（`/plugin` はセッション内コマンドで、このスキルから直接は実行できません）。
2. チームで共有する場合は、`.claude/settings.json` を退避してから `enabledPlugins` に `"<プラグイン>@claude-plugins-official": true` を追記します。

## 確認

- `/plugin` の Errors タブに「Executable not found in $PATH」が無いこと。
- 対象言語のファイルを1つ編集し、「Found N new diagnostic issues」の表示が出るか、故意の型エラーが同じターンで指摘されること。
- バイナリ未導入で見送った言語があれば、導入後に再実行するよう伝えます。

## 補助ファイル

- `templates/proposal.md`: 提案書の書式
