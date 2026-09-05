#!/usr/bin/env bash
# ハーネス監査レポートを Markdown で標準出力に出します。読み取り専用で、ファイルは変更しません。
# 使い方: harness-audit.sh [起動ディレクトリ]   省略時はカレントディレクトリ
# bash 3.2（macOS 既定）で動くように書いています。
#
# JSON の解釈には python3 または node が必要です。どちらも無い環境では、
# JSON に依存する判定（第2層 フック・第4層 プラグイン・除外の deny 件数・MCP 件数）は
# 「未着手」と誤判定せず「不明」として報告します（json_query の戻り値 2 で判別）。
set -u

start="${1:-.}"
start="$(cd "$start" 2>/dev/null && pwd -P)" || { echo "起動ディレクトリが見つかりません: ${1:-.}" >&2; exit 1; }
limit_lines=200

# リポルート。環境変数 HARNESS_AUDIT_ROOT があればそれ、無ければ git のトップ、どちらも無ければ起動ディレクトリ。
# 別リポの中に置いた検証用ディレクトリを監査するときは HARNESS_AUDIT_ROOT で明示します。
if [ -n "${HARNESS_AUDIT_ROOT:-}" ]; then
  root="$(cd "$HARNESS_AUDIT_ROOT" 2>/dev/null && pwd -P)" || { echo "HARNESS_AUDIT_ROOT が見つかりません: $HARNESS_AUDIT_ROOT" >&2; exit 1; }
else
  root="$(cd "$start" && git rev-parse --show-toplevel 2>/dev/null || echo "$start")"
