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
- Plugin skills go in `~/.claude/skills/`. Commands go in `~/.claude/commands/`.
- `~/.claude.json` is mutable at runtime (Claude writes onboarding state, etc). nix-claude deep-merges its fields (mcpServers, skipOnboarding, dotClaudeJson) via jq.
- `~/.claude/settings.json` is NOT mutable at runtime. Written wholesale when `settings` is non-empty.

## Testing

Run `nix flake check` to execute all tests. Tests build real derivations and verify file presence/content. No network access needed.

## Plugin convention

Plugin flakes export `plugin.${system}` (an attrset with `skills`, `settings`, `package`). Consumers pass plugin flake inputs directly in the `plugins` list. nix-claude resolves the `plugin` attr automatically. See `examples/persist/`.
