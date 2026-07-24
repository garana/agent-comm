---
name: agent-comm-ssh
description: >
  Message AI coding agents on other hosts through a hub machine's
  agent bus, over ssh. Use when the peer agent runs on a different
  machine, or the user names a hub host. For peers on this same host
  use the agent-comm skill instead.
---

# Cross-host agent communication over ssh

A designated hub host owns the bus (`~/.agent-bus` in the hub user's
home). Agents on other machines run the same channel protocol as the
local agent-comm skill, transported over ssh. The hub needs only sshd
and a POSIX shell - nothing is installed there. Key-based ssh auth to
the hub must already work (`BatchMode=yes` is used; password prompts
fail fast).

Helper scripts [`send`](scripts/send), [`watch`](scripts/watch),
[`recv`](scripts/recv), [`ack`](scripts/ack), and
[`pending`](scripts/pending) (POSIX sh) live in the `scripts/`
directory next to this SKILL.md. Below, `<skill>` stands for that
directory's absolute path (in Claude Code, `${CLAUDE_SKILL_DIR}`).

Always use these scripts for bus operations instead of composing
ad-hoc ssh one-liners: each script is a fixed command prefix, so the
user can grant it permission once instead of being prompted for every
variation, and the ssh invocation stays inside the script.

The hub - `user@hub` or a ~/.ssh/config alias - must reach every
command below. Provide it as the `AGENT_BUS_REMOTE` environment
variable, or per call by prefixing one command (needs no pre-launch
env, and one session can reach several hubs):

    AGENT_BUS_REMOTE=user@hub <skill>/scripts/send <A>-<B>

Also honored:

- `AGENT_BUS_REMOTE_DIR`: absolute bus root on the hub (optional).
- `AGENT_BUS_JITTER`: max random delay in seconds before a new
  message id is emitted by `watch` (default 10, 0 disables). It
  spreads out simultaneously woken agents; keep it enabled in
  collaborations with several agents.

Channels are directories `<sender>-<receiver>/` under the bus root
on the hub (default `$HOME/.agent-bus` there).
Two agents A and B use `<A>-<B>` (A writes, B reads) and `<B>-<A>`.
Agent names are short lowercase slugs agreed with the user; ask if
unknown. Agents on the hub itself use the local agent-comm skill
against the same directories; both kinds mix freely.

## Sending (you are A, peer is B)

Pipe the message body via stdin:

    echo "your message" | <skill>/scripts/send <A>-<B>

or pass the path of a local file containing the message:

    <skill>/scripts/send <A>-<B> path/to/message.md

The script prints `sent: <id>` where `<id>` is the message file name
on the hub.

## Receiving (you are B, peer is A)

1. Watch the channel with:

       <skill>/scripts/watch <A>-<B>

   It emits one message id per line as messages arrive. Run it as a
   background task that notifies you on new output (in Claude Code,
   start a persistent Monitor on it); otherwise poll it. On start it
   replays the whole log, so dedup with the seen file (step 4) before
   acting. If the ssh session drops, `watch` exits: restart it -
   replay plus `seen` make that safe.

2. For each new id `<id>`, read the message from the hub:

       <skill>/scripts/recv <A>-<B> <id>

3. Act on it, then reply on the reverse channel:

       <skill>/scripts/send <B>-<A> reply.md

4. Mark it handled so it is not reprocessed after a restart:

       <skill>/scripts/ack <A>-<B> <id>

On session start, list ids that arrived while nobody was listening:

    <skill>/scripts/pending <A>-<B>

It prints unhandled ids one per line (empty output means none).

## Staying responsive (required)

Once you agree to participate, keep your inbound receiver active for
the entire collaboration: do not start `watch` only around your own
sends, and do not stop listening after the initial replay. Where
persistent background monitors exist, keep `watch` running as a
long-lived task; where they do not, poll it (or the catch-up command
above) at regular points throughout the task - including once more
before declaring your part finished.
