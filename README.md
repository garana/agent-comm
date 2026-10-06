# agent-comm

A tiny file-based message bus that lets AI coding agents - Claude
Code, Antigravity CLI (`agy`), Codex CLI, and any agent supporting
the open SKILL.md standard - running in different folders (or
terminals) on the same host talk to each other, in any mix.

It ships two skills backed by small POSIX sh scripts:

- `agent-comm` - peers on the same host. `scripts/send` appends a
  message to a channel; `scripts/watch` tails a channel so a
  listening agent is woken on (or can poll for) each new message;
  `recv`, `ack`, and `pending` read, acknowledge, and list messages.
- `agent-comm-ssh` - peers on different machines, through a hub host
  that owns the bus (see "Remote peers over SSH" below).

Messages live under `$HOME/.agent-bus/<sender>-<receiver>/` (override
the root with the `AGENT_BUS_DIR` environment variable). Agents must
share that filesystem: same host, or a shared/synced bus directory.

## Install in Claude Code

As a plugin (recommended):

    /plugin marketplace add garana/agent-comm
    /plugin install agent-comm@agent-comm

The skill then triggers automatically when you ask an agent to message
or listen for another agent, or explicitly via `/agent-comm:agent-comm`.

As a personal skill (no plugin), clone the repo and symlink the skill
directory:

    git clone https://github.com/garana/agent-comm ~/src/agent-comm
    ln -s ~/src/agent-comm/skills/agent-comm ~/.claude/skills/agent-comm

Or symlink into a project's `.claude/skills/` to scope it to one repo.

## Install in Antigravity CLI (agy)

This repo ships `.agents/skills.json`, so the skill is discovered
automatically when working in this workspace. For global use, symlink
it into the global config:

    ln -s <repo>/skills/agent-comm ~/.gemini/config/skills/agent-comm

To avoid repeated permission prompts, add `write_file(~/.agent-bus)`
(which implicitly grants read access) to the `"allow"` array in
`~/.gemini/antigravity-cli/settings.json`.

## Install in Codex CLI

Codex discovers repo skills from `.agents/skills`, and this repo
ships the `.agents/skills/agent-comm` symlink, so the skill loads
automatically when working in this workspace. To install it globally
instead, run from a clone of this repo:

    mkdir -p "$HOME/.agents/skills"
    ln -s "$(pwd)/skills/agent-comm" "$HOME/.agents/skills/agent-comm"

`codex plugin add` installs are supported via
`.codex-plugin/plugin.json` and `.agents/plugins/marketplace.json`.

The bus lives in `$HOME/.agent-bus`, which Codex's workspace-write
sandbox cannot write by default. Either launch each session with

    codex --add-dir "$HOME/.agent-bus"

(the shell expands `$HOME` before Codex starts), or add a permanent
entry to the user-level `~/.codex/config.toml` - substituting your
own absolute home directory path, since config.toml does not expand
`$HOME`:

    [sandbox_workspace_write]
    writable_roots = ["<absolute-home-path>/.agent-bus"]

Either way this grants only the bus directory, not all of `$HOME`.

Codex also has no equivalent of Claude Code's Monitor wakeups, and a
foreground `watch` started through Codex command execution may be
terminated or detached when the tool call yields - do not treat it as
a persistent monitor. For a truly long-lived local watcher, start it
detached (choosing your own durable log location if needed):

    nohup <repo>/skills/agent-comm/scripts/watch <peer>-<self> \
        > /private/tmp/agent-comm-watch.log 2>&1 &

Even then, Codex cannot automatically wake the chat on that log's
output: the agent must periodically poll `queue.log` (or the watch
log) throughout the task, especially before completing it. Use
`AGENT_BUS_DIR` only for deliberate shared or network filesystem
deployments.

## Install in other agents

The skill follows the open SKILL.md standard, so any agent supporting
Agent Skills can load it: point the agent's skills directory at
`skills/agent-comm` (e.g. Kimi CLI's `--skills-dir`).

## Remote peers over SSH (agent-comm-ssh)

The `agent-comm-ssh` skill lets agents on different machines use a bus
that lives on one box - that pair's hub. The remote agent runs the
protocol over ssh to the hub. A hub needs only sshd and a POSIX shell
- nothing is installed there; an agent on the hub itself keeps using
plain `agent-comm` against the same directories.

Buses are per pair. Different pairs can use different hubs, and not
every box needs ssh to every other. There is no single hub, so the
skill has the agent record each pair's hub (which box, and the ssh
user@host to reach it) in memory and never guess it.

Requirements and configuration on each remote agent's machine:

- Key-based ssh access to the hub (`BatchMode=yes` is used, so a
  password prompt fails fast instead of hanging the agent).
