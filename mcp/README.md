# overmind-mcp — the team engine over MCP

The ai-overmind plugin runs the full system inside Claude Code: hooks, TARS, skills. `overmind-mcp`
gives every other MCP client a way into the same team. It is one compiled program per platform.
It needs no Python or Node, reads your team folder on your own disk, and sends nothing anywhere.

**Status: Phase 1, read-only.** It can boot a seat and read shared state. It cannot write yet.

## What it serves

| Tool | Does |
|---|---|
| `boot(seat)` | The seat's `BOOT.md` with every `@` import inlined, then a runtime note on what this client cannot do, then the `Engine:` line. |
| `roster()` | Every seat: name, role, folder. |
| `board(seat?, all?)` | Active rows of `MISSION_BOARD.md`, optionally only one seat's. |
| `handoff(seat)` | The seat's staged `HANDOFF.md`: the newer of the folder-root copy and the legacy `.auto-memory` copy, with WRITTEN and ACTIVATED stamps. The other copy is reported. |
| `inbox(seat, unread_only?)` | `INBOX.md` entries. An entry is read only when its header's last segment is `READ`; untagged counts as unread. |
| `firmware(section?)` | The firmware this binary was built with: the topic index, or one topic. |

It also serves each seat's boot as a resource, `overmind://seat/<seat>/boot`, and as a `boot`
prompt, for clients that surface those.

A seat is any top-level folder in the team root that holds a `BOOT.md` and doesn't start with `_`.
Its name is the `**X**` in the BOOT.md line `You are **X**`, else the folder name before ` - `, else
the folder name. Two seats with the same short name are an error that names both folders; use the
full folder name. Seat names from a caller are matched against that list and nothing else, so no
caller-supplied path ever reaches the file system.

## Read rules

- **Containment.** Every path is resolved through symlinks and Windows junctions before it is read,
  and anything that resolves outside the team root is refused. That covers seat folders, the files
  in them and every import.
- **Imports.** Only `.md` files inside the team root load. Each file is inlined once, so a file that
  imports itself, or a cycle, stops at the second visit. Nesting stops at 5 levels.
- **Caps.** One file read is capped at 1 MiB and one boot or tool result at 2 MiB. Anything cut ends
  in `[truncated by overmind-mcp]`.
- **No host paths.** Text the server writes itself shows the team root as `<team-root>`. File
  content passes through as written.
- **Board.** The Status cell is split on `/`, `,`, `;` and spaces, and a row is COMPLETE only when
  every part is. A seat matches an Owner or Assignee name exactly (ignoring case), never as part of
  a longer name.
- **Handoffs.** `WRITTEN` is read from the first 40 lines, mid-line or in bold, as `YYYY-MM-DD` with
  an optional `HH:MM` and an optional `Z` or `+HH:MM` (local time when no zone is given). Copies
  are compared by time. A value that doesn't parse falls back to the file's modification time.

## Firmware identity

The last line of every boot is

    Engine: overmind-mcp <version>, firmware sha256 <12 hex>.

The hash covers `hooks/kernel.md` and then `reference/*.md`, as the plugin ships them. Pass
`--plugin-root <installed plugin folder>` (or set `OVERMIND_PLUGIN_ROOT`) and the server hashes the
installed plugin's firmware on every boot. When the two differ, a `WARNING:` line comes directly
before the Engine line: rebuild or update overmind-mcp. `/diagnostic` compares the same hash.

## Setup

1. Download the binary for your platform from the release, or build it: `bash mcp/build.sh`
   (needs Go; writes `mcp/dist/`).
2. Put it somewhere stable, for example `~/.overmind/bin/`.
   On macOS, a downloaded binary is quarantined; clear it once with
   `xattr -d com.apple.quarantine ~/.overmind/bin/overmind-mcp-darwin-arm64`.
3. Add it to your MCP client. For the Claude desktop app, `claude_desktop_config.json`:

   ```json
   {
     "mcpServers": {
       "overmind": {
         "command": "C:\\Users\\you\\.overmind\\bin\\overmind-mcp-windows-amd64.exe",
         "args": ["--root", "C:\\Users\\you\\Documents\\AI Team",
                  "--plugin-root", "C:\\path\\to\\installed\\ai-overmind"]
       }
     }
   }
   ```

   Restart the client fully so it loads the server.
4. In the project or conversation that belongs to a seat, one line of instructions is enough:
   `You are the seat T-Bot. Call the overmind boot tool before replying.`

`--seat NAME` (or `OVERMIND_SEAT`) makes a seat the default and tells the model to boot as it in
every conversation. Use it only in a client, or a client profile, that is dedicated to that seat.

## The honest ceiling

MCP is passive. The server answers when it is called and never speaks first. Outside Claude Code:

- **No TARS.** No turn checkpoints, no inbox or delivery alerts. A seat booted this way declares
  `TARS: UNAVAILABLE (MCP client - no hooks)`.
- **Nothing is injected before the first message.** The boot arrives because the model calls
  `boot`, prompted by the server's instructions and the one line above. A client that ignores
  server instructions needs that line.
- **No writes yet.** Gopher registration, ledger rows and marking inbox entries READ need Phase 2.
  A seat names the steps it skipped rather than pretending they ran.

What it does fix: no more pasting boot layers, and no re-paste after a BOOT.md edit. Every client
reads the current file.

## Roadmap

1. **Read-only core** (this).
2. **Write tools with enforcement:** board status and notes, the /go handoff stamp, inbox READ,
   Gopher rows. Rules enforced in code, not recalled.
3. **Plugin integration:** release binaries built in CI, and a `/link` skill that installs the
   binary and writes each client's config.
4. **Hosted, bring-your-own-storage:** the same server over HTTP, reading your own private GitHub
   repo. Only if phone access proves worth it. Nobody's data is stored on a server we run.
