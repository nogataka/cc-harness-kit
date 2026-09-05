#!/usr/bin/env bash
# PreToolUse（Bash）用。不可逆な操作を機械的に止め、確認を促します。
# CLAUDE.md に「〜しないでください」と書くだけでは強制になりません。止めたいものはここに列挙します。
# 対象リポの事情に合わせてパターンを追加・削除してください。
#
# JSON の読み取りは python3 → node → sed/grep の順でフォールバックします。
# python3 / node が「存在するが実行に失敗する」場合（例: pyenv shim が未導入バージョンを指す、
# Xcode Command Line Tools 未導入の /usr/bin/python3 スタブ）も、無音で判定を諦めず次の tier へ
# 落とします。全 tier が失敗した場合・不正な JSON の場合・command が空の場合は、判定ができな
# かったことを stderr に警告してから通します（無音で通しません。詳細は harness-hooks/SKILL.md）。
#
# rm/git push の検出は生のコマンド文字列への grep なので、echo/grep の文字列引数に
# 「rm -rf」等の言及があるだけでも deny します（実行ではなく言及に過ぎない場合の誤検知）。
# これは意図的です。不可逆な操作を機械的に止めるという目的上、見逃す（false negative）より
# 過検知する（false positive）方を安全側として許容します。
set -u

# 判定に必要な外部コマンドが PATH に無ければ、判定そのものができません。
# 無音で通す（＝ガードが無効化されたことに気づけない）のを避け、tier3 と同じ警告を出します。
missing=""
for t in grep sed tr; do
  command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
if [ -n "$missing" ]; then
  echo "警告: 判定に必要な外部コマンド(${missing# }) が見つからないため、コマンドの安全性判定ができません。念のためこのコマンドの実行は通しますが、判定ロジックは機能していません。" >&2
  exit 0
fi

input="$(cat)"

# 標準入力の JSON から tool_input.command を取り出します。
# 戻り値: 0=python3 か node で取り出せた（$REPLY にセット） / 2=sed/grep の簡易抽出にフォールバックした
extract_command() {
  local rc

  if command -v python3 >/dev/null 2>&1; then
    REPLY="$(printf '%s' "$input" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print((d.get("tool_input") or {}).get("command") or "")
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
    process.stdout.write(((d.tool_input || {}).command) || "");
  } catch (e) {
    process.exit(3);
  }
});
' 2>/dev/null)"
    rc=$?
    [ "$rc" -eq 0 ] && return 0
  fi

  # ネストした引用符など一部の複雑な書き方には対応しない簡易抽出です。
  # \n・\t は復元しますが、それ以外のネストした引用符の一部ケースは見逃す場合があります。
  #
  # 復元順序に注意: JSON側で「リテラルなバックスラッシュ+n」（例: printf 'a\nb' のように、
  # コマンド文字列そのものが持つバックスラッシュとnの2文字。json.dumps は \\n の3文字にエンコード
  # する）と「改行エスケープ \n」（json.dumps が改行を \n の2文字にエンコードしたもの）は、
  # どちらも復元前の生JSON上では「バックスラッシュが連続する文字列」として現れ得るため、
  # 先に \\ を \n/\t の復元より前に単純展開すると、前者を誤って改行に変換してしまう
  # （code-review 4巡目で実測。tier3限定で強制pushの検出漏れを引き起こしていた）。
  # そのため二重バックスラッシュ（\\）を、command 文字列に出現しない制御バイト（0x01）へ一旦
  # 退避してから \n・\t・\" を復元し、最後にその制御バイトを単一バックスラッシュへ戻す。
  # \x01 のようなsedの16進エスケープ記法はBSD sed（macOS）が解釈しないため、printf で実バイトを
  # 変数に入れてsed式へ埋め込む（BSD/GNU双方で同じ結果になる）。
  local ph
  ph="$(printf '\001')"
  REPLY="$(printf '%s' "$input" | grep -o '"command"[[:space:]]*:[[:space:]]*"\([^"\\]\|\\.\)*"' | head -1 | sed -E 's/^"command"[[:space:]]*:[[:space:]]*"//; s/"$//; s/\\\\/'"$ph"'/g; s/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g; s/'"$ph"'/\\/g')"
  return 2
}

extract_command
extract_rc=$?
cmd="$REPLY"
# tier3（sed/grep）を使った場合、および python3/node/tier3 のいずれを使っても command を
# 取り出せなかった場合（不正な JSON、tool_input 欠落、command 空を含む）は、判定が十分に
# できていない可能性があることを stderr に警告します（無音で通さないため）。
if [ "$extract_rc" -ne 0 ] || [ -z "$cmd" ]; then
  echo "警告: コマンドの安全性判定に必要な情報を取得できませんでした（python3 / node が使えない、JSON が不正、または command が空です）。sed/grep による簡易抽出、あるいは抽出そのものに失敗しており、複雑な引用符を含むコマンドなどを見逃す場合があります。念のためこのコマンドの実行は通します。" >&2
fi
[ -n "$cmd" ] || exit 0

deny() {
  # 設計判断: 理由文字列にはコマンド断片を含めません（JSON 破壊、および接続文字列・トークン等の
  # 秘密情報がトランスクリプトへ転記されることを防ぐため）。
  # $1=理由。ダブルクォートとバックスラッシュだけをエスケープして JSON を組み立てます（python3 不要）。
  local reason="$1"
  reason="${reason//\\/\\\\}"
  reason="${reason//\"/\\\"}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
}

# rm による再帰・強制削除の組み合わせ検出。
# -rf・-fr・-Rf・-fR のような1トークン内の順不同、および --force と -r/-R/--recursive の
# 別トークンの組み合わせ（順不同）も捕まえます。; | & で区切った rm を含む区間ごとに判定します。
# rm の左境界は「単語境界」（\b 相当。文字列先頭または英数字・アンダースコア以外）を使います。
# 空白のみを境界にすると bash -c "rm -rf x" や (rm -rf x)、$(rm -rf x) のような
# 入れ子シェル・サブシェル経由の rm を見逃すためです（クォートや括弧の直後も rm の開始とみなす）。
rm_force_and_recursive() {
  local cmd="$1" seg
  while IFS= read -r seg; do
    printf '%s' "$seg" | grep -qE '(^|[^a-zA-Z0-9_])rm([[:space:]]|$)' || continue
    printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*f[a-zA-Z]*|--force)([[:space:]]|$)' || continue
    printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]|$)' || continue
    return 0
  done <<EOF
