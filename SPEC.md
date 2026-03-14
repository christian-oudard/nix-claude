# nix-claude -- Specification

Declarative configuration for Claude Code via Nix.

## Overview

A Nix library (`mkClaudeConfig`) and home-manager plugin module that assembles Claude Code configuration from declarative inputs.

nix-claude manages plugins and configuration extensions. It does not package the Claude Code binary or MCP server binaries. For home-manager users, nix-claude works alongside the built-in `programs.claude-code` module, which handles settings, memory, commands, skills, and MCP servers.

## What nix-claude manages

- Plugin skills (installed as bare skills to `~/.claude/skills/`, auto-discovered by Claude Code)
- Plugin commands (installed to `~/.claude/commands/`)
- Plugin packages (collected and added to `home.packages`)
- Plugin settings (deep-merged into `programs.claude-code.settings`)

Via `mkClaudeConfig` (standalone use):
- Skills (bare directory-based skills, each containing SKILL.md)
- Commands (flat markdown files)
- CLAUDE.md (persistent instructions, composed from fragments)
- `~/.claude.json` state (MCP servers, onboarding skip, arbitrary fields)
- Settings (written to `~/.claude/settings.json`)

## Architecture

```
                        nix-claude
                       /          \
          home-manager module    lib.mkClaudeConfig
          (plugins only)        (full standalone config)
                 |                      |
     programs.claude-code.plugins   derivation output
                 |                      |
     + home.packages             /nix/store/...-claude-config/
     + programs.claude-code.settings
     + activation script (skills + commands)
```

### `lib.mkClaudeConfig`

Pure function producing a derivation. Does not touch `~/.claude/`. Consumers decide how to install. Supports the full configuration surface.

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
  skills/
    persist/SKILL.md
    persist-status/SKILL.md
    persist-stop/SKILL.md
  commands/
    quick-review.md
  CLAUDE.md
  dot-claude.json          # merged mcpServers + skipOnboarding + dotClaudeJson
  settings.json
```

### Home-manager module

The home-manager module is plugins-only. It works alongside the built-in `programs.claude-code` module (provided by home-manager or claude-code-nix), which handles settings, memory, commands, skills, MCP servers, and the Claude Code package.

```nix
# Built-in module handles core config
programs.claude-code = {
  enable = true;
  settings = {
    permissions.allow = [ "Bash" "Read" "Write" ];
  };
};

