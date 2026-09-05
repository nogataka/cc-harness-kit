#!/usr/bin/env bash
# SessionStart 用。stdout に書いた文章は Claude のコンテキストに追加されます。
# 起動ディレクトリに応じた短い案内（担当チーム、使うスキル、直近の注意）を動的に渡します。
# 長文は禁物です。CLAUDE.md に書けることはそちらに書き、ここは「今日この場所で最初に知るべきこと」だけにします。
set -u

root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# CLAUDE_PROJECT_DIR がシンボリックリンク経由でも here と同じ基準（pwd -P）に正規化します。
root="$(cd "$root" 2>/dev/null && pwd -P || printf '%s' "$root")"
here="$(pwd -P)"
rel="${here#"$root"}"; rel="${rel#/}"

echo "起動ディレクトリ: ${rel:-（リポルート）}"

# 例: パッケージごとの案内。対象リポに合わせて書き換える。
case "$rel" in
  packages/api*)   echo "この領域のテスト手順は api-testing スキルにあります。DB を触る変更は migration を新規追加で行います。" ;;
  packages/web*)   echo "この領域のコンポーネント規約は component-patterns スキルにあります。" ;;
esac

# CLAUDE.md 追記候補が溜まっていれば知らせる
cand="$root/.claude/harness-kit/claudemd-candidates.md"
if [ -f "$cand" ]; then
  n=$(grep -c '^- \[ \]' "$cand" 2>/dev/null || echo 0)
  [ "$n" -gt 0 ] && echo "CLAUDE.md への追記候補が ${n} 件あります（.claude/harness-kit/claudemd-candidates.md）。手が空いたら人に確認を促してください。"
fi
exit 0
