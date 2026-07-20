# claude-comm

A tiny file-based message bus that lets Claude Code agents running in
different folders (or terminals) on the same host talk to each other.

It ships as a Claude Code plugin containing one skill, `agent-comm`,
plus the two POSIX sh scripts it drives:

- `skills/agent-comm/scripts/send` - append a message to a channel.
- `skills/agent-comm/scripts/watch` - tail a channel (used with Claude
  Code's Monitor tool so the agent wakes on each new message).

Messages live under `$HOME/.agent-bus/<sender>-<receiver>/` (override
the root with the `AGENT_BUS_DIR` environment variable). Agents must
share that filesystem: same host, or a shared/synced bus directory.

## Install as a plugin (recommended)

Inside Claude Code:

    /plugin marketplace add garana/claude-comm
    /plugin install claude-comm@claude-comm

The skill then triggers automatically when you ask an agent to message
or listen for another agent, or explicitly via `/claude-comm:agent-comm`.

## Install as a personal skill (no plugin)

Clone the repo and symlink the skill directory:

    git clone https://github.com/garana/claude-comm ~/src/claude-comm
    ln -s ~/src/claude-comm/skills/agent-comm ~/.claude/skills/agent-comm

Or symlink into a project's `.claude/skills/` to scope it to one repo.

## Install in other agents

The skill follows the open SKILL.md standard, so any agent supporting
Agent Skills can load `skills/agent-comm/`.

Antigravity CLI (`agy`): this repo ships `.agents/skills.json`, so the
skill is discovered automatically when working in this workspace. For
global use, symlink it into the global config:

    ln -s <repo>/skills/agent-comm ~/.gemini/config/skills/agent-comm

To avoid repeated permission prompts, add `write_file(~/.agent-bus)`
(which implicitly grants read access) to the `"allow"` array in
`~/.gemini/antigravity-cli/settings.json`.

Codex CLI: the repo ships a `.agents/skills/agent-comm` symlink for
workspace auto-discovery, plus `.codex-plugin/plugin.json` and
`.agents/plugins/marketplace.json` for `codex plugin add`. Codex's
workspace sandbox cannot write `~/.agent-bus` by default, so create
the bus directory once and whitelist exactly it in the user-level
`~/.codex/config.toml` (works from every repo):

    mkdir -p ~/.agent-bus

    [sandbox_workspace_write]
    writable_roots = ["/Users/you/.agent-bus"]

Replace `/Users/you` with your home directory (the setting takes
absolute paths). This grants only the bus directory - not all of
`$HOME` - keeps messages across reboots, and avoids per-message
approval prompts. Receive by polling `queue.log` or a `watch`
session. Use `AGENT_BUS_DIR` only for deliberate shared or network
filesystem deployments.

Other agents: point their skills directory at `skills/agent-comm`
(e.g. Kimi CLI's `--skills-dir`).

## Running it

Open two Claude Code sessions in different folders and give each agent
a name and a peer. For example, with agents named `api` and `web`:

In the first session (folder 1):

    Use the agent-comm skill. You are "api". Listen for messages from
    "web" and answer questions about this codebase.

The agent starts a Monitor on `watch web-api` and wakes whenever a
message arrives.

In the second session (folder 2):

    Use the agent-comm skill. You are "web". Ask "api" which endpoints
    exist for user management, and wait for the reply.

The second agent sends on channel `web-api`, listens on `api-web`, and
reports the answer back to you. Any number of agents can participate;
each ordered pair of names is its own channel.

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
