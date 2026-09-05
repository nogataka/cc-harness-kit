#!/usr/bin/env bash
# PostToolUse（Edit|Write）用。編集されたファイルに対してフォーマッタと静的チェックを走らせます。
# 対象リポの実態に合わせて、下の case のコマンドを書き換えてください。
# stdin には Claude Code から JSON（tool_input.file_path など）が渡されます。
#
# JSON の読み取りは python3 → node → sed/grep の順でフォールバックします。
# どちらも無い場合は sed/grep による簡易抽出になり、抽出できなければ何もせず終了します
# （フォーマット・チェックは補助機能のため、失敗時は静かにスキップします）。
set -u

input="$(cat)"

# 標準入力の JSON から tool_input.file_path を取り出し、$REPLY にセットします。
# python3 / node が「存在するが実行に失敗する」場合も、無音で次の tier へ落とします
# （このフックは非セキュリティ機能のため、guard-irreversible.sh と違い警告は出さず静かに
# フォーマット・チェックをスキップするだけにします）。
extract_file_path() {
  local rc

  if command -v python3 >/dev/null 2>&1; then
    REPLY="$(printf '%s' "$input" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); print((d.get("tool_input") or {}).get("file_path") or "")
except Exception:
    sys.exit(3)' 2>/dev/null)"
    rc=$?
    [ "$rc" -eq 0 ] && return 0
  fi

  if command -v node >/dev/null 2>&1; then
    REPLY="$(printf '%s' "$input" | node -e '
let s = "";
process.stdin.on("data", function (c) { s += c; });
process.stdin.on("end", function () {
  try {
    const d = JSON.parse(s);
    process.stdout.write(((d.tool_input || {}).file_path) || "");
  } catch (e) {
    process.exit(3);
  }
});
' 2>/dev/null)"
    rc=$?
    [ "$rc" -eq 0 ] && return 0
  fi

  REPLY="$(printf '%s' "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"\([^"\\]\|\\.\)*"' | head -1 | sed -E 's/^"file_path"[[:space:]]*:[[:space:]]*"//; s/"$//; s/\\"/"/g; s/\\\\/\\/g')"
}

extract_file_path
file="$REPLY"

[ -n "$file" ] && [ -f "$file" ] || exit 0

# コマンドは配列で持ち、文字列を再解釈しません（ファイル名に記号が含まれても安全です）。
fmt=()
chk=()
case "$file" in
  *.ts|*.tsx|*.js|*.jsx)
    fmt=(npx --no-install prettier --write "$file")
    chk=(npx --no-install tsc --noEmit)
    ;;
  *.py)
    fmt=(ruff format "$file")
    chk=(ruff check "$file")
    ;;
  *)
    exit 0
    ;;
esac

# フォーマットは黙って適用します。
"${fmt[@]}" >/dev/null 2>&1 || true

# チェックの失敗は stderr に出して exit 2 にすると、Claude にフィードバックとして返り、同じターンで修正に向かいます。
if ! out="$("${chk[@]}" 2>&1)"; then
  printf '%s\n' "$out" | tail -30 >&2
  exit 2
fi
exit 0
