# nix-claude

Declarative configuration for Claude Code via Nix.

Manages skills, commands, CLAUDE.md, MCP servers, and settings from a single Nix expression. Works with home-manager or standalone.

## Quick start

Add to your flake inputs:

```nix
inputs.nix-claude.url = "github:your-user/nix-claude";
```

### Home-manager

```nix
{ nix-claude, persist, ... }:
{
  imports = [ nix-claude.homeManagerModules.default ];

  programs.claude-code = {
    enable = true;

    skills = [
      persist.skills.persist
      persist.skills.persist-status
      persist.skills.persist-stop
      ./my-local-skill  # directory containing SKILL.md
    ];

    commands = [
      ./commands/quick-review.md
    ];

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
    skills = [ ./skills/my-skill ];
    memory.fragments = [ ./instructions.md ];
    mcpServers.github = { command = "..."; args = [ "stdio" ]; };
  };
in
# claudeConfig is a derivation:
# $out/skills/my-skill/SKILL.md
# $out/CLAUDE.md
# $out/mcp-servers.json
```

Copy the output into `~/.claude/` however you like.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable config management |
| `package` | package or null | `null` | Claude Code package to install |
| `skills` | list of path | `[]` | Directories containing SKILL.md |
| `commands` | list of path | `[]` | Flat markdown command files |
| `commandsDir` | path or null | `null` | Directory of .md files to bulk-import |
| `memory.fragments` | list of (path or string) | `[]` | Concatenated into CLAUDE.md |
| `memory.separator` | string | `"\n\n"` | Separator between fragments |
| `mcpServers` | attrset | `{}` | MCP server configs, merged into ~/.claude.json |
| `settings` | attrset | `{}` | Written to ~/.claude/settings.json |

## How it works

- **Skills** go to `~/.claude/skills/<name>/SKILL.md`
- **Commands** go to `~/.claude/commands/<name>.md`
- **CLAUDE.md** is concatenated from fragments in order
- **MCP servers** are deep-merged into `~/.claude.json` (preserving runtime state)
- **Settings** are written wholesale to `~/.claude/settings.json`
- All files are **copied, not symlinked** (Claude Code can't read symlinks)
- Managed files are tracked via manifest for clean removal on config change

## Writing a plugin flake

A Claude Code plugin can export paths for nix-claude:

```nix
{
  # Package the binary
  packages.${system}.default = pkgs.buildSomething { ... };

  # Export skill directories
  skills = {
    my-skill = ./skills/my-skill;
    my-other-skill = ./skills/my-other-skill;
  };
}
```

See `examples/persist/` for a real-world example using [persist](https://github.com/christian-oudard/persist).

## Composing with mcps.nix

nix-claude composes with [mcps.nix](https://github.com/roman/mcps.nix) via home-manager option merging. Both write to `programs.claude-code.mcpServers` independently:

```nix
imports = [
  nix-claude.homeManagerModules.default
  mcps-nix.homeManagerModules.default
];
```

No configuration needed -- home-manager merges the `mcpServers` attrsets by key.

## Running tests

```bash
nix flake check
```
