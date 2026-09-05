#!/usr/bin/env bash
# fixture に対して監査スクリプトを実行し、期待する判定が出ることを確認します。
# 使い方: bash tests/run.sh
set -u

repo="$(cd "$(dirname "$0")/.." && pwd)"
audit="$repo/scripts/harness-audit.sh"
fx="$repo/tests/fixtures"
tmp="$repo/tests/tmp"
mkdir -p "$tmp"
fail=0

# fixture 内の .gitignore で除外されるファイルは、テスト実行時に作り直す
mkdir -p "$fx/monorepo/dist" && printf 'built output\n' > "$fx/monorepo/dist/bundle.js"

expect() {
  # $1=レポート $2=正規表現 $3=説明
  if grep -qE "$2" "$1"; then
    echo "ok   $3"
  else
    echo "FAIL $3  (期待: /$2/)" >&2
    fail=1
  fi
}

# このテストを実行するホストに python3 / node があるかどうかで、JSON に依存するアサーションを切り替えます。
# 無い環境（例: 素の debian:12）では、監査は該当項目を「不明」と報告するのが正しい挙動です。
have_json_interp=0
command -v python3 >/dev/null 2>&1 && have_json_interp=1
command -v node >/dev/null 2>&1 && have_json_interp=1

echo "== fixture: monorepo（ルートから起動）"
HOME="$tmp/home-empty" HARNESS_AUDIT_ROOT="$fx/monorepo" bash "$audit" "$fx/monorepo" > "$tmp/monorepo-root.md"; echo "exit=$?"
r="$tmp/monorepo-root.md"
expect "$r" '^\| `.*/monorepo/CLAUDE.md` \| [0-9]+ \| 範囲内 \|' "ルート CLAUDE.md が起動時読込に載る"
expect "$r" 'packages/api/CLAUDE.md`（5 行）' "下位 CLAUDE.md をオンデマンドとして検出"
expect "$r" '強い語.*: [1-9][0-9]* 行' "強い語を検出"
expect "$r" '番号付き手順の行: [5-9] 行|番号付き手順の行: [1-9][0-9]+ 行' "番号付き手順（リリース手順5行）を検出"
expect "$r" '複数箇所に重複する行: 1 行' "重複行（npm test）を検出"
if [ "$have_json_interp" -eq 1 ]; then
  expect "$r" '\| 第2層 フック \| 未着手 \|' "フック未着手"
else
  expect "$r" '\| 第2層 フック \| 不明 \|' "フック: python3/node 不在のため不明（未着手に誤判定しない）"
fi
expect "$r" 'rules: 2 本（うち paths 限定 1 本' "rules の paths 判定"
expect "$r" 'スキル（リポ内の .claude/skills）: 2 本' "スキル2本（root release + api-testing）"
expect "$r" '\| TypeScript/JavaScript \| [0-9]+ \| `typescript-lsp` \| `typescript-language-server` \|' "TypeScript を検出し公式プラグインを対応付け"
expect "$r" '警告: `.claudeignore`' ".claudeignore の警告"
if [ "$have_json_interp" -eq 1 ]; then
  expect "$r" '読み取り拒否.*: 1 件' "deny Read ルール1件"
  expect "$r" '`Read\(\./\*\*/dist/\*\*\)`' "deny ルールの内容を表示"
else
  expect "$r" '読み取り拒否.*不明' "deny: python3/node 不在のため不明"
fi
expect "$r" '読み取り拒否の候補ディレクトリ: vendor/' "vendor/ を候補として検出"
expect "$r" '\| オーナーシップ \| 未着手 \|' "オーナー文書なし"
expect "$r" '^\| 第1層 CLAUDE.md \| 充足 \|' "第1層は行数内・階層ありで充足"