# nix-claude adds plugin support
programs.claude-code.plugins.persist = {
  description = "Persistent coding sessions";
  skills = builtins.attrValues persist.skills;
  package = persistPkg;
  settings = {
    hooks.Stop = [{
      matcher = "";
      hooks = [{ type = "command"; command = "${persistPkg}/bin/persist hook"; }];
    }];
  };
};
```

The module:

1. Installs skills as bare skills to `~/.claude/skills/` via activation script
2. Installs commands to `~/.claude/commands/` via activation script
3. Collects `package` from each plugin into `home.packages`
4. Deep-merges `settings` from each plugin into `programs.claude-code.settings`

Since `programs.claude-code.settings` uses `pkgs.formats.json` type, list values (like `hooks.Stop`) concatenate when merged from multiple sources. This means plugin hooks and user hooks both end up in the final `settings.json`.

## Options reference

### Home-manager module (plugins)

```
programs.claude-code.plugins : attrset of {
  src : path | null                    # existing plugin directory (skills/commands extracted)
  description : string                 # plugin description (ignored if src set)
  skills : list of path                # skill directories with SKILL.md (ignored if src set)
  package : package | null             # optional; added to home.packages
  settings : attrset                   # deep-merged into programs.claude-code.settings
}
```

When `src` is set, skills and commands are extracted from the directory and installed
as bare skills/commands. This is useful for installing pre-built plugins (e.g. from
`claude-plugins-official`). When `src` is not set, skills are taken from the `skills` list.

### `mkClaudeConfig` (standalone)

```
mkClaudeConfig {
  pkgs : pkgs                            # required

  plugins : attrset of {                 # skills installed as bare skills
    src : path | null                    # existing plugin directory (skills/commands extracted)
    description : string                 # plugin description (ignored if src set)
    skills : list of path                # skill directories with SKILL.md (ignored if src set)
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
}
```

## Design decisions

### Skills use bare skill directories

nix-claude installs plugin skills as bare skills to `~/.claude/skills/<name>/`. Claude Code auto-discovers skill directories containing `SKILL.md` in this location. This is simpler and more reliable than the plugin cache system, which requires a recognized marketplace.

The `plugins` option in mkClaudeConfig extracts skills from plugin sources and outputs them to `$out/skills/`. The home-manager activation script copies them to `~/.claude/skills/` with manifest-based tracking for cleanup.

### Home-manager module is plugins-only

The home-manager module only manages plugins. Settings, memory, commands, skills, MCP servers, and the Claude Code package are handled by the built-in `programs.claude-code` module. This avoids re-declaring options that already exist upstream and lets nix-claude focus on what it adds: the plugin system.

Plugin settings are deep-merged into `programs.claude-code.settings` via `lib.mkMerge`, so plugins can contribute hooks, permissions, and other settings that combine naturally with user-defined settings.

### Skills go in `~/.claude/skills/`, not `~/.claude/commands/`

Claude Code uses two separate directories:

- `~/.claude/skills/<name>/SKILL.md` -- directory-based skills (slash commands)
- `~/.claude/commands/<name>.md` -- flat markdown commands

The `plugins` option installs skills to `~/.claude/skills/`. In standalone mode, the `skills` option also installs bare skills to `~/.claude/skills/` and the `commands` option installs flat commands to `~/.claude/commands/`.

### `~/.claude.json` is assembled from multiple sources (standalone)

Three options contribute to `~/.claude.json`, merged in this order:

1. `skipOnboarding` -- sets `hasCompletedOnboarding` and `effortCalloutDismissed`
2. `mcpServers` -- sets the `mcpServers` key
3. `dotClaudeJson` -- arbitrary fields (e.g. `theme`, preferences)

These are merged with `//` (later keys win) into a single `dot-claude.json` in the derivation output.

### Idempotency and cleanup: manifest-based tracking

Managed files are tracked via `.nix-claude-managed` manifest files. On each activation: read the previous manifest, delete listed entries, copy new files, write updated manifest. User-added files outside the manifest are preserved.

### Activation scripts, not symlinks

Claude Code cannot read symlinked config files. All files are copied via `install -m 0644` (files) or `cp -r` + `chmod` (directories).

### Plugin convention for flakes

Plugin flakes export:

- `packages.<system>.default` -- the plugin binary (if any)
- `skills.<name>` -- paths to skill directories
- `plugin.<system>` -- a ready-made nix-claude config attrset (description, skills, package, settings)

The `plugin` output bundles everything a consumer needs:

```nix
plugin = eachSystem (system:
  let pkg = self.packages.${system}.default; in {
    description = "Persistent coding sessions for Claude Code";
    skills = builtins.attrValues self.skills;
    package = pkg;
    settings.hooks.Stop = [{
      matcher = "";
      hooks = [{ type = "command"; command = "${pkg}/bin/persist hook"; }];
    }];
  });
```

Consumers use a single line:

```nix
plugins.persist = persist.plugin.${system};
```

### Authentication is out of scope

nix-claude manages configuration, not credentials. OAuth tokens flow through environment variables (`CLAUDE_CODE_OAUTH_TOKEN`) or the system keychain, never through the Nix store. See README for setup guidance.

### Per-project config is out of scope

Per-project config is team-managed (committed to git), not generated from one person's Nix config.

### `~/.claude/` directory audit

```
backups/          # runtime
cache/            # runtime
CLAUDE.md         # managed by built-in module or mkClaudeConfig
commands/         # managed by nix-claude (plugin commands) or mkClaudeConfig
debug/            # runtime
file-history/     # runtime
history.jsonl     # runtime
paste-cache/      # runtime
plugins/          # runtime (marketplace plugins only)
projects/         # runtime (per-project memory)
session-env/      # runtime
settings.json     # managed by built-in module or mkClaudeConfig
shell-snapshots/  # runtime
skills/           # managed by nix-claude (plugin skills) or mkClaudeConfig
tasks/            # runtime
telemetry/        # runtime
todos/            # runtime
```

nix-claude home-manager module manages: `skills/` (bare skills from plugins), `commands/` (from src-based plugins), and contributes to `programs.claude-code.settings` and `home.packages`.

## File layout

```
nix-claude/
  flake.nix
  lib/
    mkClaudeConfig.nix    # core: inputs -> derivation
    options.nix            # shared option type definitions (standalone)
  modules/
    home-manager.nix       # home-manager module (plugins only)
  tests/
    default.nix            # nix flake checks
    fixtures/              # test data
  examples/
    persist/flake.nix      # real-world usage example
  SPEC.md
  DESIGN.md               # design exploration + built-in module relationship
```
