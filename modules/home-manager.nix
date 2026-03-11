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

  hasCommands = cfg.skills != [] || cfg.commands != [] || cfg.commandsDir != null;
  hasMemory = cfg.memory.fragments != [];
  hasMcpServers = cfg.mcpServers != {};
  hasSettings = cfg.settings != {};
in
{
  options.programs.claude-code = options;

  config = lib.mkIf cfg.enable {
    home.packages = lib.optional (cfg.package != null) cfg.package;

    home.activation.claudeCodeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Ensure ~/.claude/commands exists
      install -d -m 0755 "${claudeDir}/commands"

      ${lib.optionalString hasCommands ''
        # Clean managed commands directory and repopulate
        # Only remove files/dirs that came from nix-claude (tracked via marker)
        if [ -f "${claudeDir}/commands/.nix-claude-managed" ]; then
          while IFS= read -r managed; do
            rm -rf "${claudeDir}/commands/$managed"
          done < "${claudeDir}/commands/.nix-claude-managed"
        fi

        # Copy commands and skills from the derivation
        manifest=""
        for item in "${configDrv}/commands/"*; do
          name="$(basename "$item")"
          if [ -d "$item" ]; then
            rm -rf "${claudeDir}/commands/$name"
            cp -r "$item" "${claudeDir}/commands/$name"
            chmod -R u+w "${claudeDir}/commands/$name"
          else
            install -m 0644 "$item" "${claudeDir}/commands/$name"
          fi
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
