{ pkgs, lib, mkClaudeConfig, build }:

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
        plugin.${pkgs.system} = {
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

  # lib.build tests

  build-empty =
    let drv = build { inherit pkgs; }; in
    mkTest "build-empty" {
      inherit drv;
      script = ''
        test -f "${drv}/settings.json"
        ${pkgs.jq}/bin/jq -e '. == {}' "${drv}/settings.json"
        ! test -d "${drv}/skills"
        ! test -d "${drv}/packages"
        ! test -f "${drv}/statusline.sh"
      '';
    };

  build-settings-merge =
    let
      plugin1 = { settings = { permissions.allow = [ "Bash" ]; foo = "from-plugin"; }; };
      plugin2 = { settings = { permissions.deny = [ "Write" ]; }; };
      drv = build {
        inherit pkgs;
        plugins = [ plugin1 plugin2 ];
        settings = { foo = "from-user"; bar = "user-only"; };
      };
    in
    mkTest "build-settings-merge" {
      inherit drv;
      script = ''
        ${pkgs.jq}/bin/jq -e '.foo == "from-user"' "${drv}/settings.json"
        ${pkgs.jq}/bin/jq -e '.permissions.allow[0] == "Bash"' "${drv}/settings.json"
        ${pkgs.jq}/bin/jq -e '.permissions.deny[0] == "Write"' "${drv}/settings.json"
        ${pkgs.jq}/bin/jq -e '.bar == "user-only"' "${drv}/settings.json"
      '';
    };

  build-plugin-skills =
    let
      skillDir = pkgs.runCommand "test-skill" {} ''
        mkdir -p $out
        echo "# Plugin skill content" > $out/SKILL.md
      '';
      plugin = { skills = [ skillDir ]; };
      drv = build { inherit pkgs; plugins = [ plugin ]; };
    in
    mkTest "build-plugin-skills" {
      inherit drv;
      script = ''
        test -d "${drv}/skills/test-skill"
        test -f "${drv}/skills/test-skill/SKILL.md"
        grep -q "Plugin skill content" "${drv}/skills/test-skill/SKILL.md"
      '';
    };

  build-inline-skills =
    let
      drv = build {
        inherit pkgs;
        skills = {
          my-skill = "Custom skill content here.";
        };
      };
    in
    mkTest "build-inline-skills" {
      inherit drv;
      script = ''
        test -d "${drv}/skills/my-skill"
        test -f "${drv}/skills/my-skill/SKILL.md"
        grep -q "Custom skill content" "${drv}/skills/my-skill/SKILL.md"
      '';
    };

  build-packages =
    let
      plugin = { package = pkgs.hello; };
      drv = build { inherit pkgs; plugins = [ plugin ]; };
    in
    mkTest "build-packages" {
      inherit drv;
      script = ''
        test -d "${drv}/packages"
        test -L "${drv}/packages/hello"
        test -d "$(readlink "${drv}/packages/hello")"
      '';
    };

  build-statusline =
    let
      drv = build {
        inherit pkgs;
        statusline = ''
          #!/bin/bash
          read -r input
          echo "custom status"
        '';
      };
    in
    mkTest "build-statusline" {
      inherit drv;
      script = ''
        test -f "${drv}/statusline.sh"
        test -x "${drv}/statusline.sh"
        grep -q "custom status" "${drv}/statusline.sh"
      '';
    };

  build-full =
    let
      skillDir = pkgs.runCommand "full-test-skill" {} ''
        mkdir -p $out
        echo "# Full test plugin skill" > $out/SKILL.md
      '';
      plugin = {
        package = pkgs.hello;
        settings = { permissions.allow = [ "Bash" ]; };
        skills = [ skillDir ];
      };
      drv = build {
        inherit pkgs;
        plugins = [ plugin ];
        settings = { permissions.deny = [ "Write" ]; };
        skills = { inline-skill = "Inline skill."; };
        statusline = "#!/bin/bash\necho status";
      };
    in
    mkTest "build-full" {
      inherit drv;
      script = ''
        ${pkgs.jq}/bin/jq -e '.permissions.allow[0] == "Bash"' "${drv}/settings.json"
        ${pkgs.jq}/bin/jq -e '.permissions.deny[0] == "Write"' "${drv}/settings.json"
        test -d "${drv}/skills/full-test-skill"
        test -f "${drv}/skills/inline-skill/SKILL.md"
        test -L "${drv}/packages/hello"
        test -x "${drv}/statusline.sh"
      '';
    };

  # mkClaudeConfig tests

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
