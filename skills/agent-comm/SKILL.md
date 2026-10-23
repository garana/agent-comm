---
name: agent-comm
description: >
  Message other AI coding agents running in different folders/sessions
  on this same host via the file bus in ~/.agent-bus. Use when the
  user asks to send a message to, coordinate with, listen for, or
  reply to another agent, or mentions the agent bus / agent channels.
  Operate the bus only through this skill's send/watch/recv/ack/pending
  scripts, never raw cat/echo/ssh on the bus files. Write each message
  to a file with your file tool and pass its path; do not pipe
  echo/printf. For peers on a different machine use the agent-comm-ssh
  skill instead.
---

# Cross-agent communication bus

Helper scripts [`send`](scripts/send), [`watch`](scripts/watch),
[`recv`](scripts/recv), [`ack`](scripts/ack), and
[`pending`](scripts/pending) (POSIX sh) live in the `scripts/`
directory next to this SKILL.md. Below, `<skill>` stands for that
skill directory. In every command replace `<skill>` with the literal
absolute path this skill was loaded from - do not type
`${CLAUDE_SKILL_DIR}`, a `$VAR`, or `~` on the command line: an
unresolved path fails in the shell, and expansion stops a one-time
permission grant from matching later calls.

Always use these scripts for bus operations instead of composing
ad-hoc shell (raw cat/echo/ssh one-liners): each script is a fixed
command prefix, so the user can grant it permission once instead of
being prompted for every variation. For that grant to keep matching,
keep the whole command literal: literal path and literal channel/id
arguments, no command substitution (`$(...)` or backticks), and no
`&&`/`||`/`;` chaining. To send, pass a literal file path (see
Sending); do not use `echo`/`printf` pipes or `"$(cat ...)"`.

A channel is a directory `$HOME/.agent-bus/<sender>-<receiver>/`. Two
agents A and B use a pair of channels:

- `<A>-<B>`: A writes, B reads.
- `<B>-<A>`: B writes, A reads.

Agent names are short lowercase slugs agreed with the user (e.g. the
project folder name). Ask the user for this agent's name and the peer's
name if not already known. Agents must share a filesystem (same host or
a shared/synced `$HOME/.agent-bus`); set `AGENT_BUS_DIR` to relocate
the bus root. Sandboxed agents that cannot write to `$HOME` (e.g. the
Codex CLI workspace sandbox) should whitelist `$HOME/.agent-bus` in
their sandbox or permission config rather than relocate the bus; the
README has per-agent snippets.

## Sending (you are A, peer is B)

Write the message body to a file with your file tool (in Claude Code,
the Write tool). Do not pipe `echo` or `printf` into the script. Put
the file in a git-ignored folder in the project if there is one, else
create and use `/tmp/<A>-<B>/`. Then pass its path:

    <skill>/scripts/send <A>-<B> /tmp/<A>-<B>/msg.md

Staging files this way lets the operator grant your file tool write
access to that folder and the send script once, so sends need no
per-message approval. The script prints `sent: <id>`.

## Receiving (you are B, peer is A)

1. Watch for messages. For one peer, watch that channel; to hear
   from every peer at once, use watch-all (see "Listen for all
   peers"):

       <skill>/scripts/watch <A>-<B>

   It tails the channel's `queue.log` and prints one message id per
   line as messages arrive. Run it as a background task that notifies
   you on new output (in Claude Code, run it under a Monitor; see
   "Staying responsive" for the timeout). If your environment
   cannot watch a stream, poll
   `$HOME/.agent-bus/<A>-<B>/queue.log` for new lines instead.
   Note: watch skips ids you have acked (those in the seen file),
   both on start and while running, so a restart replays only the
   unacked backlog. Still ack each id in step 4.
   Each newly arriving id is emitted after a random delay of up to
   `AGENT_BUS_JITTER` seconds (default 10, 0 disables) so that agents
   woken by the same message do not hit their APIs simultaneously;
   replayed history is not delayed.

2. For each new id `<id>`, read the message:

       <skill>/scripts/recv <A>-<B> <id>

3. Act on it, then reply on the reverse channel, the same way as
   Sending above (write the reply with your file tool, then send its
   path):

       <skill>/scripts/send <B>-<A> /tmp/<B>-<A>/reply.md

4. Mark it handled so it is not reprocessed after a restart:

       <skill>/scripts/ack <A>-<B> <id>

On session start, list ids that arrived while no agent was listening:

    <skill>/scripts/pending <A>-<B>

It prints unhandled ids one per line (empty output means none).

## Listen for all peers (watch-all)

`watch` follows one channel. When more than one peer may message you,
or a new peer can appear mid-session, listen on all your inbound
channels at once:

    <skill>/scripts/watch-all <ourname>

`<ourname>` is this agent's name. Each sweep it finds every channel
named `<sender>-<ourname>` (the ones where you are the receiver),
new peers included, so you never restart it to add a peer. It prints
one unacked message per line as `<channel> <id>`; read and ack each
with that channel:

    <skill>/scripts/recv <channel> <id>
    <skill>/scripts/ack  <channel> <id>

It skips acked ids (the `seen` file) and emits each id once per run; a
restart replays the unacked backlog once. The first sweep is emitted
at once; later ids carry the same `AGENT_BUS_JITTER` delay as `watch`.
`AGENT_BUS_POLL` sets the seconds between sweeps (default 2).

## Staying responsive (required)

Once you agree to participate, keep your inbound receiver active for
the entire collaboration: do not start it only around your own sends,
and do not stop listening after the initial replay. Where persistent
background monitors exist (e.g. Claude Code), keep a listener running
as a long-lived task and handle each new id as it arrives, deduping
via `seen`; prefer `watch-all <ourname>` so a new peer needs no
restart. In Claude Code a Monitor cannot run without a timeout; it is
killed at its deadline (30 minutes maximum, 5 by default), so start it
with the longest `timeout_ms` (1800000) and re-arm it each time it
expires. (There is no no-timeout option; a `persistent` flag once
existed but was removed and is now rejected.) Stop it with TaskStop
when the collaboration ends. Where stream wakeups do not exist (e.g.
Codex CLI, where a foreground listener inside a tool call may be
terminated when the call yields), start it detached with its output
to a log file (`nohup ... &`) or skip it, and poll `queue.log` (or
the log) at regular points throughout the task, including once more
before declaring your part finished.
