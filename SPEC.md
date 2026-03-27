# nix-claude -- Specification

Declarative configuration for Claude Code via Nix.

## Problem

Claude Code's configuration is scattered across multiple files and formats (`~/.claude/skills/`, `~/.claude/commands/`, `~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.claude.json`). Setting up a Claude Code environment means manually copying files, editing JSON, and hoping nothing drifts. With multiple machines or sandboxed environments, this becomes untenable.

## Scope

nix-claude manages configuration and extensions. It does not package the Claude Code binary or MCP server binaries.

**Manages:**

- Plugin skills, commands, packages, and settings
- Skills (directory-based, each containing SKILL.md)
- Commands (flat markdown files)
- CLAUDE.md (persistent instructions, composable from fragments)
- MCP server configuration (in `~/.claude.json`)
- Settings (in `~/.claude/settings.json`)

**Does not manage:**

- The Claude Code binary (use `claude-code-nix` or nixpkgs)
- MCP server binaries (use `mcps.nix`, nixpkgs, or your own derivations)
- Multi-account management (use `claude-env` if needed)
- Runtime state (conversations, OAuth tokens, `.claude.json` fields Claude writes itself)
- Per-project config (team-managed, committed to git)
- Authentication (tokens flow through environment variables or the system keychain, never through the Nix store)

## Interfaces

nix-claude provides three interfaces to the same underlying capability:

**`lib.mkClaudeConfig`** -- Pure function producing a derivation. Does not touch `~/.claude/`. Supports the full configuration surface: plugins, skills, commands, memory fragments, MCP servers, settings, statusline, and arbitrary `.claude.json` fields. Consumers decide how to install the output.

**Home-manager module** -- Plugins only. Works alongside the built-in `programs.claude-code` module, which handles settings, memory, commands, skills, MCP servers, and the Claude Code package. nix-claude adds a `plugins` option and integrates plugin outputs into the built-in module's options.

## Plugins

A plugin is an attrset that can contain skills, a package, settings, and optionally a pre-built source directory. Plugins are the primary extension mechanism.

Plugin flakes export a `plugin.<system>` attrset that bundles everything a consumer needs (skills, package, settings). Consumers pass plugin flake inputs directly in the `plugins` list, and nix-claude resolves the `plugin` attr automatically.

### Plugin composition

- Plugin settings are deep-merged. User settings override plugin settings. Later plugins override earlier ones.
- Plugin skills are installed as bare skill directories in `~/.claude/skills/`.
- Plugin packages are collected and made available on PATH (via `home.packages` for home-manager, via `$out/packages/` for standalone).
- List-typed settings (like hooks) concatenate when merged from multiple sources, so plugin hooks and user hooks coexist.

### Pre-built plugins

When a plugin provides a `src` directory, skills and commands are extracted from it directly. This supports installing pre-built plugin directories without enumerating individual skills.

## Key constraints

- **No symlinks.** Claude Code cannot read symlinked config files. All installation copies files.
- **`~/.claude.json` is mutable at runtime.** Claude writes onboarding state and other fields to this file. nix-claude deep-merges its fields (`mcpServers`, `skipOnboarding`, arbitrary fields) rather than replacing the file.
- **`~/.claude/settings.json` is not mutable at runtime.** Written wholesale when settings are provided. Empty settings means the file is unmanaged.
- **`skipOnboarding` is separate from `settings`.** It writes to `~/.claude.json` (runtime state file), not `settings.json`. Claude Code checks `hasCompletedOnboarding` in the runtime JSON, not in settings.
- **CLAUDE.md is composed from fragments.** Multiple sources can contribute instructions without conflicting. Fragments are concatenated in order.
- **Managed files are tracked for cleanup.** When a skill or command is removed from the Nix config, the next activation deletes it. User-added files outside the managed set are preserved.

## Design decisions

### Skills use bare skill directories

Skills are installed as bare directories containing SKILL.md, which Claude Code auto-discovers. This is simpler and more reliable than the plugin cache system, which requires a recognized marketplace.

### Home-manager module is plugins-only

The built-in `programs.claude-code` module already handles settings, memory, commands, skills, MCP servers, and the package. nix-claude only adds the plugin concept, avoiding duplicate options and composing cleanly with upstream.

### Skills and commands are separate

Claude Code distinguishes `~/.claude/skills/<name>/SKILL.md` (directory-based skills) from `~/.claude/commands/<name>.md` (flat markdown commands). nix-claude preserves this distinction.

## Relationship to other projects

- **claude-code-nix**: provides the Claude Code binary. nix-claude uses it as the default package but doesn't depend on it.
- **mcps.nix**: complementary. Both write to `programs.claude-code` options and compose via home-manager option merging.
- **claude-env**: orthogonal. Manages which config directory Claude uses, not what's in it.