echo
echo "== fixture: monorepo（packages/api から起動）"
HOME="$tmp/home-empty" HARNESS_AUDIT_ROOT="$fx/monorepo" bash "$audit" "$fx/monorepo/packages/api" > "$tmp/monorepo-api.md"; echo "exit=$?"
r="$tmp/monorepo-api.md"
expect "$r" 'packages/api/CLAUDE.md` \| 5 \| 範囲内' "起動ディレクトリの CLAUDE.md を読込対象に"
expect "$r" '^\| `.*/monorepo/CLAUDE.md` \| ' "親（ルート）の CLAUDE.md も読込対象に"
expect "$r" '設定ファイル: 起動ディレクトリにありません' "起動ディレクトリに settings なし"
expect "$r" '注意: ルート `.*/monorepo/.claude/settings.json` は、このディレクトリから起動した場合には読み込まれません' "ルート settings が継承されない注意"
expect "$r" '読み取り拒否.*: 0 件' "起動ディレクトリ基準では deny 0 件"

echo
echo "== fixture: empty（何も無いリポ）"
HOME="$tmp/home-empty" HARNESS_AUDIT_ROOT="$fx/empty" bash "$audit" "$fx/empty" > "$tmp/empty.md"; echo "exit=$?"
r="$tmp/empty.md"
expect "$r" '\| 第1層 CLAUDE.md \| 未着手 \|' "第1層 未着手"
expect "$r" '\| 第2層 フック \| 未着手 \|' "第2層 未着手"
expect "$r" '\| 第3層 スキル \| 未着手 \|' "第3層 未着手"
expect "$r" '\| 第4層 プラグイン \| 未着手 \|' "第4層 未着手"
expect "$r" '\| 第5層 LSP \| 未着手 \|' "第5層 未着手（JS を検出）"
expect "$r" '\.gitignore: ありません' ".gitignore なし"

echo
echo "== ルート外の起動ディレクトリ"
if HARNESS_AUDIT_ROOT="$fx/monorepo" bash "$audit" "$fx/empty" > /dev/null 2>&1; then
  echo "FAIL ルート外の起動ディレクトリで exit 0 になっています" >&2; fail=1
else
  echo "ok   ルート外の起動ディレクトリで非ゼロ終了"
fi

echo "== 存在しないディレクトリ"
if bash "$audit" "$tmp/does-not-exist" > /dev/null 2>&1; then
  echo "FAIL 存在しないディレクトリで exit 0 になっています" >&2; fail=1
else
  echo "ok   存在しないディレクトリで非ゼロ終了"
fi

echo
echo "== フックテンプレートのスモークテスト"
hooks="$repo/templates/hooks"
# guard-irreversible: 履歴を書き換える push を deny する
out=$(printf '{"tool_input":{"command":"git push origin main --force"}}' | bash "$hooks/guard-irreversible.sh")
printf '%s' "$out" | grep -q '"permissionDecision": *"deny"' && echo "ok   guard: 強制 push を deny" || { echo "FAIL guard: 強制 push を deny できていません: $out" >&2; fail=1; }
out=$(printf '{"tool_input":{"command":"git status"}}' | bash "$hooks/guard-irreversible.sh")
[ -z "$out" ] && echo "ok   guard: 通常コマンドは通す" || { echo "FAIL guard: 通常コマンドで出力があります: $out" >&2; fail=1; }

# guard-irreversible: 個別ケースの手直しではなく、対象一覧をコーパス化して全件回します
# （tests/fixtures/guard-cases.tsv。差し戻し3回目対応）。JSON の組み立ては python3 に
# 依存せず、シェルの printf/パラメータ展開でエスケープします（" と \ と改行・タブのみ）。
to_json_command() {
  # $1 = 生のコマンド文字列。json.dumps と同じ順序（\ を最初にエスケープし、その後 " ・
  # 実改行・実タブ）でエスケープします。<NL>・<TAB> は、TSV が1行1レコードのため実際の
  # 改行・タブを保持できないコーパス向けの構造マーカーです（コマンド本体には現れない前提の
  # 記法を使い、実際の改行・タブへ変換してからエスケープします）。
  # 重要: コマンド文字列そのものが持つ「文字としての \n・\t」（例: printf 'a\nb' の
  # バックスラッシュ+n の2文字）は、ここでは一切特別扱いしません。単なる文字として \ の
  # エスケープ対象になり、json.dumps 同様に \\n の3文字へ正しく変換されます（差し戻し4巡目で
  # 発見。旧実装は \n・\t の2文字を常に「改行・タブへのマーカー」とみなしており、文字としての
  # \n を区別できず、回帰テストとして表現すること自体ができませんでした）。
  local raw="$1" s
  s="${raw//<NL>/$'\n'}"
  s="${s//<TAB>/$'\t'}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '{"tool_input":{"command":"%s"}}' "$s"
}

