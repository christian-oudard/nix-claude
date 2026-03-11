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

    skills = mkOption {
      type = types.listOf types.path;
      default = [];
      description = ''
        List of skill paths. Each path should be either:
        - A directory containing SKILL.md (installed as a directory-based skill)
        - A file (installed as a flat command)
        The directory/file name becomes the slash command name.
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
