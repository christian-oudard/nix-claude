# nix-claude -- Specification

Declarative configuration for Claude Code via Nix.

## Overview

A Nix library (`mkClaudeConfig`) and home-manager module (`programs.claude-code`) that assembles a complete Claude Code configuration from declarative inputs.

nix-claude manages configuration and extensions. It does not package the Claude Code binary or MCP server binaries.

## What nix-claude manages

- Skills (directory-based, each containing SKILL.md)
- Commands (flat markdown files)
- CLAUDE.md (persistent instructions, composed from fragments)
- MCP server configuration (merged into `~/.claude.json`)
- Settings (written to `~/.claude/settings.json`)

## Architecture

Two interfaces to the same core logic:

```
                        nix-claude
                       /          \
          home-manager module    lib.mkClaudeConfig
                 |                      |
           home activation         derivation output
                 |                      |
         ~/.claude/ (copied)     /nix/store/...-claude-config/
```

### `lib.mkClaudeConfig`

Pure function producing a derivation. Does not touch `~/.claude/`. Consumers decide how to install.

```nix
nix-claude.lib.mkClaudeConfig {
  inherit pkgs;

  skills = [
    persist.skills.persist
    persist.skills.persist-status
    ./my-local-skill              # directory containing SKILL.md
  ];

  commands = [
    ./commands/quick-review.md    # flat markdown file
  ];

  memory.fragments = [
    ./base-claude.md
    "Inline instruction string."
  ];

  mcpServers = {
    github = {
      command = "${github-mcp-server}/bin/github-mcp-server";
      args = [ "stdio" ];
    };
  };

  settings = {
    permissions.allow = [ "Bash" "Read" "Write" ];
    hooks.Stop = [{
      matcher = "";
      hooks = [{ type = "command"; command = "${persistPkg}/bin/persist hook"; }];
    }];
  };
}
```

Output derivation:

```
$out/
  skills/
    persist/SKILL.md
    persist-status/SKILL.md
    my-local-skill/SKILL.md
  commands/
    quick-review.md
  CLAUDE.md
  settings.json
  mcp-servers.json
```

### Home-manager module

```nix
programs.claude-code = {
  enable = true;
  package = claude-code.packages.${system}.default;  # or null to skip
  skills = [ ... ];
  commands = [ ... ];
  memory.fragments = [ ... ];
  mcpServers = { ... };
  settings = { ... };
};
```

Calls `mkClaudeConfig` internally, then uses `home.activation` scripts to install files into `~/.claude/`.

## Options reference

```
programs.claude-code = {
  enable : bool                          # default false
  package : package | null               # default null

  skills : list of path                  # directories with SKILL.md
  commands : list of path                # flat .md files
  commandsDir : path | null              # directory of .md files (bulk import)

  memory = {
    fragments : list of (path | string)  # concatenated into CLAUDE.md
    separator : string                   # default "\n\n"
  };

  mcpServers : attrset of attrset        # merged into ~/.claude.json
  settings : attrset                     # written to settings.json; empty = unmanaged
};
```

## Resolved design decisions

### Skills go in `~/.claude/skills/`, not `~/.claude/commands/`

**Status: BUG in current implementation.**

The DESIGN.md assumed skills and commands both live in `~/.claude/commands/`. Audit of `~/.claude/` and the persist README confirm that Claude Code uses two separate directories:

- `~/.claude/skills/<name>/SKILL.md` -- directory-based skills (slash commands)
- `~/.claude/commands/<name>.md` -- flat markdown commands

The current implementation incorrectly places skills into `commands/`. This needs to be fixed: `mkClaudeConfig` should output `$out/skills/` and `$out/commands/` separately, and the home-manager activation should install them to their respective locations.

### Home-manager option namespace: `programs.claude-code`

Chose `programs.claude-code` to match prior art (claude-config.nix, mcps.nix). This allows option merging with mcps.nix without coupling -- both modules can independently contribute to the same namespace. Risk of conflict with hypothetical future upstream home-manager support is accepted; the namespace can be migrated if that happens.

### Idempotency and cleanup: manifest-based tracking

Chose the middle path: track managed files via a `.nix-claude-managed` manifest file in the target directory. On each activation:

1. Read the previous manifest and delete listed entries
2. Copy new files from the derivation
3. Write an updated manifest

