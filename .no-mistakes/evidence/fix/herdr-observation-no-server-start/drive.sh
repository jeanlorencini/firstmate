#!/usr/bin/env bash
# drive.sh <code-root> <label> : run observation entrypoints against a stopped/absent herdr lab session
set -u
CODE=$1; LABEL=$2; S=$3; SES=$4
LAB=$(mktemp -d "$S/lab-$LABEL.XXXXXX")
"$CODE/bin/fm-lab-home.sh" create "$LAB" >/dev/null
mkdir -p "$LAB/wt"; git -C "$LAB/wt" init -q -b fm/obs-probe
# window must be session:pane form
printf 'window=%s:w1:p1\nworktree=%s\nkind=ship\nbackend=herdr\nharness=claude\n' "$SES" "$LAB/wt" > "$LAB/state/obs-probe.meta"
LOG="$S/herdr-calls-$LABEL.log"; : > "$LOG"
export HERDR_GUARD_LOG=$LOG
RUN() { env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u HERDR_SESSION -u HERDR_PANE_ID -u HERDR_ENV -u TMUX \
  FM_HOME="$LAB" PATH="$S/shim:/usr/local/bin:/usr/bin:/bin" HERDR_GUARD_LOG="$LOG" timeout 60 "$@"; }
step() { printf '\n=== %s ===\n' "$1"; printf '\n# STEP %s\n' "$1" >> "$LOG"; }
echo "## code=$CODE session=$SES"
step "real herdr session list (before)"
/home/zerojour/.local/bin/herdr session list --json | jq -c '[.sessions[]|{name,running}]'
step "fm_backend_herdr_capture $SES:w1:p1 40"
RUN bash -c '. "$0/bin/backends/herdr.sh"; fm_backend_herdr_capture "$1" 40; echo "exit=$?"' "$CODE" "$SES:w1:p1" 2>&1 | tail -3
step "fm_backend_herdr_busy_state $SES:w1:p1"
RUN bash -c '. "$0/bin/backends/herdr.sh"; printf "busy_state=%s\n" "$(fm_backend_herdr_busy_state "$1")"' "$CODE" "$SES:w1:p1" 2>&1 | tail -3
step "bin/fm-fleet-snapshot.sh --json (task row)"
RUN "$CODE/bin/fm-fleet-snapshot.sh" --json 2>&1 | jq -c '.tasks[]? | {id, backend, target: .endpoint.target, current_state: (.current_state|{state,source,detail}?), capture: (.endpoint.capture // .capture // null)}' 2>&1 | head -5
step "bin/fm-bearings-snapshot.sh"
RUN "$CODE/bin/fm-bearings-snapshot.sh" >/dev/null 2>&1; echo "exit=$?"
step "bin/fm-crew-state.sh obs-probe"
RUN "$CODE/bin/fm-crew-state.sh" obs-probe 2>&1 | head -6
step "bin/fm-peek.sh obs-probe"
RUN "$CODE/bin/fm-peek.sh" obs-probe 2>&1 | head -6; echo "exit=${PIPESTATUS[0]}"
step "pane-acting control: fm_backend_herdr_send_key $SES:w1:p1 Escape"
RUN bash -c '. "$0/bin/backends/herdr.sh"; fm_backend_herdr_send_key "$1" Escape; echo "exit=$?"' "$CODE" "$SES:w1:p1" 2>&1 | tail -2
step "real herdr session list (after)"
/home/zerojour/.local/bin/herdr session list --json | jq -c '[.sessions[]|{name,running}]'
echo; echo "--- server-start attempts recorded by guard shim ---"
awk '/^# STEP/{s=$0} /^server|^BLOCKED/{print s " -> " $0}' "$LOG"
echo "--- herdr calls per step ---"
awk '/^# STEP/{s=$0; next} NF{c[s]++} END{for(k in c) print c[k], k}' "$LOG" | sort -k3
rm -rf "$LAB"
