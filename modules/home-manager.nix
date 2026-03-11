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
in
{
  options.programs.claude-code = options;

  config = lib.mkIf cfg.enable {
    home.packages = lib.optional (cfg.package != null) cfg.package;

    home.activation.claudeCodeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${lib.optionalString hasPlugins ''
        install -d -m 0755 "${claudeDir}/plugins/cache/nix-claude"

        # Clean previously managed plugins
        if [ -f "${claudeDir}/plugins/.nix-claude-managed" ]; then
          while IFS= read -r managed; do
            rm -rf "${claudeDir}/plugins/cache/nix-claude/$managed"
          done < "${claudeDir}/plugins/.nix-claude-managed"
        fi

        # Install plugin cache directories
        manifest=""
        for plugin in "${configDrv}/plugins/cache/nix-claude/"*; do
          name="$(basename "$plugin")"
          rm -rf "${claudeDir}/plugins/cache/nix-claude/$name"
          cp -r "$plugin" "${claudeDir}/plugins/cache/nix-claude/$name"
          chmod -R u+w "${claudeDir}/plugins/cache/nix-claude/$name"
          manifest="$manifest$name"$'\n'
        done
        printf '%s' "$manifest" > "${claudeDir}/plugins/.nix-claude-managed"

        # Merge installed_plugins.json
        # Replace __PLUGINS_DIR__ placeholder with actual path
        nix_plugins="$(${pkgs.jq}/bin/jq --arg dir "${claudeDir}/plugins" \
          'walk(if type == "string" then gsub("__PLUGINS_DIR__"; $dir) else . end)' \
          "${configDrv}/plugins/installed_plugins.json")"

        if [ -f "${claudeDir}/plugins/installed_plugins.json" ]; then
          # Merge: nix-claude entries override, existing non-nix-claude entries preserved
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

      ${lib.optionalString hasSkills ''
        install -d -m 0755 "${claudeDir}/skills"

        # Clean previously managed skills
        if [ -f "${claudeDir}/skills/.nix-claude-managed" ]; then
          while IFS= read -r managed; do
            rm -rf "${claudeDir}/skills/$managed"
          done < "${claudeDir}/skills/.nix-claude-managed"
        fi

        # Install skills from the derivation
        manifest=""
        for item in "${configDrv}/skills/"*; do
          name="$(basename "$item")"
          rm -rf "${claudeDir}/skills/$name"
          cp -r "$item" "${claudeDir}/skills/$name"
          chmod -R u+w "${claudeDir}/skills/$name"
          manifest="$manifest$name"$'\n'
        done
        printf '%s' "$manifest" > "${claudeDir}/skills/.nix-claude-managed"
      ''}

      ${lib.optionalString hasCommands ''
        install -d -m 0755 "${claudeDir}/commands"

        # Clean previously managed commands
        if [ -f "${claudeDir}/commands/.nix-claude-managed" ]; then
          while IFS= read -r managed; do
            rm -rf "${claudeDir}/commands/$managed"
          done < "${claudeDir}/commands/.nix-claude-managed"
        fi

        # Install commands from the derivation
        manifest=""
        for item in "${configDrv}/commands/"*; do
          name="$(basename "$item")"
          install -m 0644 "$item" "${claudeDir}/commands/$name"
          manifest="$manifest$name"$'\n'
        done
        printf '%s' "$manifest" > "${claudeDir}/commands/.nix-claude-managed"
      ''}

      ${lib.optionalString hasMemory ''
        install -m 0644 "${configDrv}/CLAUDE.md" "${claudeDir}/CLAUDE.md"
      ''}

      ${lib.optionalString hasSettings ''
        install -m 0644 "${configDrv}/settings.json" "${claudeDir}/settings.json"
      ''}

      ${lib.optionalString hasDotClaudeJson ''
        # Deep-merge nix-claude fields into ~/.claude.json
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
