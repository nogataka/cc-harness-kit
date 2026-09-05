#!/usr/bin/env bash
# スキル一覧を「パス | 起動方式 | description」で出します。
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"

find skills -name SKILL.md -not -path '*/templates/*' | sort | while IFS= read -r f; do
  mode="model-invoked"
  if grep -qE '^disable-model-invocation:[[:space:]]*true' "$f"; then
    mode="user-invoked"
  fi
  desc="$(grep -m1 -E '^description:' "$f" | sed -E 's/^description:[[:space:]]*//; s/^"//; s/"$//' | cut -c1-90)"
  printf '%-45s | %-13s | %s\n' "${f%/SKILL.md}" "$mode" "$desc"
done
