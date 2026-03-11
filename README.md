# nix-claude

Declarative configuration for Claude Code via Nix.

Manages plugins, skills, commands, CLAUDE.md, MCP servers, and settings from a single Nix expression. Works with home-manager or standalone.

## Quick start

Add to your flake inputs:

```nix
inputs.nix-claude.url = "github:christian-oudard/nix-claude";
```

### Home-manager

```nix
{ nix-claude, persist, ... }:
{
  imports = [ nix-claude.homeManagerModules.default ];

  programs.claude-code = {
    enable = true;
    skipOnboarding = true;

    plugins.persist = {
      description = "Persistent coding sessions";
      skills = builtins.attrValues persist.skills;
    };

    commands = [ ./commands/quick-review.md ];

    memory.fragments = [
      ./base-instructions.md
      "Always use TypeScript for new files."
    ];

    mcpServers.github = {
      command = "${github-mcp}/bin/github-mcp-server";
      args = [ "stdio" ];
    };

    settings = {
      permissions.allow = [ "Bash" "Read" "Write" ];
      hooks.Stop = [{
        matcher = "";
        hooks = [{ type = "command"; command = "${persist-pkg}/bin/persist hook"; }];
      }];
    };
  };
}
```

### Standalone (coding-cave, scripts)

```nix
let
  claudeConfig = nix-claude.lib.mkClaudeConfig {
    inherit pkgs;
    skipOnboarding = true;
    plugins.persist = {
      description = "Persistent coding sessions";
      skills = builtins.attrValues persist.skills;
    };
    memory.fragments = [ ./instructions.md ];
    mcpServers.github = { command = "..."; args = [ "stdio" ]; };
  };
in
# claudeConfig is a derivation containing:
# $out/plugins/cache/nix-claude/persist/<version>/...
# $out/plugins/installed_plugins.json
# $out/CLAUDE.md
# $out/dot-claude.json
```

Copy the output into `~/.claude/` however you like.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable config management |
| `package` | package or null | `null` | Claude Code package to install |
| `plugins` | attrset of { description, skills } | `{}` | Plugins installed via Claude's plugin system |
| `skills` | list of path | `[]` | Bare skills installed to ~/.claude/skills/ |
| `commands` | list of path | `[]` | Flat markdown command files |
| `commandsDir` | path or null | `null` | Directory of .md files to bulk-import |
| `memory.fragments` | list of (path or string) | `[]` | Concatenated into CLAUDE.md |
| `memory.separator` | string | `"\n\n"` | Separator between fragments |
| `mcpServers` | attrset | `{}` | MCP server configs, merged into ~/.claude.json |
| `skipOnboarding` | bool | `false` | Skip first-run onboarding prompts |
| `dotClaudeJson` | attrset | `{}` | Arbitrary fields merged into ~/.claude.json |
| `settings` | attrset | `{}` | Written to ~/.claude/settings.json |

## Plugins vs skills

**Plugins** (`plugins` option) are installed through Claude Code's plugin system -- they appear in `~/.claude/plugins/` with full metadata (`installed_plugins.json`, `plugin.json`), as if installed via the marketplace. This is the recommended way to install skills.

**Bare skills** (`skills` option) are installed directly to `~/.claude/skills/`. Simpler, but not visible to Claude Code's plugin management.

## Writing a plugin flake

A Claude Code plugin flake should export:

```nix
{
  packages.${system}.default = pkgs.buildSomething { ... };  # the binary
  skills = {
    my-skill = ./skills/my-skill;       # directories with SKILL.md
    my-other-skill = ./skills/my-other-skill;
  };
}
```

See `examples/persist/` for a real-world example using [persist](https://github.com/christian-oudard/persist).

## Authentication

nix-claude manages configuration, not credentials. Authentication is handled separately:

**Interactive (desktop NixOS):** Run `claude auth login` after your first `home-manager switch`. This opens a browser OAuth flow and stores the token in your system keychain. Works fine with `skipOnboarding = true` -- onboarding and auth are separate flows.

**Headless (servers, CI, sandboxes):** Generate a long-lived token with `claude setup-token`, then pass it via environment variable:

```nix
# home-manager
home.sessionVariables.CLAUDE_CODE_OAUTH_TOKEN = "$(cat /run/secrets/claude-token)";

# or via your secrets manager (sops-nix, agenix, etc.)
sops.secrets.claude-oauth-token = {};
systemd.user.sessionVariables.CLAUDE_CODE_OAUTH_TOKEN =
  config.sops.secrets.claude-oauth-token.path;
```

**API key (no subscription):** Set `ANTHROPIC_API_KEY` instead of using OAuth.

nix-claude never writes tokens to the Nix store or to disk. Credentials should flow through environment variables or your secrets manager. Good options include [sops-nix](https://github.com/Mic92/sops-nix), [agenix](https://github.com/ryantm/agenix), and [chezmoi](https://www.chezmoi.io/) (which complements Nix well for managing secrets and other mutable dotfiles that don't belong in the Nix store).

## Composing with mcps.nix

nix-claude composes with [mcps.nix](https://github.com/roman/mcps.nix) via home-manager option merging:

```nix
imports = [
  nix-claude.homeManagerModules.default
  mcps-nix.homeManagerModules.default
];
```

Both write to `programs.claude-code.mcpServers` independently -- home-manager merges by key.

## Running tests

```bash
nix flake check
```
