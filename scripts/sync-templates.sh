#!/usr/bin/env bash
# templates/ を正本として、各スキルの templates/ ディレクトリへコピーします。
# スキルはプラグインとして単体で配布されるため、リポ直下の templates/ を参照できません。
# templates/ を編集したら必ずこれを実行してください。--check で差分の有無だけ確認できます。
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
check=0; [ "${1:-}" = "--check" ] && check=1
status=0
used_list=""

# 書式: <スキルディレクトリ> <templates/ からの相対パス>...
sync() {
  local skill="$1"; shift
  local dest="$skill/templates"
  for src in "$@"; do
    local from="templates/$src" to="$dest/$src"
    used_list="$used_list
$src"
    if [ "$check" -eq 1 ]; then
      if [ ! -f "$to" ] || ! cmp -s "$from" "$to"; then
        echo "DIFF ${to} (${from} と異なるか、未コピー)" >&2; status=1
      fi
    else
      mkdir -p "$(dirname "$to")"
      cp "$from" "$to"
      echo "synced $to"
    fi
  done
}

sync skills/setup/harness-claudemd   proposal.md claude-md/root.md claude-md/subdir.md claude-md/codebase-map.md
sync skills/setup/harness-hooks      proposal.md settings/hooks.json hooks/format-and-check.sh hooks/guard-irreversible.sh hooks/stop-propose-claudemd.sh hooks/session-start-context.sh
sync skills/setup/harness-skills     proposal.md skills/SKILL.md rules/path-rule.md
sync skills/setup/harness-plugin     proposal.md settings/plugins.json
sync skills/setup/harness-lsp        proposal.md
sync skills/setup/harness-exclusions proposal.md settings/deny.json
sync skills/setup/harness-ownership  proposal.md harness-owner.md

# templates/ 配下にあるが、どの sync() 呼び出しからも参照されていないファイル（孤立ファイル）を検出します。
if [ "$check" -eq 1 ]; then
  all_files="$(find templates -type f | sed 's#^templates/##' | sort)"
  used_sorted="$(printf '%s\n' "$used_list" | awk 'NF' | sort -u)"
  orphans="$(comm -23 <(printf '%s\n' "$all_files") <(printf '%s\n' "$used_sorted") 2>/dev/null || true)"
  if [ -n "$orphans" ]; then
    printf '%s\n' "$orphans" | sed 's/^/ORPHAN templates\//' >&2
    status=1
  fi
fi

[ "$check" -eq 1 ] && { [ "$status" -eq 0 ] && echo "templates: in sync" || echo "templates: OUT OF SYNC（bash scripts/sync-templates.sh を実行、または孤立ファイルを削除・sync() に追記）" >&2; }
exit "$status"
