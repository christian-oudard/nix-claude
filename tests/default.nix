{ pkgs, lib, mkClaudeConfig }:

let
  fixtures = ./fixtures;

  mkTest = name: { drv, script }:
    pkgs.runCommand "nix-claude-test-${name}" { inherit drv; } ''
      echo "TEST: ${name}"
      ${script}
      echo "PASS: ${name}"
      touch $out
    '';

in
{
  skill-directory =
    let drv = mkClaudeConfig { inherit pkgs; skills = [ "${fixtures}/test-skill" ]; }; in
    mkTest "skill-directory" {
      inherit drv;
      script = ''
        test -d "${drv}/skills/test-skill"
        test -f "${drv}/skills/test-skill/SKILL.md"
      '';
    };

  flat-command =
    let drv = mkClaudeConfig { inherit pkgs; commands = [ "${fixtures}/test-command.md" ]; }; in
    mkTest "flat-command" {
      inherit drv;
      script = ''test -f "${drv}/commands/test-command.md"'';
    };

  commands-dir =
    let drv = mkClaudeConfig { inherit pkgs; commandsDir = "${fixtures}/commands-dir"; }; in
    mkTest "commands-dir" {
      inherit drv;
      script = ''
        test -f "${drv}/commands/alpha.md"
        test -f "${drv}/commands/beta.md"
      '';
    };

  memory-fragments =
    let drv = mkClaudeConfig {
      inherit pkgs;
      memory.fragments = [ "${fixtures}/fragment-a.md" "${fixtures}/fragment-b.md" ];
    }; in
    mkTest "memory-fragments" {
      inherit drv;
      script = ''
        test -f "${drv}/CLAUDE.md"
        grep -q "Fragment A" "${drv}/CLAUDE.md"
        grep -q "Fragment B" "${drv}/CLAUDE.md"
      '';
    };

  memory-inline-strings =
    let drv = mkClaudeConfig {
      inherit pkgs;
      memory.fragments = [ "Inline instruction one." "Inline instruction two." ];
    }; in
    mkTest "memory-inline-strings" {
      inherit drv;
      script = ''
        grep -q "Inline instruction one" "${drv}/CLAUDE.md"
        grep -q "Inline instruction two" "${drv}/CLAUDE.md"
      '';
    };

  mcp-servers =
    let drv = mkClaudeConfig {
      inherit pkgs;
      mcpServers.test-server = { command = "/bin/test-server"; args = [ "stdio" ]; };
    }; in
    mkTest "mcp-servers" {
      inherit drv;
      script = ''
        test -f "${drv}/dot-claude.json"
        ${pkgs.jq}/bin/jq -e '.mcpServers["test-server"].command == "/bin/test-server"' "${drv}/dot-claude.json"
      '';
    };

  skip-onboarding =
    let drv = mkClaudeConfig { inherit pkgs; skipOnboarding = true; }; in
    mkTest "skip-onboarding" {
      inherit drv;
      script = ''
        test -f "${drv}/dot-claude.json"
        ${pkgs.jq}/bin/jq -e '.hasCompletedOnboarding == true' "${drv}/dot-claude.json"
        ${pkgs.jq}/bin/jq -e '.effortCalloutDismissed == true' "${drv}/dot-claude.json"
      '';
    };

  dot-claude-json =
    let drv = mkClaudeConfig {
      inherit pkgs;
      skipOnboarding = true;
      mcpServers.test = { command = "/bin/test"; };
      dotClaudeJson = { theme = "dark"; };
    }; in
    mkTest "dot-claude-json" {
      inherit drv;
      script = ''
        ${pkgs.jq}/bin/jq -e '.hasCompletedOnboarding == true' "${drv}/dot-claude.json"
        ${pkgs.jq}/bin/jq -e '.mcpServers.test.command == "/bin/test"' "${drv}/dot-claude.json"
        ${pkgs.jq}/bin/jq -e '.theme == "dark"' "${drv}/dot-claude.json"
      '';
    };

  settings =
    let drv = mkClaudeConfig {
      inherit pkgs;
      settings.permissions.allow = [ "Bash" "Read" ];
    }; in
    mkTest "settings" {
      inherit drv;
      script = ''
        test -f "${drv}/settings.json"
        ${pkgs.jq}/bin/jq -e '.permissions.allow | length == 2' "${drv}/settings.json"
      '';
    };

  plugin-install =
    let drv = mkClaudeConfig {
      inherit pkgs;
      plugins.test-plugin = {
        description = "A test plugin";
        skills = [ "${fixtures}/test-skill" ];
      };
    }; in
    mkTest "plugin-install" {
      inherit drv;
      script = ''
        test -d "${drv}/plugins/cache/nix-claude/test-plugin"
        found=$(find "${drv}/plugins/cache/nix-claude/test-plugin" -name plugin.json)
        test -n "$found"
        ${pkgs.jq}/bin/jq -e '.name == "test-plugin"' "$found"
        ${pkgs.jq}/bin/jq -e '.description == "A test plugin"' "$found"
        found=$(find "${drv}/plugins/cache/nix-claude/test-plugin" -name SKILL.md)
        test -n "$found"
        test -f "${drv}/plugins/installed_plugins.json"
        ${pkgs.jq}/bin/jq -e '.version == 2' "${drv}/plugins/installed_plugins.json"
        ${pkgs.jq}/bin/jq -e '.plugins["test-plugin@nix-claude"][0].scope == "user"' "${drv}/plugins/installed_plugins.json"
      '';
    };

  plugin-src =
    let drv = mkClaudeConfig {
      inherit pkgs;
      plugins.src-plugin = {
        src = "${fixtures}/src-plugin";
      };
    }; in
    mkTest "plugin-src" {
      inherit drv;
      script = ''
        # Plugin directory exists in cache
        test -d "${drv}/plugins/cache/nix-claude/src-plugin"
        # plugin.json was copied from src
        found=$(find "${drv}/plugins/cache/nix-claude/src-plugin" -name plugin.json)
        test -n "$found"
        ${pkgs.jq}/bin/jq -e '.name == "src-plugin"' "$found"
        ${pkgs.jq}/bin/jq -e '.description == "A plugin installed from src"' "$found"
        # Commands were copied
        found=$(find "${drv}/plugins/cache/nix-claude/src-plugin" -name my-command.md)
        test -n "$found"
        # Skills were copied
        found=$(find "${drv}/plugins/cache/nix-claude/src-plugin" -path "*/skills/my-skill/SKILL.md")
        test -n "$found"
        # Registered in installed_plugins.json
        test -f "${drv}/plugins/installed_plugins.json"
        ${pkgs.jq}/bin/jq -e '.plugins["src-plugin@nix-claude"][0].scope == "user"' "${drv}/plugins/installed_plugins.json"
      '';
    };

  empty-config =
    let drv = mkClaudeConfig { inherit pkgs; }; in
    mkTest "empty-config" {
      inherit drv;
      script = ''
        test -d "${drv}"
        ! test -f "${drv}/CLAUDE.md"
        ! test -f "${drv}/settings.json"
        ! test -f "${drv}/dot-claude.json"
      '';
    };

  full-config =
    let drv = mkClaudeConfig {
      inherit pkgs;
      plugins.test-plugin = {
        description = "Full config test plugin";
        skills = [ "${fixtures}/test-skill" ];
      };
      commands = [ "${fixtures}/test-command.md" ];
      commandsDir = "${fixtures}/commands-dir";
      memory.fragments = [ "${fixtures}/fragment-a.md" "Inline fragment." ];
      mcpServers.github = { command = "/bin/github-mcp"; args = [ "stdio" ]; };
      skipOnboarding = true;
      settings.permissions.allow = [ "Bash" ];
    }; in
    mkTest "full-config" {
      inherit drv;
      script = ''
        # Plugin
        test -f "${drv}/plugins/installed_plugins.json"
        found=$(find "${drv}/plugins/cache/nix-claude/test-plugin" -name SKILL.md)
        test -n "$found"
        # Commands
        test -f "${drv}/commands/test-command.md"
        test -f "${drv}/commands/alpha.md"
        test -f "${drv}/commands/beta.md"
        # Memory
        test -f "${drv}/CLAUDE.md"
        grep -q "Fragment A" "${drv}/CLAUDE.md"
        grep -q "Inline fragment" "${drv}/CLAUDE.md"
        # dot-claude.json
        ${pkgs.jq}/bin/jq -e '.hasCompletedOnboarding == true' "${drv}/dot-claude.json"
        ${pkgs.jq}/bin/jq -e '.mcpServers.github.command == "/bin/github-mcp"' "${drv}/dot-claude.json"
        # Settings
        ${pkgs.jq}/bin/jq -e '.permissions.allow | length == 1' "${drv}/settings.json"
      '';
    };
}
