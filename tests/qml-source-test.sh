#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
QML_SOURCE=$(find "$ROOT" -maxdepth 1 -name '*.qml' -type f -exec sed -n '1,$p' {} +)

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ $QML_SOURCE != *"notify-send"* ]] || fail "use omarchy-notification-send"
[[ $QML_SOURCE != *"Qt.openUrlExternally"* ]] || fail "use omarchy-launch-browser"

while IFS= read -r command; do
  [[ $command =~ command:[[:space:]]*\[ ]] || fail "Process.command must use an argv array: $command"
done < <(grep -hE '^[[:space:]]*command:' "$ROOT"/*.qml || true)

echo "QML source tests passed"
