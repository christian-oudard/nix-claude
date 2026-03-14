{ config, lib, pkgs, ... }:

let
  cfg = config.programs.claude-code.plugins;
  mkClaudeConfig = import ../lib/mkClaudeConfig.nix { inherit lib; };

  hasPlugins = cfg != {};

  # Extract only the fields mkClaudeConfig expects (src, description, skills)
  pluginsForDrv = lib.mapAttrs (name: pluginCfg:
    if pluginCfg.src != null then {
      inherit (pluginCfg) src;
    } else {
      inherit (pluginCfg) description skills;
    }
  ) cfg;

  configDrv = mkClaudeConfig {
    inherit pkgs;
    plugins = pluginsForDrv;
  };

  claudeDir = "${config.home.homeDirectory}/.claude";

  # Collect packages from all plugins
  pluginPackages = lib.concatLists (lib.mapAttrsToList (_: pluginCfg:
    lib.optional (pluginCfg.package != null) pluginCfg.package
  ) cfg);

  # Deep-merge settings from all plugins
  pluginSettings = lib.mapAttrsToList (_: pluginCfg: pluginCfg.settings) cfg;

  # Manifest-based install: clean old entries, copy new ones, write manifest
  installWithManifest = { targetDir, sourceDir, copyCmd ? null }:
    let
      defaultCopy = ''
        if [ -d "$item" ]; then
          rm -rf "${targetDir}/$name"
          cp -r "$item" "${targetDir}/$name"
          chmod -R u+w "${targetDir}/$name"
        else
          install -m 0644 "$item" "${targetDir}/$name"
        fi
      '';
    in
    ''
      install -d -m 0755 "${targetDir}"
      if [ -f "${targetDir}/.nix-claude-managed" ]; then
        while IFS= read -r managed; do
          rm -rf "${targetDir}/$managed"
        done < "${targetDir}/.nix-claude-managed"
      fi
      manifest=""
      for item in "${sourceDir}/"*; do
        [ -e "$item" ] || continue
        name="$(basename "$item")"
        ${if copyCmd != null then copyCmd else defaultCopy}
        manifest="$manifest$name"$'\n'
      done
      printf '%s' "$manifest" > "${targetDir}/.nix-claude-managed"
    '';

in
{
  options.programs.claude-code.plugins = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        src = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Path to an existing plugin directory. When set, skills and commands
            are extracted and installed as bare skills/commands. The directory
            should contain skills/<name>/SKILL.md and/or commands/<name>.md.
            When set, description and skills options are ignored.
          '';
        };
        description = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Plugin description (used when building from components).";
        };
        skills = lib.mkOption {
          type = lib.types.listOf lib.types.path;
          default = [];
          description = "Skill directories (containing SKILL.md) provided by this plugin.";
        };
        package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
          description = "Optional package provided by this plugin, added to home.packages.";
        };
        settings = lib.mkOption {
          type = lib.types.attrs;
          default = {};
          description = ''
            Settings contributed by this plugin, deep-merged into
            programs.claude-code.settings. List values (like hooks.Stop)
            concatenate when merged from multiple sources.
          '';
        };
      };
    });
    default = {};
    description = ''
      Plugins to install for Claude Code. Skills are installed as bare
      skills to ~/.claude/skills/ (auto-discovered by Claude Code).
      Commands are installed to ~/.claude/commands/.

      Use src to install from a pre-built plugin directory (e.g. from
      claude-plugins-official). Skills and commands are extracted automatically.
    '';
  };

  config = lib.mkIf hasPlugins {
    home.packages = pluginPackages;

    programs.claude-code.settings = lib.mkMerge pluginSettings;

    home.activation.nixClaudePlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Install skills
      if [ -d "${configDrv}/skills" ]; then
        ${installWithManifest {
          targetDir = "${claudeDir}/skills";
          sourceDir = "${configDrv}/skills";
          copyCmd = ''
            rm -rf "${claudeDir}/skills/$name"
            cp -r "$item" "${claudeDir}/skills/$name"
            chmod -R u+w "${claudeDir}/skills/$name"
          '';
        }}
      fi

      # Install commands
      if [ -d "${configDrv}/commands" ]; then
        ${installWithManifest {
          targetDir = "${claudeDir}/commands";
          sourceDir = "${configDrv}/commands";
        }}
      fi

      # Clean up stale plugin cache from previous nix-claude versions
      rm -rf "${claudeDir}/plugins/cache/nix-claude"
      if [ -f "${claudeDir}/plugins/installed_plugins.json" ]; then
        ${pkgs.jq}/bin/jq 'if .plugins then .plugins |= with_entries(select(.key | endswith("@nix-claude") | not)) else . end' \
          "${claudeDir}/plugins/installed_plugins.json" > "${claudeDir}/plugins/installed_plugins.json.tmp"
        mv "${claudeDir}/plugins/installed_plugins.json.tmp" "${claudeDir}/plugins/installed_plugins.json"
      fi
    '';
  };
}
