#!/bin/zsh
# auto-cleanup.sh を launchd に週 1 回の定期ジョブとして登録する（再実行すると入れ替える）。
#
#   install-auto.sh [WEEKDAY] [HOUR] [MINUTE]   既定: 6 8 0（土曜 08:00、Mac のローカル時刻）
#   install-auto.sh --uninstall
#
# WEEKDAY は launchd の表記（0 と 7 が日曜、6 が土曜）。発火時刻にスリープ中なら復帰後に 1 回だけ走る。
set -eu

LABEL="${DISK_AUTO_CLEANUP_LABEL:-local.disk-auto-cleanup}"
STATE_DIR="${DISK_AUTO_CLEANUP_DIR:-${HOME}/.claude/disk-auto-cleanup}"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
SCRIPT="${0:A:h}/auto-cleanup.sh"
EXAMPLE="${0:A:h}/../assets/auto-cleanup.config.example"
DOMAIN="gui/$(id -u)"

launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
if [[ "${1:-}" == "--uninstall" ]]; then
  rm -f "$PLIST"
  echo "removed ${LABEL}（${STATE_DIR} の設定とログは残している）"
  exit 0
fi

WEEKDAY="${1:-6}"; HOUR="${2:-8}"; MINUTE="${3:-0}"
mkdir -p "${STATE_DIR}/logs" "${PLIST:h}"
chmod +x "$SCRIPT"
if [[ ! -f "${STATE_DIR}/config" ]]; then
  cp "$EXAMPLE" "${STATE_DIR}/config"
  echo "created ${STATE_DIR}/config（AUTO_CLEANUP_REPOS と通知先を編集する）"
fi

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>${SCRIPT}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>DISK_AUTO_CLEANUP_DIR</key>
        <string>${STATE_DIR}</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>${WEEKDAY}</integer>
        <key>Hour</key>
        <integer>${HOUR}</integer>
        <key>Minute</key>
        <integer>${MINUTE}</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>${STATE_DIR}/logs/launchd.out.log</string>
    <key>StandardErrorPath</key>
    <string>${STATE_DIR}/logs/launchd.err.log</string>
</dict>
</plist>
EOF
plutil -lint "$PLIST" >/dev/null
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "installed ${LABEL}: weekday=${WEEKDAY} ${HOUR}:$(printf %02d "$MINUTE") → ${SCRIPT}"
