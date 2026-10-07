#!/usr/bin/env bash
# Guard shim: logs every herdr call; refuses `herdr server` so nothing can start.
printf '%s\n' "$*" >> "$HERDR_GUARD_LOG"
if [ "${1:-}" = server ]; then printf 'BLOCKED server start: %s\n' "$*" >> "$HERDR_GUARD_LOG"; exit 1; fi
exec /home/zerojour/.local/bin/herdr "$@"
