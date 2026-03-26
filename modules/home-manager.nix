{ config, lib, pkgs, ... }:

let
  cfg = config.programs.claude-code.plugins;
  mkClaudeConfig = import ../lib/mkClaudeConfig.nix { inherit lib; };

  # Resolve plugin: flake inputs have a `plugin` attr keyed by system
  resolvePlugin = p:
    if p ? plugin then p.plugin.${pkgs.system}
    else p;

  resolvedPlugins = map resolvePlugin cfg;

  hasPlugins = cfg != [];

  configDrv = mkClaudeConfig {
    inherit pkgs;
    plugins = resolvedPlugins;
  };

  claudeDir = "${config.home.homeDirectory}/.claude";

  # Collect packages from all plugins
  pluginPackages = lib.concatMap (p:
    if p ? package && p.package != null then [ p.package ] else []
  ) resolvedPlugins;

  # Deep-merge settings from all plugins
  pluginSettings = map (p: p.settings or {}) resolvedPlugins;

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
    type = lib.types.listOf lib.types.attrs;
    default = [];
    description = ''
      Plugins to install for Claude Code. Each element is a plugin
      attrset with optional skills, settings, package, and src fields.
      Flake inputs with a `plugin` attr are resolved automatically.
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
