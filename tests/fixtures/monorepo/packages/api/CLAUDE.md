# packages/api

- .env.example を .env にコピーしてから起動する。無いとテストと dev サーバが落ちる。
- DB クエリは Knex で書く。生 SQL をルートハンドラに置かない。
- マージ済みの migration は編集しない。新しい migration を足す。
