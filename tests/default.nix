{ pkgs, lib, mkClaudeConfig }:

let
  fixtures = ./fixtures;

  # Helper to build a config and run assertions against it
  mkTest = name: { config, assertions }:
    let
      drv = mkClaudeConfig config;
    in
    pkgs.runCommand "nix-claude-test-${name}" {} ''
      ${lib.concatStringsSep "\n" (map (a: ''
        echo "  checking: ${a.description}"
        ${a.script}
      '') assertions)}

      echo "PASS: ${name}"
      touch $out
    '';

in
{
  skill-directory = mkTest "skill-directory" {
    config = {
      inherit pkgs;
      skills = [ "${fixtures}/test-skill" ];
    };
    assertions = [
      {
        description = "skill directory is created";
        script = ''test -d "${mkClaudeConfig { inherit pkgs; skills = [ "${fixtures}/test-skill" ]; }}/commands/test-skill"'';
      }
      {
        description = "SKILL.md is copied";
        script = ''test -f "${mkClaudeConfig { inherit pkgs; skills = [ "${fixtures}/test-skill" ]; }}/commands/test-skill/SKILL.md"'';
      }
    ];
  };

  flat-command = mkTest "flat-command" {
    config = {
      inherit pkgs;
      commands = [ "${fixtures}/test-command.md" ];
    };
    assertions = [
      {
        description = "command file is copied";
        script = ''test -f "${mkClaudeConfig { inherit pkgs; commands = [ "${fixtures}/test-command.md" ]; }}/commands/test-command.md"'';
      }
    ];
  };

  commands-dir = mkTest "commands-dir" {
    config = {
      inherit pkgs;
      commandsDir = "${fixtures}/commands-dir";
    };
    assertions = [
      {
        description = "alpha.md is copied";
        script = ''test -f "${mkClaudeConfig { inherit pkgs; commandsDir = "${fixtures}/commands-dir"; }}/commands/alpha.md"'';
      }
      {
        description = "beta.md is copied";
        script = ''test -f "${mkClaudeConfig { inherit pkgs; commandsDir = "${fixtures}/commands-dir"; }}/commands/beta.md"'';
      }
    ];
  };

  memory-fragments = mkTest "memory-fragments" {
    config = {
      inherit pkgs;
      memory.fragments = [
        "${fixtures}/fragment-a.md"
        "${fixtures}/fragment-b.md"
      ];
    };
    assertions = [
      {
        description = "CLAUDE.md exists";
        script = ''
          drv="${mkClaudeConfig { inherit pkgs; memory.fragments = [ "${fixtures}/fragment-a.md" "${fixtures}/fragment-b.md" ]; }}"
          test -f "$drv/CLAUDE.md"
        '';
      }
      {
        description = "CLAUDE.md contains both fragments";
        script = ''
          drv="${mkClaudeConfig { inherit pkgs; memory.fragments = [ "${fixtures}/fragment-a.md" "${fixtures}/fragment-b.md" ]; }}"
          grep -q "Fragment A" "$drv/CLAUDE.md"
          grep -q "Fragment B" "$drv/CLAUDE.md"
        '';
      }
    ];
  };

  memory-inline-strings = mkTest "memory-inline-strings" {
    config = {
      inherit pkgs;
      memory.fragments = [
        "Inline instruction one."
        "Inline instruction two."
      ];
    };
    assertions = [
      {
        description = "CLAUDE.md contains inline strings";
        script = ''
          drv="${mkClaudeConfig { inherit pkgs; memory.fragments = [ "Inline instruction one." "Inline instruction two." ]; }}"
          grep -q "Inline instruction one" "$drv/CLAUDE.md"
          grep -q "Inline instruction two" "$drv/CLAUDE.md"
        '';
      }
    ];
  };

  mcp-servers = mkTest "mcp-servers" {
    config = {
      inherit pkgs;
      mcpServers.test-server = {
        command = "/bin/test-server";
        args = [ "stdio" ];
      };
    };
    assertions = [
      {
        description = "mcp-servers.json exists";
        script = ''
          drv="${mkClaudeConfig { inherit pkgs; mcpServers.test-server = { command = "/bin/test-server"; args = [ "stdio" ]; }; }}"
          test -f "$drv/mcp-servers.json"
        '';
      }
      {
        description = "mcp-servers.json contains server config";
        script = ''
          drv="${mkClaudeConfig { inherit pkgs; mcpServers.test-server = { command = "/bin/test-server"; args = [ "stdio" ]; }; }}"
          ${pkgs.jq}/bin/jq -e '.mcpServers["test-server"].command == "/bin/test-server"' "$drv/mcp-servers.json"
        '';
      }
    ];
  };

  settings = mkTest "settings" {
    config = {
      inherit pkgs;
      settings = {
        permissions.allow = [ "Bash" "Read" ];
      };
    };
    assertions = [
      {
        description = "settings.json exists";
        script = ''
          drv="${mkClaudeConfig { inherit pkgs; settings = { permissions.allow = [ "Bash" "Read" ]; }; }}"
          test -f "$drv/settings.json"
        '';
      }
      {
        description = "settings.json has correct content";
        script = ''
          drv="${mkClaudeConfig { inherit pkgs; settings = { permissions.allow = [ "Bash" "Read" ]; }; }}"
          ${pkgs.jq}/bin/jq -e '.permissions.allow | length == 2' "$drv/settings.json"
        '';
      }
    ];
  };

  empty-config = mkTest "empty-config" {
    config = { inherit pkgs; };
    assertions = [
      {
        description = "empty config produces output dir";
        script = ''test -d "${mkClaudeConfig { inherit pkgs; }}"'';
      }
      {
        description = "no CLAUDE.md when no fragments";
        script = ''! test -f "${mkClaudeConfig { inherit pkgs; }}/CLAUDE.md"'';
      }
      {
        description = "no settings.json when no settings";
        script = ''! test -f "${mkClaudeConfig { inherit pkgs; }}/settings.json"'';
      }
      {
        description = "no mcp-servers.json when no servers";
        script = ''! test -f "${mkClaudeConfig { inherit pkgs; }}/mcp-servers.json"'';
      }
    ];
  };

  full-config = mkTest "full-config" {
    config = {
      inherit pkgs;
      skills = [ "${fixtures}/test-skill" ];
      commands = [ "${fixtures}/test-command.md" ];
      commandsDir = "${fixtures}/commands-dir";
      memory.fragments = [
        "${fixtures}/fragment-a.md"
        "Inline fragment."
      ];
      mcpServers.github = {
        command = "/bin/github-mcp";
        args = [ "stdio" ];
      };
      settings.permissions.allow = [ "Bash" ];
    };
    assertions = [
      {
        description = "skill installed";
        script = ''
          drv="${mkClaudeConfig {
            inherit pkgs;
            skills = [ "${fixtures}/test-skill" ];
            commands = [ "${fixtures}/test-command.md" ];
            commandsDir = "${fixtures}/commands-dir";
            memory.fragments = [ "${fixtures}/fragment-a.md" "Inline fragment." ];
            mcpServers.github = { command = "/bin/github-mcp"; args = [ "stdio" ]; };
            settings.permissions.allow = [ "Bash" ];
          }}"
          test -f "$drv/commands/test-skill/SKILL.md"
          test -f "$drv/commands/test-command.md"
          test -f "$drv/commands/alpha.md"
          test -f "$drv/commands/beta.md"
          test -f "$drv/CLAUDE.md"
          test -f "$drv/mcp-servers.json"
          test -f "$drv/settings.json"
        '';
      }
    ];
  };
}
