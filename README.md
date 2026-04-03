# nix-claude

Declarative configuration for Claude Code via Nix.

Manages Claude Code plugins, skills, commands, settings, and MCP servers via Nix. The home-manager module adds plugin support alongside the built-in `programs.claude-code` module. For standalone use, `mkClaudeConfig` produces a self-contained derivation.

## Quick start

Add to your flake inputs:

```nix
inputs.nix-claude.url = "github:christian-oudard/nix-claude";
```

### Home-manager (with built-in module)

nix-claude adds plugin support alongside the built-in `programs.claude-code` module:

```nix
{ nix-claude, persist, ... }:
{
  imports = [ nix-claude.homeModules.default ];

  # Built-in module handles core config
  programs.claude-code = {
    enable = true;
    skipOnboarding = true;

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
    };
  };

  # Plugins are a list; flake inputs are resolved automatically
  programs.claude-code.plugins = [ persist ];
}
```

Plugin settings are deep-merged into `programs.claude-code.settings`. List values like `hooks.Stop` concatenate, so plugin hooks and user hooks both end up in the final `settings.json`.

### Standalone (`mkClaudeConfig`)

```nix
let
  claudeConfig = nix-claude.lib.mkClaudeConfig {
    inherit pkgs;
    skipOnboarding = true;
    plugins = [ persist ];
    memory.fragments = [ ./instructions.md ];
    mcpServers.github = { command = "..."; args = [ "stdio" ]; };
  };
in
# claudeConfig is a derivation containing:
# $out/skills/persist/SKILL.md
# $out/CLAUDE.md
# $out/dot-claude.json
```

Copy the output into `~/.claude/` however you like.

## Options

### Home-manager module

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `plugins` | list of attrs | `[]` | Plugins to install. Flake inputs with a `plugin` attr are resolved automatically. |

Each plugin attrset can have:

| Field | Type | Description |
|-------|------|-------------|
| `src` | path or null | Pre-built plugin directory (skills/commands extracted) |
| `skills` | list of path | Skill directories containing SKILL.md (ignored if `src` set) |
| `package` | package or null | Added to `home.packages` |
| `settings` | attrset | Deep-merged into `programs.claude-code.settings` |

Core options (`enable`, `package`, `settings`, `memory`, `commands`, `skills`, `mcpServers`, `skipOnboarding`, `dotClaudeJson`) are provided by the built-in `programs.claude-code` module.

### `mkClaudeConfig` (standalone)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `plugins` | list of attrs | `[]` | Plugins (skills installed as bare skills) |
| `skills` | list of path | `[]` | Bare skills installed to `$out/skills/` |
| `commands` | list of path | `[]` | Flat markdown command files |
| `commandsDir` | path or null | `null` | Directory of .md files to bulk-import |
| `memory.fragments` | list of (path or string) | `[]` | Concatenated into CLAUDE.md |
| `memory.separator` | string | `"\n\n"` | Separator between fragments |
| `mcpServers` | attrset | `{}` | MCP server configs, merged into `dot-claude.json` |
| `skipOnboarding` | bool | `false` | Skip first-run prompts (writes to `~/.claude.json`, not `settings.json`) |
| `dotClaudeJson` | attrset | `{}` | Arbitrary fields merged into `dot-claude.json` |
| `settings` | attrset | `{}` | Written to `settings.json` |
| `statusline` | string or null | `null` | Statusline script content |

## Writing a plugin flake

A Claude Code plugin flake should export three things:

- `packages.<system>.default` -- the plugin binary
- `skills` -- an attrset of skill directory paths (each containing SKILL.md)
- `plugin.<system>` -- a ready-made nix-claude config attrset

The `plugin` output bundles description, skills, package, and settings so consumers can use it directly:

```nix
{
  packages = eachSystem (system: {
    default = pkgs.buildSomething { ... };
  });

  skills = {
    my-skill = ./skills/my-skill;
    my-other-skill = ./skills/my-other-skill;
  };

  plugin = eachSystem (system:
    let pkg = self.packages.${system}.default; in {
      description = "What this plugin does";
      skills = builtins.attrValues self.skills;
      package = pkg;
      settings.hooks.Stop = [{
        matcher = "";
        hooks = [{ type = "command"; command = "${pkg}/bin/my-tool hook"; }];
      }];
    });
}
```

Consumers pass plugin flake inputs directly in the `plugins` list. nix-claude resolves the `plugin` attr automatically:

```nix
programs.claude-code.plugins = [ persist ];
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
  nix-claude.homeModules.default
  mcps-nix.homeModules.default
];
```

Both write to `programs.claude-code.mcpServers` independently -- home-manager merges by key.

## Running tests

```bash
nix flake check
```
