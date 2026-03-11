# nix-claude -- Specification

Declarative configuration for Claude Code via Nix.

## Overview

A Nix library (`mkClaudeConfig`) and home-manager module (`programs.claude-code`) that assembles a complete Claude Code configuration from declarative inputs.

nix-claude manages configuration and extensions. It does not package the Claude Code binary or MCP server binaries.

## What nix-claude manages

- Plugins (installed through Claude Code's plugin system with full metadata)
- Skills (bare directory-based skills, each containing SKILL.md)
- Commands (flat markdown files)
- CLAUDE.md (persistent instructions, composed from fragments)
- `~/.claude.json` state (MCP servers, onboarding skip, arbitrary fields)
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
  skipOnboarding = true;

  plugins.persist = {
    description = "Persistent coding sessions";
    skills = builtins.attrValues persist.skills;
  };

  commands = [ ./commands/quick-review.md ];
  memory.fragments = [ ./base-claude.md "Inline instruction." ];

  mcpServers.github = {
    command = "${github-mcp-server}/bin/github-mcp-server";
    args = [ "stdio" ];
  };

  dotClaudeJson = { theme = "dark"; };

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
  plugins/
    cache/nix-claude/persist/<version>/
      .claude-plugin/plugin.json
      skills/persist/SKILL.md
      skills/persist-status/SKILL.md
      skills/persist-stop/SKILL.md
    installed_plugins.json
  commands/
    quick-review.md
  CLAUDE.md
  dot-claude.json          # merged mcpServers + skipOnboarding + dotClaudeJson
  settings.json
```

### Home-manager module

```nix
programs.claude-code = {
  enable = true;
  package = claude-code.packages.${system}.default;
  skipOnboarding = true;
  plugins.persist = { ... };
  commands = [ ... ];
  memory.fragments = [ ... ];
  mcpServers = { ... };
  dotClaudeJson = { ... };
  settings = { ... };
};
```

Calls `mkClaudeConfig` internally, then uses `home.activation` scripts to install files into `~/.claude/`.

## Options reference

```
programs.claude-code = {
  enable : bool                          # default false
  package : package | null               # default null

  plugins : attrset of {                 # installed via Claude's plugin system
    description : string                 # plugin.json description
    skills : list of path                # skill directories with SKILL.md
  }

  skills : list of path                  # bare skills in ~/.claude/skills/
  commands : list of path                # flat .md files
  commandsDir : path | null              # directory of .md files (bulk import)

  memory = {
    fragments : list of (path | string)  # concatenated into CLAUDE.md
    separator : string                   # default "\n\n"
  };

  mcpServers : attrset of attrset        # merged into ~/.claude.json
  skipOnboarding : bool                  # default false; skip first-run prompts
  dotClaudeJson : attrset                # arbitrary fields merged into ~/.claude.json
  settings : attrset                     # written to settings.json; empty = unmanaged
};
```

## Design decisions

### Plugins use Claude Code's native plugin system

nix-claude acts as a virtual marketplace called `nix-claude`. Each plugin is installed to `~/.claude/plugins/cache/nix-claude/<name>/<version>/` with a `.claude-plugin/plugin.json` manifest and `skills/` directory. Plugins are registered in `installed_plugins.json` as `<name>@nix-claude` with user scope.

This means nix-claude-installed plugins look identical to marketplace-installed ones. The version is a 12-character hash derived from the plugin name and skill paths, providing content-based versioning.

### Skills go in `~/.claude/skills/`, not `~/.claude/commands/`

Claude Code uses two separate directories:

- `~/.claude/skills/<name>/SKILL.md` -- directory-based skills (slash commands)
- `~/.claude/commands/<name>.md` -- flat markdown commands

The `plugins` option installs skills through the plugin system (`~/.claude/plugins/cache/`). The `skills` option installs bare skills to `~/.claude/skills/`. The `commands` option installs flat commands to `~/.claude/commands/`.

### `~/.claude.json` is assembled from multiple sources

Three options contribute to `~/.claude.json`, merged in this order:

1. `skipOnboarding` -- sets `hasCompletedOnboarding` and `effortCalloutDismissed`
2. `mcpServers` -- sets the `mcpServers` key
3. `dotClaudeJson` -- arbitrary fields (e.g. `theme`, preferences)

These are merged with `//` (later keys win) into a single `dot-claude.json` in the derivation output. The home-manager module deep-merges this into the existing `~/.claude.json` via jq, preserving runtime state Claude has written.

### Home-manager option namespace: `programs.claude-code`

Matches prior art (claude-config.nix, mcps.nix). Composes with mcps.nix via option merging -- both modules contribute to `programs.claude-code.mcpServers` independently.

### Idempotency and cleanup: manifest-based tracking

Managed files are tracked via `.nix-claude-managed` manifest files. On each activation: read the previous manifest, delete listed entries, copy new files, write updated manifest. User-added files outside the manifest are preserved.

### Activation scripts, not symlinks

Claude Code cannot read symlinked config files. All files are copied via `install -m 0644` (files) or `cp -r` + `chmod` (directories).

### Settings are fully replaced, not merged

`settings.json` is not mutable at runtime. Written wholesale when non-empty, untouched when empty.

### Plugin convention for flakes

Plugin flakes export:

- `packages.<system>.default` -- the plugin binary (if any)
- `skills.<name>` -- paths to skill directories

Consumers use `plugins.<name>.skills` to install and wire up hooks/settings separately.

### Authentication is out of scope

nix-claude manages configuration, not credentials. OAuth tokens flow through environment variables (`CLAUDE_CODE_OAUTH_TOKEN`) or the system keychain, never through the Nix store. See README for setup guidance.

### Per-project config is out of scope

Per-project config is team-managed (committed to git), not generated from one person's Nix config.

### `~/.claude/` directory audit

```
backups/          # runtime
cache/            # runtime
CLAUDE.md         # managed by nix-claude
commands/         # managed by nix-claude (flat commands)
debug/            # runtime
file-history/     # runtime
history.jsonl     # runtime
paste-cache/      # runtime
plugins/          # managed by nix-claude (plugin cache + installed_plugins.json)
projects/         # runtime (per-project memory)
session-env/      # runtime
settings.json     # managed by nix-claude
shell-snapshots/  # runtime
skills/           # managed by nix-claude (bare skills)
tasks/            # runtime
telemetry/        # runtime
todos/            # runtime
```

nix-claude manages: `plugins/cache/nix-claude/`, `plugins/installed_plugins.json`, `skills/`, `commands/`, `CLAUDE.md`, `settings.json`, and fields in `~/.claude.json`.

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
