---
name: api-testing
description: packages/api のテストを書く・直すときの手順。テスト構成、実行コマンド、ヘルパの一覧。
---

# API テスト手順

- テストは src/__tests__/ にルートと同じ構造で置く。
- 単一ファイル: npm test -- src/__tests__/routes/users.test.ts