run_guard_corpus() {
  # $1=PATH値 $2=環境名 $3=1なら「この環境ではケースごとに毎回 stderr に警告が出ること」も必須にする
  # （差し戻し4巡目対応: コーパス全体で1回でも警告があれば良しとする集計だと、特定ケースだけが
  # 無音で通っている劣化を見逃すため、ケース単位で判定する）
  local envpath="$1" envname="$2" require_warn="${3:-0}"
  local corpus="$fx/guard-cases.tsv"
  local total=0 cfail=0
  local expect cmd json out err got errfile
  # ファイル名に環境名（コロンを含む）をそのまま使うと、macOS（APFS/HFS+互換層）でコロンが
  # パス区切りとして扱われ「No such file or directory」になるため、1件ごとの stderr は
  # 固定名の使い捨てファイルに書きます（各ケースは逐次処理のため使い回して問題ありません）。
  errfile="$tmp/guard-corpus.err"

  while IFS=$'\t' read -r expect cmd || [ -n "${expect:-}" ]; do
    [ -z "${expect:-}" ] && continue
    [ "$expect" = "#" ] && continue
    total=$((total+1))
    json="$(to_json_command "$cmd")"
    out=$(printf '%s' "$json" | PATH="$envpath" bash "$hooks/guard-irreversible.sh" 2>"$errfile")
    err="$(cat "$errfile" 2>/dev/null)"
    if printf '%s' "$out" | grep -q '"permissionDecision": *"deny"'; then got=deny; else got=pass; fi
    if [ "$got" != "$expect" ]; then
      echo "FAIL guard-corpus[$envname]: expect=$expect got=$got cmd=[$cmd]" >&2
      cfail=$((cfail+1))
    fi
    if [ "$require_warn" -eq 1 ] && ! printf '%s' "$err" | grep -q '警告'; then
      echo "FAIL guard-corpus[$envname]: このケースだけ無音で通っています cmd=[$cmd]" >&2
      cfail=$((cfail+1))
    fi
  done < "$corpus"

  if [ "$cfail" -eq 0 ]; then
    echo "ok   guard-corpus[$envname]: $total 件すべて期待どおり（require_warn=$require_warn はケースごとに判定）"
  else
    echo "FAIL guard-corpus[$envname]: $cfail 件が期待と不一致（total=$total）" >&2
    fail=1
  fi
}

# (a) 通常 PATH（python3 あり）
run_guard_corpus "$PATH" "a:通常PATH"

# (b) node のみ（python3 を PATH から外す）。ホストに node が無ければ skip します。
guard_path_node="$tmp/guard-path-node"
rm -rf "$guard_path_node" && mkdir -p "$guard_path_node"
for b in bash grep sed awk tr find git wc date dirname basename sort cmp mkdir cp head uniq cat env rm ln mv chmod printf true false expr node; do
  p="$(command -v "$b" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$guard_path_node/$b"
done
if [ -x "$guard_path_node/node" ]; then
  run_guard_corpus "$guard_path_node" "b:nodeのみ"
else
  echo "skip guard-corpus[b:nodeのみ]: このホストに node がありません" >&2
fi

# (c) sed/grep のみ（python3・node どちらも外す。tier3。常に警告が出ます）
guard_path_tier3="$tmp/guard-path-tier3"
rm -rf "$guard_path_tier3" && mkdir -p "$guard_path_tier3"
for b in bash grep sed awk tr find git wc date dirname basename sort cmp mkdir cp head uniq cat env rm ln mv chmod printf true false expr; do
  p="$(command -v "$b" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$guard_path_tier3/$b"
done
run_guard_corpus "$guard_path_tier3" "c:sed/grepのみ" 1

