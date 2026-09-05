## What it does

`harness-plugin` は、ハーネスをチームに配る準備をします。公式マーケットプレイスのプラグインを `enabledPlugins` で有効にし、社内マーケットプレイスを `extraKnownMarketplaces` に登録する断片を、起動ディレクトリの `.claude/settings.json` に提案します。最初に「他の人にも配るか」を聞き、一人で使うなら公式プラグインの有効化だけで終わります。

## When to reach for it

`/harness-plugin` と打ちます。Claude が自分で開くことはありません。

- 複数人で同じリポを触り、同じスキルとフックを全員の環境に揃えたいときに使います。
- 一人で複数リポを持つだけなら、`~/.claude/skills` に置くほうが早く、このスキルの出番は公式プラグインの有効化だけです。

## Common questions

**`enabledPlugins` に書いたのに、他のメンバーの環境で動きません。**
外部ソースのプラグインは、設定に書いただけでは入りません。各メンバーの Claude Code が未インストールを検知してコマンドを案内するので、それを実行してもらいます。全員に強制したいなら管理設定（managed settings）で配ります。

**社内マーケットプレイスはどう作りますか。**
`.claude-plugin/marketplace.json` と `plugin.json` を持つ Git リポを1つ作ります。作り方は公式ドキュメント「Create and distribute a plugin marketplace」にあります。このスキルは手順を案内するだけで、そのリポは作りません。

## It's working if

- `/plugin` の Installed タブに、有効化したプラグインが載っています。
- Errors タブに何も出ていません。
- 新しくクローンしたメンバーが、案内されたコマンド1つで同じプラグイン一式を入れられます。