fi
case "$start" in
  "$root"|"$root"/*) ;;
  *) echo "起動ディレクトリ $start はリポルート $root の配下ではありません" >&2; exit 1 ;;
esac

# JSON の読み取り。python3 → node の順でフォールバックします。
# 戻り値: 0=解釈できた（結果は標準出力。0件なら何も出しません） / 1=ファイルなし・パース失敗 / 2=python3・node どちらも無く判定不能
# 第2引数は固定の問い合わせ名で、外部入力を評価することはありません。
json_query() {
  # $1=ファイル $2=問い合わせ名（hooks_keys / plugins / marketplaces / deny_read / mcp_count）
  local file="$1" op="$2"
  [ -f "$file" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" "$op" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
op = sys.argv[2]
out = []
if op == "hooks_keys":
    out = list((d.get("hooks") or {}).keys())
elif op == "plugins":
    v = d.get("enabledPlugins") or {}
    out = list(v.keys()) if isinstance(v, dict) else list(v)
elif op == "marketplaces":
    out = list((d.get("extraKnownMarketplaces") or {}).keys())
elif op == "deny_read":
    out = [x for x in ((d.get("permissions") or {}).get("deny") or []) if str(x).startswith("Read(")]
elif op == "mcp_count":
    out = [len(d.get("mcpServers") or {})]
for x in out:
    print(x)
PY
    return 0
  elif command -v node >/dev/null 2>&1; then
    node -e '
const fs = require("fs");
const file = process.argv[1], op = process.argv[2];
let d;
try { d = JSON.parse(fs.readFileSync(file, "utf8")); } catch (e) { process.exit(0); }
let out = [];
if (op === "hooks_keys") out = Object.keys(d.hooks || {});
else if (op === "plugins") { const v = d.enabledPlugins || {}; out = Array.isArray(v) ? v : Object.keys(v); }
else if (op === "marketplaces") out = Object.keys(d.extraKnownMarketplaces || {});
else if (op === "deny_read") out = ((d.permissions || {}).deny || []).filter(function (x) { return String(x).indexOf("Read(") === 0; });
else if (op === "mcp_count") out = [Object.keys(d.mcpServers || {}).length];
out.forEach(function (x) { console.log(x); });
' -- "$file" "$op" 2>/dev/null
    return 0
  else
    return 2
  fi
}

json_interp_missing=1
command -v python3 >/dev/null 2>&1 && json_interp_missing=0
command -v node >/dev/null 2>&1 && json_interp_missing=0

count_lines() { wc -l < "$1" | tr -d ' '; }

judge_row() {
  # $1=層名 $2=判定 $3=根拠
  printf '| %s | %s | %s |\n' "$1" "$2" "$3"
}

strong_pattern='絶対|必ず|禁止|決して|しないこと|never|always|must not|do not|don'\''t'

echo "# ハーネス監査レポート"
echo
echo "- 起動ディレクトリ: \`$start\`"
echo "- リポルート: \`$root\`"
if command -v claude >/dev/null 2>&1; then
  echo "- Claude Code: $(claude --version 2>/dev/null | head -1)"
else
  echo "- Claude Code: CLI が PATH にありません"
fi
if [ "$json_interp_missing" -eq 1 ]; then
  echo "- JSON の解釈: 不可（python3 / node なし）。第2層・第4層・除外の deny 件数・MCP 件数は「不明」と表示します"
fi
echo "- 監査日時: $(date '+%Y-%m-%d %H:%M')"
echo

summary_rows=""

###############################################################################
echo "## 1. 第1層 CLAUDE.md"
echo
echo "### 起動時に読み込まれるファイル（起動ディレクトリから親へ）"
echo
echo "| ファイル | 行数 | 目安 ${limit_lines} 行 |"
echo "|---|---:|---|"
loaded=0; over=0
dir="$start"
while :; do
  for f in "$dir/CLAUDE.md" "$dir/CLAUDE.local.md" "$dir/.claude/CLAUDE.md"; do
    if [ -f "$f" ]; then
      n=$(count_lines "$f"); loaded=$((loaded+1))
      if [ "$n" -ge "$limit_lines" ]; then mark="超過"; over=$((over+1)); else mark="範囲内"; fi
      echo "| \`$f\` | $n | $mark |"
    fi
  done
  [ "$dir" = "/" ] && break
  case "$root" in "$dir") break;; esac
  dir="$(dirname "$dir")"
done
if [ -f "$HOME/.claude/CLAUDE.md" ]; then
  n=$(count_lines "$HOME/.claude/CLAUDE.md"); loaded=$((loaded+1))
  if [ "$n" -ge "$limit_lines" ]; then mark="超過"; over=$((over+1)); else mark="範囲内"; fi
  echo "| \`~/.claude/CLAUDE.md\` | $n | $mark |"
fi
[ "$loaded" -eq 0 ] && echo "| （なし） | | |"
echo

echo "### 下位ディレクトリの CLAUDE.md（そのディレクトリのファイルを読んだときに読み込まれる）"
echo
nested=$(find "$start" -mindepth 2 \( -name node_modules -o -name .git -o -name dist -o -name build -o -name vendor \) -prune -o -type f \( -name CLAUDE.md -o -name CLAUDE.local.md \) -print 2>/dev/null | grep -v "^$start/.claude/CLAUDE.md$" | sort)
nested_count=0
if [ -n "$nested" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    nested_count=$((nested_count+1))
    echo "- \`$f\`（$(count_lines "$f") 行）"
  done <<< "$nested"
else
  echo "- なし"
fi
echo

echo "### 点検対象の行"
echo
all_claude=$(printf '%s\n' "$start/CLAUDE.md" "$start/.claude/CLAUDE.md" "$root/CLAUDE.md" "$root/.claude/CLAUDE.md"; printf '%s\n' "$nested")
all_claude=$(printf '%s\n' "$all_claude" | awk 'NF' | sort -u | while IFS= read -r f; do [ -f "$f" ] && echo "$f"; done)
strong=0; steps=0; dups=0
if [ -n "$all_claude" ]; then
  strong=$(printf '%s\n' "$all_claude" | while IFS= read -r f; do grep -ciE "$strong_pattern" "$f"; done | awk '{s+=$1} END{print s+0}')
  steps=$(printf '%s\n' "$all_claude" | while IFS= read -r f; do grep -cE '^[[:space:]]*[0-9]+\.[[:space:]]' "$f"; done | awk '{s+=$1} END{print s+0}')
  dups=$(printf '%s\n' "$all_claude" | while IFS= read -r f; do grep -vE '^\s*(#|$)' "$f"; done | sed -E 's/^[[:space:]]+//; s/^[-*] +//; s/[[:space:]]+$//' | awk 'length($0) >= 20' | sort | uniq -d | wc -l | tr -d ' ')
fi
echo "- 強い語（絶対・必ず・禁止・never など）を含む行: ${strong} 行（判断基準への書き直し候補）"
echo "- 番号付き手順の行: ${steps} 行（スキルへの切り出し候補）"
echo "- 複数箇所に重複する行: ${dups} 行"
map=""
for m in "$root/docs/CODEBASE-MAP.md" "$root/CODEBASE-MAP.md" "$root/docs/codebase-map.md"; do [ -f "$m" ] && map="$m"; done
if [ -n "$map" ]; then echo "- コードベースマップ: \`$map\`"; else echo "- コードベースマップ: なし"; fi
echo

has_packages=0
[ -d "$root/packages" ] || [ -d "$root/apps" ] || [ -f "$root/pnpm-workspace.yaml" ] && has_packages=1
if [ "$loaded" -eq 0 ]; then j1="未着手"; r1="CLAUDE.md がありません"
elif [ "$over" -gt 0 ]; then j1="一部"; r1="${over} ファイルが ${limit_lines} 行以上"
elif [ "$has_packages" -eq 1 ] && [ "$nested_count" -eq 0 ]; then j1="一部"; r1="パッケージ構成なのに下位 CLAUDE.md がありません"
else j1="充足"; r1="行数目安内・階層あり"; fi
summary_rows="$summary_rows$(judge_row "第1層 CLAUDE.md" "$j1" "$r1")
"

###############################################################################
echo "## 2. 第2層 フック（設定ファイルは起動ディレクトリのものだけが読まれます）"
echo
settings="$start/.claude/settings.json"
if [ -f "$settings" ]; then
  echo "- 設定ファイル: \`$settings\`"
  hooks=$(json_query "$settings" hooks_keys); hooks_rc=$?
  if [ "$hooks_rc" -eq 2 ]; then
    echo "- フック: JSON を解釈できないため判定できません（python3 / node なし）"
    j2="不明"; r2="python3 / node が無く判定できません"
  elif [ -n "$hooks" ]; then
    echo "- フックのイベント: $(printf '%s' "$hooks" | tr '\n' ' ')"
    j2="充足"; r2="$(printf '%s' "$hooks" | tr '\n' ' ')"
  else
    echo "- フック: なし"
    j2="未着手"; r2="hooks キーがありません"
  fi
else
  echo "- 設定ファイル: 起動ディレクトリにありません"
  j2="未着手"; r2="起動ディレクトリに .claude/settings.json がありません"
fi
if [ "$start" != "$root" ] && [ -f "$root/.claude/settings.json" ]; then
  echo "- 注意: ルート \`$root/.claude/settings.json\` は、このディレクトリから起動した場合には読み込まれません（設定は親から継承されません）"
fi
echo
summary_rows="$summary_rows$(judge_row "第2層 フック" "$j2" "$r2")
"

###############################################################################
echo "## 3. 第3層 スキルと rules"
echo
skills_count=$(find "$root" \( -name node_modules -o -name .git \) -prune -o -path '*/.claude/skills/*/SKILL.md' -type f -print 2>/dev/null | wc -l | tr -d ' ')
rules_total=0; rules_scoped=0
rule_dirs="$start/.claude/rules"
[ "$start" != "$root" ] && rule_dirs="$rule_dirs
$root/.claude/rules"
while IFS= read -r rd; do
  [ -d "$rd" ] || continue
  t=$(find "$rd" -name '*.md' -type f | wc -l | tr -d ' ')
  s=$(find "$rd" -name '*.md' -type f -exec grep -lE '^paths:' {} + 2>/dev/null | wc -l | tr -d ' ')
  rules_total=$((rules_total+t)); rules_scoped=$((rules_scoped+s))
done <<< "$rule_dirs"
echo "- スキル（リポ内の .claude/skills）: ${skills_count} 本"
echo "- rules: ${rules_total} 本（うち paths 限定 ${rules_scoped} 本。残りは起動時に常時読込）"
echo "- CLAUDE.md 内の番号付き手順: ${steps} 行"
if [ "$skills_count" -eq 0 ] && [ "$rules_total" -eq 0 ]; then j3="未着手"; r3="スキルも rules もありません"
elif [ "$steps" -ge 5 ]; then j3="一部"; r3="CLAUDE.md に手順が ${steps} 行残っています"
else j3="充足"; r3="スキル ${skills_count} 本・rules ${rules_total} 本"; fi
echo
summary_rows="$summary_rows$(judge_row "第3層 スキル" "$j3" "$r3")
"

###############################################################################
echo "## 4. 第4層 プラグイン"
echo
plugins=$(json_query "$settings" plugins); plugins_rc=$?
markets=$(json_query "$settings" marketplaces); markets_rc=$?
if [ "$plugins_rc" -eq 2 ] || [ "$markets_rc" -eq 2 ]; then
  echo "- enabledPlugins: 判定できません（python3 / node なし）"
  echo "- extraKnownMarketplaces: 判定できません（python3 / node なし）"
  [ -f "$root/.claude-plugin/plugin.json" ] && echo "- このリポ自身がプラグイン manifest を持っています"
  j4="不明"; r4="python3 / node が無く判定できません"
else
  if [ -n "$plugins" ]; then echo "- enabledPlugins: $(printf '%s' "$plugins" | tr '\n' ' ')"; else echo "- enabledPlugins: なし"; fi
  if [ -n "$markets" ]; then echo "- extraKnownMarketplaces: $(printf '%s' "$markets" | tr '\n' ' ')"; else echo "- extraKnownMarketplaces: なし"; fi
  [ -f "$root/.claude-plugin/plugin.json" ] && echo "- このリポ自身がプラグイン manifest を持っています"
  if [ -n "$plugins" ]; then j4="充足"; r4="$(printf '%s' "$plugins" | wc -l | tr -d ' ') 個のプラグインを有効化"; else j4="未着手"; r4="enabledPlugins がありません"; fi
fi
echo
summary_rows="$summary_rows$(judge_row "第4層 プラグイン" "$j4" "$r4")
"

###############################################################################
echo "## 5. 第5層 LSP（コードインテリジェンス）"
echo
echo "| 言語 | ファイル数 | 公式プラグイン | 必要なバイナリ | バイナリ | enabledPlugins |"
echo "|---|---:|---|---|---|---|"
count_ext() {
  # $1=カンマ区切りの find -name パターン（例: "*.ts,*.tsx"）。lsp-table.tsv の第2列を渡します。
  local patterns="$1" args old_ifs
  args=()
  old_ifs="$IFS"; IFS=','
  for p in $patterns; do
    if [ "${#args[@]}" -eq 0 ]; then args=(-name "$p"); else args=("${args[@]}" -o -name "$p"); fi
  done
  IFS="$old_ifs"
  find "$root" \( -name node_modules -o -name .git -o -name dist -o -name build -o -name vendor \) -prune -o -type f \( "${args[@]}" \) -print 2>/dev/null | wc -l | tr -d ' '
}
lsp_missing=0; lsp_present=0; lsp_langs=0
lsp_row() {
  # $1=言語 $2=件数 $3=plugin $4=binary
  local lang="$1" n="$2" plugin="$3" bin="$4" b="なし" e="なし"
  [ "$n" -gt 0 ] || return 0
  lsp_langs=$((lsp_langs+1))
  if command -v "$bin" >/dev/null 2>&1; then b="あり"; else lsp_missing=$((lsp_missing+1)); fi
  if printf '%s\n' "$plugins" | grep -q "^$plugin"; then e="あり"; lsp_present=$((lsp_present+1)); fi
  printf '| %s | %s | `%s` | `%s` | %s | %s |\n' "$lang" "$n" "$plugin" "$bin" "$b" "$e"
}
lsp_table_file="$(dirname "$0")/lsp-table.tsv"
if [ -f "$lsp_table_file" ]; then
  while IFS=$'\t' read -r lang exts plugin bin; do
    [ -n "$lang" ] || continue
    case "$lang" in \#*) continue ;; esac
    lsp_row "$lang" "$(count_ext "$exts")" "$plugin" "$bin"
  done < "$lsp_table_file"
else
  echo "| (lsp-table.tsv が見つかりません: ${lsp_table_file}) | | | | | |"
fi
echo
if [ "$lsp_langs" -eq 0 ]; then j5="対象外"; r5="対応言語のファイルがありません"
elif [ "$lsp_present" -ge "$lsp_langs" ]; then j5="充足"; r5="検出 ${lsp_langs} 言語すべてでプラグイン有効"
elif [ "$lsp_present" -gt 0 ]; then j5="一部"; r5="${lsp_langs} 言語中 ${lsp_present} 言語で有効"
else j5="未着手"; r5="${lsp_langs} 言語を検出、プラグイン有効化なし（バイナリ未導入 ${lsp_missing}）"; fi
summary_rows="$summary_rows$(judge_row "第5層 LSP" "$j5" "$r5")
"

###############################################################################
echo "## 6. 除外（検索除外と読み取り拒否）"
echo
gi="$root/.gitignore"
if [ -f "$gi" ]; then
  for pat in node_modules dist build; do
    if grep -qE "^/?${pat}/?\s*$" "$gi"; then echo "- .gitignore: \`$pat\` あり"; else echo "- .gitignore: \`$pat\` なし"; fi
  done
else
  echo "- .gitignore: ありません"
fi
deny=$(json_query "$settings" deny_read); deny_rc=$?
if [ "$deny_rc" -eq 2 ]; then
  echo "- 読み取り拒否（permissions.deny の Read ルール）: 不明（python3 / node なし）"
  deny_count=-1
else
  deny_count=0; [ -n "$deny" ] && deny_count=$(printf '%s\n' "$deny" | wc -l | tr -d ' ')
  echo "- 読み取り拒否（permissions.deny の Read ルール）: ${deny_count} 件"
  [ -n "$deny" ] && printf '%s\n' "$deny" | sed 's/^/  - `/; s/$/`/'
fi
if [ -f "$root/.claudeignore" ] || [ -f "$start/.claudeignore" ]; then
  echo "- 警告: \`.claudeignore\` がありますが、Claude Code の正式機能ではないため効いていません"
fi
cands=""
for c in vendor third_party generated; do [ -d "$root/$c" ] && cands="$cands $c/"; done
[ -n "$cands" ] && echo "- 読み取り拒否の候補ディレクトリ:$cands"
echo
if [ "$deny_count" -eq -1 ]; then j6="不明"; r6="python3 / node が無く判定できません"
elif [ "$deny_count" -gt 0 ]; then j6="充足"; r6="Read 拒否 ${deny_count} 件"
elif [ -n "$cands" ]; then j6="未着手"; r6="候補ディレクトリ（$cands ）に拒否ルールなし"
else j6="一部"; r6="拒否ルールなし（候補も検出されず）"; fi
summary_rows="$summary_rows$(judge_row "除外" "$j6" "$r6")
"

###############################################################################
echo "## 7. 第6層 MCP と 第7層 サブエージェント（情報のみ）"
echo
mcp_count=$(json_query "$root/.mcp.json" mcp_count); mcp_rc=$?
if [ "$mcp_rc" -eq 2 ]; then
  mcp_display="不明（python3 / node なし）"
else
  [ -z "$mcp_count" ] && mcp_count=0
  mcp_display="${mcp_count} 件"
fi
echo "- .mcp.json の MCP サーバ: ${mcp_display}"
agents_count=$(find "$root/.claude/agents" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
echo "- .claude/agents のサブエージェント定義: ${agents_count} 件"
echo
summary_rows="$summary_rows$(judge_row "第6層 MCP" "情報" "MCP ${mcp_display}")
$(judge_row "第7層 サブエージェント" "情報" "定義 ${agents_count} 件（探索の切り出しは運用で判断）")
"

###############################################################################
echo "## 8. オーナーシップと見直し"
echo
owner=""
for o in "$root/docs/agents/harness-owner.md" "$root/HARNESS-OWNER.md" "$root/.claude/HARNESS-OWNER.md"; do [ -f "$o" ] && owner="$o"; done
if [ -n "$owner" ]; then echo "- オーナー文書: \`$owner\`"; j8="充足"; r8="オーナー文書あり"
else echo "- オーナー文書: なし（DRI と次回見直し日が記録されていません）"; j8="未着手"; r8="オーナー文書なし"; fi
echo
summary_rows="$summary_rows$(judge_row "オーナーシップ" "$j8" "$r8")
"

###############################################################################
echo "## 採点表"
echo
echo "| 層 | 判定 | 根拠 |"
echo "|---|---|---|"
printf '%s' "$summary_rows"
echo
echo "判定の意味: 充足＝このまま運用可 / 一部＝改善余地あり / 未着手＝この層がまだ無い / 不明＝JSON を解釈できず判定不能 / 対象外・情報＝採点しない"