# (d) 壊れた python3（存在するが exit 127 する）を PATH 先頭に置く。node は含めず tier3 まで
# 落ちることを確認します（S-1 の再現・修正確認。pyenv shim が未導入バージョンを指す場合等）。
guard_path_broken="$tmp/guard-path-broken-python3"
rm -rf "$guard_path_broken" && mkdir -p "$guard_path_broken"
for b in bash grep sed awk tr find git wc date dirname basename sort cmp mkdir cp head uniq cat env rm ln mv chmod printf true false expr; do
  p="$(command -v "$b" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$guard_path_broken/$b"
done
{
  printf '#!/bin/sh\n'
  printf 'echo "pyenv: version 3.11.9 is not installed" >&2\n'
  printf 'exit 127\n'
} > "$guard_path_broken/python3"
chmod +x "$guard_path_broken/python3"
run_guard_corpus "$guard_path_broken" "d:壊れたpython3(exit127)" 1

# (e) grep が PATH に無い環境。判定ロジックそのものが動かせないため（:20-27 の外部コマンド存在
# チェック）、コーパス全件ではなく代表ケースのみ「警告付きで pass」になることを確認します
# （grep 欠落時は deny 判定自体ができないため、コーパスの deny 期待とは比較できません）。
guard_path_no_grep="$tmp/guard-path-no-grep"
rm -rf "$guard_path_no_grep" && mkdir -p "$guard_path_no_grep"
for b in bash sed awk tr find git wc date dirname basename sort cmp mkdir cp head uniq cat env rm ln mv chmod printf true false expr; do
  p="$(command -v "$b" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$guard_path_no_grep/$b"
done
no_grep_fail=0
for cmd in 'git push --force origin main' 'git status' 'rm -rf /tmp/x'; do
  errfile="$tmp/guard-no-grep.err"
  json="$(to_json_command "$cmd")"
  out=$(printf '%s' "$json" | PATH="$guard_path_no_grep" bash "$hooks/guard-irreversible.sh" 2>"$errfile")
  err="$(cat "$errfile" 2>/dev/null)"
  if [ -n "$out" ]; then
    echo "FAIL guard-corpus[e:grep無し]: grep 欠落時は判定できず pass のはずが出力があります cmd=[$cmd] out=[$out]" >&2
    no_grep_fail=1
  fi
  if ! printf '%s' "$err" | grep -qE '警告.*grep'; then
    echo "FAIL guard-corpus[e:grep無し]: grep 欠落の警告が出ていません cmd=[$cmd] err=[$err]" >&2
    no_grep_fail=1
  fi
done
if [ "$no_grep_fail" -eq 0 ]; then
  echo "ok   guard-corpus[e:grep無し]: 代表3件すべて警告付き pass"
else
  fail=1
fi

# guard-irreversible: 異常入力（無音で通さないことの確認。差し戻し4巡目対応）
guard_anomaly_fail=0
check_anomaly() {
  # $1=説明 $2=標準入力に渡す生テキスト
  local desc="$1" raw="$2" out err errfile
  errfile="$tmp/guard-anomaly.err"
  out=$(printf '%s' "$raw" | bash "$hooks/guard-irreversible.sh" 2>"$errfile")
  err="$(cat "$errfile" 2>/dev/null)"
  if [ -n "$out" ]; then
    echo "FAIL guard-anomaly[$desc]: 出力があります（無音で通すべき）: $out" >&2
    guard_anomaly_fail=1
    return
  fi
  if ! printf '%s' "$err" | grep -q '警告'; then
    echo "FAIL guard-anomaly[$desc]: stderr に警告がありません（無音通過）" >&2
    guard_anomaly_fail=1
    return
  fi
  echo "ok   guard-anomaly[$desc]: 警告付きで exit 0"
}
check_anomaly "途中で切れたJSON" '{"tool_input":{"command":"echo hi"'
check_anomaly "非JSON文字列" 'not a json at all'
check_anomaly "stdin空" ''
check_anomaly "tool_input欠落" '{"foo":"bar"}'
check_anomaly "command空文字" '{"tool_input":{"command":""}}'
[ "$guard_anomaly_fail" -eq 0 ] || fail=1