$(printf '%s' "$cmd" | tr ';|&' '\n\n\n')
EOF
  return 1
}

# git の破壊的なローカル操作（branch -D 相当・reset --hard・clean -f 相当）。
# git のグローバルオプション（-C <dir>・-c k=v・--git-dir= など）を挟んでも検出できるよう、
# 「git」と各キーワードが同じ区間（; | & 区切り）にあるかで判定します（rm と同じ設計判断）。
# フラグは結合・ロング形式・別トークンいずれの書き方も拾います。
git_destructive_local() {
  local cmd="$1" seg has_force
  while IFS= read -r seg; do
    printf '%s' "$seg" | grep -qE '(^|[^a-zA-Z0-9_])git([[:space:]]|$)' || continue

    has_force=1
    printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*f[a-zA-Z]*|--force)([[:space:]]|$)' && has_force=0

    # reset --hard
    printf '%s' "$seg" | grep -qE '(^|[[:space:]])reset([[:space:]]|$)' \
      && printf '%s' "$seg" | grep -qE '(^|[[:space:]])--hard([[:space:]]|$)' \
      && return 0

    # branch -D（それ自体で force delete）／branch --delete|-d + --force|-f（別トークンの組み合わせ）
    if printf '%s' "$seg" | grep -qE '(^|[[:space:]])branch([[:space:]]|$)'; then
      printf '%s' "$seg" | grep -qE '(^|[[:space:]])-D([[:space:]]|$)' && return 0
      printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-d|--delete)([[:space:]]|$)' && [ "$has_force" -eq 0 ] && return 0
    fi

    # clean + force フラグ（結合・ロング・別トークンいずれも）
    printf '%s' "$seg" | grep -qE '(^|[[:space:]])clean([[:space:]]|$)' && [ "$has_force" -eq 0 ] && return 0
  done <<EOF
$(printf '%s' "$cmd" | tr ';|&' '\n\n\n')
EOF
  return 1
}

# 履歴の書き換えを伴う push。結合短縮オプション（-uf・-fu など）、短縮 refspec の `+`（`+main`・
# `+HEAD:main` 等）、`--mirror` も捕まえます。`git` の直後にグローバルオプションを挟んでも
# （`git -C <dir> push` 等）検出できるよう、`push` の前を区間内ワイルドカードにしています。
# -f 系フラグ・`+` refspec の左境界に (^|[[:space:]]) を要求し、feature-fix・release-final の
# ようなブランチ名末尾のハイフン文字列や、`v1.2.3` のようなタグ名を誤って強制 push と検知しません。
printf '%s' "$cmd" | grep -qE 'git[[:space:]][^|;&]*push[^|;&]*(--force|(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)|\+refs/|--mirror|(^|[[:space:]])\+[A-Za-z0-9_./@^~-]+([:[:space:]]|$))' && deny "履歴を書き換える push は人が実行してください。"
# ブランチの強制削除・reset --hard・clean -f 相当（git のグローバルオプションを挟んでも検出）
git_destructive_local "$cmd" && deny "作業内容を失う git 操作は人が実行してください。"
# 本番反映（例。対象リポのデプロイコマンドに置き換える）
printf '%s' "$cmd" | grep -qE '(terraform|tofu)[[:space:]]+(apply|destroy)|kubectl[[:space:]]+(apply|delete)[^|;&]*prod' && deny "本番環境を変える操作は人が実行してください。"
# データ削除（rm -rf 系。順序・ロングオプション・別トークンの組み合わせを問わず検出）
rm_force_and_recursive "$cmd" && deny "データを失う操作は人が実行してください。"
# DB クライアント経由の DROP/TRUNCATE/DELETE FROM。大文字・小文字・混在を区別しません。
# grep や echo の文字列中の言及までは deny しません（DB クライアント名との AND 条件のため）。
# DELETE FROM は DML で頻度が高く、WHERE 句付きのスコープされた正当な削除も止まります。
# 頻繁に実行するリポでは、この選択肢だけ外して構いません。
printf '%s' "$cmd" | grep -qEi '\b(psql|mysql|mysqladmin|sqlite3|mariadb)\b' \
  && printf '%s' "$cmd" | grep -qEi '\bDROP[[:space:]]+(TABLE|DATABASE|SCHEMA|INDEX)|\bTRUNCATE[[:space:]]|\bDELETE[[:space:]]+FROM' \
  && deny "データを失う操作は人が実行してください。"

exit 0
