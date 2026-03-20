# nix-claude

Declarative Claude Code configuration via Nix. Pure Nix -- no runtime dependencies beyond nixpkgs.

## Structure

- `lib/mkClaudeConfig.nix` -- core function: takes `{ pkgs, plugins, skills, commands, ... }`, returns a derivation
- `lib/build.nix` -- simplified builder for coding-cave: takes `{ pkgs, plugins, settings, skills, statusline }`, returns a derivation
- `lib/options.nix` -- shared NixOS/home-manager option type definitions
- `modules/home-manager.nix` -- home-manager module using `programs.claude-code` namespace
- `tests/default.nix` -- nix flake checks (run with `nix flake check`)
- `examples/persist/` -- real-world plugin installation example

## Key constraints

- Claude Code cannot read symlinked files. All installation uses `cp`/`install`, never symlinks.
- Skills installed via `plugins` go in `~/.claude/plugins/cache/nix-claude/<name>/<version>/skills/`. Bare skills go in `~/.claude/skills/`. Commands go in `~/.claude/commands/`.
- `~/.claude.json` is mutable at runtime (Claude writes onboarding state, etc). nix-claude deep-merges its fields (mcpServers, skipOnboarding, dotClaudeJson) via jq.
- `~/.claude/settings.json` is NOT mutable at runtime. Written wholesale when `settings` is non-empty.
- nix-claude acts as a virtual marketplace called `nix-claude` in `installed_plugins.json`.

## Testing

Run `nix flake check` to execute all tests. Tests build real derivations and verify file presence/content. No network access needed.

## Plugin convention

Plugin flakes export `skills.<name>` (paths to directories with SKILL.md) and `packages.<system>.default` (the binary). Consumers use `plugins.<name>.skills` to install through the plugin system, and wire up hooks/settings separately. See `examples/persist/`.