This avoids destroying user-added commands (unlike wipe-and-recreate) and avoids accumulating cruft (unlike add-only). The manifest is a simple newline-delimited list of filenames.

### MCP config merge strategy: deep merge, no stale tracking

Adopted `jq -s '.[0] * .[1]'` (deep merge) from claude-config.nix. A removed MCP server persists in `~/.claude.json` until manually cleaned. This is the simplest correct approach -- stale tracking adds complexity for marginal benefit. Users who need a clean slate can delete `~/.claude.json` before activation.

### Relationship with mcps.nix: compose via option merging

No dependency on mcps.nix. Both modules write to `programs.claude-code.mcpServers`; home-manager's option system merges them. This works because `mcpServers` is typed as `attrsOf attrs`, which home-manager merges by key. No coupling, no coordination needed.

### Activation scripts, not symlinks

Claude Code cannot read symlinked config files. All files are copied via `install -m 0644` (files) or `cp -r` + `chmod` (directories).

### Settings are fully replaced, not merged

Unlike `~/.claude.json` (which Claude writes to at runtime), `settings.json` is not mutable at runtime. When `settings` is non-empty, the file is written wholesale. When `settings` is empty (default), the file is not touched.

### Plugin convention for flakes

Established by the persist example. A Claude Code plugin flake should export:

- `packages.<system>.default` -- the plugin binary (if any)
- `skills.<name>` -- paths to skill directories for nix-claude's `skills` option

Consumers wire up hooks and settings on their side. This keeps plugins decoupled from nix-claude.

### `plugins/` marketplace is not managed directly

The `~/.claude/plugins/` directory is Claude Code's built-in plugin marketplace system. It contains:

- `known_marketplaces.json` -- git-backed marketplace registries (e.g. `anthropics/claude-plugins-official`)
- `installed_plugins.json` -- tracks installed plugins with versions, scopes, and git SHAs
- `cache/` -- downloaded plugin contents (git checkouts with `.claude-plugin/plugin.json` manifest and `skills/` directories)
- `blocklist.json` -- remote blocklist fetched from Anthropic

nix-claude does not write to `plugins/`. The marketplace adds indirection (plugin.json manifests, git SHA tracking, blocklist checks) that nix-claude would have to replicate or ignore. Instead, nix-claude installs plugin content directly as skills -- a marketplace plugin's payload is just a `skills/` directory with SKILL.md files, which is exactly what nix-claude's `skills` option installs to `~/.claude/skills/`. Same result, no marketplace machinery to emulate.

User-level plugin management is fully covered by `skills`, `commands`, `memory`, `mcpServers`, and `settings`. The marketplace is a parallel installation path for users who don't use Nix.

### Per-project config is out of scope

Per-project config lives in-repo (`.claude/` directories) or in `~/.claude/projects/<hash>/`. This is fundamentally team-managed (checked into git), not generated from one person's Nix config. If a team wants project-local skills, they commit the `skills/` directory to their repo. `mkClaudeConfig` could technically produce this output, but there's no sensible installation target -- it would be writing into a git working tree, which Nix derivations shouldn't do.

### `~/.claude/` directory audit (complete)

```
backups/          # runtime: .claude.json backups
cache/            # runtime: changelog cache
CLAUDE.md         # managed by nix-claude
commands/         # managed by nix-claude (flat commands)
debug/            # runtime: debug logs
file-history/     # runtime
history.jsonl     # runtime: conversation history
paste-cache/      # runtime
plugins/          # runtime: built-in marketplace (out of scope, see above)
projects/         # runtime: per-project memory/config
session-env/      # runtime
settings.json     # managed by nix-claude
shell-snapshots/  # runtime
skills/           # managed by nix-claude (directory-based skills)
tasks/            # runtime
telemetry/        # runtime
todos/            # runtime
```

nix-claude manages 4 items: `skills/`, `commands/`, `CLAUDE.md`, `settings.json`. Everything else is runtime state.

## File layout

```
nix-claude/
  flake.nix
  lib/
    mkClaudeConfig.nix    # core: inputs -> derivation
    options.nix            # shared option type definitions
  modules/
    home-manager.nix       # home-manager module
  tests/
    default.nix            # nix flake checks
    fixtures/              # test data
  examples/
    persist/flake.nix      # real-world usage example
  SPEC.md
  DESIGN.md               # original design exploration (historical)
```
