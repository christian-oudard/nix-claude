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
        script = ''test -d "${mkClaudeConfig { inherit pkgs; skills = [ "${fixtures}/test-skill" ]; }}/skills/test-skill"'';
      }
      {
        description = "SKILL.md is copied";
        script = ''test -f "${mkClaudeConfig { inherit pkgs; skills = [ "${fixtures}/test-skill" ]; }}/skills/test-skill/SKILL.md"'';
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
    assertions =
      let drv = mkClaudeConfig { inherit pkgs; mcpServers.test-server = { command = "/bin/test-server"; args = [ "stdio" ]; }; }; in
      [
        {
          description = "dot-claude.json exists";
          script = ''test -f "${drv}/dot-claude.json"'';
        }
        {
          description = "dot-claude.json contains server config";
          script = ''${pkgs.jq}/bin/jq -e '.mcpServers["test-server"].command == "/bin/test-server"' "${drv}/dot-claude.json"'';
        }
      ];
  };

  skip-onboarding = mkTest "skip-onboarding" {
    config = {
      inherit pkgs;
      skipOnboarding = true;
    };
    assertions =
      let drv = mkClaudeConfig { inherit pkgs; skipOnboarding = true; }; in
      [
        {
          description = "dot-claude.json exists";
          script = ''test -f "${drv}/dot-claude.json"'';
        }
        {
          description = "hasCompletedOnboarding is true";
          script = ''${pkgs.jq}/bin/jq -e '.hasCompletedOnboarding == true' "${drv}/dot-claude.json"'';
        }
        {
          description = "effortCalloutDismissed is true";
          script = ''${pkgs.jq}/bin/jq -e '.effortCalloutDismissed == true' "${drv}/dot-claude.json"'';
        }
      ];
  };

  dot-claude-json = mkTest "dot-claude-json" {
    config = {
      inherit pkgs;
      skipOnboarding = true;
      mcpServers.test = { command = "/bin/test"; };
      dotClaudeJson = { theme = "dark"; };
    };
    assertions =
      let drv = mkClaudeConfig {
        inherit pkgs;
        skipOnboarding = true;
        mcpServers.test = { command = "/bin/test"; };
        dotClaudeJson = { theme = "dark"; };
      }; in
      [
        {
          description = "all sources merged into dot-claude.json";
          script = ''
            ${pkgs.jq}/bin/jq -e '.hasCompletedOnboarding == true' "${drv}/dot-claude.json"
            ${pkgs.jq}/bin/jq -e '.mcpServers.test.command == "/bin/test"' "${drv}/dot-claude.json"
            ${pkgs.jq}/bin/jq -e '.theme == "dark"' "${drv}/dot-claude.json"
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

  plugin-install = mkTest "plugin-install" {
    config = {
      inherit pkgs;
      plugins.test-plugin = {
        description = "A test plugin";
        skills = [ "${fixtures}/test-skill" ];
      };
    };
    assertions =
      let drv = mkClaudeConfig {
        inherit pkgs;
        plugins.test-plugin = {
          description = "A test plugin";
          skills = [ "${fixtures}/test-skill" ];
        };
      }; in
      [
        {
          description = "plugin cache directory exists";
          script = ''test -d "${drv}/plugins/cache/nix-claude/test-plugin"'';
        }
        {
          description = "plugin.json exists";
          script = ''
            found=$(find "${drv}/plugins/cache/nix-claude/test-plugin" -name plugin.json)
            test -n "$found"
          '';
        }
        {
          description = "plugin.json has correct name";
          script = ''
            found=$(find "${drv}/plugins/cache/nix-claude/test-plugin" -name plugin.json)
            ${pkgs.jq}/bin/jq -e '.name == "test-plugin"' "$found"
          '';
        }
        {
          description = "plugin.json has correct description";
          script = ''
            found=$(find "${drv}/plugins/cache/nix-claude/test-plugin" -name plugin.json)
            ${pkgs.jq}/bin/jq -e '.description == "A test plugin"' "$found"
          '';
        }
        {
          description = "skill is inside plugin cache";
          script = ''
            found=$(find "${drv}/plugins/cache/nix-claude/test-plugin" -name SKILL.md)
            test -n "$found"
          '';
        }
        {
          description = "installed_plugins.json exists";
          script = ''test -f "${drv}/plugins/installed_plugins.json"'';
        }
        {
          description = "installed_plugins.json has nix-claude marketplace entry";
          script = ''
            ${pkgs.jq}/bin/jq -e '.plugins["test-plugin@nix-claude"]' "${drv}/plugins/installed_plugins.json"
          '';
        }
        {
          description = "installed_plugins.json has version 2";
          script = ''
            ${pkgs.jq}/bin/jq -e '.version == 2' "${drv}/plugins/installed_plugins.json"
          '';
        }
        {
          description = "entry has user scope";
          script = ''
            ${pkgs.jq}/bin/jq -e '.plugins["test-plugin@nix-claude"][0].scope == "user"' "${drv}/plugins/installed_plugins.json"
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
        description = "no dot-claude.json when no servers";
        script = ''! test -f "${mkClaudeConfig { inherit pkgs; }}/dot-claude.json"'';
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
          test -f "$drv/skills/test-skill/SKILL.md"
          test -f "$drv/commands/test-command.md"
          test -f "$drv/commands/alpha.md"
          test -f "$drv/commands/beta.md"
          test -f "$drv/CLAUDE.md"
          test -f "$drv/dot-claude.json"
          test -f "$drv/settings.json"
        '';
      }
    ];
  };
}
