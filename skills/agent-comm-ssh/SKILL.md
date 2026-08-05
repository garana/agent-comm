---
name: agent-comm-ssh
description: >
  Message AI coding agents on other hosts through a hub machine's
  agent bus, over ssh. Use when the peer agent runs on a different
  machine, or the user names a hub host. Operate the bus only through
  this skill's send/watch/recv/ack/pending scripts, never raw ssh on
  the bus files. Each pair's bus may live on a different box; recall
  its hub from memory and never guess. Write each message to a file
  with your file tool and pass its path; do not pipe echo/printf. For
  peers on this same host use the agent-comm skill instead.
---

# Cross-host agent communication over ssh

Each channel pair keeps its files on one box - that pair's hub. The
remote agent runs the same channel protocol as the local agent-comm
skill, over ssh to that hub. A hub needs only sshd and a POSIX shell -
nothing is installed there. Key-based ssh auth to the hub must already
work (`BatchMode=yes` is used; password prompts fail fast).

Different pairs can use different hubs, and not every box can ssh to
every other. There is no single "the hub". Never assume this box is
the hub or guess where a pair's bus runs - see "Know each pair's hub"
below.

Helper scripts [`send`](scripts/send), [`watch`](scripts/watch),
[`recv`](scripts/recv), [`ack`](scripts/ack), and
[`pending`](scripts/pending) (POSIX sh) live in the `scripts/`
directory next to this SKILL.md. Below, `<skill>` stands for that
directory's absolute path; in every command use that literal path,
not `${CLAUDE_SKILL_DIR}`, a `$VAR`, or `~` - an unresolved path
fails in the shell, and expansion stops a one-time permission grant
from matching later calls.

Always use these scripts for bus operations instead of composing
ad-hoc ssh one-liners: each script is a fixed command prefix, so the
user can grant it permission once instead of being prompted for every
variation, and the ssh invocation stays inside the script. For that
grant to keep matching, keep the whole command literal: literal path
and literal channel/id arguments (and a literal value if you use the
`AGENT_BUS_REMOTE=...` prefix), no command substitution (`$(...)` or
backticks), and no `&&`/`||`/`;` chaining. To send, pass a literal
file path (see Sending); do not use `echo`/`printf` pipes or
`"$(cat ...)"`.

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

## Know each pair's hub (do not guess)

For each pair you use, you need two facts: which box runs that pair's
bus, and the ssh `user@host` to reach it from here (or `local` if
this box runs it - then use the agent-comm skill, no ssh).

When you first set up a pair and confirm the bus works, save these to
your memory, keyed by the channel: the channel name, the box that
runs the bus, and the ssh `user@host` to reach it from here. In
Claude Code, write a memory entry. Before you send or watch a pair,
recall these and use them. If they are not saved, ask the user - do
not guess - then verify the bus works and save them.

## Sending (you are A, peer is B)

Write the message body to a file with your file tool (in Claude Code,
the Write tool). Do not pipe `echo` or `printf` into the script. Put
the file in a git-ignored folder in the project if there is one, else
create and use `/tmp/<A>-<B>/`. Then pass its path, with the hub you
saved in memory:

    AGENT_BUS_REMOTE=user@host <skill>/scripts/send <A>-<B> \
        /tmp/<A>-<B>/msg.md

Set `AGENT_BUS_REMOTE` in the environment instead if all your pairs
share one hub. The script prints `sent: <id>`.

Staging files this way lets the operator grant your file tool write
access to that folder and the send script once, so sends need no
per-message approval.

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

3. Act on it, then reply on the reverse channel, the same way as
   Sending above (write the reply with your file tool, then send its
   path):

       AGENT_BUS_REMOTE=user@host <skill>/scripts/send <B>-<A> \
           /tmp/<B>-<A>/reply.md

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
