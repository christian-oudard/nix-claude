# nix-claude

Declarative Claude Code configuration via Nix. Pure Nix -- no runtime dependencies beyond nixpkgs.

## Structure

- `lib/mkClaudeConfig.nix` -- core function: takes `{ pkgs, skills, commands, ... }`, returns a derivation
- `lib/options.nix` -- shared NixOS/home-manager option type definitions
- `modules/home-manager.nix` -- home-manager module using `programs.claude-code` namespace
- `tests/default.nix` -- nix flake checks (run with `nix flake check`)
- `examples/persist/` -- real-world plugin installation example

## Key constraints

- Claude Code cannot read symlinked files. All installation uses `cp`/`install`, never symlinks.
- Skills go in `~/.claude/skills/<name>/SKILL.md`. Commands go in `~/.claude/commands/<name>.md`. These are separate directories.
- `~/.claude.json` is mutable at runtime (Claude writes onboarding state, etc). MCP servers are deep-merged via jq, not replaced.
- `~/.claude/settings.json` is NOT mutable at runtime. Written wholesale when `settings` is non-empty.

## Testing

Run `nix flake check` to execute all tests. Tests build real derivations and verify file presence/content. No network access needed.

## Plugin convention

Plugin flakes export `skills.<name>` (paths to directories with SKILL.md) and `packages.<system>.default` (the binary). Consumers wire up hooks/settings. See `examples/persist/`.
