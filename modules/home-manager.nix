{ config, lib, pkgs, ... }:

let
  cfg = config.programs.claude-code;
  options = (import ../lib/options.nix { inherit lib; }).mkClaudeCodeOptions {};
  mkClaudeConfig = import ../lib/mkClaudeConfig.nix { inherit lib; };

  configDrv = mkClaudeConfig {
    inherit pkgs;
    inherit (cfg) skills commands commandsDir mcpServers settings;
    memory = {
      inherit (cfg.memory) fragments separator;
    };
  };

  claudeDir = "${config.home.homeDirectory}/.claude";
  claudeJson = "${config.home.homeDirectory}/.claude.json";

  hasSkills = cfg.skills != [];
  hasCommands = cfg.commands != [] || cfg.commandsDir != null;
  hasMemory = cfg.memory.fragments != [];
  hasMcpServers = cfg.mcpServers != {};
  hasSettings = cfg.settings != {};
in
{
  options.programs.claude-code = options;

  config = lib.mkIf cfg.enable {
    home.packages = lib.optional (cfg.package != null) cfg.package;

    home.activation.claudeCodeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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

      ${lib.optionalString hasMcpServers ''
        # Merge mcpServers into ~/.claude.json
        if [ -f "${claudeJson}" ]; then
          ${pkgs.jq}/bin/jq -s '.[0] * .[1]' \
            "${claudeJson}" \
            "${configDrv}/mcp-servers.json" \
            > "${claudeJson}.tmp"
          mv "${claudeJson}.tmp" "${claudeJson}"
        else
          install -m 0644 "${configDrv}/mcp-servers.json" "${claudeJson}"
        fi
      ''}
    '';
  };
}
