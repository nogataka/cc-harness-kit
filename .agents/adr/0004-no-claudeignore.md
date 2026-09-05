# ADR-0004: `.claudeignore` を生成しない

日付: 2026-09-05 / 状態: 採用

## 背景

「Claude に読ませたくないファイルを `.claudeignore` で除外する」という説明を、解説記事や要約でよく見かけます。しかし 2026年9月時点の Claude Code 公式ドキュメントに `.claudeignore` は存在しません。GitHub の issue で要望が上がっている段階で、コミュニティのフックで代替している人がいるだけです。

Anthropic のブログは「.ignore ファイルで生成物・ビルド成果物・サードパーティコードを除外し、`permissions.deny` を `.claude/settings.json` にコミットする」と説明しています。

## 決定

- `.claudeignore` を生成しません。存在しないファイルを作っても効果がなく、効いていると誤解させるだけです。
- 除外は2つの仕組みを役割で分けて使います。
  - **検索除外**: `.gitignore`。Claude の検索は `.gitignore` を既定で尊重します。`node_modules/`、`dist/`、`build/` はここで外れます。
  - **読み取り拒否**: `permissions.deny` の `Read(...)` ルール。チェックイン済みの生成コードや vendored SDK など、`.gitignore` に入れられないものはこちらです。
- `harness-exclusions` は `.gitignore` の点検と `permissions.deny` の提案を行い、`.claudeignore` が対象リポにあれば「効いていない」と警告します。

## 帰結

- 読み取り拒否はスコープ間でマージされ、個人設定で打ち消せません。例外が要るパスは共有の deny に入れない設計にします。
- 将来 Claude Code に `.claudeignore` 相当が入った場合は、この ADR を改訂してから対応します。