- `AGENT_BUS_REMOTE=user@hub` (required).
- `AGENT_BUS_REMOTE_DIR` - absolute bus root on the hub (optional;
  default is the hub user's `$HOME/.agent-bus`).

Usage mirrors the local skill (write the message with your file tool,
then pass its path):

    skills/agent-comm-ssh/scripts/send web-api /tmp/web-api/msg.md
    skills/agent-comm-ssh/scripts/watch api-web

If the ssh session behind `watch` drops, the script exits; restarting
it is safe (replay plus the `seen` file deduplicate).

Instead of setting `AGENT_BUS_REMOTE` before launch, the hub can be
chosen per call by prefixing the command - this needs no pre-launch
env and lets one session reach several hubs:

    AGENT_BUS_REMOTE=user@hub \
        skills/agent-comm-ssh/scripts/send web-api

In Claude Code a leading `VAR=value` is only stripped for a few
known-safe variables, so a `Bash(.../send *)` allow rule does not
cover this prefixed form; add a `Bash(AGENT_BUS_REMOTE=* .../send *)`
rule per script to keep it prompt-free (see Permissions).

Recommended ssh options for the hub host in `~/.ssh/config` on each
agent machine: keep-alives, so NAT/firewall idle timeouts do not
silently kill a quiet `watch` session (a dead connection then makes
`watch` exit promptly instead of hanging), and connection
multiplexing, so the frequent short commands (`send`, `recv`, `ack`,
`pending`) reuse one authenticated connection instead of paying the
handshake each time:

    Host hub-host
        ServerAliveInterval 30
        ServerAliveCountMax 3
        ControlMaster auto
        ControlPath ~/.ssh/cm-%r@%h:%p
        ControlPersist 10m

## Wake-up jitter

When one message wakes several agents at once, they tend to hit
their LLM APIs in the same instant and get rate limited. Both watch
scripts therefore delay each newly arriving id by a random 0 to
`AGENT_BUS_JITTER` seconds (default 10) before emitting it; the
delay is drawn from `/dev/urandom` on the receiving host, so it
needs no coordination between agents or hosts. Replayed history is
never delayed. Set `AGENT_BUS_JITTER=0` to disable, or raise it for
large fan-outs.

## Permissions

Agents drive the bus exclusively through each skill's five scripts
(`send`, `watch`, `recv`, `ack`, `pending`); the ssh invocations of
`agent-comm-ssh` stay inside the scripts. Every bus operation is
therefore one of a handful of fixed command prefixes, which agent
harnesses can be allowed to run once - in Claude Code, answer the
first prompt for each script with "always allow", or add rules like:

    "permissions": {
      "allow": [
        "Bash(<install-path>/skills/agent-comm/scripts/send *)",
        "Bash(<install-path>/skills/agent-comm/scripts/watch *)",
        "Bash(<install-path>/skills/agent-comm/scripts/recv *)",
        "Bash(<install-path>/skills/agent-comm/scripts/ack *)",
        "Bash(<install-path>/skills/agent-comm/scripts/pending *)"
      ]
    }

(and the same five under `skills/agent-comm-ssh/` when using the ssh
skill). If an agent asks to run a raw `ssh`/`cat`/`echo` one-liner
against the bus, that is a bug: point it at the scripts.

If you target the hub per call with an `AGENT_BUS_REMOTE=...` prefix
instead of a preset env var, that plain rule will not match it -
Claude Code only strips a leading assignment for known-safe
variables. Add a prefixed rule per script, e.g.
`Bash(AGENT_BUS_REMOTE=* <install-path>/agent-comm-ssh/scripts/send *)`.

For the same reason the scripts must be called by their literal
absolute path with literal arguments: a `${CLAUDE_SKILL_DIR}`, `$VAR`,
`~`, or `$(...)` in the command is not statically matchable, so it
re-prompts every call (an unresolved variable path also just fails).
Both skills instruct agents to keep the command literal.

### Sending without per-message prompts

Agents stage each outgoing message as a file - written with their
file tool (in Claude Code, the Write tool) - and pass its path to
`send`, instead of piping `echo`/`printf`. The file goes in a
git-ignored project folder if there is one, else `/tmp/<from>-<to>/`.
To let an agent send on its own, grant its file tool write access to
that folder and allow the send script; both are one-time grants:

    "permissions": {
      "allow": [
        "Write(/tmp/**)",
        "Bash(<install-path>/skills/agent-comm/scripts/send *)"
      ]
    }

For the ssh skill also add the `AGENT_BUS_REMOTE=*` send rule shown
above, since the hub is passed as a command prefix.

### Enforcing script-only access

SKILL.md instructions are dropped when a session is compacted, and
agents then tend to improvise raw shell against the bus. To enforce
the rule regardless of context, the repo ships a `PreToolUse` hook
(`hooks/bus-guard.sh`, wired by `hooks/hooks.json`) that denies any
Bash command naming the bus internals (`.agent-bus`, `inbox/`,
`queue.log`) and tells the agent to use the scripts instead. The
harness runs it on every call, so compaction cannot defeat it.

`PreToolUse` hooks are a Claude Code mechanism, so this enforcement
covers Claude Code agents only. Other agents (Codex, agy, Kimi, ...)
still read the SKILL.md instructions and the script-only clause in the
skill description, but for a hard guard they would need their own
equivalent; the hook file is simply ignored by them and breaks
nothing.

Installed as a plugin, the hook is active automatically. With the
symlink install (plugin disabled) add it to `~/.claude/settings.json`:

    "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [
      { "type": "command",
        "command": "<repo>/hooks/bus-guard.sh", "timeout": 5 } ] } ] }

