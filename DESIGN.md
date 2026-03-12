# nix-claude — Design

Declarative configuration for Claude Code via Nix.

## Problem

Claude Code's configuration is scattered across multiple files and formats:

- `~/.claude/commands/<name>.md` — flat slash commands
- `~/.claude/commands/<name>/SKILL.md` — directory-based skills (slash commands with structure)
- `~/.claude/CLAUDE.md` — persistent instructions (always in context)
- `~/.claude/settings.json` — editor settings, permissions, allowed tools
- `~/.claude.json` — MCP servers, runtime state (Claude writes to this at runtime)

Setting up a Claude Code environment means manually copying files, editing JSON, and hoping nothing drifts. With multiple machines or sandboxed environments (like coding-cave), this becomes untenable.

## Solution

A Nix library and home-manager module that assembles a complete Claude Code configuration from declarative inputs.

## Scope

nix-claude manages **configuration and extensions**. It does not package the Claude Code binary — that's `claude-code-nix`'s job.

What nix-claude handles:

- Skills (directory-based commands with SKILL.md)
- Commands (flat markdown files)
- CLAUDE.md (persistent instructions, composable from fragments)
- MCP server configuration (in `~/.claude.json`)
- Settings (in `~/.claude/settings.json`)

What nix-claude does NOT handle:

- Packaging the Claude Code binary (use `claude-code-nix` or nixpkgs)
- Packaging MCP server binaries (use `mcps.nix`, nixpkgs, or your own derivations)
- Multi-account management (use `claude-env` if needed)
- Runtime state (conversations, OAuth tokens, `.claude.json` fields Claude writes itself)

## Prior art

Examined in detail before this design (source cloned and read):

- **claude-code-nix** (sadjow) — Nix package for the Claude Code binary. Hourly auto-updates, native/node/bun variants, overlay. No config management. We use this as the default package source.
- **mcps.nix** (roman) — MCP server presets for home-manager and devenv. Has a `mkPresetModule` pattern with typed options, `wrapWithCredentialFiles` for secret handling, and a `tools.nix` registry mapping preset names to packaged binaries. Only handles MCP servers, not skills/commands/CLAUDE.md.
- **claude-config.nix** (flyinggrizzly) — Home-manager module for commands, CLAUDE.md, and mcpServers. Uses `home.activation` scripts with `install -m 0644` to work around Claude's symlink bug. Merges mcpServers into `~/.claude.json` via jq. No skill support (directory-based commands). No settings.json management.
- **claude-env** (solomon-b) — Multi-account switcher via `CLAUDE_CONFIG_DIR`. Orthogonal to nix-claude.

### Gap

Nobody unifies the full config surface. Skills don't exist as a Nix concept anywhere. MCP server config and skill/command management are split across separate projects that don't compose. The coding-cave has ad-hoc skill seeding that isn't reusable.

## Architecture

Two interfaces to the same logic:

```
                          nix-claude
                         /          \
            home-manager module    lib.mkClaudeConfig
                   |                      |
             home activation         derivation output
                   |                      |
           ~/.claude/ (copied)     /nix/store/...-claude-config/
                                          |
                                   coding-cave init copies
                                   into sandbox ~/.claude/
```

### 1. `lib.mkClaudeConfig` — the core

A function that takes config options and produces a derivation:

```nix
nix-claude.lib.mkClaudeConfig {
  skills = [
    agent-capabilities.skills.pdf-convert
    agent-capabilities.skills.audio-transcribe
    ./my-local-skill
  ];

  commands = [
    ./commands/quick-review.md
    "${claude-loop.src}/commands/loop.md"
  ];

  memory = {
    fragments = [
      ./base-claude.md
      ./project-conventions.md
    ];
  };

  mcpServers = {
    github = {
      command = "${github-mcp-server}/bin/github-mcp-server";
      args = [ "stdio" ];
      env.GITHUB_PERSONAL_ACCESS_TOKEN_FILE = "/run/secrets/github-token";
    };
  };

  settings = {
    permissions = {
      allow = [ "Bash" "Read" "Write" ];
    };
  };
}
```

Output derivation:

```
$out/
  commands/
    pdf-convert/SKILL.md
    audio-transcribe/SKILL.md
    my-local-skill/SKILL.md
    quick-review.md
    loop.md
  CLAUDE.md                    # concatenated fragments
  settings.json                # if settings provided
  mcp-servers.json             # mcpServers as JSON (for merge into ~/.claude.json)
```

This is a pure derivation. It doesn't touch `~/.claude/`. Consumers decide how to install it.

### 2. Home-manager module

For NixOS/home-manager users:

```nix
programs.claude-code = {
  enable = true;
  package = claude-code.packages.${system}.default;

  skills = [ ... ];
  commands = [ ... ];
  memory.fragments = [ ... ];
  mcpServers = { ... };
  settings = { ... };
};
```

Implementation: calls `mkClaudeConfig` internally, then uses `home.activation` scripts to copy files into `~/.claude/` and merge MCP config into `~/.claude.json`.

### 3. Coding-cave consumption

The coding-cave doesn't use home-manager. It has its own sandbox init. It would use `mkClaudeConfig` directly:

```nix
# In coding-cave's flake.nix
claudeConfig = nix-claude.lib.mkClaudeConfig {
  skills = [
    agent-capabilities.skills.pdf-convert
    "${claude-loop.src}/commands/loop"
  ];
  memory.fragments = [ ./cave-claude.md ];
};
```

Then in the cave's init runtime (replacing the current ad-hoc skill seeding):

```bash
# Copy assembled config into the sandbox
cp -r ${claudeConfig}/commands/* "$CLAUDE_DIR/commands/"
cp ${claudeConfig}/CLAUDE.md "$CLAUDE_DIR/CLAUDE.md"
# etc.
```

## Design decisions

### Skills are paths, not derivations

A skill is just a directory containing `SKILL.md`. No builder needed:

```nix
skills = [
  ./my-skill                              # local directory
  "${some-flake}/skills/some-skill"       # from a flake
  agent-capabilities.skills.pdf-convert   # exported path
];
```

`mkClaudeConfig` copies each into `$out/commands/<dirname>/SKILL.md`. The directory name becomes the slash command name.

If a skill source is a file (not a directory), it's treated as a flat command and copied to `$out/commands/<filename>`.

### CLAUDE.md is composed from fragments

Instead of a single monolithic file, memory is built from fragments:

```nix
memory.fragments = [
  ./base.md
  ./project-specific.md
];
```

Fragments are concatenated in order, separated by blank lines. This lets different flakes contribute instructions without conflicting.

### Activation scripts, not symlinks

Claude Code cannot read symlinked config files (confirmed by claude-config.nix, mcps.nix, and the Lewis Flude blog post). All files are copied into `~/.claude/` via `home.activation` scripts with `install -m 0644`.

### Settings are optional

`settings.json` management is opt-in. If `settings = {}` (the default), nix-claude doesn't touch `~/.claude/settings.json`. When provided, it writes the full file (this file is not mutable at runtime like `.claude.json`).

## Open questions

### Relationship with mcps.nix

mcps.nix has a well-designed MCP preset system (`mkPresetModule`, typed options, credential file wrapping). Several options for how nix-claude relates to it:

- **Compose via option merging**: nix-claude accepts raw `mcpServers` attrsets. mcps.nix also writes to `programs.claude-code.mcpServers`. If both are imported as home-manager modules, home-manager merges them. No coupling needed, but need to verify this actually works without conflicts.
- **Depend on mcps.nix**: import mcps.nix and re-export its presets. Tighter integration but adds a dependency and ties our release cycle to theirs.
- **Absorb the preset pattern**: implement our own `mkPresetModule` equivalent. More self-contained but duplicates work.

Need to test the compose path first. If home-manager option merging works cleanly, that's the simplest answer.

### MCP config merge strategy

`~/.claude.json` is mutable — Claude writes to it at runtime (onboarding state, etc.). claude-config.nix merges via `jq -s '.[0] * .[1]'`. Questions:

- Is deep merge the right strategy, or should `mcpServers` be replaced wholesale? Deep merge means a removed server persists until the user manually cleans `.claude.json`.
- Should nix-claude track which servers it manages and remove stale ones? This adds complexity but avoids drift.
- How does this interact with mcps.nix if both are writing to `.claude.json`?

### devenv module

