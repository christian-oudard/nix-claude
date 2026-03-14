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

  # Deep-merge settings from all plugins, plus enabledPlugins entries
  pluginSettings = lib.mapAttrsToList (_: pluginCfg: pluginCfg.settings) cfg;
  enabledPluginsSettings = {
    enabledPlugins = lib.mapAttrs' (name: _:
      lib.nameValuePair "${name}@nix-claude" true
    ) cfg;
  };

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
            Path to an existing plugin directory. When set, the directory is
            copied as-is into the plugin cache. The directory should contain
            .claude-plugin/plugin.json and any skills/, commands/, agents/.
            When set, description and skills options are ignored.
          '';
        };
        description = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Plugin description for plugin.json.";
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
      Plugins to install via the Claude Code plugin system.
      Each plugin is registered in installed_plugins.json under the
      nix-claude virtual marketplace, with its skills installed to
      the plugin cache directory.

      Use src to install a pre-built plugin directory (e.g. from
      claude-plugins-official). For settings, memory, skills, commands,
      and MCP servers, use home-manager's built-in options instead.
    '';
  };

  config = lib.mkIf hasPlugins {
    home.packages = pluginPackages;

    programs.claude-code.settings = lib.mkMerge (pluginSettings ++ [ enabledPluginsSettings ]);

    home.activation.nixClaudePlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${installWithManifest {
        targetDir = "${claudeDir}/plugins/cache/nix-claude";
        sourceDir = "${configDrv}/plugins/cache/nix-claude";
        copyCmd = ''
          rm -rf "${claudeDir}/plugins/cache/nix-claude/$name"
          cp -r "$item" "${claudeDir}/plugins/cache/nix-claude/$name"
          chmod -R u+w "${claudeDir}/plugins/cache/nix-claude/$name"
        '';
      }}

      # Merge installed_plugins.json: replace __PLUGINS_DIR__ placeholder, then merge
      nix_plugins="$(${pkgs.jq}/bin/jq --arg dir "${claudeDir}/plugins" \
        'walk(if type == "string" then gsub("__PLUGINS_DIR__"; $dir) else . end)' \
        "${configDrv}/plugins/installed_plugins.json")"

      if [ -f "${claudeDir}/plugins/installed_plugins.json" ]; then
        existing="$(cat "${claudeDir}/plugins/installed_plugins.json")"
        printf '%s\n%s' "$existing" "$nix_plugins" | \
          ${pkgs.jq}/bin/jq -s '
            .[0] as $existing | .[1] as $new |
            $existing * { plugins: ($existing.plugins // {} | to_entries | map(select(.key | endswith("@nix-claude") | not)) | from_entries) * $new.plugins }
          ' > "${claudeDir}/plugins/installed_plugins.json.tmp"
        mv "${claudeDir}/plugins/installed_plugins.json.tmp" "${claudeDir}/plugins/installed_plugins.json"
      else
        printf '%s' "$nix_plugins" > "${claudeDir}/plugins/installed_plugins.json"
      fi
    '';
  };
}
