#!/usr/bin/env bash
# manifest とスクリプトの静的検証をまとめて実行します。
set -u

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo" || exit 1
status=0

echo "== claude plugin validate"
if command -v claude >/dev/null 2>&1; then
  claude plugin validate . --strict || status=1
else
  echo "claude CLI が見つかりません。スキップします。" >&2
fi

echo "== plugin.json と package.json の版"
node scripts/sync-plugin-version.mjs --check || status=1

echo "== plugin.json の skills が実在するか"
for dir in $(node -e 'for (const s of require("./.claude-plugin/plugin.json").skills) console.log(s)'); do
  if [ -f "$dir/SKILL.md" ]; then
    echo "ok   $dir"
  else
    echo "MISSING $dir/SKILL.md" >&2
    status=1
  fi
done

echo "== promoted スキルが plugin.json に列挙されているか"
while IFS= read -r skill_md; do
  dir="./${skill_md%/SKILL.md}"
  if ! grep -q "\"$dir\"" .claude-plugin/plugin.json; then
    echo "NOT LISTED $dir" >&2
    status=1
  fi
done < <(find skills -name SKILL.md -not -path '*/templates/*' | sort)


echo "== templates の同期"
bash scripts/sync-templates.sh --check || status=1

echo "== LSP 対応表: lsp-table.tsv と harness-lsp/SKILL.md のプラグイン名整合"
lsp_tsv="skills/audit/harness-audit/scripts/lsp-table.tsv"
lsp_skill="skills/setup/harness-lsp/SKILL.md"
if [ -f "$lsp_tsv" ] && [ -f "$lsp_skill" ]; then
  while IFS=$'\t' read -r lang _exts plugin _bin; do
    case "$lang" in \#*|'') continue ;; esac
    grep -q "$plugin" "$lsp_skill" || { echo "harness-lsp/SKILL.md に無いプラグイン: ${plugin} (${lsp_tsv} にはある)" >&2; status=1; }
  done < "$lsp_tsv"
else
  echo "$lsp_tsv または $lsp_skill が見つかりません" >&2; status=1
fi

echo "== スキルの起動方式（setup は user-invoked、audit は model-invoked）"
for f in skills/setup/*/SKILL.md; do
  grep -qE '^disable-model-invocation:[[:space:]]*true' "$f" || { echo "setup スキルに disable-model-invocation がありません: $f" >&2; status=1; }
done
for f in skills/audit/*/SKILL.md; do
  grep -qE '^disable-model-invocation:' "$f" && { echo "audit スキルは model-invoked にしてください: $f" >&2; status=1; }
done
for f in skills/*/*/SKILL.md; do
  name="$(grep -m1 -E '^name:' "$f" | sed -E 's/^name:[[:space:]]*//')"
  dir="$(basename "$(dirname "$f")")"
  [ "$name" = "$dir" ] || { echo "name とディレクトリ名が違います: $f ($name)" >&2; status=1; }
done

sh_files=$(find scripts tests templates skills -name '*.sh' -type f 2>/dev/null | grep -v '/fixtures/' | sort)

echo "== shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  shellcheck -S warning $sh_files || status=1
else
  echo "shellcheck が見つかりません。スキップします。" >&2
fi

echo "== bash -n"
for f in $sh_files; do
  bash -n "$f" || status=1
done

[ "$status" -eq 0 ] && echo "validate: OK" || echo "validate: FAILED" >&2
exit "$status"