mcps.nix and mcp-servers-nix both support devenv (per-project `.mcp.json`). Should nix-claude also have a devenv module, or is per-project config out of scope? The core `mkClaudeConfig` could support it, but the use case is different (project-local vs user-global).

### Home-manager option namespace

claude-config.nix uses `programs.claude-code`. mcps.nix extends `programs.claude-code.mcps`. Home-manager upstream may eventually add native Claude Code options. Need to decide:

- Use `programs.claude-code` (matches prior art, risks conflict with upstream)
- Use a different namespace like `programs.nix-claude` (avoids conflict, breaks compose with mcps.nix)

### Idempotency and cleanup

When a skill is removed from the Nix config, should the next activation delete it from `~/.claude/commands/`? claude-config.nix has a `forceClean` option that wipes everything first. Alternatives:

- Always wipe and recreate (simple, but destroys user-added commands)
- Track managed files and only remove those (complex, needs state)
- Never delete, only add/update (safe, but accumulates cruft)

### What else lives in `~/.claude/`?

Need to audit the full contents of `~/.claude/` to understand what else might be worth managing. Known: commands/, CLAUDE.md, settings.json, settings.local.json. May also be: agents/, hooks.json, projects/ (per-project memory). Some of these may be worth managing declaratively; others are runtime state that should be left alone.

## Module options reference

Preliminary — subject to change based on open questions above.

```
programs.claude-code = {
  enable : bool                          # default false
  package : package | null               # default pkgs.claude-code
                                         # set null to skip installing the binary

  skills : list of path                  # directories with SKILL.md
  commands : list of path                # flat .md files
  commandsDir : path | null              # directory of .md files (bulk import)

  memory = {
    fragments : list of (path | string)  # concatenated into CLAUDE.md
    separator : string                   # default "\n\n"
  };

  mcpServers : attrset                   # raw JSON-compatible attrset
                                         # merged into ~/.claude.json

  settings : attrset                     # written to ~/.claude/settings.json
                                         # empty = don't manage
};
```

## Relationship with home-manager's built-in module

Home-manager (via claude-code-nix or upstream) provides a built-in `programs.claude-code` module that handles:

- `enable`, `package` -- installing the Claude Code binary
- `settings` -- `~/.claude/settings.json` (using `pkgs.formats.json` type)
- `memory`, `commands`, `skills` -- CLAUDE.md, commands, bare skills
- `mcpServers`, `skipOnboarding`, `dotClaudeJson` -- `~/.claude.json`

nix-claude's home-manager module does NOT re-declare any of these options. It only declares `programs.claude-code.plugins`, which is a new option not provided by the built-in module. The module then:

1. Installs plugin skills to the plugin cache directory via activation scripts
2. Registers plugins in `installed_plugins.json`
3. Collects `package` from each plugin and adds them to `home.packages`
4. Deep-merges `settings` from each plugin into `programs.claude-code.settings` via `lib.mkMerge`

This design means the two modules compose cleanly: users configure core settings through the built-in module, and add plugins through nix-claude. Plugin settings (like hooks) merge naturally with user settings because `pkgs.formats.json` concatenates list values.

For standalone use (coding-cave, scripts), `mkClaudeConfig` still supports the full configuration surface.

## Relationship to other projects

```
claude-code-nix -----> provides the binary
                          |
                          v
                    nix-claude -----> configures everything
                     ^      ^
                     |      |
              mcps.nix      agent-capabilities
          (MCP presets,     (skill definitions,
           optional)         any flake can do this)
```

- **claude-code-nix**: upstream binary. nix-claude uses it as the default package but doesn't depend on it — any Claude Code package works.
- **mcps.nix**: see open questions. Intent is complementary, not competitive.
- **agent-capabilities**: one of many possible skill sources. Exports paths that nix-claude's `skills` option accepts.
- **claude-config.nix**: nix-claude covers its full feature set (commands, memory, mcpServers) plus skills and settings. Whether to fork, supersede, or collaborate is TBD.
- **claude-env**: orthogonal. Manages which config directory Claude uses, not what's in it.

## File layout

```
nix-claude/
  flake.nix
  lib/
    mkClaudeConfig.nix      # core: inputs -> derivation
    options.nix              # shared option type definitions
  modules/
    home-manager.nix         # home-manager module (uses mkClaudeConfig)
  DESIGN.md
```
