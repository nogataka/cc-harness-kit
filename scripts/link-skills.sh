#!/usr/bin/env bash
# 開発用。このリポジトリの全スキルを ~/.claude/skills にシンボリックリンクします。
# git pull すればリンク先が更新されるので、再インストールは不要です。
# 利用者向けの導入手段ではありません（利用者はプラグインとして入れます）。
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
dest="${CC_HARNESS_KIT_SKILLS_DIR:-$HOME/.claude/skills}"

if [ -L "$dest" ]; then
  resolved="$(cd "$dest" && pwd -P)"
  case "$resolved" in
    "$repo"|"$repo"/*)
      echo "error: $dest はこのリポジトリ内を指すシンボリックリンクです。削除してから再実行してください。" >&2
      exit 1
      ;;
  esac
fi
mkdir -p "$dest"

find "$repo/skills" -name SKILL.md -not -path '*/templates/*' | sort | while IFS= read -r skill_md; do
  src="$(dirname "$skill_md")"
  name="$(basename "$src")"
  target="$dest/$name"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "skip  ${name} (実体のディレクトリが既にあります。手で確認してください)" >&2
    continue
  fi
  ln -sfn "$src" "$target"
  echo "linked $name -> $src"
done
