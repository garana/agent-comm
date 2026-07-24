---
name: agent-comm
description: >
  Message other AI coding agents running in different folders/sessions
  on this same host via the file bus in ~/.agent-bus. Use when the
  user asks to send a message to, coordinate with, listen for, or
  reply to another agent, or mentions the agent bus / agent channels.
  For peers on a different machine use the agent-comm-ssh skill
  instead.
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
`&&`/`||`/`;` chaining. To send, pipe a literal string
(`echo "text" | <skill>/scripts/send <A>-<B>`) or pass a literal file
path; do not use `"$(cat ...)"`.

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

Either pipe the message body via stdin:

    echo "your message" | <skill>/scripts/send <A>-<B>

or pass the path of a file containing the message:

    <skill>/scripts/send <A>-<B> path/to/message.md

For long messages, write the body to a file first and pass its path.
The script prints `sent: <id>` where `<id>` is the message file name.

## Receiving (you are B, peer is A)

1. Watch the channel with:

       <skill>/scripts/watch <A>-<B>

   It tails the channel's `queue.log` and prints one message id per
   line as messages arrive. Run it as a background task that notifies
   you on new output (in Claude Code, start a persistent Monitor on
   it). If your environment cannot watch a stream, poll
   `$HOME/.agent-bus/<A>-<B>/queue.log` for new lines instead.
   Note: on start, watch replays the whole log, so dedup with the
   seen file (step 4) before acting.
   Each newly arriving id is emitted after a random delay of up to
   `AGENT_BUS_JITTER` seconds (default 10, 0 disables) so that agents
   woken by the same message do not hit their APIs simultaneously;
   replayed history is not delayed.

2. For each new id `<id>`, read the message:

       <skill>/scripts/recv <A>-<B> <id>

3. Act on it, then reply on the reverse channel:

       <skill>/scripts/send <B>-<A> reply.md

4. Mark it handled so it is not reprocessed after a restart:

       <skill>/scripts/ack <A>-<B> <id>

On session start, list ids that arrived while no agent was listening:

    <skill>/scripts/pending <A>-<B>

It prints unhandled ids one per line (empty output means none).

## Staying responsive (required)

Once you agree to participate, keep your inbound receiver active for
the entire collaboration: do not start `watch` only around your own
sends, and do not stop listening after the initial replay. Where
persistent background monitors exist (e.g. Claude Code), keep `watch`
running as a long-lived task and handle each new id as it arrives,
deduping via `seen`. Where stream wakeups do not exist (e.g. Codex
CLI, where a foreground `watch` inside a tool call may be terminated
when the call yields), start `watch` detached with its output to a
log file (`nohup ... &`) or skip it, and poll `queue.log` (or the
watch log) at regular points throughout the task - including once
more before declaring your part finished.
