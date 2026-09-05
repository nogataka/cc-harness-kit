# fixture-monorepo

## 技術スタック
- Node.js 22 / TypeScript 5.6
- Prisma 6 / PostgreSQL 16
- Vitest / Playwright

## ディレクトリ構成
- packages/api: API サーバ
- packages/web: フロント
- packages/shared: 共有ライブラリ

## コーディング規約
- コメントは書かない。
- 複数行の docstring は決して書かない。
- 変更したファイルには必ず適切なドキュメントを残す。
- any を絶対に使わない。
- 関数は 30 行以内にする。

## テスト
- 必ずテストを先に書く。
- 小さな修正ではテストを省略してよい。
- テストコマンドは npm test を使う。

## リリース手順
1. main を最新にする。
2. npm run build を実行する。
3. npm version patch を実行する。
4. git push --tags を実行する。
5. GitHub Releases にノートを書く。

## メモ
- 2026-03-10: API のエラー形式は { code, message } に統一した。
- テストコマンドは npm test を使う。
