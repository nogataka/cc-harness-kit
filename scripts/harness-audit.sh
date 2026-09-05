#!/usr/bin/env bash
# 実体は skills/audit/harness-audit/scripts/harness-audit.sh です（スキルに同梱するため）。
exec bash "$(cd "$(dirname "$0")/.." && pwd)/skills/audit/harness-audit/scripts/harness-audit.sh" "$@"
