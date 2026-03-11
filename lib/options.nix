{ lib }:

let
  inherit (lib) mkOption mkEnableOption types;
in
{
  mkClaudeCodeOptions = { defaultPackage ? null }: {
    enable = mkEnableOption "Claude Code configuration management";

    package = mkOption {
      type = types.nullOr types.package;
      default = defaultPackage;
      description = "Claude Code package to install. Set to null to skip installing the binary.";
    };

    plugins = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          description = mkOption {
            type = types.str;
            default = "";
            description = "Plugin description for plugin.json.";
          };
          skills = mkOption {
            type = types.listOf types.path;
            default = [];
            description = "Skill directories (containing SKILL.md) provided by this plugin.";
          };
        };
      });
      default = {};
      description = ''
        Plugins to install via the Claude Code plugin system.
        Each plugin is registered in installed_plugins.json under the
        nix-claude virtual marketplace, with its skills installed to
        the plugin cache directory.
      '';
    };

    skills = mkOption {
      type = types.listOf types.path;
      default = [];
      description = ''
        Bare skill paths installed directly to ~/.claude/skills/.
        For full plugin integration, use the plugins option instead.
        Each path should be a directory containing SKILL.md.
      '';
    };

    commands = mkOption {
      type = types.listOf types.path;
      default = [];
      description = "List of flat markdown command files to install.";
    };

    commandsDir = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Directory of .md files to bulk-import as commands.";
    };

    memory = {
      fragments = mkOption {
        type = types.listOf (types.either types.path types.str);
        default = [];
        description = ''
          List of fragments to concatenate into CLAUDE.md.
          Each fragment can be a path to a markdown file or an inline string.
        '';
      };

      separator = mkOption {
        type = types.str;
        default = "\n\n";
        description = "Separator inserted between memory fragments.";
      };
    };

    mcpServers = mkOption {
      type = types.attrsOf types.attrs;
      default = {};
      description = ''
        MCP server configurations. Each key is a server name, each value
        is an attrset with command, args, env, etc.
        Merged into ~/.claude.json under the mcpServers key.
      '';
    };

    skipOnboarding = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Skip Claude Code's first-run onboarding prompts.
        Sets hasCompletedOnboarding and effortCalloutDismissed in ~/.claude.json.
      '';
    };

    dotClaudeJson = mkOption {
      type = types.attrs;
      default = {};
      description = ''
        Arbitrary fields to deep-merge into ~/.claude.json.
        Use this for any .claude.json fields not covered by other options
        (e.g. theme, model preferences). mcpServers and skipOnboarding
        fields are merged automatically; you don't need to duplicate them here.
      '';
    };

    settings = mkOption {
      type = types.attrs;
      default = {};
      description = ''
        Settings written to ~/.claude/settings.json.
        If empty (default), the file is not managed.
      '';
    };
  };
}
