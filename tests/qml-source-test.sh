#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
QML_SOURCE=$(find "$ROOT" -maxdepth 1 -name '*.qml' -type f -exec sed -n '1,$p' {} +)

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ $QML_SOURCE != *"notify-send"* ]] || fail "use omarchy-notification-send"
[[ $QML_SOURCE != *"Qt.openUrlExternally"* ]] || fail "use omarchy-launch-browser"
[[ $QML_SOURCE == *'omarchy-launch-browser'* ]] || fail "browser links must use omarchy-launch-browser"
[[ $QML_SOURCE == *'Model.isSafeHttpUrl'* || $QML_SOURCE == *'"https://omarchy.org/news"'* ]] || fail "dynamic browser URLs must pass isSafeHttpUrl"
[[ $QML_SOURCE != *'["bash"'* ]] || fail "runtime commands must not invoke a shell"
[[ $QML_SOURCE == *'"--proto", "=https", "--max-time", "15"'* ]] || fail "feed fetch must be HTTPS-only and time-bounded"
[[ $QML_SOURCE == *'"--max-filesize", "2097152"'* ]] || fail "feed fetch must have a two-megabyte limit"
[[ $QML_SOURCE == *'atomicWrites: true'* ]] || fail "state and cache writes must be atomic"
[[ $QML_SOURCE == *'bar.shell.serviceFor(moduleName)'* ]] || fail "bar widgets must share the singleton service"
[[ $QML_SOURCE == *'visible: root.unseenCount > 0'* ]] || fail "the bar dot must follow unseen posts"
[[ $QML_SOURCE == *'Model.sanitizeInline'* ]] || fail "reader HTML must pass through the inline sanitizer"
[[ $QML_SOURCE == *'feed.imagePath'* ]] || fail "reader images must load from the local image cache"
[[ $QML_SOURCE == *'Easing.OutCubic'* ]] || fail "the list-to-reader page turn must use the approved easing"
[[ $QML_SOURCE != *'wl-copy'* ]] || fail "the panel must not expose link-copy behavior"
[[ $QML_SOURCE == *'titleText.lineCount'* ]] || fail "the unread dot must centre on the first title line, not the whole row"
[[ $QML_SOURCE == *'"omarchy-notification-send", "--app-name", "Omarchy News", "-u", "normal"'* ]] || fail "new-post notices must use the Omarchy notification helper"
[[ $QML_SOURCE == *'"--exec", "omarchy-shell", "shell", "summon", "io.github.eliasstravik.omarchy-news", "{}"'* ]] || fail "notification clicks must summon the panel with fixed argv"

while IFS= read -r command; do
  [[ $command =~ command:[[:space:]]*\[ ]] || fail "Process.command must use an argv array: $command"
done < <(grep -hE '^[[:space:]]*command:' "$ROOT"/*.qml || true)

echo "QML source tests passed"
