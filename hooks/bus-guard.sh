#!/bin/sh
# PreToolUse (Bash) guard for the agent-comm bus.
#
# Blocks raw access to the bus files and redirects the agent to the
# skill scripts (send/watch/recv/ack/pending). The harness runs this
# on every Bash call, so it keeps working after context compaction has
# dropped the SKILL.md instructions from the agent's memory.
#
# It reads the PreToolUse JSON on stdin and denies when the command
# names bus internals. A legitimate script invocation is just the
# script path plus a channel/id, so it never names those paths and
# passes through untouched.
set -e

payload=$(cat)

# .agent-bus: the default bus dir; queue.log and /inbox/: the internal
# files, which also catch a relocated bus (AGENT_BUS_DIR / a remote
# hub dir) since raw reads/writes still go through inbox and queue.log.
if printf '%s' "$payload" |
   grep -Eq '\.agent-bus|queue\.log|/inbox/'; then
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Do not touch the agent bus files directly (no raw cat/echo/tail/ssh on .agent-bus, inbox/, queue.log, or seen): it breaks atomic delivery, dedup, and wake-up jitter. Use the skill scripts instead - send, watch, recv, ack, pending under the agent-comm (or agent-comm-ssh) skill's scripts/ dir - and re-read that SKILL.md for exact usage."}}
JSON
fi