It is a broad text match, so a command that merely mentions those
tokens (`grep queue.log ...`) is denied too; narrow it with the hook
`if` field or soften `deny` to `ask` in the script if that gets in
your way.

## Running it

Open two agent sessions in different folders - both from the same
CLI, or any mix of the platforms above. The prompt for each agent
must tell it three things: use the skill, its own name, and its
peer's name. A reusable template:

    Use the agent-comm skill.
    You are "<your-name>"; your peer is "<peer-name>".
    Listen for messages from "<peer-name>", act on them, and reply.
    <the task this agent is responsible for>

The listening instruction matters even for an agent that mostly asks:
replies arrive on its inbound channel, and the skill requires the
receiver to stay active for the whole collaboration.

For example, with agents named `api` and `web`:

In the first session (folder 1):

    Use the agent-comm skill. You are "api". Listen for messages from
    "web" and answer questions about this codebase.

The agent watches channel `web-api` (in Claude Code, via a Monitor on
the `watch` script, started with `persistent: true` so it has no
timeout; elsewhere, a background task or polling) and wakes whenever a
message arrives.

In the second session (folder 2):

    Use the agent-comm skill. You are "web". Ask "api" which endpoints
    exist for user management, and wait for the reply.

The second agent sends on channel `web-api`, listens on `api-web`, and
reports the answer back to you. Any number of agents can participate;
each ordered pair of names is its own channel.

One rule is required for the bus to work: an agent that joins a
collaboration keeps its inbound receiver active until the
collaboration ends - listening is continuous, not something done only
around its own sends. See "Staying responsive" in the skill.

## Running it across machines

When the two agents are on different machines, one of them - or a
third box both can reach - is the hub that owns the bus (see "Remote
peers over SSH" above). Point each remote agent at the hub - via
`AGENT_BUS_REMOTE` in its environment, or a per-call command prefix -
then prompt each agent to use the `agent-comm-ssh` skill instead of
`agent-comm`. The naming, channels,
and listening rule are identical; only the transport differs. An
agent that runs on the hub itself keeps using plain `agent-comm`.

The reusable template becomes:

    Use the agent-comm-ssh skill.
    You are "<your-name>"; your peer is "<peer-name>".
    Listen for messages from "<peer-name>", act on them, and reply.
    <the task this agent is responsible for>

For example, with `api` on the hub host and `web` on a laptop:

On the hub host (agent `api`), plain local skill:

    Use the agent-comm skill. You are "api". Listen for messages from
    "web" and answer questions about this codebase.

On the laptop (agent `web`), after `export AGENT_BUS_REMOTE=user@hub`:

    Use the agent-comm-ssh skill. You are "web". Ask "api" which
    endpoints exist for user management, and wait for the reply.

Both drive the same channels (`web-api`, `api-web`) on the hub, so
`api` reads and replies locally while `web` sends and listens over
ssh. If both agents are remote, prompt both with `agent-comm-ssh`.

## How it works

Each ordered pair of agents gets its own channel directory. For agents
A and B:

| Channel   | Writer | Reader |
| --------- | ------ | ------ |
| `<A>-<B>` | A      | B      |
| `<B>-<A>` | B      | A      |

Sending writes the message to `tmp/`, moves it atomically into
`inbox/`, and appends its id to `queue.log`. Receivers tail
`queue.log`, read `inbox/<id>`, and append handled ids to `seen` so
restarts do not reprocess old messages.

Try it from a shell:

    echo "hello" | skills/agent-comm/scripts/send demo-a
    skills/agent-comm/scripts/watch demo-a   # prints ids as they arrive
    cat ~/.agent-bus/demo-a/inbox/*

The full agent-facing protocol is in `skills/agent-comm/SKILL.md`.
