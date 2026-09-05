#!/usr/bin/env bash
# Stop（Claude が応答を終えたとき）用。セッション中に人が訂正した内容を拾い、CLAUDE.md への追記候補をファイルに書き出します。
# 書き出すだけで CLAUDE.md は変更しません。候補は .claude/harness-kit/claudemd-candidates.md に溜まります。
#
# JSON の読み取りは python3 → node → sed/grep の順でフォールバックします。
# どちらも無い場合は sed/grep による簡易抽出になります。1行1JSON（JSONL）という前提を使い、
# `"type":"user"` を含む行から `"text":"..."` または `"content":"..."` を粗く取り出します。
# ネストした引用符や複数行の発話は正しく抜き出せない場合があります。
set -u

input="$(cat)"

extract_transcript_path() {
  local rc

  if command -v python3 >/dev/null 2>&1; then
    REPLY="$(printf '%s' "$input" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); print(d.get("transcript_path") or "")
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
    process.stdout.write(d.transcript_path || "");
  } catch (e) {
    process.exit(3);
  }
});
' 2>/dev/null)"
    rc=$?
    [ "$rc" -eq 0 ] && return 0
  fi

  REPLY="$(printf '%s' "$input" | grep -o '"transcript_path"[[:space:]]*:[[:space:]]*"\([^"\\]\|\\.\)*"' | head -1 | sed -E 's/^"transcript_path"[[:space:]]*:[[:space:]]*"//; s/"$//; s/\\"/"/g; s/\\\\/\\/g')"
}

extract_transcript_path
transcript="$REPLY"
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

out_dir="${CLAUDE_PROJECT_DIR:-.}/.claude/harness-kit"
mkdir -p "$out_dir"
out="$out_dir/claudemd-candidates.md"

# python3 / node が「存在するが実行に失敗する」場合も、無音で次の tier へ落とします
# （このフックは非セキュリティ機能のため、guard-irreversible.sh と違い警告は出さず、候補の
# 抽出を静かにスキップ・フォールバックするだけにします）。
python3_rc=1
if command -v python3 >/dev/null 2>&1; then
  # 人の発話のうち、訂正・禁止・指示の口調を含む行を候補として抜き出す（雑な抽出で構いません。人が読んで選びます）。
  python3 - "$transcript" "$out" <<'PY' 2>/dev/null
import json, sys, datetime
src, dst = sys.argv[1], sys.argv[2]
keys = ("しないで", "やめて", "違う", "ではなく", "必ず", "今後は", "覚えて", "never", "don't", "always", "instead")
found = []
for line in open(src, encoding="utf-8", errors="replace"):
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("type") != "user":
        continue
    msg = d.get("message") or {}
    content = msg.get("content")
    texts = []
    if isinstance(content, str):
        texts.append(content)
    elif isinstance(content, list):
        texts += [c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text"]
    for t in texts:
        t = t.strip()
        if 8 <= len(t) <= 300 and any(k in t for k in keys):
            found.append(t)
if found:
    with open(dst, "a", encoding="utf-8") as f:
        f.write(f"\n## {datetime.datetime.now():%Y-%m-%d %H:%M} のセッションからの候補\n\n")
        for t in dict.fromkeys(found):
            f.write(f"- [ ] {t}\n")
        f.write("\n（採用するものだけ CLAUDE.md か rules に移し、残りは消してください）\n")
PY
  python3_rc=$?
fi

node_rc=1
if [ "$python3_rc" -ne 0 ] && command -v node >/dev/null 2>&1; then
  node -e '
const fs = require("fs");
const src = process.argv[1], dst = process.argv[2];
const keys = ["しないで","やめて","違う","ではなく","必ず","今後は","覚えて","never","don'"'"'t","always","instead"];
const found = [];
const lines = fs.readFileSync(src, "utf8").split("\n");
for (const line of lines) {
  if (!line.trim()) continue;
  let d;
  try { d = JSON.parse(line); } catch (e) { continue; }
  if (d.type !== "user") continue;
  const msg = d.message || {};
  const content = msg.content;
  let texts = [];
  if (typeof content === "string") texts.push(content);
  else if (Array.isArray(content)) texts = content.filter(function (c) { return c && c.type === "text"; }).map(function (c) { return c.text || ""; });
  for (let t of texts) {
    t = t.trim();
    if (t.length >= 8 && t.length <= 300 && keys.some(function (k) { return t.indexOf(k) !== -1; })) found.push(t);
  }
}
if (found.length) {
  const uniq = found.filter(function (t, i) { return found.indexOf(t) === i; });
  const now = new Date();
  const pad = function (n) { return String(n).length < 2 ? "0" + n : String(n); };
  const stamp = now.getFullYear() + "-" + pad(now.getMonth() + 1) + "-" + pad(now.getDate()) + " " + pad(now.getHours()) + ":" + pad(now.getMinutes());
  let text = "\n## " + stamp + " のセッションからの候補\n\n";
  for (const t of uniq) text += "- [ ] " + t + "\n";
  text += "\n（採用するものだけ CLAUDE.md か rules に移し、残りは消してください）\n";
  fs.appendFileSync(dst, text);
}
' "$transcript" "$out" 2>/dev/null
  node_rc=$?
fi

if [ "$python3_rc" -ne 0 ] && [ "$node_rc" -ne 0 ]; then
  # 簡易抽出。JSONL は1行1オブジェクトである前提を使い、行内の "text" か "content" 文字列を粗く取り出します。
  found=""
  while IFS= read -r line; do
    printf '%s' "$line" | grep -qE '"type"[[:space:]]*:[[:space:]]*"user"' || continue
    text="$(printf '%s' "$line" | grep -o '"text"[[:space:]]*:[[:space:]]*"\([^"\\]\|\\.\)*"' | head -1)"
    [ -n "$text" ] || text="$(printf '%s' "$line" | grep -o '"content"[[:space:]]*:[[:space:]]*"\([^"\\]\|\\.\)*"' | head -1)"
    [ -n "$text" ] || continue
    text="$(printf '%s' "$text" | sed -E 's/^"[a-zA-Z_]+"[[:space:]]*:[[:space:]]*"//; s/"$//; s/\\"/"/g; s/\\\\/\\/g')"
    len=${#text}
    [ "$len" -ge 8 ] && [ "$len" -le 300 ] || continue
    printf '%s' "$text" | grep -qE 'しないで|やめて|違う|ではなく|必ず|今後は|覚えて|never|always|instead|don.t' || continue
    printf '%s\n' "$found" | grep -qF "$text" && continue
    found="$found
$text"
  done < "$transcript"
  found="$(printf '%s' "$found" | awk 'NF')"
  if [ -n "$found" ]; then
    {
      printf '\n## %s のセッションからの候補\n\n' "$(date '+%Y-%m-%d %H:%M')"
      printf '%s\n' "$found" | sed 's/^/- [ ] /'
      printf '\n（採用するものだけ CLAUDE.md か rules に移し、残りは消してください）\n'
    } >> "$out"
  fi
fi
exit 0