# format-and-check: 対象外の拡張子は何もせず exit 0
printf '{"tool_input":{"file_path":"%s"}}' "$fx/monorepo/package.json" | bash "$hooks/format-and-check.sh" >/dev/null 2>&1 && echo "ok   format-and-check: 対象外は exit 0" || { echo "FAIL format-and-check: 対象外で非ゼロ" >&2; fail=1; }
# stop-propose-claudemd: 訂正の発話を候補として抜き出す
mkdir -p "$tmp/stop" && printf '%s\n' '{"type":"user","message":{"content":"今後は migration を編集しないで、新しく追加してください"}}' '{"type":"assistant","message":{"content":[{"type":"text","text":"了解しました"}]}}' '{"type":"user","message":{"content":"ありがとう"}}' > "$tmp/stop/transcript.jsonl"
rm -f "$tmp/stop/.claude/harness-kit/claudemd-candidates.md"
printf '{"transcript_path":"%s"}' "$tmp/stop/transcript.jsonl" | CLAUDE_PROJECT_DIR="$tmp/stop" bash "$hooks/stop-propose-claudemd.sh"
if grep -q 'migration を編集しないで' "$tmp/stop/.claude/harness-kit/claudemd-candidates.md" 2>/dev/null && ! grep -q 'ありがとう' "$tmp/stop/.claude/harness-kit/claudemd-candidates.md"; then
  echo "ok   stop: 訂正の発話だけを候補に抜き出す"
else
  echo "FAIL stop: 候補ファイルの内容が想定と異なります" >&2; fail=1
fi
# session-start-context: 起動ディレクトリ名と候補件数を出す
out=$(cd "$tmp/stop" && CLAUDE_PROJECT_DIR="$tmp/stop" bash "$hooks/session-start-context.sh")
printf '%s' "$out" | grep -q '追記候補が 1 件' && echo "ok   session-start: 候補件数を通知" || { echo "FAIL session-start: 候補件数が出ていません: $out" >&2; fail=1; }

echo
echo "== python3 / node が無い環境でのフォールバック"
noipath="$tmp/no-interpreter-path"
rm -rf "$noipath" && mkdir -p "$noipath"
for b in bash grep sed awk tr find git wc date dirname basename sort cmp mkdir cp head uniq cat env rm ln mv chmod printf true false expr; do
  p="$(command -v "$b" 2>/dev/null)" && ln -sf "$p" "$noipath/$b"
done

r="$tmp/no-interp-audit.md"
# .claude/settings.json が実在する起動ディレクトリ（ルート）でないと、
# 「ファイルが無いので未着手」と「JSON を解釈できず不明」を区別できないため、ルートを対象にします。
PATH="$noipath" HOME="$tmp/home-empty" HARNESS_AUDIT_ROOT="$fx/monorepo" bash "$audit" "$fx/monorepo" > "$r" 2> "$tmp/no-interp-audit.err"; echo "exit=$?"
expect "$r" 'JSON の解釈: 不可（python3 / node なし）' "python3/node 不在: レポート冒頭に明示"
expect "$r" '\| 第2層 フック \| 不明 \|' "python3/node 不在: 第2層フックが不明判定（未着手に誤判定しない）"
expect "$r" '\| 第4層 プラグイン \| 不明 \|' "python3/node 不在: 第4層プラグインが不明判定"
expect "$r" '読み取り拒否.*不明' "python3/node 不在: 除外の deny 件数が不明判定"
# guard-irreversible の python3/node 不在時の挙動は、上の guard-corpus[c:sed/grepのみ] で
# コーパス全件（"git status" のような pass ケースの警告有無を含む）を確認済みのため、
# ここでの個別アサーションは持たず二重管理を避けます。

echo
echo "== shellcheck / bash -n"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "$audit" "$0" && echo "ok   shellcheck" || fail=1
fi
bash -n "$audit" && echo "ok   bash -n"

echo
if [ "$fail" -eq 0 ]; then echo "tests: OK"; else echo "tests: FAILED" >&2; fi
exit "$fail"
