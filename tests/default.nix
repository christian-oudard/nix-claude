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
      plugins = [{
        skills = [ "${fixtures}/test-skill" ];
      }];
    }; in
    mkTest "plugin-install" {
      inherit drv;
      script = ''
        # Skills installed as bare skills
        test -d "${drv}/skills/test-skill"
        test -f "${drv}/skills/test-skill/SKILL.md"
        # No plugin cache or installed_plugins.json
        ! test -d "${drv}/plugins"
      '';
    };

  plugin-src =
    let drv = mkClaudeConfig {
      inherit pkgs;
      plugins = [{
        src = "${fixtures}/src-plugin";
      }];
    }; in
    mkTest "plugin-src" {
      inherit drv;
      script = ''
        # Skills extracted from src to bare skills
        test -d "${drv}/skills/my-skill"
        test -f "${drv}/skills/my-skill/SKILL.md"
        # Commands extracted from src
        test -f "${drv}/commands/my-command.md"
        # No plugin cache or installed_plugins.json
        ! test -d "${drv}/plugins"
      '';
    };

  plugin-flake-input =
    let
      # Simulate a flake input with a `plugin` attr
      fakeFlakeInput = {
        plugin.${pkgs.stdenv.hostPlatform.system} = {
          skills = [ "${fixtures}/test-skill" ];
        };
      };
      drv = mkClaudeConfig {
        inherit pkgs;
        plugins = [ fakeFlakeInput ];
      };
    in
    mkTest "plugin-flake-input" {
      inherit drv;
      script = ''
        test -d "${drv}/skills/test-skill"
        test -f "${drv}/skills/test-skill/SKILL.md"
      '';
    };

  hash-stripping =
    let
      skillDir = pkgs.runCommand "test-skill" {} ''
        mkdir -p $out
        echo "# Hash-stripped skill" > $out/SKILL.md
      '';
      drv = mkClaudeConfig {
        inherit pkgs;
        plugins = [{ skills = [ skillDir ]; }];
      };
    in
    mkTest "hash-stripping" {
      inherit drv;
      script = ''
        # Store path hash prefix should be stripped: "abc123-test-skill" -> "test-skill"
        test -d "${drv}/skills/test-skill"
        test -f "${drv}/skills/test-skill/SKILL.md"
        grep -q "Hash-stripped skill" "${drv}/skills/test-skill/SKILL.md"
      '';
    };

  statusline =
    let drv = mkClaudeConfig {
      inherit pkgs;
      statusline = "#!/bin/bash\nread -r input\necho custom";
    }; in
    mkTest "statusline" {
      inherit drv;
      script = ''
        test -f "${drv}/statusline.sh"
        test -x "${drv}/statusline.sh"
        grep -q "custom" "${drv}/statusline.sh"
      '';
    };

  plugin-packages =
    let
      fakePkg = pkgs.runCommand "my-tool" {} ''
        mkdir -p $out/bin
        echo "#!/bin/sh" > $out/bin/my-tool
        chmod +x $out/bin/my-tool
      '';
      drv = mkClaudeConfig {
        inherit pkgs;
        plugins = [{
          skills = [ "${fixtures}/test-skill" ];
          package = fakePkg;
        }];
      };
    in
    mkTest "plugin-packages" {
      inherit drv;
      script = ''
        test -d "${drv}/packages"
        test -L "${drv}/packages/my-tool"
        test -x "${drv}/packages/my-tool/bin/my-tool"
      '';
    };

  plugin-settings =
    let drv = mkClaudeConfig {
      inherit pkgs;
      plugins = [{
        settings.hooks.Stop = [{ hooks = [{ type = "command"; command = "persist hook"; }]; }];
      }];
      settings.model = "opus";
    }; in
    mkTest "plugin-settings" {
      inherit drv;
      script = ''
        test -f "${drv}/settings.json"
        # Plugin settings merged in
        ${pkgs.jq}/bin/jq -e '.hooks.Stop | length == 1' "${drv}/settings.json"
        # User settings override plugin settings
        ${pkgs.jq}/bin/jq -e '.model == "opus"' "${drv}/settings.json"
      '';
    };

  plugin-settings-list-concat =
    let drv = mkClaudeConfig {
      inherit pkgs;
      plugins = [{
        settings.hooks.Stop = [{ hooks = [{ type = "command"; command = "persist hook"; }]; }];
      }];
      settings.hooks.Stop = [{ hooks = [{ type = "command"; command = "user hook"; }]; }];
    }; in
    mkTest "plugin-settings-list-concat" {
      inherit drv;
      script = ''
        # Both plugin and user hooks present (concatenated, not clobbered)
        ${pkgs.jq}/bin/jq -e '.hooks.Stop | length == 2' "${drv}/settings.json"
        ${pkgs.jq}/bin/jq -e '.hooks.Stop[0].hooks[0].command == "persist hook"' "${drv}/settings.json"
        ${pkgs.jq}/bin/jq -e '.hooks.Stop[1].hooks[0].command == "user hook"' "${drv}/settings.json"
      '';
    };

  plugin-settings-override =
    let drv = mkClaudeConfig {
      inherit pkgs;
      plugins = [{
        settings.model = "sonnet";
      }];
      settings.model = "opus";
    }; in
    mkTest "plugin-settings-override" {
      inherit drv;
      script = ''
        # User settings take precedence over plugin settings
        ${pkgs.jq}/bin/jq -e '.model == "opus"' "${drv}/settings.json"
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
        ! test -f "${drv}/statusline.sh"
      '';
    };

  full-config =
    let drv = mkClaudeConfig {
      inherit pkgs;
      plugins = [{
        skills = [ "${fixtures}/test-skill" ];
      }];
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
        # Plugin skills as bare skills
        test -d "${drv}/skills/test-skill"
        test -f "${drv}/skills/test-skill/SKILL.md"
        # No plugin cache
        ! test -d "${drv}/plugins"
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
