{ config, lib, pkgs, ... }:

let
  cfg = config.programs.claude-code;
  options = (import ../lib/options.nix { inherit lib; }).mkClaudeCodeOptions {};
  mkClaudeConfig = import ../lib/mkClaudeConfig.nix { inherit lib; };

  configDrv = mkClaudeConfig {
    inherit pkgs;
    inherit (cfg) plugins skills commands commandsDir mcpServers settings skipOnboarding dotClaudeJson;
    memory = {
      inherit (cfg.memory) fragments separator;
    };
  };

  claudeDir = "${config.home.homeDirectory}/.claude";
  claudeJson = "${config.home.homeDirectory}/.claude.json";

  hasPlugins = cfg.plugins != {};
  hasSkills = cfg.skills != [];
  hasCommands = cfg.commands != [] || cfg.commandsDir != null;
  hasMemory = cfg.memory.fragments != [];
  hasDotClaudeJson = cfg.mcpServers != {} || cfg.skipOnboarding || cfg.dotClaudeJson != {};
  hasSettings = cfg.settings != {};

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
  options.programs.claude-code = options;

  config = lib.mkIf cfg.enable {
    home.packages = lib.optional (cfg.package != null) cfg.package;

    home.activation.claudeCodeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${lib.optionalString hasPlugins ''
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
      ''}

      ${lib.optionalString hasSkills (installWithManifest {
        targetDir = "${claudeDir}/skills";
        sourceDir = "${configDrv}/skills";
      })}

      ${lib.optionalString hasCommands (installWithManifest {
        targetDir = "${claudeDir}/commands";
        sourceDir = "${configDrv}/commands";
      })}

      ${lib.optionalString hasMemory ''
        install -m 0644 "${configDrv}/CLAUDE.md" "${claudeDir}/CLAUDE.md"
      ''}

      ${lib.optionalString hasSettings ''
        install -m 0644 "${configDrv}/settings.json" "${claudeDir}/settings.json"
      ''}

      ${lib.optionalString hasDotClaudeJson ''
        if [ -f "${claudeJson}" ]; then
          ${pkgs.jq}/bin/jq -s '.[0] * .[1]' \
            "${claudeJson}" \
            "${configDrv}/dot-claude.json" \
            > "${claudeJson}.tmp"
          mv "${claudeJson}.tmp" "${claudeJson}"
        else
          install -m 0644 "${configDrv}/dot-claude.json" "${claudeJson}"
        fi
      ''}
    '';
  };
}
